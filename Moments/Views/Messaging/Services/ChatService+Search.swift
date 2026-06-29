import Foundation
import FirebaseFirestore

extension ChatService {
    private static let remoteSearchBatchSize = 200
    private static let remoteSearchMaxMatches = 100

    func searchMessages(
        conversationId: String,
        query: String,
        excludingIds: Set<String> = [],
        limit: Int = remoteSearchMaxMatches,
        completion: @escaping (Result<[EnhancedMessage], Error>) -> Void
    ) {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !normalizedQuery.isEmpty else {
            completion(.success([]))
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await preloadConversationKey(for: conversationId)

            var matchingMessages: [EnhancedMessage] = []
            var lastDocument: DocumentSnapshot?
            var hasMore = true

            while hasMore, matchingMessages.count < limit {
                do {
                    var firestoreQuery = db.collection("conversations")
                        .document(conversationId)
                        .collection("messages")
                        .order(by: "timestamp", descending: true)
                        .limit(to: Self.remoteSearchBatchSize)

                    if let lastDocument {
                        firestoreQuery = firestoreQuery.start(afterDocument: lastDocument)
                    }

                    let snapshot = try await firestoreQuery.getDocuments()
                    guard !snapshot.documents.isEmpty else {
                        hasMore = false
                        break
                    }

                    lastDocument = snapshot.documents.last
                    hasMore = snapshot.documents.count >= Self.remoteSearchBatchSize

                    for doc in snapshot.documents {
                        let data = doc.data()
                        guard data["type"] as? String == MessageType.text.rawValue else { continue }
                        guard data["isDeleted"] as? Bool != true else { continue }

                        let docId = doc.documentID
                        if excludingIds.contains(docId) { continue }

                        guard let encryptedContent = data["content"] as? String else { continue }
                        let decryptedContent = await decryptMessageContent(encryptedContent, for: conversationId)
                        let searchable = decryptedContent
                            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        guard searchable.contains(normalizedQuery) else { continue }

                        let message = await buildEnhancedMessage(
                            from: data,
                            docId: docId,
                            conversationId: conversationId,
                            decryptedContentOverride: decryptedContent
                        )
                        matchingMessages.append(message)
                        if matchingMessages.count >= limit { break }
                    }
                } catch {
                    await MainActor.run {
                        completion(.failure(error))
                    }
                    return
                }
            }

            let sorted = matchingMessages.sorted { $0.timestamp < $1.timestamp }
            await MainActor.run {
                completion(.success(sorted))
            }
        }
    }
}
