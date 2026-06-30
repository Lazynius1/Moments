import Combine
import UIKit

/// Observa el ciclo de vida del teclado para sincronizar scroll del chat (paridad WhatsApp/iMessage).
final class ChatKeyboardScrollCoordinator: NSObject, ObservableObject {
    @Published private(set) var keyboardHeight: CGFloat = 0
    @Published private(set) var isVisible = false
    @Published private(set) var animationDuration: TimeInterval = 0.25
    @Published private(set) var isTransitioning = false

    private var transitionResetTask: Task<Void, Never>?

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleKeyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleKeyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        transitionResetTask?.cancel()
    }

    @objc private func handleKeyboardWillChangeFrame(_ notification: NSNotification) {
        applyKeyboardFrame(notification, visible: true)
    }

    @objc private func handleKeyboardWillHide(_ notification: NSNotification) {
        applyKeyboardFrame(notification, visible: false)
    }

    private func applyKeyboardFrame(_ notification: NSNotification, visible: Bool) {
        guard let userInfo = notification.userInfo else { return }

        let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.animationDuration = duration
            self.isTransitioning = true
            self.scheduleTransitionReset(after: duration)

            let height: CGFloat
            if visible,
               let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                height = Self.overlapHeight(for: keyboardFrame)
            } else {
                height = 0
            }

            self.keyboardHeight = height
            self.isVisible = visible && height > 0
        }
    }

    private func scheduleTransitionReset(after duration: TimeInterval) {
        transitionResetTask?.cancel()
        let delayNs = UInt64(max(duration, 0.05) * 1_000_000_000) + 32_000_000
        transitionResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            self?.isTransitioning = false
        }
    }

    private static func overlapHeight(for keyboardFrame: CGRect) -> CGFloat {
        let activeWindow: UIWindow? = {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            if let keyWindow = windows.first(where: { $0.isKeyWindow && !$0.description.contains("RemoteKeyboard") }) {
                return keyWindow
            }
            return windows.first(where: { !$0.description.contains("RemoteKeyboard") }) ?? windows.first
        }()

        if let window = activeWindow {
            let convertedFrame = window.convert(keyboardFrame, from: nil)
            return max(0, window.bounds.height - convertedFrame.minY)
        }

        let screenHeight = UIScreen.main.bounds.height
        return max(0, screenHeight - keyboardFrame.minY)
    }
}
