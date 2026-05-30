import Foundation
import FirebaseStorage

extension ChatService {
    @MainActor
    final class EncryptedMediaResolver {
        private let encryptionService: EncryptionService
        private var outgoingPreviews: [String: CachedResolvedMedia] = [:]
        private var activeUploadMessageIds: Set<String> = []
        private var resolvedMediaCache: [String: CachedResolvedMedia] = [:]

        actor DownloadQueue {
            func download(objectPath: String, maxSize: Int64) async throws -> Data {
                try await withCheckedThrowingContinuation { continuation in
                    Storage.storage()
                        .reference()
                        .child(objectPath)
                        .getData(maxSize: maxSize) { data, error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else if let data {
                                continuation.resume(returning: data)
                            } else {
                                continuation.resume(
                                    throwing: NSError(
                                        domain: "ChatService",
                                        code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "No se pudieron descargar los datos cifrados"]
                                    )
                                )
                            }
                        }
                }
            }
        }

        private let downloadQueue = DownloadQueue()

        init(encryptionService: EncryptionService) {
            self.encryptionService = encryptionService
        }

        func stageOutgoingPreview(_ preview: CachedResolvedMedia, for messageId: String) {
            outgoingPreviews[messageId] = preview
        }

        func markUploadStarted(for messageId: String) {
            activeUploadMessageIds.insert(messageId)
        }

        func markUploadFinished(for messageId: String) {
            activeUploadMessageIds.remove(messageId)
        }

        func cacheResolvedPreview(_ preview: CachedResolvedMedia, for messageId: String) {
            resolvedMediaCache[messageId] = preview
        }

        func resolveForMessage(_ message: EnhancedMessage) async -> (mediaUrl: String?, thumbnailUrl: String?)? {
            guard let mediaObjectPath = message.mediaObjectPath,
                  !mediaObjectPath.isEmpty,
                  let mediaEncryption = message.mediaEncryption else {
                return nil
            }

            let resolved = await resolveForDisplay(
                messageId: message.id,
                conversationId: message.conversationId,
                mediaObjectPath: mediaObjectPath,
                mediaEncryption: mediaEncryption,
                thumbnailObjectPath: message.thumbnailObjectPath,
                thumbnailEncryption: message.thumbnailEncryption
            )
            return (resolved.mediaUrl, resolved.thumbnailUrl)
        }

        func resolveForDisplay(
            messageId: String,
            conversationId: String,
            mediaObjectPath: String,
            mediaEncryption: EncryptedChatMediaMetadata,
            thumbnailObjectPath: String?,
            thumbnailEncryption: EncryptedChatMediaMetadata?
        ) async -> CachedResolvedMedia {
            if let cached = outgoingPreviews[messageId] {
                return cached
            }
            if let cached = resolvedMediaCache[messageId] {
                return cached
            }

            let diskMain = decryptedMediaCacheURL(
                conversationId: conversationId,
                messageId: messageId,
                purpose: mediaEncryption.purpose,
                fileExtension: mediaEncryption.fileExtension
            )
            if FileManager.default.fileExists(atPath: diskMain.path) {
                let resolved = CachedResolvedMedia(mediaUrl: diskMain.absoluteString, thumbnailUrl: nil)
                resolvedMediaCache[messageId] = resolved
                return resolved
            }

            if activeUploadMessageIds.contains(messageId) {
                return CachedResolvedMedia(mediaUrl: nil, thumbnailUrl: nil)
            }

            let resolved = await resolveEncryptedMedia(
                conversationId: conversationId,
                messageId: messageId,
                mediaObjectPath: mediaObjectPath,
                mediaEncryption: mediaEncryption,
                thumbnailObjectPath: thumbnailObjectPath,
                thumbnailEncryption: thumbnailEncryption
            )
            if resolved.mediaUrl != nil || resolved.thumbnailUrl != nil {
                resolvedMediaCache[messageId] = resolved
            }
            return resolved
        }

        private func resolveEncryptedMedia(
            conversationId: String,
            messageId: String,
            mediaObjectPath: String,
            mediaEncryption: EncryptedChatMediaMetadata,
            thumbnailObjectPath: String?,
            thumbnailEncryption: EncryptedChatMediaMetadata?
        ) async -> CachedResolvedMedia {
            async let mainURL = resolveEncryptedMediaURL(
                objectPath: mediaObjectPath,
                metadata: mediaEncryption,
                conversationId: conversationId,
                messageId: messageId
            )

            async let thumbURL = resolveEncryptedThumbnailURL(
                objectPath: thumbnailObjectPath,
                metadata: thumbnailEncryption,
                conversationId: conversationId,
                messageId: messageId
            )

            return await CachedResolvedMedia(
                mediaUrl: mainURL,
                thumbnailUrl: thumbURL
            )
        }

        private func resolveEncryptedThumbnailURL(
            objectPath: String?,
            metadata: EncryptedChatMediaMetadata?,
            conversationId: String,
            messageId: String
        ) async -> String? {
            guard let objectPath, let metadata else { return nil }
            return await resolveEncryptedMediaURL(
                objectPath: objectPath,
                metadata: metadata,
                conversationId: conversationId,
                messageId: messageId
            )
        }

        private func resolveEncryptedMediaURL(
            objectPath: String,
            metadata: EncryptedChatMediaMetadata,
            conversationId: String,
            messageId: String
        ) async -> String? {
            let cacheURL = decryptedMediaCacheURL(
                conversationId: conversationId,
                messageId: messageId,
                purpose: metadata.purpose,
                fileExtension: metadata.fileExtension
            )

            if FileManager.default.fileExists(atPath: cacheURL.path) {
                return cacheURL.absoluteString
            }

            do {
                let maxSize = max(metadata.plaintextSize + Int64(256 * 1024), Int64(8 * 1024 * 1024))
                let encryptedData = try await downloadQueue.download(objectPath: objectPath, maxSize: maxSize)
                let decryptedData = try await encryptionService.decryptChatMedia(
                    encryptedData,
                    metadata: metadata,
                    for: conversationId,
                    messageId: messageId
                )
                try ensureChatMediaCacheDirectory()
                try decryptedData.write(to: cacheURL, options: Data.WritingOptions.atomic)
                return cacheURL.absoluteString
            } catch {
                return nil
            }
        }

        private func decryptedMediaCacheURL(
            conversationId: String,
            messageId: String,
            purpose: ChatMediaPurpose,
            fileExtension: String
        ) -> URL {
            let safeConversation = conversationId.replacingOccurrences(of: "/", with: "_")
            let safeMessage = messageId.replacingOccurrences(of: "/", with: "_")
            let filename = "\(safeConversation)_\(safeMessage)_\(purpose.rawValue).\(fileExtension)"
            return chatMediaCacheDirectory().appendingPathComponent(filename)
        }

        private func chatMediaCacheDirectory() -> URL {
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("chat_media_decrypted", isDirectory: true)
        }

        private func ensureChatMediaCacheDirectory() throws {
            try FileManager.default.createDirectory(
                at: chatMediaCacheDirectory(),
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
}
