import Foundation
import SwiftUI

/// Resuelve el acceso cripto al chat una vez por sesión de app (estilo WA/Telegram).
@MainActor
final class ChatAccessCoordinator: ObservableObject {
    static let shared = ChatAccessCoordinator()

    @Published private(set) var accessState: ChatAccessState?

    private var resolveTask: Task<Void, Never>?

    private init() {}

    /// Devuelve el estado cacheado o lo resuelve si aún no se ha hecho en esta sesión.
    func ensureAccess() async -> ChatAccessState {
        if let accessState {
            return accessState
        }

        if let resolveTask {
            await resolveTask.value
            return accessState ?? .unavailable(
                NSLocalizedString("chatRecovery.unavailable.title", comment: "Chat unavailable")
            )
        }

        let task = Task { @MainActor in
            let state = await EncryptionService.shared.chatAccessState()
            self.accessState = state
            self.resolveTask = nil
        }
        resolveTask = task
        await task.value
        return accessState ?? .unavailable(
            NSLocalizedString("chatRecovery.unavailable.title", comment: "Chat unavailable")
        )
    }

    /// Tras PIN setup/restore o retry manual.
    func refreshAccess() async {
        resolveTask?.cancel()
        resolveTask = nil
        accessState = await EncryptionService.shared.chatAccessState()
    }

    /// Sign-out o cambio de identidad.
    func invalidate() {
        resolveTask?.cancel()
        resolveTask = nil
        accessState = nil
    }

    var isAvailable: Bool {
        accessState == .available
    }
}
