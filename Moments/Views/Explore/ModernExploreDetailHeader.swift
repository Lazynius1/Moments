import SwiftUI
import FirebaseAuth
import CoreLocation

/// Header del detalle Explore: glass capsule con back, autor, ubicación y seguir.
struct ModernExploreDetailHeader: View {
    let moment: Moment?
    let topInset: CGFloat
    let onDismiss: () -> Void
    let onAvatarTap: (String, Bool) -> Void
    let onLocationTap: ((String, CLLocationCoordinate2D?) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var firestoreService = FirestoreService.shared
    @State private var liveUsername: String = ""
    @State private var followButtonState: FollowButtonState = .canFollow
    @State private var isFollowLoading = false
    @State private var showingUnfollowConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInset)

            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        onDismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 38, height: 38)
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())

                if let moment {
                    let authorId = moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines)

                    HStack(spacing: 10) {
                        StoryRingAvatarView(
                            userId: authorId,
                            size: 38,
                            lineWidth: 2.2,
                            showBaseStroke: true,
                            baseStrokeColor: .white.opacity(0.15),
                            baseStrokeWidth: 0.5,
                            onTap: { hasStory in
                                guard !authorId.isEmpty else { return }
                                onAvatarTap(authorId, hasStory)
                            }
                        )

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(displayUsername(for: moment))
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                VerifiedBadgeView(userId: authorId, size: 13)
                            }

                            if let location = moment.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !location.isEmpty,
                               let onLocationTap {
                                Button {
                                    onLocationTap(location, moment.locationCoordinate?.toCLLocationCoordinate2D)
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "location.fill")
                                            .font(.system(size: 9, weight: .semibold))
                                        Text(location)
                                            .font(.custom("Poppins-Regular", size: 10))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(.secondary.opacity(0.85))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(moment.timestamp.timeAgoDisplay())
                                    .font(.custom("Poppins-Regular", size: 10))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }
                    }
                }

                Spacer(minLength: 8)

                if let moment,
                   moment.authorId != Auth.auth().currentUser?.uid {
                    ModernFollowButton(
                        state: followButtonState,
                        isLoading: isFollowLoading,
                        colorScheme: colorScheme,
                        action: toggleFollow
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .liquidGlass(in: Capsule(), interactive: false)
            .padding(.horizontal, 14)
        }
        .onAppear {
            resolveAuthorUsername()
            refreshFollowState()
        }
        .onChange(of: moment?.authorId) { _, _ in
            resolveAuthorUsername()
            refreshFollowState()
        }
        .confirmationDialog(
            NSLocalizedString("userProfile.unfollow.confirm.title", comment: ""),
            isPresented: $showingUnfollowConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.unfollow.confirm.action", comment: ""), role: .destructive) {
                performFollowToggle()
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("userProfile.unfollow.confirm.message", comment: ""))
        }
    }

    private func displayUsername(for moment: Moment) -> String {
        let fresh = liveUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return fresh.isEmpty ? moment.username : fresh
    }

    private func resolveAuthorUsername() {
        guard let moment else { return }
        let authorId = moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authorId.isEmpty else {
            liveUsername = ""
            return
        }

        UserCacheService.shared.refreshUser(userId: authorId) { user in
            let fetchedUsername = user?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                let currentAuthorId = self.moment?.authorId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard currentAuthorId == authorId else { return }
                self.liveUsername = fetchedUsername
            }
        }
    }

    private func refreshFollowState() {
        guard let moment,
              let currentUserId = Auth.auth().currentUser?.uid,
              moment.authorId != currentUserId else {
            followButtonState = .canFollow
            return
        }

        if let cached = FollowStateStore.shared.state(for: moment.authorId) {
            followButtonState = cached
        }

        PrivacyService().getFollowButtonState(viewerId: currentUserId, targetUserId: moment.authorId) { state in
            DispatchQueue.main.async {
                guard self.moment?.authorId == moment.authorId else { return }
                self.followButtonState = state
                FollowStateStore.shared.setState(state, for: moment.authorId)
            }
        }
    }

    private func toggleFollow() {
        if followButtonState == .following {
            showingUnfollowConfirmation = true
            return
        }
        performFollowToggle()
    }

    private func performFollowToggle() {
        guard let moment,
              let currentUserId = Auth.auth().currentUser?.uid else { return }
        guard followButtonState.isActionable else { return }

        let previousState = followButtonState
        let optimisticState: FollowButtonState = {
            switch previousState {
            case .following: return .canFollow
            case .canRequestFollow: return .requestPendingCancellable
            case .requestPendingCancellable: return .canRequestFollow
            case .canFollow: return .following
            default: return previousState
            }
        }()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            followButtonState = optimisticState
        }
        FollowStateStore.shared.setState(optimisticState, for: moment.authorId)
        isFollowLoading = true

        if previousState == .following {
            firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: moment.authorId) { error in
                DispatchQueue.main.async {
                    isFollowLoading = false
                    if error != nil {
                        followButtonState = previousState
                        FollowStateStore.shared.setState(previousState, for: moment.authorId)
                    }
                }
            }
        } else if previousState == .requestPendingCancellable {
            firestoreService.cancelFollowRequest(currentUserId: currentUserId, targetUserId: moment.authorId) { error in
                DispatchQueue.main.async {
                    isFollowLoading = false
                    if error != nil {
                        followButtonState = previousState
                        FollowStateStore.shared.setState(previousState, for: moment.authorId)
                    }
                }
            }
        } else {
            firestoreService.followUser(currentUserId: currentUserId, targetUserId: moment.authorId) { error in
                DispatchQueue.main.async {
                    isFollowLoading = false
                    if error != nil {
                        followButtonState = previousState
                        FollowStateStore.shared.setState(previousState, for: moment.authorId)
                    }
                }
            }
        }
    }
}
