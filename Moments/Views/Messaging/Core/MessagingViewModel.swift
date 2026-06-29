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

    @Published var filteredConversations: [Conversation] = []
    @Published var searchedUsers: [AppUser] = []
    @Published var isSearchingContent: Bool = false

    private let chatService = ChatService.shared
    private var cancellables = Set<AnyCancellable>()
    private var isFirstFetch = true
    private var searchWorkItem: DispatchWorkItem?
    private var userSearchWorkItem: DispatchWorkItem?
    private var activeSearchQuery: String = ""
    private var activeUserSearchQuery: String = ""

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
                let active = cachedConversations.filter { !$0.isArchived(for: userId) }
                let archived = cachedConversations.filter { $0.isArchived(for: userId) }
                self.conversations = active
                self.archivedConversations = archived
                self.hasUnreadMessages = cachedConversations.contains { !($0.readStatus[userId] ?? true) }
            }
        }

        chatService.fetchConversations(for: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let conversations):
                    let filtered = conversations.filter { $0.id != nil && !$0.id!.isEmpty }
                    let active = self.sortConversationsForInbox(filtered.filter { !$0.isArchived(for: userId) })
                    let archived = self.sortConversationsForInbox(filtered.filter { $0.isArchived(for: userId) })
                    self.conversations = active
                    self.archivedConversations = archived
                    self.hasUnreadMessages = filtered.contains { !($0.readStatus[userId] ?? true) }
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
                    print("⚠️ MessagingViewModel: Fallo fetch de Firestore: \(error.localizedDescription)")
                }
            }
        }
    }

    func refreshUserData(userId: String) {
        UserCacheService.shared.refreshUser(userId: userId) { [weak self] user in
            DispatchQueue.main.async {
                guard let self = self else { return }

                for i in 0..<self.conversations.count {
                    if self.conversations[i].otherParticipantId == userId {
                        let existing = self.conversations[i]
                        self.conversations[i] = self.updatingConversation(
                            Conversation(
                                id: existing.id,
                                participants: existing.participants,
                                lastMessage: existing.lastMessage,
                                timestamp: existing.timestamp,
                                readStatus: existing.readStatus,
                                otherParticipantId: userId,
                                otherParticipantUsername: user?.username ?? NSLocalizedString("messaging.user.default", comment: "Default user name"),
                                otherParticipantProfileImagePath: user?.profileImagePath ?? "",
                                isPinned: existing.isPinned,
                                pinnedByUserIds: existing.pinnedByUserIds,
                                pinnedBy: existing.pinnedBy,
                                isMuted: existing.isMuted,
                                mutedByUserIds: existing.mutedByUserIds,
                                mutedBy: existing.mutedBy,
                                archivedByUserIds: existing.archivedByUserIds,
                                encryptionVersion: existing.encryptionVersion,
                                conversationKeyVersion: existing.conversationKeyVersion,
                                wrappedKeys: existing.wrappedKeys
                            ),
                            isPinned: existing.isPinned,
                            isMuted: existing.isMuted
                        )
                        self.conversations[i].readReceiptPreferences = existing.readReceiptPreferences
                        self.conversations[i].forwardingPreferences = existing.forwardingPreferences
                        self.conversations[i].buzzPreferences = existing.buzzPreferences
                        self.conversations[i].lastDeletedAt = existing.lastDeletedAt
                        self.conversations[i].vanishModeActive = existing.vanishModeActive
                        self.conversations[i].vanishModeEnabledBy = existing.vanishModeEnabledBy
                        self.conversations[i].vanishModeEnabledAt = existing.vanishModeEnabledAt
                        self.conversations[i].vanishMessageTimer = existing.vanishMessageTimer
                    }
                }

                for i in 0..<self.filteredConversations.count {
                    if self.filteredConversations[i].otherParticipantId == userId {
                        let existing = self.filteredConversations[i]
                        self.filteredConversations[i] = self.updatingConversation(
                            Conversation(
                                id: existing.id,
                                participants: existing.participants,
                                lastMessage: existing.lastMessage,
                                timestamp: existing.timestamp,
                                readStatus: existing.readStatus,
                                otherParticipantId: userId,
                                otherParticipantUsername: user?.username ?? NSLocalizedString("messaging.user.default", comment: "Default user name"),
                                otherParticipantProfileImagePath: user?.profileImagePath ?? "",
                                isPinned: existing.isPinned,
                                pinnedByUserIds: existing.pinnedByUserIds,
                                pinnedBy: existing.pinnedBy,
                                isMuted: existing.isMuted,
                                mutedByUserIds: existing.mutedByUserIds,
                                mutedBy: existing.mutedBy,
                                archivedByUserIds: existing.archivedByUserIds,
                                encryptionVersion: existing.encryptionVersion,
                                conversationKeyVersion: existing.conversationKeyVersion,
                                wrappedKeys: existing.wrappedKeys
                            ),
                            isPinned: existing.isPinned,
                            isMuted: existing.isMuted
                        )
                        self.filteredConversations[i].readReceiptPreferences = existing.readReceiptPreferences
                        self.filteredConversations[i].forwardingPreferences = existing.forwardingPreferences
                        self.filteredConversations[i].buzzPreferences = existing.buzzPreferences
                        self.filteredConversations[i].lastDeletedAt = existing.lastDeletedAt
                        self.filteredConversations[i].vanishModeActive = existing.vanishModeActive
                        self.filteredConversations[i].vanishModeEnabledBy = existing.vanishModeEnabledBy
                        self.filteredConversations[i].vanishModeEnabledAt = existing.vanishModeEnabledAt
                        self.filteredConversations[i].vanishMessageTimer = existing.vanishMessageTimer
                    }
                }
            }
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
        isSearchingContent = false
    }

    func createOrFindConversation(with user: AppUser, from userId: String, completion: @escaping (Conversation?) -> Void) {
        if let existingConversation = (conversations + archivedConversations).first(where: { $0.otherParticipantId == user.id }) {
            completion(existingConversation)
            return
        }

        chatService.canSendMessage(from: userId, to: user.id) { [weak self] result in
            switch result {
            case .success(let canSend):
                if !canSend {
                    DispatchQueue.main.async {
                        self?.errorMessage = NSLocalizedString("messaging.error.cannotStart", comment: "Cannot start conversation")
                    }
                    completion(nil)
                    return
                }

                self?.chatService.createBidirectionalConversation(user1Id: userId, user2Id: user.id) { result in
                    switch result {
                    case .success:
                        DispatchQueue.main.async {
                            self?.fetchConversations(for: userId)
                        }
                        completion(nil)

                    case .failure(let error):
                        DispatchQueue.main.async {
                            self?.errorMessage = String(
                                format: NSLocalizedString("messaging.error.createConversation", comment: "Failed to create conversation"),
                                error.localizedDescription
                            )
                        }
                        completion(nil)
                    }
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    self?.errorMessage = String(
                        format: NSLocalizedString("messaging.error.verifyPermissions", comment: "Failed to verify permissions"),
                        error.localizedDescription
                    )
                }
                completion(nil)
            }
        }
    }

    private func createNewConversation(with user: AppUser, from userId: String, completion: @escaping (Conversation?) -> Void) {
        let participants = [userId, user.id].sorted()
        let readStatus: [String: Bool] = [userId: true, user.id: false]
        let conversationData: [String: Any] = [
            "participants": participants,
            "lastMessage": "",
            "timestamp": FieldValue.serverTimestamp(),
            "readStatus": readStatus,
            "otherParticipantId": user.id,
            "otherParticipantUsername": user.username,
            "otherParticipantProfileImagePath": user.profileImagePath ?? ""
        ]

        let conversationRef = Firestore.firestore().collection("conversations").document()
        let conversationId = conversationRef.documentID

        conversationRef.setData(conversationData) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = String(
                        format: NSLocalizedString("messaging.error.createConversation", comment: "Failed to create conversation"),
                        error.localizedDescription
                    )
                }
                completion(nil)
                return
            }

            let newConversation = Conversation(
                id: conversationId,
                participants: participants,
                lastMessage: "",
                timestamp: Date(),
                readStatus: readStatus,
                otherParticipantId: user.id,
                otherParticipantUsername: user.username,
                otherParticipantProfileImagePath: user.profileImagePath ?? ""
            )

            DispatchQueue.main.async {
                self?.conversations.insert(newConversation, at: 0)
                self?.selectedConversation = newConversation
            }

            completion(newConversation)
        }
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

    func startConversation(with user: AppUser, from userId: String, initialMessage: String? = nil, completion: @escaping (Conversation?) -> Void) {
        requiresMessageRequest = false

        if let existingConversation = conversations.first(where: { $0.otherParticipantId == user.id && $0.id != nil }) {
            let trimmedInitial = initialMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !trimmedInitial.isEmpty else {
                DispatchQueue.main.async {
                    self.selectedConversation = existingConversation
                    completion(existingConversation)
                }
                return
            }

            guard let conversationId = existingConversation.id else {
                DispatchQueue.main.async {
                    self.errorMessage = NSLocalizedString("messaging.error.startConversationFailed", comment: "Failed to start conversation")
                    completion(nil)
                }
                return
            }

            chatService.sendTextMessage(
                conversationId: conversationId,
                senderId: userId,
                content: trimmedInitial
            ) { [weak self] result in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        let updatedConversation = Conversation(
                            id: existingConversation.id,
                            participants: existingConversation.participants,
                            lastMessage: MessageType.text.conversationPreview,
                            timestamp: Date(),
                            readStatus: existingConversation.readStatus,
                            otherParticipantId: existingConversation.otherParticipantId,
                            otherParticipantUsername: existingConversation.otherParticipantUsername,
                            otherParticipantProfileImagePath: existingConversation.otherParticipantProfileImagePath,
                            isPinned: existingConversation.isPinned,
                            pinnedByUserIds: existingConversation.pinnedByUserIds,
                            pinnedBy: existingConversation.pinnedBy,
                            isMuted: existingConversation.isMuted,
                            mutedByUserIds: existingConversation.mutedByUserIds,
                            mutedBy: existingConversation.mutedBy
                        )
                        self.selectedConversation = updatedConversation
                        if let idx = self.conversations.firstIndex(where: { $0.id == conversationId }) {
                            self.conversations[idx] = updatedConversation
                        }
                        self.fetchConversations(for: userId)
                        self.errorMessage = nil
                        self.requiresMessageRequest = false
                        completion(updatedConversation)
                    case .failure(let error):
                        self.errorMessage = String(
                            format: NSLocalizedString("messaging.error.sendMessage", comment: "Failed to send message"),
                            error.localizedDescription
                        )
                        self.requiresMessageRequest = false
                        completion(nil)
                    }
                }
            }
            return
        }

        chatService.canSendMessage(from: userId, to: user.id) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let canSend):
                if !canSend {
                    DispatchQueue.main.async {
                        self.errorMessage = NSLocalizedString("messaging.error.cannotStart", comment: "Cannot start conversation")
                        self.requiresMessageRequest = false
                        completion(nil)
                    }
                    return
                }

                self.chatService.getOrCreateConversation(between: userId, and: user.id, initialMessage: initialMessage) { result in
                    switch result {
                    case .success(let conversationId):
                        DispatchQueue.main.async {
                            let immediateConversation = Conversation(
                                id: conversationId,
                                participants: [userId, user.id].sorted(),
                                lastMessage: MessageType.text.conversationPreview,
                                timestamp: Date(),
                                readStatus: [userId: true, user.id: false],
                                otherParticipantId: user.id,
                                otherParticipantUsername: user.username,
                                otherParticipantProfileImagePath: user.profileImagePath
                            )
                            self.selectedConversation = immediateConversation
                            if !self.conversations.contains(where: { $0.id == conversationId }) {
                                self.conversations.insert(immediateConversation, at: 0)
                            }
                            self.fetchConversations(for: userId)
                            self.errorMessage = nil
                            self.requiresMessageRequest = false
                            completion(immediateConversation)
                        }

                    case .failure(let error):
                        let nsError = error as NSError
                        DispatchQueue.main.async {
                            let localizedError = nsError.localizedDescription.lowercased()
                            if nsError.code == 403 || localizedError.contains("no siguen mutuamente") || localizedError.contains("solicitud") {
                                self.errorMessage = NSLocalizedString("messaging.error.messageRequestRequired", comment: "A message request is required to start this conversation")
                                self.requiresMessageRequest = true
                            } else {
                                self.errorMessage = String(
                                    format: NSLocalizedString("messaging.error.createConversation", comment: "Failed to create conversation"),
                                    nsError.localizedDescription
                                )
                                self.requiresMessageRequest = false
                            }
                            completion(nil)
                        }
                    }
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    self.errorMessage = String(
                        format: NSLocalizedString("messaging.error.verifyPermissions", comment: "Failed to verify permissions"),
                        error.localizedDescription
                    )
                    self.requiresMessageRequest = false
                    completion(nil)
                }
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
