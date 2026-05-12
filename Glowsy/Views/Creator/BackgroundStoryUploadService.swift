// BackgroundStoryUploadService.swift
import Foundation
import CoreLocation
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

// MARK: - 📦 PERSISTENCE PAYLOADS
struct StoryUploadPayload: Codable {
    let userId: String
    let mediaItem: CachedMediaItem
    let storyText: String?
    let textPosition: CGPoint?
    let selectedTextStyle: String?
    let stickers: [CachedSticker]?
    let drawingFileName: String?
    let audienceSetting: String
    let customViewers: [String]?
    let customListId: String?
    let selectedListName: String?
    let createdAt: Date
    
    // Story Chain fields
    let chainId: String?
    let chainPosition: Int?
    let chainTitle: String?
    let allowOthersToContinue: Bool?
    let continuationAudience: String?
    let continuationCustomViewers: [String]?
    let continuationCustomListId: String?
    let continuationCustomListName: String?
}

struct CachedSticker: Codable {
    let id: String
    let localImageName: String?
    let position: CGPoint
    let scale: CGFloat
    let rotationRadians: Double
    let gifURL: URL?
    let videoURL: URL? // ✅ NUEVO: Persistencia de Video URL
    let isAnimated: Bool
    let type: String
    let interactionData: CachedStickerInteractionData?
}

struct CachedStickerInteractionData: Codable {
    let username: String?
    let userId: String?
    let hashtag: String?
    let location: String?
    let latitude: Double?
    let longitude: Double?
    let pollData: [String]?
    let questionText: String?
    let weatherSymbol: String?
    let linkURL: String?
    let linkTitle: String?
    let countdownTitle: String?
    let countdownTargetAtMs: Double?
    let sliderEmoji: String?
    let sliderPrompt: String?
    let caption: String?
    let profileImagePath: String?
    let momentId: String?
    let mediaCount: Int?
    
    // Quiz & Reveal
    let quizQuestion: String?
    let quizOptions: [String]?
    let quizCorrectIndex: Int?
    let revealType: String?
    let frameStyle: String?
}

// MARK: - 🔥 SERVICIO PRINCIPAL DE STORIES
@MainActor
class BackgroundStoryUploadService: ObservableObject {
    static let shared = BackgroundStoryUploadService()
    
    @Published var uploadingStory: UploadingStory? // Solo una historia a la vez
    @Published var isProcessing = false
    
    private let pendingUploadsDir: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("pending_story_uploads")
    }()
    
    // ✅ NUEVO: Live Activity para Dynamic Island
    @available(iOS 16.1, *)
    private var liveActivity: Activity<StoryUploadActivityAttributes>?
    
    private init() {
        // ✅ Limpiar actividades huerfanas de sesiones anteriores
        if #available(iOS 16.1, *) {
            Task {
                await cleanupStaleLiveActivities()
            }
        }
    }
    
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
        Task {
            // 1. Persistir acción en disco por si la app muere
            await self.persistAction(uploadingStory)
            
            // 2. Ejecutar upload
            await self.processStoryUpload(uploadingStory)
            
            // 3. Limpiar acción y archivos al terminar (éxito o error fatal)
            if uploadingStory.status == .completed || uploadingStory.status == .moderated {
                await LocalPersistenceService.shared.deleteAction(id: uploadingStory.tempId)
                self.deleteActionFiles(id: uploadingStory.tempId)
            }
            
            // ✅ Terminar background task
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
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

                let emojiSliderStickers = stickerData.filter { $0.type == .emojiSlider }
                if !emojiSliderStickers.isEmpty {
                    await setupEmojiSliderStickers(storyId: storyId, stickers: emojiSliderStickers)
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

                // ✅ NUEVO: Procesar quiz stickers
                let quizStickers = stickerData.filter { $0.type == .quiz }
                if !quizStickers.isEmpty {
                    await setupQuizStickers(storyId: storyId, stickers: quizStickers)
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
            return try await uploadBackgroundFrameImage(uiImage)
        } catch {
            return nil
        }
    }

    private func uploadBackgroundFrameImage(_ image: UIImage) async throws -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { return nil }

        let frameFileName = "background_frames/\(UUID().uuidString).jpg"
        let storageRef = Storage.storage().reference().child(frameFileName)

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        return downloadURL.absoluteString
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
        let firestoreService = FirestoreService.shared
        
        // ✅ DETECTAR ASPECT RATIO Y EXTRAER FRAME DE FONDO
        var aspectRatio: String? = nil
        var backgroundFrameURL: String? = nil
        
        if uploadingStory.mediaItem.type == .video,
           let videoURL = uploadingStory.mediaItem.videoURL {
            aspectRatio = await GlassmorphicStoryViewer.detectVideoAspectRatio(from: videoURL)
            
            // Extraer frame cuando el media no debe ir a fill y necesita blur de relleno.
            if let aspectRatio = aspectRatio,
               StoryMediaLayoutRules.presentationMode(
                   for: parseAspectRatio(aspectRatio) ?? 0.0,
                   canvasAspectRatio: UIScreen.main.bounds.width / max(UIScreen.main.bounds.height, 1)
               ) == .fitWithBlur {
                if let finalRenderedImage = uploadingStory.finalRenderedImage {
                    backgroundFrameURL = try await uploadBackgroundFrameImage(finalRenderedImage)
                } else {
                    backgroundFrameURL = await extractBackgroundFrame(from: videoURL)
                }
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
        
        // ✅ NORMALIZAR STICKERS EN EL ÁREA REAL DEL CONTENIDO (tipo Instagram)
        // Guardamos posición relativa (u,v) dentro del contentRect y escala relativa al ancho del contentRect.
        // Así se mantiene estable entre móviles con tamaños/ratios distintos.
        let contentRect = storyContentRectInEditor(for: uploadingStory, aspectRatio: aspectRatio)
        let referenceContentWidth: CGFloat = 375.0

        let normalizedStickerData: [StickerData]? = uploadingStory.stickerData?.compactMap { stickerItem in
            var normalizedItem = stickerItem
            
            let safeWidth = max(contentRect.width, 1)
            let safeHeight = max(contentRect.height, 1)
            
            let normalizedX = (stickerItem.position.x - contentRect.minX) / safeWidth
            let normalizedY = (stickerItem.position.y - contentRect.minY) / safeHeight
            let normalizedScale = stickerItem.scale * (referenceContentWidth / safeWidth)
            
            normalizedItem.position = CGPoint(
                x: normalizedX.isFinite ? normalizedX : 0.5,
                y: normalizedY.isFinite ? normalizedY : 0.5
            )
            normalizedItem.scale = normalizedScale.isFinite ? normalizedScale : stickerItem.scale
            return StickerData.from(normalizedItem)
        }
        
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
                    stickers: normalizedStickerData, // ✅ USAR DATOS NORMALIZADOS
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
                        FirestoreService.shared.rebuildStorySummary(for: uploadingStory.userId) { rebuildError in
                            _ = rebuildError
                        }
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
                    stickers: normalizedStickerData, // ✅ USAR DATOS NORMALIZADOS
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
                        FirestoreService.shared.rebuildStorySummary(for: uploadingStory.userId) { rebuildError in
                            _ = rebuildError
                        }
                        continuation.resume(returning: storyId) // 🔥 DEVOLVER EL ID REAL
                    } else {
                        continuation.resume(throwing: NSError(domain: "FirestoreError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Story ID not returned from createStoryWithVisibility"]))
                    }
                }
            }
        }
    }
    
    // MARK: - 🎯 STICKER LAYOUT HELPERS
    private func storyContentRectInEditor(for uploadingStory: UploadingStory, aspectRatio: String?) -> CGRect {
        let containerSize = UIScreen.main.bounds.size
        let resolvedAspectRatio = parseAspectRatio(aspectRatio) ?? {
            let imageSize = (uploadingStory.finalRenderedImage ?? uploadingStory.mediaItem.image).size
            guard imageSize.width > 0, imageSize.height > 0 else {
                return containerSize.width / max(containerSize.height, 1)
            }
            return imageSize.width / imageSize.height
        }()
        
        let contentMode = StoryMediaLayoutRules.presentationMode(
            for: resolvedAspectRatio,
            canvasAspectRatio: containerSize.width / max(containerSize.height, 1)
        ).swiftUIContentMode
        return contentRect(
            containerSize: containerSize,
            mediaAspectRatio: resolvedAspectRatio,
            contentMode: contentMode
        )
    }
    
    private func parseAspectRatio(_ aspectRatio: String?) -> CGFloat? {
        guard let aspectRatio else { return nil }
        let components = aspectRatio.split(separator: ":")
        guard components.count == 2,
              let widthValue = Double(components[0]),
              let heightValue = Double(components[1]) else {
            return nil
        }
        
        let width = CGFloat(widthValue)
        let height = CGFloat(heightValue)
        guard
              width > 0,
              height > 0 else {
            return nil
        }
        return width / height
    }
    
    private func contentRect(
        containerSize: CGSize,
        mediaAspectRatio: CGFloat,
        contentMode: SwiftUI.ContentMode
    ) -> CGRect {
        let containerWidth = max(containerSize.width, 1)
        let containerHeight = max(containerSize.height, 1)
        let containerAspectRatio = containerWidth / containerHeight
        
        let isFit = contentMode == .fit
        let mediaIsWider = mediaAspectRatio > containerAspectRatio
        
        let width: CGFloat
        let height: CGFloat
        
        if isFit {
            if mediaIsWider {
                width = containerWidth
                height = containerWidth / max(mediaAspectRatio, 0.0001)
            } else {
                height = containerHeight
                width = containerHeight * mediaAspectRatio
            }
        } else {
            if mediaIsWider {
                height = containerHeight
                width = containerHeight * mediaAspectRatio
            } else {
                width = containerWidth
                height = containerWidth / max(mediaAspectRatio, 0.0001)
            }
        }
        
        return CGRect(
            x: (containerWidth - width) / 2,
            y: (containerHeight - height) / 2,
            width: width,
            height: height
        )
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

        await moderateStoryImageStickersSilently(
            storyId: storyId,
            uploadingStory: uploadingStory
        )
    }

    private func moderateStoryImageStickersSilently(
        storyId: String,
        uploadingStory: UploadingStory
    ) async {
        guard let stickers = uploadingStory.stickerData, !stickers.isEmpty else {
            return
        }

        let moderatableStickers = stickers.filter { sticker in
            sticker.type == .frame || sticker.type == .selfie
        }

        guard !moderatableStickers.isEmpty else {
            return
        }

        var moderatedStickers: [String: MediaModerationAction] = [:]

        for sticker in moderatableStickers {
            let preserveAlpha = sticker.type == .selfie
            let result = await withCheckedContinuation { continuation in
                MediaModerationService.shared.moderateStickerImage(
                    sticker.image,
                    preserveAlpha: preserveAlpha,
                    userId: uploadingStory.userId,
                    storyId: storyId,
                    stickerId: sticker.id
                ) { action in
                    continuation.resume(returning: action)
                }
            }

            switch result {
            case .deleted, .warning:
                moderatedStickers[sticker.id] = result
            case .approved, .error:
                break
            }
        }

        guard !moderatedStickers.isEmpty else {
            return
        }

        await withCheckedContinuation { continuation in
            MediaModerationService.shared.hideStoryStickerItems(
                userId: uploadingStory.userId,
                storyId: storyId,
                moderatedStickers: moderatedStickers
            ) { _ in
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

    private func setupEmojiSliderStickers(storyId: String, stickers: [StickerItem]) async {
        guard let uploadingStory = uploadingStory else {
            return
        }

        for sticker in stickers {
            guard let prompt = sticker.interactionData?.sliderPrompt,
                  let emoji = sticker.interactionData?.sliderEmoji else {
                continue
            }

            let emojiSliderRef = Firestore.firestore()
                .collection("users")
                .document(uploadingStory.userId)
                .collection("stories")
                .document(storyId)
                .collection("emojiSliders")
                .document(sticker.id)

            let metadata: [String: Any] = [
                "stickerId": sticker.id,
                "prompt": prompt,
                "emoji": emoji,
                "createdAt": FieldValue.serverTimestamp()
            ]

            do {
                try await emojiSliderRef.setData(metadata)
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
    // MARK: - 📝 CONFIGURAR QUIZ
    private func setupQuizStickers(storyId: String, stickers: [StickerItem]) async {
        
        guard let uploadingStory = uploadingStory else { return }
        
        for sticker in stickers {
            guard let quizQuestion = sticker.interactionData?.quizQuestion,
                  let quizOptions = sticker.interactionData?.quizOptions else {
                continue
            }
            
            // Colección de respuestas para este quiz
            let quizResponsesRef = Firestore.firestore()
                .collection("users")
                .document(uploadingStory.userId)
                .collection("stories")
                .document(storyId)
                .collection("quizResponses")
            
            // Metadata inicial del quiz
            let quizMetadata: [String: Any] = [
                "question": quizQuestion,
                "options": quizOptions,
                "correctIndex": sticker.interactionData?.quizCorrectIndex ?? 0,
                "stickerId": sticker.id,
                "createdAt": FieldValue.serverTimestamp(),
                "totalResponses": 0
            ]
            
            do {
                try await quizResponsesRef.document("metadata").setData(quizMetadata)
            } catch { }
        }
    }
    
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
        // ✅ Asegurar que la Live Activity se cierre si se cancela o elimina
        if #available(iOS 16.1, *) {
            endLiveActivity()
        }
        
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
        if let currentStory = self.uploadingStory, currentStory.id == story.id {
            self.removeUploadingStory()
        }
    }
    
    // MARK: - 💾 PERSISTENCIA: Cola de Outbox
    
    /// Prepara una acción persistente antes de iniciar el upload
    func persistAction(_ uploadingStory: UploadingStory) async {
        do {
            // 1. Asegurar que existe el directorio
            if !FileManager.default.fileExists(atPath: self.pendingUploadsDir.path) {
                try FileManager.default.createDirectory(at: self.pendingUploadsDir, withIntermediateDirectories: true)
            }
            
            // 2. Guardar archivo principal en disco
            let cachedMedia = try await self.saveMediaToDisk(uploadingStory.mediaItem)
            
            // 3. Guardar stickers en disco
            var cachedStickers: [CachedSticker] = []
            if let stickers = uploadingStory.stickerData {
                for sticker in stickers {
                    let cached = try await self.saveStickerToDisk(sticker)
                    cachedStickers.append(cached)
                }
            }
            
            // 4. Guardar dibujo si existe
            var drawingFileName: String? = nil
            if let drawingData = uploadingStory.drawingData {
                drawingFileName = "\(uploadingStory.tempId)_drawing.png"
                let drawingURL = pendingUploadsDir.appendingPathComponent(drawingFileName!)
                try drawingData.write(to: drawingURL)
            }
            
            // 5. Crear payload
            let payload = StoryUploadPayload(
                userId: uploadingStory.userId,
                mediaItem: cachedMedia,
                storyText: uploadingStory.storyText,
                textPosition: uploadingStory.textPosition,
                selectedTextStyle: uploadingStory.selectedTextStyle != nil ? String(describing: uploadingStory.selectedTextStyle!) : nil,
                stickers: cachedStickers.isEmpty ? nil : cachedStickers,
                drawingFileName: drawingFileName,
                audienceSetting: uploadingStory.audienceSetting.rawValue,
                customViewers: uploadingStory.customViewers,
                customListId: uploadingStory.customListId,
                selectedListName: uploadingStory.selectedListName,
                createdAt: uploadingStory.createdAt,
                chainId: uploadingStory.chainId,
                chainPosition: uploadingStory.chainPosition,
                chainTitle: uploadingStory.chainTitle,
                allowOthersToContinue: uploadingStory.allowOthersToContinue,
                continuationAudience: uploadingStory.continuationAudience?.rawValue,
                continuationCustomViewers: uploadingStory.continuationCustomViewers,
                continuationCustomListId: uploadingStory.continuationCustomListId,
                continuationCustomListName: uploadingStory.continuationCustomListName
            )
            
            let encodedPayload = try JSONEncoder().encode(payload)
            
            // 6. Guardar en SwiftData
            let action = CachedAction(
                id: uploadingStory.tempId,
                type: CachedAction.ActionType.storyUpload.rawValue,
                payloadData: encodedPayload
            )
            
            await LocalPersistenceService.shared.saveAction(action)
            
        } catch { }
    }
    
    private func saveMediaToDisk(_ media: ProcessedMedia) async throws -> CachedMediaItem {
        let id = UUID().uuidString
        let fileName = "\(id)_\(media.type == .image ? "img.jpg" : "vid.mp4")"
        let fileURL = pendingUploadsDir.appendingPathComponent(fileName)
        
        if media.type == .image {
            let image = media.image
            if let data = image.jpegData(compressionQuality: 0.8) {
                try data.write(to: fileURL)
            }
        } else if media.type == .video, let videoURL = media.videoURL {
            try FileManager.default.copyItem(at: videoURL, to: fileURL)
        }
        
        // Guardar thumbnail si existe
        var thumbName: String? = nil
        if let thumbURL = media.thumbnailURL {
            thumbName = "\(id)_thumb.jpg"
            let thumbDest = pendingUploadsDir.appendingPathComponent(thumbName!)
            try? FileManager.default.copyItem(at: thumbURL, to: thumbDest)
        }
        
        return CachedMediaItem(
            type: media.type == .image ? "image" : "video",
            localFileName: fileName,
            thumbnailFileName: thumbName,
            aspectRatio: media.aspectRatio.displayName,
            videoDuration: media.videoDuration,
            videoFileSize: media.videoFileSize,
            videoResolution: media.videoResolution,
            tagsData: nil // Historias no usan PhotoTags tradicionales
        )
    }
    
    private func saveStickerToDisk(_ sticker: StickerItem) async throws -> CachedSticker {
        let id = sticker.id
        var localImageName: String? = nil
        
        // Solo guardamos la imagen si no es un sticker animado (GIF)
        if !sticker.isAnimated {
            let fileName = "sticker_\(UUID().uuidString).png"
            let fileURL = pendingUploadsDir.appendingPathComponent(fileName)
            if let data = sticker.image.pngData() {
                try data.write(to: fileURL)
                localImageName = fileName
            }
        }
        
        let interaction = sticker.interactionData.map { data in
            CachedStickerInteractionData(
                username: data.username,
                userId: data.userId,
                hashtag: data.hashtag,
                location: data.location,
                latitude: data.locationCoordinate?.latitude,
                longitude: data.locationCoordinate?.longitude,
                pollData: data.pollData,
                questionText: data.questionText,
                weatherSymbol: data.weatherSymbol,
                linkURL: data.linkURL,
                linkTitle: data.linkTitle,
                countdownTitle: data.countdownTitle,
                countdownTargetAtMs: data.countdownTargetAtMs,
                sliderEmoji: data.sliderEmoji,
                sliderPrompt: data.sliderPrompt,
                caption: data.caption,
                profileImagePath: data.profileImagePath,
                momentId: data.momentId,
                mediaCount: data.mediaCount,
                quizQuestion: data.quizQuestion,
                quizOptions: data.quizOptions,
                quizCorrectIndex: data.quizCorrectIndex,
                revealType: data.revealType,
                frameStyle: data.frameStyle
            )
        }
        
        return CachedSticker(
            id: sticker.id,
            localImageName: localImageName,
            position: sticker.position,
            scale: sticker.scale,
            rotationRadians: sticker.rotation.radians,
            gifURL: sticker.gifURL,
            videoURL: sticker.videoURL, // ✅ Guardar Video URL
            isAnimated: sticker.isAnimated,
            type: sticker.type.rawValue,
            interactionData: interaction
        )
    }
    
    /// Borra los archivos temporales asociados a una acción
    func deleteActionFiles(id: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: pendingUploadsDir, includingPropertiesForKeys: nil) else { return }
        
        for file in files {
            // Borramos archivos que contengan el ID de la historia (tempId o id de acción)
            if file.lastPathComponent.contains(id) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    /// Reanuda una subida desde una acción persistida
    func resumeUpload(from action: CachedAction) async {
        guard action.type == CachedAction.ActionType.storyUpload.rawValue else { return }
        
        do {
            let payload = try JSONDecoder().decode(StoryUploadPayload.self, from: action.payloadData)
            
            // ✅ DUPLICATE CHECK: Evitar re-subir si ya está en proceso
            if let currentStory = uploadingStory, currentStory.tempId == action.id {
                 return
            }

            // ✅ AUDIENCE CHECK: Asegurar compatibilidad con onlyMe y customList
            // El rawValue directo suele funcionar, pero si queremos ser explícitos como en MomentUpload:
            let audience: ContentAudience = {
                if let aud = ContentAudience(rawValue: payload.audienceSetting) {
                    return aud
                }
                // Fallback manual por si acaso
                switch payload.audienceSetting {
                case "everyone": return .everyone
                case "connections": return .connections
                case "bestFriends": return .bestFriends
                case "custom": return .custom
                case "customList": return .customList
                case "onlyMe": return .onlyMe
                default: return .everyone
                }
            }()
            
            // 1. Reconstruir MediaItem
            let mediaFileURL = pendingUploadsDir.appendingPathComponent(payload.mediaItem.localFileName)
            guard FileManager.default.fileExists(atPath: mediaFileURL.path) else { return }
            
            let thumbURL: URL? = payload.mediaItem.thumbnailFileName != nil ? pendingUploadsDir.appendingPathComponent(payload.mediaItem.thumbnailFileName!) : nil
            
            // Determinar aspect ratio
            let itemAspectRatio: CreatorMedia.AspectRatio = {
                if let cachedAspectRatio = payload.mediaItem.aspectRatio {
                    return CreatorMedia.AspectRatio(from: cachedAspectRatio)
                }
                if payload.mediaItem.type == "image", let uiImage = UIImage(contentsOfFile: mediaFileURL.path) {
                    return CreatorMedia.AspectRatio.fromRatio(uiImage.size.width / uiImage.size.height)
                }
                return .square
            }()
            
            var processedMedia = ProcessedMedia(
                type: payload.mediaItem.type == "image" ? .image : .video,
                image: (payload.mediaItem.type == "image" ? UIImage(contentsOfFile: mediaFileURL.path) : nil) ?? UIImage(),
                videoURL: payload.mediaItem.type == "video" ? mediaFileURL : nil,
                aspectRatio: itemAspectRatio
            )
            processedMedia.thumbnailURL = thumbURL
            processedMedia.videoDuration = payload.mediaItem.videoDuration
            processedMedia.videoFileSize = payload.mediaItem.videoFileSize
            processedMedia.videoResolution = payload.mediaItem.videoResolution
            
            // 2. Reconstruir Stickers
            var stickers: [StickerItem] = []
            if let cachedStickers = payload.stickers {
                for cached in cachedStickers {
                    var image = UIImage()
                    if let localName = cached.localImageName {
                        let path = pendingUploadsDir.appendingPathComponent(localName).path
                        image = UIImage(contentsOfFile: path) ?? UIImage()
                    }
                    
                    let type = StickerItem.StickerType(rawValue: cached.type) ?? .generic
                    let interaction = cached.interactionData.map { data in
                        StickerItem.StickerInteractionData(
                            username: data.username,
                            userId: data.userId,
                            hashtag: data.hashtag,
                            location: data.location,
                            locationCoordinate: (data.latitude != nil && data.longitude != nil) ? CLLocationCoordinate2D(latitude: data.latitude!, longitude: data.longitude!) : nil,
                            pollData: data.pollData,
                            questionText: data.questionText,
                            weatherSymbol: data.weatherSymbol,
                            linkURL: data.linkURL,
                            linkTitle: data.linkTitle,
                            countdownTitle: data.countdownTitle,
                            countdownTargetAtMs: data.countdownTargetAtMs,
                            sliderEmoji: data.sliderEmoji,
                            sliderPrompt: data.sliderPrompt,
                            caption: data.caption,
                            profileImagePath: data.profileImagePath,
                            momentId: data.momentId,
                            mediaCount: data.mediaCount,
                            quizQuestion: data.quizQuestion,
                            quizOptions: data.quizOptions,
                            quizCorrectIndex: data.quizCorrectIndex,
                            revealType: data.revealType,
                            frameStyle: data.frameStyle
                        )
                    }
                    
                    var sticker: StickerItem
                    if cached.isAnimated {
                        if let videoURL = cached.videoURL {
                            // ✅ RECONSTRUIR VIDEO STICKER
                            sticker = StickerItem(
                                id: cached.id,
                                image: image,
                                position: cached.position,
                                scale: cached.scale,
                                rotation: .radians(cached.rotationRadians),
                                gifURL: nil,
                                videoURL: videoURL,
                                isAnimated: true,
                                type: type,
                                interactionData: interaction
                            )
                        } else if let gifURL = cached.gifURL {
                            // ✅ RECONSTRUIR GIF ANIMADO
                            sticker = StickerItem(
                                id: cached.id,
                                image: image,
                                position: cached.position,
                                scale: cached.scale,
                                rotation: .radians(cached.rotationRadians),
                                gifURL: gifURL,
                                videoURL: nil,
                                isAnimated: true,
                                type: type,
                                interactionData: interaction
                            )
                        } else {
                            // Fallback (raro si es animado)
                            sticker = StickerItem(
                                id: cached.id,
                                image: image,
                                position: cached.position,
                                scale: cached.scale,
                                rotation: .radians(cached.rotationRadians),
                                gifURL: nil,
                                videoURL: nil,
                                isAnimated: false,
                                type: type,
                                interactionData: interaction
                            )
                        }
                    } else {
                         sticker = StickerItem(
                            id: cached.id,
                            image: image,
                            position: cached.position,
                            scale: cached.scale,
                            rotation: .radians(cached.rotationRadians),
                            gifURL: nil,
                            videoURL: nil,
                            isAnimated: false,
                            type: type,
                            interactionData: interaction
                        )
                    }
                    stickers.append(sticker)
                }
            }
            
            // 3. Reconstruir Dibujo
            var drawingData: Data? = nil
            if let drawingName = payload.drawingFileName {
                let path = pendingUploadsDir.appendingPathComponent(drawingName).path
                drawingData = try? Data(contentsOf: URL(fileURLWithPath: path))
            }
            
            // 4. Iniciar upload
            // let audience = ContentAudience(rawValue: payload.audienceSetting) ?? .everyone // Eliminado, usamos la variable de arriba
            let continuationAudience = payload.continuationAudience != nil ? ContentAudience(rawValue: payload.continuationAudience!) : nil
            
            _ = uploadStory(
                mediaItem: processedMedia,
                storyText: payload.storyText,
                textPosition: payload.textPosition,
                selectedTextStyle: payload.selectedTextStyle,
                stickerData: stickers.isEmpty ? nil : stickers,
                drawingData: drawingData,
                audienceSetting: audience,
                customViewers: payload.customViewers,
                customListId: payload.customListId,
                selectedListName: payload.selectedListName,
                finalRenderedImage: nil,
                chainId: payload.chainId,
                chainPosition: payload.chainPosition,
                chainTitle: payload.chainTitle,
                allowOthersToContinue: payload.allowOthersToContinue,
                continuationAudience: continuationAudience,
                continuationCustomViewers: payload.continuationCustomViewers,
                continuationCustomListId: payload.continuationCustomListId,
                continuationCustomListName: payload.continuationCustomListName
            )
            
            LocalPersistenceService.shared.deleteAction(id: action.id)

        } catch { }
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
        // Normalizamos orientación siempre
        let normalizedImage = image.normalized()
        
        // Capped dimension for memory - Stories are typically 1080x1920
        // Using 1440 for high quality but much less memory than camera resolution
        let maxDimension: CGFloat = 1440
        
        if normalizedImage.size.width > maxDimension || normalizedImage.size.height > maxDimension {
            return calculateOptimalSize(for: normalizedImage, maxDimension: maxDimension)
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
    
    // ✅ NUEVO: Limpiar actividades huerfanas al inicio
    @available(iOS 16.1, *)
    private func cleanupStaleLiveActivities() async {
        // Obtener todas las actividades de este tipo
        for activity in Activity<StoryUploadActivityAttributes>.activities {
            // Si hay una actividad en curso (liveActivity), no la borramos (aunque en init no debería haber)
            // Pero si la app se reinició, activity != liveActivity (que es nil o nueva)
            // Así que borramos TODAS las actividades antiguas almacenadas por el sistema
            
            // Solo borramos si NO es la actual (por si acaso se llama en otro momento)
            if let current = liveActivity, current.id == activity.id {
                continue
            }
            
            await activity.end(dismissalPolicy: .immediate)
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
