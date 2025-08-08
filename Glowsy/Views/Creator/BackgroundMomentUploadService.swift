// BackgroundMomentUploadService.swift
import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

// MARK: - 📱 MODELO DE MOMENTO EN PROGRESO
class UploadingMoment: ObservableObject, Identifiable {
    let id = UUID()
    let tempId: String
    let userId: String
    let content: String
    let mediaItems: [ProcessedMedia]
    let taggedUsers: [String]?
    let location: String?
    let audienceSetting: CaptionAndDetailsView.AudienceSetting
    let customViewers: [String]?
    let customListId: String?
    let aspectRatio: String
    let createdAt: Date
    let disableComments: Bool
    let hideLikeCounts: Bool
    let allowSharing: Bool
    
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
        audienceSetting: CaptionAndDetailsView.AudienceSetting,
        customViewers: [String]?,
        customListId: String?,
        aspectRatio: String,
        disableComments: Bool = false,
        hideLikeCounts: Bool = false,
        allowSharing: Bool = true
    ) {
        self.tempId = "temp_\(UUID().uuidString)"
        self.userId = userId
        self.content = content
        self.mediaItems = mediaItems
        self.taggedUsers = taggedUsers
        self.location = location
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

// MARK: - 🔥 SERVICIO PRINCIPAL
class BackgroundMomentUploadService: ObservableObject {
    static let shared = BackgroundMomentUploadService()
    
    @Published var uploadingMoments: [UploadingMoment] = []
    @Published var isProcessing = false
    weak var feedViewModel: FeedViewModel?
    
    private init() {}
    
    // MARK: - 📤 FUNCIÓN PRINCIPAL: Iniciar upload en background
    func uploadMoment(
        content: String,
        mediaItems: [ProcessedMedia],
        taggedUsers: [String]?,
        location: String?,
        audienceSetting: CaptionAndDetailsView.AudienceSetting,
        customViewers: [String]?,
        customListId: String?,
        aspectRatio: String,
        disableComments: Bool = false,
        hideLikeCounts: Bool = false,
        allowSharing: Bool = true
    ) -> UploadingMoment? {
        
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        
        print("📤 === INICIANDO UPLOAD CON PAUSA DE LISTENERS ===")
        feedViewModel?.pauseListenersForUpload()
        
        // Crear momento temporal
        let uploadingMoment = UploadingMoment(
            userId: userId,
            content: content,
            mediaItems: mediaItems,
            taggedUsers: taggedUsers,
            location: location,
            audienceSetting: audienceSetting,
            customViewers: customViewers,
            customListId: customListId,
            aspectRatio: aspectRatio,
            disableComments: disableComments,
            hideLikeCounts: hideLikeCounts,
            allowSharing: allowSharing
        )
        
        // Agregar al feed inmediatamente
        DispatchQueue.main.async {
            self.uploadingMoments.append(uploadingMoment)
            self.isProcessing = true
        }
        
        // Procesar en background
        Task.detached(priority: .userInitiated) {
            await self.processUpload(uploadingMoment)
        }
        
        print("✅ Momento agregado al feed con progreso")
        return uploadingMoment
    }
    
    // MARK: - 🔄 PROCESAMIENTO COMPLETO
    private func processUpload(_ uploadingMoment: UploadingMoment) async {
        print("🔄 Procesando upload: \(uploadingMoment.tempId)")
        
        do {
            // PASO 1: Upload archivos (0% - 70%)
            let mediaUrls = try await uploadMediaFiles(uploadingMoment)
            
            // PASO 2: Crear momento en Firestore (70% - 90%)
            await updateProgress(uploadingMoment, progress: 0.8, status: .processing)
            let momentId = try await createMomentInFirestore(uploadingMoment, mediaUrls: mediaUrls)
            await MainActor.run {
                uploadingMoment.momentId = momentId
            }
            
            // PASO 3: Completado (90% - 100%)
            await updateProgress(uploadingMoment, progress: 1.0, status: .completed)
            
            print("✅ Upload completado: \(momentId)")
            
            // ✅ NUEVO: Reanudar listeners con delay para evitar conflictos
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.feedViewModel?.resumeListenersAfterUpload()
                print("▶️ Listeners reanudados después de upload exitoso")
            }
            
            // PASO 4: Moderar en background silencioso
            Task.detached(priority: .background) {
                await self.moderateContentSilently(
                    momentId: momentId,
                    uploadingMoment: uploadingMoment,
                    mediaUrls: mediaUrls
                )
            }
            
            // PASO 5: Remover del feed después de 2 segundos (reducido)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.removeUploadingMoment(uploadingMoment)
            }
            
        } catch {
            print("❌ Error en upload: \(error)")
            await updateProgress(uploadingMoment, progress: 0.0, status: .failed, error: error.localizedDescription)
            
            // ✅ NUEVO: Reanudar listeners incluso si falló
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.feedViewModel?.resumeListenersAfterUpload()
                print("▶️ Listeners reanudados después de error")
            }
        }
        
        await MainActor.run {
            self.isProcessing = self.uploadingMoments.contains { $0.status == .uploading || $0.status == .processing }
        }
    }
    
    // ✅ FUNCIÓN NUEVA: Configurar referencia al FeedViewModel
    func setFeedViewModel(_ feedViewModel: FeedViewModel) {
        self.feedViewModel = feedViewModel
        print("🔗 FeedViewModel configurado en UploadService")
    }
    
    // MARK: - 📁 UPLOAD DE ARCHIVOS
    private func uploadMediaFiles(_ uploadingMoment: UploadingMoment) async throws -> [MediaItem] {
        print("📁 Subiendo \(uploadingMoment.mediaItems.count) archivos...")
        
        var uploadedItems: [MediaItem] = []
        let storageService = StorageService() // Asume que StorageService está definido
        let totalFiles = uploadingMoment.mediaItems.count
        
        for (index, media) in uploadingMoment.mediaItems.enumerated() {
            // Actualizar progreso (0% a 70% distribuido entre archivos)
            let baseProgress = Double(index) / Double(totalFiles) * 0.7
            await updateProgress(uploadingMoment, progress: baseProgress)
            
            let uploadMediaItem = UploadMediaItem(
                type: media.type == .image ? .image : .video,
                image: media.type == .image ? media.image : nil,
                videoURL: media.type == .video ? media.videoURL : nil
            )
            
            // 🔥 USAR uploadMedia NORMAL (que ya devuelve éxito y modera en background)
            let urlString = try await withCheckedThrowingContinuation { continuation in
                storageService.uploadMedia(userId: uploadingMoment.userId, mediaItem: uploadMediaItem) { result in
                    continuation.resume(with: result)
                }
            }
            
            let mediaItemType: MediaItem.MediaType = media.type == .image ? .image : .video
            uploadedItems.append(MediaItem(type: mediaItemType, url: urlString))
            
            // Progreso por archivo completado
            let fileProgress = Double(index + 1) / Double(totalFiles) * 0.7
            await updateProgress(uploadingMoment, progress: fileProgress)
        }
        
        print("✅ Archivos subidos: \(uploadedItems.count)")
        return uploadedItems
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
                    aspectRatio: uploadingMoment.aspectRatio
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
                    audienceSetting: uploadingMoment.audienceSetting,
                    customViewers: uploadingMoment.customViewers,
                    aspectRatio: uploadingMoment.aspectRatio
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
        print("🛡️ === MODERACIÓN SILENCIOSA INICIADA ===")
        print("📱 Momento real ID: \(momentId)")
        
        for mediaUrl in mediaUrls {
            await withCheckedContinuation { continuation in
                MediaModerationService.shared.moderateMedia(
                    mediaURL: mediaUrl.url,
                    mediaType: mediaUrl.type == .image ? .image : .video,
                    userId: uploadingMoment.userId,
                    contentId: momentId, // Usar momentId correctamente
                    contentType: .moment // Especificar que es un momento
                ) { result in
                    switch result {
                    case .approved:
                        print("✅ Media aprobado: \(mediaUrl.url)")
                        
                    case .deleted(let reason, let category):
                        print("🚨 Contenido moderado - ocultando: \(reason)")
                        DispatchQueue.main.async {
                            if let index = self.uploadingMoments.firstIndex(where: { $0.id == uploadingMoment.id }) {
                                self.uploadingMoments[index].status = .moderated
                            }
                        }
                        
                    case .warning(let reason, let category):
                        print("⚠️ Media con advertencia: \(reason)")
                        
                    case .error(let errorMessage):
                        print("❌ Error moderando: \(errorMessage)")
                    }
                    
                    continuation.resume()
                }
            }
        }
        
        print("✅ Moderación silenciosa completada")
    }
    
    // MARK: - 🔄 HELPERS
    @MainActor
    private func updateProgress(_ moment: UploadingMoment, progress: Double, status: UploadStatus? = nil, error: String? = nil) {
        if let index = uploadingMoments.firstIndex(where: { $0.id == moment.id }) {
            uploadingMoments[index].uploadProgress = progress
            if let status = status {
                uploadingMoments[index].status = status
            }
            if let error = error {
                uploadingMoments[index].errorMessage = error
            }
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
        
        DispatchQueue.main.async {
            moment.status = .uploading
            moment.uploadProgress = 0.0
            moment.errorMessage = nil
            self.isProcessing = true
        }
        
        Task.detached(priority: .userInitiated) {
            await self.processUpload(moment)
        }
    }
    
    // MARK: - 🗑️ CANCELAR UPLOAD
    func cancelUpload(_ moment: UploadingMoment) {
        DispatchQueue.main.async {
            self.removeUploadingMoment(moment)
        }
    }
    
    // MARK: - 🔄 HELPER: Convertir AudienceSetting a String
    private func convertAudienceSettingToString(_ setting: CaptionAndDetailsView.AudienceSetting) -> String {
        switch setting {
        case .everyone: return "everyone"
        case .mutuals: return "mutuals"
        case .admirers: return "admirers"
        case .bestFriends: return "bestFriends"
        case .custom: return "custom"
        }
    }
}
