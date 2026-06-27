import Foundation
import FirebaseStorage

extension ChatService {
    @MainActor
    final class EncryptedMediaResolver {
        private let encryptionService: EncryptionService
        private var outgoingPreviews: [String: CachedResolvedMedia] = [:]
        private var activeUploadMessageIds: Set<String> = []
        private var resolvedMediaCache: [String: CachedResolvedMedia] = [:]
        private var resolvedThumbnailCache: [String: String] = [:]

        /// Si el media ya fue descifrado en sesiones anteriores, devuelve URLs locales
        /// sin tocar la red (útil al abrir la galería del cluster).
        func warmMessageURLsFromDiskCache(_ message: EnhancedMessage) -> (mediaUrl: String?, thumbnailUrl: String?) {
            let warmed = ChatCacheStore.localURLsIfPresent(for: message)

            if let mediaUrl = warmed.mediaUrl {
                resolvedMediaCache[message.id] = CachedResolvedMedia(
                    mediaUrl: mediaUrl,
                    thumbnailUrl: warmed.thumbnailUrl
                )
            }
            if let thumbnailUrl = warmed.thumbnailUrl {
                resolvedThumbnailCache[message.id] = thumbnailUrl
            }

            return warmed
        }

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

        /// Resuelve únicamente la miniatura cifrada (barato, no descarga el vídeo
        /// completo). Devuelve un file:// local descifrado para usar como portada.
        func resolveThumbnailURL(for message: EnhancedMessage, forceDownload: Bool = false) async -> String? {
            if let existing = message.thumbnailUrl, !existing.isEmpty {
                return existing
            }
            if let cached = resolvedThumbnailCache[message.id] {
                return cached
            }
            guard let thumbObjectPath = message.thumbnailObjectPath,
                  !thumbObjectPath.isEmpty,
                  let thumbEncryption = message.thumbnailEncryption else {
                return nil
            }

            let resolved = await resolveEncryptedMediaURL(
                objectPath: thumbObjectPath,
                metadata: thumbEncryption,
                conversationId: message.conversationId,
                messageId: message.id,
                forceDownload: forceDownload
            )
            if let resolved {
                resolvedThumbnailCache[message.id] = resolved
            }
            return resolved
        }

        func resolveForMessage(_ message: EnhancedMessage, forceDownload: Bool = false) async -> (mediaUrl: String?, thumbnailUrl: String?)? {
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
                thumbnailEncryption: message.thumbnailEncryption,
                forceDownload: forceDownload
            )
            return (resolved.mediaUrl, resolved.thumbnailUrl)
        }

        func resolveForDisplay(
            messageId: String,
            conversationId: String,
            mediaObjectPath: String,
            mediaEncryption: EncryptedChatMediaMetadata,
            thumbnailObjectPath: String?,
            thumbnailEncryption: EncryptedChatMediaMetadata?,
            forceDownload: Bool = false
        ) async -> CachedResolvedMedia {
            if let cached = outgoingPreviews[messageId] {
                return cached
            }
            if let cached = resolvedMediaCache[messageId] {
                if Self.cachedMediaFileExists(cached.mediaUrl) {
                    return cached
                }
                resolvedMediaCache.removeValue(forKey: messageId)
            }

            let diskMain = ChatCacheStore.decryptedMediaURL(
                conversationId: conversationId,
                messageId: messageId,
                purpose: mediaEncryption.purpose,
                fileExtension: mediaEncryption.fileExtension
            )
            if FileManager.default.fileExists(atPath: diskMain.path) {
                ChatCacheStore.touchAccessDate(at: diskMain)
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
                thumbnailEncryption: thumbnailEncryption,
                forceDownload: forceDownload
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
            thumbnailEncryption: EncryptedChatMediaMetadata?,
            forceDownload: Bool
        ) async -> CachedResolvedMedia {
            async let mainURL = resolveEncryptedMediaURL(
                objectPath: mediaObjectPath,
                metadata: mediaEncryption,
                conversationId: conversationId,
                messageId: messageId,
                forceDownload: forceDownload
            )

            async let thumbURL = resolveEncryptedThumbnailURL(
                objectPath: thumbnailObjectPath,
                metadata: thumbnailEncryption,
                conversationId: conversationId,
                messageId: messageId,
                forceDownload: forceDownload
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
            messageId: String,
            forceDownload: Bool
        ) async -> String? {
            guard let objectPath, let metadata else { return nil }
            return await resolveEncryptedMediaURL(
                objectPath: objectPath,
                metadata: metadata,
                conversationId: conversationId,
                messageId: messageId,
                forceDownload: forceDownload
            )
        }

        private func resolveEncryptedMediaURL(
            objectPath: String,
            metadata: EncryptedChatMediaMetadata,
            conversationId: String,
            messageId: String,
            forceDownload: Bool = false
        ) async -> String? {
            let cacheURL = ChatCacheStore.decryptedMediaURL(
                conversationId: conversationId,
                messageId: messageId,
                purpose: metadata.purpose,
                fileExtension: metadata.fileExtension
            )

            if FileManager.default.fileExists(atPath: cacheURL.path) {
                ChatCacheStore.touchAccessDate(at: cacheURL)
                return cacheURL.absoluteString
            }

            guard metadata.purpose == .thumbnail
                ? ChatMediaDownloadPolicy.shouldDownloadThumbnailPreview(force: forceDownload)
                : ChatMediaDownloadPolicy.shouldDownloadAutomatically(force: forceDownload)
            else {
                return nil
            }

            do {
                let maxSize = max(metadata.plaintextSize + Int64(256 * 1024), Int64(8 * 1024 * 1024))
                let reportsProgress = metadata.purpose == .primary
                let encryptedData = try await Self.downloadEncryptedBlob(
                    objectPath: objectPath,
                    maxSize: maxSize,
                    messageId: messageId,
                    reportsProgress: reportsProgress
                )
                if reportsProgress {
                    Self.postDownloadProgress(messageId: messageId, progress: 0.88)
                }
                let decryptedData = try await encryptionService.decryptChatMedia(
                    encryptedData,
                    metadata: metadata,
                    for: conversationId,
                    messageId: messageId
                )
                if reportsProgress {
                    Self.postDownloadProgress(messageId: messageId, progress: 0.96)
                }
                try ChatCacheStore.ensureDirectories()
                try decryptedData.write(to: cacheURL, options: Data.WritingOptions.atomic)
                ChatCacheStore.enforceQuota()
                if reportsProgress {
                    Self.postDownloadProgress(messageId: messageId, progress: 1.0)
                }
                return cacheURL.absoluteString
            } catch {
                return nil
            }
        }

        /// `true` si la URL cacheada es un `file://` cuyo archivo sigue existiendo en disco.
        private static func cachedMediaFileExists(_ urlString: String?) -> Bool {
            guard let urlString, let url = URL(string: urlString) else { return false }
            guard url.isFileURL else { return true }
            return FileManager.default.fileExists(atPath: url.path)
        }

        private static func postDownloadProgress(messageId: String, progress: Double) {
            NotificationCenter.default.post(
                name: NSNotification.Name("MediaDownloadProgress"),
                object: nil,
                userInfo: [
                    "messageId": messageId,
                    "progress": min(max(progress, 0), 1)
                ]
            )
        }

        /// Descargas en paralelo (antes un `actor` serializaba todo y la galería tardaba mucho).
        private static func downloadEncryptedBlob(
            objectPath: String,
            maxSize: Int64,
            messageId: String,
            reportsProgress: Bool
        ) async throws -> Data {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("chat-enc-\(UUID().uuidString).bin")
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let reference = Storage.storage().reference().child(objectPath)

            return try await withCheckedThrowingContinuation { continuation in
                let task = reference.write(toFile: tempURL)
                var progressHandle: String?
                var successHandle: String?
                var failureHandle: String?

                func removeObservers() {
                    if let progressHandle {
                        task.removeObserver(withHandle: progressHandle)
                    }
                    if let successHandle {
                        task.removeObserver(withHandle: successHandle)
                    }
                    if let failureHandle {
                        task.removeObserver(withHandle: failureHandle)
                    }
                }

                if reportsProgress {
                    progressHandle = task.observe(.progress) { snapshot in
                        guard let progress = snapshot.progress, progress.totalUnitCount > 0 else { return }
                        let fraction = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                        postDownloadProgress(messageId: messageId, progress: max(0.03, fraction * 0.85))
                    }
                }

                successHandle = task.observe(.success) { _ in
                    removeObservers()
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                        if fileSize > maxSize {
                            throw NSError(
                                domain: "ChatService",
                                code: -2,
                                userInfo: [NSLocalizedDescriptionKey: "El archivo cifrado supera el tamaño máximo permitido"]
                            )
                        }
                        let data = try Data(contentsOf: tempURL)
                        continuation.resume(returning: data)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }

                failureHandle = task.observe(.failure) { snapshot in
                    removeObservers()
                    continuation.resume(throwing: snapshot.error ?? NSError(
                        domain: "ChatService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No se pudieron descargar los datos cifrados"]
                    ))
                }
            }
        }
    }
}
