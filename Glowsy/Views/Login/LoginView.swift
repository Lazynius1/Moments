import SwiftUI
import FirebaseAuth
import FirebaseMessaging
import FirebaseFirestore
import AuthenticationServices
import CryptoKit

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @State private var identifier: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String? = nil
    @State private var showAlert: Bool = false
    @State private var isLoading: Bool = false
    @State private var showResetPassword: Bool = false
    @State private var resetEmail: String = ""
    @State private var showPassword: Bool = false
    @State private var isVisible = false
    
    var body: some View {
        NavigationView {
            ZStack {
                LiquidAuroraBackground()
                
                // ✅ LÓGICA DE ESTADOS CORREGIDA PARA RESPETAR EL FLUJO DE REGISTRO
                if authService.isVerifyingAccount && !authService.isRegistering {
                    // Solo mostrar verificación si NO estamos registrando
                    EnhancedAccountVerificationView()
                } else if case .suspended(let reason, let expiresAt) = authService.authState {
                    // ✅ NUEVO: Mostrar pantalla de suspensión
                    SuspendedAccountView(reason: reason, expiresAt: expiresAt)
                } else if authService.isAccountDeactivated {
                    // Mostrar pantalla de cuenta desactivada solo cuando no se está verificando
                    DeactivatedAccountView()
                } else {
                    // Formulario de login normal
                    VStack(spacing: 0) {
                        Spacer(minLength: 44)

                        VStack(spacing: 0) {
                            EnhancedHeaderView()
                                .scaleEffect(isVisible ? 1.0 : 0.8)
                                .opacity(isVisible ? 1.0 : 0.0)
                                .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)
                            
                            Spacer()
                                .frame(height: 24)
                            
                            EnhancedFormView(
                                identifier: $identifier,
                                password: $password,
                                showPassword: $showPassword,
                                isLoading: $isLoading,
                                showResetPassword: $showResetPassword,
                                errorMessage: $errorMessage,
                                showAlert: $showAlert,
                                loginAction: login
                            )
                            .offset(y: isVisible ? 0 : 30)
                            .opacity(isVisible ? 1.0 : 0.0)
                            .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: isVisible)
                        }

                        Spacer(minLength: 28)
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                withAnimation {
                    isVisible = true
                }
                
                // Track screen view
                
                // Solicitud de ubicación pospuesta hasta que el usuario use funciones que la requieran
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("login.error.title"),
                    message: Text(errorMessage ?? NSLocalizedString("login.error.unknown", comment: "Unknown login error")),
                    dismissButton: .default(Text("login.ok"))
                )
            }
            .sheet(isPresented: $showResetPassword) {
                EnhancedResetPasswordView(email: $resetEmail, isPresented: $showResetPassword)
            }
        }
        // ✅ NUEVO: Observar cambios en el estado de autenticación
        .onChange(of: authService.authState) { newState in
        }
    }
    
    private func login() {
        isLoading = true
        authService.login(identifier: identifier, password: password) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                    case .success:
                        if let userId = Auth.auth().currentUser?.uid {
                            RealLoginActivityService.shared.recordSuccessfulLogin(userId: userId, method: "email")
                        }
                        errorMessage = nil
                        
                        // ✅ SIMPLIFICADO: Usar el servicio centralizado
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            FCMTokenService.shared.updateFCMToken()
                        }
                    
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
    
    // Helper method to categorize login failures
    private func getFailureReason(from error: Error) -> String {
        let errorCode = (error as NSError).code
        
        switch errorCode {
        case 17011: // FIRAuthErrorCodeUserNotFound
            return NSLocalizedString("login.error.reason.userNotFound", comment: "User not found")
        case 17009: // FIRAuthErrorCodeWrongPassword
            return NSLocalizedString("login.error.reason.wrongPassword", comment: "Wrong password")
        case 17010: // FIRAuthErrorCodeUserDisabled
            return NSLocalizedString("login.error.reason.userDisabled", comment: "User disabled")
        case 17007: // FIRAuthErrorCodeInvalidEmail
            return NSLocalizedString("login.error.reason.invalidEmail", comment: "Invalid email")
        case 17020: // FIRAuthErrorCodeNetworkError
            return NSLocalizedString("login.error.reason.network", comment: "Network error")
        case 17026: // FIRAuthErrorCodeWeakPassword
            return NSLocalizedString("login.error.reason.weakPassword", comment: "Weak password")
        case 17012: // FIRAuthErrorCodeEmailAlreadyInUse
            return NSLocalizedString("login.error.reason.emailInUse", comment: "Email already in use")
        default:
            return NSLocalizedString("login.error.reason.other", comment: "Other reason")
        }
    }
}

// MARK: - Liquid Aurora Background (Moved to LiquidGlassComponents.swift)

// MARK: - Enhanced Header View
struct EnhancedHeaderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("LoginLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 84, height: 84)
                .shadow(color: .white.opacity(0.12), radius: 8, x: 0, y: 0)
                .overlay(
                    Ellipse()
                        .fill(.white.opacity(0.07))
                        .frame(width: 48, height: 22)
                        .blur(radius: 8)
                        .offset(y: -16)
                )
        }
    }
}
// MARK: - Enhanced Form View
struct EnhancedFormView: View {
    @Binding var identifier: String
    @Binding var password: String
    @Binding var showPassword: Bool
    @Binding var isLoading: Bool
    @Binding var showResetPassword: Bool
    @Binding var errorMessage: String?
    @Binding var showAlert: Bool
    let loginAction: () -> Void
    
    @EnvironmentObject var authService: AuthService
    
    var body: some View {
        VStack(spacing: 18) {
            LiquidGlassTextField(
                icon: "person.fill",
                placeholder: NSLocalizedString("login.usernameOrEmail", comment: ""),
                text: $identifier,
                keyboardType: .emailAddress
            )
            LiquidGlassSecureField(
                icon: "lock.fill",
                placeholder: NSLocalizedString("login.password", comment: ""),
                text: $password,
                isVisible: $showPassword
            )

            HStack {
                Spacer()

                Button(action: {
                    showResetPassword = true
                }) {
                    Text("login.forgotPassword")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.58))
                }
            }

            VStack(spacing: 12) {
                EnhancedLoginButton(isLoading: $isLoading, action: loginAction)

                SignInWithAppleButton(
                    .signIn,
                    onRequest: { request in
                        let nonce = authService.startAppleSignIn()
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = nonce
                    },
                    onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                guard let nonce = authService.currentNonce else {
                                    errorMessage = NSLocalizedString("login.apple.error.nonce", comment: "Apple sign in nonce error")
                                    showAlert = true
                                    return
                                }

                                guard let appleIDToken = appleIDCredential.identityToken else {
                                    errorMessage = NSLocalizedString("login.apple.error.noToken", comment: "Apple sign in token missing")
                                    showAlert = true
                                    return
                                }

                                guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                                    errorMessage = NSLocalizedString("login.apple.error.invalidToken", comment: "Apple sign in invalid token")
                                    showAlert = true
                                    return
                                }

                                isLoading = true
                                authService.signInWithApple(
                                    idToken: idTokenString,
                                    nonce: nonce,
                                    fullName: appleIDCredential.fullName?.formatted(),
                                    email: appleIDCredential.email
                                ) { result in
                                    isLoading = false
                                    switch result {
                                    case .success(let isComplete):
                                        if !isComplete {
                                        } else {
                                            if let userId = Auth.auth().currentUser?.uid {
                                                RealLoginActivityService.shared.recordSuccessfulLogin(userId: userId, method: "apple")
                                            }
                                        }
                                    case .failure(let error):
                                        errorMessage = error.localizedDescription
                                        showAlert = true
                                    }
                                }
                            }
                        case .failure(let error):
                            if (error as NSError).code != 1001 {
                                errorMessage = error.localizedDescription
                                showAlert = true
                            }
                        }
                    }
                )
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .cornerRadius(25)
                .padding(.top, 2)
            }

            VStack(spacing: 10) {
                NavigationLink(destination: RegisterView()) {
                    HStack {
                        Text("login.noAccount")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.white.opacity(0.54))
                        
                        Text("login.register")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.top, 6)

            LoginDisclaimerView()
                .padding(.top, 14)
        }
            // ✅ CHANGE: Use NavigationLink instead of fullScreenCover to avoid sheet dismissal issues
            // This pushes the view onto the navigation stack, which feels more integrated and
            // avoids the "flash of login" when dismissing a sheet before replacing the root view.
            .background(
                NavigationLink(
                    destination: SocialProfileCompletionView(),
                    isActive: $authService.isRegistering,
                    label: { EmptyView() }
                )
            )

        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }
}

struct LoginDisclaimerView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("login.disclaimer.line1")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            (
                Text(NSLocalizedString("login.disclaimer.line2.prefix", comment: "Login disclaimer prefix"))
                    .foregroundColor(.white.opacity(0.42))
                + Text("lazynius")
                    .foregroundColor(.white.opacity(0.78))
                + Text(NSLocalizedString("login.disclaimer.line2.middle", comment: "Login disclaimer middle"))
                    .foregroundColor(.white.opacity(0.42))
                + Text("Moments")
                    .foregroundColor(.white.opacity(0.78))
                + Text(NSLocalizedString("login.disclaimer.line2.suffix", comment: "Login disclaimer suffix"))
                    .foregroundColor(.white.opacity(0.42))
            )
            .font(.system(size: 12, weight: .medium))
            .multilineTextAlignment(.center)
            .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }
}

// MARK: - Enhanced Identifier Field (Moved to LiquidGlassComponents.swift)
// MARK: - Enhanced Password Field (Moved to LiquidGlassComponents.swift)

// MARK: - Enhanced Login Button
struct EnhancedLoginButton: View {
    @Binding var isLoading: Bool
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            // Track login attempt
            action()
        }) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Text("login.signIn")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.2, green: 0.4, blue: 0.9),
                            Color(red: 0.7, green: 0.3, blue: 0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .blue.opacity(0.2), radius: isPressed ? 4 : 10, x: 0, y: isPressed ? 2 : 5)
                .scaleEffect(isPressed ? 0.98 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        )
        .disabled(isLoading)
        .scaleEffect(isLoading ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Enhanced Divider View
struct EnhancedDividerView: View {
    var body: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.3), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
            
                            Text("login.or")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 8)
            
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.3), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Enhanced Floating Dots
struct EnhancedFloatingDotsView: View {
    @State private var animationPhase: [Bool] = [false, false, false]
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.8), .white.opacity(0.3)],
                            center: .center,
                            startRadius: 1,
                            endRadius: 6
                        )
                    )
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationPhase[index] ? 1.5 : 0.8)
                    .opacity(animationPhase[index] ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: animationPhase[index]
                    )
            }
        }
        .onAppear {
            for index in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.2) {
                    animationPhase[index] = true
                }
            }
        }
    }
}

// ✅ ENHANCED: AccountVerificationView with better animation
struct EnhancedAccountVerificationView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var rotationAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowIntensity: Double = 0.5
    @State private var isVisible = false
    
    var body: some View {
        ZStack {
            // Enhanced background similar to LoginView
            LiquidAuroraBackground()
            
            VStack(spacing: 50) {
                Spacer()
                
                // Enhanced logo
                VStack(spacing: 24) {
                    Image("LoginLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .shadow(color: .white.opacity(glowIntensity * 0.5), radius: 10, x: 0, y: 0)
                        .scaleEffect(pulseScale)
                }
                .scaleEffect(isVisible ? 1.0 : 0.8)
                .opacity(isVisible ? 1.0 : 0.0)
                .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)
                
                // Enhanced loading indicator
                VStack(spacing: 32) {
                    // Enhanced spinner
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
                                        Color(red: 0.25, green: 0.35, blue: 0.82),
                                        Color(red: 0.78, green: 0.31, blue: 0.75),
                                        Color(red: 1.0, green: 0.8, blue: 0.44),
                                        Color(red: 0.25, green: 0.35, blue: 0.82)
                                    ]),
                                    center: .center,
                                    startAngle: .degrees(-90),
                                    endAngle: .degrees(270)
                                ),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(rotationAngle))
                            .shadow(color: .blue.opacity(0.5), radius: 10, x: 0, y: 0)
                        
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
                            Image(systemName: "sparkles")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, .blue.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .white.opacity(0.5), radius: 5, x: 0, y: 0)
                        }
                    }
                    
                    VStack(spacing: 12) {
                        Text("login.verifyingAccount")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                        
                        Text("login.checkingAccountStatus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 40)
                .background(
                    ZStack {
                        // Liquid Glass Effect
                        RoundedRectangle(cornerRadius: 28)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 28)
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.05), .clear],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                        
                        // Liquid Border
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    }
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
                .offset(y: isVisible ? 0 : 30)
                .opacity(isVisible ? 1.0 : 0.0)
                .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: isVisible)
                
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            withAnimation {
                isVisible = true
            }
            
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

// MARK: - Enhanced Reset Password View
import SwiftUI

struct EnhancedResetPasswordView: View {
    @Binding var email: String
    @Binding var isPresented: Bool
    @StateObject private var authService = AuthService()
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isVisible = false
    @State private var dismissAfterAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                LiquidAuroraBackground()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    // Logo and Title Section
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [.blue.opacity(0.3), .purple.opacity(0.1)],
                                        center: .center,
                                        startRadius: 10,
                                        endRadius: 50
                                    )
                                )
                                .frame(width: 100, height: 100)
                                .blur(radius: 20)
                            
                            Image(systemName: "lock.rotation")
                                .font(.system(size: 60, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, .blue.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .white.opacity(0.5), radius: 10, x: 0, y: 0)
                        }
                        
                        VStack(spacing: 12) {
                            Text("login.resetPassword.title")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                            
                            Text("login.resetPassword.description")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    }
                    .scaleEffect(isVisible ? 1.0 : 0.8)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)
                    
                    // 1. Standalone Input Pill (Social Media Style)
                    LiquidGlassTextField(
                        icon: "envelope.fill",
                        placeholder: NSLocalizedString("login.usernameOrEmail", comment: ""),
                        text: $email,
                        keyboardType: .emailAddress,
                        autocapitalization: .none
                    )
                    .disabled(isLoading)
                    .padding(.horizontal, 8) // Adding slight padding correction if needed compared to original which had padding on HStack
                    .opacity(isLoading ? 0.7 : 1.0)
                    
                    // 2. Standalone Action Block
                    Button(action: resetPassword) {
                        HStack(spacing: 12) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("login.resetPassword.sendLink")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .blue.opacity(0.2), radius: 10, x: 0, y: 5)
                        )
                    }
                    .disabled(isLoading)
                    .padding(.horizontal, 24)
                    .offset(y: isVisible ? 0 : 30)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: isVisible)
                    
                    Spacer()
                }
            }
            .navigationBarItems(
                leading: Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                    isPresented = false
                }
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .medium))
            )
        }
        .onAppear {
            withAnimation {
                isVisible = true
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("login.info.title"),
                message: Text(alertMessage),
                dismissButton: .default(Text("login.ok")) {
                    if dismissAfterAlert {
                        isPresented = false
                    }
                }
            )
        }
    }
    
    private func resetPassword() {
        isLoading = true
        authService.resetPassword(email: email) { result in
            isLoading = false
            switch result {
            case .success:
                alertMessage = NSLocalizedString("login.resetPassword.success", comment: "Reset password success message")
                dismissAfterAlert = true
            case .failure(let error):
                alertMessage = error.localizedDescription
                dismissAfterAlert = false
            }
            showAlert = true
        }
    }
}

// MARK: - Preview
struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(AuthService())
    }
}
