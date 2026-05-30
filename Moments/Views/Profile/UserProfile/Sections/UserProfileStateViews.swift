import SwiftUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import CoreMotion
import FirebaseFirestore
import AVKit

// MARK: - ✅ NUEVO: Estado vacío moderno como ProfileView
struct UserModernEmptyMomentsView: View {
    var body: some View {
        ProfileSectionEmptyState(
            icon: "camera",
            titleKey: "userProfile.noMoments.title",
            subtitleKey: "userProfile.noMoments.description"
        )
    }
}
// MARK: - UserModernBlockedView (sin cambios - ya estaba bien)
struct UserModernBlockedView: View {
    let isBlockedByCurrentUser: Bool
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let onUnblock: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
                .frame(height: safeAreaTop)

            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle()
                                .stroke(Color.red.opacity(0.3), lineWidth: 2)
                        )
                    Image(systemName: "person.fill.xmark")
                        .font(.system(size: 40))
                        .foregroundColor(.red.opacity(0.8))
                }

                VStack(spacing: 16) {
                    Text(isBlockedByCurrentUser ? NSLocalizedString("userProfile.blockedUser", comment: "Blocked user") : NSLocalizedString("userProfile.restrictedAccess", comment: "Restricted access"))
                        .font(.custom("Poppins-Bold", size: 22))
                        .foregroundColor(.white)
                    Text(isBlockedByCurrentUser ?
                         NSLocalizedString("userProfile.blockedByYou", comment: "You blocked this user") :
                         NSLocalizedString("userProfile.blockedYou", comment: "This user blocked you"))
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(.gray.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                VStack(spacing: 12) {
                    if isBlockedByCurrentUser {
                        Button(action: onUnblock) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.fill.checkmark")
                                    .font(.system(size: 16))
                                Text("userProfile.unblockUser")
                                    .font(.custom("Poppins-SemiBold", size: 14))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color(hex: "00A896"))
                            .clipShape(Capsule())
                            .shadow(color: Color(hex: "00A896").opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                    }
                    Button(action: onDismiss) {
                        Text("userProfile.back")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }

            Spacer()
        }
        .padding(.bottom, safeAreaBottom + 20)
        // NUEVO: Gesto para cerrar
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 100 {
                        onDismiss()
                    }
                }
        )
    }
}

// MARK: - UserModernPrivateProfileView (mejorada con stats reales y card)
struct UserModernPrivateProfileView: View {
    let userProfile: AppUser?
    let userId: String
    @ObservedObject var storyViewModel: StoryViewModel
    @ObservedObject var messagingViewModel: MessagingViewModel
    @ObservedObject var viewModel: UserProfileViewModel // ✅ NUEVO: Para acceder a los datos reales
    let followButtonState: FollowButtonState
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    @Binding var navigateToChat: Bool
    @Binding var targetConversation: Conversation?
    @Binding var showingMessageRequestAlert: Bool
    @Binding var messageRequestText: String
    @Binding var messageRequestError: String?
    @Binding var showingSuccessMessage: Bool
    let onFollowAction: () -> Void
    let onDismiss: () -> Void
    @Binding var showStoryViewer: Bool
    @Binding var selectedStoryIndex: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: safeAreaTop + 20)

                UserModernAvatar(
                    profileImagePath: userProfile?.profileImagePath,
                    userId: self.userId,
                    storyViewModel: storyViewModel,
                    showStoryViewer: $showStoryViewer,
                    selectedStoryIndex: $selectedStoryIndex,
                    size: 100
                )
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Text(userProfile?.username ?? NSLocalizedString("userProfile.user", comment: "User"))
                            .font(.custom("Poppins-Bold", size: 26))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        VerifiedBadgeView(userId: self.userId, size: 22)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    if let bio = userProfile?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.custom("Poppins-Regular", size: 15))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.68) : .black.opacity(0.58))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 32)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 12) {
                    Button(action: {
                        HapticManager.shared.mediumImpact()
                        onFollowAction()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: followButtonIcon)
                                .font(.system(size: 15, weight: .medium))
                            Text(followButtonText)
                                .font(.custom("Poppins-SemiBold", size: 14))

                            if followButtonState == .following {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                            }
                        }
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .liquidGlass(in: Capsule(), interactive: followButtonState.isActionable)
                    }
                    .disabled(!followButtonState.isActionable)

                    Button(action: {
                        guard let currentUserId = Auth.auth().currentUser?.uid,
                              let targetUser = userProfile else { return }

                        messagingViewModel.startConversation(with: targetUser, from: currentUserId) { conversation in
                            if let conversation {
                                targetConversation = conversation
                                navigateToChat = true
                            } else if let error = messagingViewModel.errorMessage {
                                let lowercasedError = error.lowercased()
                                if lowercasedError.contains("no siguen mutuamente") || lowercasedError.contains("solicitud") {
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
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "lock")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.54) : .black.opacity(0.48))

                VStack(spacing: 8) {
                    Text("userProfile.private.title")
                        .font(.custom("Poppins-Bold", size: 22))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text("userProfile.private.description")
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.56))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 42)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()
            Spacer()
        }
    }

    private var followButtonText: String {
        switch followButtonState {
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
        case .requestPendingCancellable:
            return NSLocalizedString("userProfile.followButton.cancelRequest", comment: "Cancel request")
        }
    }

    private var followButtonColor: Color {
        switch followButtonState {
        case .following, .requestPending:
            return Color.gray.opacity(0.6)
        case .requestPendingCancellable:
            return Color.orange.opacity(0.8)
        case .canFollow, .canRequestFollow:
            return Color(hex: "00A896")
        case .ownProfile, .blocked:
            return Color.gray.opacity(0.4)
        }
    }

    // ✅ NUEVO: Icono para el botón según el estado
    private var followButtonIcon: String {
        switch followButtonState {
        case .ownProfile:
            return "person.circle.fill"
        case .blocked:
            return "slash.circle"
        case .following:
            return "checkmark.circle.fill"
        case .canFollow:
            return "person.badge.plus"
        case .canRequestFollow:
            return "envelope.circle"
        case .requestPending:
            return "clock.circle"
        case .requestPendingCancellable:
            return "xmark.circle"
        }
    }
}

// MARK: - Neutral unavailable profile state
struct ProfileUnavailableAvatar: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                .overlay(
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10), lineWidth: 1)
                )

            Image(systemName: "person.slash")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.62))
        }
        .frame(width: size, height: size)
    }
}

struct UserModernUnavailableProfileView: View {
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 42, height: 42)
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, safeAreaTop + 8)

            Spacer()

            VStack(spacing: 20) {
                ProfileUnavailableAvatar(size: 92)

                VStack(spacing: 10) {
                    Text("userProfile.unavailable.title")
                        .font(.custom("Poppins-Bold", size: 24))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.center)

                    Text("userProfile.unavailable.description")
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.56))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 42)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()
            Spacer()
                .frame(height: safeAreaBottom + 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
    }
}

struct UserModernBlockedByMeProfileView: View {
    let userProfile: AppUser?
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let onUnblock: () -> Void
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var username: String {
        userProfile?.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? userProfile?.username ?? NSLocalizedString("userProfile.user", comment: "User")
            : NSLocalizedString("userProfile.user", comment: "User")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 42, height: 42)
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, safeAreaTop + 8)

            VStack(spacing: 18) {
                blockedAvatar

                VStack(spacing: 8) {
                    Text(username)
                        .font(.custom("Poppins-Bold", size: 28))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    if let bio = userProfile?.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(bio)
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.52))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 34)
                    }
                }

                HStack(spacing: 22) {
                    blockedStat(label: NSLocalizedString("profile.ui.posts", comment: "Posts"))
                    blockedStat(label: NSLocalizedString("profile.ui.followers", comment: "Followers"))
                    blockedStat(label: NSLocalizedString("profile.ui.following", comment: "Following"))
                }
                .padding(.top, 2)
            }
            .padding(.top, 18)

            Spacer()

            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("userProfile.blockedByMe.title")
                        .font(.custom("Poppins-Bold", size: 22))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text("userProfile.blockedByMe.description")
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.56))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                }

                Button(action: onUnblock) {
                    Text("userProfile.unblockUser")
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 13)
                        .liquidGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
            }

            Spacer()
                .frame(height: safeAreaBottom + 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
    }

    @ViewBuilder
    private var blockedAvatar: some View {
        if let path = userProfile?.profileImagePath, let url = URL(string: path) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 104, height: 104)
                .clipShape(Circle())
                .opacity(0.72)
                .overlay(
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10), lineWidth: 1)
                )
        } else {
            ProfileUnavailableAvatar(size: 104)
        }
    }

    private func blockedStat(label: String) -> some View {
        VStack(spacing: 4) {
            Text("--")
                .font(.custom("Poppins-Bold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.66))

            Text(label)
                .font(.custom("Poppins-Regular", size: 12))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.42) : .black.opacity(0.38))
        }
        .frame(minWidth: 72)
    }
}
