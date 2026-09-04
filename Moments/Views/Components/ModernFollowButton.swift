import SwiftUI
import FirebaseAuth

struct ModernFollowButton: View {
    enum Style {
        case standard
        case compact
        case profileHeader
    }

    enum DestructiveConfirmationMode {
        case all
        case cancelRequestOnly
        case none
    }

    let state: FollowButtonState
    let isLoading: Bool
    let colorScheme: ColorScheme
    var targetUserId: String? = nil
    var style: Style = .standard
    var destructiveConfirmation: DestructiveConfirmationMode = .all
    let action: () -> Void

    @State private var showingUnfollowConfirmation = false
    @State private var showingCancelRequestConfirmation = false
    @State private var resolvedState: FollowButtonState?
    @State private var relationshipRetryCount = 0

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var isCompact: Bool { style == .compact }
    private var isProfileHeader: Bool { style == .profileHeader }
    private var showsLeadIcon: Bool { !isProfileHeader }
    private var displayedState: FollowButtonState? {
        guard targetUserId != nil else { return state }
        if let resolvedState { return resolvedState }
        return state == .canFollow ? nil : state
    }
    private var renderState: FollowButtonState { displayedState ?? state }
    private var hasResolvedRelationship: Bool { targetUserId == nil || displayedState != nil }
    private var showsFollowingChevron: Bool { isProfileHeader && renderState.isFollowingOrMutual }
    private var relationshipTaskId: String {
        "\(Auth.auth().currentUser?.uid ?? "")|\(targetUserId ?? "")"
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .standard: return 16
        case .compact: return 10
        case .profileHeader: return 18
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .standard: return 8
        case .compact: return 6
        case .profileHeader: return 10
        }
    }

    private var contentSpacing: CGFloat {
        switch style {
        case .standard: return 6
        case .compact: return 4
        case .profileHeader: return 7
        }
    }

    private var titleFontSize: CGFloat {
        switch style {
        case .standard: return legacyPoppinsSize(14)
        case .compact: return legacyPoppinsSize(11)
        case .profileHeader: return legacyPoppinsSize(13)
        }
    }

    private var iconFontSize: CGFloat {
        switch style {
        case .standard: return 14
        case .compact: return 11
        case .profileHeader: return 13
        }
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: contentSpacing) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                        .tint(adaptiveColors.primary)
                } else if renderState == .mutuals {
                    AudienceIconView(
                        audience: .mutuals,
                        size: isCompact ? 11 : 13,
                        tintColor: adaptiveColors.primary
                    )
                } else if showsLeadIcon {
                    Image(systemName: iconName)
                        .font(.system(size: iconFontSize, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(isCompact ? 0.82 : 0.85)
                    .allowsTightening(isCompact || isProfileHeader)

                if showsFollowingChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(adaptiveColors.primary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .momentsChromeGlass(in: Capsule(), interactive: renderState.isActionable)
        }
        .disabled(isLoading || !renderState.isActionable || !hasResolvedRelationship)
        .opacity(hasResolvedRelationship ? (renderState == .requestPending ? 0.78 : 1) : 0)
        .accessibilityHidden(!hasResolvedRelationship)
        .task(id: relationshipTaskId) {
            relationshipRetryCount = 0
            resolveRelationship()
        }
        .onReceive(NotificationCenter.default.publisher(for: FollowStateStore.didChangeNotification)) { notification in
            guard let targetUserId,
                  let changedUserId = notification.userInfo?["userId"] as? String,
                  changedUserId == targetUserId,
                  let changedState = notification.userInfo?["state"] as? FollowButtonState else { return }
            if let changedViewerId = notification.userInfo?["viewerId"] as? String,
               changedViewerId != Auth.auth().currentUser?.uid {
                return
            }
            resolvedState = changedState
            relationshipRetryCount = 0
        }
        .confirmationDialog(
            NSLocalizedString("userProfile.unfollow.confirm.title", comment: ""),
            isPresented: $showingUnfollowConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.unfollow.confirm.action", comment: ""), role: .destructive) {
                action()
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("userProfile.unfollow.confirm.message", comment: ""))
        }
        .confirmationDialog(
            NSLocalizedString("userProfile.cancelRequest.confirm.title", comment: ""),
            isPresented: $showingCancelRequestConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.cancelRequest.confirm.action", comment: ""), role: .destructive) {
                action()
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("userProfile.cancelRequest.confirm.message", comment: ""))
        }
    }

    private func handleTap() {
        HapticManager.shared.mediumImpact()
        guard hasResolvedRelationship else { return }

        switch renderState {
        case .following where destructiveConfirmation == .all,
             .mutuals where destructiveConfirmation == .all:
            showingUnfollowConfirmation = true
        case .requestPendingCancellable where destructiveConfirmation != .none:
            showingCancelRequestConfirmation = true
        default:
            action()
        }
    }

    private var title: String {
        switch renderState {
        case .ownProfile:
            return NSLocalizedString("userProfile.followButton.ownProfile", comment: "")
        case .mutuals:
            return NSLocalizedString("audience.type.mutuals", comment: "")
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

    private var iconName: String {
        switch renderState {
        case .ownProfile: return "person.circle"
        case .following, .mutuals: return "person.fill.checkmark"
        case .canRequestFollow: return "person.crop.circle.badge.plus"
        case .requestPending: return "clock"
        case .requestPendingCancellable: return "xmark.circle"
        case .blocked: return "slash.circle"
        default: return "person.badge.plus"
        }
    }

    private func resolveRelationship() {
        guard let targetUserId,
              let viewerId = Auth.auth().currentUser?.uid else {
            resolvedState = nil
            return
        }
        guard viewerId != targetUserId else {
            resolvedState = .ownProfile
            return
        }

        if let cachedState = FollowStateStore.shared.state(
            viewerId: viewerId,
            targetUserId: targetUserId
        ) {
            resolvedState = cachedState
        } else if state != .canFollow {
            resolvedState = state
        } else {
            resolvedState = nil
        }

        FollowStateStore.shared.resolve(viewerId: viewerId, targetUserId: targetUserId) { resolved in
            DispatchQueue.main.async {
                guard Auth.auth().currentUser?.uid == viewerId,
                      self.targetUserId == targetUserId else { return }
                if let resolved {
                    self.resolvedState = resolved
                    self.relationshipRetryCount = 0
                } else if self.relationshipRetryCount < 2 {
                    self.relationshipRetryCount += 1
                    let retryTaskId = self.relationshipTaskId
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(self.relationshipRetryCount)) {
                        guard self.relationshipTaskId == retryTaskId else { return }
                        self.resolveRelationship()
                    }
                }
            }
        }
    }
}
