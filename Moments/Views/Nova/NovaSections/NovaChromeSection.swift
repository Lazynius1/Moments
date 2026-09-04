import SwiftUI
import UIKit

// MARK: - Header Mejorado con Memoria
struct NovaHeader: View {
    @ObservedObject var viewModel: NovaAgent
    @Binding var showConversationHistory: Bool
    @Binding var showSuggestedOptions: Bool
    @Binding var isShowingMemory: Bool
    @Environment(\.dismiss) private var dismiss

    // ✨ ESTADOS PARA EASTER EGG
    @State private var logoTapCount = 0
    @State private var showDeveloperEasterEgg = false
    @State private var lastTapTime = Date()
    @State private var logoScale: CGFloat = 1.0
    @State private var logoPulse = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(NovaColors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background {
                        Color.clear
                            .momentsChromeGlass(in: Circle(), interactive: true)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.momentsPressIcon)
            .accessibilityLabel(NSLocalizedString("common.back", comment: "Back"))

            Button(action: handleLogoTap) {
                Image("NovaTabIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(NovaColors.textPrimary)
                    .frame(width: 34, height: 34)
                    .scaleEffect(logoScale * (logoPulse ? 1.06 : 1.0))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.momentsPress(scale: 0.92, haptic: .none))
            .accessibilityLabel(Text("nova.name"))
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

            Text("nova.name")
                .font(.system(size: legacyPoppinsSize(22), weight: .bold))
                .foregroundStyle(NovaColors.textPrimary)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Button(action: { showConversationHistory = true }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(NovaColors.textPrimary)
                        .frame(width: 42, height: 42)
                        .background {
                            Color.clear
                                .momentsChromeGlass(in: Circle(), interactive: true)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.momentsPressIcon)
                .accessibilityLabel(Text("nova.recentConversations"))

                if !viewModel.conversationHistory.isEmpty {
                    Button(action: {
                        viewModel.startNewConversation()
                        showSuggestedOptions = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(NovaColors.textPrimary)
                            .frame(width: 42, height: 42)
                            .background {
                                Color.clear
                                    .momentsChromeGlass(in: Circle(), interactive: true)
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.momentsPressIcon)
                    .accessibilityLabel(Text("nova.newConversation"))
                }

                Button(action: { isShowingMemory = true }) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(NovaColors.textPrimary)
                        .frame(width: 42, height: 42)
                        .background {
                            Color.clear
                                .momentsChromeGlass(in: Circle(), interactive: true)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.momentsPressIcon)
                .accessibilityLabel(Text("nova.memory.title"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
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
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
            logoScale = targetScale
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
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
    let onOpenMemory: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var greetingSize: CGFloat = 45

    private var rotatingQuestions: [String] {
        [
            localized("nova.welcome.editorial.question", fallback: "What are you thinking about?"),
            localized("nova.welcome.editorial.question.create", fallback: "What would you like to create?"),
            localized("nova.welcome.editorial.question.solve", fallback: "What would you like to solve?"),
            localized("nova.welcome.editorial.question.begin", fallback: "Where should we begin?")
        ]
    }

    private var suggestions: [NovaEditorialSuggestion] {
        [
            NovaEditorialSuggestion(
                id: "organize",
                titleKey: "nova.welcome.editorial.organize.title",
                titleFallback: "Help me organize an idea",
                promptKey: "nova.welcome.editorial.organize.prompt",
                promptFallback: "Help me organize an idea I have"
            ),
            NovaEditorialSuggestion(
                id: "write",
                titleKey: "nova.welcome.editorial.write.title",
                titleFallback: "Write something with me",
                promptKey: "nova.welcome.editorial.write.prompt",
                promptFallback: "Help me write something"
            ),
            NovaEditorialSuggestion(
                id: "moments",
                titleKey: "nova.welcome.editorial.moments.title",
                titleFallback: "What can I do in Moments?",
                promptKey: "nova.welcome.editorial.moments.prompt",
                promptFallback: "What can you help me do in Moments?"
            )
        ]
    }

    private var highlightedMemory: NovaFact? {
        viewModel.userMemory?.facts
            .filter { fact in
                let content = fact.normalizedContent
                return !content.hasPrefix("preferred name:")
                    && !content.hasPrefix("pronouns:")
            }
            .sorted { lhs, rhs in
                let lhsPersonal = lhs.type == .personal
                let rhsPersonal = rhs.type == .personal
                if lhsPersonal != rhsPersonal { return lhsPersonal }
                if lhs.importance != rhs.importance { return lhs.importance > rhs.importance }
                return lhs.timestamp > rhs.timestamp
            }
            .first
    }

    private var latestConversation: ConversationTitle? {
        viewModel.conversationTitles.max { $0.lastUpdated < $1.lastUpdated }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 92)
                        .accessibilityHidden(true)

                    Color.clear
                        .frame(height: 22)
                        .accessibilityHidden(true)

                    Text(
                        String(
                            format: localized(
                                "nova.welcome.editorial.greeting",
                                fallback: "Hello, %@."
                            ),
                            viewModel.currentUserDisplayName
                        )
                    )
                    .font(.system(size: greetingSize, weight: .regular, design: .serif))
                    .foregroundStyle(NovaColors.textPrimary)
                    .minimumScaleFactor(0.78)
                    .lineLimit(1)

                    NovaTypewriterQuestion(
                        phrases: rotatingQuestions,
                        fontSize: greetingSize
                    )
                    .padding(.top, 2)

                    Text(
                        localized(
                            "nova.welcome.editorial.support",
                            fallback: "I can help you write, decide, learn, or make things in Moments."
                        )
                    )
                    .font(.system(size: legacyPoppinsSize(16)))
                    .foregroundStyle(NovaColors.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .padding(.bottom, 22)

                    if showSuggestedOptions {
                        VStack(spacing: 0) {
                            ForEach(suggestions) { suggestion in
                                NovaEditorialSuggestionRow(suggestion: suggestion) {
                                    viewModel.inputText = suggestion.prompt
                                    showSuggestedOptions = false
                                    viewModel.sendMessage()
                                }
                            }
                        }
                    }

                    NovaWelcomeTodaySection(
                        memory: highlightedMemory,
                        conversation: latestConversation,
                        dailySpark: viewModel.welcomeSpark,
                        onOpenMemory: onOpenMemory,
                        onContinueConversation: { conversationId in
                            Task { await viewModel.loadConversation(conversationId) }
                        },
                        onUseSpark: {
                            viewModel.openConversationFromSpark()
                        }
                    )
                    .padding(.top, 22)

                    Spacer(minLength: 24)

                    HStack(spacing: 8) {
                        Image(systemName: "lock")
                            .font(.system(size: 12, weight: .medium))

                        Text(
                            localized(
                                "nova.welcome.editorial.privacy",
                                fallback: "I remember your preferences · Private"
                            )
                        )
                        .font(.system(size: legacyPoppinsSize(13)))
                    }
                    .foregroundStyle(NovaColors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 136)
                }
                .padding(.horizontal, 28)
                .frame(
                    maxWidth: .infinity,
                    minHeight: geometry.size.height,
                    alignment: .topLeading
                )
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func localized(_ key: String, fallback: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "")
    }
}

private struct NovaWelcomeTodaySection: View {
    let memory: NovaFact?
    let conversation: ConversationTitle?
    let dailySpark: String?
    let onOpenMemory: () -> Void
    let onContinueConversation: (String) -> Void
    let onUseSpark: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("nova.welcome.today.title")
                .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                .foregroundStyle(NovaColors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.7)
                .padding(.bottom, 10)

            NovaWelcomeTodayRow(
                icon: memory == nil ? "brain.head.profile" : "sparkles",
                eyebrow: String(localized: "nova.welcome.memory.title"),
                title: memory?.content ?? NSLocalizedString(
                    "nova.memory.empty.subtitle",
                    comment: "Empty Nova memory subtitle"
                ),
                detail: nil,
                action: onOpenMemory
            )

            if let conversation {
                NovaWelcomeTodayRow(
                    icon: "arrow.uturn.forward",
                    eyebrow: String(localized: "nova.welcome.continue.title"),
                    title: conversation.title,
                    detail: conversation.lastUpdated.timeAgoDisplay(),
                    action: { onContinueConversation(conversation.id) }
                )
            }

            NovaWelcomeTodayRow(
                icon: "sparkle",
                eyebrow: String(localized: "nova.welcome.spark.title"),
                title: dailySpark ?? "…",
                detail: nil,
                action: onUseSpark
            )
            .disabled(dailySpark == nil)
            .opacity(dailySpark == nil ? 0.58 : 1)
        }
    }
}

private struct NovaWelcomeTodayRow: View {
    let icon: String
    let eyebrow: String
    let title: String
    let detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NovaColors.textSecondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow)
                        .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
                        .foregroundStyle(NovaColors.textTertiary)

                    Text(title)
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundStyle(NovaColors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if let detail {
                    Text(detail)
                        .font(.system(size: legacyPoppinsSize(10)))
                        .foregroundStyle(NovaColors.textTertiary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NovaColors.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(NovaColors.borderColor.opacity(0.5))
                    .frame(height: 0.7)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct NovaTypewriterQuestion: View {
    let phrases: [String]
    let fontSize: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedText = ""
    @State private var phraseIndex = 0
    @State private var cursorVisible = true

    var body: some View {
        Text(attributedText)
            .font(.system(size: fontSize, weight: .regular, design: .serif))
            .foregroundStyle(NovaColors.textPrimary)
            .minimumScaleFactor(0.68)
            .lineLimit(2)
            .frame(minHeight: fontSize * 2.12, alignment: .topLeading)
            .accessibilityLabel(currentPhrase)
            .task(id: reduceMotion) {
                await runTypewriter()
            }
            .task(id: reduceMotion) {
                await runCursorBlink()
            }
    }

    private var currentPhrase: String {
        guard !phrases.isEmpty else { return "" }
        return phrases[phraseIndex % phrases.count]
    }

    private var attributedText: AttributedString {
        var text = AttributedString(displayedText)
        var cursor = AttributedString("│")
        cursor.foregroundColor = NovaColors.textPrimary.opacity(cursorVisible ? 0.82 : 0)
        text.append(cursor)
        return text
    }

    @MainActor
    private func runTypewriter() async {
        guard !phrases.isEmpty else { return }

        if reduceMotion {
            displayedText = currentPhrase
            return
        }

        while !Task.isCancelled {
            let phrase = currentPhrase
            displayedText = ""

            for character in phrase {
                guard !Task.isCancelled else { return }
                displayedText.append(character)
                try? await Task.sleep(for: .milliseconds(65))
            }

            try? await Task.sleep(for: .milliseconds(1_650))
            guard !Task.isCancelled else { return }

            while !displayedText.isEmpty {
                guard !Task.isCancelled else { return }
                displayedText.removeLast()
                try? await Task.sleep(for: .milliseconds(38))
            }

            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            phraseIndex = (phraseIndex + 1) % phrases.count
        }
    }

    @MainActor
    private func runCursorBlink() async {
        cursorVisible = !reduceMotion
        guard !reduceMotion else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }
            cursorVisible.toggle()
        }
    }
}

private struct NovaEditorialSuggestion: Identifiable {
    let id: String
    let titleKey: String
    let titleFallback: String
    let promptKey: String
    let promptFallback: String

    var title: String {
        NSLocalizedString(titleKey, tableName: nil, bundle: .main, value: titleFallback, comment: "")
    }

    var prompt: String {
        NSLocalizedString(promptKey, tableName: nil, bundle: .main, value: promptFallback, comment: "")
    }
}

private struct NovaEditorialSuggestionRow: View {
    let suggestion: NovaEditorialSuggestion
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(suggestion.title)
                    .font(.system(size: legacyPoppinsSize(16), weight: .regular))
                    .foregroundStyle(NovaColors.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NovaColors.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(NovaColors.borderColor.opacity(0.62))
                    .frame(height: 0.7)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(suggestion.prompt))
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
                    .foregroundStyle(NovaColors.primary)
                    .font(.system(size: 20))

                Text(title)
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundStyle(NovaColors.textPrimary)

                Spacer()
            }

            Text(value)
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundStyle(NovaColors.textSecondary)
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
                .foregroundStyle(NovaColors.secondary)
                .font(.system(size: 24))

            Text(value)
                .font(.system(size: legacyPoppinsSize(20), weight: .bold))
                .foregroundStyle(NovaColors.textPrimary)

            Text(title)
                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                .foregroundStyle(NovaColors.textSecondary)
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
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .foregroundStyle(NovaColors.textPrimary)
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
                    .foregroundStyle(color)
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
                        .momentsChromeGlass(in: Circle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let statusLabel, !statusLabel.isEmpty {
                        Text(statusLabel)
                            .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                            .foregroundStyle(NovaColors.textSecondary)
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
                    .momentsChromeGlass(in: Capsule(), interactive: false)
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
                .foregroundStyle(NovaColors.textPrimary)

            Text("nova.encryptedData")
                .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                .foregroundStyle(NovaColors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Color.clear
                .momentsChromeGlass(in: Capsule())
        }
    }
}
