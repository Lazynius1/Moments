import SwiftUI
import Kingfisher
import CoreMotion
import FirebaseAuth

struct ProfileOwnPinnedTopChrome: View {
    let username: String
    let isVerified: Bool
    let collapseProgress: CGFloat
    @Binding var isShowingSettings: Bool
    @Binding var showingQRCode: Bool
    @Binding var isShowingIncognito: Bool
    let isIncognitoActive: Bool
    let profileZoomNamespace: Namespace.ID

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        StickyChromeBarLayout {
            Color.clear
                .frame(width: ProfileChromeGlassMetrics.controlSize, height: ProfileChromeGlassMetrics.controlSize)
        } center: {
            HStack(spacing: 5) {
                Text(username)
                    .font(StickyChromeTitleTypography.font)
                    .foregroundColor(ProfileColors.textPrimary)
                    .lineLimit(1)

                if isVerified {
                    VerifiedBadge(size: 16)
                }
            }
            .opacity(collapseProgress)
            .scaleEffect(0.96 + (collapseProgress * 0.04))
            .animation(.easeOut(duration: 0.18), value: collapseProgress)
            .allowsHitTesting(false)
        } trailing: {
            ProfileChromeControlsCluster {
                ProfileChromeIconButton(
                    systemName: "bell",
                    foregroundColor: ProfileColors.textPrimary,
                    standaloneGlass: false,
                    action: {
                        NotificationCenter.default.post(name: NSNotification.Name("ShowNotifications"), object: nil)
                    }
                )

                ownHeaderMenu
            }
        }
    }

    private var ownHeaderMenu: some View {
        Menu {
            Button {
                showingQRCode = true
            } label: {
                Label("QR", systemImage: "qrcode")
            }

            Button {
                isShowingIncognito = true
            } label: {
                Label(
                    NSLocalizedString("incognito.title", comment: "Incognito mode"),
                    systemImage: isIncognitoActive ? "eye.slash.fill" : "eye"
                )
            }

            Button {
                isShowingSettings = true
            } label: {
                Label(NSLocalizedString("settings.title", comment: "Settings"), systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ProfileColors.textPrimary)
                .frame(width: ProfileChromeGlassMetrics.controlSize, height: ProfileChromeGlassMetrics.controlSize)
                .contentShape(Circle())
                .matchedTransitionSource(id: "settings-view", in: profileZoomNamespace)
        }
    }
}

struct ModernProfileHeader: View {
    @ObservedObject var viewModel: ProfileViewModel
    @ObservedObject var storyViewModel: StoryViewModel
    @EnvironmentObject var authService: AuthService
    @Binding var isShowingSettings: Bool
    @Binding var isShowingEditProfile: Bool
    @Binding var newBio: String
    @Binding var showStoryViewer: Bool
    @Binding var selectedStoryIndex: Int
    @Binding var showingThemeSelector: Bool
    @Binding var showingQRCode: Bool
    @Binding var showProfileImageFullscreen: Bool
    @Binding var isShowingIncognito: Bool
    let isIncognitoActive: Bool
    let profileZoomNamespace: Namespace.ID
    let usernameCollapseProgress: CGFloat

    @Environment(\.colorScheme) var colorScheme

    private var storyCount: Int {
        guard let userId = Auth.auth().currentUser?.uid else { return 0 }
        return storyViewModel.stories[userId]?.count ?? 0
    }

    private var storyViewedStatus: [Bool] {
        guard let userId = Auth.auth().currentUser?.uid,
              let userStories = storyViewModel.stories[userId] else {
            return []
        }

        // Para historias propias, siempre están "vistas" (iluminadas)
        return userStories.map { _ in true }
    }

    private var storyAudiences: [String?] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        return storyViewModel.stories[userId]?.map { $0.audience } ?? []
    }

    private var isOwnStory: Bool {
        return true // Siempre es el perfil propio
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    compactAvatar
                        .onTapGesture {
                            if storyViewModel.hasActiveStory, Auth.auth().currentUser?.uid != nil {
                                showStoryViewer = true
                                selectedStoryIndex = 0
                            } else {
                                showProfileImageFullscreen = true
                            }
                        }

                    ProfileAvatarNoteView(
                        note: viewModel.userProfile?.profileNote,
                        isEditable: true,
                        onSave: { note in
                            viewModel.updateProfileNote(note)
                        }
                    )
                }
                .frame(width: ProfileAvatarNoteMetrics.columnWidth)

                VStack(alignment: .leading, spacing: 5) {
                    VStack(alignment: .leading, spacing: 3) {
                        VerifiedUsernameGradientView(
                            username: viewModel.userProfile?.username ?? "Usuario",
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

                        if let currentUser = authService.currentUser,
                           (currentUser.isPlusSubscriber || currentUser.isSupporter) {
                            HStack(spacing: 6) {
                                if currentUser.isPlusSubscriber,
                                   currentUser.showPlusBadge,
                                   currentUser.selectedProfileTheme == nil || currentUser.selectedProfileTheme == "default" {
                                    PlusBadgeInline()
                                }

                                if let primaryBadge = currentUser.primaryBadge {
                                    SupportBadgeInline(badge: primaryBadge)
                                }
                            }
                            .animation(.easeInOut(duration: 0.3), value: currentUser.isPlusSubscriber)
                            .animation(.easeInOut(duration: 0.3), value: currentUser.primaryBadge?.id)
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

                    ExpandableBioView(bio: viewModel.userProfile?.bio ?? "Añade una biografía")

                    if let websiteUrl = viewModel.userProfile?.websiteUrl, !websiteUrl.isEmpty,
                       let url = URL(string: websiteUrl.hasPrefix("http") ? websiteUrl : "https://\(websiteUrl)") {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.system(size: 11, weight: .semibold))

                                Text(websiteUrl.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .foregroundColor(Color(hex: "007AFF"))
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            // Fila de acción: botón Editar Perfil
            ownProfileActionRow
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    private var ownProfileActionRow: some View {
        HStack(spacing: 10) {
            Button {
                newBio = viewModel.userProfile?.bio ?? ""
                isShowingEditProfile = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                    Text(NSLocalizedString("profile.editButton", comment: "Edit profile"))
                        .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                }
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .momentsChromeGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: "edit-profile-view", in: profileZoomNamespace)
        }
    }

    private var compactAvatar: some View {
        ZStack {
            Group {
                if let profileImagePath = viewModel.userProfile?.profileImagePath, let url = URL(string: profileImagePath) {
                    KFImage(url)
                        .placeholder {
                            Circle()
                                .fill(ProfileColors.materialBackground)
                                .frame(width: 96, height: 96)
                                .overlay(
                                    ProgressView()
                                        .tint(ProfileColors.accent)
                                        .scaleEffect(1.1)
                                )
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                        .contentShape(Circle())
                } else {
                    Circle()
                        .fill(ProfileColors.materialBackground)
                        .frame(width: 96, height: 96)
                        .overlay(
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 56))
                                .foregroundColor(ProfileColors.textTertiary)
                        )
                }
            }
            .overlay(avatarBorderOverlay())
            .shadow(color: ProfileColors.shadowColor, radius: 12, x: 0, y: 6)

            if let currentUser = authService.currentUser,
               let primaryBadge = currentUser.primaryBadge {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: primaryBadge.swiftUIColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 29, height: 29)

                    Text(primaryBadge.emoji)
                        .font(.system(size: 14))
                }
                .offset(x: 37, y: -36)
                .shadow(color: ProfileColors.shadowColor, radius: 5, x: 0, y: 2)
            }

            if let currentUser = authService.currentUser,
               currentUser.isPlusSubscriber,
               currentUser.showPlusBadge,
               currentUser.selectedProfileTheme == nil || currentUser.selectedProfileTheme == "default" {
                ZStack {
                    Circle()
                        .fill(ProfileColors.cardBackground)
                        .frame(width: 26, height: 26)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "FFD700"))
                }
                .offset(x: -37, y: -36)
                .shadow(color: ProfileColors.shadowColor, radius: 5, x: 0, y: 2)
            }
        }
        .frame(width: 96, height: 96)
        .background {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            ProfileColors.accent.opacity(colorScheme == .dark ? 0.16 : 0.12),
                            ProfileColors.purple.opacity(colorScheme == .dark ? 0.08 : 0.05),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 36,
                        endRadius: 66
                    )
                )
                .frame(width: 118, height: 118)
                .blur(radius: 10)
                .allowsHitTesting(false)
        }
    }
    // Border inteligente del avatar adaptativo (SIN BORDE VERDE)
    @ViewBuilder
    private func avatarBorderOverlay() -> some View {
        let currentUser = authService.currentUser

        if storyViewModel.hasActiveStory {
            StorySegmentedRing(
                storyCount: storyCount,
                hasStory: storyViewModel.hasActiveStory,
                hasUnseenStory: false, // Propias siempre iluminadas
                storyViewedStatus: storyViewedStatus,
                storyAudiences: storyAudiences,
                isOwnStory: isOwnStory,
                colorScheme: colorScheme,
                ringSize: 96,
                lineWidth: 3
            )
        } else if currentUser?.isPlusSubscriber == true && currentUser?.showPlusBadge == true {
            Circle()
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [Color(hex: "FFD700"), Color(hex: "FFA500")]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
        }
    }
}

// ✅ NUEVO: Plus Badge Inline
struct PlusBadgeInline: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)

                            Text("profile.plus")
                .font(.system(size: legacyPoppinsSize(9), weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
        .shadow(color: Color(hex: "FFD700").opacity(0.3), radius: 3, x: 0, y: 1)
    }
}

// ✅ NUEVO: Support Badge Inline
struct SupportBadgeInline: View {
    let badge: UserBadge

    var body: some View {
        HStack(spacing: 4) {
            Text(badge.emoji)
                .font(.system(size: 10))

            Text(badge.name.uppercased())
                .font(.system(size: legacyPoppinsSize(8), weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: badge.swiftUIColors,
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
        .shadow(color: badge.swiftUIColors.first?.opacity(0.3) ?? .clear, radius: 3, x: 0, y: 1)
    }
}


struct ProfileOverviewCard: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Binding var socialConnectionsRoute: SocialConnectionsRoute?
    @Binding var showingInterests: Bool
    let interests: [String]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModernStatsSection(
                viewModel: viewModel,
                socialConnectionsRoute: $socialConnectionsRoute,
                embeddedStyle: true
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)

            if !interests.isEmpty {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        showingInterests.toggle()
                    }
                }) {
                    HStack(spacing: 10) {
                        Text("profile.interests.title")
                            .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                            .foregroundColor(ProfileColors.textPrimary)

                        Text("· \(interests.count)")
                            .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                            .foregroundColor(ProfileColors.textSecondary)

                        if !showingInterests, let firstInterest = interests.first {
                            Text(firstInterest)
                                .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                                .foregroundColor(ProfileColors.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(ProfileColors.textSecondary)
                            .rotationEffect(.degrees(showingInterests ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 12)

                if showingInterests {
                    ModernInterestsView(
                        interests: interests,
                        showsTitle: false,
                        embeddedStyle: true
                    )
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

// MARK: - Sección de estadísticas moderna (ARREGLADA)
struct ModernStatsSection: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Binding var socialConnectionsRoute: SocialConnectionsRoute?
    var embeddedStyle: Bool = false
    @Environment(\.colorScheme) var colorScheme

    private var computedStats: [(String, Int, ProfileView.UserListType)] {
        [
            (NSLocalizedString("profile.stats.visits", comment: "Visits"), viewModel.groupedVisits.count, .visits),
            (NSLocalizedString("profile.ui.followers", comment: "Followers"), viewModel.followers.count, .followers),
            (NSLocalizedString("profile.ui.following", comment: "Following"), viewModel.following.count, .following),
            (NSLocalizedString("profile.ui.mutuals", comment: "Mutuals"), viewModel.mutuals.count, .mutuals)
        ]
    }

    var body: some View {
        HStack(spacing: embeddedStyle ? 0 : 6) {
            ForEach(Array(computedStats.enumerated()), id: \.offset) { index, stat in
                Button(action: {
                    socialConnectionsRoute = SocialConnectionsRoute(initialTab: stat.2.socialTab)
                }) {
                    VStack(spacing: 4) {
                        Text("\(stat.1)")
                            .font(.system(size: legacyPoppinsSize(embeddedStyle ? 17 : 18), weight: .bold))
                            .foregroundColor(ProfileColors.textPrimary)

                        Text(stat.0)
                            .font(.system(size: legacyPoppinsSize(embeddedStyle ? 10 : 11), weight: .medium))
                            .foregroundColor(ProfileColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, embeddedStyle ? 8 : 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if embeddedStyle && index < computedStats.count - 1 {
                    Rectangle()
                        .fill(ProfileColors.borderColor.opacity(colorScheme == .dark ? 0.24 : 0.4))
                        .frame(width: 1, height: 26)
                }
            }
        }
        .padding(.horizontal, embeddedStyle ? 2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: socialConnectionsRoute)
    }
}

// MARK: - Vista de intereses
struct ModernInterestsView: View {
    let interests: [String]
    var showsTitle: Bool = true
    var embeddedStyle: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsTitle {
                Text("profile.interests.title")
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundColor(ProfileColors.textPrimary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(interests, id: \.self) { interest in
                        let emoji = interestEmoji(for: interest)

                        HStack(spacing: 6) {
                            Text(emoji)
                                .font(.system(size: 16))
                            Text(interest)
                                .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                                .foregroundColor(ProfileColors.textPrimary)
                        }
                        .padding(.horizontal, embeddedStyle ? 14 : 16)
                        .padding(.vertical, embeddedStyle ? 9 : 10)
                        .background(embeddedStyle ? ProfileColors.materialBackground.opacity(0.62) : ProfileColors.cardBackground)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(ProfileColors.borderColor.opacity(embeddedStyle ? 0.18 : 0), lineWidth: embeddedStyle ? 1 : 0)
                        )
                        .shadow(color: ProfileColors.shadowColor, radius: embeddedStyle ? 0 : 4, x: 0, y: embeddedStyle ? 0 : 2)
                    }
                }
                .padding(.horizontal, embeddedStyle ? 20 : 0)
            }
            .scrollClipDisabled(embeddedStyle)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func interestEmoji(for interest: String) -> String {
        return InterestEmojiHelper.emoji(for: interest)
    }
}
