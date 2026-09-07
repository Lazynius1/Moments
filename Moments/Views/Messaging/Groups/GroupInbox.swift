import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class GroupDirectory: ObservableObject {
    static let shared = GroupDirectory()
    @Published var groups: [String: GroupConversation] = [:]
    var userId: String?
    func replace(_ snapshots: [QueryDocumentSnapshot], userId: String) {
        self.userId = userId
        groups = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.documentID, GroupConversation($0)) })
    }
}

@MainActor
private final class GroupInboxMerge {
    var direct: [Conversation] = []
    var groups: [Conversation] = []
    let userId: String
    let completion: (Result<[Conversation], Error>) -> Void
    init(userId: String, completion: @escaping (Result<[Conversation], Error>) -> Void) { self.userId = userId; self.completion = completion }
    func publish() {
        guard Auth.auth().currentUser?.uid == userId else { return }
        completion(.success((direct + groups).sorted { $0.timestamp > $1.timestamp }))
    }
}

extension ChatService {
    func fetchConversations(for userId: String, completion: @escaping (Result<[Conversation], Error>) -> Void) {
        let merge = GroupInboxMerge(userId: userId, completion: completion)
        for key in activeListeners.keys.filter({ $0.hasPrefix("group_conversations_") }) { activeListeners.removeValue(forKey: key)?.remove() }
        let key = "group_conversations_\(userId)"
        var revision = 0
        activeListeners[key] = db.collection("groupConversations").whereField("participants", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, Auth.auth().currentUser?.uid == userId else { return }
                    guard let snapshot, error == nil else { if let error { completion(.failure(error)) }; return }
                    revision += 1; let currentRevision = revision
                    GroupDirectory.shared.replace(snapshot.documents, userId: userId)
                    let groups = snapshot.documents.compactMap { self.groupConversation($0, userId: userId) }
                    let hydrated = await self.hydrateConversationPreviews(groups)
                    guard currentRevision == revision, Auth.auth().currentUser?.uid == userId else { return }
                    merge.groups = hydrated
                    merge.publish()
                }
            }
        fetchDirectConversations(for: userId) { result in
            switch result {
            case .success(let conversations): merge.direct = conversations; merge.publish()
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    func groupConversation(_ doc: DocumentSnapshot, userId: String) -> Conversation? {
        guard GroupChatScope.isGroup(doc.documentID), let data = doc.data(),
              let participants = data["participants"] as? [String], participants.contains(userId) else { return nil }
        let date = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
        let cutoffs = (data["lastDeletedAt"] as? [String: Timestamp] ?? [:]).mapValues { $0.dateValue() }
        if (data["deletedFor"] as? [String] ?? []).contains(userId), date <= (cutoffs[userId] ?? .distantFuture) { return nil }
        let keys = (data["wrappedKeys"] as? [String: [String: Any]] ?? [:]).compactMapValues(WrappedConversationKey.init(map:))
        var conversation = Conversation(id: doc.documentID, participants: participants, lastMessage: "", timestamp: date,
            readStatus: data["readStatus"] as? [String: Bool] ?? [:], otherParticipantId: doc.documentID,
            otherParticipantUsername: data["groupName"] as? String, otherParticipantProfileImagePath: nil,
            pinnedByUserIds: data["pinnedByUserIds"] as? [String], mutedByUserIds: data["mutedByUserIds"] as? [String],
            archivedByUserIds: data["archivedByUserIds"] as? [String], encryptionVersion: "3.0",
            conversationKeyVersion: data["conversationKeyVersion"] as? Int, wrappedKeys: keys)
        conversation.lastDeletedAt = cutoffs
        conversation.lastReadAt = (data["lastReadAt"] as? [String: Timestamp] ?? [:]).mapValues { $0.dateValue() }
        conversation.lastMessageSeenAt = (data["lastMessageSeenAt"] as? [String: Timestamp] ?? [:]).mapValues { $0.dateValue() }
        conversation.lastMessageSenderId = data["lastMessageSenderId"] as? String
        conversation.lastMessageType = (data["lastMessageType"] as? String).flatMap(MessageType.init(rawValue:))
        conversation.forwardingPreferences = data["forwardingPreferences"] as? [String: Bool]
        conversation.readReceiptPreferences = data["readReceiptPreferences"] as? [String: Bool]
        conversation.vanishModeActive = false; conversation.buzzPreferences = Dictionary(uniqueKeysWithValues: participants.map { ($0, false) })
        return conversation
    }
}
