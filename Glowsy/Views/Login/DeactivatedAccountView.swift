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
            EnhancedBackgroundView()
            
            if authService.isVerifyingAccount {
                EnhancedVerificationOverlay()
            } else {
                EnhancedMainContent(
                    userData: authService.deactivatedUserData,
                    isReactivating: $isReactivating,
                    reactivateAction: reactivateAccount,
                    logoutAction: { authService.logout() },
                    isVisible: $isVisible
                )
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
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

// MARK: - Enhanced Verification Overlay
struct EnhancedVerificationOverlay: View {
    @State private var rotationAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowIntensity: Double = 0.5
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Enhanced loading indicator
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 6)
                        .frame(width: 80, height: 80)
                    
                    // Progress ring with enhanced gradient
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.0, green: 0.66, blue: 0.59),
                                    Color(red: 0.01, green: 0.76, blue: 0.60),
                                    Color(red: 1.0, green: 0.8, blue: 0.44),
                                    Color(red: 0.0, green: 0.66, blue: 0.59)
                                ]),
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(270)
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(rotationAngle))
                        .shadow(color: Color(red: 0.0, green: 0.66, blue: 0.59).opacity(0.5), radius: 10, x: 0, y: 0)
                    
                    // Center icon with particles effect
                    ZStack {
                        // Particle rings
                        ForEach(0..<2, id: \.self) { index in
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                .frame(width: CGFloat(25 + index * 10), height: CGFloat(25 + index * 10))
                                .scaleEffect(pulseScale)
                                .animation(
                                    .easeInOut(duration: 1.5)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.2),
                                    value: pulseScale
                                )
                        }
                        
                        // Main icon
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, Color(red: 0.0, green: 0.66, blue: 0.59).opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .white.opacity(0.5), radius: 5, x: 0, y: 0)
                    }
                }
                
                VStack(spacing: 12) {
                    Text("Reactivando cuenta...")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                    
                    Text("Verificando estado de la cuenta")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 40)
            .background(
                ZStack {
                    // Enhanced glass morphism effect
                    RoundedRectangle(cornerRadius: 32)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 32)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.1),
                                            .white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    
                    // Enhanced border gradient
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.3),
                                    .white.opacity(0.1),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 15)
            .shadow(color: Color(red: 0.0, green: 0.66, blue: 0.59).opacity(0.1), radius: 50, x: 0, y: 25)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 1.0
                pulseScale = 1.1
            }
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
}

// MARK: - Enhanced Main Content
struct EnhancedMainContent: View {
    let userData: AppUser?
    @Binding var isReactivating: Bool
    let reactivateAction: () -> Void
    let logoutAction: () -> Void
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(spacing: 50) {
            Spacer()
            
            EnhancedPausedAccountIcon(isVisible: $isVisible)
            EnhancedTitleSection(isVisible: $isVisible)
            
            if let userData = userData {
                EnhancedUserInfoCard(userData: userData, isVisible: $isVisible)
            }
            
            Spacer()
            
            EnhancedActionButtons(
                isReactivating: $isReactivating,
                reactivateAction: reactivateAction,
                logoutAction: logoutAction,
                isVisible: $isVisible
            )
            
            Spacer()
        }
    }
}

// MARK: - Enhanced Paused Account Icon
struct EnhancedPausedAccountIcon: View {
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowIntensity: Double = 0.3
    @Binding var isVisible: Bool
    
    var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.0, green: 0.66, blue: 0.59).opacity(0.3), .clear],
                        center: .center,
                        startRadius: 60,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .scaleEffect(pulseScale)
                .blur(radius: 20)
            
            // Main background circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.0, green: 0.66, blue: 0.59).opacity(0.2),
                            Color(red: 0.0, green: 0.66, blue: 0.59).opacity(0.1)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)
                .shadow(color: Color(red: 0.0, green: 0.66, blue: 0.59).opacity(glowIntensity), radius: 20, x: 0, y: 0)
                .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 15)
            
            // Icon
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 60, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(red: 0.0, green: 0.66, blue: 0.59).opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .white.opacity(0.5), radius: 10, x: 0, y: 0)
        }
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.1
                glowIntensity = 0.6
            }
        }
    }
}

// MARK: - Enhanced Title Section
struct EnhancedTitleSection: View {
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Cuenta desactivada")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(red: 0.0, green: 0.66, blue: 0.59).opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            
            VStack(spacing: 8) {
                Text("Tu cuenta está temporalmente desactivada.")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                
                Text("Todos tus datos están seguros y se conservarán al reactivar.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
            }
        }
        .padding(.horizontal, 40)
        .offset(y: isVisible ? 0 : 30)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: isVisible)
    }
}

// MARK: - Enhanced User Info Card
struct EnhancedUserInfoCard: View {
    let userData: AppUser
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 15) {
                EnhancedReactivationProfileImageView(userData: userData)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(userData.username)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(userData.email)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                ZStack {
                    // Enhanced glass morphism effect
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.15),
                                            .white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    
                    // Enhanced border gradient
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.3),
                                    .white.opacity(0.1),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
        }
        .padding(.horizontal, 40)
        .offset(y: isVisible ? 0 : 30)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.4), value: isVisible)
    }
}

// MARK: - Enhanced Reactivation Profile Image View
struct EnhancedReactivationProfileImageView: View {
    let userData: AppUser
    @State private var glowIntensity: Double = 0.3
    
    var body: some View {
        ZStack {
            // Background with glow effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.0, green: 0.66, blue: 0.59).opacity(0.2), .clear],
                        center: .center,
                        startRadius: 5,
                        endRadius: 25
                    )
                )
                .frame(width: 60, height: 60)
                .shadow(color: Color(red: 0.0, green: 0.66, blue: 0.59).opacity(glowIntensity), radius: 10, x: 0, y: 0)
            
            if let profileImagePath = userData.profileImagePath, !profileImagePath.isEmpty {
                AsyncImage(url: URL(string: profileImagePath)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "person.fill")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 24))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.6), Color(red: 0.0, green: 0.66, blue: 0.59).opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
            } else {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.system(size: 24))
                    )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
        }
    }
}

// MARK: - Enhanced Action Buttons
struct EnhancedActionButtons: View {
    @Binding var isReactivating: Bool
    let reactivateAction: () -> Void
    let logoutAction: () -> Void
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            EnhancedReactivateButton(
                isReactivating: $isReactivating,
                action: reactivateAction
            )
            
            if !isReactivating {
                EnhancedLogoutButton(action: logoutAction)
            }
        }
        .offset(y: isVisible ? 0 : 30)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.6), value: isVisible)
    }
}

// MARK: - Enhanced Reactivate Button
struct EnhancedReactivateButton: View {
    @Binding var isReactivating: Bool
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isReactivating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.0, green: 0.66, blue: 0.59)))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                }
                
                Text(isReactivating ? "Reactivando..." : "Reactivar mi cuenta")
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(Color(red: 0.0, green: 0.66, blue: 0.59))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(red: 0.0, green: 0.66, blue: 0.59).opacity(0.3), radius: isPressed ? 5 : 15, x: 0, y: isPressed ? 2 : 8)
                .scaleEffect(isPressed ? 0.98 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        )
        .disabled(isReactivating)
        .scaleEffect(isReactivating ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isReactivating)
        .padding(.horizontal, 40)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Enhanced Logout Button
struct EnhancedLogoutButton: View {
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            Text("Usar otra cuenta")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .padding(.vertical, 16)
                .padding(.horizontal, 32)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(isPressed ? 0.15 : 0.1))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .scaleEffect(isPressed ? 0.95 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
                )
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Preview
struct DeactivatedAccountView_Previews: PreviewProvider {
    static var previews: some View {
        DeactivatedAccountView()
            .environmentObject(AuthService())
    }
}
