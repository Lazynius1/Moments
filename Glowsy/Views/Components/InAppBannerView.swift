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
    
    private func bannerContent(for notification: Notification) -> some View {
        Button(action: {
            handleTap(on: notification)
        }) {
            HStack(spacing: 12) {
                AsyncProfileImageView(userId: notification.senderId)
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 1) {
                    // Header: Username + Verb
                    HStack(spacing: 4) {
                        Text(notification.senderUsername)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text(verbFor(notification.type))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    // Detailed Content
                    Group {
                        if notification.type == .reaction || notification.type == .storyReaction {
                            if let content = notification.reaction {
                                if let type = ReactionType(rawValue: content) {
                                    Text(type.icon)
                                        .font(.system(size: 16))
                                } else {
                                    Text(content)
                                        .font(.system(size: 14))
                                }
                            }
                        } else if let content = notification.reaction, !content.isEmpty {
                            // Comentario, Mención o Mensaje
                            Text(content)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // Icono tipo de notificación O PREVIEW DE IMAGEN
                if let previewPath = contentPreviewImage, let url = URL(string: previewPath) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                } else {
                    Image(systemName: notification.type.systemIconName)
                        .font(.system(size: 16))
                        .foregroundColor(colorFor(notification.type))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadImages(for: notification)
        }
        .onChange(of: notification.id) { _ in
            // Reset y recargar si cambia la notificación en vuelo
            contentPreviewImage = nil
            loadImages(for: notification)
        }
    }
    
    private func loadImages(for notification: Notification) {
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
        default: return "interacted"
        }
    }
    
    private func colorFor(_ type: NotificationType) -> Color {
        switch type {
        case .like: return .red
        case .reaction: return .purple
        case .comment: return .blue
        case .newFollower: return .green
        default: return .gray
        }
    }
}
