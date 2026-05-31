import FirebaseStorage
import UIKit
import AVFoundation

enum StorageError: Error {
    case invalidData
    case uploadFailed
    case urlRetrievalFailed
    case deleteFailed
    case invalidPath
}

struct UploadMediaItem {
    let type: MediaType
    let image: UIImage?
    let videoURL: URL?
}

enum MediaType: String, Codable {
    case image
    case video
}

enum ModerationError: Error, LocalizedError {
    case contentRejected(String)

    var errorDescription: String? {
        switch self {
        case .contentRejected(let reason):
            return "Contenido no permitido: \(reason)"
        }
    }
}

enum FeedMediaUploadContext {
    case moment(momentId: String, mediaId: String = UUID().uuidString)
    case story(storyId: String, mediaId: String = UUID().uuidString)
}

class StorageService {
    private let uploader = MediaUploadService.shared
    private let videoCompression = VideoCompressionService.shared
    private let encryptionService = EncryptionService.shared

    // MARK: - Profile

    func uploadProfileImage(userId: String, image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        guard let imageData = image.storageUploadJPEGData(compressionQuality: 0.75, maxPixelDimension: 1080) else {
            completion(.failure(StorageError.invalidData))
            return
        }

        let target = StoragePathBuilder.build(userId: userId, domain: .profileAvatar())
        uploader.upload(target: target, payload: .data(imageData)) { result in
            self.completeWithPublicDownloadURL(result, completion: completion)
        }
    }

    // MARK: - Feed media (moments / stories)

    func uploadNovaConversationImage(
        userId: String,
        conversationId: String,
        messageId: String,
        image: UIImage
    ) async throws -> String {
        guard let imageData = image.storageUploadJPEGData(compressionQuality: 0.82, maxPixelDimension: 1080) else {
            throw StorageError.invalidData
        }

        let target = StoragePathBuilder.build(
            userId: userId,
            domain: .novaConversationImage(conversationId: conversationId, messageId: messageId)
        )
        let purpose = "conversationImage|\(conversationId)|\(messageId)"
        let encryptedData = try await encryptionService.encryptNovaBlob(
            imageData,
            for: userId,
            purpose: purpose
        )
        return try await uploader.uploadEncryptedBlob(target: target, data: encryptedData)
    }

    func downloadNovaConversationImage(
        userId: String,
        conversationId: String,
        messageId: String,
        storedPath: String
    ) async throws -> UIImage {
        let objectPath = StoragePathBuilder.extractObjectPath(from: storedPath)
        guard !objectPath.isEmpty else {
            throw StorageError.invalidPath
        }

        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            Storage.storage().reference().child(objectPath).getData(maxSize: 15 * 1024 * 1024) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: StorageError.invalidData)
                    return
                }
                continuation.resume(returning: data)
            }
        }

        let purpose = "conversationImage|\(conversationId)|\(messageId)"
        let decryptedData = try await encryptionService.decryptNovaBlob(
            data,
            for: userId,
            purpose: purpose
        )
        guard let image = UIImage(data: decryptedData) else {
            throw StorageError.invalidData
        }
        return image
    }

    func uploadMedia(
        userId: String,
        mediaItem: UploadMediaItem,
        context: FeedMediaUploadContext,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        switch mediaItem.type {
        case .image:
            uploadFeedImage(
                image: mediaItem.image,
                userId: userId,
                context: context,
                progress: progress,
                completion: completion
            )
        case .video:
            uploadFeedVideo(
                videoURL: mediaItem.videoURL,
                userId: userId,
                context: context,
                progress: progress,
                completion: completion
            )
        }
    }

    func uploadMomentThumbnail(
        userId: String,
        momentId: String,
        image: UIImage,
        mediaId: String = UUID().uuidString,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let imageData = image.storageUploadJPEGData(compressionQuality: 0.8, maxPixelDimension: 720) else {
            completion(.failure(StorageError.invalidData))
            return
        }
        let target = StoragePathBuilder.build(
            userId: userId,
            domain: .momentThumbnail(momentId: momentId, mediaId: mediaId)
        )
        uploader.upload(target: target, payload: .data(imageData), progress: progress) { result in
            self.completeWithPublicDownloadURL(result, completion: completion)
        }
    }

    func uploadHiddenLayerImage(
        userId: String,
        momentId: String,
        layerId: String,
        image: UIImage,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let imageData = image.storageUploadJPEGData(compressionQuality: 0.82, maxPixelDimension: 1080) else {
            completion(.failure(StorageError.invalidData))
            return
        }
        let target = StoragePathBuilder.build(
            userId: userId,
            domain: .momentHiddenLayerImage(momentId: momentId, layerId: layerId)
        )
        uploader.upload(target: target, payload: .data(imageData)) { result in
            self.completeWithPublicDownloadURL(result, completion: completion)
        }
    }

    func uploadHiddenLayerAudio(
        userId: String,
        momentId: String,
        layerId: String,
        audioURL: URL,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let target = StoragePathBuilder.build(
            userId: userId,
            domain: .momentHiddenLayerAudio(momentId: momentId, layerId: layerId)
        )
        uploader.upload(target: target, payload: .file(audioURL)) { result in
            self.completeWithPublicDownloadURL(result, completion: completion)
        }
    }

    // MARK: - Delete

    func deleteMedia(path: String, completion: @escaping (Error?) -> Void) {
        guard !path.isEmpty else {
            completion(StorageError.invalidPath)
            return
        }
        uploader.delete(pathOrURL: path) { error in
            if error != nil {
                completion(StorageError.deleteFailed)
            } else {
                completion(nil)
            }
        }
    }

    func deleteMedia(path: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            deleteMedia(path: path) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func deleteProfileImage(userId: String, oldImagePath: String?, completion: @escaping (Error?) -> Void) {
        guard let oldPath = oldImagePath, !oldPath.isEmpty else {
            completion(nil)
            return
        }

        guard oldPath.contains("firebasestorage.googleapis.com")
            || oldPath.hasPrefix("images/")
            || oldPath.hasPrefix("users/") else {
            completion(nil)
            return
        }

        deleteMedia(path: oldPath, completion: completion)
    }

    // MARK: - Private upload helpers

    /// Asegura URL HTTPS con token; corrige subidas antiguas que guardaron solo object path.
    private func completeWithPublicDownloadURL(
        _ result: Result<String, Error>,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        switch result {
        case .failure(let error):
            completion(.failure(error))
        case .success(let value):
            if value.hasPrefix("https://") || value.hasPrefix("http://") {
                completion(.success(value))
                return
            }
            uploader.resolveDownloadURL(forStoredValue: value, completion: completion)
        }
    }

    private func uploadFeedImage(
        image: UIImage?,
        userId: String,
        context: FeedMediaUploadContext,
        progress: ((Double) -> Void)?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let image,
              let imageData = image.storageUploadJPEGData(compressionQuality: 0.8, maxPixelDimension: 1280) else {
            completion(.failure(StorageError.invalidData))
            return
        }

        let target: StorageUploadTarget
        switch context {
        case .moment(let momentId, let mediaId):
            target = StoragePathBuilder.momentImageTarget(userId: userId, momentId: momentId, mediaId: mediaId)
        case .story(let storyId, let mediaId):
            target = StoragePathBuilder.storyImageTarget(userId: userId, storyId: storyId, mediaId: mediaId)
        }

        uploader.upload(target: target, payload: .data(imageData), progress: progress) { result in
            self.completeWithPublicDownloadURL(result, completion: completion)
        }
    }

    private func uploadFeedVideo(
        videoURL: URL?,
        userId: String,
        context: FeedMediaUploadContext,
        progress: ((Double) -> Void)?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let sourceURL = videoURL, FileManager.default.fileExists(atPath: sourceURL.path) else {
            completion(.failure(StorageError.invalidData))
            return
        }

        Task {
            do {
                let preset: VideoCompressionPreset
                switch context {
                case .moment: preset = .moment
                case .story: preset = .story
                }

                let preparedURL = try await videoCompression.prepareVideoForUpload(
                    inputURL: sourceURL,
                    preset: preset
                )

                let target: StorageUploadTarget
                switch context {
                case .moment(let momentId, let mediaId):
                    target = StoragePathBuilder.build(
                        userId: userId,
                        domain: .momentMedia(momentId: momentId, mediaId: mediaId)
                    )
                case .story(let storyId, let mediaId):
                    target = StoragePathBuilder.build(
                        userId: userId,
                        domain: .storyMedia(storyId: storyId, mediaId: mediaId)
                    )
                }

                self.uploader.upload(target: target, payload: .file(preparedURL), progress: progress) { result in
                    if preparedURL != sourceURL {
                        try? FileManager.default.removeItem(at: preparedURL)
                    }
                    self.completeWithPublicDownloadURL(result, completion: completion)
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}
