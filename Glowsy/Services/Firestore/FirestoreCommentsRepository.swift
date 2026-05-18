import FirebaseAuth
import FirebaseFirestore
import Foundation

extension FirestoreService {
    func fetchComments(for momentId: String, userId: String, limit: Int = 10, lastDocument: DocumentSnapshot? = nil, completion: @escaping (Result<(comments: [Comment], lastDocument: DocumentSnapshot?), Error>) -> Void) {
        var query = db.collection("users").document(userId).collection("moments").document(momentId).collection("comments")
            .order(by: "timestamp", descending: false)
            .limit(to: limit)

        if let lastDocument = lastDocument {
            query = query.start(afterDocument: lastDocument)
        }

        query.getDocuments { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            let comments = snapshot?.documents.compactMap { document -> Comment? in
                let data = document.data()
                guard let authorId = data["authorId"] as? String,
                      let username = data["username"] as? String,
                      let content = data["content"] as? String,
                      let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                    return nil
                }

                let profileImagePath = data["profileImagePath"] as? String
                let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                let reactions = data["reactions"] as? [String: [String]] ?? [:]
                let parentCommentId = data["parentCommentId"] as? String
                let isEdited = data["isEdited"] as? Bool ?? false
                let editedTimestamp = (data["editedTimestamp"] as? Timestamp)?.dateValue()

                return Comment(
                    id: document.documentID,
                    authorId: authorId,
                    username: username,
                    content: content,
                    timestamp: timestamp,
                    profileImagePath: profileImagePath,
                    updatedAt: updatedAt,
                    reactions: reactions,
                    parentCommentId: parentCommentId,
                    isEdited: isEdited,
                    editedTimestamp: editedTimestamp
                )
            }.filter { $0.id != nil } ?? []

            let lastDoc = snapshot?.documents.last
            completion(.success((comments: comments, lastDocument: lastDoc)))
        }
    }

    func addComment(to momentId: String, userId: String, authorId: String, content: String, parentCommentId: String? = nil, commentId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        let commentId = commentId ?? UUID().uuidString

        if !NetworkMonitor.shared.isConnected {
            let payload = CommentPayload(
                momentId: momentId,
                authorId: userId,
                senderId: authorId,
                content: content,
                parentCommentId: parentCommentId,
                commentId: commentId
            )

            if let data = try? JSONEncoder().encode(payload) {
                let action = CachedAction(
                    id: UUID().uuidString,
                    type: CachedAction.ActionType.comment.rawValue,
                    payloadData: data
                )

                Task {
                    await LocalPersistenceService.shared.saveAction(action)
                    await MainActor.run {
                        LocalPersistenceService.shared.updateCommentCountLocally(momentId: momentId, increment: 1)
                    }
                    print("💾 FirestoreService: Comentario guardado en outbox (offline)")
                    completion(.success(()))
                }
                return
            }
        }

        let now = Date()

        fetchUser(userId: authorId) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let user):
                Task(priority: .background) { @MainActor in
                    LocalPersistenceService.shared.updateCommentCountLocally(momentId: momentId, increment: 1)
                }

                var commentData: [String: Any] = [
                    "authorId": authorId,
                    "username": user.username,
                    "content": content,
                    "text": content,
                    "timestamp": Timestamp(date: now),
                    "profileImagePath": user.profileImagePath ?? NSNull(),
                    "updatedAt": NSNull(),
                    "reactions": [:] as [String: [String]],
                    "isEdited": false,
                    "editedTimestamp": NSNull()
                ]

                if let parentCommentId = parentCommentId {
                    commentData["parentCommentId"] = parentCommentId
                } else {
                    commentData["parentCommentId"] = NSNull()
                }

                let batch = self.db.batch()
                let commentRef = self.db.collection("users").document(userId).collection("moments").document(momentId).collection("comments").document(commentId)
                batch.setData(commentData, forDocument: commentRef)

                let momentRef = self.db.collection("users").document(userId).collection("moments").document(momentId)
                batch.updateData([
                    "commentCount": FieldValue.increment(Int64(1))
                ], forDocument: momentRef)

                batch.commit { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))

                        if let parentCommentId = parentCommentId {
                            self.notifyCommentReply(
                                parentCommentId: parentCommentId,
                                momentId: momentId,
                                momentAuthorId: userId,
                                fromUserId: authorId,
                                fromUsername: user.username,
                                content: content
                            )
                        }

                        let mentions = self.extractMentions(from: content)
                        self.handleMentions(mentions, momentId: momentId, fromUserId: authorId, fromUsername: user.username, content: content)
                    }
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func updateComment(momentId: String, userId: String, commentId: String, content: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let commentRef = db.collection("users").document(userId).collection("moments").document(momentId).collection("comments").document(commentId)

        commentRef.updateData([
            "content": content,
            "isEdited": true,
            "editedTimestamp": Timestamp(date: Date())
        ]) { [weak self] error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))

                let mentions = self?.extractMentions(from: content) ?? []
                if !mentions.isEmpty {
                    let currentUserId = Auth.auth().currentUser?.uid ?? ""
                    self?.fetchUserProfile(userId: currentUserId) { result in
                        if case .success(let user) = result {
                            self?.handleMentions(mentions, momentId: momentId, fromUserId: currentUserId, fromUsername: user.username, content: content)
                        } else {
                            self?.handleMentions(mentions, momentId: momentId, fromUserId: currentUserId, fromUsername: "Alguien", content: content)
                        }
                    }
                }
            }
        }
    }

    func deleteComment(to momentId: String, commentId: String, userId: String, authorId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Task(priority: .background) { @MainActor in
            LocalPersistenceService.shared.updateCommentCountLocally(momentId: momentId, increment: -1)
        }

        if !NetworkMonitor.shared.isConnected {
            let payload = DeleteCommentPayload(
                momentId: momentId,
                commentId: commentId,
                userId: userId,
                authorId: authorId
            )

            if let data = try? JSONEncoder().encode(payload) {
                let action = CachedAction(
                    id: UUID().uuidString,
                    type: CachedAction.ActionType.deleteComment.rawValue,
                    payloadData: data
                )

                Task {
                    await LocalPersistenceService.shared.saveAction(action)
                    print("💾 FirestoreService: Borrado de comentario guardado en outbox (offline)")
                    completion(.success(()))
                }
                return
            }
        }

        let batch = db.batch()
        let commentRef = db.collection("users").document(userId).collection("moments").document(momentId).collection("comments").document(commentId)

        commentRef.getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard snapshot?.exists == true else {
                completion(.failure(NSError(domain: "CommentNotFound", code: 404, userInfo: [NSLocalizedDescriptionKey: "Comment not found"])))
                return
            }

            batch.deleteDocument(commentRef)

            let momentRef = self.db.collection("users").document(userId).collection("moments").document(momentId)
            batch.updateData([
                "commentCount": FieldValue.increment(Int64(-1))
            ], forDocument: momentRef)

            self.db.collection("users").document(userId).collection("moments").document(momentId).collection("comments")
                .whereField("parentCommentId", isEqualTo: commentId)
                .getDocuments { nestedSnapshot, _ in
                    let nestedDocs = nestedSnapshot?.documents ?? []

                    for nestedDoc in nestedDocs {
                        batch.deleteDocument(nestedDoc.reference)
                        batch.updateData([
                            "commentCount": FieldValue.increment(Int64(-1))
                        ], forDocument: momentRef)

                        if let replyAuthorId = nestedDoc.data()["authorId"] as? String {
                            Task { @MainActor in
                                NotificationService.shared.removeNotification(
                                    type: .comment,
                                    senderId: replyAuthorId,
                                    recipientId: authorId,
                                    momentId: momentId,
                                    commentId: nestedDoc.documentID
                                )
                            }
                        }
                    }

                    batch.commit { batchError in
                        if let batchError = batchError {
                            completion(.failure(batchError))
                        } else {
                            Task { @MainActor in
                                NotificationService.shared.removeNotification(
                                    type: .comment,
                                    senderId: authorId,
                                    recipientId: userId,
                                    momentId: momentId,
                                    commentId: commentId
                                )
                            }
                            completion(.success(()))
                        }
                    }
                }
        }
    }

    func addCommentReaction(to momentId: String, commentId: String, reaction: String, userId: String, authorId: String, completion: @escaping (Error?) -> Void) {
        let commentRef = db.collection("users").document(userId).collection("moments").document(momentId).collection("comments").document(commentId)

        commentRef.getDocument { snapshot, error in
            if let error = error {
                completion(error)
                return
            }

            guard let data = snapshot?.data(),
                  var reactions = data["reactions"] as? [String: [String]] else {
                let initialReactions = [reaction: [Auth.auth().currentUser?.uid ?? ""]]
                commentRef.updateData(["reactions": initialReactions]) { error in
                    if let error = error {
                        completion(error)
                    } else {
                        self.sendCommentReactionNotification(
                            to: authorId,
                            from: Auth.auth().currentUser?.uid ?? "",
                            momentId: momentId,
                            commentId: commentId,
                            reaction: reaction
                        )
                        completion(nil)
                    }
                }
                return
            }

            let currentUserId = Auth.auth().currentUser?.uid ?? ""
            var reactionUsers = reactions[reaction] ?? []
            let wasLiked = reactionUsers.contains(currentUserId)

            if wasLiked {
                reactionUsers.removeAll { $0 == currentUserId }
            } else {
                reactionUsers.append(currentUserId)

                if authorId != currentUserId {
                    self.sendCommentReactionNotification(
                        to: authorId,
                        from: currentUserId,
                        momentId: momentId,
                        commentId: commentId,
                        reaction: reaction
                    )
                }
            }

            reactions[reaction] = reactionUsers

            let updateData: [String: Any] = [
                "reactions": reactions,
                "metadata.lastReactionTimestamp": Timestamp(date: Date()),
                "metadata.totalReactions": reactions.values.map { $0.count }.reduce(0, +)
            ]

            commentRef.updateData(updateData) { error in
                if let error = error {
                    completion(error)
                } else {
                    completion(nil)
                }
            }
        }
    }

    func getCommentReactionStats(momentId: String, userId: String, commentId: String, completion: @escaping (Result<[String: Int], Error>) -> Void) {
        let commentRef = db.collection("users").document(userId).collection("moments").document(momentId).collection("comments").document(commentId)

        commentRef.getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = snapshot?.data(),
                  let reactions = data["reactions"] as? [String: [String]] else {
                completion(.success([:]))
                return
            }

            var stats: [String: Int] = [:]
            for (reaction, users) in reactions {
                stats[reaction] = users.count
            }

            completion(.success(stats))
        }
    }

    func hasUserReactedToComment(momentId: String, userId: String, commentId: String, reaction: String, completion: @escaping (Bool) -> Void) {
        let commentRef = db.collection("users").document(userId).collection("moments").document(momentId).collection("comments").document(commentId)
        let currentUserId = Auth.auth().currentUser?.uid ?? ""

        commentRef.getDocument { snapshot, error in
            if error != nil {
                completion(false)
                return
            }

            guard let data = snapshot?.data(),
                  let reactions = data["reactions"] as? [String: [String]],
                  let reactionUsers = reactions[reaction] else {
                completion(false)
                return
            }

            completion(reactionUsers.contains(currentUserId))
        }
    }

    private func notifyCommentReply(parentCommentId: String, momentId: String, momentAuthorId: String, fromUserId: String, fromUsername: String, content: String) {
        db.collection("users").document(momentAuthorId).collection("moments").document(momentId).collection("comments").document(parentCommentId).getDocument { snapshot, _ in
            guard let data = snapshot?.data(),
                  let parentAuthorId = data["authorId"] as? String else { return }

            Task { @MainActor in
                NotificationService.shared.sendInteractionNotification(
                    type: .comment,
                    to: parentAuthorId,
                    momentId: momentId,
                    commentId: parentCommentId,
                    reaction: content,
                    senderUsername: fromUsername
                )
            }
        }
    }

    private func extractMentions(from text: String) -> [String] {
        let pattern = #"@(\w+)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex?.matches(in: text, range: range) ?? []

        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private func handleMentions(_ mentions: [String], momentId: String, fromUserId: String, fromUsername: String, content: String) {
        for mention in mentions {
            db.collection("users").whereField("username", isEqualTo: mention.lowercased()).getDocuments(source: .default) { snapshot, _ in
                guard let documents = snapshot?.documents, let userDoc = documents.first else { return }

                let mentionedUserId = userDoc.documentID
                Task { @MainActor in
                    NotificationService.shared.sendInteractionNotification(
                        type: .mention,
                        to: mentionedUserId,
                        momentId: momentId,
                        reaction: content,
                        senderUsername: fromUsername
                    )
                }
            }
        }
    }

    private func sendCommentReactionNotification(to recipientId: String, from senderId: String, momentId: String, commentId: String, reaction: String) {
        guard recipientId != senderId else { return }

        fetchUser(userId: senderId) { result in
            switch result {
            case .success(let user):
                Task { @MainActor in
                    NotificationService.shared.sendInteractionNotification(
                        type: .like,
                        to: recipientId,
                        momentId: momentId,
                        commentId: commentId,
                        reaction: reaction,
                        senderUsername: user.username
                    )
                }

            case .failure:
                break
            }
        }
    }
}
