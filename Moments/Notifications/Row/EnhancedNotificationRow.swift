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
    let onShowGroupedFollowers: ((NotificationGroup) -> Void)?
    let onModerationReviewTap: ((Notification) -> Void)?
    var onOpenProfile: ((String) -> Void)? = nil
    /// Long-press de la fila → preview de perfil del actor más reciente (como feed).
    var onProfilePreview: ((String, String, CGRect) -> Void)? = nil
    @Namespace private var profileZoomNamespace
    @State var showStories = false
    @State var momentImagePath: String?
    @State var storyImagePath: String?
    @State var storyPreviewModel: Story?
    @State var isLoadingMomentImage: Bool = false
    @State var isLoadingStoryImage: Bool = false
    @State var momentImageLoadFailed: Bool = false
    @State var storyImageLoadFailed: Bool = false
    @State var followButtonState: FollowButtonState = .canFollow
    @State var isPressed: Bool = false
    @State var senderUsernameOverride: String?
    @State private var rowAnchorCapture = FeedStoryCircleAnchorCapture()

    var hasMultipleGroupedFollowActors: Bool {
        guard let type = group.notifications.first?.type else { return false }
        guard type == .newFollower || type == .mutualConnection else { return false }
        return uniqueSenderIdList.count > 1
    }

    var body: some View {
        HStack(spacing: 12) {
            leadingAvatar

            // Texto / preview / tiempo.
            // Tap (solo contenido): abre momento/story.
            // Long-press (fila): preview del sender más reciente — trailing fuera.
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
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.5))
                        .lineLimit(2)
                }
                
                Text(MomentsFormat.relativeTime(from: group.notifications.first!.timestamp))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.72))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                !supportsRowProfilePreview && isPressed
                    ? Color.primary.opacity(0.04)
                    : Color.clear
            )
            .modifier(NotificationRowBodyInteractionModifier(
                opensContentOnTap: opensContentOnBodyTap,
                supportsProfilePreview: supportsRowProfilePreview,
                isPressed: $isPressed,
                onTap: onTapAction,
                onLongPress: openMostRecentProfilePreview
            ))
            
            trailingContent

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
        .background(rowPlateBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                .frame(height: 0.5)
                .padding(.leading, leadingAvatarInset)
                .opacity(isRowLifted ? 0 : 1)
        }
        .compositingGroup()
        .scaleEffect(isRowLifted ? 1.07 : 1)
        .shadow(
            color: .black.opacity(isRowLifted ? 0.28 : 0),
            radius: isRowLifted ? 22 : 0,
            x: 0,
            y: isRowLifted ? 10 : 0
        )
        .background(FeedStoryCircleAnchorProbe(capture: rowAnchorCapture))
        .zIndex(isRowLifted ? 20 : 0)
        .animation(
            UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.32, dampingFraction: 0.86),
            value: isRowLifted
        )
        .fullScreenCover(isPresented: $showStories) {
            StoriesView(startWithUserId: .constant(group.notifications.first?.senderId ?? ""))
                .environmentObject(FirestoreService.shared)
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

    /// Dos caras si hay 2 actores; con 3+ solo la más reciente.
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
                .userProfileZoomSource(
                    userId: displaySenderIds.first ?? "",
                    namespace: profileZoomNamespace,
                    cornerRadius: NotificationRowMetrics.avatarSize / 2
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
        if let onOpenProfile {
            onOpenProfile(trimmed)
        }
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

    /// Follow / request: perfil solo vía avatar o nick; no tap de fila.
    var isSocialRelationshipNotification: Bool {
        guard let type = group.notifications.first?.type else { return false }
        return type == .newFollower
            || type == .followRequest
            || type == .mutualConnection
            || type == .requestAccepted
    }

    /// Like / reaction / comment / story / mention…: el cuerpo abre el contenido.
    var opensContentOnBodyTap: Bool {
        !isSocialRelationshipNotification && !isModerationNotification
    }

    /// Long-press de fila → preview (no en moderación / sin sender).
    var supportsRowProfilePreview: Bool {
        !isModerationNotification && !(uniqueSenderIdList.first ?? "").isEmpty
    }

    /// Lista, no feed: la placa se despega de las filas vecinas durante el hold.
    var isRowLifted: Bool {
        supportsRowProfilePreview && isPressed
    }

    var rowCanvasColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    var rowPlateBackground: Color {
        if isRowLifted {
            return rowCanvasColor
        }
        if group.isUnread {
            return colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)
        }
        return .clear
    }

    /// Actor más reciente del grupo (varios likes/follows → el primero de la lista dedupe).
    func openMostRecentProfilePreview() {
        guard supportsRowProfilePreview,
              let userId = uniqueSenderIdList.first,
              let onProfilePreview else { return }
        let momentId = group.notifications.first?.momentId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        HapticManager.shared.mediumImpact()
        onProfilePreview(userId, momentId, rowAnchorCapture.resolvedFrame)
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
                if let storyId = first.storyId {
                    fetchStoryPreview(storyId: storyId, authorId: resolvedStoryAuthorId(for: first))
                }
            } else if let storyId = first.storyId {
                fetchStoryPreview(storyId: storyId, authorId: resolvedStoryAuthorId(for: first))
            }
        }
        
        if (first.type == .newFollower || first.type == .mutualConnection) && !hasMultipleGroupedFollowActors {
            checkFollowingStatus()
        }
    }
}

/// Tap (contenido) + long-press (preview perfil) en el cuerpo; trailing fuera.
private struct NotificationRowBodyInteractionModifier: ViewModifier {
    let opensContentOnTap: Bool
    let supportsProfilePreview: Bool
    @Binding var isPressed: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if supportsProfilePreview {
            content.chatMessagePressClassifier(
                isPressing: $isPressed,
                onTap: opensContentOnTap ? onTap : nil,
                onLongPress: onLongPress
            )
        } else if opensContentOnTap {
            content
                .onTapGesture(perform: onTap)
                .onLongPressGesture(
                    minimumDuration: 0,
                    maximumDistance: .infinity,
                    pressing: { isPressed = $0 },
                    perform: {}
                )
        } else {
            content
        }
    }
}
