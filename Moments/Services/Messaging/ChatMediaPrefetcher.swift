import Foundation
import FirebaseAuth

/// Precarga proactiva de media de chat: cuando llegan
/// mensajes con media, descarga y descifra el contenido en segundo plano —según la
/// política de auto-descarga y la cuota— para que el caché refleje lo recibido y la
/// media esté lista antes de abrir la conversación.
///
/// Reutiliza el resolver cifrado existente, que ya aplica `ChatMediaDownloadPolicy`
/// y `ChatCacheStore.enforceQuota()`; aquí solo se decide *qué* precargar y se acota
/// la concurrencia para no saturar red/CPU.
@MainActor
final class ChatMediaPrefetcher {
    static let shared = ChatMediaPrefetcher()

    private var inFlight = Set<String>()
    private var pending: [EnhancedMessage] = []
    private var activeCount = 0
    private let maxConcurrent = 3

    private init() {}

    /// Encola la media descargable de estos mensajes para precarga en background.
    /// No-op si la política de descarga no lo permite ahora (p. ej. wifi-only en celular).
    func prefetchIfNeeded(_ messages: [EnhancedMessage]) {
        guard ChatMediaDownloadPolicy.shouldDownloadAutomatically() else { return }
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        for message in messages where shouldPrefetch(message, currentUserId: currentUserId) {
            guard !inFlight.contains(message.id) else { continue }
            inFlight.insert(message.id)
            pending.append(message)
        }
        pump()
    }

    private func shouldPrefetch(_ message: EnhancedMessage, currentUserId: String) -> Bool {
        guard !message.isDeleted else { return false }
        // Los mensajes propios ya se cachean localmente al enviarse.
        guard message.senderId != currentUserId else { return false }
        // View-once y efímeros se abren deliberadamente: no se precachean en silencio.
        guard message.type == .image || message.type == .video else { return false }
        // Debe tener media cifrada descargable.
        guard let path = message.mediaObjectPath, !path.isEmpty, message.mediaEncryption != nil else { return false }
        return true
    }

    private func pump() {
        while activeCount < maxConcurrent, !pending.isEmpty {
            let message = pending.removeFirst()
            activeCount += 1
            Task { [weak self] in
                // El resolver descarga, descifra, escribe a disco y aplica cuota.
                // Devuelve nil sin efecto si la política bloquea ese fichero concreto.
                _ = await ChatService.shared.encryptedMediaResolver.resolveForMessage(message)
                self?.finish(message.id)
            }
        }
    }

    private func finish(_ messageId: String) {
        inFlight.remove(messageId)
        activeCount = max(0, activeCount - 1)
        pump()
    }
}
