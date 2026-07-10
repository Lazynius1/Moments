import Foundation
import FirebaseFirestore

extension ChatService {
    // MARK: - Conversations and Sharing
    func getOrCreateConversation(between user1Id: String, and user2Id: String, initialMessage: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        db.collection("conversations")
            .whereField("participants", arrayContains: user1Id)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                let existingConversation = snapshot?.documents.first { doc in
                    let participants = doc.data()["participants"] as? [String] ?? []
                    return participants.contains(user2Id)
                }

                if let conversation = existingConversation {
                    let conversationId = conversation.documentID
                    let trimmedInitial = initialMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    guard !trimmedInitial.isEmpty else {
                        completion(.success(conversationId))
                        return
                    }

                    Task { @MainActor in
                        guard let self = self else {
                            completion(
                                .failure(
                                    NSError(
                                        domain: "ChatService",
                                        code: -2,
                                        userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.serviceUnavailable", comment: "Messaging service unavailable")]
                                    )
                                )
                            )
                            return
                        }

                        self.sendTextMessage(
                            conversationId: conversationId,
                            senderId: user1Id,
                            content: trimmedInitial
                        ) { sendResult in
                            switch sendResult {
                            case .success:
                                completion(.success(conversationId))
                            case .failure(let sendError):
                                completion(.failure(sendError))
                            }
                        }
                    }
                } else {
                    Task { @MainActor in
                        self?.checkMutualFollowAndCreateConversation(user1Id: user1Id, user2Id: user2Id, initialMessage: initialMessage, completion: completion)
                    }
                }
            }
    }

    private func checkMutualFollowAndCreateConversation(user1Id: String, user2Id: String, initialMessage: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        let firestoreService = FirestoreService()

        firestoreService.isFollowing(currentUserId: user1Id, targetUserId: user2Id) { [weak self] user1FollowsUser2 in
            firestoreService.isFollowing(currentUserId: user2Id, targetUserId: user1Id) { user2FollowsUser1 in
                let mutualFollow = user1FollowsUser2 && user2FollowsUser1

                if mutualFollow {
                    Task { @MainActor in
                        self?.createBidirectionalConversation(user1Id: user1Id, user2Id: user2Id, initialMessage: initialMessage, completion: completion)
                    }
                } else {
                    let error = NSError(
                        domain: "ChatService",
                        code: 403,
                        userInfo: [
                            NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.messageRequestRequired", comment: "A message request is required to start this conversation")
                        ]
                    )
                    completion(.failure(error))
                }
            }
        }
    }

    func sendSharedMomentMessage(
        conversationId: String,
        senderId: String,
        moment: Moment,
        shareText: String,
        momentUrl: String,
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        Task {
            let encryptedContent: String
            do {
                encryptedContent = try await encryptMessageContent(shareText, for: conversationId)
            } catch {
                completion(.failure(error))
                return
            }
            let freshMomentAuthor = UserCacheService.shared.getCachedUser(userId: moment.authorId)?.username ?? moment.username

            let sharedMomentData: [String: String] = [
                "momentId": moment.id ?? "",
                "momentAuthor": freshMomentAuthor,
                "momentAuthorId": moment.authorId,
                "momentContent": moment.content,
                "momentImageUrl": moment.thumbnailUrl ?? moment.imagePath ?? "",
                "momentAspectRatio": moment.aspectRatio ?? "1:1",
                "momentVideoUrl": moment.videoUrl ?? "",
                "momentTimestamp": String(moment.timestamp.timeIntervalSince1970),
                "shareUrl": momentUrl
            ]

            let messageId = UUID().uuidString
            let message = EnhancedMessage(
                id: messageId,
                conversationId: conversationId,
                senderId: senderId,
                type: .sharedMoment,
                content: encryptedContent,
                mediaUrl: nil,
                thumbnailUrl: nil,
                duration: nil,
                fileName: nil,
                fileSize: nil,
                latitude: nil,
                longitude: nil,
                timestamp: Date(),
                status: .sending,
                isRead: false,
                isDeleted: false,
                deletedAt: nil,
                editedAt: nil,
                reactions: nil,
                replyTo: nil,
                expirationDate: nil,
                isViewed: false,
                storyReplyData: nil,
                sharedMomentData: sharedMomentData
            )

            sendMessage(message, useServerTimestamp: true) { result in
                switch result {
                case .success(let sentMessage):
                    self.updateConversation(
                        conversationId: conversationId,
                        lastMessage: self.neutralConversationPreview(for: .sharedMoment),
                        senderId: senderId,
                        messageType: .sharedMoment
                    ) { _ in
                        completion(.success(sentMessage))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func sendSharedStoryMessage(
        conversationId: String,
        senderId: String,
        story: Story,
        shareText: String,
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        guard let storyId = story.id else {
            completion(.failure(NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing story id"])))
            return
        }

        Task {
            let encryptedContent: String
            do {
                encryptedContent = try await encryptMessageContent(shareText, for: conversationId)
            } catch {
                completion(.failure(error))
                return
            }
            let freshAuthor = UserCacheService.shared.getCachedUser(userId: story.authorId)?.username ?? story.username

            let sharedStoryData: [String: String] = [
                "storyId": storyId,
                "storyAuthor": freshAuthor,
                "storyAuthorId": story.authorId,
                "storyPreviewUrl": storyPreviewURL(for: story),
                "storyMediaType": storyMediaTypeString(for: story),
                "storyExpiration": String(story.expirationDate.timeIntervalSince1970),
                "storyTimestamp": String(story.timestamp.timeIntervalSince1970)
            ]

            let messageId = UUID().uuidString
            let message = EnhancedMessage(
                id: messageId,
                conversationId: conversationId,
                senderId: senderId,
                type: .sharedStory,
                content: encryptedContent,
                mediaUrl: nil,
                thumbnailUrl: nil,
                duration: nil,
                fileName: nil,
                fileSize: nil,
                latitude: nil,
                longitude: nil,
                timestamp: Date(),
                status: .sending,
                isRead: false,
                isDeleted: false,
                deletedAt: nil,
                editedAt: nil,
                reactions: nil,
                replyTo: nil,
                expirationDate: nil,
                isViewed: false,
                storyReplyData: nil,
                sharedMomentData: nil,
                sharedStoryData: sharedStoryData
            )

            sendMessage(message, useServerTimestamp: true) { result in
                switch result {
                case .success(let sentMessage):
                    self.updateConversation(
                        conversationId: conversationId,
                        lastMessage: self.neutralConversationPreview(for: .sharedStory),
                        senderId: senderId,
                        messageType: .sharedStory
                    ) { _ in
                        completion(.success(sentMessage))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - View Once
    func deleteViewOnceAfterViewing(
        conversationId: String,
        messageId: String,
        completion: @escaping (Error?) -> Void
    ) {
        ViewOnceConsumptionService.shared.consume(
            conversationId: conversationId,
            messageId: messageId,
            reason: .viewOnce,
            completion: completion
        )
    }

    func cleanupConsumedViewOnceMessages(conversationId: String) {
        guard !conversationId.isEmpty else { return }

        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .whereField("isViewOnce", isEqualTo: true)
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 50)
            .getDocuments { [weak self] snapshot, error in
                guard let self else { return }
                guard error == nil, let documents = snapshot?.documents else { return }

                for document in documents {
                    let data = document.data()
                    guard let reason = self.consumptionReasonForConsumedViewOnce(data) else { continue }

                    let messageId = data["id"] as? String ?? document.documentID
                    ViewOnceConsumptionService.shared.consume(
                        conversationId: conversationId,
                        messageId: messageId,
                        reason: reason
                    ) { error in
                        if let error {
                            LogConfig.log("Consumed view-once cleanup failed: \(error.localizedDescription)", category: "Chat")
                        }
                    }
                }
            }
    }

    private func consumptionReasonForConsumedViewOnce(_ data: [String: Any]) -> ViewOnceConsumptionReason? {
        guard data["isViewOnce"] as? Bool == true else { return nil }
        guard data["isDeleted"] as? Bool != true else { return nil }

        let hasMedia = [
            data["mediaObjectPath"] as? String,
            data["thumbnailObjectPath"] as? String,
            data["mediaUrl"] as? String,
            data["thumbnailUrl"] as? String
        ].contains { value in
            guard let value else { return false }
            return !value.isEmpty
        }
        guard hasMedia else { return nil }

        let allowReplay = data["allowReplay"] as? Bool == true
        if allowReplay {
            if (data["replayedBy"] as? [String])?.isEmpty == false {
                return .replay
            }

            if (data["viewedBy"] as? [String])?.isEmpty == false || data["isViewed"] as? Bool == true {
                return .abandonReplay
            }

            return nil
        }

        if (data["viewedBy"] as? [String])?.isEmpty == false || data["isViewed"] as? Bool == true {
            return .viewOnce
        }

        return nil
    }

    func sendViewOnceMessage(
        conversationId: String,
        senderId: String,
        mediaData: Data,
        mediaType: EnhancedCameraPickerView.MediaType,
        messageId: String? = nil,
        isVanishModeMessage: Bool = false,
        allowReplay: Bool = false,
        replyTo: String? = nil,
        overlayPayload: ChatMediaOverlayPayload? = nil,
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        let messageType: MessageType = mediaType == .image ? .viewOnceImage : .viewOnceVideo
        let finalMessageId = messageId ?? UUID().uuidString

        uploadMedia(data: mediaData, type: messageType, conversationId: conversationId, messageId: finalMessageId) { [weak self] result in
            switch result {
            case .success(let uploadResult):
                let message = EnhancedMessage(
                    id: finalMessageId,
                    conversationId: conversationId,
                    senderId: senderId,
                    type: messageType,
                    content: nil,
                    mediaUrl: uploadResult.mediaUrl,
                    thumbnailUrl: uploadResult.thumbnailUrl,
                    mediaObjectPath: uploadResult.mediaObjectPath,
                    thumbnailObjectPath: uploadResult.thumbnailObjectPath,
                    mediaEncryption: uploadResult.mediaEncryption,
                    thumbnailEncryption: uploadResult.thumbnailEncryption,
                    duration: nil,
                    fileName: nil,
                    fileSize: Int64(mediaData.count),
                    latitude: nil,
                    longitude: nil,
                    timestamp: Date(),
                    status: .sending,
                    isRead: false,
                    isDeleted: false,
                    deletedAt: nil,
                    editedAt: nil,
                    reactions: nil,
                    replyTo: replyTo,
                    expirationDate: nil,
                    isViewed: false,
                    storyReplyData: nil,
                    sharedMomentData: nil,
                    sharedStoryData: nil,
                    mediaBatchId: nil,
                    textOverlayLive: overlayPayload?.textOverlayLive,
                    textOverlays: overlayPayload?.textOverlays,
                    stickers: overlayPayload?.stickers,
                    drawingData: overlayPayload?.drawingData,
                    viewedBy: [],
                    isVanishModeMessage: isVanishModeMessage ? true : nil
                )

                message.allowReplay = allowReplay ? true : nil

                var messageData = self?.createBasicMessageData(from: message) ?? [:]
                messageData["isViewOnce"] = true
                messageData["viewedBy"] = []
                if allowReplay {
                    messageData["allowReplay"] = true
                    messageData["replayedBy"] = []
                }

                self?.saveViewOnceMessage(message: message, customData: messageData, completion: completion)

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func markViewOnceAsViewed(
        conversationId: String,
        messageId: String,
        viewerId: String,
        completion: @escaping (Error?) -> Void
    ) {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)

        db.runTransaction({ transaction, errorPointer -> Any? in
            let messageDocument: DocumentSnapshot
            do {
                try messageDocument = transaction.getDocument(messageRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }

            guard var viewedBy = messageDocument.data()?["viewedBy"] as? [String] else {
                transaction.updateData([
                    "viewedBy": [viewerId],
                    "isViewed": true,
                    "status": MessageStatus.read.rawValue
                ], forDocument: messageRef)
                return nil
            }

            if !viewedBy.contains(viewerId) {
                viewedBy.append(viewerId)
                transaction.updateData([
                    "viewedBy": viewedBy,
                    "isViewed": true,
                    "status": MessageStatus.read.rawValue
                ], forDocument: messageRef)
            }

            return nil
        }) { _, error in
            completion(error)
        }
    }

    func markViewOnceReplayed(
        conversationId: String,
        messageId: String,
        viewerId: String,
        completion: @escaping (Error?) -> Void
    ) {
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData(["replayedBy": FieldValue.arrayUnion([viewerId])]) { error in
                completion(error)
            }
    }

    private func saveViewOnceMessage(
        message: EnhancedMessage,
        customData: [String: Any],
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        nonisolated(unsafe) let message = message
        let messageRef = db.collection("conversations")
            .document(message.conversationId)
            .collection("messages")
            .document(message.id)

        messageRef.setData(customData) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let error = error {
                    self.updateLocalMessageStatus(
                        conversationId: message.conversationId,
                        messageId: message.id,
                        status: .failed
                    )
                    completion(.failure(error))
                    return
                }

                self.updateMessageStatus(
                    conversationId: message.conversationId,
                    messageId: message.id,
                    status: .sent
                ) { _ in }

                let lastMessagePreview = message.type == .viewOnceImage ?
                    self.neutralConversationPreview(for: .viewOnceImage) :
                    self.neutralConversationPreview(for: .viewOnceVideo)

                self.updateConversation(
                    conversationId: message.conversationId,
                    lastMessage: lastMessagePreview,
                    senderId: message.senderId,
                    messageType: message.type
                ) { _ in
                    let updatedMessage: EnhancedMessage = {
                        let m = message
                        m.status = .sent
                        return m
                    }()
                    completion(.success(updatedMessage))
                }
            }
        }
    }
}
