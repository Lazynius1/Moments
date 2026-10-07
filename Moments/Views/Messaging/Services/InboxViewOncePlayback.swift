import Foundation
import UIKit
import FirebaseFirestore
import FirebaseAuth

/// Ver una vez reproducido desde la lista de chats, sin entrar en la conversación.
struct InboxViewOncePresentation: Identifiable {
    let id = UUID()
    let conversation: Conversation
    let message: EnhancedMessage
    let authorName: String
}

/// Preparación en curso del botón de la fila (spinner + bloqueo de dobles pulsaciones).
struct InboxViewOncePreparation: Equatable {
    let conversationId: String
    let token = UUID()
}

/// Localiza, descifra y resuelve el ver una vez pendiente con los mismos servicios del chat,
/// y replica los efectos del visor del chat (visto, sesión de replay, respuestas).
enum InboxViewOncePlayback {
    /// Tope de espera antes de abrir el chat como alternativa (descarga colgada, sin red…).
    static let preparationTimeout: TimeInterval = 20

    /// Último ver una vez recibido sin abrir, con la media ya disponible en local. nil si no hay o falla.
    static func prepare(conversationId: String) async -> EnhancedMessage? {
        guard !conversationId.isEmpty,
              let currentUserId = Auth.auth().currentUser?.uid else { return nil }
        let service = ChatService.shared

        let documents: [QueryDocumentSnapshot]
        do {
            documents = try await service.db.messagingThread(conversationId)
                .messagingMessages
                .applyingHistoryCutoff(service.resolvedHistoryCutoff(conversationId: conversationId))
                .order(by: "timestamp", descending: true)
                .limit(to: 10)
                .getDocuments()
                .documents
        } catch {
            LogConfig.log("Inbox view-once fetch failed: \(error.localizedDescription)", category: "Chat")
            return nil
        }

        guard let document = documents.first(where: {
            isPendingViewOnce($0.data(), conversationId: conversationId, currentUserId: currentUserId)
        }) else { return nil }

        let message = await service.buildEnhancedMessage(
            from: document.data(),
            docId: document.documentID,
            conversationId: conversationId
        )
        guard message.isViewOnce, !message.isDeleted, !message.isUndecryptable else { return nil }

        // Media cifrada: misma resolución (descarga + descifrado + caché en disco) que la burbuja.
        if message.mediaObjectPath?.isEmpty == false, message.mediaEncryption != nil {
            guard let resolved = await service.resolveEncryptedMediaForMessage(message),
                  let mediaUrl = resolved.mediaUrl, !mediaUrl.isEmpty else { return nil }
            message.mediaUrl = mediaUrl
            if let thumbnailUrl = resolved.thumbnailUrl {
                message.thumbnailUrl = thumbnailUrl
            }
        }

        guard let mediaUrl = message.mediaUrl, !mediaUrl.isEmpty, URL(string: mediaUrl) != nil else { return nil }
        return message
    }

    /// Mismo criterio que la preview del inbox: de otro remitente y sin mi uid en `viewedBy`.
    private static func isPendingViewOnce(_ raw: [String: Any], conversationId: String, currentUserId: String) -> Bool {
        let data = GroupChatScope.recipientMetadata(raw, conversationId: conversationId)
        guard data["isDeleted"] as? Bool != true,
              let rawType = data["type"] as? String,
              MessageType(rawValue: rawType)?.isViewOnce == true,
              let senderId = data["senderId"] as? String,
              senderId != currentUserId else { return false }
        if (data["vanishedFor"] as? [String])?.contains(currentUserId) == true { return false }
        let viewedBy = data["viewedBy"] as? [String] ?? []
        return !viewedBy.contains(currentUserId)
    }

    /// Equivale a `handleViewOnceViewerViewed` del chat.
    @MainActor
    static func markViewed(_ message: EnhancedMessage) {
        guard let viewerId = Auth.auth().currentUser?.uid else { return }
        if message.allowReplay == true {
            ViewOnceReplaySessionStore.shared.markAvailable(message: message, viewerId: viewerId)
            message.replayAvailableInCurrentChatSession = true
        }
        ChatService.shared.markViewOnceAsViewed(
            conversationId: message.conversationId,
            messageId: message.id,
            viewerId: viewerId
        ) { _ in }
    }

    /// Al cerrar el visor la repetición sigue disponible: se puede repetir al entrar en el chat, que la
    /// descarta al salir. Si nunca se entra, se descarta al pasar la app a segundo plano.
    @MainActor
    static func finishSession(_ message: EnhancedMessage) {
        installBackgroundObserverIfNeeded()
    }

    @MainActor private static var backgroundObserver: NSObjectProtocol?

    @MainActor
    private static func installBackgroundObserverIfNeeded() {
        guard backgroundObserver == nil else { return }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in abandonPendingReplaysOutsideActiveChat() }
        }
    }

    /// Descarta las repeticiones abiertas desde la lista que no se usaron, salvo la del chat abierto.
    @MainActor
    private static func abandonPendingReplaysOutsideActiveChat() {
        guard let viewerId = Auth.auth().currentUser?.uid else { return }
        let activeConversationId = ChatSessionEngine.shared.activeConversationId
        let pending = ViewOnceReplaySessionStore.shared.drainAvailable(excludingConversationId: activeConversationId)
        pending.forEach { replay in
            // Re-marcar visto (idempotente) antes de consumir: la CF exige mi uid en `viewedBy`.
            ChatService.shared.markViewOnceAsViewed(
                conversationId: replay.conversationId,
                messageId: replay.messageId,
                viewerId: viewerId
            ) { _ in
                ViewOnceConsumptionService.shared.consume(
                    conversationId: replay.conversationId,
                    messageId: replay.messageId,
                    reason: .abandonReplay
                ) { error in
                    if let error {
                        LogConfig.log("Inbox replay consume failed: \(error.localizedDescription)", category: "Chat")
                    }
                }
            }
        }
    }

    /// Respuesta o reacción desde el visor, citando el ver una vez como en el chat.
    @MainActor
    static func sendReply(_ text: String, to presentation: InboxViewOncePresentation) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let senderId = Auth.auth().currentUser?.uid else { return }
        ChatService.shared.sendTextMessage(
            conversationId: presentation.message.conversationId,
            senderId: senderId,
            content: trimmed,
            replyTo: presentation.message.id,
            isVanishModeMessage: presentation.conversation.vanishModeActive == true
        ) { result in
            if case .failure(let error) = result {
                LogConfig.log("Inbox view-once reply failed: \(error.localizedDescription)", category: "Chat")
            }
        }
    }
}
