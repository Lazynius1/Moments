import SwiftUI
import Combine

/// Progreso 0…1 de la floating tab bar de Moments (0 = expandida, 1 = encogida).
@MainActor
final class TabBarMinimizeController: ObservableObject {
    @Published var progress: CGFloat = 0
    /// Oculta la pill (notificaciones, settings, chat, perfiles pusheados, etc.).
    @Published private(set) var isHidden: Bool = false

    /// Refcount: varias pantallas con back pueden pedir hide a la vez.
    private var hideCount = 0

    func requestHidden(_ hidden: Bool) {
        if hidden {
            hideCount += 1
        } else {
            hideCount = max(0, hideCount - 1)
        }
        let next = hideCount > 0
        guard isHidden != next else { return }
        withAnimation(.interpolatingSpring(duration: 0.25, bounce: 0, initialVelocity: 0)) {
            isHidden = next
        }
    }

    func expand() {
        guard progress != 0 else { return }
        withAnimation(.interpolatingSpring(duration: 0.25, bounce: 0, initialVelocity: 0)) {
            progress = 0
        }
    }
}
