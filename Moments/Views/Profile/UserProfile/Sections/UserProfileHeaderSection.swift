import SwiftUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import CoreMotion
import FirebaseFirestore
import AVKit

struct ProfileVisitorPinnedTopChrome: View {
    @ObservedObject var viewModel: UserProfileViewModel
    let collapseProgress: CGFloat
    let onDismiss: () -> Void
    @Binding var showingQRCode: Bool
    @Binding var showingReportSheet: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var profileShareItem: ProfileShareSheetItem?

    var body: some View {
        StickyChromeBarLayout {
            ProfileChromeIconButton(
                systemName: "chevron.left",
                foregroundColor: UserProfileColors.textPrimary,
                preset: .navigationBack,
                action: onDismiss
            )
        } center: {
            HStack(spacing: 5) {
                Text(viewModel.userProfile?.username ?? NSLocalizedString("userProfile.user", comment: "User"))
                    .font(StickyChromeTitleTypography.font)
                    .foregroundStyle(UserProfileColors.textPrimary)
                    .lineLimit(1)

                if viewModel.userProfile?.isVerified == true {
                    VerifiedBadge(size: 16)
                }
            }
            .opacity(collapseProgress)
            .offset(x: -6 * (1 - collapseProgress))
            .animation(.easeOut(duration: 0.18), value: collapseProgress)
        } trailing: {
            visitorHeaderMenu
        }
        // `item:` evita race del Menu: sheet(isPresented) a veces abre con payload vacío.
        .sheet(item: $profileShareItem) { item in
            ProfileShareSheet(
                profileUserId: item.profileUserId,
                sharedProfileData: item.data,
                onDismiss: { profileShareItem = nil }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var visitorHeaderMenu: some View {
        Menu {
            Button(action: {
                viewModel.toggleMute()
            }) {
                Label(
                    viewModel.isMutedByCurrentUser
                        ? NSLocalizedString("userProfile.relationship.mute.disable", comment: "Unmute")
                        : NSLocalizedString("userProfile.relationship.mute.enable", comment: "Mute"),
                    systemImage: viewModel.isMutedByCurrentUser ? "speaker.wave.2" : "speaker.slash"
                )
            }

            Button(action: {
                if viewModel.isBlockedByCurrentUser {
                    viewModel.unblockUser(userId: viewModel.userId)
                } else {
                    viewModel.blockUser(userId: viewModel.userId)
                }
            }) {
                Label(
                    viewModel.isBlockedByCurrentUser
                        ? NSLocalizedString("userProfile.unblockUser", comment: "Unblock user")
                        : NSLocalizedString("storyContextMenu.block", comment: "Block"),
                    systemImage: "person.slash"
                )
            }

            Button(action: {
                showingReportSheet = true
            }) {
                Label(
                    NSLocalizedString("report.action.user", comment: "Report user"),
                    systemImage: "flag"
                )
            }

            if let user = viewModel.userProfile {
                Button {
                    presentProfileShare(for: user)
                } label: {
                    Label(
                        NSLocalizedString("share.profile.sendInChat", comment: "Send in Moments"),
                        systemImage: "paperplane"
                    )
                }

                ShareLink(item: URL(string: "https://glowsy.app/\(user.username)")!) {
                    Label {
                        Text(NSLocalizedString("qrCode.share", comment: "Share"))
                    } icon: {
                        AttachmentIconView(icon: .share, preset: .shareInline)
                    }
                }
            }

            Button(action: {
                showingQRCode = true
            }) {
                Label("QR", systemImage: "qrcode")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(UserProfileColors.textPrimary)
                .frame(
                    width: MomentsGlassButtonPreset.toolbarAction.controlSize,
                    height: MomentsGlassButtonPreset.toolbarAction.controlSize
                )
                .momentsChromeGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
    }

    private func presentProfileShare(for user: AppUser) {
        let resolvedId = user.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? viewModel.userId
            : user.id
        let isOwnProfile = resolvedId == Auth.auth().currentUser?.uid
        let data = SharedProfilePayloadBuilder.make(
            user: user,
            moments: viewModel.moments,
            canViewContent: viewModel.canViewContent,
            visibleConnectionTypes: viewModel.visibleConnectionTypes,
            isOwnProfile: isOwnProfile,
            fallbackUserId: viewModel.userId
        )
        guard let profileUserId = data["profileUserId"], !profileUserId.isEmpty else { return }
        profileShareItem = ProfileShareSheetItem(profileUserId: profileUserId, data: data)
    }
}

/// Payload identificable para `.sheet(item:)` (evita compartir con dict vacío).
private struct ProfileShareSheetItem: Identifiable {
    let id = UUID()
    let profileUserId: String
    let data: [String: String]
}

struct UserModernProfileHeader: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @ObservedObject var messagingViewModel: MessagingViewModel
    @StateObject private var messageRequestService = MessageRequestService()
    @EnvironmentObject var authService: AuthService // ✅ NUEVO: Para acceder a badges del usuario visitado
    @Binding var navigateToChat: Bool
    @Binding var targetConversation: Conversation?
    @Binding var pendingChatContext: PendingChatContext?
    @Binding var socialConnectionsRoute: SocialConnectionsRoute?
    @Binding var showProfileImageFullscreen: Bool
    let onFollowAction: () -> Void
    let onDismiss: () -> Void
    let onOpenStories: () -> Void
    let storyRingRefreshTrigger: Int
    let usernameCollapseProgress: CGFloat
    @Binding var showingQRCode: Bool
    let chatZoomNamespace: Namespace.ID
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    UserModernAvatarWithBadges(
                        userProfile: viewModel.userProfile,
                        onOpenStories: onOpenStories,
                        storyRingRefreshTrigger: storyRingRefreshTrigger,
                        showProfileImageFullscreen: Binding<Bool>(
                            get: { self.showProfileImageFullscreen },
                            set: { self.showProfileImageFullscreen = $0 }
                        ),
                        size: 96
                    )
                    .frame(width: 96, height: 96)

                    ProfileAvatarNoteView(
                        note: viewModel.userProfile?.profileNote,
                        isEditable: false
                    )
                }
                .frame(width: ProfileAvatarNoteMetrics.columnWidth)

                VStack(alignment: .leading, spacing: 5) {
                    VStack(alignment: .leading, spacing: 3) {
                        VerifiedUsernameGradientView(
                            username: viewModel.userProfile?.username ?? NSLocalizedString("userProfile.user", comment: "User"),
                            isVerified: viewModel.userProfile?.isVerified ?? false,
                            badgeSize: 18,
                            spacing: 5,
                            gradient: LinearGradient(
                                colors: [Color(hex: "007AFF"), Color(hex: "6B73FF")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .font(StickyChromeTitleTypography.font)

                        if let userProfile = viewModel.userProfile {
                            UserProfileBadgesView(userProfile: userProfile)
                        }
                    }
                    .opacity(1 - usernameCollapseProgress)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ProfileIdentityMinYPreferenceKey.self,
                                value: geometry.frame(in: .named("scroll")).minY
                            )
                        }
                    )

                    ExpandableBioView(bio: viewModel.userProfile?.bio ?? NSLocalizedString("userProfile.noBio", comment: "No bio"))

                    if let websiteUrl = viewModel.userProfile?.websiteUrl,
                       !websiteUrl.isEmpty,
                       let url = URL(string: websiteUrl.hasPrefix("http") ? websiteUrl : "https://\(websiteUrl)") {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.system(size: 11, weight: .semibold))

                                Text(
                                    websiteUrl
                                        .replacingOccurrences(of: "https://", with: "")
                                        .replacingOccurrences(of: "http://", with: "")
                                )
                                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            }
                            .foregroundStyle(UserProfileColors.accent)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(action: onFollowAction) {
                    HStack(spacing: 7) {
                        Text(followButtonText)
                            .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        if viewModel.followButtonState == .following {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .momentsChromeGlass(in: Capsule(), interactive: viewModel.followButtonState.isActionable)
                }
                .disabled(!viewModel.followButtonState.isActionable)
                .scaleEffect(viewModel.followButtonState.isActionable ? 1.0 : 0.95)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: viewModel.followButtonState), value: viewModel.followButtonState)

                Button(action: openMessageFlow) {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 13, weight: .semibold))

                        Text(NSLocalizedString("userProfile.sendMessage", comment: "Send message"))
                            .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .momentsChromeGlass(in: Capsule(), interactive: true)
                }
                .matchedTransitionSource(id: "profile-message-chat", in: chatZoomNamespace) { source in
                    source.clipShape(RoundedRectangle(cornerRadius: 22))
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func openMessageFlow() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let targetUser = viewModel.userProfile else { return }

        messagingViewModel.startConversation(with: targetUser, from: currentUserId) { conversation in
            if let conversation {
                targetConversation = conversation
                navigateToChat = true
            } else if messagingViewModel.requiresMessageRequest {
                Task { @MainActor in
                    pendingChatContext = await PendingChatContextFactory.outgoing(
                        to: targetUser,
                        from: currentUserId,
                        followersCountOverride: viewModel.followers.count,
                        momentsCountOverride: viewModel.moments.count
                    )
                }
            }
        }
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
        case .requestPendingCancellable:
            return NSLocalizedString("userProfile.followButton.cancelRequest", comment: "Cancel request")
        }
    }

    private var followButtonColor: Color {
        switch viewModel.followButtonState {
        case .following, .requestPending: return Color.gray.opacity(0.6)
        case .requestPendingCancellable: return Color.orange.opacity(0.8)
        case .canFollow, .canRequestFollow: return UserProfileColors.accent
        case .ownProfile, .blocked: return Color.gray.opacity(0.4)
        }
    }

    private var followButtonIcon: String {
        switch viewModel.followButtonState {
        case .following:
            return "person.fill.checkmark"
        case .canFollow:
            return "person.badge.plus"
        case .canRequestFollow:
            return "person.crop.circle.badge.plus"
        case .requestPending:
            return "clock"
        case .requestPendingCancellable:
            return "xmark.circle"
        case .ownProfile:
            return "person.circle"
        case .blocked:
            return "slash.circle"
        }
    }
}
