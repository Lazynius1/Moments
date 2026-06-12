import SwiftUI
import FirebaseAuth

struct GroupedFollowerItem: Identifiable {
    let id: String
    let username: String
}

private struct GroupedFollowerStoryRoute: Identifiable {
    let id: String
}

struct NotificationGroupedFollowersOverlay: View {
    private enum Layout {
        static let rowHeight: CGFloat = 52
        static let rowSpacing: CGFloat = 6
        static let maxVisibleRows = 10
    }

    let group: NotificationGroup
    @ObservedObject var viewModel: NotificationsViewModel
    let colorScheme: ColorScheme
    @Binding var isPresented: Bool

    @State private var followStates: [String: FollowButtonState] = [:]
    @State private var loadingStates: [String: Bool] = [:]
    @State private var profileUserId: String?
    @State private var showProfile = false
    @Namespace private var profileZoomNamespace
    @State private var storyRoute: GroupedFollowerStoryRoute?
    @State private var unfollowTargetId: String?

    private var items: [GroupedFollowerItem] {
        var seen = Set<String>()
        var result: [GroupedFollowerItem] = []

        for notification in group.notifications {
            let id = notification.senderId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }

            let username = notification.senderUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(GroupedFollowerItem(
                id: id,
                username: username.isEmpty ? NSLocalizedString("notifications.groupedFollowers.unknownUser", comment: "Unknown follower username") : username
            ))
        }

        return result
    }

    private var overlayTitle: String {
        switch group.notifications.first?.type {
        case .mutualConnection:
            return NSLocalizedString("notifications.groupedFollowers.title.mutual", comment: "Grouped mutual connections overlay title")
        default:
            return NSLocalizedString("notifications.groupedFollowers.title.followers", comment: "Grouped followers overlay title")
        }
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    /// Crece con el contenido hasta `maxVisibleRows`; a partir de ahí altura fija + scroll.
    private var listAreaHeight: CGFloat {
        let visibleRows = min(items.count, Layout.maxVisibleRows)
        guard visibleRows > 0 else { return 0 }
        return CGFloat(visibleRows) * Layout.rowHeight
            + CGFloat(visibleRows - 1) * Layout.rowSpacing
    }

    private var listNeedsScroll: Bool {
        items.count > Layout.maxVisibleRows
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissOverlay() }

            dialogCard
                .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
        .zIndex(5000)
        .onAppear(perform: loadFollowStates)
        .onReceive(NotificationCenter.default.publisher(for: FollowStateStore.didChangeNotification)) { notification in
            guard let userId = notification.userInfo?["userId"] as? String,
                  let state = notification.userInfo?["state"] as? FollowButtonState else { return }
            followStates[userId] = state
        }
        .fullScreenCover(isPresented: $showProfile) {
            if let profileUserId, !profileUserId.isEmpty {
                UserProfileView(userId: profileUserId)
                    .userProfileZoomDestination(userId: profileUserId, namespace: profileZoomNamespace)
            }
        }
        .fullScreenCover(item: $storyRoute) { route in
            StoriesView(startWithUserId: .constant(route.id))
                .ignoresSafeArea(.keyboard)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseStoryViewer"))) { _ in
            storyRoute = nil
        }
        .confirmationDialog(
            NSLocalizedString("userProfile.unfollow.confirm.title", comment: ""),
            isPresented: Binding(
                get: { unfollowTargetId != nil },
                set: { if !$0 { unfollowTargetId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.unfollow.confirm.action", comment: ""), role: .destructive) {
                if let userId = unfollowTargetId {
                    performFollowToggle(for: userId)
                }
                unfollowTargetId = nil
            }

            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                unfollowTargetId = nil
            }
        } message: {
            Text(NSLocalizedString("userProfile.unfollow.confirm.message", comment: ""))
        }
    }

    private var dialogCard: some View {
        VStack(spacing: 0) {
            Text(overlayTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(primaryTextColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: Layout.rowSpacing) {
                    ForEach(items) { item in
                        followerRow(item)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(listNeedsScroll ? .visible : .hidden)
            .frame(maxWidth: .infinity)
            .frame(height: listAreaHeight)

            MomentRowButton(action: dismissOverlay) {
                Text(NSLocalizedString("common.close", comment: "Close"))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(primaryTextColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxWidth: 320)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 24, x: 0, y: 12)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func followerRow(_ item: GroupedFollowerItem) -> some View {
        let state = followStates[item.id] ?? .canFollow
        let isLoading = loadingStates[item.id] ?? false

        HStack(spacing: 10) {
            StoryRingAvatarView(
                userId: item.id,
                size: 44,
                lineWidth: 2.2,
                showBaseStroke: true,
                baseStrokeColor: colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14),
                baseStrokeWidth: 0.9,
                profileZoomNamespace: profileZoomNamespace
            ) { hasStory in
                if hasStory {
                    storyRoute = GroupedFollowerStoryRoute(id: item.id)
                } else {
                    profileUserId = item.id
                    showProfile = true
                }
            }

            Button {
                profileUserId = item.id
                showProfile = true
            } label: {
                HStack(spacing: 4) {
                    Text(item.username)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)

                    VerifiedBadgeView(userId: item.id, size: 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            followButton(for: item.id, state: state, isLoading: isLoading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.rowHeight)
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func followButton(for userId: String, state: FollowButtonState, isLoading: Bool) -> some View {
        Button {
            if state == .following {
                unfollowTargetId = userId
            } else {
                performFollowToggle(for: userId)
            }
        } label: {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.75)
            } else {
                Text(compactFollowTitle(for: state))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .liquidGlass(in: Capsule(), interactive: state.isActionable)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading || !state.isActionable)
        .opacity(isPassiveFollowState(state) ? 0.78 : 1)
    }

    private func dismissOverlay() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            isPresented = false
        }
    }

    private func loadFollowStates() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        for item in items {
            if let cached = FollowStateStore.shared.state(for: item.id) {
                followStates[item.id] = cached
            }

            PrivacyService().getFollowButtonState(viewerId: currentUserId, targetUserId: item.id) { state in
                DispatchQueue.main.async {
                    let reconciled = FollowStateStore.shared.reconciledState(state, for: item.id)
                    followStates[item.id] = reconciled
                    FollowStateStore.shared.setState(reconciled, for: item.id)
                }
            }
        }
    }

    private func performFollowToggle(for userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        let currentState = followStates[userId] ?? .canFollow
        loadingStates[userId] = true

        if currentState == .following {
            viewModel.unfollowUser(currentUserId: currentUserId, targetUserId: userId) { error in
                DispatchQueue.main.async {
                    loadingStates[userId] = false
                    if error == nil {
                        followStates[userId] = .canFollow
                        FollowStateStore.shared.setState(.canFollow, for: userId)
                    }
                }
            }
        } else if currentState == .requestPendingCancellable {
            viewModel.cancelFollowRequest(currentUserId: currentUserId, targetUserId: userId) { error in
                DispatchQueue.main.async {
                    loadingStates[userId] = false
                    if error == nil {
                        followStates[userId] = .canRequestFollow
                        FollowStateStore.shared.setState(.canRequestFollow, for: userId)
                    }
                }
            }
        } else {
            viewModel.followUser(currentUserId: currentUserId, targetUserId: userId) { error in
                DispatchQueue.main.async {
                    loadingStates[userId] = false
                    if error == nil {
                        let newState: FollowButtonState = currentState == .canRequestFollow ? .requestPendingCancellable : .following
                        followStates[userId] = newState
                        FollowStateStore.shared.setState(newState, for: userId)
                    }
                }
            }
        }
    }

    private func compactFollowTitle(for state: FollowButtonState) -> String {
        switch state {
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

    private func isPassiveFollowState(_ state: FollowButtonState) -> Bool {
        if case .requestPending = state { return true }
        return false
    }
}
