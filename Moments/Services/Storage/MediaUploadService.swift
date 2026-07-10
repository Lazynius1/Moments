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

    /// Subida cifrada. Reusa `startUpload` (que RETIENE el `StorageUploadTask` en `sessions`):
    /// si no se retiene, ARC lo libera, su deinit cancela el fetcher y el backend responde
    /// 400 "Upload has already finalized" sin guardar el archivo.
    func uploadEncryptedBlob(
        target: StorageUploadTarget,
        data: Data,
        progress: ((Double) -> Void)? = nil
    ) async throws -> String {
        var customMetadata = target.customMetadata
        customMetadata["returnObjectPath"] = "true" // startUpload devuelve el objectPath, no downloadURL
        let patchedTarget = StorageUploadTarget(
            objectPath: target.objectPath,
            contentType: target.contentType,
            customMetadata: customMetadata
        )

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.startUpload(
                path: patchedTarget.objectPath,
                target: patchedTarget,
                payload: .data(data),
                progress: progress
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Variante para ciphertext grande: Firebase lee el fichero progresivamente y
    /// no obliga a mantener el blob cifrado completo en memoria.
    func uploadEncryptedFile(
        target: StorageUploadTarget,
        fileURL: URL,
        progress: ((Double) -> Void)? = nil
    ) async throws -> String {
        var customMetadata = target.customMetadata
        customMetadata["returnObjectPath"] = "true"
        let patchedTarget = StorageUploadTarget(
            objectPath: target.objectPath,
            contentType: target.contentType,
            customMetadata: customMetadata
        )

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.startUpload(
                path: patchedTarget.objectPath,
                target: patchedTarget,
                payload: .file(fileURL),
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
        Task { @MainActor in
            do {
                let path = target.objectPath
                switch payload {
                case .data(let data):
                    if target.customMetadata["encrypted"] == "true" {
                        let result = try await self.uploadEncryptedBlob(target: target, data: data, progress: progress)
                        completion(.success(result))
                        return
                    }
                default:
                    break
                }
                self.startUpload(
                    path: path,
                    target: target,
                    payload: payload,
                    progress: progress,
                    completion: completion
                )
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func startUpload(
        path: String,
        target: StorageUploadTarget,
        payload: MediaUploadPayload,
        progress: ((Double) -> Void)?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let ref = storage.child(path)
        let metadata = StorageMetadata()
        metadata.contentType = target.contentType
        metadata.customMetadata = target.customMetadata
        // Solo chat cifrado devuelve objectPath; moments/stories necesitan downloadURL (token) para KFImage.
        let shouldResolveDownloadURL = target.customMetadata["returnObjectPath"] != "true"

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
            guard shouldResolveDownloadURL else {
                finish(.success(path))
                return
            }

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

    /// Convierte object path guardado en Firestore a URL HTTPS con token (para mostrar en feed/perfil).
    func resolveDownloadURL(forStoredValue pathOrURL: String, completion: @escaping (Result<String, Error>) -> Void) {
        let trimmed = pathOrURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            completion(.success(trimmed))
            return
        }

        let objectPath = StoragePathBuilder.extractObjectPath(from: trimmed)
        guard !objectPath.isEmpty else {
            completion(.failure(StorageError.invalidPath))
            return
        }

        storage.child(objectPath).downloadURL { url, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let absolute = url?.absoluteString else {
                completion(.failure(StorageError.urlRetrievalFailed))
                return
            }
            completion(.success(absolute))
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
