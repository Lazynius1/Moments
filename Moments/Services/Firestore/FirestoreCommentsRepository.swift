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
                let mentions = Self.decodeCommentMentions(from: data["mentions"])

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
                    editedTimestamp: editedTimestamp,
                    mentions: mentions
                )
            }.filter { $0.id != nil } ?? []

            let lastDoc = snapshot?.documents.last
            completion(.success((comments: comments, lastDocument: lastDoc)))
        }
    }

    func addComment(to momentId: String, userId: String, authorId: String, content: String, parentCommentId: String? = nil, commentId: String? = nil, mentions: [CommentMentionEntity]? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        let commentId = commentId ?? UUID().uuidString
        let usesValidatedMentions = mentions != nil
        let sanitizedMentions = sanitizeCommentMentions(mentions ?? [], in: content)

        if !NetworkMonitor.shared.isConnected {
            let payload = CommentPayload(
                momentId: momentId,
                authorId: userId,
                senderId: authorId,
                content: content,
                parentCommentId: parentCommentId,
                commentId: commentId,
                mentions: sanitizedMentions
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
                    "editedTimestamp": NSNull(),
                    "mentions": sanitizedMentions.map(commentMentionData)
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

                        let sendMentions: (String?, Set<String>) -> Void = { momentAuthorUsername, excludedUserIds in
                            if usesValidatedMentions {
                                self.handleMentions(
                                    sanitizedMentions,
                                    momentId: momentId,
                                    momentAuthorId: userId,
                                    momentAuthorUsername: momentAuthorUsername,
                                    commentId: commentId,
                                    fromUserId: authorId,
                                    fromUsername: user.username,
                                    content: content,
                                    excludedUserIds: excludedUserIds
                                )
                            } else {
                                self.handleMentions(
                                    self.extractMentions(from: content),
                                    momentId: momentId,
                                    momentAuthorId: userId,
                                    momentAuthorUsername: momentAuthorUsername,
                                    commentId: commentId,
                                    fromUserId: authorId,
                                    fromUsername: user.username,
                                    content: content,
                                    excludedUserIds: excludedUserIds
                                )
                            }
                        }

                        if let parentCommentId = parentCommentId {
                            self.notifyCommentReply(
                                parentCommentId: parentCommentId,
                                replyCommentId: commentId,
                                momentId: momentId,
                                momentAuthorId: userId,
                                fromUserId: authorId,
                                fromUsername: user.username,
                                content: content
                            ) { parentAuthorId, momentAuthorUsername in
                                var excludedUserIds = Set([authorId])
                                if let parentAuthorId {
                                    excludedUserIds.insert(parentAuthorId)
                                }
                                sendMentions(momentAuthorUsername, excludedUserIds)
                            }
                        } else {
                            self.fetchUsername(userId: userId) { momentAuthorUsername in
                                sendMentions(momentAuthorUsername, Set([authorId]))
                            }
                        }
                    }
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func updateComment(momentId: String, userId: String, commentId: String, content: String, mentions: [CommentMentionEntity]? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        let commentRef = db.collection("users").document(userId).collection("moments").document(momentId).collection("comments").document(commentId)

        commentRef.getDocument { [weak self] snapshot, _ in
            let usesValidatedMentions = mentions != nil
            let previousContent = snapshot?.data()?["content"] as? String ?? ""
            let previousEntities = Self.decodeCommentMentions(from: snapshot?.data()?["mentions"])
            let previousMentionUserIds = Set(previousEntities.map(\.userId))
            let previousMentions = Set(self?.extractMentions(from: previousContent).map { $0.lowercased() } ?? [])
            let sanitizedMentions = self?.sanitizeCommentMentions(mentions ?? [], in: content) ?? []

            commentRef.updateData([
                "content": content,
                "isEdited": true,
                "editedTimestamp": Timestamp(date: Date()),
                "mentions": sanitizedMentions.map { self?.commentMentionData($0) ?? [:] }
            ]) { [weak self] error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))

                    let mentionsToNotify = sanitizedMentions.filter { !previousMentionUserIds.contains($0.userId) }
                    let regexMentions = self?.extractMentions(from: content) ?? []
                    let newRegexMentions = regexMentions.filter { !previousMentions.contains($0.lowercased()) }

                    if !mentionsToNotify.isEmpty || (!usesValidatedMentions && !regexMentions.isEmpty && sanitizedMentions.isEmpty && !newRegexMentions.isEmpty) {
                        let currentUserId = Auth.auth().currentUser?.uid ?? ""
                        self?.fetchUserProfile(userId: currentUserId) { result in
                            let senderUsername: String
                            if case .success(let user) = result {
                                senderUsername = user.username
                            } else {
                                senderUsername = "Alguien"
                            }

                            if !mentionsToNotify.isEmpty {
                                self?.handleMentions(
                                    mentionsToNotify,
                                    momentId: momentId,
                                    momentAuthorId: userId,
                                    momentAuthorUsername: nil,
                                    commentId: commentId,
                                    fromUserId: currentUserId,
                                    fromUsername: senderUsername,
                                    content: content,
                                    excludedUserIds: Set([currentUserId])
                                )
                            } else if !usesValidatedMentions {
                                self?.handleMentions(
                                    newRegexMentions,
                                    momentId: momentId,
                                    momentAuthorId: userId,
                                    momentAuthorUsername: nil,
                                    commentId: commentId,
                                    fromUserId: currentUserId,
                                    fromUsername: senderUsername,
                                    content: content,
                                    excludedUserIds: Set([currentUserId])
                                )
                            }
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

                // Al deshacer la reacción del comentario, borramos la notificación
                // para que no quede huérfana en el destinatario.
                if authorId != currentUserId {
                    Task { @MainActor in
                        NotificationService.shared.removeNotification(
                            type: .like,
                            senderId: currentUserId,
                            recipientId: authorId,
                            momentId: momentId,
                            commentId: commentId,
                            reaction: reaction
                        )
                    }
                }
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

    private func notifyCommentReply(
        parentCommentId: String,
        replyCommentId: String,
        momentId: String,
        momentAuthorId: String,
        fromUserId: String,
        fromUsername: String,
        content: String,
        completion: @escaping (String?, String?) -> Void
    ) {
        db.collection("users").document(momentAuthorId).collection("moments").document(momentId).collection("comments").document(parentCommentId).getDocument { snapshot, _ in
            guard let data = snapshot?.data(),
                  let parentAuthorId = data["authorId"] as? String else {
                completion(nil, nil)
                return
            }

            self.fetchUsername(userId: momentAuthorId) { momentAuthorUsername in
                completion(parentAuthorId, momentAuthorUsername)

                self.canUserViewMoment(momentId: momentId, momentAuthorId: momentAuthorId, viewerId: parentAuthorId) { canView in
                    guard canView else { return }

                    Task { @MainActor in
                        NotificationService.shared.sendInteractionNotification(
                            type: .comment,
                            to: parentAuthorId,
                            momentId: momentId,
                            commentId: replyCommentId,
                            reaction: content,
                            senderUsername: fromUsername,
                            mentionContext: "reply",
                            targetAuthorId: momentAuthorId,
                            targetAuthorUsername: momentAuthorUsername
                        )
                    }
                }
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

    private static func decodeCommentMentions(from value: Any?) -> [CommentMentionEntity] {
        guard let rawMentions = value as? [[String: Any]] else { return [] }

        return rawMentions.compactMap { data in
            guard let userId = data["userId"] as? String,
                  let username = data["username"] as? String else { return nil }

            let rangeStart = data["rangeStart"] as? Int ?? 0
            let rangeLength = data["rangeLength"] as? Int ?? 0
            return CommentMentionEntity(
                userId: userId,
                username: username,
                rangeStart: rangeStart,
                rangeLength: rangeLength
            )
        }
    }

    private func commentMentionData(_ mention: CommentMentionEntity) -> [String: Any] {
        [
            "userId": mention.userId,
            "username": mention.username,
            "rangeStart": mention.rangeStart,
            "rangeLength": mention.rangeLength
        ]
    }

    private func sanitizeCommentMentions(_ mentions: [CommentMentionEntity], in text: String) -> [CommentMentionEntity] {
        var seenUserIds = Set<String>()
        var sanitized: [CommentMentionEntity] = []

        for mention in mentions {
            guard !seenUserIds.contains(mention.userId),
                  let range = text.range(of: "@\(mention.username)", options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }

            seenUserIds.insert(mention.userId)
            let rangeStart = text.distance(from: text.startIndex, to: range.lowerBound)
            let rangeLength = text.distance(from: range.lowerBound, to: range.upperBound)
            sanitized.append(
                CommentMentionEntity(
                    userId: mention.userId,
                    username: mention.username,
                    rangeStart: rangeStart,
                    rangeLength: rangeLength
                )
            )
        }

        return sanitized
    }

    private func handleMentions(
        _ mentions: [String],
        momentId: String,
        momentAuthorId: String,
        momentAuthorUsername: String?,
        commentId: String,
        fromUserId: String,
        fromUsername: String,
        content: String,
        excludedUserIds: Set<String>
    ) {
        for mention in Set(mentions.map { $0.lowercased() }) {
            db.collection("users").whereField("username", isEqualTo: mention.lowercased()).getDocuments(source: .default) { snapshot, _ in
                guard let documents = snapshot?.documents, let userDoc = documents.first else { return }

                let mentionedUserId = userDoc.documentID
                guard !excludedUserIds.contains(mentionedUserId) else { return }

                self.canUserViewMoment(momentId: momentId, momentAuthorId: momentAuthorId, viewerId: mentionedUserId) { canView in
                    guard canView else { return }

                    Task { @MainActor in
                        NotificationService.shared.sendCommentMentionNotification(
                            to: mentionedUserId,
                            momentId: momentId,
                            momentAuthorId: momentAuthorId,
                            momentAuthorUsername: momentAuthorUsername,
                            commentId: commentId,
                            commentText: content,
                            senderUsername: fromUsername
                        )
                    }
                }
            }
        }
    }

    private func handleMentions(
        _ mentions: [CommentMentionEntity],
        momentId: String,
        momentAuthorId: String,
        momentAuthorUsername: String?,
        commentId: String,
        fromUserId: String,
        fromUsername: String,
        content: String,
        excludedUserIds: Set<String>
    ) {
        for mention in mentions {
            let mentionedUserId = mention.userId
            guard !excludedUserIds.contains(mentionedUserId) else { continue }

            canUserViewMoment(momentId: momentId, momentAuthorId: momentAuthorId, viewerId: mentionedUserId) { canView in
                guard canView else { return }

                Task { @MainActor in
                    NotificationService.shared.sendCommentMentionNotification(
                        to: mentionedUserId,
                        momentId: momentId,
                        momentAuthorId: momentAuthorId,
                        momentAuthorUsername: momentAuthorUsername,
                        commentId: commentId,
                        commentText: content,
                        senderUsername: fromUsername
                    )
                }
            }
        }
    }

    private func fetchUsername(userId: String, completion: @escaping (String?) -> Void) {
        guard !userId.isEmpty else {
            completion(nil)
            return
        }

        db.collection("users").document(userId).getDocument { snapshot, _ in
            completion(snapshot?.data()?["username"] as? String)
        }
    }

    private func canUserViewMoment(
        momentId: String,
        momentAuthorId: String,
        viewerId: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard !momentId.isEmpty, !momentAuthorId.isEmpty, !viewerId.isEmpty else {
            completion(false)
            return
        }

        if momentAuthorId == viewerId {
            completion(true)
            return
        }

        db.collection("users")
            .document(momentAuthorId)
            .collection("moments")
            .document(momentId)
            .getDocument { [weak self] snapshot, _ in
                guard let self, let data = snapshot?.data() else {
                    completion(false)
                    return
                }

                let audience = data["audience"] as? String ?? ContentAudience.everyone.rawValue

                switch audience {
                case ContentAudience.onlyMe.rawValue:
                    completion(false)
                case ContentAudience.custom.rawValue:
                    self.fetchCustomMomentAudience(momentId: momentId, authorId: momentAuthorId) { allowedUsers in
                        ContentVisibilityService.shared.canUserSeeContent(
                            contentOwnerId: momentAuthorId,
                            viewerId: viewerId,
                            contentType: .custom,
                            customViewers: allowedUsers,
                            completion: completion
                        )
                    }
                case ContentAudience.customList.rawValue:
                    guard let customListId = data["customListId"] as? String, !customListId.isEmpty else {
                        completion(false)
                        return
                    }
                    self.fetchCustomListMembers(listId: customListId, ownerId: momentAuthorId) { members in
                        ContentVisibilityService.shared.canUserSeeContent(
                            contentOwnerId: momentAuthorId,
                            viewerId: viewerId,
                            contentType: .custom,
                            customViewers: members,
                            completion: completion
                        )
                    }
                default:
                    let visibilityType: ContentVisibilityType
                    switch audience {
                    case ContentAudience.connections.rawValue:
                        visibilityType = .connections
                    case ContentAudience.bestFriends.rawValue:
                        visibilityType = .bestFriends
                    default:
                        visibilityType = .everyone
                    }

                    ContentVisibilityService.shared.canUserSeeContent(
                        contentOwnerId: momentAuthorId,
                        viewerId: viewerId,
                        contentType: visibilityType,
                        completion: completion
                    )
                }
            }
    }

    private func fetchCustomMomentAudience(
        momentId: String,
        authorId: String,
        completion: @escaping ([String]) -> Void
    ) {
        let customAudiencesRef = db.collection("users").document(authorId).collection("customAudiences")

        customAudiencesRef.document("moment_\(momentId)").getDocument { snapshot, _ in
            if let allowedUsers = snapshot?.data()?["allowedUsers"] as? [String], !allowedUsers.isEmpty {
                completion(allowedUsers)
                return
            }

            customAudiencesRef.document("default_moment").getDocument { snapshot, _ in
                let allowedUsers = snapshot?.data()?["allowedUsers"] as? [String] ?? []
                completion(allowedUsers)
            }
        }
    }

    private func fetchCustomListMembers(
        listId: String,
        ownerId: String,
        completion: @escaping ([String]) -> Void
    ) {
        db.collection("users")
            .document(ownerId)
            .collection("customAudienceLists")
            .document(listId)
            .getDocument { snapshot, _ in
                let members = snapshot?.data()?["members"] as? [String] ?? []
                completion(members)
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
