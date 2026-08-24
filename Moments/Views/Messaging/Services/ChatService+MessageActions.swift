import Foundation
import FirebaseFirestore

struct DirectRecipientSendResult: Identifiable, Hashable {
    enum Outcome: String, Hashable {
        case conversation
        case request
        case denied
        case failed
    }

    let id: String
    let outcome: Outcome
    let errorDescription: String?
}

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
            let encryptedContent: String
            do {
                encryptedContent = try await encryptMessageContent(trimmed, for: destinationConversationId)
            } catch {
                completion(.failure(error))
                return
            }
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
        completion: @escaping ([DirectRecipientSendResult]) -> Void
    ) {
        guard !toUserIds.isEmpty else {
            completion([])
            return
        }

        Task { @MainActor in
            let coordinator = MessageRequestService()
            var results: [DirectRecipientSendResult] = []
            for userId in toUserIds.sorted() {
                guard !userId.isEmpty else {
                    results.append(DirectRecipientSendResult(id: userId, outcome: .denied, errorDescription: "INVALID_RECIPIENT"))
                    continue
                }
                do {
                    let route = try await coordinator.resolveRoute(
                        to: userId,
                        interaction: MessageRequestInteractionContext(kind: .forwardText)
                    )
                    switch route {
                    case .conversation(let conversationId):
                        try await self.forwardText(
                            plaintext: plaintext,
                            destinationConversationId: conversationId,
                            senderId: senderId
                        )
                        results.append(DirectRecipientSendResult(id: userId, outcome: .conversation, errorDescription: nil))
                    case .conversationDraft(let threadId):
                        let conversationId = try await coordinator.activateConversationDraft(
                            to: userId,
                            threadId: threadId
                        )
                        try await self.forwardText(
                            plaintext: plaintext,
                            destinationConversationId: conversationId,
                            senderId: senderId
                        )
                        results.append(DirectRecipientSendResult(id: userId, outcome: .conversation, errorDescription: nil))
                    case .outgoingRequest:
                        _ = try await coordinator.appendRequestMessage(
                            to: userId,
                            text: plaintext,
                            interaction: MessageRequestInteractionContext(kind: .forwardText)
                        )
                        results.append(DirectRecipientSendResult(id: userId, outcome: .request, errorDescription: nil))
                    case .incomingRequest(let threadId, _):
                        let accepted = try await coordinator.acceptIncomingThread(threadId: threadId)
                        try await self.forwardText(
                            plaintext: plaintext,
                            destinationConversationId: accepted.conversationId,
                            senderId: senderId
                        )
                        results.append(DirectRecipientSendResult(id: userId, outcome: .conversation, errorDescription: nil))
                    }
                } catch {
                    let outcome: DirectRecipientSendResult.Outcome = (error as NSError).code == 403 ? .denied : .failed
                    results.append(DirectRecipientSendResult(
                        id: userId,
                        outcome: outcome,
                        errorDescription: error.localizedDescription
                    ))
                }
            }
            completion(results)
        }
    }

    private func forwardText(
        plaintext: String,
        destinationConversationId: String,
        senderId: String
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            forwardTextMessage(
                plaintext: plaintext,
                destinationConversationId: destinationConversationId,
                senderId: senderId
            ) { result in
                continuation.resume(with: result.map { _ in () })
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
