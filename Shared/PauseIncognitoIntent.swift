import ActivityKit
import AppIntents
import Foundation

@available(iOS 18.0, *)
struct PauseIncognitoIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause Incognito"
    static var openAppWhenRun = false
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: Foundation.Notification.Name("incognitoLiveActivityPauseRequested"),
            object: nil
        )
        pauseFromExtensionFallback()

        return .result()
    }

    private func pauseFromExtensionFallback() {
        let defaults = UserDefaults(suiteName: "group.com.glowsyapp")
        let remainingSeconds = defaults?.integer(forKey: "incognito_mirrored_remaining_seconds") ?? 0

        defaults?.set(false, forKey: "incognito_mirrored_is_active")
        defaults?.set("pause", forKey: "incognito_pending_widget_action")
        defaults?.set(Date().timeIntervalSince1970, forKey: "incognito_pending_widget_action_timestamp")

        let finalState = IncognitoActivityAttributes.ContentState(
            remainingSeconds: max(remainingSeconds, 0),
            isActive: false
        )

        Task {
            for activity in Activity<IncognitoActivityAttributes>.activities {
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
    }
}
