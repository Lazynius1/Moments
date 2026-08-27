import SwiftUI
import FirebaseAuth
import Kingfisher

// MARK: - Payload

enum SharedProfilePayloadBuilder {
    /// Firestore `sharedProfileData: [String: String]`.
    /// Identidad + snapshot opcional. La ficha DM **reevalúa** privacidad
    /// para el viewer (como `FeedPostProfilePreviewCard`); no confiar en
    /// `showMoments` / `showFollowers` / `showFollowing` / thumbs del payload.
    /// Avatar key: `profileImagePath` (campo real de `AppUser`).
    static func make(
        user: AppUser,
        moments: [Moment],
        canViewContent: Bool,
        visibleConnectionTypes: VisibleConnectionTypes,
        isOwnProfile: Bool,
        fallbackUserId: String = ""
    ) -> [String: String] {
        let previewURLs = moments
            .prefix(4)
            .compactMap { $0.previewImageURLString?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let previewJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: Array(previewURLs), options: []),
           let string = String(data: data, encoding: .utf8) {
            previewJSON = string
        } else {
            previewJSON = "[]"
        }

        let showMoments = isOwnProfile || canViewContent
        let profileUserId = user.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallbackUserId.trimmingCharacters(in: .whitespacesAndNewlines)
            : user.id

        return [
            "profileUserId": profileUserId,
            "username": user.username,
            "displayName": "",
            "profileImagePath": user.profileImagePath ?? "",
            "bio": user.bio ?? "",
            "profileNote": user.profileNote ?? "",
            "isVerified": user.isVerified ? "true" : "false",
            "momentsCount": String(max(user.momentsCount, moments.count)),
            "followersCount": String(user.followersCount),
            "followingCount": String(user.followingCount),
            "previewMomentUrls": previewJSON,
            "shareUrl": "https://glowsy.app/\(user.username)",
            "showMoments": showMoments ? "true" : "false",
            "showFollowers": visibleConnectionTypes.canViewFollowers ? "true" : "false",
            "showFollowing": visibleConnectionTypes.canViewFollowing ? "true" : "false"
        ]
    }
}

// MARK: - Share sheet (espejo de ModernShareSheet)

struct ProfileShareSheet: View {
    let profileUserId: String
    let sharedProfileData: [String: String]
    let onDismiss: () -> Void

    @StateObject private var chatService = ChatService.shared
    @State private var isSending = false
    @State private var deliveryFeedback: String?
    @State private var dismissAfterFeedback = false
    @State private var showSuccessFeedback = false

    private var username: String {
        sharedProfileData["username"] ?? ""
    }

    var body: some View {
        ShareRecipientsPickerSheet(
            titleKey: "share.sendTo",
            subtitle: String(
                format: NSLocalizedString("share.profile.by", comment: ""),
                username
            ),
            showsBackButton: false,
            onBack: nil,
            onDismiss: onDismiss,
            onSend: sendToSelectedUsers
        )
        .alert(
            NSLocalizedString("common.error", comment: ""),
            isPresented: Binding(
                get: { deliveryFeedback != nil },
                set: { if !$0 { deliveryFeedback = nil } }
            )
        ) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {
                deliveryFeedback = nil
                if dismissAfterFeedback { onDismiss() }
                dismissAfterFeedback = false
            }
        } message: {
            Text(deliveryFeedback ?? "")
        }
        .alert(
            NSLocalizedString("share.send.success.title", comment: ""),
            isPresented: $showSuccessFeedback
        ) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {
                onDismiss()
            }
        } message: {
            Text(NSLocalizedString("share.send.success.message", comment: ""))
        }
    }

    private func sendToSelectedUsers(selectedUsers: Set<String>, conversations: [Conversation]) {
        let fromProp = self.profileUserId.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let fromPayload = (sharedProfileData["profileUserId"] ?? "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let resolvedProfileUserId = fromProp.isEmpty ? fromPayload : fromProp

        guard let currentUserId = Auth.auth().currentUser?.uid,
              !resolvedProfileUserId.isEmpty,
              !isSending else {
            if resolvedProfileUserId.isEmpty {
                deliveryFeedback = NSLocalizedString("share.send.invalidPayload", comment: "")
            }
            return
        }

        let recipientIds = selectedUsers.sorted()
        guard !recipientIds.isEmpty else { return }
        isSending = true

        let shareText = String(
            format: NSLocalizedString("share.profile.by", comment: ""),
            username
        )

        Task { @MainActor in
            let coordinator = MessageRequestService()
            var results: [DirectRecipientSendResult] = []
            for userId in recipientIds {
                guard !userId.isEmpty else {
                    results.append(.init(id: userId, outcome: .denied, errorDescription: nil))
                    continue
                }
                do {
                    let context = MessageRequestInteractionContext(
                        kind: .shareProfile,
                        sharedContentId: resolvedProfileUserId,
                        sharedContentOwnerId: resolvedProfileUserId
                    )
                    let route = try await coordinator.resolveRoute(to: userId, interaction: context)
                    switch route {
                    case .conversation(let conversationId):
                        try await sendSharedProfile(
                            conversationId: conversationId,
                            senderId: currentUserId,
                            shareText: shareText,
                            profileUserId: resolvedProfileUserId
                        )
                        results.append(.init(id: userId, outcome: .conversation, errorDescription: nil))
                    case .conversationDraft(let threadId):
                        let conversationId = try await coordinator.activateConversationDraft(
                            to: userId,
                            threadId: threadId
                        )
                        try await sendSharedProfile(
                            conversationId: conversationId,
                            senderId: currentUserId,
                            shareText: shareText,
                            profileUserId: resolvedProfileUserId
                        )
                        results.append(.init(id: userId, outcome: .conversation, errorDescription: nil))
                    case .outgoingRequest:
                        _ = try await coordinator.appendRequestMessage(
                            to: userId,
                            text: shareText,
                            messageType: .sharedProfile,
                            interaction: context
                        )
                        results.append(.init(id: userId, outcome: .request, errorDescription: nil))
                    case .incomingRequest(let threadId, _):
                        let accepted = try await coordinator.acceptIncomingThread(threadId: threadId)
                        try await sendSharedProfile(
                            conversationId: accepted.conversationId,
                            senderId: currentUserId,
                            shareText: shareText,
                            profileUserId: resolvedProfileUserId
                        )
                        results.append(.init(id: userId, outcome: .conversation, errorDescription: nil))
                    }
                } catch {
                    results.append(.init(
                        id: userId,
                        outcome: (error as NSError).code == 403 ? .denied : .failed,
                        errorDescription: error.localizedDescription
                    ))
                }
            }
            isSending = false
            let failures = results.filter { $0.outcome == .failed || $0.outcome == .denied }
            if !results.isEmpty, failures.isEmpty {
                HapticManager.shared.success()
                showSuccessFeedback = true
                return
            }

            HapticManager.shared.error()
            if results.count == 1, let message = failures.first?.errorDescription, !message.isEmpty {
                deliveryFeedback = message
            } else {
                deliveryFeedback = String(
                    format: NSLocalizedString("messaging.forward.partialFailure", comment: ""),
                    failures.count,
                    results.count
                )
            }
            dismissAfterFeedback = failures.count < results.count
        }
    }

    private func sendSharedProfile(
        conversationId: String,
        senderId: String,
        shareText: String,
        profileUserId: String
    ) async throws {
        var payload = sharedProfileData
        payload["profileUserId"] = profileUserId
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            chatService.sendSharedProfileMessage(
                conversationId: conversationId,
                senderId: senderId,
                sharedProfileData: payload,
                shareText: shareText
            ) { result in
                continuation.resume(with: result.map { _ in () })
            }
        }
    }
}

// MARK: - Chat bubble (nombre exigido por ChatMessageBubbleViews)

struct SharedProfileMessageBubble: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool

    @State private var profileUserIdToOpen: String?

    var body: some View {
        Group {
            if let data = message.sharedProfileData {
                SharedProfilePreviewCard(sharedProfileData: data) {
                    // Solo abre si el viewer puede; la card no invoca esto si está blocked/unavailable.
                    guard let userId = data["profileUserId"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !userId.isEmpty else { return }
                    if userId == Auth.auth().currentUser?.uid {
                        LegacyNavigationBridge.ownProfileTab()
                    } else {
                        profileUserIdToOpen = userId
                    }
                }
                .frame(maxWidth: 280, alignment: isCurrentUser ? .trailing : .leading)
                .padding(.vertical, 4)
            }
        }
        .fullScreenCover(item: Binding(
            get: { profileUserIdToOpen.map { SharedProfileNavItem(id: $0) } },
            set: { profileUserIdToOpen = $0?.id }
        )) { item in
            UserProfileView(userId: item.id)
        }
    }
}

private struct SharedProfileNavItem: Identifiable {
    let id: String
}

// MARK: - Compact card (~70% feed preview, grid 4×1, sin follow/footer)
// Privacidad: reevaluación live para el viewer (bloqueos, audiencia, follows).

struct SharedProfilePreviewCard: View {
    let sharedProfileData: [String: String]
    let onOpenProfile: () -> Void

    @StateObject private var viewModel: UserProfileViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private let cardCornerRadius: CGFloat = 18
    private let cardPadding: CGFloat = 11
    private let gridSpacing: CGFloat = 2
    private let avatarSize: CGFloat = 40
    private let avatarColumnWidth: CGFloat = 56

    init(sharedProfileData: [String: String], onOpenProfile: @escaping () -> Void) {
        self.sharedProfileData = sharedProfileData
        self.onOpenProfile = onOpenProfile
        let profileUserId = sharedProfileData["profileUserId"] ?? ""
        _viewModel = StateObject(wrappedValue: UserProfileViewModel(userId: profileUserId))
    }

    /// Misma superficie elevada que `SharedDMPostCard` (contraste vs canvas del chat).
    private var cardBackground: Color {
        colorScheme == .dark ? Color(hex: "151C1D") : Color(hex: "E8EEF0")
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }

    private var profileUserId: String { sharedProfileData["profileUserId"] ?? "" }

    private var isOwnProfile: Bool {
        profileUserId == Auth.auth().currentUser?.uid
    }

    /// Bloqueo mutuo / perfil no disponible para este viewer.
    private var isUnavailableForViewer: Bool {
        guard !profileUserId.isEmpty else { return true }
        return viewModel.isProfileUnavailable
            || viewModel.isCurrentUserBlocked
            || viewModel.isBlockedByCurrentUser
    }

    private var resolvedUsername: String {
        if let live = viewModel.userProfile?.username.trimmingCharacters(in: .whitespacesAndNewlines),
           !live.isEmpty {
            return live
        }
        let snapshot = sharedProfileData["username"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return snapshot.isEmpty
            ? NSLocalizedString("userProfile.user", comment: "")
            : snapshot
    }

    private var resolvedBio: String? {
        let live = viewModel.userProfile?.bio?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let live, !live.isEmpty { return live }
        let snapshot = sharedProfileData["bio"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return snapshot.isEmpty ? nil : snapshot
    }

    private var resolvedNote: String? {
        let live = viewModel.userProfile?.profileNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let live, !live.isEmpty { return live }
        let snapshot = sharedProfileData["profileNote"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return snapshot.isEmpty ? nil : snapshot
    }

    private var resolvedVerified: Bool {
        viewModel.userProfile?.isVerified ?? (sharedProfileData["isVerified"] == "true")
    }

    private var previewMoments: [Moment] {
        Array(viewModel.moments.prefix(4))
    }

    private var snapshotPreviewURLs: [String] {
        guard let json = sharedProfileData["previewMomentUrls"],
              let data = json.data(using: .utf8),
              let urls = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return urls
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var hasPreviewContent: Bool {
        !previewMoments.isEmpty || !snapshotPreviewURLs.isEmpty
    }

    private var shouldShowMomentsGrid: Bool {
        guard hasPreviewContent else { return false }
        return isOwnProfile || viewModel.canViewContent
    }

    private var shouldShowMomentsLoading: Bool {
        !hasPreviewContent
            && (isOwnProfile || viewModel.canViewContent)
            && viewModel.isLoadingMoments
    }

    var body: some View {
        Group {
            if profileUserId.isEmpty {
                unavailableCard
            } else if viewModel.isLoading && viewModel.userProfile == nil {
                loadingCard
            } else if isUnavailableForViewer {
                unavailableCard
            } else {
                liveCard
            }
        }
        .onAppear {
            guard !profileUserId.isEmpty else { return }
            viewModel.checkFollowButtonState()
            viewModel.fetchProfile(momentsLimit: 50)
            viewModel.refreshMutualRelationship()
            if isOwnProfile {
                viewModel.fetchMoments()
            }
        }
    }

    private var unavailableCard: some View {
        // Sin avatar del payload: bloqueo / no disponible no debe filtrar foto snapshot.
        SharedDMUnavailablePreviewCard(
            titleKey: "share.profileUnavailable",
            messageKey: "share.noPermission",
            iconName: "lock.fill",
            previewImageURL: nil,
            authorId: nil,
            authorName: nil,
            useStoryRing: false
        )
    }

    private var loadingCard: some View {
        let contentWidth: CGFloat = 280 - cardPadding * 2
        return VStack(alignment: .leading, spacing: 10) {
            headerRow(useLive: false)
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .tint(UserProfileColors.accent)
        }
        .padding(cardPadding)
        .frame(width: 280, alignment: .leading)
        .background(cardBackground)
        .overlay {
            cardShape.stroke(
                UserProfileColors.borderColor.opacity(colorScheme == .dark ? 0.14 : 0.22),
                lineWidth: 1
            )
        }
        .clipShape(cardShape)
        .contentShape(cardShape)
        .onTapGesture(perform: onOpenProfile)
        .accessibilityHidden(contentWidth < 0)
    }

    private var liveCard: some View {
        let contentWidth: CGFloat = 280 - cardPadding * 2
        let cellSize = max(0, (contentWidth - gridSpacing * 3) / 4)

        return VStack(alignment: .leading, spacing: 10) {
            headerRow(useLive: true)

            if shouldShowMomentsGrid {
                momentsGrid(cellSize: cellSize, contentWidth: contentWidth)
            } else if shouldShowMomentsLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .tint(UserProfileColors.accent)
            }

            statsRow
        }
        .padding(cardPadding)
        .frame(width: 280, alignment: .leading)
        .background(cardBackground)
        .overlay {
            cardShape.stroke(
                UserProfileColors.borderColor.opacity(colorScheme == .dark ? 0.14 : 0.22),
                lineWidth: 1
            )
        }
        .clipShape(cardShape)
        .contentShape(cardShape)
        .onTapGesture(perform: onOpenProfile)
    }

    private func headerRow(useLive: Bool) -> some View {
        let note = useLive ? resolvedNote : resolvedNote
        let name = resolvedUsername
        let verified = resolvedVerified
        let bio = useLive ? resolvedBio : resolvedBio

        return HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 4) {
                StoryRingAvatarView(
                    userId: profileUserId,
                    size: avatarSize,
                    lineWidth: 2,
                    allowOwnStories: true
                )

                ProfileAvatarNoteView(
                    note: note,
                    isEditable: false
                )
                .scaleEffect(avatarColumnWidth / ProfileAvatarNoteMetrics.columnWidth, anchor: .top)
                .frame(width: avatarColumnWidth)
            }
            .frame(width: avatarColumnWidth)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Text(name)
                        .font(.system(size: legacyPoppinsSize(11), weight: .bold))
                        .foregroundStyle(UserProfileColors.textPrimary)
                        .lineLimit(1)

                    if verified {
                        VerifiedBadge(size: 10)
                    }
                }

                if let bio {
                    Text(bio)
                        .font(.system(size: legacyPoppinsSize(9)))
                        .foregroundStyle(UserProfileColors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func momentsGrid(cellSize: CGFloat, contentWidth: CGFloat) -> some View {
        HStack(spacing: gridSpacing) {
            if !previewMoments.isEmpty {
                ForEach(Array(previewMoments.enumerated()), id: \.offset) { _, moment in
                    SharedProfileMomentThumb(
                        moment: moment,
                        size: cellSize,
                        displayScale: displayScale
                    )
                }
                if previewMoments.count < 4 {
                    ForEach(0..<(4 - previewMoments.count), id: \.self) { _ in
                        Color.clear.frame(width: cellSize, height: cellSize)
                    }
                }
            } else {
                ForEach(Array(snapshotPreviewURLs.prefix(4).enumerated()), id: \.offset) { _, urlString in
                    SharedProfileSnapshotThumb(
                        urlString: urlString,
                        size: cellSize,
                        displayScale: displayScale
                    )
                }
                if snapshotPreviewURLs.count < 4 {
                    ForEach(0..<(4 - snapshotPreviewURLs.count), id: \.self) { _ in
                        Color.clear.frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
        .frame(width: contentWidth, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private var statsRow: some View {
        let stats = visibleStats
        if !stats.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                    VStack(spacing: 1) {
                        Text(MomentsFormat.count(stat.count, style: .profileStat))
                            .font(.system(size: legacyPoppinsSize(11), weight: .bold))
                            .foregroundStyle(UserProfileColors.textPrimary)
                        Text(stat.label)
                            .font(.system(size: legacyPoppinsSize(7), weight: .medium))
                            .foregroundStyle(UserProfileColors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)

                    if index < stats.count - 1 {
                        Rectangle()
                            .fill(UserProfileColors.borderColor.opacity(colorScheme == .dark ? 0.22 : 0.35))
                            .frame(width: 1, height: 20)
                    }
                }
            }
        }
    }

    /// Misma lógica que `FeedPostProfilePreviewCard.previewStats` para este viewer.
    private var visibleStats: [(label: String, count: Int)] {
        var stats: [(String, Int)] = []
        let postsCount = max(viewModel.moments.count, viewModel.userProfile?.momentsCount ?? 0)

        if viewModel.canViewContent || isOwnProfile {
            stats.append((NSLocalizedString("profile.ui.posts", comment: ""), postsCount))
            if viewModel.visibleConnectionTypes.canViewFollowers {
                stats.append((
                    NSLocalizedString("profile.ui.followers", comment: ""),
                    max(viewModel.followers.count, viewModel.userProfile?.followersCount ?? 0)
                ))
            }
            if viewModel.visibleConnectionTypes.canViewFollowing {
                stats.append((
                    NSLocalizedString("profile.ui.following", comment: ""),
                    max(viewModel.following.count, viewModel.userProfile?.followingCount ?? 0)
                ))
            }
        } else {
            if viewModel.visibleConnectionTypes.canViewFollowers {
                stats.append((
                    NSLocalizedString("profile.ui.followers", comment: ""),
                    max(viewModel.followers.count, viewModel.userProfile?.followersCount ?? 0)
                ))
            }
            if viewModel.visibleConnectionTypes.canViewFollowing {
                stats.append((
                    NSLocalizedString("profile.ui.following", comment: ""),
                    max(viewModel.following.count, viewModel.userProfile?.followingCount ?? 0)
                ))
            }
        }
        return stats
    }
}

private struct SharedProfileSnapshotThumb: View {
    let urlString: String
    let size: CGFloat
    let displayScale: CGFloat

    var body: some View {
        GridPreviewThumbnailFrame(size: size, settings: .default) {
            if let url = URL(string: urlString) {
                KFImage(url)
                    .placeholder {
                        Rectangle().fill(UserProfileColors.cardBackground)
                    }
                    .downsampling(size: CGSize(width: size * displayScale, height: size * displayScale))
                    .scaleFactor(displayScale)
                    .cancelOnDisappear(true)
                    .resizable()
            } else {
                Rectangle().fill(UserProfileColors.cardBackground)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct SharedProfileMomentThumb: View {
    let moment: Moment
    let size: CGFloat
    let displayScale: CGFloat

    var body: some View {
        ScreenshotProtectedView(
            isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
        ) {
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
                        Rectangle().fill(UserProfileColors.cardBackground)
                    }
                }

                if moment.hasVideoMedia {
                    ChatVideoPlayBadge(size: 14, padding: 8)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
