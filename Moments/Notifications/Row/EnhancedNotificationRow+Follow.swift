import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher

extension EnhancedNotificationRow {
    func senderDisplayName(for notification: Notification) -> String {
        if let senderUsernameOverride, !senderUsernameOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return senderUsernameOverride
        }
        let username = notification.senderUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        if username.isEmpty {
            return "Alguien"
        }
        return username
    }

    func resolveSenderDisplayData() {
        guard let senderId = group.notifications.first?.senderId, !senderId.isEmpty else { return }
        let needsUsernameResolution: Bool = {
            guard let current = group.notifications.first?.senderUsername else { return true }
            let normalized = current.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty || normalized == "alguien"
        }()
        if !needsUsernameResolution { return }

        let firestoreService = FirestoreService()
        firestoreService.fetchUser(userId: senderId) { result in
            switch result {
            case .success(let user):
                DispatchQueue.main.async {
                    if !user.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.senderUsernameOverride = user.username
                    }
                }
            case .failure:
                break
            }
        }
    }

    func fetchMomentPreview(momentId: String, authorId: String? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let ownerId = authorId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let firestoreService = FirestoreService()
        isLoadingMomentImage = true
        firestoreService.fetchMoment(momentId: momentId, userId: ownerId?.isEmpty == false ? ownerId! : userId) { result in
            switch result {
            case .success(let fetchedMoment):
                DispatchQueue.main.async {
                    if let previewPath = fetchedMoment.previewImageURLString, !previewPath.isEmpty {
                        self.loadMomentImage(from: previewPath)
                    } else {
                        self.isLoadingMomentImage = false
                        self.momentImageLoadFailed = true
                    }
                }
            case .failure(_):
                DispatchQueue.main.async {
                    self.isLoadingMomentImage = false
                    self.momentImageLoadFailed = true
                }
            }
        }
    }

    func loadMomentImage(from path: String) {
        isLoadingMomentImage = true
        guard let url = URL(string: path) else {
            DispatchQueue.main.async {
                self.isLoadingMomentImage = false
                self.momentImageLoadFailed = true
            }
            return
        }

        ImageDownloader.default.downloadImage(with: url) { result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    self.momentImagePath = path
                    self.isLoadingMomentImage = false
                    self.momentImageLoadFailed = false
                }
            case .failure(_):
                DispatchQueue.main.async {
                    self.isLoadingMomentImage = false
                    self.momentImageLoadFailed = true
                }
            }
        }
    }

    func checkFollowingStatus() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let targetUserId = group.notifications.first?.senderId else { return }

        if let cachedState = FollowStateStore.shared.state(for: targetUserId) {
            followButtonState = cachedState
        }
        
        PrivacyService().getFollowButtonState(viewerId: currentUserId, targetUserId: targetUserId) { state in
            DispatchQueue.main.async {
                let reconciledState = FollowStateStore.shared.reconciledState(state, for: targetUserId)
                self.followButtonState = reconciledState
                FollowStateStore.shared.setState(reconciledState, for: targetUserId)
            }
        }
    }

    func toggleFollow() {
        if followButtonState == .following {
            showingUnfollowConfirmation = true
            return
        }

        performFollowToggle()
    }

    func performFollowToggle() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let targetUserId = group.notifications.first?.senderId else { return }
        
        if followButtonState == .following {
            viewModel.unfollowUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
                if error == nil {
                    DispatchQueue.main.async {
                        self.followButtonState = .canFollow
                        FollowStateStore.shared.setState(.canFollow, for: targetUserId)
                    }
                }
            }
        } else if followButtonState == .requestPendingCancellable {
            viewModel.cancelFollowRequest(currentUserId: currentUserId, targetUserId: targetUserId) { error in
                if error == nil {
                    DispatchQueue.main.async {
                        self.followButtonState = .canRequestFollow
                        FollowStateStore.shared.setState(.canRequestFollow, for: targetUserId)
                    }
                }
            }
        } else {
            viewModel.followUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
                if error == nil {
                    DispatchQueue.main.async {
                        let newState: FollowButtonState = self.followButtonState == .canRequestFollow ? .requestPendingCancellable : .following
                        self.followButtonState = newState
                        FollowStateStore.shared.setState(newState, for: targetUserId)
                    }
                }
            }
        }
    }

    var notificationFollowTitle: String {
        switch followButtonState {
        case .following:
            return NSLocalizedString("userProfile.followButton.following", comment: "")
        case .canRequestFollow:
            return NSLocalizedString("feed.follow.request", comment: "")
        case .requestPending:
            return NSLocalizedString("feed.follow.requested", comment: "")
        case .requestPendingCancellable:
            return NSLocalizedString("feed.follow.cancelRequest", comment: "")
        case .blocked:
            return NSLocalizedString("userProfile.followButton.blocked", comment: "")
        default:
            return NSLocalizedString("userProfile.followButton.canFollow", comment: "")
        }
    }

    var notificationFollowIcon: String {
        switch followButtonState {
        case .following:
            return "person.fill.checkmark"
        case .canRequestFollow:
            return "person.crop.circle.badge.plus"
        case .requestPending:
            return "clock"
        case .requestPendingCancellable:
            return "xmark.circle"
        case .blocked:
            return "slash.circle"
        default:
            return "person.badge.plus"
        }
    }

    var notificationFollowIsPassive: Bool {
        if case .requestPending = followButtonState {
            return true
        }
        return false
    }
}
