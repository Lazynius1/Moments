import FirebaseStorage
import Foundation
import UIKit

enum MediaUploadPayload {
    case data(Data)
    case file(URL)
}

private final class UploadSession {
    let objectPath: String
    let task: StorageUploadTask
    var didFinish = false
    var progressHandle: String?
    var successHandle: String?
    var failureHandle: String?

    init(objectPath: String, task: StorageUploadTask) {
        self.objectPath = objectPath
        self.task = task
    }

    func removeObservers() {
        if let progressHandle { task.removeObserver(withHandle: progressHandle) }
        if let successHandle { task.removeObserver(withHandle: successHandle) }
        if let failureHandle { task.removeObserver(withHandle: failureHandle) }
        progressHandle = nil
        successHandle = nil
        failureHandle = nil
    }

    deinit {
        removeObservers()
    }
}

final class MediaUploadService {
    static let shared = MediaUploadService()

    private let storage = Storage.storage().reference()
    private var sessions: [String: UploadSession] = [:]
    private let sessionLock = NSLock()

    private init() {}

    func upload(
        target: StorageUploadTarget,
        payload: MediaUploadPayload,
        progress: ((Double) -> Void)? = nil
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            upload(
                target: target,
                payload: payload,
                progress: progress
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    func upload(
        target: StorageUploadTarget,
        payload: MediaUploadPayload,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let path = target.objectPath

        let ref = storage.child(path)
        let metadata = StorageMetadata()
        metadata.contentType = target.contentType
        metadata.customMetadata = target.customMetadata

        let uploadTask: StorageUploadTask
        switch payload {
        case .data(let data):
            uploadTask = ref.putData(data, metadata: metadata)
        case .file(let url):
            uploadTask = ref.putFile(from: url, metadata: metadata)
        }

        let session = UploadSession(objectPath: path, task: uploadTask)
        sessionLock.lock()
        sessions[path] = session
        sessionLock.unlock()

        var didCallCompletion = false
        func finish(_ result: Result<String, Error>) {
            sessionLock.lock()
            let tracked = sessions[path]
            sessionLock.unlock()

            tracked?.removeObservers()
            tracked?.didFinish = true

            sessionLock.lock()
            sessions.removeValue(forKey: path)
            sessionLock.unlock()

            guard !didCallCompletion else { return }
            didCallCompletion = true
            completion(result)
        }

        if let progress {
            session.progressHandle = uploadTask.observe(.progress) { snapshot in
                guard let uploadProgress = snapshot.progress, uploadProgress.totalUnitCount > 0 else { return }
                progress(Double(uploadProgress.completedUnitCount) / Double(uploadProgress.totalUnitCount))
            }
        }

        session.successHandle = uploadTask.observe(.success) { _ in
            ref.downloadURL { url, error in
                if let error {
                    finish(.failure(error))
                    return
                }
                guard let downloadURL = url?.absoluteString else {
                    finish(.failure(StorageError.urlRetrievalFailed))
                    return
                }
                finish(.success(downloadURL))
            }
        }

        session.failureHandle = uploadTask.observe(.failure) { snapshot in
            let error = snapshot.error ?? StorageError.uploadFailed
            finish(.failure(error))
        }
    }

    /// Cancela subidas activas cuyo path empieza por el prefijo (p. ej. users/{uid}/moments/{momentId}/).
    func cancelUploads(withPathPrefix prefix: String) {
        sessionLock.lock()
        let paths = sessions.keys.filter { $0.hasPrefix(prefix) }
        sessionLock.unlock()

        for path in paths {
            sessionLock.lock()
            let session = sessions[path]
            sessionLock.unlock()

            guard let session, !session.didFinish else { continue }

            session.task.cancel()
            session.removeObservers()
            session.didFinish = true

            sessionLock.lock()
            sessions.removeValue(forKey: path)
            sessionLock.unlock()
        }
    }

    func delete(pathOrURL: String, completion: @escaping (Error?) -> Void) {
        let objectPath = StoragePathBuilder.extractObjectPath(from: pathOrURL)
        guard !objectPath.isEmpty else {
            completion(StorageError.invalidPath)
            return
        }
        storage.child(objectPath).delete { error in
            completion(error)
        }
    }
}
