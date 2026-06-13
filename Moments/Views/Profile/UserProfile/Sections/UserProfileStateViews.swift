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

// MARK: - UserModernPrivateProfileView — shell unificado
struct UserModernPrivateProfileView: View {
    let userProfile: AppUser?
    let userId: String
    @ObservedObject var messagingViewModel: MessagingViewModel
    @ObservedObject var viewModel: UserProfileViewModel
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
    let onOpenStories: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                // ── Top bar ──────────────────────────────────────────────
                privateTopBar
                    .padding(.top, 4)

                // ── Avatar + Info (mismo shell que público) ───────────────
                HStack(alignment: .center, spacing: 14) {
                    UserModernAvatar(
                        profileImagePath: userProfile?.profileImagePath,
                        userId: self.userId,
                        onOpenStories: onOpenStories,
                        size: 96,
                        showStoryRing: false
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(userProfile?.username ?? NSLocalizedString("userProfile.user", comment: "User"))
                                .font(.custom("Poppins-Bold", size: 20))
                                .foregroundColor(colorScheme == .dark ? .white : .black)

                            VerifiedBadgeView(userId: self.userId, size: 18)
                        }

                        if let bio = userProfile?.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.54))
                                .lineLimit(3)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                // ── Botones de acción ──────────────────────────────────────
                HStack(spacing: 10) {
                    Button(action: {
                        HapticManager.shared.mediumImpact()
                        onFollowAction()
                    }) {
                        HStack(spacing: 7) {
                            Image(systemName: followButtonIcon)
                                .font(.system(size: 13, weight: .medium))
                            Text(followButtonText)
                                .font(.custom("Poppins-SemiBold", size: 13))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            if followButtonState == .following {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
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
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 13, weight: .semibold))

                            Text(NSLocalizedString("userProfile.sendMessage", comment: "Send message"))
                                .font(.custom("Poppins-SemiBold", size: 13))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .liquidGlass(in: Capsule(), interactive: true)
                    }
                }
                .padding(.horizontal, 20)

                // ── Stats con "--" ──────────────────────────────────────────
                HStack(spacing: 0) {
                    ForEach(Array(privateStats.enumerated()), id: \.offset) { index, stat in
                        VStack(spacing: 3) {
                            Text("--")
                                .font(.custom("Poppins-Bold", size: 17))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.38) : .black.opacity(0.32))
                            Text(stat)
                                .font(.custom("Poppins-Medium", size: 10))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.38) : .black.opacity(0.32))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                        if index < privateStats.count - 1 {
                            Rectangle()
                                .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.12))
                                .frame(width: 1, height: 26)
                        }
                    }
                }
                .padding(.horizontal, 20)

                // ── Contenido de estado: candado ──────────────────────────
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.48) : .black.opacity(0.42))

                    VStack(spacing: 6) {
                        Text(NSLocalizedString("userProfile.private.title", comment: "Private profile title"))
                            .font(.custom("Poppins-Bold", size: 18))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text(NSLocalizedString("userProfile.private.description", comment: "Private profile description"))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.56) : .black.opacity(0.50))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .padding(.bottom, safeAreaBottom + 60)
            }
        }
    }

    private var privateStats: [String] {
        [
            NSLocalizedString("profile.ui.followers", comment: "Followers"),
            NSLocalizedString("profile.ui.following", comment: "Following"),
            NSLocalizedString("profile.ui.mutuals", comment: "Mutuals")
        ]
    }

    private var privateTopBar: some View {
        ZStack {
            Text(userProfile?.username ?? NSLocalizedString("userProfile.user", comment: "User"))
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 36, height: 36)
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)

                Spacer()

                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 20)
    }

    private var followButtonText: String {
        switch followButtonState {
        case .ownProfile: return NSLocalizedString("userProfile.followButton.ownProfile", comment: "Own profile")
        case .blocked: return NSLocalizedString("userProfile.followButton.blocked", comment: "Blocked")
        case .following: return NSLocalizedString("userProfile.followButton.following", comment: "Following")
        case .canFollow: return NSLocalizedString("userProfile.followButton.canFollow", comment: "Follow")
        case .canRequestFollow: return NSLocalizedString("userProfile.followButton.canRequestFollow", comment: "Request follow")
        case .requestPending: return NSLocalizedString("userProfile.followButton.requestPending", comment: "Request sent")
        case .requestPendingCancellable: return NSLocalizedString("userProfile.followButton.cancelRequest", comment: "Cancel request")
        }
    }

    private var followButtonIcon: String {
        switch followButtonState {
        case .ownProfile: return "person.circle.fill"
        case .blocked: return "slash.circle"
        case .following: return "checkmark.circle.fill"
        case .canFollow: return "person.badge.plus"
        case .canRequestFollow: return "envelope.circle"
        case .requestPending: return "clock.circle"
        case .requestPendingCancellable: return "xmark.circle"
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

// MARK: - Usuario no disponible — shell unificado
struct UserModernUnavailableProfileView: View {
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            // ── Top bar ──────────────────────────────────────────────
            ZStack {
                Text("")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 36, height: 36)
                            .liquidGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            // ── Avatar genérico + info placeholder (mismo HStack que el shell) ───
            HStack(alignment: .center, spacing: 14) {
                ProfileUnavailableAvatar(size: 96)

                VStack(alignment: .leading, spacing: 5) {
                    Text(NSLocalizedString("userProfile.unavailable.username", comment: "Unavailable username placeholder"))
                        .font(.custom("Poppins-Bold", size: 20))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.38) : .black.opacity(0.32))

                    Text(NSLocalizedString("userProfile.unavailable.bio", comment: "Unavailable bio placeholder"))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.28) : .black.opacity(0.22))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Spacer()

            // ── Contenido de estado ───────────────────────────────────────
            VStack(spacing: 14) {
                Image(systemName: "person.slash")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.44) : .black.opacity(0.36))

                VStack(spacing: 6) {
                    Text(NSLocalizedString("userProfile.unavailable.title", comment: "Unavailable title"))
                        .font(.custom("Poppins-Bold", size: 20))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString("userProfile.unavailable.description", comment: "Unavailable description"))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.56) : .black.opacity(0.50))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()
            Spacer()
                .frame(height: safeAreaBottom + 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Bloqueado por mí — shell unificado
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                // ── Top bar ──────────────────────────────────────────────
                ZStack {
                    Text(username)
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack {
                        Button(action: onDismiss) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(width: 36, height: 36)
                                .liquidGlass(in: Circle(), interactive: true)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Color.clear.frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)

                // ── Avatar + Info (mismo shell) ───────────────────────────
                HStack(alignment: .center, spacing: 14) {
                    blockedAvatar

                    VStack(alignment: .leading, spacing: 5) {
                        Text(username)
                            .font(.custom("Poppins-Bold", size: 20))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        if let bio = userProfile?.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(bio)
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.54) : .black.opacity(0.48))
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                // ── Stats con "--" ──────────────────────────────────────────
                HStack(spacing: 0) {
                    ForEach(Array(blockedStats.enumerated()), id: \.offset) { index, stat in
                        VStack(spacing: 3) {
                            Text("--")
                                .font(.custom("Poppins-Bold", size: 17))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.38) : .black.opacity(0.32))
                            Text(stat)
                                .font(.custom("Poppins-Medium", size: 10))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.38) : .black.opacity(0.32))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                        if index < blockedStats.count - 1 {
                            Rectangle()
                                .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.12))
                                .frame(width: 1, height: 26)
                        }
                    }
                }
                .padding(.horizontal, 20)

                // ── Contenido de estado: bloqueado ────────────────────────
                VStack(spacing: 14) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.44) : .black.opacity(0.36))

                    VStack(spacing: 6) {
                        Text(NSLocalizedString("userProfile.blockedByMe.title", comment: "Blocked by me title"))
                            .font(.custom("Poppins-Bold", size: 18))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text(NSLocalizedString("userProfile.blockedByMe.description", comment: "Blocked by me description"))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.56) : .black.opacity(0.50))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 34)
                    }

                    Button(action: onUnblock) {
                        Text(NSLocalizedString("userProfile.unblockUser", comment: "Unblock user"))
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .liquidGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.bottom, safeAreaBottom + 40)
            }
        }
    }

    private var blockedStats: [String] {
        [
            NSLocalizedString("profile.ui.followers", comment: "Followers"),
            NSLocalizedString("profile.ui.following", comment: "Following"),
            NSLocalizedString("profile.ui.mutuals", comment: "Mutuals")
        ]
    }

    @ViewBuilder
    private var blockedAvatar: some View {
        if let path = userProfile?.profileImagePath, let url = URL(string: path) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .opacity(0.62)
                .overlay(
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                )
        } else {
            ProfileUnavailableAvatar(size: 96)
        }
    }
}
