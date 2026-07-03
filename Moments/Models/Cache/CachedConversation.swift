import Foundation
import SwiftData
import FirebaseAuth

@Model
final class CachedConversation {
    @Attribute(.unique) var id: String
    var participants: [String]
    var lastMessage: String?
    var timestamp: Date
    var readStatusData: Data? // [String: Bool] encoded
    var otherParticipantId: String
    var otherParticipantUsername: String?
    var otherParticipantProfileImagePath: String?
    var isPinned: Bool
    var isMuted: Bool
    var isArchived: Bool
    var readReceiptPreferencesData: Data? // [String: Bool] encoded
    var forwardingPreferencesData: Data? // [String: Bool] encoded
    var lastDeletedAtData: Data? // [String: Date] encoded
    var lastReadAtData: Data? // [String: Date] encoded
    var lastMessageSenderId: String?
    var lastMessageSeenAtData: Data?
    var lastMessageReactionData: Data?
    var lastSyncedAt: Date
    var vanishModeActive: Bool = false

    init(id: String,
         participants: [String],
         lastMessage: String?,
         timestamp: Date,
         readStatusData: Data? = nil,
         otherParticipantId: String,
         otherParticipantUsername: String?,
         otherParticipantProfileImagePath: String?,
         isPinned: Bool = false,
         isMuted: Bool = false,
         isArchived: Bool = false,
         readReceiptPreferencesData: Data? = nil,
         forwardingPreferencesData: Data? = nil,
         lastDeletedAtData: Data? = nil,
         lastReadAtData: Data? = nil,
         lastMessageSenderId: String? = nil,
         lastMessageSeenAtData: Data? = nil,
         lastMessageReactionData: Data? = nil,
         lastSyncedAt: Date = Date(),
         vanishModeActive: Bool = false) {
        self.id = id
        self.participants = participants
        self.lastMessage = lastMessage
        self.timestamp = timestamp
        self.readStatusData = readStatusData
        self.otherParticipantId = otherParticipantId
        self.otherParticipantUsername = otherParticipantUsername
        self.otherParticipantProfileImagePath = otherParticipantProfileImagePath
        self.isPinned = isPinned
        self.isMuted = isMuted
        self.isArchived = isArchived
        self.readReceiptPreferencesData = readReceiptPreferencesData
        self.forwardingPreferencesData = forwardingPreferencesData
        self.lastDeletedAtData = lastDeletedAtData
        self.lastReadAtData = lastReadAtData
        self.lastMessageSenderId = lastMessageSenderId
        self.lastMessageSeenAtData = lastMessageSeenAtData
        self.lastMessageReactionData = lastMessageReactionData
        self.lastSyncedAt = lastSyncedAt
        self.vanishModeActive = vanishModeActive
    }
}

extension CachedConversation {
    static func from(_ conversation: Conversation) -> CachedConversation {
        let encoder = JSONEncoder()
        let readStatusData = try? encoder.encode(conversation.readStatus)
        let readReceiptPreferencesData = try? encoder.encode(conversation.readReceiptPreferences)
        let forwardingPreferencesData = try? encoder.encode(conversation.forwardingPreferences)
        let lastDeletedAtData = try? encoder.encode(conversation.lastDeletedAt)
        let lastReadAtData = try? encoder.encode(conversation.lastReadAt)
        let lastMessageSeenAtData = try? encoder.encode(conversation.lastMessageSeenAt)
        let lastMessageReactionData = try? encoder.encode(conversation.lastMessageReaction)

        return CachedConversation(
            id: conversation.id ?? UUID().uuidString,
            participants: conversation.participants,
            lastMessage: conversation.lastMessage,
            timestamp: conversation.timestamp,
            readStatusData: readStatusData,
            otherParticipantId: conversation.otherParticipantId,
            otherParticipantUsername: conversation.otherParticipantUsername,
            otherParticipantProfileImagePath: conversation.otherParticipantProfileImagePath,
            isPinned: conversation.isPinned ?? false,
            isMuted: conversation.isMuted ?? false,
            isArchived: conversation.isArchived(for: Auth.auth().currentUser?.uid),
            readReceiptPreferencesData: readReceiptPreferencesData,
            forwardingPreferencesData: forwardingPreferencesData,
            lastDeletedAtData: lastDeletedAtData,
            lastReadAtData: lastReadAtData,
            lastMessageSenderId: conversation.lastMessageSenderId,
            lastMessageSeenAtData: lastMessageSeenAtData,
            lastMessageReactionData: lastMessageReactionData,
            lastSyncedAt: Date(),
            vanishModeActive: conversation.vanishModeActive ?? false
        )
    }

    func toConversation() -> Conversation {
        let decoder = JSONDecoder()
        let readStatus: [String: Bool] = {
            guard let data = readStatusData else { return [:] }
            return (try? decoder.decode([String: Bool].self, from: data)) ?? [:]
        }()

        let readReceiptPreferences: [String: Bool]? = {
            guard let data = readReceiptPreferencesData else { return [:] }
            return try? decoder.decode([String: Bool].self, from: data)
        }()

        let forwardingPreferences: [String: Bool]? = {
            guard let data = forwardingPreferencesData else { return [:] }
            return try? decoder.decode([String: Bool].self, from: data)
        }()

        let lastDeletedAt: [String: Date]? = {
            guard let data = lastDeletedAtData else { return nil }
            return try? decoder.decode([String: Date].self, from: data)
        }()

        let lastReadAt: [String: Date]? = {
            guard let data = lastReadAtData else { return nil }
            return try? decoder.decode([String: Date].self, from: data)
        }()

        let lastMessageSeenAt: [String: Date]? = {
            guard let data = lastMessageSeenAtData else { return nil }
            return try? decoder.decode([String: Date].self, from: data)
        }()

        let lastMessageReaction: ConversationLastMessageReaction? = {
            guard let data = lastMessageReactionData else { return nil }
            return try? decoder.decode(ConversationLastMessageReaction.self, from: data)
        }()

        var conversation = Conversation(
            id: id,
            participants: participants,
            lastMessage: lastMessage,
            timestamp: timestamp,
            readStatus: readStatus,
            otherParticipantId: otherParticipantId,
            otherParticipantUsername: otherParticipantUsername,
            otherParticipantProfileImagePath: otherParticipantProfileImagePath,
            isPinned: isPinned,
            isMuted: isMuted,
            archivedByUserIds: isArchived ? [Auth.auth().currentUser?.uid ?? ""].filter { !$0.isEmpty } : nil
        )
        conversation.readReceiptPreferences = readReceiptPreferences
        conversation.forwardingPreferences = forwardingPreferences
        conversation.lastDeletedAt = lastDeletedAt
        conversation.lastReadAt = lastReadAt
        conversation.lastMessageSenderId = lastMessageSenderId
        conversation.lastMessageSeenAt = lastMessageSeenAt
        conversation.lastMessageReaction = lastMessageReaction
        conversation.vanishModeActive = vanishModeActive
        return conversation
    }
}
