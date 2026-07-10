import Foundation
import FirebaseFirestore
import FirebaseAuth

struct ConversationLastMessageReaction: Codable, Equatable {
    let messageId: String
    let emoji: String
    let byUserId: String
}

struct PendingChatContext: Identifiable, Hashable {
    enum Direction: String, Hashable {
        case outgoing
        case incoming
    }

    enum Status: String, Hashable {
        case normalConversation
        case outgoingRequestDraft
        case outgoingRequestSent
        case outgoingRequestBlocked
        case incomingRequestPending
    }

    let id: String
    let otherUserId: String
    let otherUsername: String
    let otherProfileImagePath: String?
    let otherFollowersCount: Int?
    let otherMomentsCount: Int?
    let otherIsVerified: Bool
    let viewerFollowsOther: Bool?
    let otherFollowsViewer: Bool?
    let viewerFollowedAt: Date?
    let otherFollowedViewerAt: Date?
    let request: MessageRequest?
    let direction: Direction
    var status: Status
    var initialText: String?

    init(
        otherUserId: String,
        otherUsername: String,
        otherProfileImagePath: String?,
        otherFollowersCount: Int? = nil,
        otherMomentsCount: Int? = nil,
        otherIsVerified: Bool = false,
        viewerFollowsOther: Bool? = nil,
        otherFollowsViewer: Bool? = nil,
        viewerFollowedAt: Date? = nil,
        otherFollowedViewerAt: Date? = nil,
        request: MessageRequest? = nil,
        direction: Direction,
        status: Status,
        initialText: String? = nil
    ) {
        self.otherUserId = otherUserId
        self.otherUsername = otherUsername
        self.otherProfileImagePath = otherProfileImagePath
        self.otherFollowersCount = otherFollowersCount
        self.otherMomentsCount = otherMomentsCount
        self.otherIsVerified = otherIsVerified
        self.viewerFollowsOther = viewerFollowsOther
        self.otherFollowsViewer = otherFollowsViewer
        self.viewerFollowedAt = viewerFollowedAt
        self.otherFollowedViewerAt = otherFollowedViewerAt
        self.request = request
        self.direction = direction
        self.status = status
        self.initialText = initialText
        self.id = request?.id.map { "request:\($0)" } ?? "pending:\(direction.rawValue):\(otherUserId)"
    }

    init(
        outgoingTo user: AppUser,
        status: Status = .outgoingRequestDraft,
        initialText: String? = nil,
        request: MessageRequest? = nil,
        followersCount: Int? = nil,
        momentsCount: Int? = nil,
        viewerFollowsOther: Bool? = nil,
        otherFollowsViewer: Bool? = nil,
        viewerFollowedAt: Date? = nil,
        otherFollowedViewerAt: Date? = nil
    ) {
        self.init(
            otherUserId: user.id,
            otherUsername: user.username,
            otherProfileImagePath: user.profileImagePath,
            otherFollowersCount: followersCount ?? user.followersCount,
            otherMomentsCount: momentsCount ?? user.momentsCount,
            otherIsVerified: user.isVerified,
            viewerFollowsOther: viewerFollowsOther,
            otherFollowsViewer: otherFollowsViewer,
            viewerFollowedAt: viewerFollowedAt,
            otherFollowedViewerAt: otherFollowedViewerAt,
            request: request,
            direction: .outgoing,
            status: status,
            initialText: initialText
        )
    }

    func resetToDraft() -> PendingChatContext {
        PendingChatContext(
            otherUserId: otherUserId,
            otherUsername: otherUsername,
            otherProfileImagePath: otherProfileImagePath,
            otherFollowersCount: otherFollowersCount,
            otherMomentsCount: otherMomentsCount,
            otherIsVerified: otherIsVerified,
            viewerFollowsOther: viewerFollowsOther,
            otherFollowsViewer: otherFollowsViewer,
            viewerFollowedAt: viewerFollowedAt,
            otherFollowedViewerAt: otherFollowedViewerAt,
            request: nil,
            direction: .outgoing,
            status: .outgoingRequestDraft,
            initialText: nil
        )
    }

    init(incoming request: MessageRequest) {
        self.init(
            otherUserId: request.senderId,
            otherUsername: request.senderUsername ?? NSLocalizedString("common.user", value: "Usuario", comment: "Generic user fallback"),
            otherProfileImagePath: request.senderProfileImagePath,
            request: request,
            direction: .incoming,
            status: .incomingRequestPending,
            initialText: request.message
        )
    }

    init(
        incoming request: MessageRequest,
        sender: AppUser?,
        followersCount: Int?,
        momentsCount: Int?,
        viewerFollowsOther: Bool?,
        otherFollowsViewer: Bool?,
        viewerFollowedAt: Date?,
        otherFollowedViewerAt: Date?
    ) {
        self.init(
            otherUserId: request.senderId,
            otherUsername: sender?.username ?? request.senderUsername ?? NSLocalizedString("common.user", value: "Usuario", comment: "Generic user fallback"),
            otherProfileImagePath: sender?.profileImagePath ?? request.senderProfileImagePath,
            otherFollowersCount: followersCount,
            otherMomentsCount: momentsCount,
            otherIsVerified: sender?.isVerified ?? false,
            viewerFollowsOther: viewerFollowsOther,
            otherFollowsViewer: otherFollowsViewer,
            viewerFollowedAt: viewerFollowedAt,
            otherFollowedViewerAt: otherFollowedViewerAt,
            request: request,
            direction: .incoming,
            status: .incomingRequestPending,
            initialText: request.message
        )
    }

    func syntheticConversation(currentUserId: String) -> Conversation {
        Conversation(
            id: nil,
            participants: [currentUserId, otherUserId].filter { !$0.isEmpty }.sorted(),
            lastMessage: initialText,
            timestamp: request?.timestamp ?? Date(),
            readStatus: [currentUserId: true, otherUserId: false],
            otherParticipantId: otherUserId,
            otherParticipantUsername: otherUsername,
            otherParticipantProfileImagePath: otherProfileImagePath
        )
    }
}

struct AcceptMessageRequestResult: Hashable {
    let conversationId: String
    let messageId: String
}

enum PendingChatContextFactory {
    private static let conversationIntroCache = ConversationIntroContextCache()

    static func conversationIntro(for conversation: Conversation, currentUserId: String) async -> PendingChatContext? {
        let otherUserId = conversation.otherParticipantId
        guard !currentUserId.isEmpty, !otherUserId.isEmpty else { return nil }

        if let cached = await conversationIntroCache.value(currentUserId: currentUserId, otherUserId: otherUserId) {
            return cached
        }

        async let otherUser = fetchCachedOrRemoteUser(userId: otherUserId)
        async let viewerFollowedAt = followTimestamp(from: currentUserId, to: otherUserId)
        async let otherFollowedViewerAt = followerTimestamp(viewerId: currentUserId, otherId: otherUserId)
        async let profileStats = fetchProfileStats(userId: otherUserId)
        async let followersAggregate = aggregateFollowersCount(userId: otherUserId)
        async let visibleMoments = visibleMomentsCount(userId: otherUserId)

        let user = await otherUser
        let relationship = await (viewerFollowedAt, otherFollowedViewerAt)
        let stats = await profileStats
        let counts = await (followersAggregate, visibleMoments)

        let context = PendingChatContext(
            otherUserId: otherUserId,
            otherUsername: user?.username ?? conversation.otherParticipantUsername ?? NSLocalizedString("common.user", value: "Usuario", comment: "Generic user fallback"),
            otherProfileImagePath: user?.profileImagePath ?? conversation.otherParticipantProfileImagePath,
            otherFollowersCount: resolvedCount(user?.followersCount, stats?.followersCount, counts.0),
            otherMomentsCount: counts.1 ?? resolvedCount(user?.momentsCount, stats?.momentsCount),
            otherIsVerified: user?.isVerified ?? false,
            viewerFollowsOther: relationship.0 != nil,
            otherFollowsViewer: relationship.1 != nil,
            viewerFollowedAt: relationship.0,
            otherFollowedViewerAt: relationship.1,
            request: nil,
            direction: .outgoing,
            status: .normalConversation
        )

        await conversationIntroCache.insert(context, currentUserId: currentUserId, otherUserId: otherUserId)
        return context
    }

    static func outgoing(
        to user: AppUser,
        from currentUserId: String,
        followersCountOverride: Int? = nil,
        momentsCountOverride: Int? = nil
    ) async -> PendingChatContext {
        async let viewerFollowedAt = followTimestamp(from: currentUserId, to: user.id)
        async let otherFollowedViewerAt = followerTimestamp(viewerId: currentUserId, otherId: user.id)
        async let profileStats = fetchProfileStats(userId: user.id)
        async let pendingRequest = pendingOutgoingRequest(from: currentUserId, to: user.id)
        async let followersAggregate = aggregateFollowersCount(userId: user.id)
        async let visibleMoments = visibleMomentsCount(userId: user.id)

        let relationship = await (viewerFollowedAt, otherFollowedViewerAt)
        let stats = await profileStats
        let existingRequest = await pendingRequest
        let counts = await (followersAggregate, visibleMoments)

        let receiverFollowsViewer = relationship.1 != nil
        let policy = stats?.requestPolicy ?? user.messageRequestPolicy
        let requestsClosed = policy == .nobody || (policy == .following && !receiverFollowsViewer)
        let status: PendingChatContext.Status = existingRequest != nil
            ? .outgoingRequestSent
            : (requestsClosed ? .outgoingRequestBlocked : .outgoingRequestDraft)

        return PendingChatContext(
            outgoingTo: user,
            status: status,
            initialText: existingRequest?.message,
            request: existingRequest,
            followersCount: resolvedCount(user.followersCount, followersCountOverride, stats?.followersCount, counts.0),
            momentsCount: momentsCountOverride ?? counts.1 ?? resolvedCount(user.momentsCount, stats?.momentsCount),
            viewerFollowsOther: relationship.0 != nil,
            otherFollowsViewer: relationship.1 != nil,
            viewerFollowedAt: relationship.0,
            otherFollowedViewerAt: relationship.1
        )
    }

    static func incoming(request: MessageRequest, viewerId: String) async -> PendingChatContext {
        async let sender = fetchUser(userId: request.senderId)
        async let viewerFollowedAt = followTimestamp(from: viewerId, to: request.senderId)
        async let otherFollowedViewerAt = followerTimestamp(viewerId: viewerId, otherId: request.senderId)
        async let profileStats = fetchProfileStats(userId: request.senderId)
        async let followersAggregate = aggregateFollowersCount(userId: request.senderId)
        async let visibleMoments = visibleMomentsCount(userId: request.senderId)

        let senderUser = await sender
        let relationship = await (viewerFollowedAt, otherFollowedViewerAt)
        let stats = await profileStats
        let counts = await (followersAggregate, visibleMoments)

        return PendingChatContext(
            incoming: request,
            sender: senderUser,
            followersCount: resolvedCount(senderUser?.followersCount, stats?.followersCount, counts.0),
            momentsCount: counts.1 ?? resolvedCount(senderUser?.momentsCount, stats?.momentsCount),
            viewerFollowsOther: relationship.0 != nil,
            otherFollowsViewer: relationship.1 != nil,
            viewerFollowedAt: relationship.0,
            otherFollowedViewerAt: relationship.1
        )
    }

    private static func fetchUser(userId: String) async -> AppUser? {
        guard !userId.isEmpty else { return nil }
        return try? await FirestoreService().fetchUsersAsync(userIds: [userId]).first
    }

    private static func fetchCachedOrRemoteUser(userId: String) async -> AppUser? {
        if let cached = UserCacheService.shared.getCachedUser(userId: userId) {
            return cached
        }
        return await fetchUser(userId: userId)
    }

    static func pendingOutgoingRequest(from senderId: String, to receiverId: String) async -> MessageRequest? {
        guard !senderId.isEmpty, !receiverId.isEmpty else { return nil }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("messageRequests")
                .whereField("senderId", isEqualTo: senderId)
                .whereField("receiverId", isEqualTo: receiverId)
                .whereField("status", isEqualTo: MessageRequest.RequestStatus.pending.rawValue)
                .getDocuments()
            guard let document = snapshot.documents.first else { return nil }
            return MessageRequest.fromFirestoreData(document.data(), id: document.documentID)
        } catch {
            return nil
        }
    }

    private static func followTimestamp(from followerId: String, to followedId: String) async -> Date? {
        guard !followerId.isEmpty, !followedId.isEmpty else { return nil }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("users")
                .document(followerId)
                .collection("following")
                .document(followedId)
                .getDocument()
            return (snapshot.data()?["timestamp"] as? Timestamp)?.dateValue()
        } catch {
            return nil
        }
    }

    /// Lee la propia subcolección `followers` del viewer (en vez de la `following` ajena) para
    /// evitar el fallo de permisos de Firestore al consultar la lista privada de otro usuario
    /// (regla `following` exige `showFollowing`, campo que no todos los usuarios tienen seteado).
    private static func followerTimestamp(viewerId: String, otherId: String) async -> Date? {
        guard !viewerId.isEmpty, !otherId.isEmpty else { return nil }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("users")
                .document(viewerId)
                .collection("followers")
                .document(otherId)
                .getDocument()
            return (snapshot.data()?["timestamp"] as? Timestamp)?.dateValue()
        } catch {
            return nil
        }
    }

    /// Cuenta seguidores con una aggregate query (1 lectura, sin traer documentos).
    private static func aggregateFollowersCount(userId: String) async -> Int? {
        guard !userId.isEmpty else { return nil }
        return await aggregateCount(
            Firestore.firestore().collection("users").document(userId).collection("followers")
        )
    }

    /// Cuenta solo los moments que el viewer actual puede ver: audiencia, archivados y privacidad
    /// los resuelve el backend (`getProfileMomentsPage`), igual que el grid del perfil.
    /// Fallback: aggregate de los públicos (audience == everyone) si el backend no responde.
    private static func visibleMomentsCount(userId: String) async -> Int? {
        guard !userId.isEmpty else { return nil }
        if let result = await BackendFeedService.shared.fetchProfileMoments(targetUserId: userId, limit: 1, includeTotalCount: true),
           let total = result.totalVisibleCount {
            return total
        }
        return await aggregateCount(
            Firestore.firestore().collection("users").document(userId).collection("moments")
                .whereField("audience", isEqualTo: "everyone")
        )
    }

    private static func aggregateCount(_ query: Query) async -> Int? {
        do {
            let snapshot = try await query.count.getAggregation(source: .server)
            return snapshot.count.intValue
        } catch {
            return nil
        }
    }

    private static func fetchProfileStats(userId: String) async -> (followersCount: Int?, momentsCount: Int?, requestPolicy: MessageRequestPolicy?)? {
        guard !userId.isEmpty else { return nil }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("users")
                .document(userId)
                .getDocument()
            guard let data = snapshot.data() else { return nil }
            return (
                firstIntValue(from: data, keys: ["followersCount", "followers_count"]),
                firstIntValue(from: data, keys: ["momentsCount", "moments_count", "postsCount", "posts_count"]),
                (data["messageRequestPolicy"] as? String).flatMap(MessageRequestPolicy.init(rawValue:))
            )
        } catch {
            return nil
        }
    }

    private static func resolvedCount(_ values: Int?...) -> Int? {
        let resolved = values.compactMap { $0 }.max() ?? 0
        return resolved > 0 ? resolved : nil
    }

    private static func intValue(from value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as Int64:
            return Int(value)
        case let value as Double:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        default:
            return nil
        }
    }

    private static func firstIntValue(from data: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = intValue(from: data[key]) {
                return value
            }
        }
        return nil
    }
}

actor ConversationIntroContextCache {
    private struct Entry {
        let context: PendingChatContext
        let storedAt: Date
    }

    private let ttl: TimeInterval = 300
    private var storage: [String: Entry] = [:]

    func value(currentUserId: String, otherUserId: String) -> PendingChatContext? {
        let key = cacheKey(currentUserId: currentUserId, otherUserId: otherUserId)
        guard let entry = storage[key] else { return nil }
        guard Date().timeIntervalSince(entry.storedAt) < ttl else {
            storage.removeValue(forKey: key)
            return nil
        }
        return entry.context
    }

    func insert(_ context: PendingChatContext, currentUserId: String, otherUserId: String) {
        let key = cacheKey(currentUserId: currentUserId, otherUserId: otherUserId)
        storage[key] = Entry(context: context, storedAt: Date())
    }

    private func cacheKey(currentUserId: String, otherUserId: String) -> String {
        "\(currentUserId)::\(otherUserId)"
    }
}

struct PendingChatTimelineMessage: Identifiable, Hashable {
    let id: String
    let text: String
    let messageType: MessageType
    let mediaUrl: String?
    let thumbnailUrl: String?
    let timestamp: Date
    let isOutgoing: Bool

    init(request: MessageRequest, currentUserId: String) {
        self.id = request.id.map { "pending-request:\($0)" } ?? "pending-request:\(request.senderId):\(request.timestamp.timeIntervalSince1970)"
        self.text = request.message
        self.messageType = request.messageType
        self.mediaUrl = request.mediaUrl
        self.thumbnailUrl = request.thumbnailUrl
        self.timestamp = request.timestamp
        self.isOutgoing = request.senderId == currentUserId
    }

    init(outgoingText: String, receiverId: String) {
        self.id = "pending-outgoing:\(receiverId)"
        self.text = outgoingText
        self.messageType = .text
        self.mediaUrl = nil
        self.thumbnailUrl = nil
        self.timestamp = Date()
        self.isOutgoing = true
    }
}

// MARK: - Conversation Model
struct Conversation: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    let participants: [String]
    let lastMessage: String?
    let timestamp: Date
    var readStatus: [String: Bool]
    let otherParticipantId: String
    var otherParticipantUsername: String?
    var otherParticipantProfileImagePath: String?
    let isPinned: Bool?
    let pinnedByUserIds: [String]?
    let pinnedBy: String?
    let isMuted: Bool?
    let mutedByUserIds: [String]?
    let mutedBy: String?
    let archivedByUserIds: [String]?
    let encryptionVersion: String?
    let conversationKeyVersion: Int?
    let wrappedKeys: [String: WrappedConversationKey]?

    // ✅ Privacy: Preferencias explícitas de lectura por usuario en este chat
    var readReceiptPreferences: [String: Bool]?
    /// Si `false`, los demás no pueden enviar zumbidos a ese usuario en este chat.
    var buzzPreferences: [String: Bool]?
    /// Si `false`, los demás no pueden reenviar los mensajes de texto de ese usuario en este chat.
    var forwardingPreferences: [String: Bool]?
    /// Timestamp del momento en que cada usuario borró la conversación (punto de corte).
    /// Los mensajes y buzz events con timestamp ≤ este valor se ocultan para ese usuario.
    var lastDeletedAt: [String: Date]?
    /// Última vez que cada usuario marcó la conversación como leída (server timestamp).
    /// Mensajes entrantes con timestamp ≤ este valor cuentan como leídos para ese usuario.
    var lastReadAt: [String: Date]?
    /// Modo desaparecer activo en el hilo.
    var vanishModeActive: Bool?
    var vanishModeEnabledBy: String?
    var vanishModeEnabledAt: Date?
    var vanishMessageTimer: String?
    /// ID del notice inline activo de vanish activado (para actualizar timer in-place).
    var vanishSettingsNoticeMessageId: String?
    /// ID del notice inline de vanish desactivado (anti-spam al togglear OFF muy rápido).
    var vanishDisabledNoticeMessageId: String?
    var lastMessageSenderId: String?
    var lastMessageSeenAt: [String: Date]?
    var lastMessageReaction: ConversationLastMessageReaction?
    /// Tipo del último mensaje (Firestore + hidratación local).
    var lastMessageType: MessageType?
    /// View-once entrante aún no abierto por el usuario actual.
    var lastMessageViewOncePending: Bool = false

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        return lhs.id == rhs.id
    }

    enum CodingKeys: String, CodingKey {
        case id
        case participants
        case lastMessage
        case timestamp
        case readStatus
        case otherParticipantId
        case otherParticipantUsername
        case otherParticipantProfileImagePath
        case isPinned
        case pinnedByUserIds
        case pinnedBy
        case isMuted
        case mutedByUserIds
        case mutedBy
        case archivedByUserIds
        case encryptionVersion
        case conversationKeyVersion
        case wrappedKeys
        case readReceiptPreferences
        case buzzPreferences
        case forwardingPreferences
        case lastDeletedAt
        case vanishModeActive
        case vanishModeEnabledBy
        case vanishModeEnabledAt
        case vanishMessageTimer
        case vanishSettingsNoticeMessageId
        case vanishDisabledNoticeMessageId

    }

    init(
        id: String?,
        participants: [String],
        lastMessage: String?,
        timestamp: Date,
        readStatus: [String: Bool],
        otherParticipantId: String,
        otherParticipantUsername: String?,
        otherParticipantProfileImagePath: String?,
        isPinned: Bool? = false,
        pinnedByUserIds: [String]? = nil,
        pinnedBy: String? = nil,
        isMuted: Bool? = false,
        mutedByUserIds: [String]? = nil,
        mutedBy: String? = nil,
        archivedByUserIds: [String]? = nil,
        encryptionVersion: String? = nil,
        conversationKeyVersion: Int? = nil,
        wrappedKeys: [String: WrappedConversationKey]? = nil
    ) {
        self.id = id
        self.participants = participants
        self.lastMessage = lastMessage
        self.timestamp = timestamp
        self.readStatus = readStatus
        self.otherParticipantId = otherParticipantId
        self.otherParticipantUsername = otherParticipantUsername
        self.otherParticipantProfileImagePath = otherParticipantProfileImagePath
        self.isPinned = isPinned
        self.pinnedByUserIds = pinnedByUserIds
        self.pinnedBy = pinnedBy
        self.isMuted = isMuted
        self.mutedByUserIds = mutedByUserIds
        self.mutedBy = mutedBy
        self.archivedByUserIds = archivedByUserIds
        self.encryptionVersion = encryptionVersion
        self.conversationKeyVersion = conversationKeyVersion
        self.wrappedKeys = wrappedKeys
        self.readReceiptPreferences = [:]
        self.buzzPreferences = [:]
        self.forwardingPreferences = [:]
        self.lastDeletedAt = nil
        self.lastReadAt = nil
        self.vanishModeActive = false
        self.vanishModeEnabledBy = nil
        self.vanishModeEnabledAt = nil
        self.vanishMessageTimer = VanishMessageTimer.default.rawValue
        self.lastMessageSenderId = nil
        self.lastMessageSeenAt = nil
        self.lastMessageReaction = nil
        self.lastMessageType = nil
        self.lastMessageViewOncePending = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.participants = try container.decode([String].self, forKey: .participants)
        self.lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage)
        let timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
        self.timestamp = timestamp.dateValue()
        self.readStatus = try container.decodeIfPresent([String: Bool].self, forKey: .readStatus) ?? [:]
        self.otherParticipantId = try container.decodeIfPresent(String.self, forKey: .otherParticipantId) ?? ""
        self.otherParticipantUsername = try container.decodeIfPresent(String.self, forKey: .otherParticipantUsername)
        self.otherParticipantProfileImagePath = try container.decodeIfPresent(String.self, forKey: .otherParticipantProfileImagePath)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.pinnedByUserIds = try container.decodeIfPresent([String].self, forKey: .pinnedByUserIds)
        self.pinnedBy = try container.decodeIfPresent(String.self, forKey: .pinnedBy)
        self.isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        self.mutedByUserIds = try container.decodeIfPresent([String].self, forKey: .mutedByUserIds)
        self.mutedBy = try container.decodeIfPresent(String.self, forKey: .mutedBy)
        self.archivedByUserIds = try container.decodeIfPresent([String].self, forKey: .archivedByUserIds)
        self.encryptionVersion = try container.decodeIfPresent(String.self, forKey: .encryptionVersion)
        self.conversationKeyVersion = try container.decodeIfPresent(Int.self, forKey: .conversationKeyVersion)
        self.wrappedKeys = try container.decodeIfPresent([String: WrappedConversationKey].self, forKey: .wrappedKeys)
        self.readReceiptPreferences = try container.decodeIfPresent([String: Bool].self, forKey: .readReceiptPreferences) ?? [:]
        self.buzzPreferences = try container.decodeIfPresent([String: Bool].self, forKey: .buzzPreferences) ?? [:]
        self.forwardingPreferences = try container.decodeIfPresent([String: Bool].self, forKey: .forwardingPreferences) ?? [:]
        // lastDeletedAt/lastReadAt se hidratan manualmente desde Firestore (Timestamp → Date)
        self.lastDeletedAt = nil
        self.lastReadAt = nil
        self.vanishModeActive = try container.decodeIfPresent(Bool.self, forKey: .vanishModeActive) ?? false
        self.vanishModeEnabledBy = try container.decodeIfPresent(String.self, forKey: .vanishModeEnabledBy)
        if let enabledAt = try container.decodeIfPresent(Timestamp.self, forKey: .vanishModeEnabledAt) {
            self.vanishModeEnabledAt = enabledAt.dateValue()
        } else {
            self.vanishModeEnabledAt = nil
        }
        self.vanishMessageTimer = try container.decodeIfPresent(String.self, forKey: .vanishMessageTimer)
            ?? VanishMessageTimer.default.rawValue
        self.vanishSettingsNoticeMessageId = try container.decodeIfPresent(String.self, forKey: .vanishSettingsNoticeMessageId)
        self.vanishDisabledNoticeMessageId = try container.decodeIfPresent(String.self, forKey: .vanishDisabledNoticeMessageId)
        self.lastMessageSenderId = nil
        self.lastMessageSeenAt = nil
        self.lastMessageReaction = nil
        self.lastMessageType = nil
        self.lastMessageViewOncePending = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(participants, forKey: .participants)
        try container.encodeIfPresent(lastMessage, forKey: .lastMessage)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        try container.encode(readStatus, forKey: .readStatus)
        try container.encode(otherParticipantId, forKey: .otherParticipantId)
        try container.encodeIfPresent(otherParticipantUsername, forKey: .otherParticipantUsername)
        try container.encodeIfPresent(otherParticipantProfileImagePath, forKey: .otherParticipantProfileImagePath)
        try container.encodeIfPresent(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(pinnedByUserIds, forKey: .pinnedByUserIds)
        try container.encodeIfPresent(pinnedBy, forKey: .pinnedBy)
        try container.encodeIfPresent(isMuted, forKey: .isMuted)
        try container.encodeIfPresent(mutedByUserIds, forKey: .mutedByUserIds)
        try container.encodeIfPresent(mutedBy, forKey: .mutedBy)
        try container.encodeIfPresent(archivedByUserIds, forKey: .archivedByUserIds)
        try container.encodeIfPresent(encryptionVersion, forKey: .encryptionVersion)
        try container.encodeIfPresent(conversationKeyVersion, forKey: .conversationKeyVersion)
        try container.encodeIfPresent(wrappedKeys, forKey: .wrappedKeys)
        try container.encodeIfPresent(readReceiptPreferences, forKey: .readReceiptPreferences)
        try container.encodeIfPresent(buzzPreferences, forKey: .buzzPreferences)
        try container.encodeIfPresent(forwardingPreferences, forKey: .forwardingPreferences)
        // lastDeletedAt no se codifica a Firestore desde el cliente; se gestiona en el servidor
        try container.encodeIfPresent(vanishModeActive, forKey: .vanishModeActive)
        try container.encodeIfPresent(vanishModeEnabledBy, forKey: .vanishModeEnabledBy)
        if let vanishModeEnabledAt {
            try container.encode(Timestamp(date: vanishModeEnabledAt), forKey: .vanishModeEnabledAt)
        }
        try container.encodeIfPresent(vanishMessageTimer, forKey: .vanishMessageTimer)
        try container.encodeIfPresent(vanishSettingsNoticeMessageId, forKey: .vanishSettingsNoticeMessageId)
        try container.encodeIfPresent(vanishDisabledNoticeMessageId, forKey: .vanishDisabledNoticeMessageId)
    }

    func allowsForwarding(ofMessagesFrom senderId: String) -> Bool {
        forwardingPreferences?[senderId] ?? true
    }

    func isMuted(for userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else {
            return isMuted ?? false
        }

        if mutedByUserIds?.contains(userId) == true {
            return true
        }

        if isMuted == true, let mutedBy {
            return mutedBy == userId
        }

        return false
    }

    func isPinned(for userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else {
            return isPinned ?? false
        }

        if pinnedByUserIds?.contains(userId) == true {
            return true
        }

        if isPinned == true, let pinnedBy {
            return pinnedBy == userId
        }

        return false
    }

    func isArchived(for userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return archivedByUserIds?.contains(userId) == true
    }

    /// Devuelve el timestamp de borrado del usuario dado, si existe.
    /// Mensajes y buzz events con `timestamp <= deletedAtCutoff` deben ocultarse para ese usuario.
    func deletedAtCutoff(for userId: String) -> Date? {
        lastDeletedAt?[userId]
    }

    // Propiedad calculada para obtener el número de mensajes no leídos
    @MainActor
    var unreadCount: Int {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let isRead = readStatus[currentUserId] else { return 0 }
        if isRead { return 0 }
        guard let id = id else { return 1 }
        let dbCount = LocalPersistenceService.shared.unreadMessageCount(
            for: id,
            currentUserId: currentUserId,
            since: lastReadAt?[currentUserId]
        )
        return dbCount > 0 ? dbCount : 1
    }

    // Verificar si la conversación está activa
    var isActive: Bool {
        // Aquí podrías verificar que ningún participante haya bloqueado al otro
        return true // Por ahora retornamos true
    }

    /// Indica si el último mensaje del hilo es del usuario actual (para preview del inbox).
    /// Infiere desde metadatos de lectura/reacción cuando `lastMessageSenderId` no llegó sincronizado.
    func isOwnLastMessage(for currentUserId: String) -> Bool {
        if lastMessageSenderId == currentUserId { return true }
        if lastMessageSeenAt?[otherParticipantId] != nil { return true }
        if let reaction = lastMessageReaction, reaction.byUserId == otherParticipantId { return true }
        return false
    }

    /// Botón play azul en inbox cuando hay view-once entrante sin abrir.
    func showsViewOnceInboxPlayButton(for currentUserId: String) -> Bool {
        guard lastMessageViewOncePending,
              let type = lastMessageType,
              type.isViewOnce,
              !isOwnLastMessage(for: currentUserId) else {
            return false
        }
        return true
    }

    /// Preview de lista: view-once entrante → "Foto"/"Video" genérico.
    func inboxMessagePreview(for currentUserId: String) -> String {
        if let type = lastMessageType,
           type.isViewOnce,
           !isOwnLastMessage(for: currentUserId) {
            switch type {
            case .viewOnceVideo:
                return NSLocalizedString("chat.preview.video", comment: "")
            default:
                return NSLocalizedString("chat.preview.photo", comment: "")
            }
        }
        return messagePreview
    }

    // Obtener preview del último mensaje para notificaciones
    var messagePreview: String {
        if let lastMessage {
            if lastMessage.starts(with: "📎") {
                return lastMessage
            } else if lastMessage.count > 50 {
                return String(lastMessage.prefix(47)) + "..."
            }
            return lastMessage
        }
        return NSLocalizedString("chat.preview.newConversation", comment: "")
    }
}

// MARK: - Legacy Message Model (mantener compatibilidad)
struct Message: Identifiable, Codable {
    @DocumentID var id: String?
    let conversationId: String
    let senderId: String
    let content: String
    let timestamp: Date
    var isRead: Bool
    var reaction: String?
    var expirationDate: Date?
    var isViewed: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId
        case senderId
        case content
        case timestamp
        case isRead
        case reaction
        case expirationDate
        case isViewed
    }

    init(id: String?, conversationId: String, senderId: String, content: String, timestamp: Date, isRead: Bool, reaction: String?, expirationDate: Date? = nil, isViewed: Bool = false) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.content = content
        self.timestamp = timestamp
        self.isRead = isRead
        self.reaction = reaction
        self.expirationDate = expirationDate
        self.isViewed = isViewed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.conversationId = try container.decode(String.self, forKey: .conversationId)
        self.senderId = try container.decode(String.self, forKey: .senderId)
        self.content = try container.decode(String.self, forKey: .content)
        let timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
        self.timestamp = timestamp.dateValue()
        self.isRead = try container.decode(Bool.self, forKey: .isRead)
        self.reaction = try container.decodeIfPresent(String.self, forKey: .reaction)
        self.expirationDate = try container.decodeIfPresent(Timestamp.self, forKey: .expirationDate)?.dateValue()
        self.isViewed = try container.decodeIfPresent(Bool.self, forKey: .isViewed) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(content, forKey: .content)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        try container.encode(isRead, forKey: .isRead)
        try container.encodeIfPresent(reaction, forKey: .reaction)
        if let expirationDate = expirationDate {
            try container.encode(Timestamp(date: expirationDate), forKey: .expirationDate)
        }
        try container.encode(isViewed, forKey: .isViewed)
    }
}

extension Message: Equatable {
    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Message Types
enum MessageType: String, CaseIterable, Codable {
    case text = "text"
    case image = "image"
    case video = "video"
    case audio = "audio"
    case gif = "gif"
    case sticker = "sticker"
    case location = "location"
    case file = "file"
    case ephemeral = "ephemeral"
    case sharedMoment = "sharedMoment"
    case sharedStory = "sharedStory"
    // ✅ NUEVOS: Tipos para view-once
    case viewOnceImage = "viewOnceImage"
    case viewOnceVideo = "viewOnceVideo"
    case chatNotice = "chatNotice"

    var displayName: String {
        switch self {
        case .text: return NSLocalizedString("common.text", comment: "")
        case .image: return NSLocalizedString("common.photo", comment: "")
        case .video: return NSLocalizedString("common.video", comment: "")
        case .audio: return NSLocalizedString("common.audio", comment: "")
        case .gif: return "GIF"
        case .sticker: return "Sticker"
        case .location: return NSLocalizedString("common.location", comment: "")
        case .file: return NSLocalizedString("common.file", comment: "")
        case .ephemeral: return NSLocalizedString("chat.viewOnce.viewOnce", comment: "")
        case .sharedMoment: return NSLocalizedString("chat.preview.sharedMoment", comment: "")
        case .sharedStory: return NSLocalizedString("chat.preview.sharedStory", comment: "")
        case .viewOnceImage: return NSLocalizedString("chat.viewOnce.photo", comment: "") + " (" + NSLocalizedString("chat.viewOnce.viewOnce", comment: "") + ")"
        case .viewOnceVideo: return NSLocalizedString("chat.viewOnce.video", comment: "") + " (" + NSLocalizedString("chat.viewOnce.viewOnce", comment: "") + ")"
        case .chatNotice: return ""
        }
    }

    var iconName: String {
        switch self {
        case .text: return "text.bubble"
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "mic"
        case .gif: return "photo.on.rectangle.angled"
        case .sticker: return "face.smiling"
        case .location: return "location"
        case .file: return "doc"
        case .ephemeral: return "timer"
        case .sharedMoment: return "square.and.arrow.up"
        case .sharedStory: return "paperplane.fill"
        case .viewOnceImage: return "camera.circle"
        case .viewOnceVideo: return "video.circle"
        case .chatNotice: return "timer"
        }
    }

    // ✅ NUEVA: Propiedad para identificar view-once
    var isViewOnce: Bool {
        return self == .viewOnceImage || self == .viewOnceVideo
    }

    var isChatNotice: Bool {
        self == .chatNotice
    }

    // ✅ NUEVA: Preview para lista de conversaciones
    var conversationPreview: String {
        switch self {
        case .text: return NSLocalizedString("chat.preview.text", comment: "")
        case .image: return NSLocalizedString("chat.preview.photo", comment: "")
        case .video: return NSLocalizedString("chat.preview.video", comment: "")
        case .audio: return NSLocalizedString("chat.preview.audio", comment: "")
        case .gif: return NSLocalizedString("chat.preview.gif", comment: "")
        case .sticker: return NSLocalizedString("chat.preview.sticker", comment: "")
        case .location: return NSLocalizedString("chat.preview.location", comment: "")
        case .file: return NSLocalizedString("chat.preview.file", comment: "")
        case .ephemeral: return NSLocalizedString("chat.preview.ephemeral", comment: "")
        case .sharedMoment: return NSLocalizedString("chat.preview.sharedMoment", comment: "")
        case .sharedStory: return NSLocalizedString("chat.preview.sharedStory", comment: "")
        case .viewOnceImage: return NSLocalizedString("chat.preview.photo", comment: "")
        case .viewOnceVideo: return NSLocalizedString("chat.preview.video", comment: "")
        case .chatNotice: return ""
        }
    }
}

private let neutralConversationPreviewPrefixes = ["💬", "📷", "🎥", "🎵", "🎞", "😊", "📍", "📎", "📸", "⏱"]

func sanitizedConversationPreview(_ rawPreview: String?, encryptionVersion: String?) -> String {
    let trimmedPreview = rawPreview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard encryptionVersion?.hasPrefix("3") == true else {
        return trimmedPreview
    }

    guard !trimmedPreview.isEmpty else {
        return MessageType.text.conversationPreview
    }

    if neutralConversationPreviewPrefixes.contains(where: { trimmedPreview.hasPrefix($0) }) {
        return trimmedPreview
    }

    return MessageType.text.conversationPreview
}

// MARK: - Message Status
enum MessageStatus: String, Codable {
    case pending = "pending"
    case sending = "sending"
    case sent = "sent"
    case delivered = "delivered"
    case read = "read"
    case failed = "failed"

    var displayName: String {
        switch self {
        case .pending: return NSLocalizedString("chat.status.pending", comment: "")
        case .sending: return NSLocalizedString("chat.status.sending", comment: "")
        case .sent: return NSLocalizedString("chat.status.sent", comment: "")
        case .delivered: return NSLocalizedString("chat.status.delivered", comment: "")
        case .read: return NSLocalizedString("chat.status.read", comment: "")
        case .failed: return NSLocalizedString("chat.status.failed", comment: "")
        }
    }

    var iconName: String {
        switch self {
        case .pending, .sending: return "clock"
        case .sent: return "checkmark"
        case .delivered: return "checkmark.circle"
        case .read: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

enum ChatMediaPurpose: String, Codable {
    case primary
    case thumbnail
}

struct EncryptedChatMediaMetadata: Codable, Hashable {
    let version: String
    let algorithm: String
    let purpose: ChatMediaPurpose
    let mediaId: String
    let contentType: String
    let fileExtension: String
    let plaintextSize: Int64

    init(
        version: String = "1.0",
        algorithm: String = "AES.GCM+HKDF-SHA256",
        purpose: ChatMediaPurpose,
        mediaId: String,
        contentType: String,
        fileExtension: String,
        plaintextSize: Int64
    ) {
        self.version = version
        self.algorithm = algorithm
        self.purpose = purpose
        self.mediaId = mediaId
        self.contentType = contentType
        self.fileExtension = fileExtension
        self.plaintextSize = plaintextSize
    }

    init?(map: [String: Any]) {
        guard
            let version = map["version"] as? String,
            let algorithm = map["algorithm"] as? String,
            let purposeRaw = map["purpose"] as? String,
            let purpose = ChatMediaPurpose(rawValue: purposeRaw),
            let mediaId = map["mediaId"] as? String,
            let contentType = map["contentType"] as? String,
            let fileExtension = map["fileExtension"] as? String
        else {
            return nil
        }

        let plaintextSize: Int64
        if let size = map["plaintextSize"] as? Int64 {
            plaintextSize = size
        } else if let size = map["plaintextSize"] as? Int {
            plaintextSize = Int64(size)
        } else if let size = map["plaintextSize"] as? Double {
            plaintextSize = Int64(size)
        } else {
            return nil
        }

        self.init(
            version: version,
            algorithm: algorithm,
            purpose: purpose,
            mediaId: mediaId,
            contentType: contentType,
            fileExtension: fileExtension,
            plaintextSize: plaintextSize
        )
    }

    var firestoreData: [String: Any] {
        [
            "version": version,
            "algorithm": algorithm,
            "purpose": purpose.rawValue,
            "mediaId": mediaId,
            "contentType": contentType,
            "fileExtension": fileExtension,
            "plaintextSize": plaintextSize
        ]
    }
}

// MARK: - Enhanced Message Model with View-Once Support
class EnhancedMessage: Codable, Identifiable, ObservableObject {
    let id: String
    let conversationId: String
    let senderId: String
    let type: MessageType
    let content: String?
    var mediaUrl: String? {
        didSet { objectWillChange.send() }
    }
    var thumbnailUrl: String? {
        didSet { objectWillChange.send() }
    }
    let mediaObjectPath: String?
    let thumbnailObjectPath: String?
    let mediaEncryption: EncryptedChatMediaMetadata?
    let thumbnailEncryption: EncryptedChatMediaMetadata?
    let duration: Double?
    let audioWaveform: [Float]?
    let fileName: String?
    let fileSize: Int64?
    let latitude: Double?
    let longitude: Double?
    // ✅ NUEVO: Ubicación (fija + en vivo)
    let locationName: String?
    let locationAddress: String?
    let isLiveLocation: Bool?
    let liveLocationExpiresAt: Date?
    let liveLocationDuration: String?
    var liveLocationStoppedAt: Date?
    let liveLocationSessionId: String?
    let locationUpdatedAt: Date?
    let timestamp: Date
    @Published var status: MessageStatus
    @Published var isRead: Bool
    @Published var isDeleted: Bool
    var deletedAt: Date?
    var editedAt: Date?
    var reactions: [String: [String]]? {
        didSet { objectWillChange.send() }
    }
    var replyTo: String?
    var expirationDate: Date?
    @Published var isViewed: Bool
    let storyReplyData: [String: String]?
    let sharedMomentData: [String: String]?
    let sharedStoryData: [String: String]?
    let mediaBatchId: String?
    var textOverlayLive: Bool?
    var textOverlays: [StoryTextOverlayMetadata]?
    var stickers: [StickerData]?
    var drawingData: Data?

    // ✅ NUEVOS: Campos para view-once
    var viewedBy: [String]? // IDs de usuarios que han visto el mensaje view-once
    // Modo "permitir repetición": el receptor puede ver el media una segunda vez.
    var allowReplay: Bool?
    var replayedBy: [String]?
    @Published var replayAvailableInCurrentChatSession: Bool = false
    @Published var replayConsumedInCurrentChatSession: Bool = false
    /// Lectores registrados aunque el destinatario tenga read receipts desactivados (solo vanish/timer).
    var readBy: [String]?
    var starredBy: [String]?
    var isForwarded: Bool?
    /// Dimensiones originales de GIF/sticker (p. ej. Giphy `fixed_height`).
    let mediaWidth: Int?
    let mediaHeight: Int?
    let isVanishModeMessage: Bool?
    var vanishedFor: [String]?
    var vanishExpiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, conversationId, senderId, type, content, mediaUrl, thumbnailUrl
        case mediaObjectPath, thumbnailObjectPath, mediaEncryption, thumbnailEncryption
        case duration, audioWaveform, fileName, fileSize, mediaWidth, mediaHeight, latitude, longitude, timestamp
        case status, isRead, isDeleted, deletedAt, editedAt, reactions
        case replyTo, expirationDate, isViewed, storyReplyData, sharedMomentData, sharedStoryData
        case mediaBatchId
        case textOverlayLive, textOverlays, stickers, drawingData
        case viewedBy
        case allowReplay
        case replayedBy
        case readBy
        case starredBy, isForwarded
        case isVanishModeMessage
        case vanishedFor
        case vanishExpiresAt
        // ✅ NUEVO: Ubicación (fija + en vivo)
        case locationName, locationAddress
        case isLiveLocation, liveLocationExpiresAt, liveLocationDuration
        case liveLocationStoppedAt, liveLocationSessionId, locationUpdatedAt
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(String.self, forKey: .id)
        self.conversationId = try container.decode(String.self, forKey: .conversationId)
        self.senderId = try container.decode(String.self, forKey: .senderId)

        if let typeString = try container.decodeIfPresent(String.self, forKey: .type),
           let type = MessageType(rawValue: typeString) {
            self.type = type
        } else {
            self.type = .text
        }

        self.content = try container.decodeIfPresent(String.self, forKey: .content)
        self.mediaUrl = try container.decodeIfPresent(String.self, forKey: .mediaUrl)
        self.thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        self.mediaObjectPath = try container.decodeIfPresent(String.self, forKey: .mediaObjectPath)
        self.thumbnailObjectPath = try container.decodeIfPresent(String.self, forKey: .thumbnailObjectPath)
        self.mediaEncryption = try container.decodeIfPresent(EncryptedChatMediaMetadata.self, forKey: .mediaEncryption)
        self.thumbnailEncryption = try container.decodeIfPresent(EncryptedChatMediaMetadata.self, forKey: .thumbnailEncryption)
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        self.audioWaveform = try container.decodeIfPresent([Float].self, forKey: .audioWaveform)
        self.fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        self.fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        self.mediaWidth = try container.decodeIfPresent(Int.self, forKey: .mediaWidth)
        self.mediaHeight = try container.decodeIfPresent(Int.self, forKey: .mediaHeight)
        self.latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        self.longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)

        // ✅ NUEVO: Ubicación (fija + en vivo)
        self.locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        self.locationAddress = try container.decodeIfPresent(String.self, forKey: .locationAddress)
        self.isLiveLocation = try container.decodeIfPresent(Bool.self, forKey: .isLiveLocation)
        self.liveLocationDuration = try container.decodeIfPresent(String.self, forKey: .liveLocationDuration)
        self.liveLocationSessionId = try container.decodeIfPresent(String.self, forKey: .liveLocationSessionId)
        if let expiresAt = try container.decodeIfPresent(Timestamp.self, forKey: .liveLocationExpiresAt) {
            self.liveLocationExpiresAt = expiresAt.dateValue()
        } else {
            self.liveLocationExpiresAt = nil
        }
        if let stoppedAt = try container.decodeIfPresent(Timestamp.self, forKey: .liveLocationStoppedAt) {
            self.liveLocationStoppedAt = stoppedAt.dateValue()
        } else {
            self.liveLocationStoppedAt = nil
        }
        if let updatedAt = try container.decodeIfPresent(Timestamp.self, forKey: .locationUpdatedAt) {
            self.locationUpdatedAt = updatedAt.dateValue()
        } else {
            self.locationUpdatedAt = nil
        }

        if let timestamp = try container.decodeIfPresent(Timestamp.self, forKey: .timestamp) {
            self.timestamp = timestamp.dateValue()
        } else {
            self.timestamp = Date()
        }

        let statusString = try container.decodeIfPresent(String.self, forKey: .status) ?? MessageStatus.sent.rawValue
        let status = MessageStatus(rawValue: statusString) ?? .sent
        self.status = status

        let isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        self.isRead = isRead

        let isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        self.isDeleted = isDeleted

        if let deletedAt = try container.decodeIfPresent(Timestamp.self, forKey: .deletedAt) {
            self.deletedAt = deletedAt.dateValue()
        } else {
            self.deletedAt = nil
        }

        if let editedAt = try container.decodeIfPresent(Timestamp.self, forKey: .editedAt) {
            self.editedAt = editedAt.dateValue()
        } else {
            self.editedAt = nil
        }

        self.reactions = try container.decodeIfPresent([String: [String]].self, forKey: .reactions)
        self.replyTo = try container.decodeIfPresent(String.self, forKey: .replyTo)

        if let expirationDate = try container.decodeIfPresent(Timestamp.self, forKey: .expirationDate) {
            self.expirationDate = expirationDate.dateValue()
        } else {
            self.expirationDate = nil
        }

        let isViewed = try container.decodeIfPresent(Bool.self, forKey: .isViewed) ?? false
        self.isViewed = isViewed

        self.storyReplyData = try container.decodeIfPresent([String: String].self, forKey: .storyReplyData)
        self.sharedMomentData = try container.decodeIfPresent([String: String].self, forKey: .sharedMomentData)
        self.sharedStoryData = try container.decodeIfPresent([String: String].self, forKey: .sharedStoryData)
        self.mediaBatchId = try container.decodeIfPresent(String.self, forKey: .mediaBatchId)
        self.textOverlayLive = try container.decodeIfPresent(Bool.self, forKey: .textOverlayLive)
        self.textOverlays = try container.decodeIfPresent([StoryTextOverlayMetadata].self, forKey: .textOverlays)
        self.stickers = try container.decodeIfPresent([StickerData].self, forKey: .stickers)
        self.drawingData = try container.decodeIfPresent(Data.self, forKey: .drawingData)

        // ✅ NUEVO: Decodificar viewedBy
        self.viewedBy = try container.decodeIfPresent([String].self, forKey: .viewedBy)
        self.allowReplay = try container.decodeIfPresent(Bool.self, forKey: .allowReplay)
        self.replayedBy = try container.decodeIfPresent([String].self, forKey: .replayedBy)
        self.readBy = try container.decodeIfPresent([String].self, forKey: .readBy)
        self.starredBy = try container.decodeIfPresent([String].self, forKey: .starredBy)
        self.isForwarded = try container.decodeIfPresent(Bool.self, forKey: .isForwarded)
        self.isVanishModeMessage = try container.decodeIfPresent(Bool.self, forKey: .isVanishModeMessage)
        self.vanishedFor = try container.decodeIfPresent([String].self, forKey: .vanishedFor)
        if let expiresAt = try container.decodeIfPresent(Timestamp.self, forKey: .vanishExpiresAt) {
            self.vanishExpiresAt = expiresAt.dateValue()
        } else {
            self.vanishExpiresAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(type.rawValue, forKey: .type)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(mediaUrl, forKey: .mediaUrl)
        try container.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
        try container.encodeIfPresent(mediaObjectPath, forKey: .mediaObjectPath)
        try container.encodeIfPresent(thumbnailObjectPath, forKey: .thumbnailObjectPath)
        try container.encodeIfPresent(mediaEncryption, forKey: .mediaEncryption)
        try container.encodeIfPresent(thumbnailEncryption, forKey: .thumbnailEncryption)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(audioWaveform, forKey: .audioWaveform)
        try container.encodeIfPresent(fileName, forKey: .fileName)
        try container.encodeIfPresent(fileSize, forKey: .fileSize)
        try container.encodeIfPresent(mediaWidth, forKey: .mediaWidth)
        try container.encodeIfPresent(mediaHeight, forKey: .mediaHeight)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        // ✅ NUEVO: Ubicación (fija + en vivo)
        try container.encodeIfPresent(locationName, forKey: .locationName)
        try container.encodeIfPresent(locationAddress, forKey: .locationAddress)
        try container.encodeIfPresent(isLiveLocation, forKey: .isLiveLocation)
        try container.encodeIfPresent(liveLocationDuration, forKey: .liveLocationDuration)
        try container.encodeIfPresent(liveLocationSessionId, forKey: .liveLocationSessionId)
        if let liveLocationExpiresAt {
            try container.encode(Timestamp(date: liveLocationExpiresAt), forKey: .liveLocationExpiresAt)
        }
        if let liveLocationStoppedAt {
            try container.encode(Timestamp(date: liveLocationStoppedAt), forKey: .liveLocationStoppedAt)
        }
        if let locationUpdatedAt {
            try container.encode(Timestamp(date: locationUpdatedAt), forKey: .locationUpdatedAt)
        }
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(isRead, forKey: .isRead)
        try container.encode(isDeleted, forKey: .isDeleted)

        if let deletedAt = deletedAt {
            try container.encode(Timestamp(date: deletedAt), forKey: .deletedAt)
        }

        if let editedAt = editedAt {
            try container.encode(Timestamp(date: editedAt), forKey: .editedAt)
        }

        try container.encodeIfPresent(reactions, forKey: .reactions)
        try container.encodeIfPresent(replyTo, forKey: .replyTo)

        if let expirationDate = expirationDate {
            try container.encode(Timestamp(date: expirationDate), forKey: .expirationDate)
        }

        try container.encode(isViewed, forKey: .isViewed)
        try container.encodeIfPresent(storyReplyData, forKey: .storyReplyData)
        try container.encodeIfPresent(sharedMomentData, forKey: .sharedMomentData)
        try container.encodeIfPresent(sharedStoryData, forKey: .sharedStoryData)
        try container.encodeIfPresent(mediaBatchId, forKey: .mediaBatchId)
        try container.encodeIfPresent(textOverlayLive, forKey: .textOverlayLive)
        try container.encodeIfPresent(textOverlays, forKey: .textOverlays)
        try container.encodeIfPresent(stickers, forKey: .stickers)
        try container.encodeIfPresent(drawingData, forKey: .drawingData)

        // ✅ NUEVO: Codificar viewedBy
        try container.encodeIfPresent(viewedBy, forKey: .viewedBy)
        try container.encodeIfPresent(allowReplay, forKey: .allowReplay)
        try container.encodeIfPresent(replayedBy, forKey: .replayedBy)
        try container.encodeIfPresent(readBy, forKey: .readBy)
        try container.encodeIfPresent(starredBy, forKey: .starredBy)
        try container.encodeIfPresent(isForwarded, forKey: .isForwarded)
        try container.encodeIfPresent(isVanishModeMessage, forKey: .isVanishModeMessage)
        try container.encodeIfPresent(vanishedFor, forKey: .vanishedFor)
        if let vanishExpiresAt {
            try container.encode(Timestamp(date: vanishExpiresAt), forKey: .vanishExpiresAt)
        }
    }

    func isVanished(forUserId userId: String) -> Bool {
        vanishedFor?.contains(userId) == true
    }

    required init(id: String? = nil,
         conversationId: String,
         senderId: String,
         type: MessageType,
         content: String? = nil,
         mediaUrl: String? = nil,
         thumbnailUrl: String? = nil,
         mediaObjectPath: String? = nil,
         thumbnailObjectPath: String? = nil,
         mediaEncryption: EncryptedChatMediaMetadata? = nil,
         thumbnailEncryption: EncryptedChatMediaMetadata? = nil,
         duration: Double? = nil,
         audioWaveform: [Float]? = nil,
         fileName: String? = nil,
         fileSize: Int64? = nil,
         mediaWidth: Int? = nil,
         mediaHeight: Int? = nil,
         latitude: Double? = nil,
         longitude: Double? = nil,
         locationName: String? = nil,
         locationAddress: String? = nil,
         isLiveLocation: Bool? = nil,
         liveLocationExpiresAt: Date? = nil,
         liveLocationDuration: String? = nil,
         liveLocationStoppedAt: Date? = nil,
         liveLocationSessionId: String? = nil,
         locationUpdatedAt: Date? = nil,
         timestamp: Date = Date(),
         status: MessageStatus = .sending,
         isRead: Bool = false,
         isDeleted: Bool = false,
         deletedAt: Date? = nil,
         editedAt: Date? = nil,
         reactions: [String: [String]]? = nil,
         replyTo: String? = nil,
         expirationDate: Date? = nil,
         isViewed: Bool = false,
         storyReplyData: [String: String]? = nil,
         sharedMomentData: [String: String]? = nil,
         sharedStoryData: [String: String]? = nil,
         mediaBatchId: String? = nil,
         textOverlayLive: Bool? = nil,
         textOverlays: [StoryTextOverlayMetadata]? = nil,
         stickers: [StickerData]? = nil,
         drawingData: Data? = nil,
         viewedBy: [String]? = nil,
         readBy: [String]? = nil,
         starredBy: [String]? = nil,
         isForwarded: Bool? = nil,
         isVanishModeMessage: Bool? = nil,
         vanishedFor: [String]? = nil,
         vanishExpiresAt: Date? = nil) {

        self.id = id ?? UUID().uuidString
        self.conversationId = conversationId
        self.senderId = senderId
        self.type = type
        self.content = content
        self.mediaUrl = mediaUrl
        self.thumbnailUrl = thumbnailUrl
        self.mediaObjectPath = mediaObjectPath
        self.thumbnailObjectPath = thumbnailObjectPath
        self.mediaEncryption = mediaEncryption
        self.thumbnailEncryption = thumbnailEncryption
        self.duration = duration
        self.audioWaveform = audioWaveform
        self.fileName = fileName
        self.fileSize = fileSize
        self.mediaWidth = mediaWidth
        self.mediaHeight = mediaHeight
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.locationAddress = locationAddress
        self.isLiveLocation = isLiveLocation
        self.liveLocationExpiresAt = liveLocationExpiresAt
        self.liveLocationDuration = liveLocationDuration
        self.liveLocationStoppedAt = liveLocationStoppedAt
        self.liveLocationSessionId = liveLocationSessionId
        self.locationUpdatedAt = locationUpdatedAt
        self.timestamp = timestamp
        self.status = status
        self.isRead = isRead
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.editedAt = editedAt
        self.reactions = reactions
        self.replyTo = replyTo
        self.expirationDate = expirationDate
        self.isViewed = isViewed
        self.storyReplyData = storyReplyData
        self.sharedMomentData = sharedMomentData
        self.sharedStoryData = sharedStoryData
        self.mediaBatchId = mediaBatchId
        self.textOverlayLive = textOverlayLive
        self.textOverlays = textOverlays
        self.stickers = stickers
        self.drawingData = drawingData
        self.viewedBy = viewedBy
        self.readBy = readBy
        self.starredBy = starredBy
        self.isForwarded = isForwarded
        self.isVanishModeMessage = isVanishModeMessage
        self.vanishedFor = vanishedFor
        self.vanishExpiresAt = vanishExpiresAt
    }

    func isStarred(by userId: String) -> Bool {
        starredBy?.contains(userId) ?? false
    }

    func replacingContent(_ newContent: String?) -> EnhancedMessage {
        EnhancedMessage(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            type: type,
            content: newContent,
            mediaUrl: mediaUrl,
            thumbnailUrl: thumbnailUrl,
            mediaObjectPath: mediaObjectPath,
            thumbnailObjectPath: thumbnailObjectPath,
            mediaEncryption: mediaEncryption,
            thumbnailEncryption: thumbnailEncryption,
            duration: duration,
            audioWaveform: audioWaveform,
            fileName: fileName,
            fileSize: fileSize,
            mediaWidth: mediaWidth,
            mediaHeight: mediaHeight,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            locationAddress: locationAddress,
            isLiveLocation: isLiveLocation,
            liveLocationExpiresAt: liveLocationExpiresAt,
            liveLocationDuration: liveLocationDuration,
            liveLocationStoppedAt: liveLocationStoppedAt,
            liveLocationSessionId: liveLocationSessionId,
            locationUpdatedAt: locationUpdatedAt,
            timestamp: timestamp,
            status: status,
            isRead: isRead,
            isDeleted: isDeleted,
            deletedAt: deletedAt,
            editedAt: editedAt,
            reactions: reactions,
            replyTo: replyTo,
            expirationDate: expirationDate,
            isViewed: isViewed,
            storyReplyData: storyReplyData,
            sharedMomentData: sharedMomentData,
            sharedStoryData: sharedStoryData,
            mediaBatchId: mediaBatchId,
            textOverlayLive: textOverlayLive,
            textOverlays: textOverlays,
            stickers: stickers,
            drawingData: drawingData,
            viewedBy: viewedBy,
            readBy: readBy,
            starredBy: starredBy,
            isForwarded: isForwarded,
            isVanishModeMessage: isVanishModeMessage,
            vanishedFor: vanishedFor,
            vanishExpiresAt: vanishExpiresAt
        )
    }

    var isExpired: Bool {
        guard let expirationDate = expirationDate else { return false }
        return Date() > expirationDate
    }

    /// `true` si el mensaje es una sesión de ubicación en vivo (independiente de si sigue activa).
    var isLiveLocationMessage: Bool {
        type == .location && (isLiveLocation ?? false)
    }

    /// `true` si la sesión live sigue activa (no parada manualmente y no expirada).
    var isLiveLocationActive: Bool {
        guard isLiveLocationMessage else { return false }
        if liveLocationStoppedAt != nil { return false }
        if let expiresAt = liveLocationExpiresAt, Date() >= expiresAt { return false }
        return true
    }

    // ✅ ACTUALIZADA: Preview mejorado con support para view-once
    var preview: String {
        if isVanishModeMessage == true, type != .chatNotice {
            return type.conversationPreview
        }
        switch type {
        case .text:
            return content ?? ""
        case .image:
            return NSLocalizedString("chat.preview.image", comment: "")
        case .video:
            return NSLocalizedString("chat.preview.video", comment: "")
        case .audio:
            return NSLocalizedString("chat.preview.audio", comment: "")
        case .gif:
            return NSLocalizedString("chat.preview.gif", comment: "")
        case .sticker:
            return NSLocalizedString("chat.preview.sticker", comment: "")
        case .location:
            return NSLocalizedString("chat.preview.location", comment: "")
        case .file:
            return "📎 \(fileName ?? NSLocalizedString("common.file", comment: ""))"
        case .ephemeral:
            return NSLocalizedString("chat.preview.ephemeral_long", comment: "")
        case .sharedMoment:
            return NSLocalizedString("chat.preview.sharedMoment", comment: "")
        case .sharedStory:
            return NSLocalizedString("chat.preview.sharedStory", comment: "")
        case .viewOnceImage:
            return NSLocalizedString("chat.preview.photo", comment: "")
        case .viewOnceVideo:
            return NSLocalizedString("chat.preview.video", comment: "")
        case .chatNotice:
            return EnhancedMessage.chatNoticePreviewText(for: content ?? "")
        }
    }

    static func chatNoticePreviewText(for token: String) -> String {
        if VanishMessageTimer.parseEnabledNotice(token) != nil || token == "chat.vanish.enabled" {
            return NSLocalizedString("chat.vanish.notice.preview.enabled", comment: "Disappearing messages turned on")
        }
        if token == VanishMessageTimer.disabledNoticeToken || token == "chat.vanish.disabled" {
            return NSLocalizedString("chat.vanish.notice.preview.disabled", comment: "Disappearing messages turned off")
        }
        if token == VanishMessageTimer.screenshotNoticeToken {
            return NSLocalizedString("chat.vanish.screenshot", comment: "")
        }
        if token == VanishMessageTimer.screenRecordingNoticeToken {
            return NSLocalizedString("chat.vanish.screenRecording", comment: "")
        }
        guard !token.isEmpty else { return "" }
        let localized = NSLocalizedString(token, comment: "Chat system notice")
        return localized == token ? "" : localized
    }

    // ✅ NUEVAS: Propiedades y funciones para view-once

    /// Determina si este mensaje es view-once
    var isViewOnce: Bool {
        return type.isViewOnce
    }

    /// Determina si el usuario actual ya vio este mensaje view-once
    func hasBeenViewedBy(userId: String) -> Bool {
        guard isViewOnce else { return false }
        return viewedBy?.contains(userId) ?? false
    }

    func hasBeenReplayedBy(userId: String) -> Bool {
        guard isViewOnce else { return false }
        return replayedBy?.contains(userId) ?? false
    }

    /// El receptor puede repetir la vista: modo allow-replay, ya visto y sin repetir.
    func canReplayViewOnce(userId: String) -> Bool {
        guard isViewOnce, allowReplay == true, senderId != userId else { return false }
        return hasBeenViewedBy(userId: userId) && !hasBeenReplayedBy(userId: userId)
    }

    /// Obtiene el estado del view-once para un usuario específico
    func viewOnceStatus(for currentUserId: String) -> String {
        guard isViewOnce else { return "" }

        if senderId == currentUserId {
            // Usuario que envió el mensaje
            return isViewed ? NSLocalizedString("chat.viewOnce.viewed", comment: "") : NSLocalizedString("chat.viewOnce.sent", comment: "")
        } else {
            // Usuario que recibe el mensaje
            let hasViewed = hasBeenViewedBy(userId: currentUserId)
            return hasViewed ? NSLocalizedString("chat.viewOnce.viewed", comment: "") : NSLocalizedString("chat.viewOnce.tapToView", comment: "")
        }
    }

    /// Determina si debe mostrar el contenido del view-once
    func shouldShowViewOnceContent(for currentUserId: String) -> Bool {
        guard isViewOnce else { return true }

        if senderId == currentUserId {
            // El remitente siempre puede ver un preview
            return true
        } else {
            // El receptor solo puede ver si no ha sido visto aún
            return !hasBeenViewedBy(userId: currentUserId)
        }
    }

    /// Obtiene el ícono apropiado para el tipo de mensaje
    var typeIcon: String {
        return type.iconName
    }

    /// Determina si el mensaje puede ser eliminado automáticamente (view-once visto)
    var canBeAutoDeleted: Bool {
        return isViewOnce && isViewed && !isDeleted
    }

    /// Preview para mostrar en la lista de conversaciones
    var conversationPreview: String {
        if let content = content, type == .text {
            return content.count > 50 ? String(content.prefix(47)) + "..." : content
        }
        return type.conversationPreview
    }
}

// MARK: - ✅ NUEVAS: Extensiones para View-Once
extension EnhancedMessage: Equatable {
    static func == (lhs: EnhancedMessage, rhs: EnhancedMessage) -> Bool {
        return lhs.id == rhs.id
    }
}

extension EnhancedMessage: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - ✅ NUEVA: Extension para crear mensajes view-once fácilmente
extension EnhancedMessage {

    /// Crea un mensaje view-once de imagen
    static func createViewOnceImage(
        conversationId: String,
        senderId: String,
        mediaUrl: String,
        fileSize: Int64? = nil
    ) -> EnhancedMessage {
        return EnhancedMessage(
            conversationId: conversationId,
            senderId: senderId,
            type: .viewOnceImage,
            mediaUrl: mediaUrl,
            fileSize: fileSize,
            viewedBy: []
        )
    }

    /// Crea un mensaje view-once de video
    static func createViewOnceVideo(
        conversationId: String,
        senderId: String,
        mediaUrl: String,
        thumbnailUrl: String? = nil,
        duration: Double? = nil,
        fileSize: Int64? = nil
    ) -> EnhancedMessage {
        return EnhancedMessage(
            conversationId: conversationId,
            senderId: senderId,
            type: .viewOnceVideo,
            mediaUrl: mediaUrl,
            thumbnailUrl: thumbnailUrl,
            duration: duration,
            fileSize: fileSize,
            viewedBy: []
        )
    }
}

// MARK: - ✅ NUEVA: Helper para conversión de tipos de media
enum ViewOnceMediaType {
    case image
    case video

    var messageType: MessageType {
        switch self {
        case .image: return .viewOnceImage
        case .video: return .viewOnceVideo
        }
    }

    var preview: String {
        switch self {
        case .image: return NSLocalizedString("chat.preview.viewOncePhoto", comment: "")
        case .video: return NSLocalizedString("chat.preview.viewOnceVideo", comment: "")
        }
    }

    var iconName: String {
        switch self {
        case .image: return "camera.circle"
        case .video: return "video.circle"
        }
    }
}

// MARK: - ✅ NUEVA: Extension para compatibilidad con EnhancedCameraPickerView
extension ViewOnceMediaType {
    init(from cameraMediaType: EnhancedCameraPickerView.MediaType) {
        switch cameraMediaType {
        case .image: self = .image
        case .video: self = .video
        }
    }
}

// MARK: - ================== MODELOS AUXILIARES ==================

// MARK: - Typing Indicator Model
struct TypingIndicator: Codable {
    let userId: String
    let conversationId: String
    let timestamp: Date

    init(userId: String, conversationId: String, timestamp: Date = Date()) {
        self.userId = userId
        self.conversationId = conversationId
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case userId, conversationId, timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.conversationId = try container.decode(String.self, forKey: .conversationId)
        let timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
        self.timestamp = timestamp.dateValue()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
    }
}

// MARK: - Message Notification Model
struct MessageNotification {
    let conversationId: String
    let messageId: String
    let senderId: String
    let senderName: String
    let messagePreview: String
    let timestamp: Date
    let isViewOnce: Bool // ✅ NUEVO: Indicar si es view-once

    var title: String {
        return senderName
    }

    var body: String {
        return isViewOnce ? NSLocalizedString("chat.notification.viewOncePrompt", comment: "") : messagePreview
    }

    init(conversationId: String, messageId: String, senderId: String, senderName: String, messagePreview: String, timestamp: Date = Date(), isViewOnce: Bool = false) {
        self.conversationId = conversationId
        self.messageId = messageId
        self.senderId = senderId
        self.senderName = senderName
        self.messagePreview = messagePreview
        self.timestamp = timestamp
        self.isViewOnce = isViewOnce
    }
}

// MARK: - ✅ NUEVO: View-Once Metadata Model
struct ViewOnceMetadata: Codable {
    let messageId: String
    let conversationId: String
    let senderId: String
    let createdAt: Date
    var viewedBy: [String]
    var isExpired: Bool

    init(messageId: String, conversationId: String, senderId: String, createdAt: Date = Date()) {
        self.messageId = messageId
        self.conversationId = conversationId
        self.senderId = senderId
        self.createdAt = createdAt
        self.viewedBy = []
        self.isExpired = false
    }

    mutating func markAsViewedBy(userId: String) {
        if !viewedBy.contains(userId) {
            viewedBy.append(userId)
        }
    }

    var canBeDeleted: Bool {
        return !viewedBy.isEmpty && !isExpired
    }
}

// MARK: - ================== PROTOCOLOS Y EXTENSIONES ==================

// MARK: - Helper Protocol for Message Compatibility
protocol MessageProtocol {
    var senderId: String { get }
    var timestamp: Date { get }
    var isRead: Bool { get }
}

extension Message: MessageProtocol {}
extension EnhancedMessage: MessageProtocol {}

// MARK: - ✅ NUEVA: Extension para analytics y tracking
extension EnhancedMessage {

    /// Propiedades para analytics
    var analyticsData: [String: Any] {
        var data: [String: Any] = [
            "messageType": type.rawValue,
            "hasMedia": mediaUrl != nil,
            "isViewOnce": isViewOnce,
            "messageLength": content?.count ?? 0
        ]

        if isViewOnce {
            data["viewOnceType"] = type.rawValue
            data["hasBeenViewed"] = isViewed
            data["viewerCount"] = viewedBy?.count ?? 0
        }

        if let duration = duration {
            data["mediaDuration"] = duration
        }

        if let fileSize = fileSize {
            data["fileSize"] = fileSize
        }

        return data
    }

    /// Evento de analytics para tracking
    var analyticsEvent: String {
        if isViewOnce {
            return isViewed ? "view_once_message_viewed" : "view_once_message_sent"
        } else {
            return "message_sent"
        }
    }

    /// `true` si la URL guardada es un `file://` cuyo archivo ya NO existe en disco.
    /// El media descifrado se cachea en App Group (`ChatMedia/decrypted`), pero puede
    /// eliminarse por política de retención o cuota: hay que re-resolver al abrir.
    private static func isMissingLocalFile(_ urlString: String?) -> Bool {
        guard let urlString,
              let url = URL(string: urlString),
              url.isFileURL else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    /// El `mediaUrl` apunta a un `file://` descifrado que ya no existe (cache purgada).
    var hasMissingLocalMedia: Bool { Self.isMissingLocalFile(mediaUrl) }
    /// El `thumbnailUrl` apunta a un `file://` descifrado que ya no existe (cache purgada).
    var hasMissingLocalThumbnail: Bool { Self.isMissingLocalFile(thumbnailUrl) }

    /// `true` si la URL es remota o el archivo local existe.
    func localMediaFileIsReachable(_ url: URL) -> Bool {
        guard url.isFileURL else { return true }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Vídeo sin portada usable en la UI (miniatura cifrada, poster generado o legacy).
    var needsVideoThumbnailForDisplay: Bool {
        guard type == .video else { return false }
        guard let urlString = thumbnailUrl,
              let url = URL(string: urlString) else { return true }
        return !localMediaFileIsReachable(url)
    }

    /// Media cifrada pendiente de resolver a URL local/remota.
    var isMediaPendingResolution: Bool {
        guard !isDeleted else { return false }
        guard status != .sending else { return false }
        let canResolve = mediaObjectPath != nil && mediaEncryption != nil

        func diskMediaReachable() -> Bool {
            guard mediaUrl == nil || Self.isMissingLocalFile(mediaUrl) else { return true }
            let diskURLs = ChatCacheStore.localURLsIfPresent(for: self)
            if let media = diskURLs.mediaUrl ?? mediaUrl,
               let url = URL(string: media),
               localMediaFileIsReachable(url) {
                return true
            }
            return false
        }

        func diskThumbReachable() -> Bool {
            guard thumbnailUrl == nil || Self.isMissingLocalFile(thumbnailUrl) else { return true }
            let diskURLs = ChatCacheStore.localURLsIfPresent(for: self)
            if let thumb = diskURLs.thumbnailUrl ?? thumbnailUrl,
               let url = URL(string: thumb),
               localMediaFileIsReachable(url) {
                return true
            }
            return false
        }

        switch type {
        case .image, .ephemeral:
            if diskMediaReachable() { return false }
            if mediaUrl == nil { return canResolve }
            return Self.isMissingLocalFile(mediaUrl) && canResolve
        case .video:
            guard !diskThumbReachable() && !diskMediaReachable() else { return false }
            let canResolveThumb = thumbnailObjectPath != nil && thumbnailEncryption != nil
            return canResolve || canResolveThumb
        case .gif, .sticker:
            if mediaUrl == nil { return canResolve }
            if Self.isMissingLocalFile(mediaUrl) { return canResolve }
            return false
        default:
            return false
        }
    }

    /// Vídeo descifrado listo para reproducir (fichero `.mp4` local).
    var hasLocalVideoFileReady: Bool {
        guard type == .video else { return false }
        guard let mediaUrl, let url = URL(string: mediaUrl) else { return false }
        return localMediaFileIsReachable(url)
    }

    /// Imagen o vídeo listo para abrir en visor a pantalla completa.
    var hasLocalMediaReadyForViewer: Bool {
        switch type {
        case .image, .ephemeral:
            guard let mediaUrl, let url = URL(string: mediaUrl) else { return false }
            return localMediaFileIsReachable(url)
        case .video:
            return hasLocalVideoFileReady
        default:
            return false
        }
    }

    /// Requiere descarga/descifrado antes de abrir el visor (incluye tap manual con policy `never`).
    var needsDownloadForPlayback: Bool {
        guard !isDeleted, status != .sending else { return false }
        switch type {
        case .image, .ephemeral, .video:
            if hasLocalMediaReadyForViewer { return false }
            if mediaUrl == nil || Self.isMissingLocalFile(mediaUrl) {
                let diskURLs = ChatCacheStore.localURLsIfPresent(for: self)
                if let mediaUrl = diskURLs.mediaUrl,
                   let url = URL(string: mediaUrl),
                   localMediaFileIsReachable(url) {
                    return false
                }
            }
            return mediaObjectPath != nil && mediaEncryption != nil
        case .gif, .sticker:
            if let mediaUrl, let url = URL(string: mediaUrl), !url.isFileURL { return false }
            return isMediaPendingResolution
        default:
            return false
        }
    }

    /// Media descargable manualmente (auto-descarga desactivada por policy o sin red).
    var isMediaAwaitingManualDownload: Bool {
        guard !ChatMediaDownloadPolicy.shouldDownloadAutomatically() else { return false }
        if type == .video {
            return needsDownloadForPlayback
        }
        return isMediaPendingResolution
    }

    /// Tamaño estimado del fichero completo (metadata Firestore / cifrado).
    var estimatedDownloadByteCount: Int64? {
        if let fileSize, fileSize > 0 { return fileSize }
        if let mainSize = mediaEncryption?.plaintextSize, mainSize > 0 {
            if type == .video, let thumbSize = thumbnailEncryption?.plaintextSize, thumbSize > 0 {
                return mainSize + thumbSize
            }
            return mainSize
        }
        return nil
    }

    /// Etiqueta de tamaño ("245 KB", "1,2 MB") — tamaño del fichero completo.
    var formattedDownloadSize: String? {
        guard let bytes = estimatedDownloadByteCount else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Miniatura local usable como preview borroso (thumb cifrada ya descargada).
    var previewThumbnailURLForDisplay: String? {
        guard let urlString = thumbnailUrl,
              let url = URL(string: urlString),
              localMediaFileIsReachable(url) else {
            return nil
        }
        return urlString
    }
}

// MARK: - ✅ NUEVA: Utility para manejo de estados de view-once
struct ViewOnceStateManager {

    /// Determina si un mensaje view-once debe ser eliminado
    static func shouldDeleteViewOnceMessage(_ message: EnhancedMessage, for userId: String) -> Bool {
        guard message.isViewOnce else { return false }

        // Si el usuario no es el remitente y ya vio el mensaje
        if message.senderId != userId && message.hasBeenViewedBy(userId: userId) {
            return true
        }

        return false
    }

    /// Obtiene el texto apropiado para el estado del view-once
    static func getViewOnceStatusText(_ message: EnhancedMessage, for userId: String) -> String {
        guard message.isViewOnce else { return "" }

        if message.isDeleted {
            return NSLocalizedString("messaging.message.deleted", comment: "")
        }

        if message.senderId == userId {
            return message.isViewed
                ? NSLocalizedString("chat.viewOnce.viewed", comment: "")
                : NSLocalizedString("chat.viewOnce.sent", comment: "")
        } else {
            return message.hasBeenViewedBy(userId: userId)
                ? NSLocalizedString("chat.viewOnce.viewed", comment: "")
                : NSLocalizedString("chat.viewOnce.tapToView", comment: "")
        }
    }

    /// Obtiene el color apropiado para el estado del view-once
    static func getViewOnceStatusColor(_ message: EnhancedMessage, for userId: String) -> String {
        guard message.isViewOnce else { return "primary" }

        if message.isDeleted {
            return "secondary"
        }

        if message.senderId == userId {
            return message.isViewed ? "success" : "warning"
        } else {
            return message.hasBeenViewedBy(userId: userId) ? "secondary" : "primary"
        }
    }
}

// MARK: - ✅ NUEVA: Extension para formateo y display
extension EnhancedMessage {

    /// Formato de tiempo relativo
    var relativeTimeString: String {
        MomentsFormat.relativeTime(from: timestamp)
    }

    /// Formato de tiempo absoluto
    var absoluteTimeString: String {
        MomentsFormat.smartDate(from: timestamp, context: .messageAbsolute)
    }

    /// Tamaño del archivo formateado
    var formattedFileSize: String? {
        guard let fileSize = fileSize else { return nil }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    /// Duración formateada para audio/video
    var formattedDuration: String? {
        guard let duration = duration else { return nil }

        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60

        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }
}

// MARK: - ✅ NUEVA: Constants para view-once (Moments Style)
struct ViewOnceConstants {
    // ✅ Se borra al cerrar vista, no con timers
    static let autoDeleteDelay: TimeInterval = 0.5 // Delay antes de auto-eliminar (al cerrar vista)
    static let maxFileSize: Int64 = 50 * 1024 * 1024 // 50MB máximo
    static let supportedImageTypes = ["image/jpeg", "image/png", "image/heic"]
    static let supportedVideoTypes = ["video/mp4", "video/mov", "video/quicktime"]

    struct Analytics {
        static let viewOnceCreated = "view_once_created"
        static let viewOnceOpened = "view_once_opened"
        static let viewOnceClosed = "view_once_closed" // ✅ Se triggea al cerrar vista
        static let viewOnceDeleted = "view_once_deleted" // ✅ Se triggea después de cerrar
        static let viewOnceExpired = "view_once_expired" // ✅ Por si acaso, pero no se usa
    }

    struct Notifications {
        static let viewOnceViewed = "ViewOnceMessageViewed"
        static let viewOnceDeleted = "ViewOnceMessageDeleted"
        static let viewOnceReceived = "ViewOnceMessageReceived"
        static let viewOnceClosed = "ViewOnceMessageClosed" // ✅ NUEVO: Cuando se cierra la vista
    }

    // ✅ NUEVAS: Constantes específicas para Moments-style
    struct MomentsStyle {
        static let deleteOnViewClose = true // Se borra al cerrar vista
        static let allowScreenshots = false // Prevenir screenshots (si es posible)
        static let showCloseWarning = true // Mostrar "Se borrará al cerrar"
        static let enableHapticFeedback = true // Feedback al abrir/cerrar
    }
}

// MARK: - ✅ NUEVA: Error handling para view-once
enum ViewOnceError: Error, LocalizedError {
    case messageNotFound
    case alreadyViewed
    case notViewOnceMessage
    case deletionFailed
    case uploadFailed
    case invalidMediaType
    case fileTooLarge
    case networkError

    var errorDescription: String? {
        switch self {
        case .messageNotFound:
            return NSLocalizedString("messaging.message.notFound", comment: "")
        case .alreadyViewed:
            return NSLocalizedString("messaging.message.alreadyViewed", comment: "")
        case .notViewOnceMessage:
            return NSLocalizedString("messaging.message.notViewOnce", comment: "")
        case .deletionFailed:
            return NSLocalizedString("messaging.message.deleteFailed", comment: "")
        case .uploadFailed:
            return NSLocalizedString("messaging.message.uploadFailed", comment: "")
        case .invalidMediaType:
            return NSLocalizedString("messaging.message.unsupportedFile", comment: "")
        case .fileTooLarge:
            return NSLocalizedString("messaging.message.fileTooLarge", comment: "")
        case .networkError:
            return NSLocalizedString("messaging.message.connectionError", comment: "")
        }
    }
}

// MARK: - Message Request Model
struct MessageRequest: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    let senderId: String
    let senderUsername: String?
    let senderProfileImagePath: String?
    let receiverId: String
    let message: String
    let timestamp: Date
    let status: RequestStatus
    let messageType: MessageType
    let mediaUrl: String?
    let thumbnailUrl: String?

    enum RequestStatus: String, Codable, CaseIterable {
        case pending = "pending"
        case accepted = "accepted"
        case rejected = "rejected"
        case blocked = "blocked"

        var displayName: String {
            switch self {
            case .pending: return NSLocalizedString("messaging.request.status.pending", comment: "")
            case .accepted: return NSLocalizedString("messaging.request.status.accepted", comment: "")
            case .rejected: return NSLocalizedString("messaging.request.status.rejected", comment: "")
            case .blocked: return NSLocalizedString("messaging.request.status.blocked", comment: "")
            }
        }

        var color: String {
            switch self {
            case .pending: return "FF9500" // Naranja
            case .accepted: return "34C759" // Verde
            case .rejected: return "FF3B30" // Rojo
            case .blocked: return "8E8E93" // Gris
            }
        }
    }

    init(id: String?, senderId: String, senderUsername: String?, senderProfileImagePath: String?, receiverId: String, message: String, timestamp: Date, status: RequestStatus, messageType: MessageType, mediaUrl: String?, thumbnailUrl: String?) {
        self.id = id
        self.senderId = senderId
        self.senderUsername = senderUsername
        self.senderProfileImagePath = senderProfileImagePath
        self.receiverId = receiverId
        self.message = message
        self.timestamp = timestamp
        self.status = status
        self.messageType = messageType
        self.mediaUrl = mediaUrl
        self.thumbnailUrl = thumbnailUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.senderId = try container.decode(String.self, forKey: .senderId)
        self.senderUsername = try container.decodeIfPresent(String.self, forKey: .senderUsername)
        self.senderProfileImagePath = try container.decodeIfPresent(String.self, forKey: .senderProfileImagePath)
        self.receiverId = try container.decode(String.self, forKey: .receiverId)
        self.message = try container.decode(String.self, forKey: .message)

        // Manejar timestamp de Firestore
        do {
            let timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
            self.timestamp = timestamp.dateValue()
        } catch {
            // Si falla la decodificación de Timestamp, usar fecha actual como fallback
            self.timestamp = Date()
        }

        self.status = try container.decode(RequestStatus.self, forKey: .status)
        self.messageType = try container.decode(MessageType.self, forKey: .messageType)
        self.mediaUrl = try container.decodeIfPresent(String.self, forKey: .mediaUrl)
        self.thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(senderId, forKey: .senderId)
        try container.encodeIfPresent(senderUsername, forKey: .senderUsername)
        try container.encodeIfPresent(senderProfileImagePath, forKey: .senderProfileImagePath)
        try container.encode(receiverId, forKey: .receiverId)
        try container.encode(message, forKey: .message)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        try container.encode(status, forKey: .status)
        try container.encode(messageType, forKey: .messageType)
        try container.encodeIfPresent(mediaUrl, forKey: .mediaUrl)
        try container.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case senderId
        case senderUsername
        case senderProfileImagePath
        case receiverId
        case message
        case timestamp
        case status
        case messageType
        case mediaUrl
        case thumbnailUrl
    }

    // Propiedad calculada para mostrar preview del mensaje
    var messagePreview: String {
        switch messageType {
        case .text:
            if message.count > 50 {
                return String(message.prefix(47)) + "..."
            }
            return message
        case .image:
            return NSLocalizedString("messaging.preview.image", comment: "")
        case .video:
            return NSLocalizedString("messaging.preview.video", comment: "")
        case .audio:
            return NSLocalizedString("messaging.preview.audio", comment: "")
        case .gif:
            return NSLocalizedString("messaging.preview.gif", comment: "")
        case .file:
            return NSLocalizedString("messaging.preview.file", comment: "")
        case .location:
            return NSLocalizedString("messaging.preview.location", comment: "")
        case .sticker:
            return NSLocalizedString("messaging.preview.sticker", comment: "")
        case .ephemeral:
            return NSLocalizedString("messaging.preview.ephemeral", comment: "")
        case .sharedMoment:
            return NSLocalizedString("messaging.preview.sharedMoment", comment: "")
        case .sharedStory:
            return NSLocalizedString("chat.preview.sharedStory", comment: "")
        case .viewOnceImage:
            return NSLocalizedString("messaging.preview.viewOncePhoto", comment: "")
        case .viewOnceVideo:
            return NSLocalizedString("messaging.preview.viewOnceVideo", comment: "")
        case .chatNotice:
            let localized = NSLocalizedString(message, comment: "Chat system notice")
            if localized.count > 50 {
                return String(localized.prefix(47)) + "..."
            }
            return localized
        }
    }

    // Verificar si la solicitud está pendiente
    var isPending: Bool {
        return status == .pending
    }

    // Verificar si el usuario puede enviar más solicitudes
    var canSendMoreRequests: Bool {
        return status != .blocked
    }
}

// MARK: - Reacciones (una por usuario)

enum MessageReactionMutation {
    /// Sustituye la reacción previa del usuario o la quita si repite el mismo emoji.
    static func apply(
        to reactions: [String: [String]]?,
        emoji: String,
        userId: String
    ) -> [String: [String]]? {
        var reactions = reactions ?? [:]
        let alreadyHasThisEmoji = reactions[emoji]?.contains(userId) ?? false

        if alreadyHasThisEmoji {
            var userIds = reactions[emoji] ?? []
            userIds.removeAll { $0 == userId }
            if userIds.isEmpty {
                reactions.removeValue(forKey: emoji)
            } else {
                reactions[emoji] = userIds
            }
        } else {
            for key in Array(reactions.keys) {
                var userIds = reactions[key] ?? []
                userIds.removeAll { $0 == userId }
                if userIds.isEmpty {
                    reactions.removeValue(forKey: key)
                } else {
                    reactions[key] = userIds
                }
            }
            var userIds = reactions[emoji] ?? []
            userIds.append(userId)
            reactions[emoji] = userIds
        }

        return reactions.isEmpty ? nil : reactions
    }
}

// MARK: - Políticas de mensaje (edición, reenvío)

enum ChatMessagePolicy {
    static let editWindow: TimeInterval = 10 * 60

    static func isVanishRestricted(_ message: EnhancedMessage) -> Bool {
        message.isVanishModeMessage == true
    }

    static func canEdit(_ message: EnhancedMessage, userId: String) -> Bool {
        guard !isVanishRestricted(message) else { return false }
        guard message.senderId == userId, message.type == .text, !message.isDeleted else { return false }
        return Date().timeIntervalSince(message.timestamp) < editWindow
    }

    /// Solo texto plano; el cifrado E2E obliga a descifrar y recifrar por destino.
    static func canForward(
        _ message: EnhancedMessage,
        currentUserId: String,
        forwardingPreferences: [String: Bool]? = nil
    ) -> Bool {
        guard !isVanishRestricted(message) else { return false }
        guard message.type == .text, !message.isDeleted else { return false }
        let trimmed = message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return false }
        if message.senderId == currentUserId { return true }
        return forwardingPreferences?[message.senderId] ?? true
    }

    static func canCopy(
        _ message: EnhancedMessage,
        currentUserId: String,
        forwardingPreferences: [String: Bool]? = nil
    ) -> Bool {
        canForward(message, currentUserId: currentUserId, forwardingPreferences: forwardingPreferences)
    }

    /// El remitente solo puede zumbir si todos los demás participantes lo permiten.
    static func canSendBuzz(
        participants: [String],
        currentUserId: String,
        buzzPreferences: [String: Bool]? = nil
    ) -> Bool {
        participants
            .filter { $0 != currentUserId }
            .allSatisfy { buzzPreferences?[$0] ?? true }
    }
}
