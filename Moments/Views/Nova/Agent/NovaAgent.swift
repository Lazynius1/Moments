import Foundation
import FirebaseAuth
import FirebaseAI
import UIKit

enum NovaAgentStatus: Equatable {
    case idle
    case thinking
    case callingTool(name: String)
    case streaming
    case awaitingConfirmation
}

@MainActor
final class NovaAgent: ObservableObject {
    @Published var inputText = ""
    @Published var selectedImage: UIImage?
    @Published var conversationHistory: [ChatMessage] = []
    @Published var isLoading = false
    @Published var showSuggestedOptions = true
    @Published var showCelebration = false
    @Published var userData: AppUser?
    @Published var userMemory: NovaMemory?
    @Published var userContext: NovaUserContext?
    @Published var hasMemoryLoaded = false
    @Published var conversationTitles: [ConversationTitle] = []
    @Published var agentStatus: NovaAgentStatus = .idle
    @Published var activeToolDisplayName: String?
    @Published var pendingAction: NovaPendingAction?

    /// Foto del último mensaje del usuario, disponible hasta que se publique o se cancele.
    private var stagedMomentImage: UIImage?

    private let ai = NovaAIService.shared
    private let memoryStore = NovaMemoryStore.shared
    private let contextStore = NovaContextStore.shared
    private let conversationStore = NovaConversationStore.shared
    private let firestoreService = FirestoreService()

    private var chatSession: Chat?
    private var toolExecutor: NovaToolExecutor?
    private var currentConversationId: String?
    private var sendTask: Task<Void, Never>?
    private var confirmationContinuation: CheckedContinuation<Bool, Never>?
    private var lastFinalizedFingerprint: String?
    private var internalHistorySummary: String?
    private var memoryObserver: NSObjectProtocol?

    private static let compactionThreshold = 24

    var currentUserDisplayName: String {
        userMemory?.preferredName ?? userData?.username ?? NSLocalizedString("nova.user", comment: "Default user name")
    }

    var welcomeSuggestions: [NovaWelcomeSuggestion] {
        NovaWelcomeSuggestion.defaults
    }

    // MARK: - Lifecycle

    func fetchUserData() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        installMemoryObserver(for: userId)

        firestoreService.fetchUserDataForNova(userId: userId) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let user):
                    self.userData = user
                    await self.loadMemoryAndContext(userId: userId)
                    await self.loadConversationTitles()
                    self.bootstrapChatSession()
                    self.isLoading = false
                case .failure:
                    self.isLoading = false
                }
            }
        }
    }

    func reloadMemoryFromStore() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        Task {
            memoryStore.invalidateCache(userId: userId)
            contextStore.invalidateCache(userId: userId)
            await loadMemoryAndContext(userId: userId)
            bootstrapChatSession()
        }
    }

    func checkPhotoLibraryPermission() {
        // Preserved for UI compatibility — no-op unless expanded later.
    }

    // MARK: - User confirmation

    func confirmPendingAction() {
        pendingAction = nil
        isLoading = true
        agentStatus = .callingTool(name: "confirmed")
        confirmationContinuation?.resume(returning: true)
        confirmationContinuation = nil
    }

    func cancelPendingAction() {
        if pendingAction?.kind == .createMoment {
            stagedMomentImage = nil
        }
        pendingAction = nil
        isLoading = true
        agentStatus = .streaming
        confirmationContinuation?.resume(returning: false)
        confirmationContinuation = nil
    }

    func handleConfirmationDismissed() {
        guard confirmationContinuation != nil else { return }
        cancelPendingAction()
    }

    private func waitForUserConfirmation(_ action: NovaPendingAction) async -> Bool {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        pendingAction = action
        agentStatus = .awaitingConfirmation
        activeToolDisplayName = nil
        isLoading = false

        await Task.yield()
        try? await Task.sleep(nanoseconds: 150_000_000)

        return await withCheckedContinuation { continuation in
            confirmationContinuation = continuation
        }
    }

    // MARK: - Conversations

    func loadConversationTitles() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        conversationTitles = await conversationStore.loadConversationTitles(for: userId)
    }

    func startNewConversation() {
        Task {
            await finalizeConversationIfNeeded()
            currentConversationId = nil
            lastFinalizedFingerprint = nil
            internalHistorySummary = nil
            stagedMomentImage = nil
            conversationHistory.removeAll()
            chatSession = nil

            conversationHistory.append(
                ChatMessage(
                    text: NSLocalizedString("nova.chat.encryptionNotice", comment: "Encryption notice"),
                    isUser: false,
                    isSystem: true
                )
            )

            bootstrapChatSession()
            showSuggestedOptions = true
            agentStatus = .idle
        }
    }

    func loadConversation(_ conversationId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        await finalizeConversationIfNeeded()
        lastFinalizedFingerprint = nil
        isLoading = true
        internalHistorySummary = nil
        stagedMomentImage = nil
        let messages = await conversationStore.loadConversation(conversationId, for: userId)
        currentConversationId = conversationId
        conversationHistory = messages
        rebuildChatFromHistory()
        isLoading = false
        showSuggestedOptions = false
    }

    func deleteConversation(_ conversationId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let deleted = await conversationStore.deleteConversation(conversationId, for: userId)
        if deleted {
            conversationTitles.removeAll { $0.id == conversationId }
            if currentConversationId == conversationId {
                startNewConversation()
            }
        }
    }

    // MARK: - Send

    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || selectedImage != nil else { return }
        guard userData != nil else { return }
        guard hasMemoryLoaded else { return }
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let userText = trimmed.isEmpty ? NSLocalizedString("nova.image.fallbackPrompt", comment: "Fallback when sending image only") : trimmed
        let image = selectedImage
        if let image {
            stagedMomentImage = image
        }

        inputText = ""
        selectedImage = nil

        conversationHistory.append(ChatMessage(text: userText, isUser: true, image: image))
        isLoading = true
        agentStatus = .thinking
        activeToolDisplayName = nil

        let botIndex = conversationHistory.count
        conversationHistory.append(ChatMessage(text: "", isUser: false))

        sendTask?.cancel()
        sendTask = Task {
            do {
                try await runTurn(userId: userId, userText: userText, image: image, botMessageIndex: botIndex)
            } catch {
                conversationHistory[botIndex].text = NSLocalizedString("nova.error.generic", comment: "Generic Nova error")
                LogConfig.log("Nova turn failed: \(error.localizedDescription)", category: "Nova")
            }

            isLoading = false
            agentStatus = .idle
            activeToolDisplayName = nil
            await saveCurrentConversation()
        }
    }

    private func runTurn(userId: String, userText: String, image: UIImage?, botMessageIndex: Int) async throws {
        if chatSession == nil {
            bootstrapChatSession()
        }
        guard let chatSession, let executor = toolExecutor else {
            throw NovaAgentError.missingUser
        }

        let mediaImage = image ?? stagedMomentImage
        executor.resetTurn()
        executor.attachedImageForTurn = mediaImage

        let parts = NovaAIService.userParts(text: userText, image: image)
        var step = 0
        var pending: [ModelContent] = [ModelContent(role: "user", parts: parts)]
        var seen = Set<String>()

        while step < NovaToolExecutor.maxStepsPerTurn {
            if step == 0, pending.count == 1, pending[0].role == "user" {
                // Firebase AI tool calls currently require preserving internal thought
                // signatures across the turn. The non-streaming chat path is more reliable here
                // than sendMessageStream when the model decides to call tools.
                let response = try await chatSession.sendMessage(pending)
                let calls = response.functionCalls

                if !calls.isEmpty {
                    conversationHistory[botMessageIndex].text = NSLocalizedString("nova.confirm.preparing", comment: "")
                    step += 1
                    if let finalText = try await handleToolCalls(
                        calls,
                        chat: chatSession,
                        seen: &seen,
                        botIndex: botMessageIndex
                    ) {
                        conversationHistory[botMessageIndex].text = finalText
                    }
                    return
                }

                if mediaImage != nil {
                    if try await handleMomentPublishFallback(
                        userText: userText,
                        image: mediaImage!,
                        chat: chatSession,
                        botIndex: botMessageIndex
                    ) {
                        return
                    }
                }

                conversationHistory[botMessageIndex].text = response.text ?? ""
                return
            }

            let response = try await chatSession.sendMessage(pending)
            pending = []

            if !response.functionCalls.isEmpty {
                step += 1
                if let finalText = try await handleToolCalls(
                    response.functionCalls,
                    chat: chatSession,
                    seen: &seen,
                    botIndex: botMessageIndex
                ) {
                    conversationHistory[botMessageIndex].text = finalText
                }
                return
            }

            conversationHistory[botMessageIndex].text = response.text ?? ""
            return
        }

        throw NovaAgentError.stepLimitReached
    }

    @discardableResult
    private func handleToolCalls(
        _ calls: [FunctionCallPart],
        chat: Chat,
        seen: inout Set<String>,
        botIndex: Int
    ) async throws -> String? {
        guard let executor = toolExecutor else { return nil }

        for call in calls {
            let signature = "\(call.name)-\(call.args)"
            if seen.contains(signature) { continue }
            seen.insert(signature)
        }

        let displayName = toolDisplayName(for: calls.first?.name ?? "tool")
        if pendingAction == nil {
            agentStatus = .callingTool(name: calls.first?.name ?? "tool")
            activeToolDisplayName = displayName
        }

        let responses = try await executor.execute(calls)

        if let momentSuccess = NovaToolExecutor.momentSuccessMessage(from: responses) {
            if let modelResponse = try? await chat.sendMessage([ModelContent(role: "function", parts: responses)]),
               let text = modelResponse.text, !text.isEmpty {
                activeToolDisplayName = nil
                agentStatus = .streaming
                return text
            }
            activeToolDisplayName = nil
            agentStatus = .streaming
            return momentSuccess
        }

        let modelResponse = try await chat.sendMessage([ModelContent(role: "function", parts: responses)])

        activeToolDisplayName = nil

        if !modelResponse.functionCalls.isEmpty {
            return try await handleToolCalls(
                modelResponse.functionCalls,
                chat: chat,
                seen: &seen,
                botIndex: botIndex
            )
        }

        agentStatus = .streaming
        return modelResponse.text
    }

    /// When the model replies with text but skips create_moment, nudge or show confirmation directly.
    private func handleMomentPublishFallback(
        userText: String,
        image: UIImage,
        chat: Chat,
        botIndex: Int
    ) async throws -> Bool {
        let nudge = try await chat.sendMessage([TextPart(NovaPromptCatalog.createMomentToolNudge)])
        if !nudge.functionCalls.isEmpty {
            conversationHistory[botIndex].text = NSLocalizedString("nova.confirm.preparing", comment: "")
            var seen = Set<String>()
            if let finalText = try await handleToolCalls(
                nudge.functionCalls,
                chat: chat,
                seen: &seen,
                botIndex: botIndex
            ) {
                conversationHistory[botIndex].text = finalText
            }
            return true
        }

        guard let draft = try await NovaMomentDraftParser.parse(userText: userText) else {
            return false
        }

        var args: JSONObject = [
            "content": .string(draft.content),
            "audience": .string(draft.audience)
        ]
        if let targetUsername = draft.targetUsername, !targetUsername.isEmpty {
            args["target_username"] = .string(targetUsername)
        }
        if let customListName = draft.customListName, !customListName.isEmpty {
            args["custom_list_name"] = .string(customListName)
        }

        guard let action = NovaPendingAction.from(
            toolName: "create_moment",
            args: args,
            previewImage: image
        ) else {
            return false
        }

        conversationHistory[botIndex].text = NSLocalizedString("nova.confirm.preparing", comment: "")

        let approved = await waitForUserConfirmation(action)
        guard approved else {
            conversationHistory[botIndex].text = NSLocalizedString("nova.confirm.cancelled", comment: "")
            return true
        }

        guard let executor = toolExecutor else { return false }
        isLoading = true
        let result = await executor.executeCreateMoment(args: args, image: image)
        isLoading = false

        if case .bool(true) = result["success"] {
            if case .string(let label) = result["audience_label"] {
                conversationHistory[botIndex].text = String(
                    format: NSLocalizedString("nova.moment.published", comment: ""),
                    label
                )
            } else {
                conversationHistory[botIndex].text = NSLocalizedString("nova.moment.publishedGeneric", comment: "")
            }
        } else if case .string(let code) = result["error"] {
            conversationHistory[botIndex].text = String(
                format: NSLocalizedString("nova.moment.failed", comment: ""),
                code
            )
        } else {
            conversationHistory[botIndex].text = NSLocalizedString("nova.moment.failedGeneric", comment: "")
        }

        return true
    }

    private func toolDisplayName(for tool: String) -> String {
        switch tool {
        case "get_activity_summary", "get_weekly_summary", "get_profile_visits", "get_story_chain_info":
            return NSLocalizedString("nova.agent.tool.activity", comment: "Checking activity")
        case "remember_fact", "update_user_preference":
            return NSLocalizedString("nova.agent.tool.memory", comment: "Checking memory")
        case "create_moment":
            return NSLocalizedString("nova.agent.tool.moment", comment: "Creating moment")
        case "list_audience_lists":
            return NSLocalizedString("nova.agent.tool.lists", comment: "Listing audience lists")
        case "get_connection_suggestions", "get_followers_summary", "get_following_summary", "get_mutual_connections", "get_shared_interest_users", "find_user_by_username", "send_follow_request":
            return NSLocalizedString("nova.agent.tool.connections", comment: "Finding connections")
        case "get_my_profile_snapshot", "get_recent_moments_summary", "get_recent_stories_summary", "get_profile_and_content_overview", "get_user_profile_snapshot":
            return NSLocalizedString("nova.agent.tool.activity", comment: "Checking activity")
        case "get_profile_privacy_settings", "update_profile_privacy_settings", "update_profile_bio", "update_profile_website", "update_active_hours", "update_notification_preferences":
            return NSLocalizedString("nova.agent.tool.generic", comment: "Working")
        case "get_moment_details", "get_echo_history_summary":
            return NSLocalizedString("nova.agent.tool.activity", comment: "Checking activity")
        default:
            return NSLocalizedString("nova.agent.tool.generic", comment: "Working")
        }
    }

    // MARK: - Session

    private func bootstrapChatSession(history: [ModelContent] = []) {
        guard let user = userData else { return }
        let instruction = NovaContextAssembler.systemInstruction(
            username: user.username,
            memory: userMemory,
            context: userContext,
            internalHistorySummary: internalHistorySummary
        )
        chatSession = ai.startChat(systemInstruction: instruction, history: history)
        if let userId = Auth.auth().currentUser?.uid {
            let executor = NovaToolExecutor(userId: userId)
            executor.onMemoryUpdated = { [weak self] memory in
                self?.userMemory = memory
                self?.rebuildChatFromHistory()
            }
            executor.onMomentCreated = { [weak self] in
                self?.stagedMomentImage = nil
                self?.showCelebration = true
            }
            executor.requestUserConfirmation = { [weak self] action in
                await self?.waitForUserConfirmation(action) ?? false
            }
            toolExecutor = executor
        }
    }

    private func rebuildChatFromHistory() {
        Task {
            await rebuildChatFromHistoryAsync()
        }
    }

    private func rebuildChatFromHistoryAsync() async {
        let meaningful = meaningfulConversationMessages()
        guard !meaningful.isEmpty else {
            internalHistorySummary = nil
            bootstrapChatSession()
            return
        }

        let payload = await buildHistoryPayload(from: meaningful)
        internalHistorySummary = payload.summary
        bootstrapChatSession(history: payload.history)
    }

    private func meaningfulConversationMessages() -> [ChatMessage] {
        conversationHistory.filter {
            !$0.isSystem && (!$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.image != nil)
        }
    }

    private func buildHistoryPayload(from messages: [ChatMessage]) async -> (history: [ModelContent], summary: String?) {
        guard messages.count > Self.compactionThreshold else {
            return (modelHistory(from: messages), nil)
        }

        let older = Array(messages.dropLast(12))
        let recent = Array(messages.suffix(12))
        let transcript = older
            .map { "\($0.isUser ? "User" : "Nova"): \($0.text.prefix(1200))" }
            .joined(separator: "\n")

        do {
            let summary = try await ai.compactHistory(transcript)
            return (modelHistory(from: recent), summary)
        } catch {
            LogConfig.log("Nova history compaction failed: \(error.localizedDescription)", category: "Nova")
            return (modelHistory(from: Array(messages.suffix(18))), nil)
        }
    }

    private func modelHistory(from messages: [ChatMessage]) -> [ModelContent] {
        messages.compactMap { message in
            if message.isUser {
                return ModelContent(role: "user", parts: NovaAIService.userParts(text: message.text, image: message.image))
            }

            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return ModelContent(role: "model", parts: [TextPart(trimmed)])
        }
    }

    private func loadMemoryAndContext(userId: String) async {
        userMemory = await memoryStore.loadMemory(userId: userId)
        userContext = await contextStore.loadContext(userId: userId)
        hasMemoryLoaded = true
    }

    private func saveCurrentConversation() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let messages = conversationHistory
        guard messages.contains(where: { $0.isUser }) else { return }

        if let conversationId = currentConversationId {
            _ = await conversationStore.updateConversation(conversationId, for: userId, messages: messages)
        } else if let newId = await conversationStore.saveConversation(for: userId, messages: messages) {
            currentConversationId = newId
        }
        await loadConversationTitles()
    }

    private func conversationFingerprint() -> String? {
        let meaningful = conversationHistory.filter { !$0.isSystem && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard meaningful.contains(where: \.isUser) else { return nil }
        return "\(currentConversationId ?? "draft")-\(meaningful.count)-\(meaningful.last?.id.uuidString ?? "")"
    }

    func finalizeOnExit() async {
        await finalizeConversationIfNeeded()
    }

    private func finalizeConversationIfNeeded() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        guard let fingerprint = conversationFingerprint() else { return }
        guard fingerprint != lastFinalizedFingerprint else { return }

        lastFinalizedFingerprint = fingerprint
        let snapshot = conversationHistory
        let conversationId = currentConversationId

        NovaMemoryEngine.shared.scheduleConversationFinalize(
            userId: userId,
            conversationId: conversationId,
            messages: snapshot
        )
    }

    private func installMemoryObserver(for userId: String) {
        guard memoryObserver == nil else { return }
        memoryObserver = NotificationCenter.default.addObserver(
            forName: .novaMemoryDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let updatedUserId = notification.object as? String,
                  updatedUserId == userId else {
                return
            }

            Task { @MainActor in
                self.memoryStore.invalidateCache(userId: userId)
                self.contextStore.invalidateCache(userId: userId)
                await self.loadMemoryAndContext(userId: userId)
                await self.rebuildChatFromHistoryAsync()
            }
        }
    }

    deinit {
        if let memoryObserver {
            NotificationCenter.default.removeObserver(memoryObserver)
        }
    }
}

struct NovaWelcomeSuggestion: Identifiable {
    let id = UUID()
    let titleKey: String
    let promptKey: String
    let icon: String

    var title: String { NSLocalizedString(titleKey, comment: "") }
    var prompt: String { NSLocalizedString(promptKey, comment: "") }

    static let defaults: [NovaWelcomeSuggestion] = [
        NovaWelcomeSuggestion(titleKey: "nova.suggestions.writeHelp.title", promptKey: "nova.suggestions.writeHelp.prompt", icon: "pencil.line"),
        NovaWelcomeSuggestion(titleKey: "nova.suggestions.studyTips.title", promptKey: "nova.suggestions.studyTips.prompt", icon: "book"),
        NovaWelcomeSuggestion(titleKey: "nova.suggestions.interests.title", promptKey: "nova.suggestions.interests.prompt", icon: "heart"),
        NovaWelcomeSuggestion(titleKey: "nova.suggestions.advice.title", promptKey: "nova.suggestions.advice.prompt", icon: "lightbulb")
    ]
}
