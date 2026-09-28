import Foundation
import FirebaseAuth
import FirebaseCore
import SwiftUI

/// Per-account discovery preferences. Only qualified on-screen impressions are remembered.
@MainActor
final class ForYouPreferences: ObservableObject {
    static let shared = ForYouPreferences()
    @Published private(set) var revision = 0
    @Published private(set) var isBusy = false
    @Published private(set) var undoMoment: Moment?
    @Published private(set) var notice: String?
    private var noticeOwner: String?
    private var visibilityTasks: [String: Task<Void, Never>] = [:]
    private var noticeDismissTask: Task<Void, Never>?
    private static let noticeDuration: Duration = .seconds(5)

    private func key(_ suffix: String, owner: String) -> String { "forYou.\(owner).\(suffix)" }
    func momentKey(_ moment: Moment) -> String { "\(moment.authorId)/\(moment.id ?? "")" }

    func hiddenKeys() -> Set<String> {
        _ = revision
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        return Set(UserDefaults.standard.stringArray(forKey: key("hidden", owner: uid)) ?? [])
    }

    var visibleNotice: String? {
        noticeOwner == Auth.auth().currentUser?.uid ? notice : nil
    }

    func seenMoments() -> [String: Double] {
        guard let uid = Auth.auth().currentUser?.uid else { return [:] }
        let cutoff = Date().timeIntervalSince1970 * 1000 - 30 * 86_400_000
        let saved = UserDefaults.standard.dictionary(forKey: key("seen", owner: uid)) as? [String: Double] ?? [:]
        return saved.filter { $0.value > cutoff }
    }

    func updateVisibility(moments: [Moment], fractions: [String: CGFloat], enabled: Bool) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let visible = enabled && !IncognitoModeService.isActiveSnapshot ? moments.filter { (fractions[$0.id ?? ""] ?? 0) >= 0.5 } : []
        let keys = Set(visible.map { momentKey($0) })
        for id in Array(visibilityTasks.keys) where !keys.contains(id) {
            visibilityTasks.removeValue(forKey: id)?.cancel()
        }
        for moment in visible {
            let id = momentKey(moment)
            guard moment.id != nil, visibilityTasks[id] == nil else { continue }
            visibilityTasks[id] = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
                guard let self, Auth.auth().currentUser?.uid == uid, !IncognitoModeService.isActiveSnapshot else { return }
                var seen = self.seenMoments()
                let now = Date().timeIntervalSince1970 * 1000
                if now - (seen[id] ?? 0) > 86_400_000 {
                    AffinityTracker.shared.trackInteraction(type: .momentView, with: moment.authorId)
                }
                seen[id] = now
                let trimmed = Dictionary(uniqueKeysWithValues: seen.sorted { $0.value > $1.value }.prefix(500).map { ($0.key, $0.value) })
                UserDefaults.standard.set(trimmed, forKey: self.key("seen", owner: uid))
            }
        }
    }

    /// Opening a discovery result is an explicit view; incognito stays untracked.
    func recordOpenedMoment(_ moment: Moment) {
        guard let uid = Auth.auth().currentUser?.uid, moment.id != nil,
              !IncognitoModeService.isActiveSnapshot else { return }
        let id = momentKey(moment)
        var seen = seenMoments()
        let now = Date().timeIntervalSince1970 * 1000
        if now - (seen[id] ?? 0) > 86_400_000 {
            AffinityTracker.shared.trackInteraction(type: .momentView, with: moment.authorId)
        }
        seen[id] = now
        let trimmed = Dictionary(uniqueKeysWithValues: seen.sorted { $0.value > $1.value }.prefix(500).map { ($0.key, $0.value) })
        UserDefaults.standard.set(trimmed, forKey: key("seen", owner: uid))
    }

    func clearVisibility() {
        visibilityTasks.values.forEach { $0.cancel() }
        visibilityTasks.removeAll()
    }

    func hide(_ moment: Moment) {
        guard let uid = Auth.auth().currentUser?.uid, let momentId = moment.id else { return }
        let storageKey = key("hidden", owner: uid)
        let original = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        UserDefaults.standard.set(Array(Set(original).union([momentKey(moment)])), forKey: storageKey)
        revision += 1
        undoMoment = moment
        InAppNotificationService.shared.showActionToast(
            InAppActionToast(
                systemImage: "eye.slash.fill",
                prefix: NSLocalizedString("forYou.feedback.hidden", comment: "Post hidden"),
                undo: { [weak self] in self?.undo() },
                onExpire: { [weak self] in self?.commitHiddenMoment(moment, momentId: momentId, owner: uid, original: original) }
            )
        )
    }

    func undo() {
        guard let moment = undoMoment, let uid = Auth.auth().currentUser?.uid else { return }
        let storageKey = key("hidden", owner: uid)
        let restored = (UserDefaults.standard.stringArray(forKey: storageKey) ?? []).filter { $0 != momentKey(moment) }
        UserDefaults.standard.set(restored, forKey: storageKey)
        revision += 1
        undoMoment = nil
    }

    func dismissNotice() {
        guard !isBusy else { return }
        noticeDismissTask?.cancel()
        noticeDismissTask = nil
        notice = nil
        undoMoment = nil
    }

    func clearAccountData(owner: String) {
        noticeDismissTask?.cancel()
        noticeDismissTask = nil
        clearVisibility()
        UserDefaults.standard.removeObject(forKey: key("hidden", owner: owner))
        UserDefaults.standard.removeObject(forKey: key("seen", owner: owner))
        notice = nil
        undoMoment = nil
        noticeOwner = nil
        isBusy = false
        revision += 1
    }

    private func scheduleNoticeDismiss() {
        noticeDismissTask?.cancel()
        noticeDismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.noticeDuration)
            guard !Task.isCancelled else { return }
            self?.dismissNotice()
        }
    }

    private func commitHiddenMoment(_ moment: Moment, momentId: String, owner uid: String, original: [String]) {
        guard !isBusy, let user = Auth.auth().currentUser, user.uid == uid else { return }
        let storageKey = key("hidden", owner: uid)
        isBusy = true
        InAppNotificationService.shared.showActionToast(
            InAppActionToast(
                systemImage: "eye.slash",
                prefix: NSLocalizedString("forYou.feedback.saving", comment: "Saving recommendation preference"),
                holds: true,
                showsProgress: true
            )
        )
        Task {
            do {
                let token = try await user.getIDToken()
                let project = FirebaseApp.app()?.options.projectID ?? ""
                guard let url = URL(string: "https://europe-southwest1-\(project).cloudfunctions.net/getFeedPage") else { throw URLError(.badURL) }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 15
                request.httpBody = try JSONSerialization.data(withJSONObject: ["action": "forYouFeedback",
                    "authorId": moment.authorId, "momentId": momentId, "intent": "hide"])
                let (data, response) = try await URLSession.shared.data(for: request)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard (response as? HTTPURLResponse)?.statusCode == 200, json?["accepted"] as? Bool == true else { throw URLError(.badServerResponse) }
                if Auth.auth().currentUser?.uid == uid {
                    self.undoMoment = nil
                    InAppNotificationService.shared.showActionToast(
                        InAppActionToast(
                            systemImage: "checkmark.circle.fill",
                            prefix: NSLocalizedString("forYou.feedback.saved", comment: "Preference saved"),
                            subtitle: NSLocalizedString("forYou.feedback.subtitle", comment: "Show fewer similar posts")
                        )
                    )
                }
            } catch {
                UserDefaults.standard.set(original, forKey: storageKey)
                revision += 1
                if Auth.auth().currentUser?.uid == uid {
                    InAppNotificationService.shared.showActionToast(
                        InAppActionToast(
                            systemImage: "exclamationmark.triangle.fill",
                            prefix: NSLocalizedString("forYou.feedback.failed", comment: "Recommendation feedback failed")
                        )
                    )
                    undoMoment = nil
                }
            }
            isBusy = false
        }
    }
}

struct ForYouFeedbackNotice: View {
    @ObservedObject private var preferences = ForYouPreferences.shared
    var body: some View {
        if let notice = preferences.visibleNotice {
            HStack(spacing: 12) {
                Text(notice).font(.subheadline)
                Spacer(minLength: 0)
                if preferences.isBusy { ProgressView() }
                if preferences.undoMoment != nil {
                    Button("forYou.feedback.undo") { preferences.undo() }.disabled(preferences.isBusy)
                }
                if !preferences.isBusy {
                    Button(action: preferences.dismissNotice) { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("forYou.feedback.dismiss"))
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
        }
    }
}
