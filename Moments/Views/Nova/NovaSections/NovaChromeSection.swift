import SwiftUI
import UIKit

// MARK: - Header Mejorado con Memoria
struct NovaHeader: View {
    @ObservedObject var viewModel: NovaAgent
    @Binding var showConversationHistory: Bool
    @Binding var showSuggestedOptions: Bool
    @Binding var isShowingMemory: Bool
    @Environment(\.colorScheme) var colorScheme

    // ✨ ESTADOS PARA EASTER EGG
    @State private var logoTapCount = 0
    @State private var showDeveloperEasterEgg = false
    @State private var lastTapTime = Date()
    @State private var logoScale: CGFloat = 1.0
    @State private var logoPulse = false

    private var subtitleText: String {
        NSLocalizedString("nova.chrome.subtitle", comment: "Nova header subtitle")
    }

    var body: some View {
        HStack {
            ZStack {
                NovaBrandIcon(size: 22, color: NovaColors.textPrimary)
                    .scaleEffect(logoScale * (logoPulse ? 1.06 : 1.0))
            }
            .frame(width: 40, height: 40)
            .background {
                Color.clear
                    .liquidGlass(in: Circle(), interactive: true)
            }
            .onTapGesture {
                handleLogoTap()
            }
            .alert("nova.easterEgg.title", isPresented: $showDeveloperEasterEgg) {
                Button("nova.easterEgg.primaryButton") {
                    resetEasterEgg()
                }
                Button(NSLocalizedString("nova.easterEgg.thanksButton", comment: "Thank you Álvaro button")) {
                    resetEasterEgg()
                    triggerDeveloperAppreciation()
                }
            } message: {
                Text(NSLocalizedString("nova.easterEgg.message", comment: "Easter egg message about Álvaro"))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("nova.name")
                    .font(.custom("Poppins-Bold", size: 20))
                    .foregroundColor(NovaColors.textPrimary)

                Text(subtitleText)
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(NovaColors.textSecondary)
            }

            Spacer()

            // Botones de acción
            HStack(spacing: 8) {
                // Botón de memoria
                Button(action: { isShowingMemory = true }) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(NovaColors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background {
                            Color.clear
                                .liquidGlass(in: Circle(), interactive: true)
                        }
                }

                if !viewModel.conversationHistory.isEmpty {
                    Button(action: {
                        viewModel.startNewConversation()
                        showSuggestedOptions = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(NovaColors.textPrimary)
                            .frame(width: 36, height: 36)
                            .background {
                                Color.clear
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                    }
                }

                Button(action: {
                    showConversationHistory = true
                }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(NovaColors.textPrimary)
                            .frame(width: 36, height: 36)
                            .background {
                                Color.clear
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background {
            Color.clear
                .liquidGlass(in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .onAppear {
            if logoTapCount >= 4 {
                logoPulse = true
            }
        }
    }

    // MARK: - 🎯 FUNCIONES DEL EASTER EGG CORREGIDAS

    private func handleLogoTap() {
        let now = Date()

        // Reset si han pasado más de 3 segundos
        if now.timeIntervalSince(lastTapTime) > 3.0 {
            logoTapCount = 1
        } else {
            logoTapCount += 1
        }

        lastTapTime = now

        // ✅ ANIMACIÓN VALIDADA
        let targetScale: CGFloat = logoTapCount >= 7 ? 1.0 : 1.2
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            logoScale = targetScale
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                logoScale = 1.0
            }
        }

        // ✅ EFECTOS CON LÍMITES VALIDADOS
        switch logoTapCount {
        case 3:
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()

        case 4:
            withAnimation(.easeInOut(duration: 0.5)) {
                logoPulse = true
            }
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

        case 6:
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()

        case 7:
            showDeveloperEasterEgg = true
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)

        default:
            if logoTapCount < 7 {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
    }

    private func resetEasterEgg() {
        withAnimation(.easeOut(duration: 0.5)) {
            logoTapCount = 0
            logoPulse = false
            logoScale = 1.0
        }
    }

    private func triggerDeveloperAppreciation() {
        viewModel.inputText = NSLocalizedString("nova.easterEgg.appreciationMessage", comment: "Thank you message for Álvaro")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !viewModel.inputText.isEmpty {
                viewModel.sendMessage()
            }
        }
    }
}

struct NovaBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Group {
            if colorScheme == .dark {
                Color(hex: "0B1215")
            } else {
                Color(hex: "FAF9F6")
            }
        }
        .ignoresSafeArea()
    }
}

struct ModernWelcomeSection: View {
    @ObservedObject var viewModel: NovaAgent
    @Binding var showSuggestedOptions: Bool

    private var eyebrowText: String {
        NSLocalizedString("nova.welcome.eyebrow", comment: "Welcome eyebrow")
    }

    private var supportText: String {
        NSLocalizedString("nova.welcome.support", comment: "Welcome support text")
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            VStack(spacing: 24) {
                Text(eyebrowText)
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(NovaColors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(NovaColors.materialBackground)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(NovaColors.borderColor, lineWidth: 1)
                    )

                VStack(spacing: 12) {
                    Text("\(NSLocalizedString("nova.hello", comment: "Hello message")) \(viewModel.currentUserDisplayName)")
                        .font(.custom("Poppins-Bold", size: 34))
                        .foregroundColor(NovaColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("nova.introduction")
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(NovaColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 8)
                }

                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(NovaColors.textSecondary)

                        Text(supportText)
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(NovaColors.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(NovaColors.materialBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(NovaColors.borderColor, lineWidth: 1)
                    )

                    if let userData = viewModel.userData, !userData.interests.isEmpty {
                        Text(userData.interests.prefix(3).joined(separator: " • "))
                            .font(.custom("Poppins-Medium", size: 13))
                            .foregroundColor(NovaColors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                }

                if showSuggestedOptions {
                    SmartSuggestionChips(
                        viewModel: viewModel,
                        showSuggestedOptions: $showSuggestedOptions,
                        type: .welcome
                    )
                }
            }
            .frame(maxWidth: 380)
            .padding(.horizontal, 24)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ModernInfoCard: View {
    let title: String
    let value: String
    let icon: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(NovaColors.primary)
                    .font(.system(size: 20))

                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(NovaColors.textPrimary)

                Spacer()
            }

            Text(value)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(NovaColors.textSecondary)
                .lineLimit(3)
        }
        .padding(20)
        .background(NovaColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            NovaColors.borderColor,
                            NovaColors.primary.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: NovaColors.shadowColor, radius: 10, x: 0, y: 5)
    }
}

struct ModernStatCard: View {
    let title: String
    let value: String
    let icon: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(NovaColors.secondary)
                .font(.system(size: 24))

            Text(value)
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundColor(NovaColors.textPrimary)

            Text(title)
                .font(.custom("Poppins-Medium", size: 12))
                .foregroundColor(NovaColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(NovaColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            NovaColors.borderColor,
                            NovaColors.secondary.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: NovaColors.shadowColor, radius: 8, x: 0, y: 4)
    }
}

struct ModernSuggestionCard: View {
    let title: String
    let icon: String
    let gradient: [Color]
    let action: () -> Void
    @State private var isPressed = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(NovaColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(NovaColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: gradient.map { $0.opacity(0.4) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .shadow(color: NovaColors.shadowColor, radius: 8, x: 0, y: 4)
        }
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
    }
}

// MARK: - ✨ SISTEMA DE PARTÍCULAS PREMIUM (Canvas)
struct PremiumSparkleParticle: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var size: Double
    var opacity: Double
    var speedX: Double
    var speedY: Double
    var creationDate = Date()
}

// ✅ CLASE LIGERA SIN @Published PARA EVITAR BUCLES INFINITOS EN CANVAS
class PremiumSparkleSystem {
    var particles: [PremiumSparkleParticle] = []
    private let maxParticles = 15
    private var lastUpdate: TimeInterval = 0

    func update(date: Date) {
        let now = date.timeIntervalSince1970

        // Limitar updates a ~60fps si es necesario, pero Canvas ya lo maneja bien
        if now - lastUpdate < 0.016 { return }
        lastUpdate = now

        // Eliminar partículas viejas
        particles.removeAll { date.timeIntervalSince($0.creationDate) > 1.5 }

        // Mover partículas
        for i in 0..<particles.indices.count {
            particles[i].x += particles[i].speedX
            particles[i].y += particles[i].speedY
            particles[i].opacity -= 0.01
        }

        // Crear nuevas si es necesario
        if particles.count < maxParticles {
            addParticle()
        }
    }

    private func addParticle() {
        let p = PremiumSparkleParticle(
            x: Double.random(in: -40...40),
            y: Double.random(in: -40...40),
            size: Double.random(in: 2...6),
            opacity: Double.random(in: 0.4...1.0),
            speedX: Double.random(in: -0.2...0.2),
            speedY: Double.random(in: -0.5...(-0.1))
        )
        particles.append(p)
    }
}

struct PremiumSparkleEmitter: View {
    // ✅ USAR STATE EN LUGAR DE STATEOBJECT
    @State private var system = PremiumSparkleSystem()
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                // ✅ Update síncrono seguro dentro del draw loop (no dispara re-render externo)
                system.update(date: timeline.date)

                for particle in system.particles {
                    let rect = CGRect(
                        x: size.width/2 + particle.x,
                        y: size.height/2 + particle.y,
                        width: particle.size,
                        height: particle.size
                    )

                    var resolvedContext = context
                    resolvedContext.opacity = particle.opacity

                    // Dibujar estrella/sparkle
                    if let sparkle = context.resolveSymbol(id: "sparkle") {
                        resolvedContext.draw(sparkle, in: rect)
                    } else {
                        resolvedContext.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
            } symbols: {
                Image(systemName: "sparkle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(color)
                    .tag("sparkle")
            }
        }
    }
}

// MARK: - 🎉 SISTEMA DE CONFETI (Celebración)
struct ConfettiParticle: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var color: Color
    var size: Double
    var rotation: Double
    var speedX: Double
    var speedY: Double
    var rotationSpeed: Double
    var opacity: Double = 1.0
}

class ConfettiSystem {
    var particles: [ConfettiParticle] = []
    private let colors: [Color] = [.red, .blue, .green, .yellow, .pink, .purple, .orange]
    private var lastUpdate: TimeInterval = 0

    init() {
        // Lanzar explosión inicial
        for _ in 0..<50 {
            addParticle(burst: true)
        }
    }

    func update(date: Date, size: CGSize) {
        let now = date.timeIntervalSince1970
        if now - lastUpdate < 0.016 { return }
        lastUpdate = now

        // Mover partículas
        for i in 0..<particles.indices.count {
            particles[i].x += particles[i].speedX
            particles[i].y += particles[i].speedY
            particles[i].rotation += particles[i].rotationSpeed
            particles[i].speedY += 0.1 // Gravedad

            // Fade out al final
            if particles[i].y > size.height {
                particles[i].opacity -= 0.02
            }
        }

        // Eliminar las que caen fuera o son invisibles
        particles.removeAll { $0.y > size.height + 100 || $0.opacity <= 0 }

        // Añadir nuevas continuamente (fuente)
        if particles.count < 100 {
            addParticle(burst: false)
        }
    }

    private func addParticle(burst: Bool) {
        let p = ConfettiParticle(
            x: burst ? Double.random(in: -50...50) : Double.random(in: -300...300), // Centro o ancho
            y: burst ? Double.random(in: -50...50) : -50, // Centro o arriba
            color: colors.randomElement()!,
            size: Double.random(in: 6...12),
            rotation: Double.random(in: 0...360),
            speedX: Double.random(in: -2...2),
            speedY: burst ? Double.random(in: -10...(-2)) : Double.random(in: 2...8), // Explosión vs Caída
            rotationSpeed: Double.random(in: -5...5)
        )
        particles.append(p)
    }
}

struct ConfettiView: View {
    @State private var system = ConfettiSystem()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                system.update(date: timeline.date, size: size)

                for particle in system.particles {
                    var particleContext = context
                    let rect = CGRect(
                        x: size.width/2 + particle.x, // Centrado
                        y: burstMode(particle) ? size.height/2 + particle.y : particle.y, // Ajuste coord
                        width: particle.size,
                        height: particle.size * 0.6
                    )

                    particleContext.opacity = particle.opacity
                    particleContext.rotate(by: .degrees(particle.rotation))

                    // Dibujar rectángulo de confeti
                    particleContext.fill(Path(getRect(rect)), with: .color(particle.color))
                }
            }
        }
        .allowsHitTesting(false) // Permitir toques a través
    }

    // Helpers simples para lógica de posición
    private func burstMode(_ p: ConfettiParticle) -> Bool {
        return p.speedY < 0 // Si sube, es explosión inicial
    }

    private func getRect(_ rect: CGRect) -> CGRect {
        return rect
    }
}

struct ModernLoadingAnimation: View {
    var statusLabel: String?
    @State private var isAnimating = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 8) {
                ZStack {
                    NovaBrandIcon(size: 16, color: NovaColors.textPrimary)
                }
                .frame(width: 30, height: 30)
                .background {
                    Color.clear
                        .liquidGlass(in: Circle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let statusLabel, !statusLabel.isEmpty {
                        Text(statusLabel)
                            .font(.custom("Poppins-Medium", size: 13))
                            .foregroundColor(NovaColors.textSecondary)
                    }

                    HStack(spacing: 5) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(NovaColors.textSecondary.opacity(0.65))
                                .frame(width: 6, height: 6)
                                .scaleEffect(isAnimating ? 1.0 : 0.65)
                                .animation(
                                    .easeInOut(duration: 0.72)
                                    .repeatForever()
                                    .delay(Double(index) * 0.15),
                                    value: isAnimating
                                )
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            .padding(8)
            .background {
                Color.clear
                    .liquidGlass(in: Capsule(), interactive: false)
            }

            Spacer()
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Badge de Encriptación
struct NovaEncryptionBadge: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(NovaColors.textPrimary)

            Text("nova.encryptedData")
                .font(.custom("Poppins-Medium", size: 11))
                .foregroundColor(NovaColors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Color.clear
                .liquidGlass(in: Capsule())
        }
    }
}
