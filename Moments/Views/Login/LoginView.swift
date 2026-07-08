import SwiftUI
import FirebaseAuth
import FirebaseMessaging
import FirebaseFirestore
import AuthenticationServices
import CryptoKit

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @State private var showLoginForm = false

    var body: some View {
        NavigationStack {
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
                    WelcomeContent(showLoginForm: $showLoginForm)
                }
            }
            .navigationBarHidden(true)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationDestination(isPresented: $showLoginForm) {
                LoginFormScreen()
            }
            .navigationDestination(isPresented: $authService.isRegistering) {
                ProfileOnboardingView(
                    context: authService.resumingOnboardingContext == .email ? .email : .apple
                )
            }
        }
        // ✅ NUEVO: Observar cambios en el estado de autenticación
        .onChange(of: authService.authState) { _, newState in
        }
    }
}

// MARK: - Welcome (primera pantalla: registro como camino principal)

/// Paleta del glow de bienvenida (colores de marca del logo).
private enum WelcomeGlow {
    static let colors: [Color] = [
        Color(hex: "007AFF"),
        Color(hex: "AF52DE"),
        Color(hex: "FF375F"),
        Color(hex: "02C39A")
    ]

    /// Versión apagada para estados en reposo (mismas familias, casi sin luz).
    static let dimColors: [Color] = [
        Color(hex: "123A5E"),
        Color(hex: "3A2158"),
        Color(hex: "58203A"),
        Color(hex: "12463C")
    ]
}

/// Mesh de colores en movimiento perpetuo (capa base reutilizable).
private struct AuroraMeshLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var colors: [Color] = WelcomeGlow.colors
    var speed: Double = 1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * speed
            SwiftUI.MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5 + 0.2 * Float(sin(t * 0.35)), 0], [1, 0],
                    [0, 0.5 + 0.2 * Float(cos(t * 0.3))],
                    [0.5 + 0.3 * Float(sin(t * 0.55)), 0.5 + 0.3 * Float(cos(t * 0.42))],
                    [1, 0.5 + 0.2 * Float(sin(t * 0.47))],
                    [0, 1], [0.5 + 0.2 * Float(cos(t * 0.38)), 1], [1, 1]
                ],
                colors: [
                    colors[0], colors[1], colors[2],
                    colors[3], colors[1], colors[0],
                    colors[2], colors[0], colors[3]
                ]
            )
        }
        .allowsHitTesting(false)
    }
}

/// Halo mesh animado tras el logo, estilo aurora viva.
private struct WelcomeAuroraHalo: View {
    var body: some View {
        AuroraMeshLayer(speed: 0.8)
            .clipShape(Circle())
            .blur(radius: 38)
            .opacity(0.5)
    }
}

/// CTA burbuja glass con los colores fluyendo por dentro: mesh animado
/// bajo el material Liquid Glass, que lo refracta (sandwich mesh → glass → label).
private struct AuroraGlassButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: LocalizedStringKey
    let action: () -> Void

    @State private var isPressed = false
    private let buttonHeight = AuthFormMetrics.buttonHeight
    @ScaledMetric(relativeTo: .body) private var buttonFontSize = AuthFormMetrics.buttonFontSize

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: buttonFontSize).weight(.semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                .frame(maxWidth: .infinity)
                .frame(minHeight: buttonHeight)
        }
        .background {
            ZStack {
                AuroraMeshLayer()
                    .blur(radius: 10)
                    .opacity(0.92)

                if #available(iOS 26.0, *) {
                    Color.clear
                        .glassEffect(.clear.interactive(), in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .clipShape(shape)
        }
        .overlay {
            shape
                .stroke(.white.opacity(colorScheme == .dark ? 0.22 : 0.34), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .accessibilityLabel(Text(title))
    }
}

struct WelcomeContent: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showLoginForm: Bool
    @State private var goToRegister = false
    @State private var isVisible = false

    private var primaryText: Color {
        AuthColors.primary(colorScheme)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 36)

                    EnhancedHeaderView()
                        .background {
                            WelcomeAuroraHalo()
                                .frame(width: 260, height: 260)
                                .offset(y: -34)
                        }
                        .authScreenContentWidth()
                        .scaleEffect(isVisible ? 1.0 : 0.85)
                        .opacity(isVisible ? 1.0 : 0.0)
                        .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)

                    Spacer(minLength: 28)

                    VStack(spacing: 12) {
                        AuroraGlassButton(
                            title: "welcome.createAccount",
                            action: { goToRegister = true }
                        )

                        AppleContinueButton()

                        Button {
                            showLoginForm = true
                        } label: {
                            HStack(spacing: 5) {
                                Text("welcome.haveAccount")
                                    .font(.subheadline.weight(.regular))
                                    .foregroundColor(primaryText.opacity(0.54))

                                Text("welcome.logIn")
                                    .font(.subheadline.bold())
                                    .foregroundColor(primaryText)
                            }
                            .frame(minHeight: 44)
                        }
                        .padding(.top, 2)
                    }
                    .authScreenContentWidth()
                    .offset(y: isVisible ? 0 : 30)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: isVisible)

                    Spacer(minLength: 24)

                    LoginDisclaimerView()
                        .authScreenContentWidth()
                        .opacity(isVisible ? 1.0 : 0.0)
                        .animation(.easeIn(duration: 0.6).delay(0.5), value: isVisible)
                        .padding(.bottom, 18)
                }
                .frame(minHeight: geometry.size.height)
            }
        }
        .onAppear {
            withAnimation {
                isVisible = true
            }
        }
        .navigationDestination(isPresented: $goToRegister) {
            RegisterView().environmentObject(authService)
        }
    }
}

// MARK: - Login (pantalla propia para usuarios que vuelven)
struct LoginFormScreen: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
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
        ZStack {
            LiquidAuroraBackground()

            VStack(spacing: 0) {
                topBar

                GeometryReader { geometry in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 12)

                            VStack(spacing: 0) {
                                EnhancedHeaderView()
                                    .authScreenContentWidth()
                                    .scaleEffect(isVisible ? 1.0 : 0.85)
                                    .opacity(isVisible ? 1.0 : 0.0)
                                    .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)

                                Spacer()
                                    .frame(height: 12)

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
                                .authScreenContentWidth()
                                .offset(y: isVisible ? 0 : 30)
                                .opacity(isVisible ? 1.0 : 0.0)
                                .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.15), value: isVisible)
                            }

                            Spacer(minLength: 24)
                        }
                        .frame(minHeight: geometry.size.height)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .onAppear {
            withAnimation {
                isVisible = true
            }
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
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AuthColors.primary(colorScheme))
                    .frame(width: 36, height: 36)
                    .background {
                        Color.clear
                            .momentsChromeGlass(in: Circle(), interactive: true)
                    }
            }
            .accessibilityLabel(Text("register.back"))

            Spacer()
        }
        .authScreenHorizontalPadding()
        .padding(.top, 10)
        .padding(.bottom, 2)
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
                    errorMessage = getFailureReason(from: error)
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

// MARK: - Botón "Continuar con Apple" autocontenido (bienvenida)
struct AppleContinueButton: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.colorScheme) private var colorScheme
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAlert = false

    private let buttonHeight = AuthFormMetrics.buttonHeight

    var body: some View {
        SignInWithAppleButton(
            .continue,
            onRequest: { request in
                let nonce = authService.startAppleSignIn()
                request.requestedScopes = [.fullName, .email]
                request.nonce = nonce
            },
            onCompletion: handleCompletion
        )
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: buttonHeight)
        .clipShape(RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous))
        .disabled(isLoading)
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("login.error.title"),
                message: Text(errorMessage ?? NSLocalizedString("login.error.unknown", comment: "Unknown login error")),
                dismissButton: .default(Text("login.ok"))
            )
        }
    }

    private func handleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            guard let nonce = authService.currentNonce else {
                errorMessage = NSLocalizedString("login.apple.error.nonce", comment: "Apple sign in nonce error")
                showAlert = true
                return
            }
            guard let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                errorMessage = NSLocalizedString("login.apple.error.noToken", comment: "Apple sign in token missing")
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
                    if isComplete, let userId = Auth.auth().currentUser?.uid {
                        RealLoginActivityService.shared.recordSuccessfulLogin(userId: userId, method: "apple")
                    }
                case .failure:
                    errorMessage = NSLocalizedString("login.apple.error.generic", comment: "Generic Apple sign in error")
                    showAlert = true
                }
            }
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = NSLocalizedString("login.apple.error.generic", comment: "Generic Apple sign in error")
                showAlert = true
            }
        }
    }
}

// MARK: - Liquid Aurora Background (Moved to LiquidGlassComponents.swift)

// MARK: - Enhanced Header View
struct EnhancedHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .title2) private var heroFontSize: CGFloat = 23.75
    @ScaledMetric(relativeTo: .body) private var logoWidth: CGFloat = 84
    @ScaledMetric(relativeTo: .body) private var logoHeight: CGFloat = 84

    private var primaryText: Color {
        AuthColors.primary(colorScheme)
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(colorScheme == .dark ? "LoginLogo" : "whatsnew")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: logoWidth, height: logoHeight)
                .shadow(color: .white.opacity(0.12), radius: 8, x: 0, y: 0)
                .overlay(
                    Ellipse()
                        .fill(.white.opacity(0.07))
                        .frame(width: 48, height: 22)
                        .blur(radius: 8)
                        .offset(y: -16)
                )

            VStack(spacing: 6) {
                Text("login.hero.title")
                    .font(.system(size: heroFontSize).bold())
                    .foregroundColor(primaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
    }
}
// MARK: - Enhanced Form View
struct EnhancedFormView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var identifier: String
    @Binding var password: String
    @Binding var showPassword: Bool
    @Binding var isLoading: Bool
    @Binding var showResetPassword: Bool
    @Binding var errorMessage: String?
    @Binding var showAlert: Bool
    let loginAction: () -> Void

    @EnvironmentObject var authService: AuthService
    @State private var isPasskeyLoading = false
    @State private var showPasskeyNoCredentialAlert = false
    @State private var goToRegisterFromPasskey = false

    private let buttonHeight = AuthFormMetrics.buttonHeight
    @ScaledMetric(relativeTo: .body) private var buttonFontSize = AuthFormMetrics.buttonFontSize

    private var isAuthInProgress: Bool { isLoading || isPasskeyLoading }

    private var primaryText: Color {
        AuthColors.primary(colorScheme)
    }

    private var authActionTint: Color {
        MomentsChromeGlass.canvasTint(for: colorScheme, opacity: 0.54)
    }

    var body: some View {
        VStack(spacing: 0) {
            loginFormColumn

            LoginDisclaimerView()
                .padding(.top, 10)
        }
        .padding(.bottom, 10)
        .alert("login.passkey.noCredential.title", isPresented: $showPasskeyNoCredentialAlert) {
            Button("login.passkey.noCredential.register") {
                goToRegisterFromPasskey = true
            }
            Button("login.ok", role: .cancel) { }
        } message: {
            Text("login.passkey.error.generic")
        }
        .navigationDestination(isPresented: $goToRegisterFromPasskey) {
            RegisterView().environmentObject(authService)
        }
    }

    private var loginFormColumn: some View {
        VStack(spacing: 8) {
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
                        .font(.footnote.weight(.medium))
                        .foregroundColor(primaryText.opacity(0.58))
                }
            }

            VStack(spacing: 8) {
                EnhancedLoginButton(
                    isLoading: $isLoading,
                    isEnabled: !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty,
                    action: loginAction
                )

                passkeyLoginButton
            }

            EnhancedDividerView()

            SignInWithAppleButton(
                .continue,
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
                                    if isComplete, let userId = Auth.auth().currentUser?.uid {
                                        RealLoginActivityService.shared.recordSuccessfulLogin(userId: userId, method: "apple")
                                    }
                                case .failure(let error):
                                    errorMessage = mapAppleError(error)
                                    showAlert = true
                                }
                            }
                        }
                    case .failure(let error):
                        if (error as NSError).code != 1001 {
                            errorMessage = mapAppleError(error)
                            showAlert = true
                        }
                    }
                }
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: buttonHeight)
            .clipShape(RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous))
            .disabled(isAuthInProgress)

            VStack(spacing: 10) {
                NavigationLink(destination: RegisterView().environmentObject(authService)) {
                    HStack {
                        Text("login.noAccount")
                            .font(.subheadline.weight(.regular))
                            .foregroundColor(primaryText.opacity(0.54))

                        Text("login.register")
                            .font(.subheadline.bold())
                            .foregroundColor(primaryText)
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private var passkeyLoginButton: some View {
        Button(action: loginWithPasskey) {
            HStack(spacing: 8) {
                if isPasskeyLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: primaryText))
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: "faceid")
                        .font(.body.weight(.medium))
                }
                Text("login.passkey")
                    .font(.system(size: buttonFontSize).weight(.semibold))
            }
            .foregroundColor(primaryText)
            .frame(maxWidth: .infinity)
            .frame(minHeight: buttonHeight)
        }
        .background {
            Color.clear
                .momentsChromeGlass(
                    in: RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous),
                    interactive: !isAuthInProgress,
                    tint: authActionTint
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous)
                .stroke(primaryText.opacity(colorScheme == .dark ? 0.14 : 0.12), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .disabled(isAuthInProgress)
    }

    private func loginWithPasskey() {
        isPasskeyLoading = true
        PasskeyService.shared.loginWithPasskey { result in
            DispatchQueue.main.async {
                isPasskeyLoading = false
                switch result {
                case .success(let customToken):
                    authService.signInWithPasskeyToken(customToken) { loginResult in
                        switch loginResult {
                        case .success:
                            if let userId = Auth.auth().currentUser?.uid {
                                RealLoginActivityService.shared.recordSuccessfulLogin(userId: userId, method: "passkey")
                            }
                            errorMessage = nil
                        case .failure(let error):
                            errorMessage = mapPasskeyError(error)
                            showAlert = true
                        }
                    }
                case .failure(let error):
                    if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                        return
                    }
                    showPasskeyNoCredentialAlert = true
                }
            }
        }
    }

    private func mapPasskeyError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.code == ASAuthorizationError.canceled.rawValue {
            return ""
        }
        return NSLocalizedString("login.passkey.error.generic", comment: "Generic passkey login error")
    }

    private func mapAppleError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.code == ASAuthorizationError.canceled.rawValue {
            return ""
        }
        return NSLocalizedString("login.apple.error.generic", comment: "Generic Apple sign in error")
    }
}

struct LoginDisclaimerView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var primaryText: Color {
        AuthColors.primary(colorScheme)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("login.disclaimer.line1")
                .font(.caption.weight(.medium))
                .foregroundColor(primaryText.opacity(0.42))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            (
                Text(NSLocalizedString("login.disclaimer.line2.prefix", comment: "Login disclaimer prefix"))
                    .foregroundColor(primaryText.opacity(0.42))
                + Text("lazynius")
                    .foregroundColor(primaryText.opacity(0.78))
                + Text(NSLocalizedString("login.disclaimer.line2.middle", comment: "Login disclaimer middle"))
                    .foregroundColor(primaryText.opacity(0.42))
                + Text("Moments")
                    .foregroundColor(primaryText.opacity(0.78))
                + Text(NSLocalizedString("login.disclaimer.line2.suffix", comment: "Login disclaimer suffix"))
                    .foregroundColor(primaryText.opacity(0.42))
            )
            .font(.caption.weight(.medium))
            .multilineTextAlignment(.center)
            .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Enhanced Identifier Field (Moved to LiquidGlassComponents.swift)
// MARK: - Enhanced Password Field (Moved to LiquidGlassComponents.swift)

// MARK: - Enhanced Login Button
struct EnhancedLoginButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void
    @State private var isPressed = false

    private let buttonHeight = AuthFormMetrics.buttonHeight
    @ScaledMetric(relativeTo: .body) private var buttonFontSize = AuthFormMetrics.buttonFontSize

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous)
    }

    var body: some View {
        Button(action: {
            // Track login attempt
            if isEnabled {
                action()
            }
        }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.75)
                    Text("login.signingIn")
                        .font(.system(size: buttonFontSize).weight(.semibold))
                        .transition(.opacity)
                } else {
                    Text("login.signIn")
                        .font(.system(size: buttonFontSize).weight(.semibold))
                }
            }
            .foregroundColor(.white.opacity(isEnabled ? 1 : 0.6))
            .shadow(color: .black.opacity(isEnabled ? 0.25 : 0.1), radius: 3, x: 0, y: 1)
            .frame(maxWidth: .infinity)
            .frame(minHeight: buttonHeight)
        }
        .background {
            // En reposo: colores apagados latiendo lento. Encendido: paleta plena (crossfade).
            ZStack {
                AuroraMeshLayer(colors: WelcomeGlow.dimColors, speed: 0.35)
                    .blur(radius: 10)
                    .opacity(colorScheme == .dark ? 0.7 : 0.5)

                AuroraMeshLayer()
                    .blur(radius: 10)
                    .opacity(isEnabled ? 0.92 : 0.0)

                if #available(iOS 26.0, *) {
                    Color.clear
                        .glassEffect(.clear.interactive(), in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .clipShape(shape)
            .animation(.easeInOut(duration: 0.45), value: isEnabled)
        }
        .overlay {
            shape
                .stroke(.white.opacity(isEnabled ? (colorScheme == .dark ? 0.22 : 0.34) : 0.1), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .disabled(isLoading || !isEnabled)
        .scaleEffect(isLoading ? 0.95 : (isPressed ? 0.98 : 1.0))
        .animation(.easeInOut(duration: 0.2), value: isLoading)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .accessibilityLabel(Text("login.signIn"))
    }
}

// MARK: - Enhanced Divider View
struct EnhancedDividerView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var dividerColor: Color {
        (colorScheme == .dark ? Color.white : Color.black).opacity(0.26)
    }

    private var textColor: Color {
        (colorScheme == .dark ? Color.white : Color.black).opacity(0.72)
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, dividerColor, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .layoutPriority(0)

            Text("login.orContinue")
                .font(.footnote.weight(.medium))
                .foregroundColor(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 4)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, dividerColor, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .layoutPriority(0)
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

struct EnhancedAccountVerificationView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isVisible = false

    var body: some View {
        ZStack {
            LiquidAuroraBackground()

            VStack(spacing: 30) {
                Spacer()

                VStack(spacing: 24) {
                    Image(colorScheme == .dark ? "LoginLogo" : "whatsnew")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 112, height: 112)
                        .shadow(color: AuthColors.primary(colorScheme).opacity(0.12), radius: 14, x: 0, y: 10)

                    VStack(spacing: 12) {
                        Text("login.verifyingAccount")
                            .font(.system(size: legacyPoppinsSize(26), weight: .bold))
                            .foregroundColor(AuthColors.primary(colorScheme))
                            .multilineTextAlignment(.center)

                        Text("login.checkingAccountStatus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                }
                .offset(y: isVisible ? 0 : 30)
                .opacity(isVisible ? 1.0 : 0.0)
                .animation(.spring(response: 0.9, dampingFraction: 0.72), value: isVisible)

                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            withAnimation {
                isVisible = true
            }
        }
    }
}

// MARK: - Enhanced Reset Password View
import SwiftUI

struct EnhancedResetPasswordView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var email: String
    @Binding var isPresented: Bool
    @StateObject private var authService = AuthService()
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isVisible = false
    @State private var dismissAfterAlert = false

    private var primaryText: Color {
        AuthColors.primary(colorScheme)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                header
                    .scaleEffect(isVisible ? 1 : 0.96)
                    .opacity(isVisible ? 1 : 0)

                VStack(spacing: 16) {
                    LiquidGlassTextField(
                        icon: "envelope.fill",
                        placeholder: NSLocalizedString("login.email", comment: ""),
                        text: $email,
                        keyboardType: .emailAddress,
                        autocapitalization: .none
                    )
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.7 : 1.0)

                    Button(action: resetPassword) {
                        HStack(spacing: 12) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: primaryText))
                                    .scaleEffect(0.8)
                            } else {
                                Text("login.resetPassword.sendLink")
                                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                                    .foregroundColor(primaryText)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background {
                            Color.clear
                                .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: !isLoading)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AuthColors.subtle(colorScheme, opacity: 0.08))
                                .allowsHitTesting(false)
                        }
                    }
                    .disabled(isLoading)
                    .offset(y: isVisible ? 0 : 30)
                    .opacity(isVisible ? 1 : 0)
                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: isVisible)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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

    private var header: some View {
        ZStack {
            VStack(spacing: 5) {
                Text("login.resetPassword.title")
                    .font(.system(size: legacyPoppinsSize(22), weight: .bold))
                    .foregroundColor(primaryText)

                Text("login.resetPassword.description")
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity)

            HStack {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(primaryText)
                        .frame(width: 38, height: 38)
                        .background {
                            Color.clear
                                .liquidGlass(in: Circle(), interactive: true)
                        }
                }
                .accessibilityLabel(Text("login.close"))

                Spacer()

                Color.clear
                    .frame(width: 38, height: 38)
            }
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
