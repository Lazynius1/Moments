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
        .onChange(of: authService.isVerifyingAccount) { newValue in
            if !newValue && isReactivating {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isReactivating = false
                }
            }
        }
        .onChange(of: authService.authState) { newState in
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

// MARK: - Floating Profile Photo Component
struct FloatingProfilePhoto: View {
    let profileImagePath: String?
    let size: CGFloat
    @State private var glowIntensity: Double = 0.3
    
    var body: some View {
        ZStack {
            if let profilePath = profileImagePath, !profilePath.isEmpty {
                AsyncImage(url: URL(string: profilePath)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.6), .blue.opacity(0.4), .purple.opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 3
                                    )
                            )
                            .shadow(color: .white.opacity(glowIntensity), radius: 10, x: 0, y: 0)
                            .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 0)
                    case .failure(_), .empty:
                        placeholderPhoto
                    @unknown default:
                        placeholderPhoto
                    }
                }
            } else {
                placeholderPhoto
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
        }
    }
    
    private var placeholderPhoto: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.white.opacity(0.15), .white.opacity(0.05)],
                    center: .center,
                    startRadius: 10,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "person.circle.fill")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white.opacity(0.8), .blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: .white.opacity(0.1), radius: 15, x: 0, y: 0)
    }
}

// MARK: - Loading View
struct DeactivationLoadingView: View {
    @State private var rotationAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Loading Spinner
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 6)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.blue, .purple, .pink, .blue]),
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(270)
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(rotationAngle))
                        .shadow(color: .blue.opacity(0.5), radius: 10, x: 0, y: 0)
                    
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(pulseScale)
                }
                
                VStack(spacing: 12) {
                    Text(NSLocalizedString("deactivated.reactivating", value: "Reactivando cuenta...", comment: "Reactivating account title"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(NSLocalizedString("deactivated.verifying", value: "Verificando estado...", comment: "Verifying status"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(40)
            .background(
                LiquidGlassCard(cornerRadius: 32) {
                    Color.clear
                }
            )
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.1
            }
        }
    }
}

// MARK: - Main Content
struct DeactivationContent: View {
    let userData: AppUser?
    @Binding var isReactivating: Bool
    let reactivateAction: () -> Void
    let logoutAction: () -> Void
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Icon Header
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.blue.opacity(0.2), .clear],
                                center: .center,
                                startRadius: 40,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .blur(radius: 20)
                    
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .blue.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.5), radius: 20, x: 0, y: 10)
                }
                
                VStack(spacing: 16) {
                    Text(NSLocalizedString("deactivated.title", value: "Cuenta en Reposo", comment: "Sleeping account title"))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text(NSLocalizedString("deactivated.subtitle", value: "Tu cuenta está desactivada temporalmente pero todos tus datos están seguros.", comment: "Deactivated subtitle"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .lineSpacing(4)
                }
            }
            
            // Floating Profile Photo + User Info
            HStack(spacing: 20) {
                // Floating Profile Photo
                FloatingProfilePhoto(
                    profileImagePath: userData?.profileImagePath,
                    size: 80
                )
                
                // User Info
                VStack(alignment: .leading, spacing: 8) {
                    Text(userData?.username ?? NSLocalizedString("profile.defaultUsername", value: "Usuario", comment: "Default username"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                    
                    if let email = userData?.email {
                        Text(email)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
                    }
                    
                    // Status badge
                    HStack(spacing: 6) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 12))
                        Text(NSLocalizedString("deactivated.status", value: "En pausa", comment: "Account paused status"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.blue.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.blue.opacity(0.6), .purple.opacity(0.4)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Actions
            VStack(spacing: 16) {
                LiquidGlassButton(
                    title: NSLocalizedString("deactivated.reactivate", value: "Reactivar Cuenta", comment: "Reactivate button"),
                    icon: "play.circle.fill",
                    action: reactivateAction,
                    isLoading: isReactivating,
                    gradientColors: [.blue, .purple]
                )
                
                LiquidGlassButton(
                    title: NSLocalizedString("settings.logout", comment: "Logout"),
                    icon: "rectangle.portrait.and.arrow.right",
                    action: logoutAction,
                    style: .secondary
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .offset(y: isVisible ? 0 : 30)
        .opacity(isVisible ? 1.0 : 0.0)
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
