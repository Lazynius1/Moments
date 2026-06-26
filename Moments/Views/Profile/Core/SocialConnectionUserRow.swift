import SwiftUI

// MARK: - Count formatting

enum SocialConnectionCountFormatter {
    static func string(from count: Int) -> String {
        MomentsFormat.count(count, style: .profileStat)
    }
}

// MARK: - Sort

enum SocialConnectionsSortMode: String, CaseIterable, Identifiable {
    case `default`
    case alphabetical
    case newest
    case oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default:
            return NSLocalizedString("socialConnections.sort.default", comment: "")
        case .alphabetical:
            return NSLocalizedString("socialConnections.sort.alphabetical", comment: "")
        case .newest:
            return NSLocalizedString("socialConnections.sort.newest", comment: "")
        case .oldest:
            return NSLocalizedString("socialConnections.sort.oldest", comment: "")
        }
    }
}

enum SocialConnectionsSorting {
    static func sortUsers(
        _ users: [AppUser],
        mode: SocialConnectionsSortMode,
        timestamps: [String: Date] = [:]
    ) -> [AppUser] {
        switch mode {
        case .default:
            return users
        case .alphabetical:
            return users.sorted {
                $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
            }
        case .newest:
            return users.sorted {
                (timestamps[$0.id] ?? .distantPast) > (timestamps[$1.id] ?? .distantPast)
            }
        case .oldest:
            return users.sorted {
                (timestamps[$0.id] ?? .distantFuture) < (timestamps[$1.id] ?? .distantFuture)
            }
        }
    }

    static func sortVisits(_ visits: [GroupedVisit], mode: SocialConnectionsSortMode) -> [GroupedVisit] {
        switch mode {
        case .default, .newest:
            return visits.sorted { $0.lastVisit > $1.lastVisit }
        case .oldest:
            return visits.sorted { $0.lastVisit < $1.lastVisit }
        case .alphabetical:
            return visits.sorted {
                $0.user.username.localizedCaseInsensitiveCompare($1.user.username) == .orderedAscending
            }
        }
    }
}

// MARK: - Tab item

struct SocialConnectionTabItem: Identifiable {
    let tab: SocialConnectionTab
    let count: Int

    var id: String { tab.id }

    var title: String {
        tab.localizedTitle(count: count)
    }
}

extension SocialConnectionTab {
    func localizedTitle(count: Int) -> String {
        let formatted = SocialConnectionCountFormatter.string(from: count)
        let key: String
        switch self {
        case .visits:
            let key = count == 1 ? "visits.visitorCount.single" : "visits.visitorCount.multiple"
            return String(format: NSLocalizedString(key, comment: ""), count)
        case .inCommon:
            key = "socialConnections.tab.inCommon"
        case .followers:
            key = "socialConnections.tab.followers"
        case .following:
            key = "socialConnections.tab.following"
        case .mutuals:
            key = "socialConnections.tab.mutuals"
        }
        return String(format: NSLocalizedString(key, comment: ""), formatted)
    }
}

struct SocialConnectionRowConfiguration {
    let showsRemoveFollower: Bool
    let showsRelationshipButton: Bool
    let showsOverflowMenu: Bool
    let showsFollowBackHint: Bool
    let showsBio: Bool
    let showsNewPosts: Bool
}

// MARK: - List row metrics

enum SocialConnectionRowMetrics {
    static let avatarSize: CGFloat = 56
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 6
    static let contentSpacing: CGFloat = 12
    static let textLineSpacing: CGFloat = 1
}

enum SocialConnectionAvatarTapRouting {
    static func route(
        userId: String,
        hasStory: Bool,
        openProfile: (String) -> Void,
        openStories: (String) -> Void
    ) {
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserId.isEmpty else { return }

        if hasStory {
            openStories(normalizedUserId)
        } else {
            openProfile(normalizedUserId)
        }
    }
}

// MARK: - Unified row

struct SocialConnectionUserRow<ViewModel: UserListViewModel>: View {
    let user: AppUser
    let subtitle: String?
    let viewModel: ViewModel
    let onUserTap: ((AppUser) -> Void)?
    var profileZoomNamespace: Namespace.ID? = nil
    var activeTab: SocialConnectionTab = .followers
    var includesVisits: Bool = false
    var configuration: SocialConnectionRowConfiguration = .init(
        showsRemoveFollower: false,
        showsRelationshipButton: true,
        showsOverflowMenu: false,
        showsFollowBackHint: false,
        showsBio: true,
        showsNewPosts: false
    )
    var newContentCount: Int? = nil
    var onViewSharedActivity: ((AppUser) -> Void)? = nil
    var onRemoveFollower: ((AppUser) -> Void)? = nil
    var onAvatarTap: ((String, Bool) -> Void)? = nil
    var isMutual: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var followState: FollowButtonState = .canFollow
    @State private var isFollowLoading = false
    @State private var showingUnfollowConfirmation = false
    @State private var showingRemoveFollowerConfirmation = false
    @State private var isPressed = false

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55)
    }

    private var followBackHint: String? {
        guard configuration.showsFollowBackHint else { return nil }

        switch followState {
        case .canFollow, .canRequestFollow:
            return NSLocalizedString("socialConnections.followAlso", comment: "")
        default:
            return nil
        }
    }

    private var resolvedNewPostsText: String? {
        guard configuration.showsNewPosts,
              let count = newContentCount,
              count > 0 else { return nil }

        let key = count == 1
            ? "socialConnections.newPosts.single"
            : "socialConnections.newPosts.multiple"
        return String(format: NSLocalizedString(key, comment: ""), count)
    }

    private var resolvedBio: String? {
        guard configuration.showsBio else { return nil }
        if let subtitle, !subtitle.isEmpty { return subtitle }
        if let bio = user.bio, !bio.isEmpty { return bio }
        return nil
    }

    private var secondaryLine: (text: String, isAccent: Bool)? {
        if let followBackHint {
            return (followBackHint, true)
        }
        if let resolvedBio {
            return (resolvedBio, false)
        }
        return nil
    }

    private var supportsRelationshipManagement: Bool {
        configuration.showsRelationshipButton && followState != .ownProfile
    }

    var body: some View {
        HStack(spacing: SocialConnectionRowMetrics.contentSpacing) {
            ZStack(alignment: .topLeading) {
                let avatarView = StoryRingAvatarView(
                    userId: user.id,
                    size: SocialConnectionRowMetrics.avatarSize,
                    lineWidth: 2.2,
                    showBaseStroke: true,
                    baseStrokeColor: colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14),
                    baseStrokeWidth: 0.9,
                    profileZoomNamespace: profileZoomNamespace,
                    onTap: handleAvatarTap
                )

                if isMutual {
                    avatarView
                        .reversedMask(alignment: .topLeading) {
                            Circle()
                                .frame(width: 21, height: 21)
                                .offset(x: -1.5, y: -1.5)
                        }

                    Circle()
                        .fill(Color.clear)
                        .frame(width: 18, height: 18)
                        .momentsChromeGlass(in: Circle(), interactive: false)
                        .overlay {
                            AttachmentIconView(
                                icon: .mutuals,
                                size: 10
                            )
                        }
                        .offset(x: 0, y: 0)
                } else {
                    avatarView
                }
            }

            userInfoSection

            Spacer(minLength: 4)

            trailingActions
        }
        .padding(.horizontal, SocialConnectionRowMetrics.horizontalPadding)
        .padding(.vertical, SocialConnectionRowMetrics.verticalPadding)
        .onAppear {
            refreshFollowState()
            viewModel.prefetchRelationshipState(for: user.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: FollowStateStore.didChangeNotification)) { notification in
            guard let changedUserId = notification.userInfo?["userId"] as? String,
                  changedUserId == user.id else { return }
            refreshFollowState()
        }
        .confirmationDialog(
            NSLocalizedString("userProfile.unfollow.confirm.title", comment: ""),
            isPresented: $showingUnfollowConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.unfollow.confirm.action", comment: ""), role: .destructive) {
                viewModel.unfollowUser(userId: user.id)
                viewModel.prefetchRelationshipState(for: user.id)
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("userProfile.unfollow.confirm.message", comment: ""))
        }
        .confirmationDialog(
            NSLocalizedString("socialConnections.removeFollower.confirm.title", comment: ""),
            isPresented: $showingRemoveFollowerConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("socialConnections.removeFollower", comment: ""), role: .destructive) {
                onRemoveFollower?(user)
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(String(format: NSLocalizedString("socialConnections.removeFollower.confirm.message", comment: ""), user.username))
        }
    }

    private var userInfoSection: some View {
        VStack(alignment: .leading, spacing: SocialConnectionRowMetrics.textLineSpacing) {
            HStack(spacing: 4) {
                Text(user.username)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .layoutPriority(1)

                if user.isVerified {
                    VerifiedBadge(size: 13)
                }
            }

            if let secondaryLine {
                Text(secondaryLine.text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(secondaryLine.isAccent ? Color(hex: "0095F6") : secondaryTextColor)
                    .lineLimit(1)
            }

            if let resolvedNewPostsText {
                HStack(spacing: 6) {
                    Text(resolvedNewPostsText)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)

                    Circle()
                        .fill(Color(hex: "0095F6"))
                        .frame(width: 7, height: 7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (colorScheme == .dark ? Color.white : Color.black)
                .opacity(isPressed ? 0.06 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture { onUserTap?(user) }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }

    private func handleAvatarTap(hasStory: Bool) {
        if let onAvatarTap {
            onAvatarTap(user.id, hasStory)
            return
        }

        if hasStory {
            return
        }

        onUserTap?(user)
    }

    private var trailingActions: some View {
        HStack(spacing: 6) {
            if supportsRelationshipManagement {
                relationshipChip
            }

            if configuration.showsRemoveFollower {
                Button(action: { showingRemoveFollowerConfirmation = true }) {
                    Text(NSLocalizedString("socialConnections.removeFollower", comment: ""))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .overlay(
                            Capsule()
                                .stroke((colorScheme == .dark ? Color.white : Color.black).opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            } else if configuration.showsOverflowMenu {
                Menu {
                    if let onViewSharedActivity {
                        Button(NSLocalizedString("socialConnections.menu.sharedActivity", comment: "")) {
                            onViewSharedActivity(user)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 24, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var relationshipChip: some View {
        ModernFollowButton(
            state: followState,
            isLoading: isFollowLoading,
            colorScheme: colorScheme,
            action: performRelationshipAction
        )
    }

    private func refreshFollowState() {
        followState = viewModel.relationshipState(for: user.id)
    }

    private func performRelationshipAction() {
        guard !isFollowLoading else { return }

        switch followState {
        case .following:
            showingUnfollowConfirmation = true
        case .canFollow, .canRequestFollow:
            performFollow()
        case .requestPendingCancellable:
            viewModel.cancelFollowRequest(userId: user.id)
            FollowStateStore.shared.setState(.canRequestFollow, for: user.id)
            refreshFollowState()
        case .ownProfile, .blocked, .requestPending:
            break
        }
    }

    private func performFollow() {
        isFollowLoading = true
        viewModel.followUser(userId: user.id)
        let nextState: FollowButtonState = followState == .canRequestFollow ? .requestPendingCancellable : .following
        FollowStateStore.shared.setState(nextState, for: user.id)
        followState = nextState
        isFollowLoading = false
    }
}

extension GroupedVisit {
    var socialSubtitle: String {
        rowSubtitle
    }
}
