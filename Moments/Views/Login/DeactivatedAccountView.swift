import SwiftUI
import FirebaseAuth

struct DeactivatedAccountView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.colorScheme) var colorScheme
    @State private var isReactivating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isVisible = false
    
    var body: some View {
        ZStack {
            LiquidAuroraBackground()
            
            if authService.isVerifyingAccount {
                DeactivationLoadingView()
            } else {
                DeactivationContent(
                    userData: authService.deactivatedUserData,
                    isReactivating: $isReactivating,
                    reactivateAction: reactivateAccount,
                    logoutAction: { authService.logout() },
                    isVisible: $isVisible
                )
            }
        }
        .alert(NSLocalizedString("login.error.title", comment: "Error"), isPresented: $showError) {
            Button(NSLocalizedString("login.ok", comment: "OK")) {
                isReactivating = false
            }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: authService.isVerifyingAccount) { _, newValue in
            if !newValue && isReactivating {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isReactivating = false
                }
            }
        }
        .onChange(of: authService.authState) { _, newState in
            if newState == .authenticated {
                isReactivating = false
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                isVisible = true
            }
        }
    }
    
    private func reactivateAccount() {
        isReactivating = true
        
        authService.reactivateAccount { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    break
                case .failure(let error):
                    isReactivating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Loading View
struct DeactivationLoadingView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            LiquidAuroraBackground()
            
            VStack(spacing: 10) {
                VStack(spacing: 12) {
                    Text(NSLocalizedString("deactivated.reactivating", value: "Reactivando cuenta...", comment: "Reactivating account title"))
                        .font(.system(size: legacyPoppinsSize(24), weight: .bold))
                        .foregroundColor(AuthColors.primary(colorScheme))
                    
                    Text(NSLocalizedString("deactivated.verifying", value: "Verificando estado...", comment: "Verifying status"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                }
            }
        }
    }
}

// MARK: - Main Content
struct DeactivationContent: View {
    @Environment(\.colorScheme) private var colorScheme
    let userData: AppUser?
    @Binding var isReactivating: Bool
    let reactivateAction: () -> Void
    let logoutAction: () -> Void
    @Binding var isVisible: Bool

    @ScaledMetric(relativeTo: .title) private var titleIconSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title) private var titleFontSize: CGFloat = 28.5
    @ScaledMetric(relativeTo: .body) private var subtitleFontSize: CGFloat = 15
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    VStack(spacing: 28) {
                        VStack(spacing: 14) {
                            Image(systemName: "moon.stars")
                                .font(.system(size: titleIconSize).weight(.medium))
                                .foregroundColor(AuthColors.primary(colorScheme))

                            Text(NSLocalizedString("deactivated.title", value: "Cuenta en Reposo", comment: "Sleeping account title"))
                                .font(.system(size: titleFontSize).bold())
                                .foregroundColor(AuthColors.primary(colorScheme))

                            Text(NSLocalizedString("deactivated.subtitle", value: "Tu cuenta está desactivada temporalmente pero todos tus datos están seguros.", comment: "Deactivated subtitle"))
                                .font(.system(size: subtitleFontSize).weight(.medium))
                                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }

                        userCard
                    }

                    Spacer(minLength: 24)

                    VStack(spacing: 12) {
                        LiquidGlassButton(
                            title: NSLocalizedString("deactivated.reactivate", value: "Reactivar Cuenta", comment: "Reactivate button"),
                            icon: "play.fill",
                            action: reactivateAction,
                            isLoading: isReactivating
                        )

                        LiquidGlassButton(
                            title: NSLocalizedString("settings.logout", comment: "Logout"),
                            icon: "rectangle.portrait.and.arrow.right",
                            action: logoutAction,
                            style: .secondary
                        )
                    }
                    .padding(.bottom, 30)
                }
                .authScreenContentWidth()
                .frame(minHeight: geometry.size.height)
            }
        }
        .offset(y: isVisible ? 0 : 30)
        .opacity(isVisible ? 1.0 : 0.0)
    }

    private var userCard: some View {
        DeactivatedProfileCard(
            profileImagePath: userData?.profileImagePath,
            username: userData?.username ?? NSLocalizedString("profile.defaultUsername", value: "Usuario", comment: "Default username"),
            email: userData?.email
        )
    }
}

private struct DeactivatedProfileCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let profileImagePath: String?
    let username: String
    let email: String?

    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 340
    @ScaledMetric(relativeTo: .title3) private var usernameFontSize: CGFloat = 23
    @ScaledMetric(relativeTo: .footnote) private var emailFontSize: CGFloat = 13

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                profileImage
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                VStack {
                    Spacer()

                    Rectangle()
                        .fill(.regularMaterial)
                        .frame(height: proxy.size.height * 0.38)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black.opacity(0.55), location: 0.28),
                                    .init(color: .black, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                LinearGradient(
                    colors: [
                        .clear,
                        (colorScheme == .dark ? Color.black : Color.white).opacity(0.1),
                        (colorScheme == .dark ? Color.black : Color.white).opacity(0.42)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(username)
                                .font(.system(size: usernameFontSize).bold())
                                .foregroundColor(AuthColors.primary(colorScheme))
                                .lineLimit(1)

                            if let email {
                                Text(email)
                                    .font(.system(size: emailFontSize).weight(.medium))
                                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.68))
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        statusBadge
                    }
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .frame(height: cardHeight)
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(AuthColors.subtle(colorScheme, opacity: 0.14), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.1), radius: 24, x: 0, y: 14)
    }

    @ViewBuilder
    private var profileImage: some View {
        if let profileImagePath, !profileImagePath.isEmpty {
            AsyncImage(url: URL(string: profileImagePath)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    placeholderImage
                @unknown default:
                    placeholderImage
                }
            }
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        ZStack {
            AuthColors.subtle(colorScheme, opacity: 0.08)

            Image(systemName: "person.crop.square")
                .font(.system(size: 44, weight: .medium))
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.48))
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "pause.fill")
                .font(.system(size: 10, weight: .bold))
            Text(NSLocalizedString("deactivated.status", value: "En pausa", comment: "Account paused status"))
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(AuthColors.primary(colorScheme))
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background {
            Color.clear
                .liquidGlass(in: Capsule(), interactive: true)
        }
    }
}

// MARK: - Preview
struct DeactivatedAccountView_Previews: PreviewProvider {
    static var previews: some View {
        let authService = AuthService()
        let mockUser = AppUser(
            id: "mock_user_123",
            username: "lazynius",
            email: "lazy@example.com",
            interests: ["Coding", "Design"],
            isPlusSubscriber: true,
            profileImagePath: nil,
            bio: "iOS Developer & Designer",
            blockedUsers: [],
            isPrivate: false,
            activeHoursStart: nil,
            activeHoursEnd: nil,
            notificationPreferences: nil,
            bestFriends: [],
            isActive: false,
            deactivatedAt: Date(),
            deactivatedBy: "user",
            ownedBadges: [],
            plusSubscription: nil
        )
        authService.deactivatedUserData = mockUser
        
        return DeactivatedAccountView()
            .environmentObject(authService)
    }
}
