import Foundation
import Combine
import FirebaseAuth

/// Precarga proactiva de media de chat: cuando llegan
/// mensajes con media, descarga y descifra el contenido en segundo plano para que la
/// media esté lista antes de abrir la conversación.
///
/// Reutiliza el resolver cifrado existente, que ya aplica la caché automática
/// y `ChatCacheStore.enforceQuota()`; aquí solo se decide *qué* precargar y se acota
/// la concurrencia para no saturar red/CPU.
@MainActor
final class ChatMediaPrefetcher {
    static let shared = ChatMediaPrefetcher()

    private var inFlight = Set<String>()
    private var pending: [EnhancedMessage] = []
    private var activeCount = 0
    private let maxConcurrent = 3

    private var connectivitySubscription: AnyCancellable?

    private init() {
        connectivitySubscription = NetworkMonitor.shared.$isConnected
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                if connected { self?.pump() }
            }
    }

    /// Encola la media descargable de estos mensajes para precarga en background.
    /// Conserva la cola sin conexión y la reanuda al recuperar la red.
    func prefetchIfNeeded(_ messages: [EnhancedMessage]) {
        guard Auth.auth().currentUser != nil else { return }

        for message in messages where shouldPrefetch(message) {
            guard !inFlight.contains(message.id) else { continue }
            inFlight.insert(message.id)
            pending.append(message)
        }
        pump()
    }

    private func shouldPrefetch(_ message: EnhancedMessage) -> Bool {
        guard !message.isDeleted else { return false }
        // View-once y efímeros se abren deliberadamente: no se precachean en silencio.
        guard message.isVanishModeMessage != true,
              [.image, .video, .audio, .file].contains(message.type) else { return false }
        // Debe tener media cifrada descargable.
        guard let path = message.mediaObjectPath, !path.isEmpty, message.mediaEncryption != nil else { return false }
        return true
    }

    private func pump() {
        guard NetworkMonitor.shared.isConnected else { return }
        guard Auth.auth().currentUser != nil else {
            pending.removeAll()
            inFlight.removeAll()
            return
        }
        while activeCount < maxConcurrent, !pending.isEmpty {
            let message = pending.removeFirst()
            activeCount += 1
            Task { [weak self] in
                // El resolver descarga, descifra, escribe a disco y aplica cuota.
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
