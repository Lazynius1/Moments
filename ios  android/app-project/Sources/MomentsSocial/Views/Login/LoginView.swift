import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @State var identifier: String = ""
    @State var password: String = ""
    @State var errorMessage: String? = nil
    @State var showAlert: Bool = false
    @State var isLoading: Bool = false
    @State var showResetPassword: Bool = false
    @State var resetEmail: String = ""
    @State var showPassword: Bool = false
    @State var isVisible = false
    
    var body: some View {
        NavigationView {
            ZStack {
                EnhancedBackgroundView()
                
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
                        Spacer()
                        
                        EnhancedHeaderView()
                            .scaleEffect(isVisible ? 1.0 : 0.8)
                            .opacity(isVisible ? 1.0 : 0.0)
                            .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)
                        
                        EnhancedFormView(
                            identifier: $identifier,
                            password: $password,
                            showPassword: $showPassword,
                            isLoading: $isLoading,
                            showResetPassword: $showResetPassword,
                            loginAction: login
                        )
                        .offset(y: isVisible ? 0 : 50)
                        .opacity(isVisible ? 1.0 : 0.0)
                        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: isVisible)
                        
                        Spacer()
                        
                        // Enhanced floating dots
                        EnhancedFloatingDotsView()
                            .opacity(isVisible ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 1.0).delay(0.4), value: isVisible)
                            .padding(.bottom, 50)
                    }
                }
            }
            // Android: Navigation bar visibility handled natively
            .onAppear {
                withAnimation {
                    isVisible = true
                }
                
                // Track screen view
                AnalyticsService.shared.trackScreenView("LoginView")
                
                // Solicitud de ubicación pospuesta hasta que el usuario use funciones que la requieran
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("login.error.title"),
                    message: Text(errorMessage ?? "Ocurrió un error desconocido"),
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
                        AnalyticsService.shared.trackSuccessfulLogin()
                        errorMessage = nil
                        
                        // ✅ SIMPLIFICADO: Usar el servicio centralizado
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            FCMTokenService.shared.updateFCMToken()
                        }
                    
                case .failure(let error):
                    // ❌ Track failed login
                    let failureReason = getFailureReason(from: error)
                    AnalyticsService.shared.trackFailedLogin(reason: failureReason, email: identifier)
                    
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
            return "User not found"
        case 17009: // FIRAuthErrorCodeWrongPassword
            return "Wrong password"
        case 17010: // FIRAuthErrorCodeUserDisabled
            return "User disabled"
        case 17007: // FIRAuthErrorCodeInvalidEmail
            return "Invalid email"
        case 17020: // FIRAuthErrorCodeNetworkError
            return "Network error"
        case 17026: // FIRAuthErrorCodeWeakPassword
            return "Weak password"
        case 17012: // FIRAuthErrorCodeEmailAlreadyInUse
            return "Email already in use"
        default:
            return "Other"
        }
    }
}

// MARK: - Enhanced Background View
struct EnhancedBackgroundView: View {
    @State var animateGradient = false
    
    var body: some View {
        ZStack {
            // Base animated gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.2, green: 0.1, blue: 0.3),
                    Color(red: 0.1, green: 0.1, blue: 0.2)
                ]),
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: animateGradient)
            
            // Enhanced floating orbs
            ForEach(0..<3, id: \.self) { index in
                EnhancedFloatingOrbView(index: index)
            }
        }
        .onAppear {
            animateGradient = true
        }
    }
}

// MARK: - Enhanced Floating Orb
struct EnhancedFloatingOrbView: View {
    let index: Int
    @State var offset = CGSize.zero
    @State var scale: CGFloat = 1.0
    
    private var orbColor: Color {
        switch index {
        case 0: return Color.blue.opacity(0.3)
        case 1: return Color.purple.opacity(0.3)
        default: return Color.pink.opacity(0.3)
        }
    }
    
    var body: some View {
        Circle()
            .fill(orbColor)
            .frame(width: 200, height: 200)
            .blur(radius: 40)
            .scaleEffect(scale)
            .offset(offset)
            .animation(
                .easeInOut(duration: Double.random(in: 3...6))
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.5),
                value: offset
            )
            .animation(
                .easeInOut(duration: Double.random(in: 2...4))
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.3),
                value: scale
            )
            .onAppear {
                let randomX = CGFloat.random(in: -100...100)
                let randomY = CGFloat.random(in: -150...150)
                offset = CGSize(width: randomX, height: randomY)
                scale = CGFloat.random(in: 0.8...1.2)
            }
    }
}

// MARK: - Enhanced Header View
struct EnhancedHeaderView: View {
    @State var glowIntensity: Double = 0.5
    @State var orbRotation: Double = 0
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                // Enhanced glow effect
                Image("LoginLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 150, height: 150)
                    .shadow(color: .white.opacity(glowIntensity), radius: 15, x: 0, y: 0)
                    .shadow(color: .blue.opacity(0.5), radius: 25, x: 0, y: 0)
                
                // Pelotita naranja removida
            }
            
            // Texto "Moments" removido - solo se muestra el logo
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 1.0
            }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                orbRotation = 360
            }
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
    let loginAction: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            EnhancedIdentifierField(identifier: $identifier)
            EnhancedPasswordField(password: $password, showPassword: $showPassword)
            
            HStack {
                Spacer()
                Button(action: {
                    // Track forgot password interaction
                    AnalyticsService.shared.trackInteraction("forgot_password_tapped")
                    showResetPassword = true
                }) {
                    Text("login.forgotPassword")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            EnhancedLoginButton(isLoading: $isLoading, action: loginAction)
            
            EnhancedDividerView()
            
            NavigationLink(destination: RegisterView()) {
                HStack {
                    Text("login.noAccount")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("login.register")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .onTapGesture {
                // Track register navigation
                AnalyticsService.shared.trackInteraction("register_link_tapped")
            }
        }
        .padding(.horizontal, 32)
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
        .shadow(color: .blue.opacity(0.1), radius: 50, x: 0, y: 25)
        .padding(.horizontal, 20)
    }
}

// MARK: - Enhanced Identifier Field
struct EnhancedIdentifierField: View {
    @Binding var identifier: String
    @State var isFocused = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("login.usernameOrEmail")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            // Usar el inicializador estándar de TextField con placeholder
            TextField("Ingresa tu usuario o email", text: $identifier)
                .foregroundColor(.white)
                .font(.system(size: 16))
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(isFocused ? 0.15 : 0.1))
                        .animation(.easeInOut(duration: 0.2), value: isFocused)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: isFocused ? [.blue.opacity(0.5), .purple.opacity(0.3)] : [.white.opacity(0.2), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: isFocused ? 2 : 1
                        )
                        .animation(.easeInOut(duration: 0.2), value: isFocused)
                )
                // Android: Autocapitalization handled natively
                .onTapGesture {
                    isFocused = true
                }
                .onChange(of: identifier) { _ in
                    if identifier.count == 1 {
                        // Se ha re-incluido la línea de AnalyticsService
                        AnalyticsService.shared.trackInteraction("login_form_started")
                    }
                }
        }
    }
}


// MARK: - Enhanced Password Field
struct EnhancedPasswordField: View {
    @Binding var password: String
    @Binding var showPassword: Bool
    @State var isFocused = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("login.password")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            HStack {
                if showPassword {
                    // Usar el inicializador estándar de TextField con placeholder
                    TextField("Ingresa tu contraseña", text: $password)
                        .foregroundColor(.white)
                } else {
                    // Usar el inicializador estándar de SecureField con placeholder
                    SecureField("Ingresa tu contraseña", text: $password)
                        .foregroundColor(.white)
                }
                
                Button(action: {
                    showPassword.toggle()
                    // AnalyticsService.shared.trackInteraction("password_visibility_toggled", details: ["show": showPassword]) // Eliminado si no está definido
                }) {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.system(size: 16))
                }
            }
            // Eliminar el modificador .placeholder de aquí
            .font(.system(size: 16))
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(isFocused ? 0.15 : 0.1))
                    .animation(.easeInOut(duration: 0.2), value: isFocused)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: isFocused ? [.blue.opacity(0.5), .purple.opacity(0.3)] : [.white.opacity(0.2), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: isFocused ? 2 : 1
                    )
                    .animation(.easeInOut(duration: 0.2), value: isFocused)
            )
            .onTapGesture {
                isFocused = true
            }
        }
    }
}

// MARK: - Enhanced Login Button
struct EnhancedLoginButton: View {
    @Binding var isLoading: Bool
    let action: () -> Void
    @State var isPressed = false
    
    var body: some View {
        Button(action: {
            // Track login attempt
            AnalyticsService.shared.trackInteraction("login_button_tapped")
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
            .frame(height: 56)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.25, green: 0.35, blue: 0.82),
                            Color(red: 0.78, green: 0.31, blue: 0.75)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: .blue.opacity(0.3), radius: isPressed ? 5 : 15, x: 0, y: isPressed ? 2 : 8)
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
    @State var animationPhase: [Bool] = [false, false, false]
    
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
    @State var rotationAngle: Double = 0
    @State var pulseScale: CGFloat = 1.0
    @State var glowIntensity: Double = 0.5
    @State var isVisible = false
    
    var body: some View {
        ZStack {
            // Enhanced background similar to LoginView
            EnhancedBackgroundView()
            
            VStack(spacing: 50) {
                Spacer()
                
                // Enhanced logo and title
                VStack(spacing: 24) {
                    ZStack {
                        Image("LoginLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 150, height: 150)
                            .shadow(color: .white.opacity(glowIntensity), radius: 15, x: 0, y: 0)
                            .shadow(color: .blue.opacity(0.5), radius: 25, x: 0, y: 0)
                            .scaleEffect(pulseScale)
                        
                        // Pelotita naranja removida
                    }
                    
                    // Texto "Moments" removido - solo se muestra el logo
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
                .shadow(color: .blue.opacity(0.1), radius: 50, x: 0, y: 25)
                .offset(y: isVisible ? 0 : 50)
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

// MARK: - Enhanced Reset Password View
struct EnhancedResetPasswordView: View {
    @Binding var email: String
    @Binding var isPresented: Bool
    @StateObject var authService = AuthService()
    @State var isLoading = false
    @State var showAlert = false
    @State var alertMessage = ""
    @State var isVisible = false
    
    var body: some View {
        NavigationView {
            ZStack {
                EnhancedBackgroundView()
                
                VStack(spacing: 40) {
                    Spacer()
                    
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
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .scaleEffect(isVisible ? 1.0 : 0.8)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)
                    
                    VStack(spacing: 24) {
                        TextField("Correo electrónico", text: $email)
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                            // Android: Keyboard type and autocapitalization handled natively
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        
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
                            .frame(height: 56)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.25, green: 0.35, blue: 0.82),
                                            Color(red: 0.78, green: 0.31, blue: 0.75)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 8)
                        )
                        .disabled(isLoading)
                        .scaleEffect(isLoading ? 0.95 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isLoading)
                    }
                    .padding(.horizontal, 32)
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
                    .shadow(color: .blue.opacity(0.1), radius: 50, x: 0, y: 25)
                    .padding(.horizontal, 20)
                    .offset(y: isVisible ? 0 : 50)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: isVisible)
                    
                    Spacer()
                }
            }
            // Android: Navigation bar items handled natively
            // .navigationBarItems(...) - unavailable in macOS/Android
        }
        .onAppear {
            withAnimation {
                isVisible = true
            }
            
            // Track password reset screen view
            AnalyticsService.shared.trackScreenView("ResetPasswordView")
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("login.info.title"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK")) {
                    if alertMessage.contains("enviado") {
                        // Track successful password reset request
                        AnalyticsService.shared.trackInteraction("password_reset_email_sent", details: ["email": email])
                        isPresented = false
                    }
                }
            )
        }
    }
    
    private func resetPassword() {
        // Track password reset attempt
        AnalyticsService.shared.trackInteraction("password_reset_attempted", details: ["email": email])
        
        isLoading = true
        authService.resetPassword(email: email) { result in
            isLoading = false
            switch result {
            case .success:
                alertMessage = "Se ha enviado un enlace de recuperación a tu correo."
            case .failure(let error):
                // Track password reset failure
                AnalyticsService.shared.trackInteraction("password_reset_failed", details: ["error": error.localizedDescription])
                alertMessage = error.localizedDescription
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
