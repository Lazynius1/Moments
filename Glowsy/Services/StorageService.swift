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
        
        print("📷 Subiendo foto de perfil: \(imageData.count / 1024)KB (ya recortada)")
        
        profileRef.putData(imageData, metadata: metadata) { metadata, error in
            if let error = error {
                print("❌ Error uploading profile image: \(error.localizedDescription)")
                completion(.failure(StorageError.uploadFailed))
                return
            }
            
            // Retrieve download URL
            profileRef.downloadURL { url, error in
                if let error = error {
                    print("❌ Error retrieving download URL: \(error.localizedDescription)")
                    completion(.failure(StorageError.urlRetrievalFailed))
                    return
                }
                if let downloadURL = url?.absoluteString {
                    print("✅ Profile image uploaded successfully: \(downloadURL)")
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
        
        // Crear contexto de imagen con escala de pantalla
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        
        // Calcular el rect para centrar la imagen manteniendo aspect ratio
        let imageSize = image.size
        let scale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        
        let drawRect = CGRect(
            x: (targetSize.width - scaledWidth) / 2,
            y: (targetSize.height - scaledHeight) / 2,
            width: scaledWidth,
            height: scaledHeight
        )
        
        // Dibujar la imagen escalada y centrada
        image.draw(in: drawRect)
        
        // Obtener la imagen procesada
        guard let processedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            print("⚠️ Error procesando imagen, usando original")
            return image // Fallback a la imagen original
        }
        
        return processedImage
    }
    
    // MARK: - 🔥 FUNCIÓN PRINCIPAL ACTUALIZADA: uploadMedia - AHORA CON MODERACIÓN
    func uploadMedia(userId: String, mediaItem: UploadMediaItem, completion: @escaping (Result<String, Error>) -> Void) {
        let fileName = "\(UUID().uuidString)_\(userId)"
        
        print("🔍 DEBUG StorageService - uploadMedia CON MODERACIÓN:")
        print("  - Tipo: \(mediaItem.type.rawValue)")
        print("  - Usuario: \(userId)")
        print("  - Archivo: \(fileName)")
        
        switch mediaItem.type {
        case .image:
            uploadImageMedia(image: mediaItem.image, fileName: fileName, userId: userId, completion: completion)
            
        case .video:
            uploadVideoMedia(videoURL: mediaItem.videoURL, fileName: fileName, userId: userId, completion: completion)
        }
    }
    
    // 🔥 FUNCIÓN ACTUALIZADA: Upload de imagen SIN moderación automática
    private func uploadImageMedia(image: UIImage?, fileName: String, userId: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let image = image else {
            print("❌ Error: Imagen es nil")
            completion(.failure(StorageError.invalidData))
            return
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Error: No se pudo convertir imagen a data")
            completion(.failure(StorageError.invalidData))
            return
        }
        
        let imageRef = storage.child("images/\(fileName).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        print("📸 Subiendo imagen: \(imageData.count / 1024)KB")
        
        imageRef.putData(imageData, metadata: metadata) { _, error in
            if let error = error {
                print("❌ Error subiendo imagen: \(error)")
                completion(.failure(StorageError.uploadFailed))
                return
            }
            
            imageRef.downloadURL { url, error in
                if let error = error {
                    print("❌ Error obteniendo URL imagen: \(error)")
                    completion(.failure(StorageError.urlRetrievalFailed))
                    return
                }
                
                guard let downloadURL = url?.absoluteString else {
                    completion(.failure(StorageError.urlRetrievalFailed))
                    return
                }
                
                print("✅ Imagen subida: \(downloadURL)")
                
                // 🔥 SOLO DEVOLVER ÉXITO - SIN MODERACIÓN AQUÍ
                completion(.success(downloadURL))
                
                // 🚫 MODERACIÓN REMOVIDA - Se hará en BackgroundMomentUploadService
            }
        }
    }

    // 🔥 FUNCIÓN ACTUALIZADA: Upload de video SIN moderación automática
    private func uploadVideoMedia(videoURL: URL?, fileName: String, userId: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let sourceURL = videoURL else {
            print("❌ Error: VideoURL es nil")
            completion(.failure(StorageError.invalidData))
            return
        }
        
        print("🎥 Iniciando upload de video SIN MODERACIÓN:")
        print("  - Source URL: \(sourceURL)")
        print("  - Es file URL: \(sourceURL.isFileURL)")
        print("  - Path: \(sourceURL.path)")
        
        // Verificar que el archivo existe
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            print("❌ Error: Archivo de video no existe en \(sourceURL.path)")
            completion(.failure(StorageError.invalidData))
            return
        }
        
        // ✅ PASO 1: Copiar a directorio temporal
        copyVideoToTemp(from: sourceURL) { [weak self] tempResult in
            switch tempResult {
            case .success(let tempURL):
                print("✅ Video copiado a temp: \(tempURL.lastPathComponent)")
                
                // ✅ PASO 2: Subir desde directorio temporal
                self?.uploadVideoFromTemp(tempURL: tempURL, fileName: fileName, userId: userId) { uploadResult in
                    // ✅ PASO 3: Limpiar archivo temporal
                    self?.cleanupTempFile(at: tempURL)
                    
                    // ✅ PASO 4: Retornar resultado
                    completion(uploadResult)
                }
                
            case .failure(let error):
                print("❌ Error copiando video a temp: \(error)")
                completion(.failure(error))
            }
        }
    }

    // ✅ FUNCIÓN: Copiar video a directorio temporal (SIN CAMBIOS)
    private func copyVideoToTemp(from sourceURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        print("📁 Copiando video a directorio temporal...")
        
        // Crear URL temporal única
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileName = "video_\(UUID().uuidString).mov"
        let tempURL = tempDir.appendingPathComponent(tempFileName)
        
        print("  - Destino: \(tempURL.path)")
        
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
                
                print("  - Tamaño original: \(Double(originalSize)/1024.0/1024.0) MB")
                
                // Copiar archivo
                try FileManager.default.copyItem(at: sourceURL, to: tempURL)
                
                // Verificar copia
                guard FileManager.default.fileExists(atPath: tempURL.path) else {
                    throw StorageError.invalidData
                }
                
                let copiedAttributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                let copiedSize = copiedAttributes[.size] as? Int64 ?? 0
                
                print("  - ✅ Copiado: \(Double(copiedSize)/1024.0/1024.0) MB")
                
                DispatchQueue.main.async {
                    completion(.success(tempURL))
                }
                
            } catch {
                print("  - ❌ Error copiando: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // 🔥 FUNCIÓN ACTUALIZADA: Upload desde directorio temporal SIN moderación
    private func uploadVideoFromTemp(tempURL: URL, fileName: String, userId: String, completion: @escaping (Result<String, Error>) -> Void) {
        
        let videoRef = storage.child("videos/\(fileName).mp4")
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        metadata.customMetadata = [
            "uploadTime": "\(Date().timeIntervalSince1970)",
            "tempFile": tempURL.lastPathComponent
        ]
        
        print("🔥 Subiendo a Firebase Storage:")
        print("  - Referencia: videos/\(fileName).mp4")
        print("  - Archivo temporal: \(tempURL.lastPathComponent)")
        
        // Crear tarea de upload
        let uploadTask = videoRef.putFile(from: tempURL, metadata: metadata)
        
        // Observar progreso
        uploadTask.observe(.progress) { snapshot in
            if let progress = snapshot.progress {
                let percent = Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100
                print("📈 Progreso: \(Int(percent))% (\(progress.completedUnitCount)/\(progress.totalUnitCount) bytes)")
            }
        }
        
        // Observar éxito
        uploadTask.observe(.success) { snapshot in
            print("✅ Upload completado exitosamente")
            
            // Obtener URL de descarga
            videoRef.downloadURL { url, error in
                if let error = error {
                    print("❌ Error obteniendo download URL: \(error)")
                    completion(.failure(StorageError.urlRetrievalFailed))
                    return
                }
                
                guard let downloadURL = url?.absoluteString else {
                    print("❌ Error: Download URL es nil")
                    completion(.failure(StorageError.urlRetrievalFailed))
                    return
                }
                
                print("✅ Video subido exitosamente:")
                print("  - URL: \(downloadURL)")
                
                // 🔥 SOLO DEVOLVER ÉXITO - SIN MODERACIÓN AQUÍ
                completion(.success(downloadURL))
                
                // 🚫 MODERACIÓN REMOVIDA - Se hará en BackgroundMomentUploadService
            }
        }
        
        // Observar fallo
        uploadTask.observe(.failure) { snapshot in
            if let error = snapshot.error as NSError? {
                print("❌ Upload falló:")
                print("  - Código: \(error.code)")
                print("  - Dominio: \(error.domain)")
                print("  - Descripción: \(error.localizedDescription)")
                print("  - UserInfo: \(error.userInfo)")
                
                // Analizar tipo de error
                switch error.code {
                case -1:
                    print("  - Tipo: Error de red general")
                case -1001:
                    print("  - Tipo: Timeout")
                case -1009:
                    print("  - Tipo: Sin conexión")
                default:
                    print("  - Tipo: Error desconocido")
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
                    print("🗑️ Archivo temporal eliminado: \(url.lastPathComponent)")
                }
            } catch {
                print("⚠️ Error eliminando archivo temporal: \(error)")
            }
        }
    }
    
    // MARK: - 🚨 ALERTA DE MODERACIÓN (placeholder)
    private func showModerationAlert(reason: String, category: String) {
        print("🚨 === ALERTA DE MODERACIÓN ===")
        print("📱 Razón: \(reason)")
        print("🏷️ Categoría: \(category)")
        print("💬 Usuario sería notificado: 'Tu contenido no cumple con nuestras normas'")
        
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
        print("🗑️ Intentando borrar archivo: \(path)")
        
        // Verificar que el path no esté vacío
        guard !path.isEmpty else {
            print("⚠️ Path vacío, no se puede borrar")
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
                print("❌ Error al borrar archivo: \(error.localizedDescription)")
                completion(StorageError.deleteFailed)
            } else {
                print("✅ Archivo borrado correctamente: \(storagePath)")
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
            print("⚠️ No se pudo extraer path de URL: \(url)")
            return url // Devolver original como fallback
        }
        
        // Remover parámetros de query (?alt=media)
        let pathWithoutQuery = pathComponent.components(separatedBy: "?").first ?? pathComponent
        
        // Decodificar URL encoding (%2F -> /)
        let decodedPath = pathWithoutQuery.removingPercentEncoding ?? pathWithoutQuery
        
        print("🔄 Path extraído: \(decodedPath)")
        return decodedPath
    }
    
    // MARK: - FUNCIÓN AUXILIAR: Borrar imagen de perfil anterior
    func deleteProfileImage(userId: String, oldImagePath: String?, completion: @escaping (Error?) -> Void) {
        guard let oldPath = oldImagePath, !oldPath.isEmpty else {
            print("🔄 No hay imagen anterior que borrar")
            completion(nil)
            return
        }
        
        // Verificar que sea una imagen de Firebase Storage (no externa)
        guard oldPath.contains("firebasestorage.googleapis.com") || oldPath.hasPrefix("images/") else {
            print("🔄 Imagen anterior es externa, no se borra: \(oldPath)")
            completion(nil)
            return
        }
        
        // Borrar la imagen anterior
        deleteMedia(path: oldPath, completion: completion)
    }
}
