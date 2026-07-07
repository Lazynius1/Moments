import Foundation
import FirebaseFirestore

extension ChatService {
    // MARK: - Reenviar (solo texto, recifrado E2E por destino)

    func forwardTextMessage(
        plaintext: String,
        destinationConversationId: String,
        senderId: String,
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        let trimmed = plaintext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty forward content"])))
            return
        }

        Task {
            let encryptedContent = await encryptMessageContent(trimmed, for: destinationConversationId)
            let messageId = UUID().uuidString
            let message = EnhancedMessage(
                id: messageId,
                conversationId: destinationConversationId,
                senderId: senderId,
                type: .text,
                content: encryptedContent,
                timestamp: Date(),
                status: .sending,
                isRead: false,
                isDeleted: false,
                isViewed: false,
                isForwarded: true
            )

            sendMessage(message, useServerTimestamp: true) { result in
                switch result {
                case .success(let sentMessage):
                    self.updateConversation(
                        conversationId: destinationConversationId,
                        lastMessage: self.neutralConversationPreview(for: .text),
                        senderId: senderId,
                        messageType: .text
                    ) { _ in
                        completion(.success(sentMessage))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func forwardTextMessage(
        plaintext: String,
        toUserIds: Set<String>,
        senderId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard !toUserIds.isEmpty else {
            completion(.success(()))
            return
        }

        let group = DispatchGroup()
        var lastError: Error?

        for userId in toUserIds {
            group.enter()
            getOrCreateConversation(between: senderId, and: userId) { [weak self] result in
                guard let self else {
                    group.leave()
                    return
                }
                switch result {
                case .success(let conversationId):
                    self.forwardTextMessage(
                        plaintext: plaintext,
                        destinationConversationId: conversationId,
                        senderId: senderId
                    ) { forwardResult in
                        if case .failure(let error) = forwardResult {
                            lastError = error
                        }
                        group.leave()
                    }
                case .failure(let error):
                    lastError = error
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            if let lastError {
                completion(.failure(lastError))
            } else {
                completion(.success(()))
            }
        }
    }

    // MARK: - Destacar

    func toggleMessageStar(
        conversationId: String,
        messageId: String,
        userId: String,
        isStarred: Bool,
        completion: @escaping (Error?) -> Void
    ) {
        let fieldUpdate: [String: Any] = isStarred
            ? ["starredBy": FieldValue.arrayUnion([userId])]
            : ["starredBy": FieldValue.arrayRemove([userId])]

        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData(fieldUpdate, completion: completion)
    }
}
