// BackgroundStoryUploadService.swift
import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import AVFoundation
import FirebaseStorage
import ActivityKit
import UIKit

// ✅ Importar para usar StickerPickerView.sendMentionNotificationsForStory

// MARK: - 📱 MODELO DE HISTORIA EN PROGRESO
class UploadingStory: ObservableObject, Identifiable {
    let id = UUID()
    let tempId: String
    let userId: String
    let mediaItem: ProcessedMedia
    let storyText: String?
    let textPosition: CGPoint?
    let selectedTextStyle: Any?
    let stickerData: [StickerItem]?
    let drawingData: Data?
    let audienceSetting: ContentAudience
    let customViewers: [String]?
    let customListId: String?
    let selectedListName: String?
    let createdAt: Date
    let finalRenderedImage: UIImage? // ✅ NUEVA: Imagen renderizada final para detectar aspect ratio
    let chainId: String? // 🔗 AÑADIDO: ID de la cadena
    let chainPosition: Int? // 🔗 AÑADIDO: Posición en la cadena
    let chainTitle: String? // 🔗 AÑADIDO: Título de la cadena
    let allowOthersToContinue: Bool? // 🔗 AÑADIDO: Si otros pueden continuar la cadena
    let continuationAudience: ContentAudience? // 🔗 AÑADIDO: Audiencia que puede continuar
    let continuationCustomViewers: [String]? // 🔗 AÑADIDO: Usuarios específicos que pueden continuar
    let continuationCustomListId: String? // 🔗 AÑADIDO: Lista específica que puede continuar
    let continuationCustomListName: String? // 🔗 AÑADIDO: Nombre de la lista que puede continuar
    
    @Published var uploadProgress: Double = 0.0
    @Published var status: UploadStatus = .uploading
    @Published var errorMessage: String?
    @Published var storyId: String? // Para almacenar el ID real de Firestore
    
    // 🔥 PARA MOSTRAR EN EL HEADER
    @Published var thumbnailImage: UIImage?
    
    init(
        userId: String,
        mediaItem: ProcessedMedia,
        storyText: String?,
        textPosition: CGPoint?,
        selectedTextStyle: Any?,
        stickerData: [StickerItem]?,
        drawingData: Data?,
        audienceSetting: ContentAudience,
        customViewers: [String]?,
        customListId: String?,
        selectedListName: String?,
        finalRenderedImage: UIImage? = nil, // ✅ NUEVO: Parámetro opcional
        chainId: String? = nil, // 🔗 AÑADIDO: ID de la cadena
        chainPosition: Int? = nil, // 🔗 AÑADIDO: Posición en la cadena
        chainTitle: String? = nil, // 🔗 AÑADIDO: Título de la cadena
        allowOthersToContinue: Bool? = nil, // 🔗 AÑADIDO: Si otros pueden continuar la cadena
        continuationAudience: ContentAudience? = nil, // 🔗 AÑADIDO: Audiencia que puede continuar
        continuationCustomViewers: [String]? = nil, // 🔗 AÑADIDO: Usuarios específicos que pueden continuar
        continuationCustomListId: String? = nil, // 🔗 AÑADIDO: Lista específica que puede continuar
        continuationCustomListName: String? = nil // 🔗 AÑADIDO: Nombre de la lista que puede continuar
    ) {
        self.tempId = "temp_story_\(UUID().uuidString)"
        self.userId = userId
        self.mediaItem = mediaItem
        self.storyText = storyText
        self.textPosition = textPosition
        self.selectedTextStyle = selectedTextStyle
        self.stickerData = stickerData
        self.drawingData = drawingData
        self.audienceSetting = audienceSetting
        self.customViewers = customViewers
        self.customListId = customListId
        self.selectedListName = selectedListName
        self.finalRenderedImage = finalRenderedImage // ✅ NUEVO: Asignar la imagen renderizada
        self.chainId = chainId // 🔗 AÑADIDO: Asignar ID de la cadena
        self.chainPosition = chainPosition // 🔗 AÑADIDO: Asignar posición en la cadena
        self.chainTitle = chainTitle // 🔗 AÑADIDO: Asignar título de la cadena
        self.allowOthersToContinue = allowOthersToContinue // 🔗 AÑADIDO: Asignar si otros pueden continuar
        self.continuationAudience = continuationAudience // 🔗 AÑADIDO: Asignar audiencia que puede continuar
        self.continuationCustomViewers = continuationCustomViewers // 🔗 AÑADIDO: Asignar usuarios específicos
        self.continuationCustomListId = continuationCustomListId // 🔗 AÑADIDO: Asignar lista específica
        self.continuationCustomListName = continuationCustomListName // 🔗 AÑADIDO: Asignar nombre de lista
        self.createdAt = Date()
        
        // Configurar thumbnail
        self.thumbnailImage = mediaItem.image
    }
}

// MARK: - 🔥 SERVICIO PRINCIPAL DE STORIES
class BackgroundStoryUploadService: ObservableObject {
    static let shared = BackgroundStoryUploadService()
    
    @Published var uploadingStory: UploadingStory? // Solo una historia a la vez
    @Published var isProcessing = false
    
    // ✅ NUEVO: Live Activity para Dynamic Island
    @available(iOS 16.1, *)
    private var liveActivity: Activity<StoryUploadActivityAttributes>?
    
    private init() {}
    
    // MARK: - 📤 FUNCIÓN PRINCIPAL: Iniciar upload de historia en background
    func uploadStory(
        mediaItem: ProcessedMedia,
        storyText: String?,
        textPosition: CGPoint?,
        selectedTextStyle: Any?,
        stickerData: [StickerItem]?,
        drawingData: Data?,
        audienceSetting: ContentAudience,
        customViewers: [String]?,
        customListId: String?,
        selectedListName: String?,
        finalRenderedImage: UIImage? = nil, // Para historias con overlays renderizados
        chainId: String? = nil, // 🔗 AÑADIDO: ID de la cadena
        chainPosition: Int? = nil, // 🔗 AÑADIDO: Posición en la cadena
        chainTitle: String? = nil, // 🔗 AÑADIDO: Título de la cadena
        allowOthersToContinue: Bool? = nil, // 🔗 AÑADIDO: Si otros pueden continuar la cadena
        continuationAudience: ContentAudience? = nil, // 🔗 AÑADIDO: Audiencia que puede continuar
        continuationCustomViewers: [String]? = nil, // 🔗 AÑADIDO: Usuarios específicos que pueden continuar
        continuationCustomListId: String? = nil, // 🔗 AÑADIDO: Lista específica que puede continuar
        continuationCustomListName: String? = nil // 🔗 AÑADIDO: Nombre de la lista que puede continuar
    ) -> UploadingStory? {
        
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        
        
        // Si ya hay una historia subiendo, cancelar la anterior
        if let existingStory = uploadingStory {
            cancelUpload(existingStory)
        }
        
        // 🔥 PREPARAR MEDIA ITEM (con imagen renderizada si existe)
        let finalMediaItem: ProcessedMedia
        if let finalImage = finalRenderedImage {
            // ✅ OPTIMIZAR IMAGEN RENDERIZADA para historias
            let optimizedImage = optimizeImageForStory(finalImage)
            finalMediaItem = ProcessedMedia(
                id: mediaItem.id,
                image: optimizedImage,
                videoURL: mediaItem.videoURL, // 🔥 videoURL va antes que type
                type: mediaItem.type,
                aspectRatio: mediaItem.aspectRatio
            )
        } else {
            // ✅ OPTIMIZAR IMAGEN ORIGINAL para historias
            let optimizedImage = optimizeImageForStory(mediaItem.image)
            finalMediaItem = ProcessedMedia(
                id: mediaItem.id,
                image: optimizedImage,
                videoURL: mediaItem.videoURL,
                type: mediaItem.type,
                aspectRatio: mediaItem.aspectRatio
            )
        }
        
        // Crear historia temporal
        let uploadingStory = UploadingStory(
            userId: userId,
            mediaItem: finalMediaItem, // 🔥 USAR EL MEDIA ITEM CORRECTO
            storyText: storyText,
            textPosition: textPosition,
            selectedTextStyle: selectedTextStyle,
            stickerData: stickerData,
            drawingData: drawingData,
            audienceSetting: audienceSetting,
            customViewers: customViewers,
            customListId: customListId,
            selectedListName: selectedListName,
            finalRenderedImage: finalRenderedImage, // ✅ NUEVO: Pasar la imagen renderizada
            chainId: chainId, // 🔗 AÑADIDO: Pasar ID de la cadena
            chainPosition: chainPosition, // 🔗 AÑADIDO: Pasar posición en la cadena
            chainTitle: chainTitle, // 🔗 AÑADIDO: Pasar título de la cadena
            allowOthersToContinue: allowOthersToContinue, // 🔗 AÑADIDO: Pasar si otros pueden continuar
            continuationAudience: continuationAudience, // 🔗 AÑADIDO: Pasar audiencia que puede continuar
            continuationCustomViewers: continuationCustomViewers, // 🔗 AÑADIDO: Pasar usuarios específicos
            continuationCustomListId: continuationCustomListId, // 🔗 AÑADIDO: Pasar lista específica
            continuationCustomListName: continuationCustomListName // 🔗 AÑADIDO: Pasar nombre de lista
        )
        
        // Mostrar en el header inmediatamente
        DispatchQueue.main.async {
            self.uploadingStory = uploadingStory
            self.isProcessing = true
        }
        
        // ✅ NUEVO: Iniciar Live Activity para Dynamic Island
        if #available(iOS 16.1, *) {
            Task { @MainActor in
                await startLiveActivity(for: uploadingStory)
            }
        }
        
        // ✅ NUEVO: SOLICITUD DE BACKGROUND TASK
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "StoryUpload") {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        
        // Procesar en background
        Task.detached(priority: .userInitiated) {
            await self.processStoryUpload(uploadingStory)
            
            // ✅ Terminar background task
            DispatchQueue.main.async {
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }
        }
        
        return uploadingStory
    }
    
    // MARK: - 🔄 PROCESAMIENTO COMPLETO DE HISTORIA
    private func processStoryUpload(_ uploadingStory: UploadingStory) async {
        
        do {
            // PASO 1: Preparar media item para upload (0% - 20%)
            let uploadMediaItem = try await prepareMediaItem(uploadingStory)
            await updateProgress(uploadingStory, progress: 0.2)
            
            // PASO 2: Upload archivo (20% - 70%)
            let mediaUrl = try await uploadStoryMedia(uploadingStory, uploadMediaItem: uploadMediaItem)
            await updateProgress(uploadingStory, progress: 0.7)
            
            // PASO 3: Crear historia en Firestore (70% - 90%)
            await updateProgress(uploadingStory, progress: 0.8, status: .processing)
            let storyId = try await createStoryInFirestore(uploadingStory, mediaUrl: mediaUrl)
            await MainActor.run {
                uploadingStory.storyId = storyId
            }
            
            // PASO 4: Completado (90% - 100%)
            await updateProgress(uploadingStory, progress: 1.0, status: .completed)
            
            // ✅ NUEVO: Actualizar Live Activity a estado "completed" y esperar unos segundos antes de cerrar
            if #available(iOS 16.1, *) {
                // Actualizar primero el estado a "completed" y esperar a que se complete
                await updateLiveActivityAsync(progress: 1.0, status: "completed")
                // Esperar 3 segundos para mostrar el emoji antes de cerrar
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 segundos
                await endLiveActivityAsync()
            }
            
            // PASO 5: Moderar en background silencioso
            Task.detached(priority: .background) {
                await self.moderateStoryContentSilently(
                    storyId: storyId,
                    uploadingStory: uploadingStory,
                    mediaUrl: mediaUrl
                )
            }
            
            // PASO 6: Procesar stickers interactivos con storyId real
            if let stickerData = uploadingStory.stickerData {
                // Procesar menciones
                let mentionStickers = stickerData.filter { $0.type == .mention }
                if !mentionStickers.isEmpty {
                    StickerPickerView.sendMentionNotificationsForStory(
                        storyId: storyId, // ✅ Usar storyId real
                        stickers: mentionStickers
                    )
                }
                
                // ✅ NUEVO: Procesar polls
                let pollStickers = stickerData.filter { $0.type == .poll }
                if !pollStickers.isEmpty {
                    await setupPollStickers(storyId: storyId, stickers: pollStickers)
                }
                
                // ✅ NUEVO: Procesar questions
                let questionStickers = stickerData.filter { $0.type == .question }
                if !questionStickers.isEmpty {
                    await setupQuestionStickers(storyId: storyId, stickers: questionStickers)
                }
                
                // ✅ NUEVO: Procesar question responses
                let questionResponseStickers = stickerData.filter { $0.type == .questionResponse }
                if !questionResponseStickers.isEmpty {
                    await setupQuestionResponseStickers(storyId: storyId, stickers: questionResponseStickers)
                }
                
                // ✅ NUEVO: Procesar weather stickers
                let weatherStickers = stickerData.filter { $0.type == .weather }
                if !weatherStickers.isEmpty {
                    await setupWeatherStickers(storyId: storyId, stickers: weatherStickers)
                }
            }
            
            // PASO 7: Remover del header después de 2 segundos
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NotificationCenter.default.post(name: NSNotification.Name("StoryUploaded"), object: nil)
                self.removeUploadingStory()
            }
            
        } catch {
            await updateProgress(uploadingStory, progress: 0.0, status: .failed, error: error.localizedDescription)
            
            // ✅ NUEVO: Finalizar Live Activity en caso de error
            if #available(iOS 16.1, *) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.endLiveActivity()
                }
            }
        }
        
        await MainActor.run {
            self.isProcessing = false
        }
    }
    
    // MARK: - 📁 PREPARAR MEDIA ITEM
    // ✅ COMPRESIÓN SIMPLE - PRESERVAR DIMENSIONES ORIGINALES
    // MARK: - 🎥 COMPRESIÓN DE VIDEO (Optimizado a 720p - Igual que Feed)
    private func compressVideoForStory(_ inputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        
        // 1. Crear URL de destino
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("compressed_story_\(UUID().uuidString).mp4")
        
        // 2. Configurar Export Session (Preset 720p para balance calidad/tamaño)
        // Esto reduce videos de 100MB+ a ~10-15MB con muy buena calidad visual en móvil
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw NSError(domain: "CompressionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo crear export session"])
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // 3. Exportar
        await exportSession.export()
        
        // 4. Verificar resultado
        switch exportSession.status {
        case .completed:
            return outputURL
        case .failed:
            throw exportSession.error ?? NSError(domain: "CompressionError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Compresión fallida"])
        case .cancelled:
            throw NSError(domain: "CompressionError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Compresión cancelada"])
        default:
            throw NSError(domain: "CompressionError", code: -4, userInfo: [NSLocalizedDescriptionKey: "Estado desconocido"])
        }
    }

            // ✅ EXTRACCION DE FRAME DE FONDO
        private func extractBackgroundFrame(from videoURL: URL) async -> String? {
            let asset = AVAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 400, height: 400) // ✅ TAMAÑO OPTIMIZADO
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
                let uiImage = UIImage(cgImage: cgImage)
                
                // ✅ COMPRIMIR IMAGEN PARA REDUCIR TAMAÑO
                guard let imageData = uiImage.jpegData(compressionQuality: 0.7) else { return nil }
                
                // ✅ SUBIR A STORAGE
                let frameFileName = "background_frames/\(UUID().uuidString).jpg"
                let storageRef = Storage.storage().reference().child(frameFileName)
                
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpeg"
                
                _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
                let downloadURL = try await storageRef.downloadURL()
                
                return downloadURL.absoluteString
                
            } catch {
                return nil
            }
        }
        
        // ✅ DETECTAR SI NECESITA COMPRESIÓN (SOLO POR TAMAÑO/BITRATE)
        private func needsCompressionBySize(_ videoURL: URL) async -> Bool {
        let asset = AVAsset(url: videoURL)
        let fileSize = getFileSizeInBytes(videoURL)
        
        // ✅ SOLO COMPRIMIR SI ES MUY PESADO O TIENE BITRATE ALTO
        if fileSize > 100 * 1024 * 1024 { // Más de 100MB
            return true
        }
        
        if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
            let bitrate = try? await videoTrack.load(.estimatedDataRate)
            
            if let rate = bitrate, rate > 15_000_000 { // Más de 15 Mbps
                return true
            }
        }
        
        return false
    }

    // ✅ FUNCIÓN PRINCIPAL SIMPLIFICADA
    private func prepareMediaItem(_ uploadingStory: UploadingStory) async throws -> UploadMediaItem {
        if uploadingStory.mediaItem.type == .video,
           let videoURL = uploadingStory.mediaItem.videoURL {
            
            // ✅ SOLO COMPRIMIR SI REALMENTE ES NECESARIO
            let needsCompression = await needsCompressionBySize(videoURL)
            
            if needsCompression {
                let compressedVideoURL = try await compressVideoForStory(videoURL)
                return UploadMediaItem(type: .video, image: nil, videoURL: compressedVideoURL)
            } else {
                return UploadMediaItem(type: .video, image: nil, videoURL: videoURL)
            }
        } else {
            // Para imágenes
            return UploadMediaItem(type: .image, image: uploadingStory.mediaItem.image, videoURL: nil)
        }
    }

    // ✅ FUNCIONES AUXILIARES
    private func createTemporaryVideoURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = "compressed_\(UUID().uuidString).mp4"
        return documentsPath.appendingPathComponent(fileName)
    }

    private func getFileSizeInBytes(_ url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    private func getFileSize(_ url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes[.size] as? Int64 ?? 0
            let sizeInMB = Double(size) / 1024.0 / 1024.0
            return String(format: "%.2f MB", sizeInMB)
        } catch {
            return "Unknown"
        }
    }
    
    // MARK: - 📁 UPLOAD DE ARCHIVO DE HISTORIA
    private func uploadStoryMedia(_ uploadingStory: UploadingStory, uploadMediaItem: UploadMediaItem) async throws -> String {
        
        let storageService = StorageService()
        
        return try await withCheckedThrowingContinuation { continuation in
            storageService.uploadMedia(userId: uploadingStory.userId, mediaItem: uploadMediaItem) { result in
                // Simular progreso durante upload (20% - 70%)
                Task {
                    for progress in stride(from: 0.2, through: 0.7, by: 0.1) {
                        await self.updateProgress(uploadingStory, progress: progress)
                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 segundos
                    }
                }
                
                continuation.resume(with: result)
            }
        }
    }
    
    // MARK: - 📝 CREAR HISTORIA EN FIRESTORE
    private func createStoryInFirestore(_ uploadingStory: UploadingStory, mediaUrl: String) async throws -> String {
        let firestoreService = FirestoreService()
        
        // ✅ DETECTAR ASPECT RATIO Y EXTRAER FRAME DE FONDO
        var aspectRatio: String? = nil
        var backgroundFrameURL: String? = nil
        
        if uploadingStory.mediaItem.type == .video,
           let videoURL = uploadingStory.mediaItem.videoURL {
            aspectRatio = await GlassmorphicStoryViewer.detectVideoAspectRatio(from: videoURL)
            
            // ✅ EXTRAER FRAME DE FONDO PARA VIDEOS HORIZONTALES
            if let aspectRatio = aspectRatio,
               GlassmorphicStoryViewer.isHorizontalAspectRatio(aspectRatio) {
                backgroundFrameURL = await extractBackgroundFrame(from: videoURL)
            }
        } else if uploadingStory.mediaItem.type == .image {
            // ✅ DETECTAR ASPECT RATIO PARA IMÁGENES
            if let finalRenderedImage = uploadingStory.finalRenderedImage {
                // Usar la imagen renderizada final para obtener el aspect ratio real
                let width = Int(finalRenderedImage.size.width)
                let height = Int(finalRenderedImage.size.height)
                aspectRatio = "\(width):\(height)"
            }
        }
        
        // 🔥 CREAR MediaItem como en tu función original
        let mediaItem = MediaItem(
            type: uploadingStory.mediaItem.type == .video ? .video : .image,
            url: mediaUrl
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            if uploadingStory.audienceSetting == .customList && uploadingStory.customListId != nil {
                // Lista personalizada
                firestoreService.createStoryWithCustomList(
                    userId: uploadingStory.userId,
                    mediaItem: mediaItem,
                    customListId: uploadingStory.customListId!,
                    text: uploadingStory.storyText,
                    textPosition: uploadingStory.textPosition,
                    textStyle: uploadingStory.selectedTextStyle != nil ? String(describing: uploadingStory.selectedTextStyle!) : nil,
                    stickers: uploadingStory.stickerData?.compactMap { StickerData.from($0) },
                    drawingData: uploadingStory.drawingData,
                    aspectRatio: aspectRatio, // ✅ AÑADIDO: Pasar aspect ratio
                    backgroundFrameURL: backgroundFrameURL, // ✅ AÑADIDO: Pasar URL del frame de fondo
                    chainId: uploadingStory.chainId, // 🔗 AÑADIDO: Pasar ID de la cadena
                    chainPosition: uploadingStory.chainPosition, // 🔗 AÑADIDO: Pasar posición en la cadena
                    chainTitle: uploadingStory.chainTitle, // 🔗 AÑADIDO: Pasar título de la cadena
                    allowOthersToContinue: uploadingStory.allowOthersToContinue, // 🔗 AÑADIDO: Configuración de continuación
                    continuationAudience: uploadingStory.continuationAudience, // 🔗 AÑADIDO: Audiencia de continuación
                    continuationCustomViewers: uploadingStory.continuationCustomViewers, // 🔗 AÑADIDO: Usuarios específicos de continuación
                    continuationCustomListId: uploadingStory.continuationCustomListId, // 🔗 AÑADIDO: Lista específica de continuación
                    continuationCustomListName: uploadingStory.continuationCustomListName // 🔗 AÑADIDO: Nombre de lista de continuación
                ) { storyId, error in // 🔥 AHORA CAPTURA EL storyId REAL
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let storyId = storyId {
                        continuation.resume(returning: storyId) // 🔥 DEVOLVER EL ID REAL
                    } else {
                        continuation.resume(throwing: NSError(domain: "FirestoreError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Story ID not returned from createStoryWithCustomList"]))
                    }
                }
            } else {
                // Audiencia predefinida o custom manual
                firestoreService.createStoryWithVisibility(
                    userId: uploadingStory.userId,
                    mediaItem: mediaItem,
                    audienceSetting: uploadingStory.audienceSetting,
                    customViewers: uploadingStory.customViewers,
                    text: uploadingStory.storyText,
                    textPosition: uploadingStory.textPosition,
                    textStyle: uploadingStory.selectedTextStyle != nil ? String(describing: uploadingStory.selectedTextStyle!) : nil,
                    stickers: uploadingStory.stickerData?.compactMap { StickerData.from($0) },
                    drawingData: uploadingStory.drawingData,
                    aspectRatio: aspectRatio, // ✅ AÑADIDO: Pasar aspect ratio
                    backgroundFrameURL: backgroundFrameURL, // ✅ AÑADIDO: Pasar URL del frame de fondo
                    chainId: uploadingStory.chainId, // 🔗 AÑADIDO: Pasar ID de la cadena
                    chainPosition: uploadingStory.chainPosition, // 🔗 AÑADIDO: Pasar posición en la cadena
                    chainTitle: uploadingStory.chainTitle, // 🔗 AÑADIDO: Pasar título de la cadena
                    allowOthersToContinue: uploadingStory.allowOthersToContinue, // 🔗 AÑADIDO: Configuración de continuación
                    continuationAudience: uploadingStory.continuationAudience, // 🔗 AÑADIDO: Audiencia de continuación
                    continuationCustomViewers: uploadingStory.continuationCustomViewers, // 🔗 AÑADIDO: Usuarios específicos de continuación
                    continuationCustomListId: uploadingStory.continuationCustomListId, // 🔗 AÑADIDO: Lista específica de continuación
                    continuationCustomListName: uploadingStory.continuationCustomListName // 🔗 AÑADIDO: Nombre de lista de continuación
                ) { storyId, error in // 🔥 AHORA CAPTURA EL storyId REAL
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let storyId = storyId {
                        continuation.resume(returning: storyId) // 🔥 DEVOLVER EL ID REAL
                    } else {
                        continuation.resume(throwing: NSError(domain: "FirestoreError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Story ID not returned from createStoryWithVisibility"]))
                    }
                }
            }
        }
    }
    
    
    
    // MARK: - 🛡️ MODERACIÓN SILENCIOSA DE HISTORIA
    private func moderateStoryContentSilently(
        storyId: String,
        uploadingStory: UploadingStory,
        mediaUrl: String
    ) async {
        
        await withCheckedContinuation { continuation in
            MediaModerationService.shared.moderateMedia(
                mediaURL: mediaUrl,
                mediaType: uploadingStory.mediaItem.type == .video ? .video : .image,
                userId: uploadingStory.userId,
                contentId: storyId, // Usar storyId correctamente
                contentType: .story  // ✅ CRUCIAL: Especificar que es una historia
            ) { result in
                switch result {
                case .approved:
                    // Story approved - no action needed
                    break
                    
                case .deleted(let reason, let category):
                    // ✅ IGUAL QUE MOMENTOS: MediaModerationService YA ejecutó hideContentUsingOnlyMe()
                    // NO necesitamos llamar a hideStoryUsingOnlyMe() aquí
                    break
                    
                case .warning(let reason, let category):
                    // ✅ IGUAL QUE MOMENTOS: MediaModerationService YA ejecutó hideContentUsingOnlyMe()
                    // La historia queda visible pero marcada para revisión
                    break
                    
                case .error(let errorMessage):
                    // Mantener visible si hay error técnico
                    break
                }
                
                continuation.resume()
            }
        }
        
    }
    
    // MARK: - 📊 CONFIGURAR POLLS
    private func setupPollStickers(storyId: String, stickers: [StickerItem]) async {
        
        // ✅ CORREGIDO: Unwrap uploadingStory de forma segura
        guard let uploadingStory = uploadingStory else {
            return
        }
        
        for sticker in stickers {
            guard let pollData = sticker.interactionData?.pollData else {
                continue
            }
            
            // Crear colección de votos para este poll
            let pollVotesRef = Firestore.firestore()
                .collection("users")
                .document(uploadingStory.userId)
                .collection("stories")
                .document(storyId)
                .collection("pollVotes")
            
            // Crear documento inicial del poll con metadata
            let pollMetadata: [String: Any] = [
                "pollData": pollData,
                "stickerId": sticker.id,
                "createdAt": FieldValue.serverTimestamp(),
                "totalVotes": 0,
                "option0Votes": 0,
                "option1Votes": 0
            ]
            
            do {
                try await pollVotesRef.document("metadata").setData(pollMetadata)
            } catch {
            }
        }
    }
    
    // MARK: - ❓ CONFIGURAR QUESTIONS
    private func setupQuestionStickers(storyId: String, stickers: [StickerItem]) async {
        
        // ✅ CORREGIDO: Unwrap uploadingStory de forma segura
        guard let uploadingStory = uploadingStory else {
            return
        }
        
        for sticker in stickers {
            guard let questionText = sticker.interactionData?.questionText else {
                continue
            }
            
            // Crear colección de respuestas para este question
            let questionResponsesRef = Firestore.firestore()
                .collection("users")
                .document(uploadingStory.userId)
                .collection("stories")
                .document(storyId)
                .collection("questionResponses")
            
            // Crear documento inicial del question con metadata
            let questionMetadata: [String: Any] = [
                "questionText": questionText,
                "stickerId": sticker.id,
                "createdAt": FieldValue.serverTimestamp(),
                "responseCount": 0
            ]
            
            do {
                try await questionResponsesRef.document("metadata").setData(questionMetadata)
            } catch {
            }
        }
    }
    
    // MARK: - 💬 CONFIGURAR QUESTION RESPONSES
    private func setupQuestionResponseStickers(storyId: String, stickers: [StickerItem]) async {
        
        // Los stickers de respuesta de preguntas son estáticos y se muestran en la historia
        // No necesitan configuración especial en Firestore
        for sticker in stickers {
            guard let questionText = sticker.interactionData?.questionText else {
                continue
            }
            
        }
    }
    
    // MARK: - 🌤️ CONFIGURAR WEATHER STICKERS
    private func setupWeatherStickers(storyId: String, stickers: [StickerItem]) async {
        
        // Los stickers de clima son estáticos y se muestran animados en la historia
        // No necesitan configuración especial en Firestore, solo se guardan los datos
        for sticker in stickers {
            guard let weatherSymbol = sticker.interactionData?.weatherSymbol,
                  let temperature = sticker.interactionData?.questionText else {
                continue
            }
            
        }
    }
    
    // MARK: - 🔄 HELPERS
    @MainActor
    private func updateProgress(_ story: UploadingStory, progress: Double, status: UploadStatus? = nil, error: String? = nil) {
        if let currentStory = uploadingStory, currentStory.id == story.id {
            currentStory.uploadProgress = progress
            if let status = status {
                currentStory.status = status
            }
            if let error = error {
                currentStory.errorMessage = error
            }
        }
    }
    
    @MainActor
    private func removeUploadingStory() {
        uploadingStory = nil
        isProcessing = false
    }
    
    // MARK: - 🔄 REINTENTAR UPLOAD FALLIDO
    func retryUpload(_ story: UploadingStory) {
        guard story.status == .failed else { return }
        
        DispatchQueue.main.async {
            story.status = .uploading
            story.uploadProgress = 0.0
            story.errorMessage = nil
            self.isProcessing = true
        }
        
        // ✅ NUEVO: SOLICITUD DE BACKGROUND TASK (RETRY)
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "StoryRetryUpload") {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        
        Task.detached(priority: .userInitiated) {
            await self.processStoryUpload(story)
            
            // ✅ Terminar background task
            DispatchQueue.main.async {
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }
        }
    }
    
    // MARK: - 🗑️ CANCELAR UPLOAD
    func cancelUpload(_ story: UploadingStory) {
        DispatchQueue.main.async {
            if let currentStory = self.uploadingStory, currentStory.id == story.id {
                self.removeUploadingStory()
            }
        }
    }
}
// MARK: - 🔄 EXTENSIÓN PARA INTEGRAR CON TU CREATOR VIEW
extension BackgroundStoryUploadService {
    // Función que llamarías desde tu CreatorView actualizado
    func publishStoryInBackground(
        mediaItem: ProcessedMedia,
        storyText: String,
        textPosition: CGPoint?,
        selectedTextStyle: Any?,
        stickerData: [StickerItem],
        drawingData: Data?,
        audienceSetting: ContentAudience, // 🔥 ContentAudience directamente
        customViewers: [String],
        customListId: String?,
        selectedListName: String?,
        finalRenderedImage: UIImage? = nil,
        chainId: String? = nil, // 🔗 AÑADIDO: ID de la cadena
        chainPosition: Int? = nil, // 🔗 AÑADIDO: Posición en la cadena
        chainTitle: String? = nil, // 🔗 AÑADIDO: Título de la cadena
        allowOthersToContinue: Bool? = nil, // 🔗 AÑADIDO: Si otros pueden continuar la cadena
        continuationAudience: ContentAudience? = nil, // 🔗 AÑADIDO: Audiencia que puede continuar
        continuationCustomViewers: [String]? = nil, // 🔗 AÑADIDO: Usuarios específicos que pueden continuar
        continuationCustomListId: String? = nil, // 🔗 AÑADIDO: Lista específica que puede continuar
        continuationCustomListName: String? = nil // 🔗 AÑADIDO: Nombre de la lista que puede continuar
    ) -> Bool {
        
        let uploadingStory = uploadStory(
            mediaItem: mediaItem,
            storyText: storyText.isEmpty ? nil : storyText,
            textPosition: textPosition,
            selectedTextStyle: selectedTextStyle,
            stickerData: stickerData.isEmpty ? nil : stickerData,
            drawingData: drawingData,
            audienceSetting: audienceSetting, // 🔥 PASAR ContentAudience directamente
            customViewers: customViewers.isEmpty ? nil : customViewers,
            customListId: customListId,
            selectedListName: selectedListName,
            finalRenderedImage: finalRenderedImage,
            chainId: chainId, // 🔗 AÑADIDO: Pasar ID de la cadena
            chainPosition: chainPosition, // 🔗 AÑADIDO: Pasar posición en la cadena
            chainTitle: chainTitle, // 🔗 AÑADIDO: Pasar título de la cadena
            allowOthersToContinue: allowOthersToContinue, // 🔗 AÑADIDO: Pasar si otros pueden continuar
            continuationAudience: continuationAudience, // 🔗 AÑADIDO: Pasar audiencia que puede continuar
            continuationCustomViewers: continuationCustomViewers, // 🔗 AÑADIDO: Pasar usuarios específicos
            continuationCustomListId: continuationCustomListId, // 🔗 AÑADIDO: Pasar lista específica
            continuationCustomListName: continuationCustomListName // 🔗 AÑADIDO: Pasar nombre de lista
        )
        
        return uploadingStory != nil
    }
    
    // ✅ FUNCIÓN: Optimizar imagen para historias
    private func optimizeImageForStory(_ image: UIImage) -> UIImage {
        // ✅ PASO 1: Normalizar orientación
        let normalizedImage = image.normalized()
        
        // ✅ PASO 2: Comprimir a JPEG
        guard let compressedData = normalizedImage.jpegData(compressionQuality: 0.9) else {
            return normalizedImage
        }
        
        // ✅ PASO 3: Redimensionar si es muy grande (>8MB)
        if compressedData.count > 8 * 1024 * 1024 { // 8MB
            let maxDimension: CGFloat = 3072
            let resizedImage = calculateOptimalSize(for: normalizedImage, maxDimension: maxDimension)
            return resizedImage
        }
        
        return normalizedImage
    }
    
    // ✅ FUNCIÓN: Calcular tamaño óptimo para redimensionar
    private func calculateOptimalSize(for image: UIImage, maxDimension: CGFloat) -> UIImage {
        let originalSize = image.size
        let widthRatio = maxDimension / originalSize.width
        let heightRatio = maxDimension / originalSize.height
        let scale = min(widthRatio, heightRatio)
        
        let newWidth = originalSize.width * scale
        let newHeight = originalSize.height * scale
        let newSize = CGSize(width: newWidth, height: newHeight)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        // ✅ Normalizar orientación después del redimensionamiento
        return resizedImage.normalized()
    }
    
    // MARK: - 📱 LIVE ACTIVITIES PARA DYNAMIC ISLAND
    
    @available(iOS 16.1, *)
    private func startLiveActivity(for uploadingStory: UploadingStory) async {
        let attributes = StoryUploadActivityAttributes(
            storyId: uploadingStory.tempId,
            mediaType: uploadingStory.mediaItem.type == .video ? "video" : "image"
        )
        
        let initialContentState = StoryUploadActivityAttributes.ContentState(
            progress: 0.0,
            status: "uploading"
        )
        
        do {
            let activity = try Activity<StoryUploadActivityAttributes>.request(
                attributes: attributes,
                contentState: initialContentState,
                pushType: nil
            )
            await MainActor.run {
                liveActivity = activity
            }
        } catch {
        }
    }
    
    @available(iOS 16.1, *)
    private func updateLiveActivity(progress: Double, status: String) {
        guard let activity = liveActivity else {
            return
        }
        
        let updatedState = StoryUploadActivityAttributes.ContentState(
            progress: progress,
            status: status
        )
        
        Task {
            do {
                await activity.update(using: updatedState)
            } catch {
            }
        }
    }
    
    @available(iOS 16.1, *)
    private func updateLiveActivityAsync(progress: Double, status: String) async {
        guard let activity = liveActivity else {
            return
        }
        
        let updatedState = StoryUploadActivityAttributes.ContentState(
            progress: progress,
            status: status
        )
        
        do {
            await activity.update(using: updatedState)
        } catch {
        }
    }
    
    @available(iOS 16.1, *)
    private func endLiveActivity() {
        guard let activity = liveActivity else { return }
        
        let finalState = StoryUploadActivityAttributes.ContentState(
            progress: 1.0,
            status: "completed"
        )
        
        Task {
            await activity.end(using: finalState, dismissalPolicy: .immediate)
            liveActivity = nil
        }
    }
    
    @available(iOS 16.1, *)
    private func endLiveActivityAsync() async {
        guard let activity = liveActivity else { return }
        
        // No necesitamos actualizar el estado aquí porque ya lo hicimos antes
        // Solo cerramos la Live Activity después de que se haya mostrado el emoji
        await activity.end(dismissalPolicy: .immediate)
        await MainActor.run {
            liveActivity = nil
        }
    }
    
    // ✅ NUEVO: Función helper para actualizar progreso (si no existe)
    private func updateProgress(_ uploadingStory: UploadingStory, progress: Double, status: UploadStatus? = nil, error: String? = nil) async {
        await MainActor.run {
            uploadingStory.uploadProgress = progress
            if let status = status {
                uploadingStory.status = status
            }
            if let error = error {
                uploadingStory.errorMessage = error
            }
        }
        
        // ✅ NUEVO: Actualizar Live Activity
        if #available(iOS 16.1, *) {
            let statusString: String
            if let status = status {
                switch status {
                case .uploading:
                    statusString = "uploading"
                case .processing:
                    statusString = "processing"
                case .completed:
                    statusString = "completed"
                case .failed:
                    statusString = "failed"
                case .moderated:
                    statusString = "processing" // Tratar moderated como processing para la Live Activity
                }
            } else {
                statusString = progress < 0.7 ? "uploading" : "processing"
            }
            updateLiveActivity(progress: progress, status: statusString)
        }
    }
}
