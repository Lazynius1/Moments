import SwiftUI
import FirebaseAuth

struct SuspendedAccountView: View {
    let reason: String?
    let expiresAt: Date?
    @EnvironmentObject var authService: AuthService
    @State private var showContactForm = false
    @State private var showAppealsStatus = false  // ✅ NUEVO: State para mostrar apelaciones
    @State private var animateShield = false
    @State private var animateWarning = false
    @State private var isVisible = false
    
    var body: some View {
        ZStack {
            EnhancedBackgroundView()
            
            ScrollView {
                VStack(spacing: 40) {
                    Spacer(minLength: 60)
                    
                    EnhancedSuspendedHeader(
                        animateShield: $animateShield,
                        animateWarning: $animateWarning,
                        isVisible: $isVisible
                    )
                    
                    EnhancedSuspensionInfo(
                        reason: reason,
                        expiresAt: expiresAt,
                        isVisible: $isVisible
                    )
                    
                    // ✅ ACTUALIZADO: Botones con estado de apelaciones
                    EnhancedSuspendedActionButtons(
                        showContactForm: $showContactForm,
                        showAppealsStatus: $showAppealsStatus,  // ✅ NUEVO: Pasar binding
                        logoutAction: { authService.logout() },
                        isVisible: $isVisible
                    )
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .sheet(isPresented: $showContactForm) {
            AppealFormView(
                suspensionReason: reason,
                isPresented: $showContactForm
            )
            .environmentObject(authService)
        }
        // ✅ NUEVO: Sheet para mostrar estado de apelaciones
        .sheet(isPresented: $showAppealsStatus) {
            AppealStatusView()
                .environmentObject(authService)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                isVisible = true
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                animateShield = true
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.3)) {
                animateWarning = true
            }
        }
    }
}

// MARK: - Enhanced Suspended Header
struct EnhancedSuspendedHeader: View {
    @Binding var animateShield: Bool
    @Binding var animateWarning: Bool
    @Binding var isVisible: Bool
    @State private var glowIntensity: Double = 0.3
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                // Background glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.orange.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 50,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .blur(radius: 20)
                    .scaleEffect(animateShield ? 1.1 : 1.0)
                
                // Shield background
                Image(systemName: "shield.fill")
                    .font(.system(size: 100, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .white.opacity(glowIntensity), radius: 15, x: 0, y: 0)
                    .scaleEffect(animateShield ? 1.1 : 1.0)
                
                // Warning overlay with enhanced effects
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 70, height: 70)
                        .shadow(color: .orange.opacity(0.5), radius: 10, x: 0, y: 0)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 35, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                }
                .scaleEffect(animateWarning ? 1.2 : 1.0)
            }
            
            VStack(spacing: 16) {
                Text("Cuenta Suspendida")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .orange.opacity(0.8), .red.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    .multilineTextAlignment(.center)
                
                Text("Tu cuenta ha sido temporalmente suspendida")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                    .multilineTextAlignment(.center)
            }
        }
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
        }
    }
}

// MARK: - Enhanced Suspension Info
struct EnhancedSuspensionInfo: View {
    let reason: String?
    let expiresAt: Date?
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            // Razón de la suspensión
            if let reason = reason, !reason.isEmpty {
                EnhancedInfoCard(
                    icon: "doc.text.fill",
                    title: "Motivo de la suspensión",
                    content: reason,
                    color: .orange,
                    delay: 0.2
                )
            }
            
            // Fecha de expiración
            if let expiresAt = expiresAt {
                EnhancedInfoCard(
                    icon: "clock.fill",
                    title: "Tu cuenta será reactivada",
                    content: formatExpirationDate(expiresAt),
                    color: .blue,
                    delay: 0.4
                )
                
                // Enhanced countdown timer
                EnhancedCountdownTimer(expiresAt: expiresAt)
                    .offset(y: isVisible ? 0 : 30)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.6), value: isVisible)
            } else {
                EnhancedInfoCard(
                    icon: "infinity",
                    title: "Suspensión permanente",
                    content: "Contacta con soporte para más información",
                    color: .red,
                    delay: 0.4
                )
            }
            
            // Información adicional
            EnhancedInfoCard(
                icon: "info.circle.fill",
                title: "¿Qué puedes hacer?",
                content: "Si consideras que esta suspensión es un error, puedes enviar una apelación formal. Nuestro equipo revisará tu caso detalladamente.",  // Texto actualizado
                color: .green,
                delay: 0.6
            )
        }
        .padding(.horizontal, 20)
    }
    
    private func formatExpirationDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.string(from: date)
    }
}

// MARK: - Enhanced Info Card Component
struct EnhancedInfoCard: View {
    let icon: String
    let title: String
    let content: String
    let color: Color
    let delay: Double
    @State private var isVisible = false
    @State private var glowIntensity: Double = 0.3
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .shadow(color: color.opacity(glowIntensity), radius: 8, x: 0, y: 0)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(color)
                }
                
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            Text(content)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .padding(24)
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
                                color.opacity(0.4),
                                color.opacity(0.1),
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
        .shadow(color: color.opacity(0.2), radius: 20, x: 0, y: 10)
        .offset(y: isVisible ? 0 : 30)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(delay), value: isVisible)
        .onAppear {
            isVisible = true
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
        }
    }
}

// MARK: - Enhanced Countdown Timer
struct EnhancedCountdownTimer: View {
    let expiresAt: Date
    @State private var timeRemaining: TimeInterval = 0
    @State private var timer: Timer?
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        if timeRemaining > 0 {
            VStack(spacing: 12) {
                Text("Tiempo restante")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                
                HStack(spacing: 24) {
                    EnhancedTimeComponent(value: days, label: "días", color: .blue)
                    EnhancedTimeComponent(value: hours, label: "horas", color: .purple)
                    EnhancedTimeComponent(value: minutes, label: "min", color: .pink)
                }
            }
            .padding(20)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
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
                    
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .scaleEffect(pulseScale)
            .onAppear {
                startTimer()
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.02
                }
            }
            .onDisappear {
                timer?.invalidate()
            }
        }
    }
    
    private var days: Int {
        Int(timeRemaining) / (24 * 3600)
    }
    
    private var hours: Int {
        Int(timeRemaining) % (24 * 3600) / 3600
    }
    
    private var minutes: Int {
        Int(timeRemaining) % 3600 / 60
    }
    
    private func startTimer() {
        updateTimeRemaining()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateTimeRemaining()
        }
    }
    
    private func updateTimeRemaining() {
        timeRemaining = max(0, expiresAt.timeIntervalSinceNow)
        if timeRemaining <= 0 {
            timer?.invalidate()
        }
    }
}

// MARK: - Enhanced Time Component
struct EnhancedTimeComponent: View {
    let value: Int
    let label: String
    let color: Color
    @State private var glowIntensity: Double = 0.3
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.2))
                    .frame(width: 60, height: 50)
                    .shadow(color: color.opacity(glowIntensity), radius: 8, x: 0, y: 0)
                
                Text("\(value)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
        }
    }
}

// MARK: - Enhanced Suspended Action Buttons
struct EnhancedSuspendedActionButtons: View {
    @Binding var showContactForm: Bool
    @Binding var showAppealsStatus: Bool  // ✅ NUEVO: Binding para mostrar apelaciones
    let logoutAction: () -> Void
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // ✅ NUEVO: Botón para ver estado de apelaciones
            EnhancedViewAppealsButton(action: {
                showAppealsStatus = true
            })
            
            EnhancedContactSupportButton(action: {
                showContactForm = true
            })
            
            EnhancedSuspendedLogoutButton(action: logoutAction)
        }
        .padding(.horizontal, 20)
        .offset(y: isVisible ? 0 : 30)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.8), value: isVisible)
    }
}
// MARK: - ✅ NUEVO: Botón para ver estado de apelaciones
struct EnhancedViewAppealsButton: View {
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                Text("Ver Estado de Apelaciones")
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.2, green: 0.4, blue: 0.9),  // Azul
                            Color(red: 0.1, green: 0.6, blue: 0.8)   // Azul turquesa
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: .blue.opacity(0.3), radius: isPressed ? 5 : 15, x: 0, y: isPressed ? 2 : 8)
                .scaleEffect(isPressed ? 0.98 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        )
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Enhanced Contact Support Button
struct EnhancedContactSupportButton: View {
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "scale.3d")  // Cambiar icono a balanza
                    .font(.system(size: 16, weight: .medium))
                Text("Apelar Suspensión")  // Cambiar texto
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.55, green: 0.25, blue: 0.82),  // Cambiar a colores púrpura
                            Color(red: 0.78, green: 0.31, blue: 0.75)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: .purple.opacity(0.3), radius: isPressed ? 5 : 15, x: 0, y: isPressed ? 2 : 8)  // Cambiar sombra
                .scaleEffect(isPressed ? 0.98 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        )
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}


// MARK: - Enhanced Suspended Logout Button
struct EnhancedSuspendedLogoutButton: View {
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.right.square.fill")
                    .font(.system(size: 16, weight: .medium))
                Text("Cerrar Sesión")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.8))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(isPressed ? 0.15 : 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .scaleEffect(isPressed ? 0.98 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        )
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Enhanced Contact Support View
struct EnhancedContactSupportView: View {
    let suspensionReason: String?
    @Binding var isPresented: Bool
    @State private var message: String = ""
    @State private var email: String = ""
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isVisible = false
    
    var body: some View {
        NavigationView {
            ZStack {
                EnhancedBackgroundView()
                
                ScrollView {
                    VStack(spacing: 30) {
                        EnhancedContactSupportHeader()
                            .scaleEffect(isVisible ? 1.0 : 0.8)
                            .opacity(isVisible ? 1.0 : 0.0)
                            .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)
                        
                        VStack(spacing: 24) {
                            EnhancedEmailInputField(email: $email)
                                .offset(y: isVisible ? 0 : 30)
                                .opacity(isVisible ? 1.0 : 0.0)
                                .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: isVisible)
                            
                            EnhancedMessageInputField(message: $message)
                                .offset(y: isVisible ? 0 : 30)
                                .opacity(isVisible ? 1.0 : 0.0)
                                .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.4), value: isVisible)
                            
                            EnhancedSendSupportButton(
                                isLoading: $isLoading,
                                emailIsEmpty: email.isEmpty,
                                messageIsEmpty: message.isEmpty,
                                action: sendMessage
                            )
                            .offset(y: isVisible ? 0 : 30)
                            .opacity(isVisible ? 1.0 : 0.0)
                            .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.6), value: isVisible)
                        }
                        .padding(30)
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
            }
            .navigationBarItems(
                leading: Button("Cancelar") {
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
            
            // Pre-rellenar mensaje con información de la suspensión
            if let reason = suspensionReason {
                message = "Hola, me han suspendido la cuenta por: \"\(reason)\". Creo que es un error porque..."
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Mensaje Enviado"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK")) {
                    if alertMessage.contains("enviado") {
                        isPresented = false
                    }
                }
            )
        }
    }
    
    private func sendMessage() {
        isLoading = true
        
        // Simular envío de mensaje (aquí integrarías tu sistema de soporte)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isLoading = false
            alertMessage = "Tu mensaje ha sido enviado a nuestro equipo de soporte. Te responderemos en un plazo de 24-48 horas."
            showAlert = true
        }
    }
}

// MARK: - Enhanced Contact Support Components
struct EnhancedContactSupportHeader: View {
    @State private var glowIntensity: Double = 0.3
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 30,
                            endRadius: 80
                        )
                    )
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                
                Image(systemName: "envelope.circle.fill")
                    .font(.system(size: 60, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .white.opacity(glowIntensity), radius: 10, x: 0, y: 0)
            }
            
            VStack(spacing: 12) {
                Text("Contactar Soporte")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                
                Text("Explícanos tu situación y revisaremos tu caso")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
            }
        }
        .padding(.top, 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
        }
    }
}

struct EnhancedEmailInputField: View {
    @Binding var email: String
    @State private var isFocused = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("Tu email de contacto")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            TextField("correo@ejemplo.com", text: $email)
                .foregroundColor(.white)
                .font(.system(size: 16))
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
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

struct EnhancedMessageInputField: View {
    @Binding var message: String
    @State private var isFocused = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("Tu mensaje")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(isFocused ? 0.15 : 0.1))
                    .frame(minHeight: 120)
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
                
                if message.isEmpty {
                    Text("Explícanos por qué consideras que la suspensión es incorrecta...")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.system(size: 16))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $message)
                    .foregroundColor(.white)
                    .font(.system(size: 16))
                    .padding(16)
                    .background(Color.clear)
                    .onTapGesture {
                        isFocused = true
                    }
            }
            .frame(minHeight: 120)
        }
    }
}

struct EnhancedSendSupportButton: View {
    @Binding var isLoading: Bool
    let emailIsEmpty: Bool
    let messageIsEmpty: Bool
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Text("Enviar Mensaje")
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
        .disabled(isLoading || emailIsEmpty || messageIsEmpty)
        .opacity((emailIsEmpty || messageIsEmpty) ? 0.6 : 1.0)
        .scaleEffect(isLoading ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Preview
struct SuspendedAccountView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Suspensión temporal
            SuspendedAccountView(
                reason: "Publicación de contenido inapropiado que viola nuestras normas comunitarias",
                expiresAt: Calendar.current.date(byAdding: .day, value: 3, to: Date())
            )
            .environmentObject(AuthService())
            
            // Suspensión permanente
            SuspendedAccountView(
                reason: "Múltiples violaciones graves de las normas de la comunidad",
                expiresAt: nil
            )
            .environmentObject(AuthService())
        }
    }
}
