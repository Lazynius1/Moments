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
    
    private func bannerContent(for notification: Notification) -> some View {
        let isTimeLimit = isSystemTimeLimitBanner(notification)
        let accentColor = isTimeLimit ? Color.orange : colorFor(notification.type)

        return Button(action: {
            handleTap(on: notification)
        }) {
            HStack(spacing: 12) {
                if isTimeLimit {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.16))
                            .frame(width: 42, height: 42)
                        Image(systemName: "hourglass.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(accentColor)
                    }
                    .overlay(Circle().stroke(accentColor.opacity(0.35), lineWidth: 1))
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

                        if !isTimeLimit {
                            Text(verbFor(notification.type))
                                .font(.custom("Poppins-Medium", size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    // Detailed Content
                    Group {
                        if isTimeLimit, let content = notification.reaction, !content.isEmpty {
                            Text(content)
                                .font(.custom("Poppins-Medium", size: 13))
                                .foregroundColor(.secondary.opacity(0.92))
                                .lineLimit(2)
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
                if !isTimeLimit, let previewPath = contentPreviewImage, let url = URL(string: previewPath) {
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
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: isTimeLimit ? "clock.fill" : notification.type.systemIconName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(accentColor)
                    }
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
        .onChange(of: notification.id) { _ in
            // Reset y recargar si cambia la notificación en vuelo
            contentPreviewImage = nil
            loadImages(for: notification)
        }
    }
    
    private func loadImages(for notification: Notification) {
        if isSystemTimeLimitBanner(notification) {
            return
        }
        // 1. Avatar handled by AsyncProfileImageView
        
        // 2. Cargar Preview (Moment o Story)
        if notification.type == .like || notification.type == .comment || notification.type == .reaction || notification.type == .mention {
            if let momentId = notification.momentId {
                fetchMomentPreview(momentId: momentId)
            }
        } else if notification.type == .storyReaction, let storyId = notification.storyId {
            fetchStoryPreview(storyId: storyId, authorId: notification.storyAuthorId)
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
                    // Priorizar thumbnail para videos, luego imagePath
                    if let thumbnailUrl = moment.thumbnailUrl, !thumbnailUrl.isEmpty {
                        self.contentPreviewImage = thumbnailUrl
                    } else if let imagePath = moment.imagePath, !imagePath.isEmpty {
                        self.contentPreviewImage = imagePath
                    }
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
        if isSystemTimeLimitBanner(notification) {
            return
        }
        
        switch notification.type {
        case .comment, .like, .reaction, .mention:
            if let momentId = notification.momentId {
                navigationService.navigateToMoment(momentId: momentId, userId: notification.senderId)
            }
        case .newFollower:
            navigationService.navigateToProfile(userId: notification.senderId)
        case .followRequest, .requestAccepted: // ✅ Manejar aceptación
             // Ir a notificaciones (Requests tab)
             navigationService.navigateToNotifications(filter: "requests")
        case .storyReaction:
            if let storyId = notification.storyId {
                navigationService.navigateToStory(storyId: storyId)
            }
        case .message:
            if let conversationId = notification.momentId { // momentId guarda conversationId temporalmente
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
    
    private func verbFor(_ type: NotificationType) -> String {
        switch type {
        case .like: return NSLocalizedString("banner.verb.like", value: "liked your moment", comment: "")
        case .comment: return NSLocalizedString("banner.verb.comment", value: "commented on your moment", comment: "")
        case .reaction: return NSLocalizedString("banner.verb.reaction", value: "reacted to your moment", comment: "")
        case .newFollower: return NSLocalizedString("banner.verb.follow", value: "started following you", comment: "")
        case .followRequest: return NSLocalizedString("banner.verb.request", value: "sent a request", comment: "")
        case .requestAccepted: return NSLocalizedString("banner.verb.accepted", value: "accepted your request", comment: "")
        case .mention: return NSLocalizedString("banner.verb.mention", value: "mentioned you", comment: "")
        case .storyReaction: return NSLocalizedString("banner.verb.story", value: "reacted to your story", comment: "")
        case .message: return NSLocalizedString("banner.verb.message", value: "sent you a message", comment: "")
        case .echoSuggestion: return NSLocalizedString("banner.verb.echoSuggestion", value: "is near you! Create an Echo", comment: "")
        default: return "interacted"
        }
    }
    
    private func colorFor(_ type: NotificationType) -> Color {
        switch type {
        case .like: return .red
        case .reaction: return .purple
        case .comment: return .blue
        case .newFollower: return .green
        case .echoSuggestion: return .orange // Nova Spark vibe
        default: return .gray
        }
    }
}
