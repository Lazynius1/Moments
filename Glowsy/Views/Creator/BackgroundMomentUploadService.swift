// BackgroundMomentUploadService.swift
import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import ActivityKit
import AVFoundation
import UIKit

// MARK: - 📱 MODELO DE MOMENTO EN PROGRESO
@MainActor
class UploadingMoment: ObservableObject, Identifiable {
    let id = UUID()
    let tempId: String
    let userId: String
    let content: String
    let mediaItems: [ProcessedMedia]
    let taggedUsers: [String]?
    let location: String?
    let locationCoordinate: Moment.LocationCoordinate?  // ✅ NUEVO: Coordenadas de ubicación
    let audienceSetting: CaptionAndDetailsView.AudienceSetting
    let customViewers: [String]?
    let customListId: String?
    let aspectRatio: String
    let createdAt: Date
    let disableComments: Bool
    let hideLikeCounts: Bool
    let allowSharing: Bool
    let scheduledDate: Date?
    
    @Published var uploadProgress: Double = 0.0
    @Published var status: UploadStatus = .uploading
    @Published var errorMessage: String?
    @Published var momentId: String? // 🔥 Nuevo: Para almacenar el ID real de Firestore
    
    // 🔥 PARA MOSTRAR EN EL FEED
    @Published var thumbnailImage: UIImage?
    @Published var mediaCount: Int = 1
    
    init(
        userId: String,
        content: String,
        mediaItems: [ProcessedMedia],
        taggedUsers: [String]?,
        location: String?,
        locationCoordinate: Moment.LocationCoordinate? = nil,  // ✅ NUEVO: Coordenadas de ubicación
        audienceSetting: CaptionAndDetailsView.AudienceSetting,
        customViewers: [String]?,
        customListId: String?,
        aspectRatio: String,
        disableComments: Bool = false,
        hideLikeCounts: Bool = false,
        allowSharing: Bool = true,
        scheduledDate: Date? = nil
    ) {
        self.tempId = "temp_\(UUID().uuidString)"
        self.userId = userId
        self.content = content
        self.mediaItems = mediaItems
        self.taggedUsers = taggedUsers
        self.location = location
        self.locationCoordinate = locationCoordinate  // ✅ NUEVO: Asignar coordenadas
        self.audienceSetting = audienceSetting
        self.customViewers = customViewers
        self.customListId = customListId
        self.aspectRatio = aspectRatio
        self.createdAt = Date()
        
        // Configurar thumbnail y conteo
        self.thumbnailImage = mediaItems.first?.image
        self.mediaCount = mediaItems.count
        self.disableComments = disableComments
        self.hideLikeCounts = hideLikeCounts
        self.allowSharing = allowSharing
        self.scheduledDate = scheduledDate
    }
}

enum UploadStatus {
    case uploading
    case processing
    case completed
    case failed
    case moderated // 🚨 Nuevo: Oculto por moderación
    
    var displayText: String {
        switch self {
        case .uploading: return "Subiendo..."
        case .processing: return "Procesando..."
        case .completed: return "Publicado"
        case .failed: return "Error al subir"
        case .moderated: return "Publicado" // 🤫 Usuario no sabe que fue moderado
        }
    }
    
    var shouldShowInFeed: Bool {
        switch self {
        case .uploading, .processing: return true
        case .completed, .moderated: return false // Se reemplaza por el momento real
        case .failed: return true // Para permitir reintentos
        }
    }
}

// MARK: - 📦 PERSISTENCE PAYLOADS
struct MomentUploadPayload: Codable {
    let content: String
    let mediaPaths: [CachedMediaItem]
    let taggedUsers: [String]?
    let location: String?
    let locationCoordinate: Moment.LocationCoordinate?
    let audienceSetting: String
    let customViewers: [String]?
    let customListId: String?
    let aspectRatio: String
    let disableComments: Bool
    let hideLikeCounts: Bool
    let allowSharing: Bool
    let scheduledDate: Date?
}

struct CachedMediaItem: Codable {
    let type: String
    let localFileName: String
    let thumbnailFileName: String?
    let aspectRatio: String?
    let videoDuration: Double?
    let videoFileSize: Int64?
    let videoResolution: String?
    let tagsData: Data?
}

// MARK: - 🔥 SERVICIO PRINCIPAL
@MainActor
class BackgroundMomentUploadService: ObservableObject {
    static let shared = BackgroundMomentUploadService()
    
    @Published var uploadingMoments: [UploadingMoment] = []
    @Published var isProcessing = false
    weak var feedViewModel: FeedViewModel?
    
    // ✅ NUEVO: Live Activity para Dynamic Island
    @available(iOS 16.1, *)
    private var liveActivity: Activity<MomentUploadActivityAttributes>?
    
    private init() {}
    
    // MARK: - 📤 FUNCIÓN PRINCIPAL: Iniciar upload en background
    func uploadMoment(
        content: String,
        mediaItems: [ProcessedMedia],
        taggedUsers: [String]?,
        location: String?,
        locationCoordinate: Moment.LocationCoordinate? = nil,  // ✅ NUEVO: Coordenadas de ubicación
        audienceSetting: CaptionAndDetailsView.AudienceSetting,
        customViewers: [String]?,
        customListId: String?,
        aspectRatio: String,
        disableComments: Bool = false,
        hideLikeCounts: Bool = false,
        allowSharing: Bool = true,
        scheduledDate: Date? = nil
    ) -> UploadingMoment? {
        
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        
        feedViewModel?.pauseListenersForUpload()
        
        // Crear momento temporal
        let uploadingMoment = UploadingMoment(
            userId: userId,
            content: content,
            mediaItems: mediaItems,
            taggedUsers: taggedUsers,
            location: location,
            locationCoordinate: locationCoordinate,  // ✅ NUEVO: Pasar coordenadas
            audienceSetting: audienceSetting,
            customViewers: customViewers,
            customListId: customListId,
            aspectRatio: aspectRatio,
            disableComments: disableComments,
            hideLikeCounts: hideLikeCounts,
            allowSharing: allowSharing,
            scheduledDate: scheduledDate
        )
        
        // Agregar al feed inmediatamente
        self.uploadingMoments.append(uploadingMoment)
        self.isProcessing = true
        
        // ✅ NUEVO: Iniciar Live Activity
        if #available(iOS 16.1, *) {
            Task { @MainActor in
                await startLiveActivity(for: uploadingMoment)
            }
        }
        
        // ✅ NUEVO: Solicitar tiempo de ejecución en background
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "MomentUpload") {
            // End the task if time expires
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        
        // Procesar en background
        Task {
            // 1. Persistir acción en disco por si la app muere
            await self.persistAction(uploadingMoment)
            
            // 2. Ejecutar upload
            await self.processUpload(uploadingMoment)
            
            // 3. Limpiar acción y archivos al terminar (éxito o error fatal)
            if uploadingMoment.status == .completed || uploadingMoment.status == .moderated {
                await LocalPersistenceService.shared.deleteAction(id: uploadingMoment.tempId)
                self.deleteActionFiles(id: uploadingMoment.tempId)
            }
            
            // ✅ Terminar la tarea de background cuando finalice
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
        
        return uploadingMoment
    }
    
    // MARK: - 🔄 PROCESAMIENTO COMPLETO
    private func processUpload(_ uploadingMoment: UploadingMoment) async {
        
        do {
            // PASO 1: Upload archivos (0% - 70%)
            let mediaUrls = try await uploadMediaFiles(uploadingMoment)
            
            // PASO 2: Crear momento en Firestore (70% - 90%)
            await updateProgress(uploadingMoment, progress: 0.8, status: .processing)
            let momentId = try await createMomentInFirestore(uploadingMoment, mediaUrls: mediaUrls)
            uploadingMoment.momentId = momentId
            
            // ✅ NUEVO: Enviar notificaciones a usuarios etiquetados
            if let taggedUsers = uploadingMoment.taggedUsers, !taggedUsers.isEmpty {
                for taggedUserId in taggedUsers {
                    // Evitar notificarse a sí mismo
                    if taggedUserId != uploadingMoment.userId {
                        Task { @MainActor in
                            NotificationService.shared.sendInteractionNotification(
                                type: .photoTag,
                                to: taggedUserId,
                                momentId: momentId
                            )
                        }
                    }
                }
            }
            
            // PASO 3: Completado (90% - 100%)
            await updateProgress(uploadingMoment, progress: 1.0, status: .completed)
            
            // ✅ NUEVO: Actualizar Live Activity a estado "completed" y esperar unos segundos antes de cerrar
            if #available(iOS 16.1, *) {
                // Actualizar primero el estado a "completed" y esperar a que se complete
                await updateLiveActivityAsync(progress: 1.0, status: "completed")
                // Esperar 3 segundos para mostrar el emoji antes de cerrar
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 segundos
                await endLiveActivityAsync()
            }
            
            // ✅ NUEVO: Reanudar listeners con delay para evitar conflictos
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 segundo
            self.feedViewModel?.resumeListenersAfterUpload()
            
            // PASO 4: Moderar en background silencioso
            Task.detached(priority: .background) {
                await self.moderateContentSilently(
                    momentId: momentId,
                    uploadingMoment: uploadingMoment,
                    mediaUrls: mediaUrls
                )
            }
            
            // PASO 5: Remover del feed después de 2 segundos (reducido)
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 segundos
            self.removeUploadingMoment(uploadingMoment)
            
            // 🔥 TRIGGER ECHO DETECTION
            EchoService.shared.checkForEchoOverlap(
                momentId: momentId,
                userId: uploadingMoment.userId
            )
            
        } catch {
            await updateProgress(uploadingMoment, progress: 0.0, status: .failed, error: error.localizedDescription)
            
            // ✅ NUEVO: Reanudar listeners incluso si falló
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 segundos
            self.feedViewModel?.resumeListenersAfterUpload()
        }
        
        self.isProcessing = self.uploadingMoments.contains { $0.status == .uploading || $0.status == .processing }
    }
    
    // ✅ FUNCIÓN NUEVA: Configurar referencia al FeedViewModel
    func setFeedViewModel(_ feedViewModel: FeedViewModel) {
        self.feedViewModel = feedViewModel
    }
    
    // MARK: - 📁 UPLOAD DE ARCHIVOS
    private func uploadMediaFiles(_ uploadingMoment: UploadingMoment) async throws -> [MediaItem] {
        
        var uploadedItems: [MediaItem] = []
        let storageService = StorageService() // Asume que StorageService está definido
        let totalFiles = uploadingMoment.mediaItems.count
        
        for (index, media) in uploadingMoment.mediaItems.enumerated() {
            // Actualizar progreso
            let baseProgress = Double(index) / Double(totalFiles) * 0.7
            await updateProgress(uploadingMoment, progress: baseProgress)
            
            var finalMediaItem: UploadMediaItem
            
            if media.type == .video, let videoURL = media.videoURL {
                // ✅ COMPRESIÓN DE VIDEO: Comprimir antes de subir
                do {
                     // Notificar estado de compresión
                    await updateProgress(uploadingMoment, progress: baseProgress, status: .processing)
                    
                    let compressedURL = try await compressVideo(inputURL: videoURL)
                    finalMediaItem = UploadMediaItem(type: .video, image: nil, videoURL: compressedURL)
                } catch {
                    // Si falla la compresión, usar original
                    finalMediaItem = UploadMediaItem(type: .video, image: nil, videoURL: videoURL)
                }
            } else {
                finalMediaItem = UploadMediaItem(
                    type: media.type == .image ? .image : .video,
                    image: media.type == .image ? media.image : nil,
                    videoURL: media.type == .video ? media.videoURL : nil
                )
            }
            
            // ✅ SUBIR THUMBNAIL SI ES VIDEO
            var thumbnailUrlString: String? = nil
            if media.type == .video {
                let thumbnailImg = media.image
                let thumbnailMedia = UploadMediaItem(type: .image, image: thumbnailImg, videoURL: nil)
                thumbnailUrlString = try await withCheckedThrowingContinuation { continuation in
                    storageService.uploadMedia(userId: uploadingMoment.userId, mediaItem: thumbnailMedia) { result in
                        continuation.resume(with: result)
                    }
                }
            }
            
            // 🔥 USAR uploadMedia NORMAL para el archivo principal
            let urlString = try await withCheckedThrowingContinuation { continuation in
                storageService.uploadMedia(userId: uploadingMoment.userId, mediaItem: finalMediaItem) { result in
                    continuation.resume(with: result)
                }
            }
            
            let mediaItemType: MediaItem.MediaType = media.type == .image ? .image : .video
            uploadedItems.append(MediaItem(
                type: mediaItemType,
                url: urlString,
                aspectRatio: media.aspectRatio.displayName,
                thumbnailUrl: thumbnailUrlString, // ✅ Usar el URL del thumbnail recién subido
                videoDuration: media.videoDuration,
                videoFileSize: media.videoFileSize,
                videoResolution: media.videoResolution,
                tags: media.tags // ✅ Etiquetas espaciales
            ))
            
            // Progreso por archivo completado
            let fileProgress = Double(index + 1) / Double(totalFiles) * 0.7
            await updateProgress(uploadingMoment, progress: fileProgress)
        }
        
        return uploadedItems
    }
    
    // MARK: - 🎥 COMPRESIÓN DE VIDEO
    private func compressVideo(inputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        
        // 1. Crear URL de destino
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("compressed_\(UUID().uuidString).mp4")
        
        // 2. Configurar Export Session (Preset Medium Quality = 720p/1080p H.264 balanceado)
        // AVAssetExportPreset1280x720 o AVAssetExportPresetMediumQuality son buenas opciones para redes sociales
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
    
    // MARK: - 📝 CREAR MOMENTO EN FIRESTORE
    // 🔥 MODIFICADO: Ahora devuelve el momentId real de Firestore
    private func createMomentInFirestore(_ uploadingMoment: UploadingMoment, mediaUrls: [MediaItem]) async throws -> String {
        let firestoreService = FirestoreService() // Asume que FirestoreService está definido
        
        return try await withCheckedThrowingContinuation { continuation in
            if uploadingMoment.audienceSetting == .custom && uploadingMoment.customListId != nil {
                // Lista personalizada
                firestoreService.createMomentWithCustomList(
                    userId: uploadingMoment.userId,
                    content: uploadingMoment.content,
                    mediaItems: mediaUrls,
                    customListId: uploadingMoment.customListId!,
                    taggedUsers: uploadingMoment.taggedUsers,
                    location: uploadingMoment.location,
                    locationCoordinate: uploadingMoment.locationCoordinate,  // ✅ NUEVO: Pasar coordenadas
                    aspectRatio: uploadingMoment.aspectRatio,
                    disableComments: uploadingMoment.disableComments,      // ✅ NUEVO: Configuración avanzada
                    hideLikeCounts: uploadingMoment.hideLikeCounts,        // ✅ NUEVO: Configuración avanzada
                    allowSharing: uploadingMoment.allowSharing,            // ✅ NUEVO: Configuración avanzada
                    scheduledDate: uploadingMoment.scheduledDate
                ) { momentId, error in // 🔥 Captura el momentId
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let momentId = momentId { // Asegúrate de que momentId no sea nulo
                        continuation.resume(returning: momentId)
                    } else {
                        continuation.resume(throwing: NSError(domain: "FirestoreError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Moment ID not returned from createMomentWithCustomList"]))
                    }
                }
            } else {
                // Audiencia predefinida
                // La conversión a string ya la tienes en convertAudienceSettingToString
                
                firestoreService.createMomentWithVisibility(
                    userId: uploadingMoment.userId,
                    content: uploadingMoment.content,
                    mediaItems: mediaUrls,
                    taggedUsers: uploadingMoment.taggedUsers,
                    location: uploadingMoment.location,
                    audienceSetting: uploadingMoment.audienceSetting,      // ✅ MOVIDO: Antes de locationCoordinate
                    locationCoordinate: uploadingMoment.locationCoordinate,
                    customViewers: uploadingMoment.customViewers,
                    aspectRatio: uploadingMoment.aspectRatio,
                    disableComments: uploadingMoment.disableComments,      // ✅ NUEVO: Configuración avanzada
                    hideLikeCounts: uploadingMoment.hideLikeCounts,        // ✅ NUEVO: Configuración avanzada
                    allowSharing: uploadingMoment.allowSharing,            // ✅ NUEVO: Configuración avanzada
                    scheduledDate: uploadingMoment.scheduledDate
                ) { momentId, error in // 🔥 Captura el momentId
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let momentId = momentId { // Asegúrate de que momentId no sea nulo
                        continuation.resume(returning: momentId)
                    } else {
                        continuation.resume(throwing: NSError(domain: "FirestoreError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Moment ID not returned from createMomentWithVisibility"]))
                    }
                }
            }
        }
    }
    
    // MARK: - 🛡️ MODERACIÓN SILENCIOSA
    // MARK: - 🛡️ MODERACIÓN SILENCIOSA
    private func moderateContentSilently(
        momentId: String,
        uploadingMoment: UploadingMoment,
        mediaUrls: [MediaItem]
    ) async {
        
        for mediaUrl in mediaUrls {
            await withCheckedContinuation { continuation in
                MediaModerationService.shared.moderateMedia(
                    mediaURL: mediaUrl.url,
                    mediaType: mediaUrl.type == .image ? .image : .video,
                    userId: uploadingMoment.userId,
                    contentId: momentId, // Usar momentId correctamente
                    contentType: .moment, // Especificar que es un momento
                    mediaItemId: mediaUrl.id
                ) { result in
                    switch result {
                    case .approved:
                        // Content approved - no action needed
                        break
                        
                    case .deleted(let reason, let category):
                        if let index = self.uploadingMoments.firstIndex(where: { $0.id == uploadingMoment.id }) {
                            self.uploadingMoments[index].status = .moderated
                        }
                        
                    case .warning(let reason, let category):
                        // Content has warning - no action needed
                        break
                        
                    case .error(let errorMessage):
                        // Technical error - no action needed
                        break
                    }
                    
                    continuation.resume()
                }
            }
        }
        
    }
    
    // MARK: - 🔄 HELPERS
    private func updateProgress(_ moment: UploadingMoment, progress: Double, status: UploadStatus? = nil, error: String? = nil) async {
        if let index = uploadingMoments.firstIndex(where: { $0.id == moment.id }) {
            uploadingMoments[index].uploadProgress = progress
            if let status = status {
                uploadingMoments[index].status = status
            }
            if let error = error {
                uploadingMoments[index].errorMessage = error
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
    
    @MainActor
    private func removeUploadingMoment(_ moment: UploadingMoment) {
        uploadingMoments.removeAll { $0.id == moment.id }
        isProcessing = uploadingMoments.contains { $0.status == .uploading || $0.status == .processing }
    }
    
    // MARK: - 🔄 REINTENTAR UPLOAD FALLIDO
    func retryUpload(_ moment: UploadingMoment) {
        guard moment.status == .failed else { return }
        
        moment.status = .uploading
        moment.uploadProgress = 0.0
        moment.errorMessage = nil
        self.isProcessing = true
        
        Task.detached(priority: .userInitiated) {
            await self.processUpload(moment)
        }
    }
    
    // MARK: - 🗑️ CANCELAR UPLOAD
    func cancelUpload(_ moment: UploadingMoment) {
        self.removeUploadingMoment(moment)
    }
    
    // MARK: - 🔄 HELPER: Convertir AudienceSetting a String
    private func convertAudienceSettingToString(_ setting: CaptionAndDetailsView.AudienceSetting) -> String {
        switch setting {
        case .everyone: return "everyone"
        case .mutuals: return "mutuals"
        case .admirers: return "admirers"
        case .bestFriends: return "bestFriends"
        case .custom: return "custom"
        case .onlyMe: return "onlyMe"
        }
    }
    
    // MARK: - ✅ LIVE ACTIVITY FUNCTIONS
    @available(iOS 16.1, *)
    private func startLiveActivity(for uploadingMoment: UploadingMoment) async {
        // Determinar tipo de media
        let hasVideo = uploadingMoment.mediaItems.contains { $0.type == .video }
        let hasImage = uploadingMoment.mediaItems.contains { $0.type == .image }
        let mediaType: String
        if hasVideo && hasImage {
            mediaType = "mixed"
        } else if hasVideo {
            mediaType = "video"
        } else {
            mediaType = "image"
        }
        
        let attributes = MomentUploadActivityAttributes(
            momentId: uploadingMoment.tempId,
            mediaType: mediaType,
            mediaCount: uploadingMoment.mediaItems.count
        )
        
        let initialContentState = MomentUploadActivityAttributes.ContentState(
            progress: 0.0,
            status: "uploading"
        )
        
        do {
            let activity = try Activity<MomentUploadActivityAttributes>.request(
                attributes: attributes,
                contentState: initialContentState,
                pushType: nil
            )
            await MainActor.run {
                liveActivity = activity
            }
        } catch {
            // Error al iniciar Live Activity - puede ser que el tipo no esté disponible en el widget extension
        }
    }
    
    @available(iOS 16.1, *)
    private func updateLiveActivity(progress: Double, status: String) {
        guard let activity = liveActivity else {
            return
        }
        
        let updatedState = MomentUploadActivityAttributes.ContentState(
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
        
        let updatedState = MomentUploadActivityAttributes.ContentState(
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
        guard let activity = liveActivity else {
            return
        }
        
        Task {
            do {
                await activity.end(using: nil, dismissalPolicy: .after(Date().addingTimeInterval(3)))
            } catch {
            }
        }
        
        liveActivity = nil
    }
    
    @available(iOS 16.1, *)
    private func endLiveActivityAsync() async {
        guard let activity = liveActivity else {
            return
        }
        
        do {
            await activity.end(using: nil, dismissalPolicy: .after(Date().addingTimeInterval(3)))
        } catch {
        }
        
        await MainActor.run {
            liveActivity = nil
        }
    }

    // MARK: - 💾 PERSISTENCE & RECOVERY
    
    private var pendingUploadsDir: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("pending_uploads")
    }
    
    /// Prepara una acción persistente antes de iniciar el upload
    func persistAction(_ uploadingMoment: UploadingMoment) {
        Task {
            do {
                // 1. Asegurar que existe el directorio
                if !FileManager.default.fileExists(atPath: self.pendingUploadsDir.path) {
                    try FileManager.default.createDirectory(at: self.pendingUploadsDir, withIntermediateDirectories: true)
                }
                
                // 2. Guardar archivos de media en disco
                var cachedMediaItems: [CachedMediaItem] = []
                for media in uploadingMoment.mediaItems {
                    let cachedItem = try await self.saveMediaToDisk(media)
                    cachedMediaItems.append(cachedItem)
                }
                
                // 3. Crear payload
                let payload = MomentUploadPayload(
                    content: uploadingMoment.content,
                    mediaPaths: cachedMediaItems,
                    taggedUsers: uploadingMoment.taggedUsers,
                    location: uploadingMoment.location,
                    locationCoordinate: uploadingMoment.locationCoordinate,
                    audienceSetting: self.convertAudienceSettingToString(uploadingMoment.audienceSetting),
                    customViewers: uploadingMoment.customViewers,
                    customListId: uploadingMoment.customListId,
                    aspectRatio: uploadingMoment.aspectRatio,
                    disableComments: uploadingMoment.disableComments,
                    hideLikeCounts: uploadingMoment.hideLikeCounts,
                    allowSharing: uploadingMoment.allowSharing,
                    scheduledDate: uploadingMoment.scheduledDate
                )
                
                let encodedPayload = try JSONEncoder().encode(payload)
                
                // 4. Guardar en SwiftData
                let action = CachedAction(
                    id: uploadingMoment.tempId,
                    type: CachedAction.ActionType.momentUpload.rawValue,
                    payloadData: encodedPayload
                )
                
                await LocalPersistenceService.shared.saveAction(action)

            } catch { }
        }
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
        
        let tagsData = try? JSONEncoder().encode(media.tags)
        
        return CachedMediaItem(
            type: media.type == .image ? "image" : "video",
            localFileName: fileName,
            thumbnailFileName: thumbName,
            aspectRatio: media.aspectRatio.displayName,
            videoDuration: media.videoDuration,
            videoFileSize: media.videoFileSize,
            videoResolution: media.videoResolution,
            tagsData: tagsData
        )
    }
    
    /// Intenta retomar una subida desde una acción persistente
    func resumeUpload(from action: CachedAction) async {
        guard action.type == CachedAction.ActionType.momentUpload.rawValue else { return }
        
        do {
            let payload = try JSONDecoder().decode(MomentUploadPayload.self, from: action.payloadData)
            
            // 1. Obtener el tipo de audiencia correcto (Decoding first for safer comparison)
            let audience: CaptionAndDetailsView.AudienceSetting = {
                switch payload.audienceSetting {
                case "everyone": return .everyone
                case "mutuals": return .mutuals
                case "admirers": return .admirers
                case "bestFriends": return .bestFriends
                case "custom": return .custom
                case "customList": return .custom
                case "onlyMe": return .onlyMe
                default: return .everyone
                }
            }()
            
            // 2. ✅ DUPLICATE CHECK: Evitar re-subir si ya está en proceso
            let isAlreadyUploading = uploadingMoments.contains { moment in
                // Coincidir por contenido Y audiencia Y (opcionalmente) ubicación
                return moment.content == payload.content && moment.audienceSetting == audience
            }
            
            if isAlreadyUploading {
                LocalPersistenceService.shared.deleteAction(id: action.id)
                return
            }
            
            // 3. Reconstruir ProcessedMedia
            var mediaItems: [ProcessedMedia] = []
            for item in payload.mediaPaths {
                let fileURL = pendingUploadsDir.appendingPathComponent(item.localFileName)
                guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
                
                let thumbURL: URL? = item.thumbnailFileName != nil ? pendingUploadsDir.appendingPathComponent(item.thumbnailFileName!) : nil
                let tags: [PhotoTag]? = item.tagsData != nil ? try? JSONDecoder().decode([PhotoTag].self, from: item.tagsData!) : nil
                
                // Determinar aspect ratio del item
                let itemAspectRatio: CreatorMedia.AspectRatio = {
                    if let cachedAspectRatio = item.aspectRatio {
                        return CreatorMedia.AspectRatio(from: cachedAspectRatio)
                    }
                    if item.type == "image", let uiImage = UIImage(contentsOfFile: fileURL.path) {
                        return CreatorMedia.AspectRatio.fromRatio(uiImage.size.width / uiImage.size.height)
                    }
                    return .square
                }()
                
                var processed = ProcessedMedia(
                    type: item.type == "image" ? .image : .video,
                    image: (item.type == "image" ? UIImage(contentsOfFile: fileURL.path) : nil) ?? UIImage(),
                    videoURL: item.type == "video" ? fileURL : nil,
                    aspectRatio: itemAspectRatio
                )
                
                processed.thumbnailURL = thumbURL
                processed.videoDuration = item.videoDuration
                processed.videoFileSize = item.videoFileSize
                processed.videoResolution = item.videoResolution
                processed.tags = tags
                
                mediaItems.append(processed)
            }
            
            if !mediaItems.isEmpty {
                // Iniciar el upload
                _ = self.uploadMoment(
                    content: payload.content,
                    mediaItems: mediaItems,
                    taggedUsers: payload.taggedUsers,
                    location: payload.location,
                    locationCoordinate: payload.locationCoordinate,
                    audienceSetting: audience,
                    customViewers: payload.customViewers,
                    customListId: payload.customListId,
                    aspectRatio: payload.aspectRatio,
                    disableComments: payload.disableComments,
                    hideLikeCounts: payload.hideLikeCounts,
                    allowSharing: payload.allowSharing,
                    scheduledDate: payload.scheduledDate
                )
                
                // Importante: Eliminar la acción anterior para que no se duplique
                LocalPersistenceService.shared.deleteAction(id: action.id)
            }
            
        } catch { }
    }
    
    private func deleteActionFiles(id: String) {
        do {
            if FileManager.default.fileExists(atPath: pendingUploadsDir.path) {
                let files = try FileManager.default.contentsOfDirectory(at: pendingUploadsDir, includingPropertiesForKeys: nil)
                for file in files {
                    if file.lastPathComponent.contains(id) {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            }
        } catch { }
    }
}
