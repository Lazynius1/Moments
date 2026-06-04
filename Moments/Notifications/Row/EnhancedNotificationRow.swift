import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher

struct EnhancedNotificationRow: View {
    let group: NotificationGroup
    @ObservedObject var viewModel: NotificationsViewModel
    let colorScheme: ColorScheme
    let onTapAction: () -> Void
    let onModerationReviewTap: ((Notification) -> Void)?
    @State var showProfile = false
    @State var profileUserId: String?
    @State var showStories = false
    @State var momentImagePath: String?
    @State var storyImagePath: String?
    @State var isLoadingMomentImage: Bool = false
    @State var isLoadingStoryImage: Bool = false
    @State var momentImageLoadFailed: Bool = false
    @State var storyImageLoadFailed: Bool = false
    @State var followButtonState: FollowButtonState = .canFollow
    @State var isPressed: Bool = false
    @State var senderUsernameOverride: String?
    @State var showingUnfollowConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            leadingAvatar

            VStack(alignment: .leading, spacing: 2) {
                Text(messageForGroup(group))
                    .font(.system(size: 14, weight: .regular))
                    .lineLimit(2)
                    .environment(\.openURL, OpenURLAction { url in
                        if let userId = NotificationProfileLink.userId(from: url) {
                            openProfile(userId: userId)
                            return .handled
                        }
                        return .systemAction
                    })

                if let preview = commentPreviewForGroup {
                    Text(preview)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.5))
                        .lineLimit(2)
                }
                
                Text(group.notifications.first!.timestamp, style: .relative)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray.opacity(0.72))
            }
            
            Spacer()
            
            trailingContent

            // Indicador de no leído (estilo IG): punto de acento mientras la notificación esté pendiente.
            if group.isUnread {
                Circle()
                    .fill(colorScheme == .dark ? Color.white : Color.black)
                    .frame(width: 8, height: 8)
                    .transition(.opacity)
                    .accessibilityLabel(Text(NSLocalizedString("notifications.unread.indicator", comment: "Unread notification indicator")))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            isPressed
                ? Color.primary.opacity(0.04)
                : (group.isUnread ? (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)) : Color.clear)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                .frame(height: 0.5)
                .padding(.leading, leadingAvatarInset)
        }
        .onTapGesture {
            if opensSenderProfileOnTap, let userId = displaySenderIds.first {
                openProfile(userId: userId)
            } else {
                onTapAction()
            }
        }
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                isPressed = pressing
            },
            perform: {}
        )
        .sheet(isPresented: $showProfile) {
            if let profileUserId, !profileUserId.isEmpty {
                UserProfileView(userId: profileUserId)
            }
        }
        .fullScreenCover(isPresented: $showStories) {
            StoriesView(startWithUserId: .constant(group.notifications.first?.senderId ?? ""))
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
        .onAppear {
            resolveSenderDisplayData()
            setupPreviews()
        }
        .onReceive(NotificationCenter.default.publisher(for: FollowStateStore.didChangeNotification)) { notification in
            guard let targetUserId = group.notifications.first?.senderId,
                  let userId = notification.userInfo?["userId"] as? String,
                  userId == targetUserId,
                  let state = notification.userInfo?["state"] as? FollowButtonState else { return }
            followButtonState = state
        }
    }

    var uniqueSenderIdList: [String] {
        uniqueSenderIds(in: group)
    }

    /// Dos caras si hay 2 actores; con 3+ solo la más reciente (estilo Instagram).
    var displaySenderIds: [String] {
        let ids = uniqueSenderIdList
        if ids.count >= 3 {
            return Array(ids.prefix(1))
        }
        return Array(ids.prefix(2))
    }

    var commentPreviewForGroup: String? {
        guard let first = group.notifications.first else { return nil }
        let isCommentRow = first.type == .comment || first.mentionContext == "reply"
        guard isCommentRow else { return nil }
        for notification in group.notifications {
            if let preview = normalizedCommentPreview(from: notification) {
                return preview
            }
        }
        return nil
    }

    var leadingAvatarInset: CGFloat {
        displaySenderIds.count > 1
            ? NotificationRowMetrics.stackedRowWidth + 16
            : NotificationRowMetrics.avatarSize + 16
    }

    var leadingAvatar: some View {
        Group {
            if isModerationNotification {
                ZStack {
                    Circle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                        .frame(width: NotificationRowMetrics.avatarSize, height: NotificationRowMetrics.avatarSize)
                    Image(colorScheme == .dark ? "SplashLogoLight" : "SplashLogoDark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                }
                .overlay(
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.1), lineWidth: 1)
                )
            } else if !displaySenderIds.isEmpty {
                NotificationLeadingAvatarView(
                    senderIds: displaySenderIds,
                    colorScheme: colorScheme,
                    onPrimaryTap: {
                        if let frontId = displaySenderIds.first {
                            openProfile(userId: frontId)
                        }
                    },
                    onSecondaryTap: displaySenderIds.count > 1
                        ? { openProfile(userId: displaySenderIds[1]) }
                        : nil
                )
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: NotificationRowMetrics.avatarSize, height: NotificationRowMetrics.avatarSize)
            }
        }
    }

    func openProfile(userId: String) {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profileUserId = trimmed
        showProfile = true
    }

    var notificationMessageColor: Color {
        colorScheme == .dark ? .white : .black
    }

    func senderDisplayNamesToUserIds() -> [String: String] {
        var map: [String: String] = [:]
        var seen = Set<String>()

        for notification in group.notifications {
            let id = notification.senderId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            map[displayName(for: notification)] = id
        }

        if let first = group.notifications.first {
            let authorName = first.targetAuthorUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let authorId = first.targetAuthorId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !authorName.isEmpty, !authorId.isEmpty {
                map[authorName] = authorId
            }
        }

        return map
    }

    func groupedActorsForMessage() -> NotificationGroupedActors {
        var seen = Set<String>()
        var names: [String] = []
        for notification in group.notifications {
            let id = notification.senderId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            names.append(displayName(for: notification))
        }

        guard let primary = names.first else {
            let fallback = senderDisplayName(for: group.notifications.first!)
            return NotificationGroupedActors(primary: fallback, secondary: nil, othersCount: 0)
        }

        if names.count >= 2 {
            return NotificationGroupedActors(
                primary: primary,
                secondary: names[1],
                othersCount: max(0, names.count - 2)
            )
        }

        return NotificationGroupedActors(primary: primary, secondary: nil, othersCount: 0)
    }

    func displayName(for notification: Notification) -> String {
        if notification.id == group.notifications.first?.id,
           let senderUsernameOverride,
           !senderUsernameOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return senderUsernameOverride
        }
        return senderDisplayName(for: notification)
    }

    var opensSenderProfileOnTap: Bool {
        guard let type = group.notifications.first?.type else { return false }
        return type == .newFollower
            || type == .followRequest
            || type == .mutualConnection
            || type == .requestAccepted
    }

    func setupPreviews() {
        let first = group.notifications.first!
        if first.type == .like || first.type == .comment || first.type == .reaction || first.type == .photoTag || isMomentMention(first) { // ✅ AÑADIDO .photoTag
            if let momentId = first.momentId {
                fetchMomentPreview(
                    momentId: momentId,
                    authorId: momentAuthorId(for: first)
                )
            }
        } else if first.type == .storyReaction || first.type == .storyChainContinued || isStoryMention(first) {
            // El backend ya adjunta la miniatura real (poster de vídeo o foto): úsala sin pedir nada.
            if let preview = first.storyPreviewUrl, !preview.isEmpty {
                storyImagePath = preview
                isLoadingStoryImage = false
                storyImageLoadFailed = false
            } else if let storyId = first.storyId {
                fetchStoryPreview(storyId: storyId, authorId: resolvedStoryAuthorId(for: first))
            }
        }
        
        if first.type == .newFollower || first.type == .mutualConnection {
            checkFollowingStatus()
        }
    }
}
