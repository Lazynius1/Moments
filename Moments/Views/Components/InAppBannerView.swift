import SwiftUI
import Kingfisher
import FirebaseFirestore
import FirebaseAuth

struct InAppBannerView: View {
    @ObservedObject var service = InAppNotificationService.shared
    @StateObject private var navigationService = NotificationNavigationService.shared
    @Environment(\.colorScheme) var colorScheme
    @GestureState private var dragOffset = CGSize.zero
    @State private var isQuickReplyExpanded = false
    @State private var suppressTapUntil: Date = .distantPast
    @State private var contentPreviewImage: String?

    var body: some View {
        ZStack(alignment: .top) {
            if service.showBanner, let notification = service.currentNotification {
                Group {
                    if isQuickReplyExpanded, notification.type == .message {
                        InAppMessageQuickReplyPanel(
                            notification: notification,
                            onDismiss: collapseQuickReply
                        )
                    } else {
                        compactBanner(for: notification)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2000)
                .padding(.top, 10)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: service.showBanner)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isQuickReplyExpanded)
        .onChange(of: service.showBanner) { _, isVisible in
            if !isVisible {
                isQuickReplyExpanded = false
            }
        }
    }

    private func compactBanner(for notification: Notification) -> some View {
        let isSystem = isSystemBanner(notification)
        let accentColor = isSystem ? Color.orange : colorFor(notification.type)
        let copy = NotificationCopyResolver.resolve(notification)
        let lines = bannerTextLines(copy: copy, notification: notification)

        return HStack(spacing: 12) {
            bannerAvatar(for: notification, isSystem: isSystem)

            VStack(alignment: .leading, spacing: 3) {
                if let headline = lines.headline {
                    Text(headline)
                        .font(.system(size: legacyPoppinsSize(14), weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                if let detail = lines.detail {
                    Text(detail)
                        .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else if isSystemModerationBanner(notification) {
                    Text(moderationBannerText(for: notification))
                        .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                        .foregroundColor(.secondary.opacity(0.92))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            bannerTrailingIcon(for: notification, isSystem: isSystem, accentColor: accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Capsule())
        .momentsChromeGlass(in: Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.6),
                            accentColor.opacity(0.1),
                            accentColor.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .blur(radius: 0.5)
        )
        .padding(.horizontal, 12)
        .offset(y: dragOffset.height)
        .gesture(dismissDragGesture)
        .highPriorityGesture(messageLongPressGesture(for: notification))
        .onTapGesture {
            guard Date() >= suppressTapUntil else { return }
            handleTap(on: notification)
        }
        .onAppear {
            HapticManager.shared.notification(.success)
            loadImages(for: notification)
        }
        .onChange(of: notification.id) { _, _ in
            contentPreviewImage = nil
            loadImages(for: notification)
        }
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, state, _ in
                if value.translation.height < 0 {
                    state = value.translation
                }
            }
            .onEnded { value in
                if value.translation.height < -20 {
                    collapseQuickReply()
                    service.dismissManually()
                }
            }
    }

    private func messageLongPressGesture(for notification: Notification) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .onEnded { _ in
                guard notification.type == .message, notification.conversationId != nil else { return }
                suppressTapUntil = Date().addingTimeInterval(0.6)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isQuickReplyExpanded = true
                }
                HapticManager.shared.mediumImpact()
            }
    }

    private func collapseQuickReply() {
        isQuickReplyExpanded = false
    }

    private struct BannerTextLines {
        let headline: String?
        let detail: String?
    }

    private func bannerTextLines(copy: NotificationBannerCopy, notification: Notification) -> BannerTextLines {
        let name = notification.senderUsername

        if isSystemTimeLimitBanner(notification) {
            return BannerTextLines(headline: copy.title, detail: copy.body)
        }

        if notification.type == .gentleReminder {
            return BannerTextLines(headline: copy.title, detail: copy.body)
        }

        if let body = copy.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            if body.hasPrefix(name) {
                return BannerTextLines(headline: nil, detail: body)
            }
            return BannerTextLines(headline: name, detail: body)
        }

        if copy.title != name {
            return BannerTextLines(headline: name, detail: copy.title)
        }

        return BannerTextLines(headline: name, detail: nil)
    }

    @ViewBuilder
    private func bannerAvatar(for notification: Notification, isSystem: Bool) -> some View {
        if isSystem {
            systemBannerAvatar(for: notification)
        } else {
            AsyncProfileImageView(userId: notification.senderId)
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
    }

    @ViewBuilder
    private func bannerTrailingIcon(for notification: Notification, isSystem: Bool, accentColor: Color) -> some View {
        if !isSystem, let previewPath = contentPreviewImage, let url = URL(string: previewPath) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(accentColor.opacity(0.3), lineWidth: 1)
                )
        } else {
            Group {
                if !isSystemTimeLimitBanner(notification) && !isSystemModerationBanner(notification) && notification.type == .photoTag {
                    AttachmentIconView(icon: .tagged, preset: .inAppBanner, tintColor: accentColor)
                } else {
                    Image(systemName: isSystemTimeLimitBanner(notification) ? "clock.fill" : (isSystemModerationBanner(notification) ? "exclamationmark.shield.fill" : notification.type.systemIconName))
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundColor(isSystemModerationBanner(notification) ? .primary.opacity(0.85) : accentColor)
            .frame(width: 32, height: 32)
        }
    }

    private func isSystemTimeLimitBanner(_ notification: Notification) -> Bool {
        notification.senderId == "system_time_limit"
    }

    private func isSystemModerationBanner(_ notification: Notification) -> Bool {
        notification.type == .mediaModeration
    }

    private func isSystemBanner(_ notification: Notification) -> Bool {
        isSystemTimeLimitBanner(notification) || isSystemModerationBanner(notification)
    }

    @ViewBuilder
    private func systemBannerAvatar(for notification: Notification) -> some View {
        if isSystemModerationBanner(notification) {
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    .frame(width: 42, height: 42)
                Image(colorScheme == .dark ? "SplashLogoLight" : "SplashLogoDark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
            .overlay(
                Circle()
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.1), lineWidth: 1)
            )
        } else {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.16))
                    .frame(width: 42, height: 42)
                Image(systemName: "hourglass.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.orange)
            }
            .overlay(Circle().stroke(Color.orange.opacity(0.35), lineWidth: 1))
        }
    }

    private func loadImages(for notification: Notification) {
        if isSystemBanner(notification) { return }

        if notification.type == .mention, let storyId = notification.storyId {
            fetchStoryPreview(storyId: storyId, authorId: storyAuthorId(for: notification))
        } else if notification.type == .like || notification.type == .comment || notification.type == .reaction || notification.type == .mention {
            if let momentId = notification.momentId {
                fetchMomentPreview(momentId: momentId)
            }
        } else if notification.type == .storyReaction, let storyId = notification.storyId {
            fetchStoryPreview(storyId: storyId, authorId: notification.storyAuthorId)
        } else if notification.type == .storyChainContinued, let storyId = notification.storyId {
            fetchStoryPreview(storyId: storyId, authorId: notification.senderId)
        }
    }

    private func fetchMomentPreview(momentId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        FirestoreService().fetchMoment(momentId: momentId, userId: userId) { result in
            DispatchQueue.main.async {
                if case .success(let moment) = result {
                    contentPreviewImage = moment.previewImageURLString
                }
            }
        }
    }

    private func fetchStoryPreview(storyId: String, authorId: String?) {
        guard let userId = authorId else { return }
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("stories")
            .document(storyId)
            .getDocument { snapshot, _ in
                DispatchQueue.main.async {
                    guard let mediaItem = snapshot?.data()?["mediaItem"] as? [String: Any] else { return }
                    if let thumbnailUrl = mediaItem["thumbnailUrl"] as? String, !thumbnailUrl.isEmpty {
                        contentPreviewImage = thumbnailUrl
                    } else if let url = mediaItem["url"] as? String {
                        contentPreviewImage = url
                    }
                }
            }
    }

    private func handleTap(on notification: Notification) {
        collapseQuickReply()
        service.dismissManually()

        if isSystemBanner(notification) {
            if notification.type == .mediaModeration, let momentId = notification.momentId {
                navigationService.navigateToMoment(momentId: momentId, userId: notification.senderId)
            }
            return
        }

        switch notification.type {
        case .comment, .like, .reaction, .photoTag:
            if let momentId = notification.momentId {
                navigationService.navigateToMoment(momentId: momentId, userId: momentAuthorId(for: notification))
            }
        case .mention:
            if let storyId = notification.storyId {
                navigationService.navigateToStory(storyId: storyId, authorId: storyAuthorId(for: notification))
            } else if let momentId = notification.momentId {
                navigationService.navigateToMoment(momentId: momentId, userId: momentAuthorId(for: notification))
            }
        case .newFollower, .mutualConnection:
            navigationService.navigateToProfile(userId: notification.senderId)
        case .followRequest, .requestAccepted:
            navigationService.navigateToNotifications(filter: "requests")
        case .storyReaction:
            if let storyId = notification.storyId {
                navigationService.navigateToStory(storyId: storyId, authorId: storyAuthorId(for: notification))
            }
        case .storyChainContinued:
            if let chainId = notification.chainId {
                AppRouter.shared.navigate(to: .storyChain(chainId: chainId, title: notification.chainTitle ?? ""))
            } else if let storyId = notification.storyId {
                navigationService.navigateToStory(storyId: storyId, authorId: storyAuthorId(for: notification))
            }
        case .message:
            if let conversationId = notification.conversationId {
                navigationService.navigateToConversation(conversationId: conversationId)
            }
        case .messageReaction:
            if let conversationId = notification.conversationId {
                if let messageId = notification.messageId {
                    ChatNavigationIntentStore.enqueueHighlight(conversationId: conversationId, messageId: messageId)
                }
                navigationService.navigateToConversation(conversationId: conversationId)
            }
        case .chatBuzz:
            if let conversationId = notification.conversationId {
                ChatNavigationIntentStore.enqueueBuzz(conversationId: conversationId, buzzEventId: notification.buzzEventId)
                navigationService.navigateToConversation(conversationId: conversationId)
            }
        case .gentleReminder:
            AppRouter.shared.navigate(to: .creator)
        case .dataExportReady:
            if let rawUrl = notification.downloadURL,
               let url = URL(string: rawUrl),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        case .echoSuggestion:
            if let echoId = notification.echoId {
                AppRouter.shared.navigate(to: .echoSuggestion(echoId: echoId))
            }
        default:
            break
        }
    }

    private func storyAuthorId(for notification: Notification) -> String? {
        if notification.type == .storyReaction {
            return notification.storyAuthorId
                ?? notification.targetAuthorId
                ?? Auth.auth().currentUser?.uid
                ?? notification.senderId
        }
        return notification.storyAuthorId ?? notification.targetAuthorId ?? notification.senderId
    }

    private func momentAuthorId(for notification: Notification) -> String {
        notification.targetAuthorId ?? Auth.auth().currentUser?.uid ?? notification.senderId
    }

    private func colorFor(_ type: NotificationType) -> Color {
        switch type {
        case .like: return .red
        case .reaction, .messageReaction: return .purple
        case .comment: return .blue
        case .newFollower: return .green
        case .storyChainContinued: return .indigo
        case .echoSuggestion: return .orange
        case .mediaModeration: return .orange
        case .chatBuzz: return .cyan
        case .gentleReminder: return .mint
        default: return .gray
        }
    }

    private func moderationBannerText(for notification: Notification) -> String {
        if let message = notification.message, !message.isEmpty { return message }
        let moderationType = notification.reaction ?? "partial"
        let moderationScope = notification.moderationScope ?? "post"

        if moderationScope == "storySticker" {
            return NSLocalizedString("banner.verb.mediaModeration.storySticker.partial", value: "We hid a sticker from your story", comment: "")
        }
        if moderationScope == "postHiddenLayer" {
            return NSLocalizedString("banner.verb.mediaModeration.postHiddenLayer.partial", value: "We hid a hidden layer from your post", comment: "")
        }
        if moderationScope == "story" {
            return moderationType == "full"
                ? NSLocalizedString("banner.verb.mediaModeration.story.full", value: "Your story is now only visible to you", comment: "")
                : NSLocalizedString("banner.verb.mediaModeration.story.partial", value: "Some content was hidden from your story", comment: "")
        }
        return NSLocalizedString("banner.verb.mediaModeration.partial", value: "Some content was hidden from your post", comment: "")
    }
}
