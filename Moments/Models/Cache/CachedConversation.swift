import Foundation
import SwiftData

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
    var readReceiptPreferencesData: Data? // [String: Bool] encoded
    var lastSyncedAt: Date
    
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
         readReceiptPreferencesData: Data? = nil,
         lastSyncedAt: Date = Date()) {
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
        self.readReceiptPreferencesData = readReceiptPreferencesData
        self.lastSyncedAt = lastSyncedAt
    }
}

extension CachedConversation {
    static func from(_ conversation: Conversation) -> CachedConversation {
        let encoder = JSONEncoder()
        let readStatusData = try? encoder.encode(conversation.readStatus)
        let readReceiptPreferencesData = try? encoder.encode(conversation.readReceiptPreferences)
        
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
            readReceiptPreferencesData: readReceiptPreferencesData,
            lastSyncedAt: Date()
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
            isMuted: isMuted
        )
        conversation.readReceiptPreferences = readReceiptPreferences
        return conversation
    }
}
