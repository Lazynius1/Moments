import Foundation
import Combine
import SwiftData
import FirebaseFirestore

@MainActor
class OfflineSyncService: ObservableObject {
    static let shared = OfflineSyncService()
    
    private var cancellables = Set<AnyCancellable>()
    private var isSyncing = false
    private var isAutomaticSyncEnabled = false
    
    private init() {
        setupConnectivityListener()
    }

    func enableAutomaticSync() {
        guard !isAutomaticSyncEnabled else { return }
        isAutomaticSyncEnabled = true

        // Disparar sincronización inicial cuando la UI ya tuvo tiempo de arrancar.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await syncPendingActions()
        }
    }
    
    /// Escucha cambios en la conexión para disparar la sincronización
    private func setupConnectivityListener() {
        NetworkMonitor.shared.$isConnected
            .sink { [weak self] isConnected in
                guard let self, self.isAutomaticSyncEnabled, isConnected else { return }
                if isConnected {
                    Task { @MainActor in
                        await self.syncPendingActions()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    /// Empieza a procesar la cola de acciones persistente
    func syncPendingActions() async {
        guard isAutomaticSyncEnabled && !isSyncing && NetworkMonitor.shared.isConnected else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        var pendingActions = LocalPersistenceService.shared.loadPendingActions()
        guard !pendingActions.isEmpty else { return }
        
        // ✅ OPTIMIZACIÓN: Eliminar acciones que se cancelan entre sí (ej: like -> unlike)
        pendingActions = await optimizePendingActions(pendingActions)
        guard !pendingActions.isEmpty else {
            print("✨ OfflineSync: Todas las acciones fueron optimizadas/canceladas locally")
            return
        }
        
        for action in pendingActions {
            // Si la conexión se cae durante el proceso, paramos
            guard NetworkMonitor.shared.isConnected else { break }
            
            await executeAction(action)
        }
    }
    
    /// Ejecuta una acción específica según su tipo
    private func executeAction(_ action: CachedAction) async {
        LocalPersistenceService.shared.updateActionStatus(id: action.id, status: .executing)
        
        do {
            switch action.type {
            case CachedAction.ActionType.momentUpload.rawValue:
                // Retomar la subida usando el servicio especializado
                await BackgroundMomentUploadService.shared.resumeUpload(from: action)
                // Nota: resumeUpload ya borra su propia acción si tiene éxito al "empezar"
                break
                
            case CachedAction.ActionType.storyUpload.rawValue:
                // Retomar subida de historia (usando su propio servicio)
                await BackgroundStoryUploadService.shared.resumeUpload(from: action)
                break
                
            case CachedAction.ActionType.reaction.rawValue:
                // Retomar toggle de reacción
                if let payload = try? JSONDecoder().decode(ReactionPayload.self, from: action.payloadData) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        FirestoreService.shared.addReaction(to: payload.momentId, reaction: payload.reaction, userId: payload.userId, authorId: payload.authorId) { error in
                            if error == nil {
                                LocalPersistenceService.shared.deleteAction(id: action.id)
                            }
                            continuation.resume()
                        }
                    }
                } else {
                    LocalPersistenceService.shared.deleteAction(id: action.id)
                }
                break
                
            case CachedAction.ActionType.comment.rawValue:
                // Retomar creación de comentario
                if let payload = try? JSONDecoder().decode(CommentPayload.self, from: action.payloadData) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        FirestoreService.shared.addComment(
                            to: payload.momentId,
                            userId: payload.authorId,
                            authorId: payload.senderId,
                            content: payload.content,
                            parentCommentId: payload.parentCommentId,
                            commentId: payload.commentId // ✅ Usar ID persistido para coincidir con eventuales deletes
                        ) { result in
                            if case .success = result {
                                LocalPersistenceService.shared.deleteAction(id: action.id)
                            }
                            continuation.resume()
                        }
                    }
                } else {
                    LocalPersistenceService.shared.deleteAction(id: action.id)
                }
                break
                
            case CachedAction.ActionType.message.rawValue:
                // Retomar envío de mensaje
                if let payload = try? JSONDecoder().decode(MessagePayload.self, from: action.payloadData) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        ChatService.shared.sendMessage(payload.message, useServerTimestamp: payload.useServerTimestamp) { result in
                            if case .success = result {
                                LocalPersistenceService.shared.deleteAction(id: action.id)
                            }
                            continuation.resume()
                        }
                    }
                } else {
                    LocalPersistenceService.shared.deleteAction(id: action.id)
                }
                break
                
            case CachedAction.ActionType.deleteComment.rawValue:
                // Retomar borrado de comentario
                if let payload = try? JSONDecoder().decode(DeleteCommentPayload.self, from: action.payloadData) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        FirestoreService.shared.deleteComment(to: payload.momentId, commentId: payload.commentId, userId: payload.userId, authorId: payload.authorId) { result in
                            if case .success = result {
                                LocalPersistenceService.shared.deleteAction(id: action.id)
                            }
                            continuation.resume()
                        }
                    }
                } else {
                    LocalPersistenceService.shared.deleteAction(id: action.id)
                }
                break
                
            case CachedAction.ActionType.follow.rawValue:
                // Retomar follow/unfollow
                if let payload = try? JSONDecoder().decode(FollowActionPayload.self, from: action.payloadData) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        if payload.isFollow {
                            FirestoreService.shared.followUser(currentUserId: payload.followerId, targetUserId: payload.followedId) { error in
                                if error == nil {
                                    LocalPersistenceService.shared.deleteAction(id: action.id)
                                }
                                continuation.resume()
                            }
                        } else {
                            FirestoreService.shared.unfollowUser(currentUserId: payload.followerId, targetUserId: payload.followedId) { error in
                                if error == nil {
                                    LocalPersistenceService.shared.deleteAction(id: action.id)
                                }
                                continuation.resume()
                            }
                        }
                    }
                } else {
                    LocalPersistenceService.shared.deleteAction(id: action.id)
                }
                break
                
            case CachedAction.ActionType.save.rawValue:
                // Retomar toggle de guardado
                if let payload = try? JSONDecoder().decode(SavePayload.self, from: action.payloadData) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        FirestoreService.shared.toggleSaveMoment(userId: payload.userId, momentId: payload.momentId) { error in
                            if error == nil {
                                LocalPersistenceService.shared.deleteAction(id: action.id)
                            }
                            continuation.resume()
                        }
                    }
                } else {
                    LocalPersistenceService.shared.deleteAction(id: action.id)
                }
                break
                
            case CachedAction.ActionType.block.rawValue:
                // Retomar bloqueo/desbloqueo
                if let payload = try? JSONDecoder().decode(BlockActionPayload.self, from: action.payloadData) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        if payload.isBlock {
                            FirestoreService.shared.blockUser(currentUserId: payload.currentUserId, targetUserId: payload.targetUserId) { error in
                                if error == nil {
                                    LocalPersistenceService.shared.deleteAction(id: action.id)
                                }
                                continuation.resume()
                            }
                        } else {
                            FirestoreService.shared.unblockUser(currentUserId: payload.currentUserId, targetUserId: payload.targetUserId) { error in
                                if error == nil {
                                    LocalPersistenceService.shared.deleteAction(id: action.id)
                                }
                                continuation.resume()
                            }
                        }
                    }
                } else {
                    LocalPersistenceService.shared.deleteAction(id: action.id)
                }
                break
                
            case CachedAction.ActionType.updateProfile.rawValue:
                // Retomar actualización de perfil
                if let payload = try? JSONDecoder().decode(ProfileUpdatePayload.self, from: action.payloadData) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        if payload.isImageUpdate, let localPath = payload.profileImageLocalPath {
                            // Subir imagen primero
                            if let image = UIImage(contentsOfFile: localPath) {
                                StorageService().uploadProfileImage(userId: payload.userId, image: image) { result in
                                    switch result {
                                    case .success(let url):
                                        // Actualizar Firestore con la URL
                                        FirestoreService.shared.updateProfilePicture(userId: payload.userId, profileImagePath: url) { error in
                                            if error == nil {
                                                LocalPersistenceService.shared.deleteAction(id: action.id)
                                                // Borrar archivo temporal local si ya no se necesita?
                                                // try? FileManager.default.removeItem(atPath: localPath)
                                            }
                                            continuation.resume()
                                        }
                                    case .failure(_):
                                        // Falló la subida, se reintentará en el próximo sync
                                        continuation.resume()
                                    }
                                }
                            } else {
                                // Archivo no encontrado, borrar acción para evitar bucle
                                LocalPersistenceService.shared.deleteAction(id: action.id)
                                continuation.resume()
                            }
                        } else {
                            // Solo actualizar texto (incluyendo intereses)
                            let group = DispatchGroup()
                            var syncError: Error?
                            
                            group.enter()
                            FirestoreService.shared.updateProfileDetails(
                                userId: payload.userId,
                                oldBio: payload.oldBio,
                                newBio: payload.bio,
                                oldWebsite: payload.oldWebsiteUrl,
                                newWebsite: payload.websiteUrl
                            ) { error in
                                if let error = error { syncError = error }
                                group.leave()
                            }
                            
                            if let interests = payload.interests {
                                group.enter()
                                // Usar una función helper de FirestoreService o llamar directo si no existe
                                Firestore.firestore().collection("users").document(payload.userId).updateData([
                                    "interests": interests
                                ] ) { error in
                                    if let error = error { syncError = error }
                                    group.leave()
                                }
                            }
                            
                            group.notify(queue: .main) {
                                if syncError == nil {
                                    LocalPersistenceService.shared.deleteAction(id: action.id)
                                }
                                continuation.resume()
                            }
                        }
                    }
                } else {
                    LocalPersistenceService.shared.deleteAction(id: action.id)
                }
                
            case CachedAction.ActionType.acceptFollowRequest.rawValue:
                if let payload = try? JSONDecoder().decode(FollowRequestActionPayload.self, from: action.payloadData) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        FirestoreService.shared.acceptFollowRequest(notificationId: payload.notificationId, recipientId: payload.recipientId, senderId: payload.senderId) { error in
                            if error == nil {
                                LocalPersistenceService.shared.deleteAction(id: action.id)
                            }
                            continuation.resume()
                        }
                    }
                } else {
                    LocalPersistenceService.shared.deleteAction(id: action.id)
                }
                break
                
            case CachedAction.ActionType.rejectFollowRequest.rawValue:
                if let payload = try? JSONDecoder().decode(FollowRequestActionPayload.self, from: action.payloadData) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        FirestoreService.shared.rejectFollowRequest(notificationId: payload.notificationId, recipientId: payload.recipientId, senderId: payload.senderId) { error in
                            if error == nil {
                                LocalPersistenceService.shared.deleteAction(id: action.id)
                            }
                            continuation.resume()
                        }
                    }
                } else {
                    LocalPersistenceService.shared.deleteAction(id: action.id)
                }
                break
                
            case CachedAction.ActionType.reportContent.rawValue:
                if let payload = try? JSONDecoder().decode(ReportActionPayload.self, from: action.payloadData) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        let reportData: [String: Any] = [
                            "reporterId": payload.reporterId,
                            "reportedUserId": payload.reportedUserId,
                            "reportedContentType": payload.reportedContentType,
                            "reportedContentId": payload.reportedContentId,
                            "category": payload.category,
                            "description": payload.description,
                            "status": "pending",
                            "priority": payload.priority,
                            "timestamp": FieldValue.serverTimestamp(),
                            "resolvedAt": NSNull(),
                            "moderatorId": NSNull(),
                            "moderatorNotes": ""
                        ]
                        
                        Firestore.firestore().collection("reports").addDocument(data: reportData) { error in
                            if error == nil {
                                LocalPersistenceService.shared.deleteAction(id: action.id)
                            }
                            continuation.resume()
                        }
                    }
                } else {
                    LocalPersistenceService.shared.deleteAction(id: action.id)
                }
                break
                
                
            case CachedAction.ActionType.markAsRead.rawValue:
                if let payload = try? JSONDecoder().decode(MarkAsReadPayload.self, from: action.payloadData) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        Firestore.firestore().collection("users").document(payload.userId).collection("notifications").document(payload.notificationId).updateData([
                            "isPending": false
                        ]) { error in
                            if error == nil {
                                LocalPersistenceService.shared.deleteAction(id: action.id)
                            }
                            continuation.resume()
                        }
                    }
                } else {
                    LocalPersistenceService.shared.deleteAction(id: action.id)
                }
                break
                
                
            case CachedAction.ActionType.deleteMoment.rawValue:
                if let payload = try? JSONDecoder().decode(DeleteMomentPayload.self, from: action.payloadData) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        // 1. Eliminar documento de Firestore
                        Firestore.firestore().collection("users").document(payload.userId).collection("moments").document(payload.momentId).delete { error in
                            
                            // 2. Eliminar archivos de Storage (fire & forget, no bloquea la cola si falla)
                            let storageService = StorageService() // Asumiendo que es accesible o se puede instanciar
                             
                            if let imagePath = payload.imagePath, !imagePath.isEmpty {
                                storageService.deleteMedia(path: imagePath) { _ in }
                            }
                            
                            if let videoUrl = payload.videoUrl, !videoUrl.isEmpty {
                                storageService.deleteMedia(path: videoUrl) { _ in }
                            }
                            
                            if error == nil {
                                LocalPersistenceService.shared.deleteAction(id: action.id)
                            }
                            continuation.resume()
                        }
                    }
                } else {
                    LocalPersistenceService.shared.deleteAction(id: action.id)
                }
                break
                
            default:
                break
            }
            
            LocalPersistenceService.shared.updateActionStatus(id: action.id, status: .pending) // Si no se borró, vuelve a pendiente
        } catch {
            print("❌ OfflineSync: Error al ejecutar acción \(action.id): \(error)")
            LocalPersistenceService.shared.updateActionStatus(id: action.id, status: .failed, error: error.localizedDescription)
        }
    }
    
    /// Optimiza la lista de acciones eliminando las que se cancelan entre sí
    private func optimizePendingActions(_ actions: [CachedAction]) async -> [CachedAction] {
        var optimizedActions = actions
        var actionsToDelete: Set<String> = []
        
        // 1. OPTIMIZAR COMENTARIOS (Crear + Borrar = Nada)
        let commentActions = actions.filter { $0.type == CachedAction.ActionType.comment.rawValue }
        let deleteCommentActions = actions.filter { $0.type == CachedAction.ActionType.deleteComment.rawValue }
        
        for deleteAction in deleteCommentActions {
            guard let deletePayload = try? JSONDecoder().decode(DeleteCommentPayload.self, from: deleteAction.payloadData) else { continue }
            
            // Buscar si hay una acción de creación para este mismo comentario (por ID)
            if let creationAction = commentActions.first(where: {
                guard let payload = try? JSONDecoder().decode(CommentPayload.self, from: $0.payloadData) else { return false }
                // Coincidir por commentId si existe, o intentar coincidir por contenido/timestamp como fallback arriesgado (mejor solo ID)
                return payload.commentId == deletePayload.commentId
            }) {
                // Encontrado par Crear -> Borrar. Eliminar ambas acciones.
                actionsToDelete.insert(creationAction.id)
                actionsToDelete.insert(deleteAction.id)
            }
        }
        
        // 2. OPTIMIZAR REACCIONES (Toggle + Toggle = Nada)
        // Agrupar por (momentId + userId + reaction)
        let reactionActions = actions.filter { $0.type == CachedAction.ActionType.reaction.rawValue }
        let reactionGroups = Dictionary(grouping: reactionActions) { action -> String in
            guard let payload = try? JSONDecoder().decode(ReactionPayload.self, from: action.payloadData) else { return "unknown" }
            return "\(payload.momentId)_\(payload.userId)_\(payload.reaction)"
        }
        
        for (_, group) in reactionGroups {
            if group.count > 1 {
                // Si la cantidad es par, se cancelan todas (Toggle on -> off -> on -> off)
                if group.count % 2 == 0 {
                    for action in group {
                        actionsToDelete.insert(action.id)
                    }
                } else {
                    // Si es impar, dejar solo el último, borrar los anteriores
                    let sorted = group.sorted { $0.createdAt < $1.createdAt }
                    for i in 0..<(sorted.count - 1) {
                        actionsToDelete.insert(sorted[i].id)
                    }
                }
            }
        }
        
        // 3. OPTIMIZAR SAVE (Toggle + Toggle = Nada)
        let saveActions = actions.filter { $0.type == CachedAction.ActionType.save.rawValue }
        let saveGroups = Dictionary(grouping: saveActions) { action -> String in
            guard let payload = try? JSONDecoder().decode(SavePayload.self, from: action.payloadData) else { return "unknown" }
            return "\(payload.momentId)_\(payload.userId)"
        }
        
        for (_, group) in saveGroups {
            if group.count > 1 {
                if group.count % 2 == 0 {
                    for action in group { actionsToDelete.insert(action.id) }
                } else {
                    let sorted = group.sorted { $0.createdAt < $1.createdAt }
                    for i in 0..<(sorted.count - 1) { actionsToDelete.insert(sorted[i].id) }
                }
            }
        }
        
        // 4. OPTIMIZAR FOLLOW (Follow + Unfollow = Nada)
        let followActions = actions.filter { $0.type == CachedAction.ActionType.follow.rawValue }
        let followGroups = Dictionary(grouping: followActions) { action -> String in
            guard let payload = try? JSONDecoder().decode(FollowActionPayload.self, from: action.payloadData) else { return "unknown" }
            return "\(payload.followerId)_\(payload.followedId)"
        }
        
        for (_, group) in followGroups {
            if group.count > 1 {
                // Estrategia: Ejecutar SOLO la última acción.
                let sorted = group.sorted { $0.createdAt < $1.createdAt }
                for i in 0..<(sorted.count - 1) {
                    actionsToDelete.insert(sorted[i].id)
                }
            }
        }

        // Ejecutar borrado de acciones canceladas
        if !actionsToDelete.isEmpty {
            print("✨ OfflineSync: Eliminando \(actionsToDelete.count) acciones redundantes/canceladas")
            for id in actionsToDelete {
                LocalPersistenceService.shared.deleteAction(id: id)
            }
        }
        
        return optimizedActions.filter { !actionsToDelete.contains($0.id) }
    }
}
