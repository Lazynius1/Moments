import Foundation
import FirebaseAuth
import UserNotifications

extension Foundation.Notification.Name {
    /// Feed listo para mostrar WhatsNew (tras ads/notifs).
    static let whatsNewReadyToPresent = Foundation.Notification.Name("WhatsNewReadyToPresent")
}

/// Decide *si* hay WhatsNew pendiente y *cuándo* presentarlo (no en splash/login).
@MainActor
final class WhatsNewPresentationCoordinator {
    static let shared = WhatsNewPresentationCoordinator()

    private static let lastVersionKey = "lastVersionPrompted"
    /// Valor legacy / default de `@AppStorage` — trata como “nunca promptado”.
    private static let neverPromptedSentinel = "1.0.0"

    private(set) var isPending = false
    private var didPresentThisLaunch = false
    private var evaluationTask: Task<Void, Never>?
    private var feedAppearAt: Date?

    private init() {}

    var currentMarketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.30"
    }

    private var lastPromptedVersion: String {
        get { UserDefaults.standard.string(forKey: Self.lastVersionKey) ?? Self.neverPromptedSentinel }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastVersionKey) }
    }

    /// Llamar al terminar el splash: 1ª install y upgrades dejan pendiente (mismas notas 2.30).
    func handleSplashFinished() {
        let current = currentMarketingVersion
        let last = lastPromptedVersion

        // Primera install / wipe (`1.0.0` sentinel) o upgrade → mismas notas; no hay onboarding aparte.
        if last == Self.neverPromptedSentinel || last.isEmpty || last != current {
            isPending = true
        } else {
            isPending = false
        }
    }

    /// El feed principal está visible: evaluar cuando ads + notifs hayan pasado.
    func feedBecameActive() {
        guard isPending, !didPresentThisLaunch else { return }
        guard Auth.auth().currentUser != nil else { return }
        feedAppearAt = Date()
        evaluationTask?.cancel()
        evaluationTask = Task { [weak self] in
            await self?.runEvaluationLoop()
        }
    }

    func feedBecameInactive() {
        evaluationTask?.cancel()
        evaluationTask = nil
    }

    private func runEvaluationLoop() async {
        // Hasta ~35s: cubre consent ad + primer notifs (+20s) + margen.
        for _ in 0..<70 {
            if Task.isCancelled { return }
            if await isReadyToPresent() {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // respiro 1s
                if Task.isCancelled { return }
                if await isReadyToPresent() {
                    presentIfNeeded()
                }
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        // Timeout: presentar si sigue pendiente (mejor tarde que nunca).
        presentIfNeeded()
    }

    private func isReadyToPresent() async -> Bool {
        guard isPending, !didPresentThisLaunch else { return false }
        guard Auth.auth().currentUser != nil else { return false }

        let adsReady = await MainActor.run {
            !AdMobConfiguration.shared.shouldShowConsentFlow
                || FeedNativeAdPool.didOfferConsentThisSession
        }
        guard adsReady else { return false }

        let notifsReady = await notificationsSettled()
        guard notifsReady else { return false }

        return true
    }

    private func notificationsSettled() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    switch settings.authorizationStatus {
                    case .notDetermined:
                        // Esperar a que haya pasado la ventana del primer (+20s) + 2s.
                        let elapsed = Date().timeIntervalSince(self.feedAppearAt ?? Date())
                        continuation.resume(returning: elapsed >= 22)
                    default:
                        continuation.resume(returning: true)
                    }
                }
            }
        }
    }

    private func presentIfNeeded() {
        guard isPending, !didPresentThisLaunch else { return }
        didPresentThisLaunch = true
        isPending = false
        lastPromptedVersion = currentMarketingVersion
        NotificationCenter.default.post(name: .whatsNewReadyToPresent, object: nil)
    }
}
