import FirebaseStorage
import UIKit
import AVFoundation
import FirebaseFirestore // 🔥 NUEVO IMPORT

enum StorageError: Error {
    case invalidData
    case uploadFailed
    case urlRetrievalFailed
    case deleteFailed
    case invalidPath
}

struct UploadMediaItem {
    let type: MediaType
    let image: UIImage? // For image uploads
    let videoURL: URL?  // For video uploads
}

enum MediaType: String, Codable {
    case image
    case video
}

// MARK: - 🔥 NUEVO ERROR TYPE PARA MODERACIÓN
enum ModerationError: Error, LocalizedError {
    case contentRejected(String)
    
    var errorDescription: String? {
        switch self {
        case .contentRejected(let reason):
            return "Contenido no permitido: \(reason)"
        }
    }
}

class StorageService {
    private let storage = Storage.storage().reference()
    
    // MARK: - FUNCIÓN: Específica para fotos de perfil (SIN PROCESAMIENTO - ya viene recortada)
    func uploadProfileImage(userId: String, image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        let fileName = "\(UUID().uuidString)_\(userId)"
        let profileRef = storage.child("images/\(fileName).jpg")
        
        // ✅ NO PROCESAR - la imagen ya viene perfectamente recortada del PhotoCropEditorView
        // let processedImage = processProfileImage(image)
        
        // Compresión optimizada para avatars
        guard let imageData = image.jpegData(compressionQuality: 0.75) else {
            completion(.failure(StorageError.invalidData))
            return
        }
        
        // Configure metadata
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.customMetadata = ["type": "profile_picture"] // Marcar como foto de perfil
        
        
        profileRef.putData(imageData, metadata: metadata) { metadata, error in
            if let error = error {
                completion(.failure(StorageError.uploadFailed))
                return
            }
            
            // Retrieve download URL
            profileRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(StorageError.urlRetrievalFailed))
                    return
                }
                if let downloadURL = url?.absoluteString {
                    completion(.success(downloadURL))
                } else {
                    completion(.failure(StorageError.urlRetrievalFailed))
                }
            }
        }
    }
    
    // MARK: - FUNCIÓN AUXILIAR: Procesar imagen de perfil
    private func processProfileImage(_ image: UIImage) -> UIImage {
        let targetSize = CGSize(width: 400, height: 400)

        // Calcular el rect para centrar la imagen manteniendo aspect ratio
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return image
        }

        let scale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        
        let drawRect = CGRect(
            x: (targetSize.width - scaledWidth) / 2,
            y: (targetSize.height - scaledHeight) / 2,
            width: scaledWidth,
            height: scaledHeight
        )

        return UIGraphicsImageRenderer(size: targetSize).image { _ in
            image.draw(in: drawRect)
        }
    }
    
    // MARK: - 🔥 FUNCIÓN PRINCIPAL ACTUALIZADA: uploadMedia - AHORA CON MODERACIÓN
    func uploadMedia(
        userId: String,
        mediaItem: UploadMediaItem,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let fileName = "\(UUID().uuidString)_\(userId)"

        
        switch mediaItem.type {
        case .image:
            uploadImageMedia(image: mediaItem.image, fileName: fileName, userId: userId, progress: progress, completion: completion)
            
        case .video:
            uploadVideoMedia(videoURL: mediaItem.videoURL, fileName: fileName, userId: userId, progress: progress, completion: completion)
        }
    }
    
    // 🔥 FUNCIÓN ACTUALIZADA: Upload de imagen SIN moderación automática
    private func uploadImageMedia(
        image: UIImage?,
        fileName: String,
        userId: String,
        progress: ((Double) -> Void)?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let image = image,
              image.size.width > 0,
              image.size.height > 0 else {
            completion(.failure(StorageError.invalidData))
            return
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(StorageError.invalidData))
            return
        }
        
        let imageRef = storage.child("images/\(fileName).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        
        let uploadTask = imageRef.putData(imageData, metadata: metadata) { _, error in
            if let error = error {
                completion(.failure(StorageError.uploadFailed))
                return
            }
            
            imageRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(StorageError.urlRetrievalFailed))
                    return
                }
                
                guard let downloadURL = url?.absoluteString else {
                    completion(.failure(StorageError.urlRetrievalFailed))
                    return
                }
                
                
                // 🔥 SOLO DEVOLVER ÉXITO - SIN MODERACIÓN AQUÍ
                completion(.success(downloadURL))
                
                // 🚫 MODERACIÓN REMOVIDA - Se hará en BackgroundMomentUploadService
            }
        }

        uploadTask.observe(.progress) { snapshot in
            guard let uploadProgress = snapshot.progress, uploadProgress.totalUnitCount > 0 else { return }
            progress?(Double(uploadProgress.completedUnitCount) / Double(uploadProgress.totalUnitCount))
        }
    }

    // 🔥 FUNCIÓN ACTUALIZADA: Upload de video SIN moderación automática
    private func uploadVideoMedia(
        videoURL: URL?,
        fileName: String,
        userId: String,
        progress: ((Double) -> Void)?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let sourceURL = videoURL else {
            completion(.failure(StorageError.invalidData))
            return
        }
        
        
        // Verificar que el archivo existe
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            completion(.failure(StorageError.invalidData))
            return
        }
        
        // ✅ PASO 1: Copiar a directorio temporal
        copyVideoToTemp(from: sourceURL) { [weak self] tempResult in
            switch tempResult {
            case .success(let tempURL):
                
                // ✅ PASO 2: Subir desde directorio temporal
                self?.uploadVideoFromTemp(tempURL: tempURL, fileName: fileName, userId: userId, progress: progress) { uploadResult in
                    // ✅ PASO 3: Limpiar archivo temporal
                    self?.cleanupTempFile(at: tempURL)
                    
                    // ✅ PASO 4: Retornar resultado
                    completion(uploadResult)
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // ✅ FUNCIÓN: Copiar video a directorio temporal (SIN CAMBIOS)
    private func copyVideoToTemp(from sourceURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        
        // Crear URL temporal única
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileName = "video_\(UUID().uuidString).mov"
        let tempURL = tempDir.appendingPathComponent(tempFileName)
        
        
        // Copiar en background
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Eliminar si ya existe
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                
                // Obtener tamaño original
                let originalAttributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
                let originalSize = originalAttributes[.size] as? Int64 ?? 0
                
                
                // Copiar archivo
                try FileManager.default.copyItem(at: sourceURL, to: tempURL)
                
                // Verificar copia
                guard FileManager.default.fileExists(atPath: tempURL.path) else {
                    throw StorageError.invalidData
                }
                
                let copiedAttributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                let copiedSize = copiedAttributes[.size] as? Int64 ?? 0
                
                
                DispatchQueue.main.async {
                    completion(.success(tempURL))
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // 🔥 FUNCIÓN ACTUALIZADA: Upload desde directorio temporal SIN moderación
    private func uploadVideoFromTemp(
        tempURL: URL,
        fileName: String,
        userId: String,
        progress: ((Double) -> Void)?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        
        let videoRef = storage.child("videos/\(fileName).mp4")
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        metadata.customMetadata = [
            "uploadTime": "\(Date().timeIntervalSince1970)",
            "tempFile": tempURL.lastPathComponent
        ]
        
        
        // Crear tarea de upload
        let uploadTask = videoRef.putFile(from: tempURL, metadata: metadata)
        
        // Observar progreso
        uploadTask.observe(.progress) { snapshot in
            guard let uploadProgress = snapshot.progress, uploadProgress.totalUnitCount > 0 else { return }
            progress?(Double(uploadProgress.completedUnitCount) / Double(uploadProgress.totalUnitCount))
        }
        
        // Observar éxito
        uploadTask.observe(.success) { snapshot in
            
            // Obtener URL de descarga
            videoRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(StorageError.urlRetrievalFailed))
                    return
                }
                
                guard let downloadURL = url?.absoluteString else {
                    completion(.failure(StorageError.urlRetrievalFailed))
                    return
                }
                
                
                // 🔥 SOLO DEVOLVER ÉXITO - SIN MODERACIÓN AQUÍ
                completion(.success(downloadURL))
                
                // 🚫 MODERACIÓN REMOVIDA - Se hará en BackgroundMomentUploadService
            }
        }
        
        // Observar fallo
        uploadTask.observe(.failure) { snapshot in
            if let error = snapshot.error as NSError? {
                
                // Analizar tipo de error
                switch error.code {
                case -1:
                    // Unknown error
                    break
                case -1001:
                    // Timeout error
                    break
                case -1009:
                    // Network connection lost
                    break
                default:
                    // Other error
                    break
                }
            }
            
            completion(.failure(StorageError.uploadFailed))
        }
        
        // Asegurar que la tarea inicie
        uploadTask.resume()
    }

    // ✅ FUNCIÓN: Limpiar archivo temporal (SIN CAMBIOS)
    private func cleanupTempFile(at url: URL) {
        DispatchQueue.global(qos: .utility).async {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } catch {
            }
        }
    }
    
    // MARK: - 🚨 ALERTA DE MODERACIÓN (placeholder)
    private func showModerationAlert(reason: String, category: String) {
        
        let alert = UIAlertController(
            title: "Contenido no permitido",
            message: "Tu publicación no cumple con nuestras normas de comunidad y ha sido eliminada.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Entendido", style: .default))
        
        // Mostrar en el view controller actual
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    // MARK: - FUNCIÓN: Borrar archivo de Storage
    func deleteMedia(path: String, completion: @escaping (Error?) -> Void) {
        
        // Verificar que el path no esté vacío
        guard !path.isEmpty else {
            completion(StorageError.invalidPath)
            return
        }
        
        // Si es una URL completa de Firebase Storage, extraer el path
        let storagePath: String
        if path.hasPrefix("https://firebasestorage.googleapis.com") {
            storagePath = extractPathFromURL(path)
        } else {
            storagePath = path
        }
        
        // Crear referencia y borrar
        let fileRef = storage.child(storagePath)
        fileRef.delete { error in
            if let error = error {
                completion(StorageError.deleteFailed)
            } else {
                completion(nil)
            }
        }
    }
    
    // MARK: - FUNCIÓN AUXILIAR: Extraer path de URL de Firebase Storage
    private func extractPathFromURL(_ url: String) -> String {
        // URL típica: https://firebasestorage.googleapis.com/v0/b/tu-proyecto/o/images%2Farchivo.jpg?alt=media
        // Necesitamos extraer: images/archivo.jpg
        
        guard let urlComponents = URLComponents(string: url),
              let pathComponent = urlComponents.path.components(separatedBy: "/o/").last else {
            return url // Devolver original como fallback
        }
        
        // Remover parámetros de query (?alt=media)
        let pathWithoutQuery = pathComponent.components(separatedBy: "?").first ?? pathComponent
        
        // Decodificar URL encoding (%2F -> /)
        let decodedPath = pathWithoutQuery.removingPercentEncoding ?? pathWithoutQuery
        
        return decodedPath
    }
    
    // MARK: - FUNCIÓN AUXILIAR: Borrar imagen de perfil anterior
    func deleteProfileImage(userId: String, oldImagePath: String?, completion: @escaping (Error?) -> Void) {
        guard let oldPath = oldImagePath, !oldPath.isEmpty else {
            completion(nil)
            return
        }
        
        // Verificar que sea una imagen de Firebase Storage (no externa)
        guard oldPath.contains("firebasestorage.googleapis.com") || oldPath.hasPrefix("images/") else {
            completion(nil)
            return
        }
        
        // Borrar la imagen anterior
        deleteMedia(path: oldPath, completion: completion)
    }
}
