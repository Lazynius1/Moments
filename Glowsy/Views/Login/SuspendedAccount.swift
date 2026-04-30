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
            LiquidAuroraBackground()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 34) {
                    Spacer(minLength: 72)
                    
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
                    
                    Spacer(minLength: 34)
                }
            }
        }
        .sheet(isPresented: $showContactForm) {
            AppealFormView(
                suspensionReason: reason,
                isPresented: $showContactForm
            )
            .environmentObject(authService)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // ✅ NUEVO: Sheet para mostrar estado de apelaciones
        .sheet(isPresented: $showAppealsStatus) {
            AppealStatusView()
                .environmentObject(authService)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
    @Environment(\.colorScheme) private var colorScheme
    @Binding var animateShield: Bool
    @Binding var animateWarning: Bool
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 44, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(AuthColors.primary(colorScheme))
            
            VStack(spacing: 12) {
                Text(NSLocalizedString("suspended.title", comment: "Suspended Account"))
                    .font(.custom("Poppins-Bold", size: 30))
                    .foregroundColor(AuthColors.primary(colorScheme))
                    .multilineTextAlignment(.center)
                
                Text(NSLocalizedString("suspended.subtitle", comment: "Account temporarily suspended"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 28)
        .scaleEffect(isVisible ? 1.0 : 0.92)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)
    }
}

// MARK: - Enhanced Suspension Info
struct EnhancedSuspensionInfo: View {
    @Environment(\.colorScheme) private var colorScheme
    let reason: String?
    let expiresAt: Date?
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            if let reason = reason, !reason.isEmpty {
                SuspendedInfoRow(
                    icon: "doc.text",
                    title: NSLocalizedString("suspended.reason", comment: "Suspension reason"),
                    message: reason
                )
            }
            
            if let expiresAt = expiresAt {
                SuspendedInfoRow(
                    icon: "clock",
                    title: NSLocalizedString("suspended.expires", comment: "Account will be reactivated"),
                    message: formatExpirationDate(expiresAt)
                )
                
                EnhancedCountdownTimer(expiresAt: expiresAt)
                    .offset(y: isVisible ? 0 : 30)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.6), value: isVisible)
            } else {
                SuspendedInfoRow(
                    icon: "infinity",
                    title: NSLocalizedString("suspended.permanent", comment: "Permanent suspension"),
                    message: NSLocalizedString("suspended.permanentMessage", comment: "Contact support message")
                )
            }
            
            SuspendedInfoRow(
                icon: "info.circle",
                title: NSLocalizedString("suspended.whatCanDo", comment: "What can you do"),
                message: NSLocalizedString("suspended.whatCanDoMessage", comment: "Appeal information")
            )
        }
        .padding(.horizontal, 24)
    }
    
    private func formatExpirationDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: date)
    }
}

private struct SuspendedInfoRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(AuthColors.primary(colorScheme))
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AuthColors.primary(colorScheme))

                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(5)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Enhanced Countdown Timer
struct EnhancedCountdownTimer: View {
    @Environment(\.colorScheme) private var colorScheme
    let expiresAt: Date
    @State private var timeRemaining: TimeInterval = 0
    @State private var timer: Timer?
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        if timeRemaining > 0 {
            VStack(spacing: 14) {
                Text(NSLocalizedString("suspended.timeRemaining", comment: "Time remaining"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                
                HStack(spacing: 12) {
                    EnhancedTimeComponent(value: days, label: NSLocalizedString("suspended.days", comment: "days"))
                    EnhancedTimeComponent(value: hours, label: NSLocalizedString("suspended.hours", comment: "hours"))
                    EnhancedTimeComponent(value: minutes, label: NSLocalizedString("suspended.minutes", comment: "minutes"))
                }
            }
            .padding(18)
            .background(
                Color.clear
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .onAppear {
                startTimer()
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
    @Environment(\.colorScheme) private var colorScheme
    let value: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundColor(AuthColors.primary(colorScheme))
                .monospacedDigit()
                .frame(width: 58, height: 42)
            
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.7))
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
        VStack(spacing: 12) {
            LiquidGlassButton(
                title: NSLocalizedString("suspended.viewAppeals", comment: "View appeals status"),
                icon: "doc.text.magnifyingglass",
                action: { showAppealsStatus = true },
                style: .secondary
            )
            
            LiquidGlassButton(
                title: NSLocalizedString("suspended.appeal", comment: "Appeal suspension"),
                icon: "envelope",
                action: { showContactForm = true }
            )
            
            LiquidGlassButton(
                title: NSLocalizedString("suspended.logout", comment: "Sign out"),
                icon: "rectangle.portrait.and.arrow.right",
                action: { logoutAction() },
                style: .secondary
            )
        }
        .padding(.horizontal, 20)
        .offset(y: isVisible ? 0 : 30)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.8), value: isVisible)
    }
}

// MARK: - Enhanced Contact Support View
struct EnhancedContactSupportView: View {
    @Environment(\.colorScheme) private var colorScheme
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
                LiquidAuroraBackground()
                
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
                            Color.clear
                                .liquidGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
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
                .foregroundColor(AuthColors.primary(colorScheme))
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
    @Environment(\.colorScheme) private var colorScheme
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
                            colors: [AuthColors.primary(colorScheme), AuthColors.secondary(colorScheme, opacity: 0.62)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: AuthColors.primary(colorScheme).opacity(glowIntensity * 0.18), radius: 10, x: 0, y: 0)
            }
            
            VStack(spacing: 12) {
                Text("Contactar Soporte")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(AuthColors.primary(colorScheme))
                
                Text("Explícanos tu situación y revisaremos tu caso")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                    .multilineTextAlignment(.center)
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
    @Environment(\.colorScheme) private var colorScheme
    @Binding var email: String
    @State private var isFocused = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                
                Text("Tu email de contacto")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
            }
            
            TextField("correo@ejemplo.com", text: $email)
                .foregroundColor(AuthColors.primary(colorScheme))
                .font(.system(size: 16))
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding(16)
                .background(
                    Color.clear
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                        .animation(.easeInOut(duration: 0.2), value: isFocused)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AuthColors.primary(colorScheme).opacity(isFocused ? 0.28 : 0.12),
                                    .clear
                                ],
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
    @Environment(\.colorScheme) private var colorScheme
    @Binding var message: String
    @State private var isFocused = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                
                Text("Tu mensaje")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
            }
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.clear)
                    .frame(minHeight: 120)
                    .background {
                        Color.clear
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        AuthColors.primary(colorScheme).opacity(isFocused ? 0.28 : 0.12),
                                        .clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: isFocused ? 2 : 1
                            )
                            .animation(.easeInOut(duration: 0.2), value: isFocused)
                    )
                
                if message.isEmpty {
                    Text("Explícanos por qué consideras que la suspensión es incorrecta...")
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.52))
                        .font(.system(size: 16))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $message)
                    .foregroundColor(AuthColors.primary(colorScheme))
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
    @Environment(\.colorScheme) private var colorScheme
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
                        .progressViewStyle(CircularProgressViewStyle(tint: AuthColors.primary(colorScheme)))
                        .scaleEffect(0.8)
                } else {
                    Text("Enviar Mensaje")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AuthColors.primary(colorScheme))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .background(
            Color.clear
                .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: !(emailIsEmpty || messageIsEmpty))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AuthColors.subtle(colorScheme, opacity: isPressed ? 0.14 : 0.08))
                        .allowsHitTesting(false)
                }
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
            // Suspensión corta (3 días)
            SuspendedAccountView(
                reason: "Publicación de contenido sensible sin la etiqueta de advertencia correspondiente. Por favor, revisa nuestras normas sobre contenido sensible.",
                expiresAt: Calendar.current.date(byAdding: .day, value: 3, to: Date())
            )
            .environmentObject(AuthService())
            .previewDisplayName("3 días - Contenido Sensible")
            
            // Suspensión media (7 días)
            SuspendedAccountView(
                reason: "Comportamiento spam detectado: envío masivo de mensajes no solicitados a otros usuarios. Segunda advertencia.",
                expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date())
            )
            .environmentObject(AuthService())
            .previewDisplayName("7 días - Spam")
            
            // Suspensión larga (30 días)
            SuspendedAccountView(
                reason: "Acoso reiterado hacia otros usuarios y uso de lenguaje ofensivo. Violación seria de nuestras normas comunitarias.",
                expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date())
            )
            .environmentObject(AuthService())
            .previewDisplayName("30 días - Acoso")
            
            // Suspensión permanente
            SuspendedAccountView(
                reason: "Múltiples violaciones graves de las normas de la comunidad incluyendo contenido inapropiado, acoso persistente y evasión de suspensiones previas.",
                expiresAt: nil
            )
            .environmentObject(AuthService())
            .previewDisplayName("Permanente")
            
            // Suspensión sin razón específica
            SuspendedAccountView(
                reason: nil,
                expiresAt: Calendar.current.date(byAdding: .hour, value: 12, to: Date())
            )
            .environmentObject(AuthService())
            .previewDisplayName("Sin razón - 12 horas")
        }
    }
}
