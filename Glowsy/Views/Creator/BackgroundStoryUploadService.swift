// BackgroundStoryUploadService.swift
import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import AVFoundation
import FirebaseStorage

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
        selectedListName: String?
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
        finalRenderedImage: UIImage? = nil // Para historias con overlays renderizados
    ) -> UploadingStory? {
        
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        
        
        // Si ya hay una historia subiendo, cancelar la anterior
        if let existingStory = uploadingStory {
            cancelUpload(existingStory)
        }
        
        // 🔥 PREPARAR MEDIA ITEM (con imagen renderizada si existe)
        let finalMediaItem: ProcessedMedia
        if let finalImage = finalRenderedImage {
            // Crear nuevo ProcessedMedia con la imagen renderizada
            finalMediaItem = ProcessedMedia(
                id: mediaItem.id,
                image: finalImage,
                videoURL: mediaItem.videoURL, // 🔥 videoURL va antes que type
                type: mediaItem.type,
                aspectRatio: mediaItem.aspectRatio
            )
        } else {
            // Usar el mediaItem original
            finalMediaItem = mediaItem
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
            selectedListName: selectedListName
        )
        
        // Mostrar en el header inmediatamente
        DispatchQueue.main.async {
            self.uploadingStory = uploadingStory
            self.isProcessing = true
        }
        
        // Procesar en background
        Task.detached(priority: .userInitiated) {
            await self.processStoryUpload(uploadingStory)
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
        }
        
        await MainActor.run {
            self.isProcessing = false
        }
    }
    
    // MARK: - 📁 PREPARAR MEDIA ITEM
    // ✅ COMPRESIÓN SIMPLE - PRESERVAR DIMENSIONES ORIGINALES
    private func compressVideoForStory(_ videoURL: URL) async throws -> URL {
        
        let asset = AVAsset(url: videoURL)
        
        // ✅ CONFIGURACIÓN SIMPLE Y EFECTIVA
        let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        )
        
        guard let exportSession = exportSession else {
            throw NSError(domain: "VideoCompression", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se pudo crear export session"])
        }
        
        let compressedURL = createTemporaryVideoURL()
        exportSession.outputURL = compressedURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // 🎯 CONFIGURAR BITRATE Y FPS SIN CAMBIAR DIMENSIONES
        if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            
            // ✅ CREAR COMPOSITION CON DIMENSIONES CORRECTAS
            let videoComposition = AVMutableVideoComposition()
            
            // ✅ CALCULAR DIMENSIONES REALES DESPUÉS DE TRANSFORM
            let transformedSize = naturalSize.applying(preferredTransform)
            let finalSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
            videoComposition.renderSize = finalSize // 🎯 USAR DIMENSIONES CORRECTAS
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30fps estándar
            
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
            
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layerInstruction.setTransform(preferredTransform, at: .zero) // 🎯 MANTENER TRANSFORM ORIGINAL
            
            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]
            
            exportSession.videoComposition = videoComposition
            

        }
        
        // ✅ LÍMITE DE TAMAÑO RAZONABLE
        exportSession.fileLengthLimit = 50 * 1024 * 1024 // 50MB
        
        
        // ✅ EJECUTAR COMPRESIÓN
        await exportSession.export()
        
        switch exportSession.status {
        case .completed:
            let originalSize = getFileSize(videoURL)
            let compressedSize = getFileSize(compressedURL)
            return compressedURL
            
        case .failed:
            throw exportSession.error ?? NSError(domain: "VideoCompression", code: 2, userInfo: [NSLocalizedDescriptionKey: "Error en compresión"])
        case .cancelled:
            throw NSError(domain: "VideoCompression", code: 3, userInfo: [NSLocalizedDescriptionKey: "Compresión cancelada"])
        default:
            throw NSError(domain: "VideoCompression", code: 4, userInfo: [NSLocalizedDescriptionKey: "Estado desconocido"])
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
                    backgroundFrameURL: backgroundFrameURL // ✅ AÑADIDO: Pasar URL del frame de fondo
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
                    backgroundFrameURL: backgroundFrameURL // ✅ AÑADIDO: Pasar URL del frame de fondo
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
        
        Task.detached(priority: .userInitiated) {
            await self.processStoryUpload(story)
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
        finalRenderedImage: UIImage? = nil
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
            finalRenderedImage: finalRenderedImage
        )
        
        return uploadingStory != nil
    }
}
