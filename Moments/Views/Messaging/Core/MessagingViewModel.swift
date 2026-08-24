import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class MessagingViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var archivedConversations: [Conversation] = []
    @Published var suggestedUsers: [AppUser] = []
    @Published var hasUnreadMessages: Bool = false
    @Published var selectedConversation: Conversation?
    @Published var errorMessage: String?
    @Published var requiresMessageRequest: Bool = false
    @Published var presentationRoute: MessagingPresentationRoute?

    @Published var filteredConversations: [Conversation] = []
    @Published var searchedUsers: [AppUser] = []
    @Published var searchedMessages: [GlobalMessageSearchResult] = []
    @Published var isSearchingContent: Bool = false

    private let chatService = ChatService.shared
    private let messageRequestService = MessageRequestService()
    private var cancellables = Set<AnyCancellable>()
    private var isFirstFetch = true
    private var searchWorkItem: DispatchWorkItem?
    private var userSearchWorkItem: DispatchWorkItem?
    private var activeSearchQuery: String = ""
    private var activeUserSearchQuery: String = ""
    private var locallyReadConversationIds: Set<String> = []
    private var conversationReadObserver: NSObjectProtocol?

    init() {
        conversationReadObserver = NotificationCenter.default.addObserver(
            forName: .conversationMarkedReadLocally,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let conversationId = notification.userInfo?["conversationId"] as? String else { return }
            self?.markConversationReadOptimistically(conversationId)
        }
    }

    private func markConversationReadOptimistically(_ conversationId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        locallyReadConversationIds.insert(conversationId)

        func markRead(_ list: inout [Conversation]) {
            guard let index = list.firstIndex(where: { $0.id == conversationId }) else { return }
            list[index].readStatus[currentUserId] = true
        }

        markRead(&conversations)
        markRead(&archivedConversations)
        hasUnreadMessages = (conversations + archivedConversations).contains { !($0.readStatus[currentUserId] ?? true) }
    }

    private func reconcilingOptimisticReadState(_ list: [Conversation], currentUserId: String) -> [Conversation] {
        guard !locallyReadConversationIds.isEmpty else { return list }
        return list.map { conversation in
            guard let id = conversation.id, locallyReadConversationIds.contains(id) else { return conversation }
            if conversation.readStatus[currentUserId] == true {
                locallyReadConversationIds.remove(id)
                return conversation
            }
            var patched = conversation
            patched.readStatus[currentUserId] = true
            return patched
        }
    }

    private func updatingConversation(
        _ conversation: Conversation,
        isPinned: Bool? = nil,
        isMuted: Bool? = nil,
        isArchived: Bool? = nil
    ) -> Conversation {
        let currentUserId = Auth.auth().currentUser?.uid
        let resolvedPinned = isPinned ?? conversation.isPinned(for: currentUserId)
        let resolvedMuted = isMuted ?? conversation.isMuted(for: currentUserId)
        var archivedIds = conversation.archivedByUserIds ?? []
        if let isArchived, let currentUserId, !currentUserId.isEmpty {
            if isArchived {
                if !archivedIds.contains(currentUserId) {
                    archivedIds.append(currentUserId)
                }
            } else {
                archivedIds.removeAll { $0 == currentUserId }
            }
        }
        var updated = Conversation(
            id: conversation.id,
            participants: conversation.participants,
            lastMessage: conversation.lastMessage,
            timestamp: conversation.timestamp,
            readStatus: conversation.readStatus,
            otherParticipantId: conversation.otherParticipantId,
            otherParticipantUsername: conversation.otherParticipantUsername,
            otherParticipantProfileImagePath: conversation.otherParticipantProfileImagePath,
            isPinned: resolvedPinned,
            pinnedByUserIds: conversation.pinnedByUserIds,
            pinnedBy: conversation.pinnedBy,
            isMuted: resolvedMuted,
            mutedByUserIds: conversation.mutedByUserIds,
            mutedBy: conversation.mutedBy,
            archivedByUserIds: archivedIds.isEmpty ? nil : archivedIds,
            encryptionVersion: conversation.encryptionVersion,
            conversationKeyVersion: conversation.conversationKeyVersion,
            wrappedKeys: conversation.wrappedKeys
        )
        updated.readReceiptPreferences = conversation.readReceiptPreferences
        updated.forwardingPreferences = conversation.forwardingPreferences
        updated.buzzPreferences = conversation.buzzPreferences
        updated.lastDeletedAt = conversation.lastDeletedAt
        updated.lastReadAt = conversation.lastReadAt
        updated.lastMessageSenderId = conversation.lastMessageSenderId
        updated.lastMessageSeenAt = conversation.lastMessageSeenAt
        updated.lastMessageReaction = conversation.lastMessageReaction
        updated.vanishModeActive = conversation.vanishModeActive
        updated.vanishModeEnabledBy = conversation.vanishModeEnabledBy
        updated.vanishModeEnabledAt = conversation.vanishModeEnabledAt
        updated.vanishMessageTimer = conversation.vanishMessageTimer
        return updated
    }

    private func sortConversationsForInbox(_ conversations: [Conversation]) -> [Conversation] {
        let currentUserId = Auth.auth().currentUser?.uid
        return conversations.sorted { lhs, rhs in
            let lhsPinned = lhs.isPinned(for: currentUserId)
            let rhsPinned = rhs.isPinned(for: currentUserId)

            if lhsPinned != rhsPinned {
                return lhsPinned && !rhsPinned
            }

            let lhsHasDraft = hasDraft(lhs, userId: currentUserId)
            let rhsHasDraft = hasDraft(rhs, userId: currentUserId)

            if lhsHasDraft != rhsHasDraft {
                return lhsHasDraft && !rhsHasDraft
            }

            return lhs.timestamp > rhs.timestamp
        }
    }

    private func hasDraft(_ conversation: Conversation, userId: String?) -> Bool {
        guard let conversationId = conversation.id else { return false }
        return !ChatDraftStore.shared.draft(for: conversationId, userId: userId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    func refreshDraftOrdering() {
        conversations = sortConversationsForInbox(conversations)
        archivedConversations = sortConversationsForInbox(archivedConversations)
        filteredConversations = sortConversationsForInbox(filteredConversations)
    }

    func applyLocalConversationState(
        conversationId: String,
        isPinned: Bool? = nil,
        isMuted: Bool? = nil,
        isArchived: Bool? = nil
    ) {
        let updateList: ([Conversation]) -> [Conversation] = { list in
            self.sortConversationsForInbox(list.map { conversation in
                conversation.id == conversationId
                    ? self.updatingConversation(conversation, isPinned: isPinned, isMuted: isMuted, isArchived: isArchived)
                    : conversation
            })
        }

        if let isArchived {
            if isArchived {
                if let conversation = conversations.first(where: { $0.id == conversationId }) {
                    conversations.removeAll { $0.id == conversationId }
                    let updated = updatingConversation(conversation, isPinned: isPinned, isMuted: isMuted, isArchived: true)
                    archivedConversations = sortConversationsForInbox([updated] + archivedConversations.filter { $0.id != conversationId })
                }
            } else {
                if let conversation = archivedConversations.first(where: { $0.id == conversationId }) {
                    archivedConversations.removeAll { $0.id == conversationId }
                    let updated = updatingConversation(conversation, isPinned: isPinned, isMuted: isMuted, isArchived: false)
                    conversations = sortConversationsForInbox([updated] + conversations.filter { $0.id != conversationId })
                }
            }
        } else {
            conversations = updateList(conversations)
            archivedConversations = updateList(archivedConversations)
        }

        filteredConversations = updateList(filteredConversations)
        LocalPersistenceService.shared.saveConversations(conversations + archivedConversations, sync: true)
    }

    func archivedUnreadCount(for userId: String) -> Int {
        archivedConversations.filter { !($0.readStatus[userId] ?? true) }.count
    }

    deinit {
        searchWorkItem?.cancel()
        userSearchWorkItem?.cancel()
        if let conversationReadObserver {
            NotificationCenter.default.removeObserver(conversationReadObserver)
        }
        if let userId = Auth.auth().currentUser?.uid {
            Task { @MainActor in
                ChatService.shared.removeConversationsListener(for: userId)
            }
        }
    }

    func fetchConversations(for userId: String) {
        let cachedConversations = sortConversationsForInbox(LocalPersistenceService.shared.loadConversations())
        if !cachedConversations.isEmpty {
            DispatchQueue.main.async {
                let active = self.reconcilingOptimisticReadState(
                    cachedConversations.filter { !$0.isArchived(for: userId) },
                    currentUserId: userId
                )
                let archived = self.reconcilingOptimisticReadState(
                    cachedConversations.filter { $0.isArchived(for: userId) },
                    currentUserId: userId
                )
                self.conversations = active
                self.archivedConversations = archived
                self.hasUnreadMessages = (active + archived).contains { !($0.readStatus[userId] ?? true) }
            }
        }

        chatService.fetchConversations(for: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let conversations):
                    let filtered = conversations.filter { $0.id != nil && !$0.id!.isEmpty }
                    let active = self.reconcilingOptimisticReadState(
                        self.sortConversationsForInbox(filtered.filter { !$0.isArchived(for: userId) }),
                        currentUserId: userId
                    )
                    let archived = self.reconcilingOptimisticReadState(
                        self.sortConversationsForInbox(filtered.filter { $0.isArchived(for: userId) }),
                        currentUserId: userId
                    )
                    self.conversations = active
                    self.archivedConversations = archived
                    self.hasUnreadMessages = (active + archived).contains { !($0.readStatus[userId] ?? true) }
                    self.errorMessage = nil

                    LocalPersistenceService.shared.saveConversations(active + archived, sync: self.isFirstFetch)
                    self.isFirstFetch = false

                    if LocalFirstMessagingSettings.isEnabled {
                        MessageCatchUpService.shared.syncRecent(conversations: active + archived)
                    }

                case .failure(let error):
                    if self.conversations.isEmpty {
                        self.errorMessage = String(
                            format: NSLocalizedString("messaging.error.loadConversations", comment: "Failed to load conversations"),
                            error.localizedDescription
                        )
                    }
                }
            }
        }
    }

    func refreshUserData(userId: String) {
        UserCacheService.shared.refreshUser(userId: userId) { [weak self] user in
            DispatchQueue.main.async {
                guard let self else { return }
                let username = user?.username ?? NSLocalizedString("messaging.user.default", comment: "Default user name")
                let imagePath = user?.profileImagePath ?? ""
                self.applyRefreshedParticipant(userId: userId, username: username, imagePath: imagePath, to: &self.conversations)
                self.applyRefreshedParticipant(userId: userId, username: username, imagePath: imagePath, to: &self.archivedConversations)
                self.applyRefreshedParticipant(userId: userId, username: username, imagePath: imagePath, to: &self.filteredConversations)
            }
        }
    }

    /// Muta solo los datos de perfil del participante: el resto de la conversación
    /// no se reconstruye, así ningún campo del modelo puede perderse por el camino.
    private func applyRefreshedParticipant(
        userId: String,
        username: String,
        imagePath: String,
        to list: inout [Conversation]
    ) {
        for index in list.indices where list[index].otherParticipantId == userId {
            list[index].otherParticipantUsername = username
            list[index].otherParticipantProfileImagePath = imagePath
        }
    }

    func refreshVisibleUsers() {
        let visibleUsers = Array(conversations.prefix(10))
        for conversation in visibleUsers {
            refreshUserData(userId: conversation.otherParticipantId)
        }
    }

    func searchConversationsAndUsers(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        activeSearchQuery = trimmedQuery
        searchWorkItem?.cancel()

        guard !trimmedQuery.isEmpty else {
            clearSearch()
            return
        }

        isSearchingContent = true

        filteredConversations = (conversations + archivedConversations).filter { conversation in
            let username = conversation.otherParticipantUsername?.lowercased() ?? ""
            let lastMessage = conversation.lastMessage?.lowercased() ?? ""
            let draft = conversation.id.map { ChatDraftStore.shared.draft(for: $0).lowercased() } ?? ""
            let searchQuery = trimmedQuery.lowercased()

            return username.contains(searchQuery) || lastMessage.contains(searchQuery) || draft.contains(searchQuery)
        }

        searchedMessages = globalMessageResults(for: trimmedQuery)

        let existingUserIds = Set((conversations + archivedConversations).compactMap { $0.otherParticipantId })
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            FirestoreService().searchUsers(query: trimmedQuery) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    guard self.activeSearchQuery == trimmedQuery else { return }

                    self.isSearchingContent = false

                    switch result {
                    case .success(let users):
                        self.searchedUsers = users.filter { user in
                            let notCurrentUser = user.id != Auth.auth().currentUser?.uid
                            let noExistingConversation = !existingUserIds.contains(user.id)
                            return notCurrentUser && noExistingConversation
                        }
                    case .failure:
                        self.searchedUsers = []
                    }
                }
            }
        }

        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    func clearSearch() {
        searchWorkItem?.cancel()
        activeSearchQuery = ""
        filteredConversations = []
        searchedUsers = []
        searchedMessages = []
        isSearchingContent = false
    }

    /// Búsqueda global sobre el cache local (100% local, como el estándar de mensajería:
    /// con E2E el escaneo remoto significaría descargar y descifrar todo el historial).
    private func globalMessageResults(for query: String) -> [GlobalMessageSearchResult] {
        let matches = LocalPersistenceService.shared.searchMessagesGlobally(query: query)
        guard !matches.isEmpty else { return [] }

        let conversationsById = Dictionary(
            uniqueKeysWithValues: (conversations + archivedConversations).compactMap { conversation in
                conversation.id.map { ($0, conversation) }
            }
        )

        return matches.compactMap { message in
            guard let conversation = conversationsById[message.conversationId] else { return nil }
            return GlobalMessageSearchResult(message: message, conversation: conversation)
        }
    }

    func createOrFindConversation(with user: AppUser, from userId: String, completion: @escaping (Conversation?) -> Void) {
        startConversation(with: user, from: userId, completion: completion)
    }

    func searchUsers(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        activeUserSearchQuery = trimmedQuery
        userSearchWorkItem?.cancel()

        if trimmedQuery.isEmpty {
            loadNewConversationSuggestions()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            FirestoreService().searchUsers(query: trimmedQuery) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    guard self.activeUserSearchQuery == trimmedQuery else { return }

                    switch result {
                    case .success(let users):
                        self.suggestedUsers = users
                    case .failure(let error):
                        self.errorMessage = String(
                            format: NSLocalizedString("messaging.error.searchUsers", comment: "Failed to search users"),
                            error.localizedDescription
                        )
                    }
                }
            }
        }

        userSearchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func loadNewConversationSuggestions() {
        let recentPartnerIds = conversations.map(\.otherParticipantId)

        FirestoreService().fetchNewConversationSuggestions(recentPartnerIds: recentPartnerIds) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.activeUserSearchQuery.isEmpty else { return }

                switch result {
                case .success(let users):
                    self.suggestedUsers = users
                    self.errorMessage = nil
                case .failure(let error):
                    self.errorMessage = String(
                        format: NSLocalizedString("messaging.error.searchUsers", comment: "Failed to search users"),
                        error.localizedDescription
                    )
                }
            }
        }
    }

    func startConversation(
        with user: AppUser,
        from userId: String,
        initialMessage: String? = nil,
        completion: @escaping (Conversation?) -> Void
    ) {
        let trimmed = initialMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Task { @MainActor [weak self] in
            guard let self else { completion(nil); return }
            do {
                let route = try await self.messageRequestService.resolveRoute(
                    to: user.id,
                    reserve: !trimmed.isEmpty
                )
                switch route {
                case .conversation(let conversationId):
                    if !trimmed.isEmpty {
                        try await self.sendText(trimmed, conversationId: conversationId, senderId: userId)
                    }
                    let conversation = self.directConversation(
                        id: conversationId,
                        user: user,
                        currentUserId: userId,
                        lastMessage: trimmed.isEmpty ? "" : MessageType.text.conversationPreview
                    )
                    self.selectedConversation = conversation
                    self.presentationRoute = .conversation(conversation)
                    self.requiresMessageRequest = false
                    self.errorMessage = nil
                    completion(conversation)

                case .conversationDraft(let threadId):
                    if trimmed.isEmpty {
                        let conversation = self.directConversation(
                            id: nil,
                            user: user,
                            currentUserId: userId,
                            lastMessage: ""
                        )
                        self.selectedConversation = conversation
                        self.presentationRoute = .conversation(conversation)
                        self.requiresMessageRequest = false
                        self.errorMessage = nil
                        completion(conversation)
                    } else {
                        let conversationId = try await self.messageRequestService.activateConversationDraft(
                            to: user.id,
                            threadId: threadId
                        )
                        try await self.sendText(trimmed, conversationId: conversationId, senderId: userId)
                        let conversation = self.directConversation(
                            id: conversationId,
                            user: user,
                            currentUserId: userId,
                            lastMessage: MessageType.text.conversationPreview
                        )
                        self.selectedConversation = conversation
                        self.presentationRoute = .conversation(conversation)
                        self.requiresMessageRequest = false
                        self.errorMessage = nil
                        completion(conversation)
                    }

                case let .outgoingRequest(threadId, count, _, _):
                    var request: MessageRequest?
                    var resultingCount = count
                    if !trimmed.isEmpty {
                        let sent = try await self.messageRequestService.appendRequestMessage(to: user.id, text: trimmed)
                        resultingCount = sent.messageCount
                    }
                    if resultingCount > 0 {
                        request = try? await self.messageRequestService.loadOutgoingRequest(
                            threadId: threadId,
                            receiverId: user.id
                        )
                    }
                    let context = PendingChatContext(
                        outgoingTo: user,
                        status: resultingCount > 0 ? .outgoingRequestSent : .outgoingRequestDraft,
                        initialText: trimmed.isEmpty ? request?.message : trimmed,
                        request: request
                    )
                    self.presentationRoute = .pendingChat(context)
                    self.requiresMessageRequest = false
                    self.errorMessage = nil
                    completion(nil)

                case let .incomingRequest(threadId, _):
                    if trimmed.isEmpty {
                        let request = try await self.messageRequestService.loadIncomingRequest(threadId: threadId)
                        let context = await PendingChatContextFactory.incoming(request: request, viewerId: userId)
                        self.presentationRoute = .pendingChat(context)
                        self.requiresMessageRequest = false
                        self.errorMessage = nil
                        completion(nil)
                    } else {
                        let accepted = try await self.messageRequestService.acceptIncomingThread(threadId: threadId)
                        try await self.sendText(trimmed, conversationId: accepted.conversationId, senderId: userId)
                        let conversation = self.directConversation(
                            id: accepted.conversationId,
                            user: user,
                            currentUserId: userId,
                            lastMessage: MessageType.text.conversationPreview
                        )
                        self.selectedConversation = conversation
                        self.presentationRoute = .conversation(conversation)
                        self.requiresMessageRequest = false
                        self.errorMessage = nil
                        completion(conversation)
                    }
                }
            } catch {
                self.errorMessage = error.localizedDescription
                self.requiresMessageRequest = false
                completion(nil)
            }
        }
    }

    private func directConversation(
        id: String?,
        user: AppUser,
        currentUserId: String,
        lastMessage: String
    ) -> Conversation {
        Conversation(
            id: id,
            participants: [currentUserId, user.id].sorted(),
            lastMessage: lastMessage,
            timestamp: Date(),
            readStatus: [currentUserId: true, user.id: false],
            otherParticipantId: user.id,
            otherParticipantUsername: user.username,
            otherParticipantProfileImagePath: user.profileImagePath
        )
    }

    private func sendText(_ text: String, conversationId: String, senderId: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            chatService.sendTextMessage(
                conversationId: conversationId,
                senderId: senderId,
                content: text
            ) { result in
                continuation.resume(with: result.map { _ in () })
            }
        }
    }

    func deleteConversation(_ conversation: Conversation) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        guard let currentUserId = Auth.auth().currentUser?.uid, !currentUserId.isEmpty else {
            return
        }

        conversations.removeAll { $0.id == conversationId }
        archivedConversations.removeAll { $0.id == conversationId }
        filteredConversations.removeAll { $0.id == conversationId }
        hasUnreadMessages = (conversations + archivedConversations).contains { !($0.readStatus[currentUserId] ?? true) }
        ChatSessionEngine.shared.invalidateSession(conversationId: conversationId)
        if let conversationId = conversation.id {
            ChatScrollStateStore.clear(for: conversationId)
        }
        LocalPersistenceService.shared.saveConversations(conversations + archivedConversations, sync: true)
        LocalPersistenceService.shared.deleteConversationCache(conversationId: conversationId)

        chatService.deleteConversationsBetweenUsers(
            user1Id: currentUserId,
            user2Id: conversation.otherParticipantId
        ) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = String(
                        format: NSLocalizedString("messaging.error.deleteConversation", comment: "Failed to delete conversation"),
                        error.localizedDescription
                    )
                }
            } else {
                DispatchQueue.main.async {
                    self?.conversations.removeAll { $0.id == conversationId }
                    self?.archivedConversations.removeAll { $0.id == conversationId }
                    self?.hasUnreadMessages = (self?.conversations ?? []).contains { !($0.readStatus[Auth.auth().currentUser?.uid ?? ""] ?? true) }
                        || (self?.archivedConversations ?? []).contains { !($0.readStatus[Auth.auth().currentUser?.uid ?? ""] ?? true) }
                }
            }
        }
    }

    func markConversationAsUnread(_ conversation: Conversation) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }

        Firestore.firestore()
            .collection("conversations")
            .document(conversationId)
            .updateData(["readStatus.\(Auth.auth().currentUser?.uid ?? "")": false]) { [weak self] error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.errorMessage = String(
                            format: NSLocalizedString("messaging.error.markUnread", comment: "Failed to mark conversation unread"),
                            error.localizedDescription
                        )
                    }
                } else {
                    DispatchQueue.main.async {
                        if let index = self?.conversations.firstIndex(where: { $0.id == conversationId }) {
                            var updatedConversation = conversation
                            var readStatus = conversation.readStatus
                            readStatus[Auth.auth().currentUser?.uid ?? ""] = false
                            updatedConversation.readStatus = readStatus
                            self?.conversations[index] = updatedConversation
                            self?.hasUnreadMessages = true
                        } else if let index = self?.archivedConversations.firstIndex(where: { $0.id == conversationId }) {
                            var updatedConversation = conversation
                            var readStatus = conversation.readStatus
                            readStatus[Auth.auth().currentUser?.uid ?? ""] = false
                            updatedConversation.readStatus = readStatus
                            self?.archivedConversations[index] = updatedConversation
                            self?.hasUnreadMessages = true
                        }
                    }
                }
            }
    }

    func stopListening() {
        if let userId = Auth.auth().currentUser?.uid {
            chatService.removeConversationsListener(for: userId)
        }
    }

    func updateVanishMode(conversationId: String, active: Bool) {
        func patch(_ list: inout [Conversation]) {
            for index in list.indices where list[index].id == conversationId {
                list[index].vanishModeActive = active
            }
        }
        patch(&conversations)
        patch(&archivedConversations)
        patch(&filteredConversations)
        LocalPersistenceService.shared.saveConversations(conversations + archivedConversations, sync: false)
    }

    func archiveConversation(_ conversation: Conversation) {
        guard let conversationId = conversation.id,
              let currentUserId = Auth.auth().currentUser?.uid else { return }
        applyLocalConversationState(conversationId: conversationId, isArchived: true)
        chatService.archiveConversation(conversationId, for: currentUserId) { [weak self] error in
            if let error {
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func unarchiveConversation(_ conversation: Conversation) {
        guard let conversationId = conversation.id,
              let currentUserId = Auth.auth().currentUser?.uid else { return }
        applyLocalConversationState(conversationId: conversationId, isArchived: false)
        chatService.unarchiveConversation(conversationId, for: currentUserId) { [weak self] error in
            if let error {
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Resultado de búsqueda global de mensajes
struct GlobalMessageSearchResult: Identifiable {
    let message: EnhancedMessage
    let conversation: Conversation

    var id: String { message.id }
}
