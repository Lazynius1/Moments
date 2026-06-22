import Foundation
import FirebaseAuth
import FirebaseStorage
import AVFoundation
import UIKit

extension ChatService {
    // MARK: - Media Upload
    func uploadMedia(
        data: Data,
        type: MessageType,
        conversationId: String,
        messageId: String? = nil,
        completion: @escaping (Result<ChatMediaUploadResult, Error>) -> Void
    ) {
        guard let senderId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"])))
            return
        }

        let resolvedMessageId = messageId ?? UUID().uuidString
        let ext = getFileExtension(for: type)
        let uploader = MediaUploadService.shared
        let videoCompression = VideoCompressionService.shared

        Task { @MainActor in
            do {
                let mediaFileId = UUID().uuidString

                let payload: MediaUploadPayload
                var tempFilesToCleanup: [URL] = []

                if type == .video || type == .viewOnceVideo {
                    let preparedURL = try await videoCompression.prepareVideoDataForUpload(
                        data: data,
                        preset: .chat,
                        preferredExtension: "mp4"
                    )
                    tempFilesToCleanup.append(preparedURL)
                    payload = .file(preparedURL)
                } else {
                    payload = .data(data)
                }

                let shouldEncryptMedia =
                    type == .image ||
                    type == .video ||
                    type == .audio ||
                    type == .file ||
                    type == .ephemeral ||
                    type == .viewOnceImage ||
                    type == .viewOnceVideo

                if shouldEncryptMedia {
                    let plaintextData: Data
                    let originalContentType: String
                    let localPreviewURL: String?

                    switch payload {
                    case .data(let rawData):
                        plaintextData = rawData
                        originalContentType = getContentType(for: type)
                        localPreviewURL = createLocalPreviewURL(
                            data: rawData,
                            fileExtension: ext,
                            prefix: "chat_media_preview"
                        )?.absoluteString
                    case .file(let url):
                        plaintextData = try Data(contentsOf: url)
                        originalContentType = getContentType(for: type)
                        localPreviewURL = createLocalPreviewURL(
                            data: plaintextData,
                            fileExtension: ext,
                            prefix: "chat_media_preview"
                        )?.absoluteString
                    }

                    let encryptedMain = try await encryptionService.encryptChatMedia(
                        plaintextData,
                        for: conversationId,
                        messageId: resolvedMessageId,
                        purpose: .primary,
                        contentType: originalContentType,
                        fileExtension: ext
                    )

                    let encryptedMainTarget = chatEncryptedStorageTarget(
                        userId: senderId,
                        conversationId: conversationId,
                        messageId: resolvedMessageId,
                        fileId: mediaFileId,
                        originalContentType: originalContentType
                    )

                    encryptedMediaResolver.stageOutgoingPreview(CachedResolvedMedia(
                        mediaUrl: localPreviewURL,
                        thumbnailUrl: nil
                    ), for: resolvedMessageId)

                    encryptedMediaResolver.markUploadStarted(for: resolvedMessageId)
                    defer { encryptedMediaResolver.markUploadFinished(for: resolvedMessageId) }

                    _ = try await uploader.uploadEncryptedBlob(
                        target: encryptedMainTarget,
                        data: encryptedMain.ciphertext,
                        progress: { progressValue in
                            NotificationCenter.default.post(
                                name: NSNotification.Name("MediaUploadProgress"),
                                object: nil,
                                userInfo: ["messageId": resolvedMessageId, "progress": progressValue]
                            )
                        }
                    )

                    var thumbnailObjectPath: String?
                    var thumbnailEncryption: EncryptedChatMediaMetadata?
                    var localThumbnailURL: String?

                    // Miniatura cifrada ligera (como WhatsApp): preview instantáneo en la
                    // notificación sin bajar el media completo. Vídeo → frame; imagen → reescalada.
                    var generatedThumbnailData: Data?
                    if type == .video || type == .viewOnceVideo {
                        generatedThumbnailData = try await generateVideoThumbnailData(from: plaintextData)
                    } else if type == .image || type == .viewOnceImage || type == .ephemeral {
                        generatedThumbnailData = generateImageThumbnailData(from: plaintextData)
                    }

                    if let thumbnailData = generatedThumbnailData {
                        do {
                            let thumbId = UUID().uuidString
                            let thumbBase = StoragePathBuilder.build(
                                userId: senderId,
                                domain: .chatThumbnail(
                                    conversationId: conversationId,
                                    messageId: resolvedMessageId,
                                    thumbId: thumbId
                                )
                            )
                            let encryptedThumb = try await encryptionService.encryptChatMedia(
                                thumbnailData,
                                for: conversationId,
                                messageId: resolvedMessageId,
                                purpose: .thumbnail,
                                contentType: "image/jpeg",
                                fileExtension: "jpg"
                            )
                            let encryptedThumbTarget = chatEncryptedStorageTarget(
                                userId: senderId,
                                conversationId: conversationId,
                                messageId: resolvedMessageId,
                                fileId: thumbId,
                                originalContentType: "image/jpeg",
                                objectPath: thumbBase.objectPath.replacingOccurrences(of: ".jpg", with: ".enc")
                            )
                            _ = try await uploader.uploadEncryptedBlob(
                                target: encryptedThumbTarget,
                                data: encryptedThumb.ciphertext
                            )
                            thumbnailObjectPath = encryptedThumbTarget.objectPath
                            thumbnailEncryption = encryptedThumb.metadata
                            localThumbnailURL = createLocalPreviewURL(
                                data: thumbnailData,
                                fileExtension: "jpg",
                                prefix: "chat_thumb_preview"
                            )?.absoluteString
                        } catch {
                            // Thumbnail opcional; el vídeo principal ya está subido.
                        }
                    }

                    for url in tempFilesToCleanup {
                        try? FileManager.default.removeItem(at: url)
                    }

                    let resolvedPreview = CachedResolvedMedia(
                        mediaUrl: localPreviewURL,
                        thumbnailUrl: localThumbnailURL
                    )
                    encryptedMediaResolver.stageOutgoingPreview(resolvedPreview, for: resolvedMessageId)
                    encryptedMediaResolver.cacheResolvedPreview(resolvedPreview, for: resolvedMessageId)

                    completion(.success(ChatMediaUploadResult(
                        mediaUrl: localPreviewURL,
                        thumbnailUrl: localThumbnailURL,
                        mediaObjectPath: encryptedMainTarget.objectPath,
                        thumbnailObjectPath: thumbnailObjectPath,
                        mediaEncryption: encryptedMain.metadata,
                        thumbnailEncryption: thumbnailEncryption
                    )))
                    return
                }

                let mediaTarget = StoragePathBuilder.build(
                    userId: senderId,
                    domain: .chatMedia(
                        conversationId: conversationId,
                        messageId: resolvedMessageId,
                        fileExtension: ext,
                        fileId: mediaFileId
                    )
                )

                let mediaUrl = try await uploader.upload(
                    target: mediaTarget,
                    payload: payload,
                    progress: { progressValue in
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MediaUploadProgress"),
                            object: nil,
                            userInfo: ["messageId": resolvedMessageId, "progress": progressValue]
                        )
                    }
                )

                for url in tempFilesToCleanup {
                    try? FileManager.default.removeItem(at: url)
                }

                var thumbnailUrl: String?
                if type == .video || type == .viewOnceVideo {
                    thumbnailUrl = try await generateVideoThumbnailURL(
                        from: data,
                        senderId: senderId,
                        conversationId: conversationId,
                        messageId: resolvedMessageId
                    )
                }

                completion(.success(ChatMediaUploadResult(
                    mediaUrl: mediaUrl,
                    thumbnailUrl: thumbnailUrl,
                    mediaObjectPath: nil,
                    thumbnailObjectPath: nil,
                    mediaEncryption: nil,
                    thumbnailEncryption: nil
                )))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Genera una miniatura ligera de una imagen (lado mayor ≤ 720px, JPEG ~0.6) para
    /// usarla en la vista previa de notificaciones. Devuelve nil si no se puede decodificar.
    private func generateImageThumbnailData(from imageData: Data) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }

        let maxDimension: CGFloat = 720
        let size = image.size
        let longestSide = max(size.width, size.height)

        let targetSize: CGSize
        if longestSide > maxDimension, longestSide > 0 {
            let scale = maxDimension / longestSide
            targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        } else {
            targetSize = size
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resized.jpegData(compressionQuality: 0.6)
    }

    private func generateVideoThumbnailURL(
        from videoData: Data,
        senderId: String,
        conversationId: String,
        messageId: String
    ) async throws -> String? {
        let tempVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat_video_thumb_\(UUID().uuidString).mp4")

        do {
            try videoData.write(to: tempVideoURL, options: .atomic)
        } catch {
            return nil
        }

        defer {
            try? FileManager.default.removeItem(at: tempVideoURL)
        }

        let asset = AVURLAsset(url: tempVideoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 720, height: 1280)

        let frameCandidates = [
            CMTime(seconds: 0.15, preferredTimescale: 600),
            CMTime(seconds: 0.0, preferredTimescale: 600),
            CMTime(seconds: 0.5, preferredTimescale: 600)
        ]

        var cgImage: CGImage?
        for time in frameCandidates {
            if let (candidate, _) = try? await imageGenerator.image(at: time) {
                cgImage = candidate
                break
            }
        }

        guard let cgImage,
              let thumbnailData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.78) else {
            return nil
        }

        let thumbTarget = StoragePathBuilder.build(
            userId: senderId,
            domain: .chatThumbnail(conversationId: conversationId, messageId: messageId)
        )
        return try await MediaUploadService.shared.upload(target: thumbTarget, payload: .data(thumbnailData))
    }

    private func generateVideoThumbnailData(from videoData: Data) async throws -> Data? {
        let tempVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat_video_thumb_\(UUID().uuidString).mp4")

        do {
            try videoData.write(to: tempVideoURL, options: .atomic)
        } catch {
            return nil
        }

        defer {
            try? FileManager.default.removeItem(at: tempVideoURL)
        }

        let asset = AVURLAsset(url: tempVideoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 720, height: 1280)

        let frameCandidates = [
            CMTime(seconds: 0.15, preferredTimescale: 600),
            CMTime(seconds: 0.0, preferredTimescale: 600),
            CMTime(seconds: 0.5, preferredTimescale: 600)
        ]

        for time in frameCandidates {
            if let (candidate, _) = try? await imageGenerator.image(at: time) {
                return UIImage(cgImage: candidate).jpegData(compressionQuality: 0.78)
            }
        }

        return nil
    }

    func deleteMediaFile(url: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !url.isEmpty else {
            completion(.failure(NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL inválida"])))
            return
        }

        if let localURL = URL(string: url), localURL.isFileURL {
            do {
                if FileManager.default.fileExists(atPath: localURL.path) {
                    try FileManager.default.removeItem(at: localURL)
                }
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
            return
        }

        let objectPath = StoragePathBuilder.extractObjectPath(from: url)
        let storageRef: StorageReference
        if objectPath.hasPrefix("http://") || objectPath.hasPrefix("https://") {
            storageRef = Storage.storage().reference(forURL: objectPath)
        } else {
            storageRef = Storage.storage().reference().child(objectPath)
        }

        storageRef.delete { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func deleteMediaFiles(urls: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        let group = DispatchGroup()
        var firstError: Error?

        for url in urls {
            group.enter()
            deleteMediaFile(url: url) { result in
                if case .failure(let error) = result, firstError == nil {
                    firstError = error
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let firstError {
                completion(.failure(firstError))
            } else {
                completion(.success(()))
            }
        }
    }

    private func getFileExtension(for type: MessageType) -> String {
        print("📤 ChatService: getFileExtension requested for type: \(type)")
        switch type {
        case .image, .viewOnceImage, .ephemeral: return "jpg"
        case .gif: return "gif"
        case .sticker: return "webp"
        case .video, .viewOnceVideo: return "mp4"
        case .audio: return "m4a"
        case .file: return "pdf"
        default:
            print("📤 ChatService: getFileExtension falling back to default (txt) for type: \(type)")
            return "txt"
        }
    }

    private func getContentType(for type: MessageType) -> String {
        switch type {
        case .image, .viewOnceImage, .ephemeral: return "image/jpeg"
        case .video, .viewOnceVideo: return "video/mp4"
        case .audio: return "audio/mp4"
        case .gif: return "image/gif"
        case .sticker: return "image/webp"
        case .file: return "application/pdf"
        default: return "text/plain"
        }
    }

    private func createLocalPreviewURL(
        data: Data,
        fileExtension: String,
        prefix: String
    ) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString).\(fileExtension)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func chatEncryptedStorageTarget(
        userId: String,
        conversationId: String,
        messageId: String,
        fileId: String,
        originalContentType: String,
        objectPath: String? = nil
    ) -> StorageUploadTarget {
        let path = objectPath ?? StoragePathBuilder.build(
            userId: userId,
            domain: .chatMedia(
                conversationId: conversationId,
                messageId: messageId,
                fileExtension: "enc",
                fileId: fileId
            )
        ).objectPath

        return StorageUploadTarget(
            objectPath: path,
            contentType: "application/octet-stream",
            customMetadata: [
                "ownerId": userId,
                "type": "chat_media_encrypted",
                "conversationId": conversationId,
                "messageId": messageId,
                "encrypted": "true",
                "originalContentType": originalContentType
            ]
        )
    }
}
