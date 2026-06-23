import Foundation
import FirebaseAuth
import SwiftUI

/// Resuelve el acceso cripto al chat una vez por sesión de app.
@MainActor
final class ChatAccessCoordinator: ObservableObject {
    static let shared = ChatAccessCoordinator()

    @Published private(set) var accessState: ChatAccessState?

    private var resolveTask: Task<Void, Never>?
    private var resolvedUserId: String?

    private init() {}

    /// Devuelve el estado cacheado o lo resuelve si aún no se ha hecho en esta sesión.
    func ensureAccess() async -> ChatAccessState {
        guard let userId = Auth.auth().currentUser?.uid else {
            invalidateAll()
            return .unavailable(NSLocalizedString("chatRecovery.unavailable.title", comment: "Chat unavailable"))
        }

        if resolvedUserId != userId {
            invalidateAll()
        }

        if let accessState, resolvedUserId == userId {
            return accessState
        }

        if let resolveTask {
            await resolveTask.value
            if resolvedUserId == userId, let accessState {
                return accessState
            }
            return .unavailable(
                NSLocalizedString("chatRecovery.unavailable.title", comment: "Chat unavailable")
            )
        }

        let task = Task { @MainActor in
            let state = await EncryptionService.shared.chatAccessState()
            guard Auth.auth().currentUser?.uid == userId else { return }
            self.resolvedUserId = userId
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
        guard let userId = Auth.auth().currentUser?.uid else {
            invalidateAll()
            return
        }
        resolveTask?.cancel()
        resolveTask = nil
        let state = await EncryptionService.shared.chatAccessState()
        guard Auth.auth().currentUser?.uid == userId else { return }
        resolvedUserId = userId
        accessState = state
    }

    /// Sign-out o cambio de identidad.
    func invalidate() {
        invalidateAll()
    }

    func invalidate(for userId: String?) {
        guard userId == nil || userId == resolvedUserId else { return }
        invalidateAll()
    }

    func invalidateAll() {
        resolveTask?.cancel()
        resolveTask = nil
        accessState = nil
        resolvedUserId = nil
    }

    var isAvailable: Bool {
        accessState == .available
    }
}
