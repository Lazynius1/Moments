import Foundation

extension ChatService {
    /// Pipeline de vídeo cifrado sin copias completas en memoria.
    func uploadChunkedEncryptedVideo(
        preparedURL: URL,
        senderId: String,
        conversationId: String,
        messageId: String,
        mediaFileId: String,
        fileExtension: String,
        contentType: String
    ) async throws -> ChatMediaUploadResult {
        let encryptedMain = try await encryptionService.encryptChatMediaFile(
            at: preparedURL,
            for: conversationId,
            messageId: messageId,
            purpose: .primary,
            contentType: contentType,
            fileExtension: fileExtension
        )
        defer { try? FileManager.default.removeItem(at: encryptedMain.ciphertextURL) }

        let cachedMainURL = try ChatCacheStore.copyDecryptedMedia(
            from: preparedURL,
            conversationId: conversationId,
            messageId: messageId,
            purpose: encryptedMain.metadata.purpose,
            fileExtension: encryptedMain.metadata.fileExtension
        )
        let localPreviewURL = cachedMainURL.absoluteString
        let encryptedMainTarget = chatEncryptedStorageTarget(
            userId: senderId,
            conversationId: conversationId,
            messageId: messageId,
            fileId: mediaFileId,
            originalContentType: contentType
        )

        encryptedMediaResolver.stageOutgoingPreview(
            CachedResolvedMedia(mediaUrl: localPreviewURL, thumbnailUrl: nil),
            for: messageId
        )
        encryptedMediaResolver.markUploadStarted(for: messageId)
        defer { encryptedMediaResolver.markUploadFinished(for: messageId) }

        _ = try await MediaUploadService.shared.uploadEncryptedFile(
            target: encryptedMainTarget,
            fileURL: encryptedMain.ciphertextURL,
            progress: { progressValue in
                NotificationCenter.default.post(
                    name: NSNotification.Name("MediaUploadProgress"),
                    object: nil,
                    userInfo: ["messageId": messageId, "progress": progressValue]
                )
            }
        )

        var thumbnailObjectPath: String?
        var thumbnailEncryption: EncryptedChatMediaMetadata?
        var localThumbnailURL: String?

        if let thumbnailData = try await generateVideoThumbnailData(from: preparedURL) {
            do {
                let thumbId = UUID().uuidString
                let thumbBase = StoragePathBuilder.build(
                    userId: senderId,
                    domain: .chatThumbnail(
                        conversationId: conversationId,
                        messageId: messageId,
                        thumbId: thumbId
                    )
                )
                let encryptedThumb = try await encryptionService.encryptChatMedia(
                    thumbnailData,
                    for: conversationId,
                    messageId: messageId,
                    purpose: .thumbnail,
                    contentType: "image/jpeg",
                    fileExtension: "jpg"
                )
                let encryptedThumbTarget = chatEncryptedStorageTarget(
                    userId: senderId,
                    conversationId: conversationId,
                    messageId: messageId,
                    fileId: thumbId,
                    originalContentType: "image/jpeg",
                    objectPath: thumbBase.objectPath.replacingOccurrences(of: ".jpg", with: ".enc")
                )
                _ = try await MediaUploadService.shared.uploadEncryptedBlob(
                    target: encryptedThumbTarget,
                    data: encryptedThumb.ciphertext
                )
                thumbnailObjectPath = encryptedThumbTarget.objectPath
                thumbnailEncryption = encryptedThumb.metadata
                let cachedThumbURL = try ChatCacheStore.writeDecryptedMedia(
                    thumbnailData,
                    conversationId: conversationId,
                    messageId: messageId,
                    purpose: encryptedThumb.metadata.purpose,
                    fileExtension: encryptedThumb.metadata.fileExtension
                )
                localThumbnailURL = cachedThumbURL.absoluteString
            } catch {
                AppLog.error("Encrypted video thumbnail upload failed: \(error.localizedDescription)")
            }
        }

        let preview = CachedResolvedMedia(
            mediaUrl: localPreviewURL,
            thumbnailUrl: localThumbnailURL
        )
        encryptedMediaResolver.stageOutgoingPreview(preview, for: messageId)
        encryptedMediaResolver.cacheResolvedPreview(preview, for: messageId)

        return ChatMediaUploadResult(
            mediaUrl: localPreviewURL,
            thumbnailUrl: localThumbnailURL,
            mediaObjectPath: encryptedMainTarget.objectPath,
            thumbnailObjectPath: thumbnailObjectPath,
            mediaEncryption: encryptedMain.metadata,
            thumbnailEncryption: thumbnailEncryption
        )
    }
}
