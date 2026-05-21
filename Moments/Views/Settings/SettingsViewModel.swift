import Foundation
import Combine
import FirebaseAuth

// MARK: - ViewModels y extensiones
class SettingsViewModel: ObservableObject {
    @Published var notificationPreferences: [String: Bool] = [:]
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    func fetchUserSettings(completion: @escaping (Result<AppUser, Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(
                domain: "",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("settings.error.notAuthenticated", comment: "Settings user not authenticated")]
            )))
            return
        }

        firestoreService.fetchUser(userId: userId) { result in
            switch result {
            case .success(let user):
                let defaultPreferences: [String: Bool] = [
                    NotificationType.like.rawValue: true,
                    NotificationType.newFollower.rawValue: true,
                    NotificationType.followRequest.rawValue: true,
                    NotificationType.mutualConnection.rawValue: true,
                    NotificationType.profileVisit.rawValue: true,
                    NotificationType.comment.rawValue: true,
                    NotificationType.storyReaction.rawValue: true,
                    "gentleReminders": true,
                    "commentsMutualsOnly": false,
                    "muteOldPostReactions": false
                ]
                self.notificationPreferences = defaultPreferences.merging(user.notificationPreferences ?? [:]) { _, persisted in persisted }
                completion(.success(user))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    func updatePrivacySettings(isPrivate: Bool? = nil, showMutualConnections: Bool? = nil, showFollowing: Bool? = nil, showAdmirers: Bool? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        privacyService.updatePrivacySettings(
            userId: userId,
            isPrivate: isPrivate,
            showMutualConnections: showMutualConnections,
            showFollowing: showFollowing,
            showAdmirers: showAdmirers
        ) { error in
            if let error = error {
            }
        }
    }

    func updateReadReceiptsPrivacy(enabled: Bool) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        firestoreService.db.collection("users").document(userId).updateData([
            "showReadReceipts": enabled
        ]) { error in
            if let error = error {
            }
        }
    }

    func updateActiveHours(startTime: Date, endTime: Date, completion: ((Error?) -> Void)? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let startHour = dateFormatter.string(from: startTime)
        let endHour = dateFormatter.string(from: endTime)
        firestoreService.updateActiveHours(userId: userId, startHour: startHour, endHour: endHour) { error in
            if let error = error {
            }
            completion?(error)
        }
    }

    func clearActiveHours() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        firestoreService.clearActiveHours(userId: userId) { error in
            if let error = error {
                // Handle error
            }
        }
    }

    func updateNotificationPreference(type: String, isEnabled: Bool) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        notificationPreferences[type] = isEnabled
        firestoreService.updateNotificationPreferences(userId: userId, preferences: notificationPreferences) { error in
            if let error = error {
            }
        }
    }
}

extension NotificationType {
    static var allCases: [NotificationType] {
        [.like, .newFollower, .followRequest, .mutualConnection, .profileVisit, .comment]
    }
}
