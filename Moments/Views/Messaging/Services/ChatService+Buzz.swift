import Foundation
import FirebaseFirestore

struct ChatBuzzEvent: Identifiable, Equatable {
    let id: String
    let conversationId: String
    let senderId: String
    let createdAt: Date
}

extension ChatService {
    func sendBuzz(
        conversationId: String,
        senderId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let eventRef = db.collection("conversations")
            .document(conversationId)
            .collection("buzzEvents")
            .document()

        let now = Date()
        eventRef.setData([
            "senderId": senderId,
            "type": "buzz",
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: now.addingTimeInterval(30)),
            "intensity": "normal",
            "clientNonce": UUID().uuidString
        ]) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func listenToBuzzEvents(
        conversationId: String,
        limit: Int = 80,
        onEvent: @escaping (_ event: ChatBuzzEvent, _ isInitialSnapshot: Bool) -> Void
    ) {
        let listenerKey = "buzz_\(conversationId)"
        activeListeners[listenerKey]?.remove()
        var hasDeliveredInitialSnapshot = false

        let query = db.collection("conversations")
            .document(conversationId)
            .collection("buzzEvents")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        activeListeners[listenerKey] = query.addSnapshotListener { snapshot, error in
            guard error == nil, let changes = snapshot?.documentChanges else { return }
            let isInitialSnapshot = !hasDeliveredInitialSnapshot

            for change in changes where change.type == .added {
                let data = change.document.data()
                guard data["type"] as? String == "buzz",
                      let senderId = data["senderId"] as? String else {
                    continue
                }

                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()

                onEvent(ChatBuzzEvent(
                    id: change.document.documentID,
                    conversationId: conversationId,
                    senderId: senderId,
                    createdAt: createdAt
                ), isInitialSnapshot)
            }

            hasDeliveredInitialSnapshot = true
        }
    }
}
