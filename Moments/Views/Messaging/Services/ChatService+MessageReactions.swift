import Foundation
import FirebaseFirestore

struct MessageReactionUpdate {
    let reactionsByMessage: [String: [String: [String]]]
    let changedMessageIds: Set<String>
}

extension ChatService {
    func listenToMessageReactions(
        conversationId: String,
        replaceExisting: Bool = true,
        completion: @escaping (Result<MessageReactionUpdate, Error>) -> Void
    ) {
        let listenerKey = "reactions_\(conversationId)"
        if !replaceExisting, activeListeners[listenerKey] != nil {
            return
        }
        let generation = beginListenerGeneration(for: listenerKey)
        activeListeners[listenerKey]?.remove()
        activeListeners[listenerKey] = nil

        let listener = db.collectionGroup("messageReactions")
            .whereField("conversationId", isEqualTo: conversationId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                guard self.isCurrentListenerGeneration(generation, for: listenerKey) else { return }

                if let error {
                    completion(.failure(error))
                    return
                }

                let docs = snapshot?.documents ?? []
                let changedMessageIds = Set(
                    snapshot?.documentChanges.compactMap { change in
                        change.document.data()["messageId"] as? String
                    } ?? []
                )
                completion(.success(
                    MessageReactionUpdate(
                        reactionsByMessage: self.aggregateReactionMap(from: docs),
                        changedMessageIds: changedMessageIds
                    )
                ))
            }

        activeListeners[listenerKey] = listener
    }

    func fetchReactionMap(
        conversationId: String,
        messageIds: [String]
    ) async -> [String: [String: [String]]] {
        let ids = Array(Set(messageIds.filter { !$0.isEmpty }))
        guard !ids.isEmpty else { return [:] }

        var aggregated: [String: [String: [String]]] = [:]
        for chunk in chunkMessageIds(ids, size: 10) {
            do {
                let snapshot = try await db.collectionGroup("messageReactions")
                    .whereField("conversationId", isEqualTo: conversationId)
                    .whereField("messageId", in: chunk)
                    .getDocuments()
                let partial = aggregateReactionMap(from: snapshot.documents)
                aggregated.merge(partial) { current, incoming in
                    mergeReactionBuckets(current: current, incoming: incoming)
                }
            } catch {
                continue
            }
        }

        return aggregated
    }

    func mergeLegacyAndLiveReactions(
        legacy: [String: [String]]?,
        live: [String: [String]]?
    ) -> [String: [String]]? {
        var merged = legacy ?? [:]

        for (emoji, userIds) in live ?? [:] {
            for userId in userIds {
                for key in Array(merged.keys) {
                    merged[key]?.removeAll { $0 == userId }
                    if merged[key]?.isEmpty == true {
                        merged.removeValue(forKey: key)
                    }
                }

                var updatedUserIds = merged[emoji] ?? []
                if !updatedUserIds.contains(userId) {
                    updatedUserIds.append(userId)
                }
                merged[emoji] = updatedUserIds
            }
        }

        return merged.isEmpty ? nil : merged
    }

    private func aggregateReactionMap(
        from documents: [QueryDocumentSnapshot]
    ) -> [String: [String: [String]]] {
        var map: [String: [String: [String]]] = [:]

        for document in documents {
            let data = document.data()
            guard
                let messageId = data["messageId"] as? String,
                !messageId.isEmpty,
                let emoji = data["emoji"] as? String,
                !emoji.isEmpty,
                let userId = data["userId"] as? String,
                !userId.isEmpty
            else {
                continue
            }

            var reactions = map[messageId] ?? [:]
            for key in Array(reactions.keys) {
                reactions[key]?.removeAll { $0 == userId }
                if reactions[key]?.isEmpty == true {
                    reactions.removeValue(forKey: key)
                }
            }

            var userIds = reactions[emoji] ?? []
            if !userIds.contains(userId) {
                userIds.append(userId)
            }
            reactions[emoji] = userIds
            map[messageId] = reactions
        }

        return map
    }

    private func mergeReactionBuckets(
        current: [String: [String]],
        incoming: [String: [String]]
    ) -> [String: [String]] {
        mergeLegacyAndLiveReactions(legacy: current, live: incoming) ?? incoming
    }

    private func chunkMessageIds(_ ids: [String], size: Int) -> [[String]] {
        guard size > 0, !ids.isEmpty else { return ids.isEmpty ? [] : [ids] }

        var chunks: [[String]] = []
        var index = 0
        while index < ids.count {
            let end = Swift.min(index + size, ids.count)
            chunks.append(Array(ids[index..<end]))
            index += size
        }
        return chunks
    }
}
