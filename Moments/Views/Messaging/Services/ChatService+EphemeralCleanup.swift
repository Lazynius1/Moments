import Foundation
import FirebaseFirestore
import FirebaseAuth

extension ChatService {
    // MARK: - Ephemeral Messages
    func markEphemeralAsViewed(conversationId: String, messageId: String, completion: @escaping (Error?) -> Void) {
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData(["isViewed": true]) { error in
                completion(error)
            }
    }

    // MARK: - Ephemeral Cleanup System with Encryption
    func startEphemeralCleanupTimer() {
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanupExpiredEphemeralMessages()
            }
        }
        // Diferir el primer cleanup (query collectionGroup) para no competir con el
        // arranque en frío.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.cleanupExpiredEphemeralMessages()
        }
    }

    func cleanupExpiredEphemeralMessages() {
        let now = Date()

        // Acotar a los mensajes que envié yo: las reglas de Firestore solo permiten
        // leer mensajes de conversaciones donde participo, así que una query
        // collection-group GLOBAL sería denegada. Filtrar por senderId == miUid hace
        // la query verificable (regla: resource.data.senderId == request.auth.uid) y
        // segura. Cada participante limpia los efímeros que él mismo envió.
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        db.collectionGroup("messages")
            .whereField("senderId", isEqualTo: currentUserId)
            .whereField("type", isEqualTo: MessageType.ephemeral.rawValue)
            .whereField("expirationDate", isLessThan: now)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }

                if error != nil {
                    return
                }

                guard let documents = snapshot?.documents else {
                    return
                }

                let group = DispatchGroup()

                for document in documents {
                    group.enter()

                    let data = document.data()
                    let mediaResources: [String] = [
                        data["mediaObjectPath"] as? String,
                        data["thumbnailObjectPath"] as? String,
                        data["mediaUrl"] as? String,
                        data["thumbnailUrl"] as? String
                    ].compactMap { value -> String? in
                        guard let value, !value.isEmpty else { return nil }
                        return value
                    }
                    let conversationId = data["conversationId"] as? String ?? ""
                    let messageId = data["id"] as? String ?? document.documentID

                    Task { @MainActor in
                        self.cleanupSingleEphemeralMessage(
                            conversationId: conversationId,
                            messageId: messageId,
                            mediaResources: mediaResources
                        ) { _ in
                            group.leave()
                        }
                    }
                }

                group.notify(queue: .main) {
                }
            }
    }

    private func cleanupSingleEphemeralMessage(conversationId: String, messageId: String, mediaResources: [String], completion: @escaping (Bool) -> Void) {
        let batch = db.batch()

        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)

        Task {
            let expiredText = "📸 Momento efímero expirado"
            let encryptedExpiredText = await encryptMessageContent(expiredText, for: conversationId)

            batch.updateData([
                "mediaUrl": FieldValue.delete(),
                "thumbnailUrl": FieldValue.delete(),
                "mediaObjectPath": FieldValue.delete(),
                "thumbnailObjectPath": FieldValue.delete(),
                "mediaEncryption": FieldValue.delete(),
                "thumbnailEncryption": FieldValue.delete(),
                "textOverlayLive": FieldValue.delete(),
                "textOverlays": FieldValue.delete(),
                "stickers": FieldValue.delete(),
                "drawingData": FieldValue.delete(),
                "content": encryptedExpiredText,
                "isDeleted": true,
                "deletedAt": FieldValue.serverTimestamp()
            ], forDocument: messageRef)

            do {
                try await batch.commit()
                if !mediaResources.isEmpty {
                    self.deleteMediaFiles(urls: mediaResources) { _ in
                        completion(true)
                    }
                } else {
                    completion(true)
                }
            } catch {
                completion(false)
            }
        }
    }

    private func deleteImageFromStorage(mediaUrl: String, completion: @escaping (Bool) -> Void) {
        deleteMediaFile(url: mediaUrl) { result in
            switch result {
            case .success:
                completion(true)
            case .failure:
                completion(false)
            }
        }
    }

    func forceCleanupExpiredEphemeralMessages(completion: @escaping (Int) -> Void) {
        cleanupExpiredEphemeralMessages()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            completion(0)
        }
    }
}

// MARK: - Enhanced Ephemeral Cleanup Manager
@MainActor
class EphemeralCleanupManager: ObservableObject {
    private let chatService = ChatService.shared

    init() {
        startCleanupSystem()
    }

    private func startCleanupSystem() {
        chatService.startEphemeralCleanupTimer()
    }

    func cleanupNow() {
        chatService.forceCleanupExpiredEphemeralMessages { _ in
        }
    }
}
