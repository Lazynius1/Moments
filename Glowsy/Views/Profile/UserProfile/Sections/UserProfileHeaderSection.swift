import SwiftUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import CoreMotion
import FirebaseFirestore
import AVKit

struct UserModernProfileHeader: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @ObservedObject var storyViewModel: StoryViewModel
    @ObservedObject var messagingViewModel: MessagingViewModel
    @StateObject private var messageRequestService = MessageRequestService()
    @EnvironmentObject var authService: AuthService // ✅ NUEVO: Para acceder a badges del usuario visitado
    @Binding var showStoryViewer: Bool
    @Binding var selectedStoryIndex: Int
    @Binding var navigateToChat: Bool
    @Binding var targetConversation: Conversation?
    @Binding var showingUserList: UserProfileView.UserListType?
    @Binding var showingMessageRequestAlert: Bool
    @Binding var messageRequestText: String
    @Binding var messageRequestError: String?
    @Binding var showingSuccessMessage: Bool
    @Binding var showProfileImageFullscreen: Bool
    let onFollowAction: () -> Void
    let onDismiss: () -> Void // ✅ NUEVO: Para el botón de atrás
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            // ✅ NUEVO: Botón de atrás en la esquina superior izquierda
            HStack {
                Button(action: onDismiss) {
                    ZStack {
                        Circle()
                            .fill(UserProfileColors.cardBackground.opacity(0.9))
                            .frame(width: 40, height: 40)
                            .shadow(color: UserProfileColors.shadowColor, radius: 8, x: 0, y: 4)

                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(UserProfileColors.textPrimary)
                    }
                }
                .scaleEffect(0.9)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: true)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)

            // Avatar principal con badges (sin círculo de fondo)
            UserModernAvatarWithBadges(
                userProfile: viewModel.userProfile,
                storyViewModel: storyViewModel,
                showStoryViewer: $showStoryViewer,
                selectedStoryIndex: $selectedStoryIndex,
                showProfileImageFullscreen: Binding<Bool>(
                    get: { self.showProfileImageFullscreen },
                    set: { self.showProfileImageFullscreen = $0 }
                ),
                size: 100
            )

            // Información del usuario con badges
            VStack(spacing: 10) {
                VStack(spacing: 6) {
                    VerifiedUsernameGradientView(
                        username: viewModel.userProfile?.username ?? NSLocalizedString("userProfile.user", comment: "User"),
                        isVerified: viewModel.userProfile?.isVerified ?? false,
                        badgeSize: 20,
                        spacing: 6,
                        gradient: LinearGradient(
                            colors: [Color(hex: "007AFF"), Color(hex: "6B73FF")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.custom("Poppins-Bold", size: 24))

                    // ✅ NUEVO: Badges horizontales del usuario visitado
                    if let userProfile = viewModel.userProfile {
                        UserProfileBadgesView(userProfile: userProfile)
                    }
                }

                // Bio expandible adaptativa
                VStack(spacing: 6) {
                    UserExpandableBioView(bio: viewModel.userProfile?.bio ?? NSLocalizedString("userProfile.noBio", comment: "No bio"))

                    if let websiteUrl = viewModel.userProfile?.websiteUrl,
                       !websiteUrl.isEmpty,
                       let url = URL(string: websiteUrl.hasPrefix("http") ? websiteUrl : "https://\(websiteUrl)") {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.system(size: 12, weight: .semibold))

                                Text(
                                    websiteUrl
                                        .replacingOccurrences(of: "https://", with: "")
                                        .replacingOccurrences(of: "http://", with: "")
                                )
                                .font(.custom("Poppins-Medium", size: 13))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            }
                            .foregroundColor(UserProfileColors.accent)
                            .padding(.vertical, 4)
                        }
                        .padding(.top, 2)
                    }

                }
            }

            // Botones de acción adaptativos
            HStack(spacing: 12) {
                Button(action: onFollowAction) {
                    HStack(spacing: 7) {
                        Text(followButtonText)
                            .font(.custom("Poppins-SemiBold", size: 14))

                        if viewModel.followButtonState == .following {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .liquidGlass(in: Capsule(), interactive: viewModel.followButtonState.isActionable)
                }
                .disabled(!viewModel.followButtonState.isActionable)
                .scaleEffect(viewModel.followButtonState.isActionable ? 1.0 : 0.95)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.followButtonState)

                Button(action: {
                    guard let currentUserId = Auth.auth().currentUser?.uid,
                          let targetUser = viewModel.userProfile else { return }

                    // ✅ Intentar crear conversación directa primero
                    messagingViewModel.startConversation(with: targetUser, from: currentUserId) { conversation in
                        if let conversation {
                            // ✅ Conversación creada exitosamente
                            targetConversation = conversation
                            navigateToChat = true
                        } else {
                            // ❌ Verificar si es error de seguimiento mutuo
                            let errorMessage = messagingViewModel.errorMessage ?? ""
                            if errorMessage.contains("no siguen mutuamente") || errorMessage.contains("Se requiere una solicitud") {
                                // 📤 Mostrar alerta para crear MessageRequest
                                showingMessageRequestAlert = true
                            }
                        }
                    }
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle(), interactive: true)
                }

                Button(action: {
                    if viewModel.isBlockedByCurrentUser {
                        viewModel.unblockUser(userId: viewModel.userId)
                    } else {
                        viewModel.blockUser(userId: viewModel.userId)
                    }
                }) {
                    Image(systemName: viewModel.isBlockedByCurrentUser ? "person.fill.checkmark" : "person.slash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.72))
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle(), interactive: true)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var followButtonText: String {
        switch viewModel.followButtonState {
        case .ownProfile:
            return NSLocalizedString("userProfile.followButton.ownProfile", comment: "Own profile")
        case .blocked:
            return NSLocalizedString("userProfile.followButton.blocked", comment: "Blocked")
        case .following:
            return NSLocalizedString("userProfile.followButton.following", comment: "Following")
        case .canFollow:
            return NSLocalizedString("userProfile.followButton.canFollow", comment: "Follow")
        case .canRequestFollow:
            return NSLocalizedString("userProfile.followButton.canRequestFollow", comment: "Request follow")
        case .requestPending:
            return NSLocalizedString("userProfile.followButton.requestPending", comment: "Request sent")
        }
    }

    private var followButtonColor: Color {
        switch viewModel.followButtonState {
        case .following, .requestPending: return Color.gray.opacity(0.6)
        case .canFollow, .canRequestFollow: return UserProfileColors.accent
        case .ownProfile, .blocked: return Color.gray.opacity(0.4)
        }
    }
}
