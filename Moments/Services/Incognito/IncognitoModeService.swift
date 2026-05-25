import ActivityKit
import FirebaseAuth
import FirebaseCore
import Foundation
import WidgetKit

@MainActor
final class IncognitoModeService: ObservableObject {
    static let shared = IncognitoModeService()

    enum LastErrorState: Equatable {
        case offline
        case unauthorized
        case exhausted
        case unavailable
        case unknown(String)
    }

    @Published private(set) var isLoaded = false
    @Published private(set) var isSyncing = false
    @Published private(set) var isActive = false
    @Published private(set) var remainingSeconds = 30 * 60
    @Published private(set) var dailyBudgetSeconds = 30 * 60
    @Published private(set) var lastErrorState: LastErrorState?

    var isExhausted: Bool {
        remainingSeconds <= 0
    }

    var formattedTime: String {
        let minutes = max(remainingSeconds, 0) / 60
        let seconds = max(remainingSeconds, 0) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var progress: Double {
        guard dailyBudgetSeconds > 0 else { return 0 }
        return min(max(Double(remainingSeconds) / Double(dailyBudgetSeconds), 0), 1)
    }

    private struct BackendResponse: Decodable {
        let success: Bool
        let reason: String?
        let state: RemoteState
    }

    private struct RemoteState: Decodable {
        let remainingSeconds: Int
        let isActive: Bool
        let lastResetDate: String
        let sessionStartedAt: Date?
        let sessionExpectedEndTime: Date?
        let timezoneIdentifier: String
        let lastUpdatedAt: Date?
        let dailyBudgetSeconds: Int
    }

    private struct MirroredState: Codable {
        let isLoaded: Bool
        let isActive: Bool
        let remainingSeconds: Int
        let dailyBudgetSeconds: Int
        let sessionExpectedEndTime: Date?
        let timezoneIdentifier: String
        let lastUpdatedAt: Date?
    }

    private enum Action: String {
        case get = "getIncognitoState"
        case activate = "activateIncognito"
        case pause = "pauseIncognito"
        case resume = "resumeIncognito"
    }

    private enum SharedDefaultsKeys {
        static let suiteName = "group.com.glowsyapp"
        static let mirroredState = "incognito_mirrored_state"
        static let mirroredIsActive = "incognito_mirrored_is_active"
        static let mirroredRemainingSeconds = "incognito_mirrored_remaining_seconds"
        static let pendingAction = "incognito_pending_widget_action"
        static let pendingActionTimestamp = "incognito_pending_widget_action_timestamp"
    }

    nonisolated static var isActiveSnapshot: Bool {
        UserDefaults(suiteName: SharedDefaultsKeys.suiteName)?.bool(forKey: SharedDefaultsKeys.mirroredIsActive) ?? false
    }

    private let networkMonitor = NetworkMonitor.shared
    private let defaults = UserDefaults(suiteName: SharedDefaultsKeys.suiteName)
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private var countdownTask: Task<Void, Never>?
    private var sessionExpectedEndTime: Date?
    private var lastKnownTimezoneIdentifier = TimeZone.current.identifier

    private init() {
        hydrateFromMirror()
    }

    func loadState() {
        Task {
            await perform(.get)
        }
    }

    func refresh() {
        Task {
            await perform(.get)
        }
    }

    func activate() {
        Task {
            await perform(.activate)
        }
    }

    func pause() {
        Task {
            await perform(.pause)
        }
    }

    func pauseFromLiveActivity() {
        countdownTask?.cancel()
        countdownTask = nil
        isActive = false
        sessionExpectedEndTime = nil
        syncMirror(lastUpdatedAt: Date())

        Task {
            await endLiveActivity()
            await perform(.pause)
        }
    }

    func resume() {
        Task {
            await perform(.resume)
        }
    }

    func handlePendingAppGroupActionIfNeeded() {
        Task {
            await processPendingAppGroupActionIfNeeded()
        }
    }

    func resetForSignedOutUser() {
        countdownTask?.cancel()
        countdownTask = nil
        isLoaded = false
        isSyncing = false
        isActive = false
        remainingSeconds = 30 * 60
        dailyBudgetSeconds = 30 * 60
        sessionExpectedEndTime = nil
        lastErrorState = nil
        defaults?.removeObject(forKey: SharedDefaultsKeys.mirroredState)
        defaults?.removeObject(forKey: SharedDefaultsKeys.mirroredIsActive)
        defaults?.removeObject(forKey: SharedDefaultsKeys.mirroredRemainingSeconds)

        Task {
            await endLiveActivity()
        }
    }

    private func perform(_ action: Action) async {
        guard let user = Auth.auth().currentUser else {
            lastErrorState = .unauthorized
            return
        }

        guard networkMonitor.isConnected else {
            lastErrorState = .offline
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let token = try await user.getIDToken()
            let response = try await callBackend(action: action, token: token)
            apply(response.state)

            if response.reason == "exhausted" {
                lastErrorState = .exhausted
                HapticManager.shared.notification(.warning)
            } else {
                lastErrorState = nil
            }

            switch action {
            case .activate, .resume:
                HapticManager.shared.mediumImpact()
            case .pause:
                HapticManager.shared.selection()
            case .get:
                break
            }
        } catch let error as URLError {
            lastErrorState = error.code == .notConnectedToInternet ? .offline : .unavailable
        } catch {
            lastErrorState = .unknown(error.localizedDescription)
        }
    }

    private func callBackend(action: Action, token: String) async throws -> BackendResponse {
        guard let projectId = FirebaseApp.app()?.options.projectID,
              let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/\(action.rawValue)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "timezoneIdentifier": TimeZone.current.identifier
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let decoded = try decoder.decode(BackendResponse.self, from: data)
        guard (200 ... 299).contains(httpResponse.statusCode) || httpResponse.statusCode == 409 else {
            throw URLError(.badServerResponse)
        }
        return decoded
    }

    private func apply(_ state: RemoteState) {
        lastKnownTimezoneIdentifier = state.timezoneIdentifier
        dailyBudgetSeconds = max(state.dailyBudgetSeconds, 1)
        sessionExpectedEndTime = state.sessionExpectedEndTime
        isLoaded = true
        isActive = state.isActive
        remainingSeconds = resolvedRemainingSeconds(for: state)

        if remainingSeconds <= 0 {
            isActive = false
            sessionExpectedEndTime = nil
        }

        syncMirror(lastUpdatedAt: state.lastUpdatedAt)
        updatePresentationTimer()

        Task {
            await syncLiveActivity()
        }
    }

    private func resolvedRemainingSeconds(for state: RemoteState) -> Int {
        guard state.isActive, let endDate = state.sessionExpectedEndTime else {
            return max(state.remainingSeconds, 0)
        }
        return max(Int(ceil(endDate.timeIntervalSinceNow)), 0)
    }

    private func updatePresentationTimer() {
        countdownTask?.cancel()
        countdownTask = nil

        guard isActive, let endDate = sessionExpectedEndTime else {
            return
        }

        countdownTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let nextValue = max(Int(ceil(endDate.timeIntervalSinceNow)), 0)

                if nextValue != self.remainingSeconds {
                    self.remainingSeconds = nextValue
                    self.syncMirror(lastUpdatedAt: Date())
                }

                if nextValue <= 0 {
                    self.isActive = false
                    self.sessionExpectedEndTime = nil
                    self.lastErrorState = .exhausted
                    self.syncMirror(lastUpdatedAt: Date())
                    await self.endLiveActivity()
                    break
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func hydrateFromMirror() {
        guard let data = defaults?.data(forKey: SharedDefaultsKeys.mirroredState),
              let mirrored = try? decoder.decode(MirroredState.self, from: data) else {
            return
        }

        isLoaded = mirrored.isLoaded
        isActive = mirrored.isActive
        remainingSeconds = mirrored.remainingSeconds
        dailyBudgetSeconds = mirrored.dailyBudgetSeconds
        sessionExpectedEndTime = mirrored.sessionExpectedEndTime
        lastKnownTimezoneIdentifier = mirrored.timezoneIdentifier
        updatePresentationTimer()
    }

    private func syncMirror(lastUpdatedAt: Date?) {
        let mirrored = MirroredState(
            isLoaded: isLoaded,
            isActive: isActive,
            remainingSeconds: remainingSeconds,
            dailyBudgetSeconds: dailyBudgetSeconds,
            sessionExpectedEndTime: sessionExpectedEndTime,
            timezoneIdentifier: lastKnownTimezoneIdentifier,
            lastUpdatedAt: lastUpdatedAt
        )

        if let data = try? encoder.encode(mirrored) {
            defaults?.set(data, forKey: SharedDefaultsKeys.mirroredState)
        }
        defaults?.set(isActive, forKey: SharedDefaultsKeys.mirroredIsActive)
        defaults?.set(remainingSeconds, forKey: SharedDefaultsKeys.mirroredRemainingSeconds)

        WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
    }

    private func processPendingAppGroupActionIfNeeded() async {
        guard let rawAction = defaults?.string(forKey: SharedDefaultsKeys.pendingAction) else {
            return
        }

        guard networkMonitor.isConnected else {
            lastErrorState = .offline
            return
        }

        if !isLoaded {
            await perform(.get)
        }

        switch rawAction {
        case "pause":
            await perform(.pause)
        case "resume" where !isActive && remainingSeconds > 0:
            await perform(.resume)
        default:
            break
        }

        defaults?.removeObject(forKey: SharedDefaultsKeys.pendingAction)
        defaults?.removeObject(forKey: SharedDefaultsKeys.pendingActionTimestamp)
    }

    private func currentActivity() -> Activity<IncognitoActivityAttributes>? {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return nil }
        return Activity<IncognitoActivityAttributes>.activities.first(where: { $0.attributes.userId == currentUserId })
    }

    private func syncLiveActivity() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            await endLiveActivity()
            return
        }

        if !isLoaded || remainingSeconds <= 0 || !isActive {
            await endLiveActivity()
            return
        }

        let state = IncognitoActivityAttributes.ContentState(
            remainingSeconds: remainingSeconds,
            isActive: isActive
        )

        if let activity = currentActivity() {
            await activity.update(ActivityContent(state: state, staleDate: nil))
            return
        }

        do {
            _ = try Activity<IncognitoActivityAttributes>.request(
                attributes: IncognitoActivityAttributes(userId: currentUserId),
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            // Best effort only.
        }
    }

    private func endLiveActivity() async {
        let finalState = IncognitoActivityAttributes.ContentState(
            remainingSeconds: max(remainingSeconds, 0),
            isActive: false
        )

        for activity in Activity<IncognitoActivityAttributes>.activities {
            await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}
