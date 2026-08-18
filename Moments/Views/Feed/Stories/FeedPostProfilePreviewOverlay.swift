import SwiftUI
import FirebaseAuth
import Kingfisher

struct FeedPostProfilePreviewSelection: Equatable {
    let userId: String
    let momentId: String
    let anchorFrame: CGRect
}

struct FeedPostProfilePreviewOverlay: View {
    @Binding var selection: FeedPostProfilePreviewSelection?

    let colorScheme: ColorScheme
    let messagingViewModel: MessagingViewModel
    let onOpenProfile: (String) -> Void
    /// `false` al empezar a cerrar, para devolver el post al feed como el put-back del chat.
    var onPresentedChange: (Bool) -> Void = { _ in }

    private let cardCornerRadius: CGFloat = 26
    private let horizontalInset: CGFloat = 16
    private let avatarGap: CGFloat = 10
    private let cardPadding: CGFloat = 16
    private let gridSpacing: CGFloat = 3
    private let previewAvatarSize: CGFloat = 56
    private let avatarColumnWidth: CGFloat = 80

    @State private var isPresented = false
    @State private var dismissGeneration = 0
    @State private var showUnfollowConfirmation = false
    @State private var unfollowViewModel: UserProfileViewModel?

    @Environment(\.displayScale) private var displayScale

    private var canvasColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }

    private var presentationAnimation: Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.42, dampingFraction: 0.84)
    }

    private var dismissalAnimation: Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.26)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let selection {
                    let layout = previewLayout(for: selection, in: proxy)
                    let cardCenter = isPresented ? layout.targetCenter : layout.naturalCenter

                    Color.black.opacity(isPresented ? 0.28 : 0)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { dismissOverlay() }
                        .accessibilityHidden(true)

                    FeedPostProfilePreviewCard(
                        userId: selection.userId,
                        cardWidth: layout.cardWidth,
                        contentWidth: layout.contentWidth,
                        gridCellSize: layout.gridCellSize,
                        cardPadding: cardPadding,
                        gridSpacing: gridSpacing,
                        previewAvatarSize: previewAvatarSize,
                        avatarColumnWidth: avatarColumnWidth,
                        displayScale: displayScale,
                        colorScheme: colorScheme,
                        canvasColor: canvasColor,
                        cardShape: cardShape,
                        onOpenProfile: {
                            dismissOverlay { onOpenProfile(selection.userId) }
                        },
                        onMessage: { user, viewModel in
                            openMessage(with: user, profileViewModel: viewModel)
                        },
                        onFollow: { viewModel in
                            handleFollowAction(viewModel: viewModel, userId: selection.userId)
                        }
                    )
                    .frame(width: layout.cardWidth)
                    .scaleEffect(isPresented ? 1 : 0.92, anchor: .center)
                    .opacity(isPresented ? 1 : 0)
                    .position(x: cardCenter.x, y: cardCenter.y)
                    .shadow(
                        color: .black.opacity(isPresented ? 0.28 : 0),
                        radius: isPresented ? 28 : 0,
                        x: 0,
                        y: isPresented ? 14 : 0
                    )

                    if showUnfollowConfirmation {
                        GlassmorphicStoryConfirmationDialog(
                            title: NSLocalizedString("userProfile.unfollow.confirm.title", comment: ""),
                            message: NSLocalizedString("userProfile.unfollow.confirm.message", comment: ""),
                            confirmTitle: NSLocalizedString("userProfile.unfollow.confirm.action", comment: ""),
                            cancelTitle: NSLocalizedString("common.cancel", comment: ""),
                            isDestructive: true,
                            onConfirm: {
                                showUnfollowConfirmation = false
                                unfollowViewModel?.unfollowUser(userId: selection.userId)
                                unfollowViewModel = nil
                            },
                            onCancel: {
                                showUnfollowConfirmation = false
                                unfollowViewModel = nil
                            }
                        )
                        .zIndex(20)
                    }
                }
            }
            .onChange(of: selection?.userId) { _, userId in
                guard userId != nil else {
                    GlobalVideoManager.shared.endPlaybackHold()
                    onPresentedChange(false)
                    isPresented = false
                    showUnfollowConfirmation = false
                    unfollowViewModel = nil
                    return
                }
                GlobalVideoManager.shared.beginPlaybackHold()
                dismissGeneration += 1
                isPresented = false
                showUnfollowConfirmation = false
                unfollowViewModel = nil
                DispatchQueue.main.async {
                    withAnimation(presentationAnimation) {
                        isPresented = true
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(selection != nil)
        .accessibilityHidden(selection == nil)
    }

    private func previewLayout(
        for selection: FeedPostProfilePreviewSelection,
        in proxy: GeometryProxy
    ) -> (
        cardWidth: CGFloat,
        contentWidth: CGFloat,
        gridCellSize: CGFloat,
        naturalCenter: CGPoint,
        targetCenter: CGPoint
    ) {
        let overlayGlobal = proxy.frame(in: .global)
        let anchor = CGRect(
            x: selection.anchorFrame.minX - overlayGlobal.minX,
            y: selection.anchorFrame.minY - overlayGlobal.minY,
            width: selection.anchorFrame.width,
            height: selection.anchorFrame.height
        )

        let cardWidth = max(300, proxy.size.width - horizontalInset * 2)
        let contentWidth = cardWidth - cardPadding * 2
        // Como IG (2 filas), pero 4 thumbs por fila → 4+4, máximo 8.
        let gridColumns: CGFloat = 4
        let maxGridRows: CGFloat = 2
        let gridCellSize = (contentWidth - gridSpacing * (gridColumns - 1)) / gridColumns
        let gridHeight = gridCellSize * maxGridRows + gridSpacing * (maxGridRows - 1)

        let isOwnProfile = selection.userId == Auth.auth().currentUser?.uid
        let footerHeight: CGFloat = isOwnProfile ? 0 : 44

        // header ~88 + grid 4x2 + stats ~48 + footer opcional + padding
        let cardHeight = cardPadding * 2 + 88 + gridHeight + 48 + footerHeight + 20

        let minCenterX = horizontalInset + cardWidth / 2
        let maxCenterX = max(minCenterX, proxy.size.width - horizontalInset - cardWidth / 2)
        let naturalCenterX = min(max(anchor.midX, minCenterX), maxCenterX)
        let naturalCenterY = anchor.maxY + avatarGap + cardHeight / 2

        let safeMidY = proxy.safeAreaInsets.top
            + (proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom) / 2
        let minCenterY = proxy.safeAreaInsets.top + cardHeight / 2 + 12
        let maxCenterY = proxy.size.height - proxy.safeAreaInsets.bottom - cardHeight / 2 - 12
        let targetCenterY = min(max(safeMidY, minCenterY), maxCenterY)
        let targetCenterX = proxy.size.width / 2

        return (
            cardWidth,
            contentWidth,
            gridCellSize,
            CGPoint(x: naturalCenterX, y: naturalCenterY),
            CGPoint(x: targetCenterX, y: targetCenterY)
        )
    }

    private func handleFollowAction(viewModel: UserProfileViewModel, userId: String) {
        switch viewModel.followButtonState {
        case .following:
            unfollowViewModel = viewModel
            showUnfollowConfirmation = true
        case .canFollow, .canRequestFollow:
            viewModel.followUser(userId: userId)
        case .requestPendingCancellable:
            viewModel.cancelFollowRequest(userId: userId)
        default:
            break
        }
    }

    private func openMessage(with user: AppUser, profileViewModel: UserProfileViewModel) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        dismissOverlay {
            messagingViewModel.startConversation(with: user, from: currentUserId) { conversation in
                Task { @MainActor in
                    if let conversation, let conversationId = conversation.id, !conversationId.isEmpty {
                        LegacyNavigationBridge.conversation(id: conversationId)
                        return
                    }

                    if let conversation {
                        messagingViewModel.presentationRoute = .conversation(conversation)
                        LegacyNavigationBridge.showMessages()
                        return
                    }

                    guard messagingViewModel.requiresMessageRequest else { return }

                    let context = await PendingChatContextFactory.outgoing(
                        to: user,
                        from: currentUserId,
                        followersCountOverride: profileViewModel.followers.count,
                        momentsCountOverride: profileViewModel.moments.count
                    )
                    messagingViewModel.presentationRoute = .pendingChat(context)
                    LegacyNavigationBridge.showMessages()
                }
            }
        }
    }

    private func dismissOverlay(then action: (() -> Void)? = nil) {
        dismissGeneration += 1
        let generation = dismissGeneration
        showUnfollowConfirmation = false
        unfollowViewModel = nil
        onPresentedChange(false)
        withAnimation(dismissalAnimation) {
            isPresented = false
        }

        let delay = UIAccessibility.isReduceMotionEnabled ? 0 : 0.26
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard generation == dismissGeneration else { return }
            selection = nil
            action?()
        }
    }
}

// MARK: - Card

private struct FeedPostProfilePreviewCard: View {
    let userId: String
    let cardWidth: CGFloat
    let contentWidth: CGFloat
    let gridCellSize: CGFloat
    let cardPadding: CGFloat
    let gridSpacing: CGFloat
    let previewAvatarSize: CGFloat
    let avatarColumnWidth: CGFloat
    let displayScale: CGFloat
    let colorScheme: ColorScheme
    let canvasColor: Color
    let cardShape: RoundedRectangle
    let onOpenProfile: () -> Void
    let onMessage: (AppUser, UserProfileViewModel) -> Void
    let onFollow: (UserProfileViewModel) -> Void

    @StateObject private var viewModel: UserProfileViewModel

    init(
        userId: String,
        cardWidth: CGFloat,
        contentWidth: CGFloat,
        gridCellSize: CGFloat,
        cardPadding: CGFloat,
        gridSpacing: CGFloat,
        previewAvatarSize: CGFloat,
        avatarColumnWidth: CGFloat,
        displayScale: CGFloat,
        colorScheme: ColorScheme,
        canvasColor: Color,
        cardShape: RoundedRectangle,
        onOpenProfile: @escaping () -> Void,
        onMessage: @escaping (AppUser, UserProfileViewModel) -> Void,
        onFollow: @escaping (UserProfileViewModel) -> Void
    ) {
        self.userId = userId
        self.cardWidth = cardWidth
        self.contentWidth = contentWidth
        self.gridCellSize = gridCellSize
        self.cardPadding = cardPadding
        self.gridSpacing = gridSpacing
        self.previewAvatarSize = previewAvatarSize
        self.avatarColumnWidth = avatarColumnWidth
        self.displayScale = displayScale
        self.colorScheme = colorScheme
        self.canvasColor = canvasColor
        self.cardShape = cardShape
        self.onOpenProfile = onOpenProfile
        self.onMessage = onMessage
        self.onFollow = onFollow
        _viewModel = StateObject(wrappedValue: UserProfileViewModel(userId: userId))
    }

    private var isOwnProfile: Bool {
        userId == Auth.auth().currentUser?.uid
    }

    private var previewMoments: [Moment] {
        Array(viewModel.moments.prefix(8))
    }

    private var shouldShowPreviewGrid: Bool {
        guard !previewMoments.isEmpty else { return false }
        return isOwnProfile || viewModel.canViewContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            if shouldShowPreviewGrid {
                momentsGrid
            } else if (viewModel.isLoading || viewModel.isLoadingMoments) && previewMoments.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .tint(UserProfileColors.accent)
            }

            statsRow

            if !isOwnProfile {
                footerActions
            }
        }
        .padding(cardPadding)
        .frame(width: cardWidth, alignment: .leading)
        .background(canvasColor)
        .overlay {
            cardShape
                .stroke(UserProfileColors.borderColor.opacity(colorScheme == .dark ? 0.14 : 0.22), lineWidth: 1)
        }
        .clipShape(cardShape)
        .contentShape(cardShape)
        .onTapGesture(perform: onOpenProfile)
        .onAppear {
            viewModel.checkFollowButtonState()
            // Mismo scan que el perfil: el backend aplica `limit` antes de filtrar visibilidad.
            viewModel.fetchProfile(momentsLimit: 50)
            viewModel.refreshMutualRelationship()
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                StoryRingAvatarView(
                    userId: userId,
                    size: previewAvatarSize,
                    lineWidth: 2.5,
                    allowOwnStories: true
                )

                ProfileAvatarNoteView(
                    note: viewModel.userProfile?.profileNote,
                    isEditable: false
                )
                .scaleEffect(avatarColumnWidth / ProfileAvatarNoteMetrics.columnWidth, anchor: .top)
                .frame(width: avatarColumnWidth)
            }
            .frame(width: avatarColumnWidth)

            VStack(alignment: .leading, spacing: 5) {
                if isOwnProfile {
                    HStack(spacing: 4) {
                        Text(viewModel.userProfile?.username ?? NSLocalizedString("userProfile.user", comment: ""))
                            .font(.system(size: legacyPoppinsSize(16), weight: .bold))
                            .foregroundStyle(UserProfileColors.textPrimary)
                            .lineLimit(1)

                        if viewModel.userProfile?.isVerified == true {
                            VerifiedBadge(size: 14)
                        }
                    }
                } else {
                    Button(action: onOpenProfile) {
                        HStack(spacing: 4) {
                            Text(viewModel.userProfile?.username ?? NSLocalizedString("userProfile.user", comment: ""))
                                .font(.system(size: legacyPoppinsSize(16), weight: .bold))
                                .foregroundStyle(UserProfileColors.textPrimary)
                                .lineLimit(1)

                            if viewModel.userProfile?.isVerified == true {
                                VerifiedBadge(size: 14)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if let userProfile = viewModel.userProfile {
                    UserProfileBadgesView(userProfile: userProfile)
                }

                if let bio = viewModel.userProfile?.bio?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundStyle(UserProfileColors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isOwnProfile {
                ModernFollowButton(
                    state: viewModel.followButtonState,
                    isLoading: false,
                    colorScheme: colorScheme,
                    style: .compact,
                    isMutual: viewModel.isMutualRelationship,
                    action: { onFollow(viewModel) }
                )
            }
        }
    }

    private var momentsGrid: some View {
        let rows = stride(from: 0, to: previewMoments.count, by: 4).map { start in
            Array(previewMoments[start..<min(start + 4, previewMoments.count)])
        }

        return VStack(alignment: .leading, spacing: gridSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: gridSpacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, moment in
                        gridCell(moment)
                    }
                }
            }
        }
        .frame(width: contentWidth, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func gridCell(_ moment: Moment) -> some View {
        ScreenshotProtectedView(
            isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
        ) {
            FeedPostProfilePreviewMomentThumb(
                moment: moment,
                size: gridCellSize,
                displayScale: displayScale
            )
        }
        .frame(width: gridCellSize, height: gridCellSize)
    }

    @ViewBuilder
    private var statsRow: some View {
        let stats = previewStats
        if !stats.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                    VStack(spacing: 2) {
                        Text(MomentsFormat.count(stat.count, style: .profileStat))
                            .font(.system(size: legacyPoppinsSize(15), weight: .bold))
                            .foregroundStyle(UserProfileColors.textPrimary)
                        Text(stat.label)
                            .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                            .foregroundStyle(UserProfileColors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)

                    if index < stats.count - 1 {
                        Rectangle()
                            .fill(UserProfileColors.borderColor.opacity(colorScheme == .dark ? 0.22 : 0.35))
                            .frame(width: 1, height: 28)
                    }
                }
            }
        }
    }

    private var previewStats: [(label: String, count: Int)] {
        var stats: [(String, Int)] = []
        let postsCount = max(viewModel.moments.count, viewModel.userProfile?.momentsCount ?? 0)

        if viewModel.canViewContent || isOwnProfile {
            stats.append((NSLocalizedString("profile.ui.posts", comment: ""), postsCount))
            if viewModel.visibleConnectionTypes.canViewFollowers {
                stats.append((NSLocalizedString("profile.ui.followers", comment: ""), viewModel.followers.count))
            }
            if viewModel.visibleConnectionTypes.canViewFollowing {
                stats.append((NSLocalizedString("profile.ui.following", comment: ""), viewModel.following.count))
            }
        } else {
            if viewModel.visibleConnectionTypes.canViewFollowers {
                stats.append((NSLocalizedString("profile.ui.followers", comment: ""), viewModel.followers.count))
            }
            if viewModel.visibleConnectionTypes.canViewFollowing {
                stats.append((NSLocalizedString("profile.ui.following", comment: ""), viewModel.following.count))
            }
        }

        return stats.map { ($0.0, $0.1) }
    }

    private var footerActions: some View {
        HStack(spacing: 10) {
            footerButton(
                title: NSLocalizedString("userActivity.event.action.viewProfile", comment: ""),
                icon: "person.crop.circle",
                action: onOpenProfile
            )

            if !isOwnProfile {
                footerButton(
                    title: NSLocalizedString("userProfile.sendMessage", comment: ""),
                    icon: "paperplane.fill",
                    action: {
                        guard let user = viewModel.userProfile else { return }
                        onMessage(user, viewModel)
                    }
                )
            }
        }
    }

    private func footerButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(UserProfileColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .momentsChromeGlass(in: Capsule(), interactive: true, style: .nativeTinted)
        }
        .buttonStyle(.plain)
    }
}

private struct FeedPostProfilePreviewMomentThumb: View {
    let moment: Moment
    let size: CGFloat
    let displayScale: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GridPreviewThumbnailFrame(size: size, settings: moment.gridPreviewSettings) {
                if let urlString = moment.previewImageURLString, let url = URL(string: urlString) {
                    KFImage(url)
                        .placeholder {
                            Rectangle().fill(UserProfileColors.cardBackground)
                        }
                        .downsampling(size: CGSize(width: size * displayScale, height: size * displayScale))
                        .scaleFactor(displayScale)
                        .cancelOnDisappear(true)
                        .resizable()
                } else {
                    Rectangle()
                        .fill(UserProfileColors.cardBackground)
                }
            }

            if moment.hasVideoMedia {
                ChatVideoPlayBadge(size: 14, padding: 8)
            }
        }
    }
}
