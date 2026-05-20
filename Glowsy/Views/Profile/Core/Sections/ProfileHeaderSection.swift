import SwiftUI
import Kingfisher
import CoreMotion
import FirebaseAuth

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
    @Binding var showProfileImageFullscreen: Bool // ✅ NUEVO

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
        VStack(spacing: 18) {
            // Avatar hero con efectos adaptativos
            ZStack {
                // Círculo de fondo con gradiente adaptativo
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                ProfileColors.accent.opacity(colorScheme == .dark ? 0.2 : 0.15),
                                ProfileColors.purple.opacity(colorScheme == .dark ? 0.1 : 0.08),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 40,
                            endRadius: 70
                        )
                    )
                    .frame(width: 124, height: 124)
                    .blur(radius: 12)

                // Avatar principal
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
                                            .scaleEffect(1.2)
                                    )
                            }
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                            .contentShape(Circle())
                    } else {
                        // Placeholder cuando no hay imagen
                        Circle()
                            .fill(ProfileColors.materialBackground)
                            .frame(width: 96, height: 96)
                            .overlay(
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(ProfileColors.textTertiary)
                            )
                    }
                }
                .overlay(avatarBorderOverlay())
                .shadow(color: ProfileColors.shadowColor, radius: 15, x: 0, y: 8)

                // Badges adaptativos
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
                            .frame(width: 32, height: 32)

                        Text(primaryBadge.emoji)
                            .font(.system(size: 16))
                    }
                    .offset(x: 38, y: -38)
                    .shadow(color: ProfileColors.shadowColor, radius: 6, x: 0, y: 3)
                }

                // Corona Plus adaptativa (se oculta si hay tema activo o si está desactivado)
                if let currentUser = authService.currentUser,
                   currentUser.isPlusSubscriber,
                   currentUser.showPlusBadge,
                   currentUser.selectedProfileTheme == nil || currentUser.selectedProfileTheme == "default" {
                    ZStack {
                        Circle()
                            .fill(ProfileColors.cardBackground)
                            .frame(width: 28, height: 28)

                        Image(systemName: "crown.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: "FFD700"))
                    }
                    .offset(x: -38, y: -38)
                    .shadow(color: ProfileColors.shadowColor, radius: 6, x: 0, y: 3)
                }

                // Indicador de nivel supporter - OCULTO
                // if let currentUser = authService.currentUser,
                //    currentUser.isSupporter && currentUser.supporterLevel != .none {
                //     SupporterLevelIndicator(level: currentUser.supporterLevel)
                //         .offset(x: 0, y: 65)
                //         .shadow(color: ProfileColors.shadowColor, radius: 4, x: 0, y: 2)
                // }
            }
            .onTapGesture {
                if storyViewModel.hasActiveStory, let userId = Auth.auth().currentUser?.uid {
                    showStoryViewer = true
                    selectedStoryIndex = 0
                } else {
                    // ✅ Si no hay historia, mostrar foto en grande
                    showProfileImageFullscreen = true
                }
            }

            // Información del usuario adaptativa
            VStack(spacing: 8) {
                VStack(spacing: 6) {
                    VerifiedUsernameGradientView(
                        username: viewModel.userProfile?.username ?? "Usuario",
                        isVerified: viewModel.userProfile?.isVerified ?? false,
                        badgeSize: 20,
                        spacing: 6,
                        gradient: LinearGradient(
                            colors: [Color(hex: "007AFF"), Color(hex: "6B73FF")], // ✅ MISMO GRADIENTE QUE USERPROFILEVIEW
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.custom("Poppins-Bold", size: 24))

                    // Badges horizontales adaptativos
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

                // Bio expandible adaptativa
                VStack(spacing: 6) {
                    ExpandableBioView(bio: viewModel.userProfile?.bio ?? "Añade una biografía")

                    // ✅ NUEVO: Link in Bio
                    if let websiteUrl = viewModel.userProfile?.websiteUrl, !websiteUrl.isEmpty,
                       let url = URL(string: websiteUrl.hasPrefix("http") ? websiteUrl : "https://\(websiteUrl)") {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.system(size: 12, weight: .semibold))

                                Text(websiteUrl.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                                    .font(.custom("Poppins-Medium", size: 13))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .foregroundColor(Color(hex: "007AFF")) // Color acento
                            .padding(.vertical, 4)
                        }
                        .padding(.top, 2)
                    }
                }
            }

            // Botones de acción adaptativos
            HStack(spacing: 14) {
                Button(action: {
                    newBio = viewModel.userProfile?.bio ?? ""
                    isShowingEditProfile = true
                }) {
                    HStack(spacing: 7) {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 15))
                        Text("profile.editButton")
                            .font(.custom("Poppins-SemiBold", size: 13))
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .liquidGlass(in: Capsule(), interactive: true)
                }

                // ✅ NUEVO: Botón de compartir perfil (QR)
                Button(action: {
                    showingQRCode = true
                }) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ProfileColors.textPrimary)
                        .frame(width: 40, height: 40)
                        .liquidGlass(in: Circle(), interactive: true)
                }

                // ✅ TEMPORALMENTE OCULTO: Botón de tema del perfil (solo si tiene badges)
                // if let currentUser = authService.currentUser, currentUser.canChangeProfileTheme {
                //     Button(action: {
                //         showingThemeSelector = true
                //     }) {
                //         Image(systemName: "paintbrush.fill")
                //         .font(.system(size: 18))
                //         .foregroundColor(ProfileColors.textPrimary)
                //         .frame(width: 44, height: 44)
                //         .background(ProfileColors.materialBackground)
                //         .clipShape(Circle())
                //         .overlay(
                //         Circle()
                //         .stroke(ProfileColors.borderColor, lineWidth: 1)
                //         )
                //         .shadow(color: ProfileColors.shadowColor, radius: 4, x: 0, y: 2)
                //     }
                // }

                Button(action: { isShowingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                        .foregroundColor(ProfileColors.textPrimary)
                        .frame(width: 40, height: 40)
                        .liquidGlass(in: Circle(), interactive: true)
                }
            }
        }
        .padding(.horizontal, 24)
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
                .font(.custom("Poppins-Bold", size: 9))
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
                .font(.custom("Poppins-Bold", size: 8))
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
    @Binding var showingUserList: ProfileView.UserListType?
    @Binding var showingInterests: Bool
    let interests: [String]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ModernStatsSection(
                viewModel: viewModel,
                showingUserList: $showingUserList,
                embeddedStyle: true
            )

            if !interests.isEmpty {
                Divider()
                    .overlay(ProfileColors.borderColor.opacity(colorScheme == .dark ? 0.22 : 0.4))
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        showingInterests.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("profile.interests.title")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(ProfileColors.textPrimary)

                        Text("\(interests.count)")
                            .font(.custom("Poppins-Medium", size: 11))
                            .foregroundColor(ProfileColors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(ProfileColors.materialBackground.opacity(0.7))
                            .clipShape(Capsule())

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(ProfileColors.textSecondary)
                            .rotationEffect(.degrees(showingInterests ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }

                if showingInterests {
                    ModernInterestsView(
                        interests: interests,
                        showsTitle: false,
                        embeddedStyle: true
                    )
                    .padding(.top, 12)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sección de estadísticas moderna (ARREGLADA)
struct ModernStatsSection: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Binding var showingUserList: ProfileView.UserListType?
    var embeddedStyle: Bool = false
    @Environment(\.colorScheme) var colorScheme

    private var computedStats: [(String, Int, ProfileView.UserListType)] {
        [
            (NSLocalizedString("profile.stats.visits", comment: "Visits"), viewModel.visits.count, .visits),
            (NSLocalizedString("profile.ui.followers", comment: "Followers"), viewModel.admirers.count, .admirers),
            (NSLocalizedString("profile.ui.following", comment: "Following"), viewModel.connections.count, .connections),
            (NSLocalizedString("profile.ui.mutuals", comment: "Mutuals"), viewModel.mutualConnections.count, .mutualConnections)
        ]
    }

    var body: some View {
        HStack(spacing: embeddedStyle ? 0 : 6) {
            ForEach(Array(computedStats.enumerated()), id: \.offset) { index, stat in
                Button(action: {
                    showingUserList = stat.2
                }) {
                    VStack(spacing: 6) {
                        Text("\(stat.1)")
                            .font(.custom("Poppins-Bold", size: 18))
                            .foregroundColor(ProfileColors.textPrimary)

                        Text(stat.0)
                            .font(.custom("Poppins-Medium", size: 11))
                            .foregroundColor(ProfileColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, embeddedStyle ? 10 : 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if embeddedStyle && index < computedStats.count - 1 {
                    Rectangle()
                        .fill(ProfileColors.borderColor.opacity(colorScheme == .dark ? 0.24 : 0.4))
                        .frame(width: 1, height: 30)
                }
            }
        }
        .padding(.horizontal, embeddedStyle ? 2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showingUserList)
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
                    .font(.custom("Poppins-SemiBold", size: 18))
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
                                .font(.custom("Poppins-Medium", size: 14))
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func interestEmoji(for interest: String) -> String {
        return InterestEmojiHelper.emoji(for: interest)
    }
}
