import SwiftUI
import Kingfisher
import FirebaseFirestore
import FirebaseAuth

struct InAppBannerView: View {
    @ObservedObject var service = InAppNotificationService.shared
    @StateObject private var navigationService = NotificationNavigationService.shared
    @Environment(\.colorScheme) var colorScheme
    @GestureState private var dragOffset = CGSize.zero
    
    var body: some View {
        ZStack(alignment: .top) {
            if service.showBanner, let notification = service.currentNotification {
                bannerContent(for: notification)
                    .offset(y: dragOffset.height)
                    .gesture(
                        DragGesture()
                            .updating($dragOffset) { value, state, _ in
                                if value.translation.height < 0 {
                                    state = value.translation
                                }
                            }
                            .onEnded { value in
                                if value.translation.height < -20 {
                                    service.dismissManually()
                                }
                            }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2000)
                    .padding(.top, 10) // Ajuste para Dynamic Island / Notch
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: service.showBanner)
    }
    
    // Estados para imágenes
    // @State private var senderProfileImage: String? // Eliminado, usamos AsyncProfileImageView
    @State private var contentPreviewImage: String?
    
    // Cache simple en memoria para esta sesión de vista
    @State private var profileCache: [String: String] = [:]

    private func isSystemTimeLimitBanner(_ notification: Notification) -> Bool {
        notification.senderId == "system_time_limit"
    }
    
    private func isSystemModerationBanner(_ notification: Notification) -> Bool {
        notification.type == .mediaModeration
    }
    
    private func isSystemBanner(_ notification: Notification) -> Bool {
        isSystemTimeLimitBanner(notification) || isSystemModerationBanner(notification)
    }
    
    private func bannerContent(for notification: Notification) -> some View {
        let isSystem = isSystemBanner(notification)
        let accentColor = isSystem ? Color.orange : colorFor(notification.type)

        return Button(action: {
            handleTap(on: notification)
        }) {
            HStack(spacing: 12) {
                if isSystem {
                    systemBannerAvatar(for: notification)
                } else {
                    AsyncProfileImageView(userId: notification.senderId)
                        .frame(width: 42, height: 42)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    // Header: Username + Verb
                    HStack(spacing: 6) {
                        Text(notification.senderUsername)
                            .font(.custom("Poppins-Bold", size: 14))
                            .foregroundColor(.primary)

                        if !isSystem {
                            Text(verbFor(notification))
                                .font(.custom("Poppins-Medium", size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    // Detailed Content
                    Group {
                        if isSystemTimeLimitBanner(notification), let content = notification.reaction, !content.isEmpty {
                            Text(content)
                                .font(.custom("Poppins-Medium", size: 13))
                                .foregroundColor(.secondary.opacity(0.92))
                                .lineLimit(2)
                        } else if isSystemModerationBanner(notification) {
                            Text(moderationBannerText(for: notification))
                                .font(.custom("Poppins-Medium", size: 13))
                                .foregroundColor(.secondary.opacity(0.92))
                                .lineLimit(2)
                        } else if notification.type == .storyChainContinued {
                            Text(storyChainSubtitle(for: notification))
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(.secondary.opacity(0.8))
                                .lineLimit(1)
                        } else if notification.type == .mention,
                                  notification.mentionContext == "comment",
                                  let targetAuthorUsername = notification.targetAuthorUsername,
                                  !targetAuthorUsername.isEmpty {
                            Text(String(format: NSLocalizedString("banner.subtitle.mention.comment.withAuthor", value: "in %@'s moment", comment: ""), targetAuthorUsername))
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(.secondary.opacity(0.8))
                                .lineLimit(1)
                        } else if notification.type == .reaction || notification.type == .storyReaction {
                            if let content = notification.reaction {
                                if let type = ReactionType(rawValue: content) {
                                    Text(type.icon)
                                        .font(.system(size: 18))
                                } else {
                                    Text(content)
                                        .font(.system(size: 14))
                                }
                            }
                        } else if let content = notification.reaction, !content.isEmpty {
                            Text(content)
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(.secondary.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // Icon or Preview
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
                    Image(systemName: isSystemTimeLimitBanner(notification) ? "clock.fill" : (isSystemModerationBanner(notification) ? "exclamationmark.shield.fill" : notification.type.systemIconName))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSystemModerationBanner(notification) ? .primary.opacity(0.85) : accentColor)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .liquidGlass(in: Capsule())
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
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            // Haptic Sync using the Manager
            HapticManager.shared.notification(.success)
            loadImages(for: notification)
        }
        .onChange(of: notification.id) { _, _ in
            // Reset y recargar si cambia la notificación en vuelo
            contentPreviewImage = nil
            loadImages(for: notification)
        }
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
        if isSystemBanner(notification) {
            return
        }
        // 1. Avatar handled by AsyncProfileImageView
        
        // 2. Cargar Preview (Moment o Story)
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
    
    // ✅ Método estándar para cargar preview de momento (igual que NotificationsView)
    private func fetchMomentPreview(momentId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let firestoreService = FirestoreService()
        
        firestoreService.fetchMoment(momentId: momentId, userId: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let moment):
                    self.contentPreviewImage = moment.previewImageURLString
                case .failure:
                    break
                }
            }
        }
    }
    
    // ✅ Método estándar para cargar preview de historia (igual que NotificationsView)
    private func fetchStoryPreview(storyId: String, authorId: String?) {
        guard let userId = authorId else { return }
        
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("stories")
            .document(storyId)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    if let data = snapshot?.data(),
                       let mediaItem = data["mediaItem"] as? [String: Any] {
                        
                        // Priorizar thumbnailUrl si existe (para videos)
                        if let thumbnailUrl = mediaItem["thumbnailUrl"] as? String, !thumbnailUrl.isEmpty {
                            self.contentPreviewImage = thumbnailUrl
                        } else if let url = mediaItem["url"] as? String {
                            self.contentPreviewImage = url
                        }
                    }
                }
            }
    }
    
    private func handleTap(on notification: Notification) {
        service.dismissManually()
        if isSystemBanner(notification) {
            // Para moderación, navegar al momento moderado
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
                navigationService.navigateToMoment(
                    momentId: momentId,
                    userId: momentAuthorId(for: notification)
                )
            }
        case .newFollower:
            navigationService.navigateToProfile(userId: notification.senderId)
        case .followRequest, .requestAccepted: // ✅ Manejar aceptación
             // Ir a notificaciones (Requests tab)
             navigationService.navigateToNotifications(filter: "requests")
        case .storyReaction:
            if let storyId = notification.storyId {
                navigationService.navigateToStory(storyId: storyId, authorId: storyAuthorId(for: notification))
            }
        case .storyChainContinued:
            if let chainId = notification.chainId {
                navigationService.pendingNavigation = .storyChain(chainId, notification.chainTitle ?? "")
            } else if let storyId = notification.storyId {
                navigationService.navigateToStory(storyId: storyId, authorId: storyAuthorId(for: notification))
            }
        case .message:
            if let conversationId = notification.conversationId ?? notification.momentId {
                navigationService.navigateToConversation(conversationId: conversationId)
            }
        case .echoSuggestion:
            if let echoId = notification.echoId {
                navigationService.pendingNavigation = .echoSuggestion(echoId)
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
        let currentUserId = Auth.auth().currentUser?.uid
        return notification.targetAuthorId ?? currentUserId ?? notification.senderId
    }

    private func verbFor(_ notification: Notification) -> String {
        switch notification.type {
        case .like: return NSLocalizedString("banner.verb.like", value: "liked your moment", comment: "")
        case .comment:
            if notification.mentionContext == "reply" {
                return NSLocalizedString("banner.verb.reply", value: "replied to your comment", comment: "")
            }
            return NSLocalizedString("banner.verb.comment", value: "commented on your moment", comment: "")
        case .reaction: return NSLocalizedString("banner.verb.reaction", value: "reacted to your moment", comment: "")
        case .photoTag:
            if let title = notification.reaction?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                return String(
                    format: NSLocalizedString("banner.verb.tagged.withTitle", value: "tagged you in \"%@\"", comment: ""),
                    title
                )
            }
            return NSLocalizedString("banner.verb.tagged", value: "tagged you in their moment", comment: "")
        case .newFollower: return NSLocalizedString("banner.verb.follow", value: "started following you", comment: "")
        case .followRequest: return NSLocalizedString("banner.verb.request", value: "sent a request", comment: "")
        case .requestAccepted: return NSLocalizedString("banner.verb.accepted", value: "accepted your request", comment: "")
        case .mention:
            switch notification.mentionContext ?? (notification.storyId != nil ? "story" : (notification.commentId != nil ? "comment" : "moment")) {
            case "story":
                return NSLocalizedString("banner.verb.mention.story", value: "mentioned you in a story", comment: "")
            case "comment":
                return NSLocalizedString("banner.verb.mention.comment", value: "mentioned you in a comment", comment: "")
            default:
                return NSLocalizedString("banner.verb.mention.moment", value: "mentioned you in a moment", comment: "")
            }
        case .storyReaction: return NSLocalizedString("banner.verb.story", value: "reacted to your story", comment: "")
        case .storyChainContinued: return NSLocalizedString("banner.verb.storyChain", value: "continued your story chain", comment: "")
        case .message: return NSLocalizedString("banner.verb.message", value: "sent you a message", comment: "")
        case .echoSuggestion: return NSLocalizedString("banner.verb.echoSuggestion", value: "is near you! Create an Echo", comment: "")
        case .mediaModeration: return NSLocalizedString("banner.verb.mediaModeration.partial", value: "Some content was hidden from your post", comment: "")
        default: return "interacted"
        }
    }
    
    private func colorFor(_ type: NotificationType) -> Color {
        switch type {
        case .like: return .red
        case .reaction: return .purple
        case .comment: return .blue
        case .newFollower: return .green
        case .storyChainContinued: return .indigo
        case .echoSuggestion: return .orange // Nova Spark vibe
        case .mediaModeration: return .orange // 🛡️ Moderación
        default: return .gray
        }
    }

    private func moderationBannerText(for notification: Notification) -> String {
        if let message = notification.message, !message.isEmpty {
            return message
        }
        let moderationType = notification.reaction ?? "partial" // reaction se usa para almacenar moderationType en el decode
        let moderationScope = notification.moderationScope ?? "post"

        if moderationScope == "storySticker" {
            return NSLocalizedString("banner.verb.mediaModeration.storySticker.partial", value: "We hid a sticker from your story", comment: "")
        }

        if moderationScope == "postHiddenLayer" {
            return NSLocalizedString("banner.verb.mediaModeration.postHiddenLayer.partial", value: "We hid a hidden layer from your post", comment: "")
        }

        if moderationScope == "story" {
            if moderationType == "full" {
                return NSLocalizedString("banner.verb.mediaModeration.story.full", value: "Your story is now only visible to you", comment: "")
            }
            return NSLocalizedString("banner.verb.mediaModeration.story.partial", value: "Some content was hidden from your story", comment: "")
        }

        if moderationType == "full" || notification.senderId == "system_moderation" {
            if notification.title?.contains("solo para ti") == true || notification.title?.contains("only to you") == true {
                return NSLocalizedString("banner.verb.mediaModeration.full", value: "Your post is now only visible to you", comment: "")
            }
        }
        return NSLocalizedString("banner.verb.mediaModeration.partial", value: "Some content was hidden from your post", comment: "")
    }

    private func storyChainSubtitle(for notification: Notification) -> String {
        let chainTitle = (notification.chainTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (notification.chainTitle ?? "")
            : NSLocalizedString("storyChains.chain", comment: "Chain")
        let partText = notification.chainPosition.map { String($0) } ?? "?"
        return String(format: NSLocalizedString("banner.storyChain.subtitle", value: "Part %@ · %@", comment: "Story chain banner subtitle"), partText, chainTitle)
    }
}
