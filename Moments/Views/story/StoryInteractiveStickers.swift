import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import CoreMotion

// MARK: - 1. QUIZ STICKER
struct InteractiveQuizSticker: View {
    let storyId: String
    let userId: String
    let stickerId: String
    let question: String
    let options: [String]
    let correctIndex: Int
    let isEditing: Bool
    var styleVariant: Int = 0

    @State private var selectedIndex: Int?
    @State private var showConfetti = false
    @State private var confettiStart: Date = .now

    init(storyId: String, userId: String, stickerId: String, question: String, options: [String], correctIndex: Int, isEditing: Bool = false, styleVariant: Int = 0) {
        self.storyId = storyId
        self.userId = userId
        self.stickerId = stickerId
        self.question = question
        self.options = options
        self.correctIndex = correctIndex
        self.isEditing = isEditing
        self.styleVariant = styleVariant
    }

    private var currentUserId: String? { Auth.auth().currentUser?.uid }
    private var isCorrect: Bool { selectedIndex == correctIndex }

    var body: some View {
        ZStack {
            StickerQuizCardView(
                question: question,
                options: options,
                selectedIndex: selectedIndex,
                correctIndex: correctIndex,
                styleVariant: styleVariant,
                onSelect: submitVote
            )

            // ✅ Confetti encima del sticker solo si acertó
            if showConfetti {
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(confettiStart)
                    Canvas { ctx, size in
                        QuizConfettiRenderer.draw(in: ctx, size: size, elapsed: elapsed)
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .onAppear {
            if !isEditing {
                loadVoteState()
            }
        }
    }

    private func submitVote(_ index: Int) {
        guard let currentUserId, selectedIndex == nil else { return }

        let correct = index == correctIndex

        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
            selectedIndex = index
        }

        if correct {
            // Háptico de éxito
            HapticManager.shared.notification(.success)
            // Lanzar confetti
            confettiStart = .now
            withAnimation { showConfetti = true }
            // Apagar el confetti tras 2.5s
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { showConfetti = false }
            }
        } else {
            // Háptico de error
            HapticManager.shared.notification(.error)
        }

        interactionDocument()?.setData([
            "userId": currentUserId,
            "stickerId": stickerId,
            "type": "quiz",
            "selectedIndex": index,
            "isCorrect": correct,
            "timestamp": FieldValue.serverTimestamp()
        ])
    }

    private func loadVoteState() {
        guard userId != "preview" && storyId != "preview" else { return }
        interactionDocument()?.getDocument { snapshot, _ in
            if let data = snapshot?.data(), let index = data["selectedIndex"] as? Int {
                DispatchQueue.main.async { self.selectedIndex = index }
            }
        }
    }

    private func interactionDocument() -> DocumentReference? {
        guard let currentUserId else { return nil }
        return Firestore.firestore()
            .collection("users").document(userId)
            .collection("stories").document(storyId)
            .collection("stickerInteractions")
            .document("\(stickerId)_\(currentUserId)")
    }
}

// MARK: - Confetti renderer (sin dependencias externas)
private enum QuizConfettiRenderer {
    // Colores de confetti
    static let colors: [UIColor] = [
        .systemGreen, .systemYellow, .white,
        .systemCyan, .systemMint, UIColor(red: 0.9, green: 1.0, blue: 0.6, alpha: 1)
    ]

    // Partículas: generadas una vez con seed determinista
    static let particles: [(x: CGFloat, vx: CGFloat, vy: CGFloat, color: Int, size: CGFloat, rotSpeed: CGFloat)] = {
        var result: [(CGFloat, CGFloat, CGFloat, Int, CGFloat, CGFloat)] = []
        var rng: UInt64 = 0xDEADBEEF
        func rand() -> CGFloat {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(rng >> 33) / CGFloat(UInt32.max)
        }
        for _ in 0..<52 {
            result.append((
                rand(),                          // x inicial 0-1
                (rand() - 0.5) * 120,           // velocidad horizontal
                -(rand() * 180 + 80),           // velocidad vertical (hacia arriba)
                Int(rand() * CGFloat(colors.count)),
                rand() * 6 + 5,                 // tamaño 5-11pt
                (rand() - 0.5) * 8             // rotación
            ))
        }
        return result
    }()

    static func draw(in ctx: GraphicsContext, size: CGSize, elapsed: Double) {
        guard elapsed < 2.5 else { return }
        let t = elapsed
        let gravity: CGFloat = 220

        for p in particles {
            let x = size.width * p.x + p.vx * t
            let y = size.height * 0.3 + p.vy * t + 0.5 * gravity * t * t
            let opacity = max(0, 1.0 - t / 2.0)
            let angle = p.rotSpeed * t

            guard opacity > 0, y < size.height + 20 else { continue }

            let color = Color(colors[p.color % colors.count])
            let rect = CGRect(x: x - p.size/2, y: y - p.size/2,
                              width: p.size, height: p.size * 0.55)

            var path = Path(rect)
            // Rotar alrededor del centro
            let cx = x, cy = y
            let transform = CGAffineTransform(translationX: cx, y: cy)
                .rotated(by: angle)
                .translatedBy(x: -cx, y: -cy)
            path = path.applying(transform)

            ctx.fill(path, with: .color(color.opacity(opacity)))
        }
    }
}

// MARK: - 2. POLAROID FRAME (SHAKE TO REVEAL)
struct InteractiveFrameSticker: View {
    let storyId: String
    let image: UIImage?
    let caption: String? // ✅ Nuevo
    let frameStyle: StoryPolaroidFrameStyle
    let contentScale: CGFloat
    let contentOffset: CGSize
    let isEditing: Bool
    let onPauseStory: (() -> Void)?
    let onResumeStory: (() -> Void)?

    @State private var revealProgress: Double
    @State private var motionManager = CMMotionManager()
    @State private var lastAcceleration: CMAcceleration?
    @State private var shakeTimer: Timer? = nil

    private var persistenceKey: String { "frame_revealed_\(storyId)" }

    init(
        storyId: String = "",
        image: UIImage?,
        caption: String? = nil,
        frameStyle: StoryPolaroidFrameStyle = .classic,
        contentScale: CGFloat = 1.0,
        contentOffset: CGSize = .zero,
        isEditing: Bool = false,
        onPauseStory: (() -> Void)? = nil,
        onResumeStory: (() -> Void)? = nil
    ) {
        self.storyId = storyId
        self.image = image
        self.caption = caption
        self.frameStyle = frameStyle
        self.contentScale = contentScale
        self.contentOffset = contentOffset
        self.isEditing = isEditing
        self.onPauseStory = onPauseStory
        self.onResumeStory = onResumeStory
        self._revealProgress = State(initialValue: isEditing ? 1.0 : 0.0)
    }

    var body: some View {
        StickerPolaroidFrameView(
            image: image,
            progress: revealProgress,
            caption: caption,
            frameStyle: frameStyle,
            contentScale: contentScale,
            contentOffset: contentOffset
        )
            .onAppear {
                if !storyId.isEmpty, UserDefaults.standard.bool(forKey: persistenceKey) {
                    revealProgress = 1.0
                    return
                }
                if !isEditing {
                    startMotionUpdates()
                }
            }
            .onDisappear {
                if !isEditing {
                    motionManager.stopAccelerometerUpdates()
                }
            }
    }

    private func startMotionUpdates() {
        guard motionManager.isAccelerometerAvailable else {
            // Fallback for simulator (punto medio perfecto de 3.3s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.linear(duration: 3.3)) { revealProgress = 1.0 }
                markAsRevealed()
            }
            return
        }

        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { data, _ in
            guard let acceleration = data?.acceleration else { return }

            if let last = lastAcceleration {
                let delta = abs(acceleration.x - last.x) + abs(acceleration.y - last.y) + abs(acceleration.z - last.z)

                if delta > 1.2 {
                    // Pausar la historia mientras se agita
                    if revealProgress < 1.0 {
                        onPauseStory?()
                        resetShakeTimer()
                    }

                    // Punto medio dulce: incremento balanceado y transición responsiva
                    let increment = 0.038
                    withAnimation(.easeInOut(duration: 0.26)) {
                        revealProgress = min(revealProgress + increment, 1.0)
                    }

                    if revealProgress < 1.0 {
                        HapticManager.shared.lightImpact()
                    } else if revealProgress >= 1.0 && revealProgress - increment < 1.0 {
                        HapticManager.shared.notification(.success)
                        markAsRevealed()
                        // Si ya terminó de revelar, podemos reanudar inmediatamente
                        shakeTimer?.invalidate()
                        motionManager.stopAccelerometerUpdates()
                        onResumeStory?()
                    }
                }
            }


            lastAcceleration = acceleration
        }
    }

    private func resetShakeTimer() {
        shakeTimer?.invalidate()
        shakeTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            if revealProgress < 1.0 {
                onResumeStory?()
            }
        }
    }

    private func markAsRevealed() {
        guard !storyId.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: persistenceKey)
    }
}

// MARK: - 3. REVEAL STICKER (DITHERED SCRATCH - Solo raspar)
struct InteractiveRevealSticker: View {
    var storyId: String = ""
    var onPauseStory: (() -> Void)? = nil
    var onResumeStory: (() -> Void)? = nil
    var reportsDeckInteractionExclusion: Bool = true

    // Design Configuration
    var revealType: String? = nil // "scratch", "solid", "gradient"
    var revealPattern: String? = nil // "dots", "noise", "grid", "lines", "none"
    var revealPrimaryColor: String? = nil // Hex
    var revealSecondaryColor: String? = nil // Hex — fin del degradado
    var revealEffectColor: String? = nil // Hex — color de partículas/efectos

    @Environment(\.storyDeckGestureGate) private var deckGestureGate
    @State private var points: [CGPoint] = []
    @State private var isRevealed = false
    @State private var isScratching = false
    @State private var didPauseForScratch = false
    @State private var scratchedGrid: Set<Int> = []
    @State private var showHint = false
    @State private var animateHint = false
    @State private var hintTask: Task<Void, Never>?
    private let gridSize: Int = 12

    private var persistenceKey: String { "reveal_revealed_\(storyId)" }
    private var deckExclusionZoneId: String { "reveal.scratch.\(storyId)" }
    private var suppressionSourceId: String { "reveal.scratch.\(storyId)" }

    var body: some View {
        Group {
            if isRevealed {
                Color.clear
                    .allowsHitTesting(false)
            } else {
                revealOverlay
            }
        }
        .animation(.easeOut(duration: 0.6), value: isRevealed)
        .onAppear {
            if !storyId.isEmpty {
                isRevealed = UserDefaults.standard.bool(forKey: persistenceKey)
            }

            guard !isRevealed else { return }

            showHint = true
            startHintAnimation()
        }
        .onDisappear {
            hintTask?.cancel()
            endScratchSession(resumeStory: true)
        }
    }

    private var revealOverlay: some View {
        GeometryReader { geo in
            ZStack {
                RevealSurfaceView(
                    type: revealType,
                    pattern: revealPattern,
                    primaryColor: revealPrimaryColor,
                    secondaryColor: revealSecondaryColor,
                    effectColor: revealEffectColor
                )
                .allowsHitTesting(false)
                .mask(scratchMaskCanvas)

                if showHint {
                    revealHint
                }
            }
            .overlay {
                RevealScratchPanOverlay(
                    isEnabled: true,
                    onBegan: { beginScratchSession() },
                    onPoint: { point in
                        points.append(point)
                        checkRevealStatus(in: geo.size)
                    },
                    onEnded: { endScratchSession(resumeStory: true) }
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous))
        .zIndex(0.5)
        .storyDeckInteractionExclusion(
            id: deckExclusionZoneId,
            in: .named("storyDeckCoordinateSpace"),
            intents: [.deckSwipe, .storyNavigationTap, .holdPause, .replySwipe, .revealScratch],
            suppressionScope: .suppressViewerGestures,
            horizontalInsetFraction: StoryGestureCoordinator.revealSidePassthroughFraction,
            verticalInset: 0
        )
    }

    private var scratchMaskCanvas: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

            var path = Path()
            if let first = points.first {
                path.move(to: first)
                for i in 1..<points.count {
                    path.addLine(to: points[i])
                }
            }

            context.blendMode = .destinationOut
            context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 35, lineCap: .round, lineJoin: .round))
        }
    }

    private var revealHint: some View {
        VStack {
            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(animateHint ? -8 : 6))
                    .offset(x: animateHint ? 6 : -5, y: animateHint ? 2 : -2)
                Text(NSLocalizedString("reveal.viewerHint", comment: "Reveal hint"))
                    .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.96))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.001))
            .momentsChromeGlass(in: Capsule())
            .scaleEffect(animateHint ? 1.03 : 0.985)
            .opacity(animateHint ? 1.0 : 0.82)
            .padding(.bottom, 140)
            .allowsHitTesting(false)
        }
    }

    private func hideHintIfNeeded() {
        guard showHint else { return }
        hintTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            animateHint = false
            showHint = false
        }
    }

    private func startHintAnimation() {
        hintTask?.cancel()
        guard !MotionPolicy.reduceMotion else {
            animateHint = true
            return
        }

        hintTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                animateHint = true
            }

            try? await Task.sleep(nanoseconds: 3_800_000_000)
            guard !Task.isCancelled, points.isEmpty, !isRevealed else { return }

            withAnimation(.easeOut(duration: 0.22)) {
                animateHint = false
                showHint = false
            }
        }
    }

    private func beginScratchSession() {
        hideHintIfNeeded()
        guard !isScratching else { return }
        isScratching = true
        deckGestureGate?.setSuppressionScope(.suppressViewerGestures, for: suppressionSourceId)
        if !didPauseForScratch {
            didPauseForScratch = true
            onPauseStory?()
        }
    }

    private func endScratchSession(resumeStory: Bool) {
        guard isScratching else { return }
        isScratching = false
        deckGestureGate?.clearSuppression(for: suppressionSourceId)
        if resumeStory {
            resumeStoryIfNeeded()
        }
    }

    private func resumeStoryIfNeeded() {
        guard didPauseForScratch, !isRevealed else { return }
        didPauseForScratch = false
        onResumeStory?()
    }

    private func completeReveal(persist: Bool) {
        guard !isRevealed else { return }
        endScratchSession(resumeStory: false)
        withAnimation(.easeOut(duration: 0.8)) {
            isRevealed = true
        }
        HapticManager.shared.notification(.success)
        didPauseForScratch = false
        deckGestureGate?.clearSuppression(for: suppressionSourceId)
        onResumeStory?()
        if persist, !storyId.isEmpty {
            UserDefaults.standard.set(true, forKey: persistenceKey)
        }
    }

    private func checkRevealStatus(in size: CGSize) {
        guard !isRevealed, let lastPoint = points.last else { return }

        let col = Int((lastPoint.x / size.width) * CGFloat(gridSize))
        let row = Int((lastPoint.y / size.height) * CGFloat(gridSize))

        if col >= 0 && col < gridSize && row >= 0 && row < gridSize {
            let index = row * gridSize + col
            scratchedGrid.insert(index)
        }

        let totalCells = gridSize * gridSize
        let percentage = Double(scratchedGrid.count) / Double(totalCells)

        if percentage > 0.65 {
            completeReveal(persist: true)
        }
    }
}

// MARK: - 🎨 REVEAL SURFACE COMPONENTS

struct RevealSurfaceView: View {
    let type: String?
    let pattern: String?
    let primaryColor: String?
    let secondaryColor: String?
    let effectColor: String?

    var body: some View {
        ZStack {
            // 1. Background Layer
            backgroundLayer

            // 2. Pattern Layer
            if let patternType = pattern, patternType != "none" {
                RevealPatternOverlayView(
                    type: patternType,
                    color: resolvedEffectColor(for: patternType),
                    color2: Color(hex: resolvedAccentColor(for: patternType) ?? "#C8C8C8")
                )
            } else if type == nil || type == "scratch" || type == "none" {
                // Default legacy style o si no hay tipo definido
                StickerDitherPattern(color: .white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        let pColor = Color(hex: primaryColor ?? "#000000")
        let sColor = Color(hex: secondaryColor ?? "#000000")

        if type == "gradient" {
            LinearGradient(
                colors: [pColor, sColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            pColor
        }
    }

    private func resolvedEffectColor(for patternType: String) -> Color {
        if patternType == "holographic" {
            return Color(hex: primaryColor ?? "#C8C8C8")
        }

        if let effectColor, !effectColor.isEmpty {
            return Color(hex: effectColor)
        }

        // Compatibilidad con reveals antiguos que guardaban el efecto en secondary.
        if let secondaryColor, !secondaryColor.isEmpty,
           secondaryColor.lowercased() != (primaryColor ?? "").lowercased() {
            return Color(hex: secondaryColor)
        }

        return Color(hex: primaryColor ?? "#000000").revealContrastingEffectColor()
    }

    private func resolvedAccentColor(for patternType: String) -> String? {
        if patternType == "holographic" {
            return effectColor ?? secondaryColor
        }
        return effectColor ?? secondaryColor
    }
}

struct RevealPatternOverlayView: View {
    let type: String
    let color: Color
    var color2: Color = .white
    @Environment(\.storyEffectsActive) private var effectsActive

    var body: some View {
        switch type {
        case "dots":
            StickerDitherPattern(color: color)
        case "grid":
            RevealGridPattern(color: color, isActive: effectsActive)
        case "lines":
            RevealLinesPattern(color: color)
        case "noise":
            RevealNoisePattern(color: color, isActive: effectsActive)
        case "static":
            RevealStaticPattern(color: color, isActive: effectsActive)
        case "scanlines":
            RevealScanlinesPattern(color: color, isActive: effectsActive)
        case "waves":
            RevealWavesPattern(color: color, isActive: effectsActive)
        case "matrix":
            RevealMatrixPattern(color: color, isActive: effectsActive)
        case "holographic":
            RevealHolographicPattern(color: color, accentColor: color2, isActive: effectsActive)
        default:
            EmptyView()
        }
    }
}

struct RevealGridPattern: View {
    let color: Color
    var isActive: Bool = true

    var body: some View {
        if !isActive || MotionPolicy.reduceMotion {
            RevealLinesPattern(color: color)
        } else {
        TimelineView(.periodic(from: .now, by: 1 / MotionPolicy.canvasFPS)) { timeline in
            let time = timeline.date.timeIntervalSince1970
            Canvas { context, size in
                let spacing: CGFloat = 30

                // 1. Reja base
                for x in stride(from: 0, to: size.width, by: spacing) {
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    }, with: .color(color.opacity(0.3)), lineWidth: 0.5)
                }
                for y in stride(from: 0, to: size.height, by: spacing) {
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }, with: .color(color.opacity(0.3)), lineWidth: 0.5)
                }

                // 2. Línea de escaneo (Efecto radar/plano)
                let scanY = (time * 60).truncatingRemainder(dividingBy: size.height)
                context.fill(Path(CGRect(x: 0, y: scanY, width: size.width, height: 2)), with: .color(color.opacity(0.6)))

                // 3. Puntos de intersección sutiles
                for x in stride(from: 0, to: size.width + spacing, by: spacing) {
                    for y in stride(from: 0, to: size.height + spacing, by: spacing) {
                        let rect = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.5)))
                    }
                }
            }
            .drawingGroup(opaque: false)
        }
        }
    }
}

struct RevealLinesPattern: View {
    let color: Color
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 15
            for x in stride(from: -size.height, to: size.width, by: spacing) {
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                }, with: .color(color.opacity(0.4)), lineWidth: 1)
            }
        }
    }
}

struct RevealNoisePattern: View {
    let color: Color
    var isActive: Bool = true

    var body: some View {
        if !isActive || MotionPolicy.reduceMotion {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1 / MotionPolicy.canvasFPS)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                var rng = SeededRandom(seed: 42)
                let particleCount = MotionPolicy.revealParticleCount(for: size)

                for index in 0..<particleCount {
                    // Posición base fija para esta partícula en el lienzo
                    let baseX = CGFloat(rng.next()) * size.width
                    let baseY = CGFloat(rng.next()) * size.height

                    // Factores únicos por partícula para romper la simetría del movimiento
                    let speedX = rng.next() * 3.5 + 1.5
                    let speedY = rng.next() * 4.0 + 2.0
                    let driftPhase = rng.next() * .pi * 2

                    // 🌀 Movimiento de flotación flotante (deriva lenta en X e Y)
                    // Usamos combinaciones de funciones trigonométricas para que el recorrido sea un bucle orgánico, no lineal
                    let offsetX = sin(time * 0.25 * speedX + driftPhase) * 12.0
                    let offsetY = cos(time * 0.18 * speedY + driftPhase) * 15.0

                    // Envoltorio suave de coordenadas para que si salen de la pantalla vuelvan por el lado opuesto
                    let x = (baseX + offsetX).truncatingRemainder(dividingBy: size.width)
                    let y = (baseY + offsetY).truncatingRemainder(dividingBy: size.height)

                    // Tamaños variados tal como se aprecia en los fotogramas (de 1.0pt a 3.2pt)
                    let dotSize = CGFloat(rng.next() * 2.2 + 1.0)

                    // ✨ Efecto Shimmer (Destello / Desvanecimiento lento)
                    // Las partículas aumentan y disminuyen su brillo de forma asíncrona
                    let shimmer = 0.4 + sin(time * 0.85 * speedX + driftPhase) * 0.4
                    let opacity = (0.35 + rng.next() * 0.45) * shimmer

                    let rect = CGRect(x: x >= 0 ? x : x + size.width,
                                      y: y >= 0 ? y : y + size.height,
                                      width: dotSize, height: dotSize)

                    let tone = index % 7 == 0 ? color.opacity(opacity * 0.65) : color.opacity(opacity)
                    context.fill(Path(ellipseIn: rect), with: .color(tone))
                }

                let area = max(size.width * size.height, 1)
                let microCount = min(max(Int(area / 150), 40), 250)
                for _ in 0..<microCount {
                    let mx = (CGFloat(rng.next()) * size.width + CGFloat(sin(time * 0.15)))
                        .truncatingRemainder(dividingBy: size.width)
                    let my = (CGFloat(rng.next()) * size.height + CGFloat(cos(time * 0.1)))
                        .truncatingRemainder(dividingBy: size.height)

                    let mRect = CGRect(x: mx, y: my, width: 0.8, height: 0.8)
                    context.fill(Path(mRect), with: .color(color.opacity(0.22)))
                }
            }
            .drawingGroup(opaque: false)
        }
        }
    }
}


struct RevealStaticPattern: View {
    let color: Color
    var isActive: Bool = true

    var body: some View {
        if !isActive || MotionPolicy.reduceMotion {
            Color.black.opacity(0.08)
        } else {
        TimelineView(.periodic(from: .now, by: 1/24)) { timeline in
            let time = timeline.date.timeIntervalSince1970
            Canvas { context, size in
                // 1. Fondo base con micro-flicker
                let flicker = Double.random(in: 0.96...1.04)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(0.12 * flicker)))

                // 2. Nieve Analógica (Optimizada)
                // Reducimos densidad para evitar lag
                for _ in 0..<Int(size.width * size.height / 120) {
                    let dotW = CGFloat.random(in: 2...4)
                    let dotH = CGFloat.random(in: 1...2)

                    let rect = CGRect(
                        x: CGFloat.random(in: 0...size.width),
                        y: CGFloat.random(in: 0...size.height),
                        width: dotW,
                        height: dotH
                    )

                    let rand = Double.random(in: 0...1)
                    let dotColor: Color = rand > 0.6 ? .black : (rand > 0.2 ? .white : .gray)
                    context.fill(Path(rect), with: .color(dotColor.opacity(Double.random(in: 0.1...0.7))))
                }

                // 3. Rolling Interference
                let rollY = (time * 120).truncatingRemainder(dividingBy: size.height + 1200) - 600
                context.fill(Path(CGRect(x: 0, y: rollY, width: size.width, height: 1.5)), with: .color(.black.opacity(0.2)))

                // 4. Viñeteado suave
                let gradient = GraphicsContext.Shading.radialGradient(
                    Gradient(colors: [.clear, .black.opacity(0.1)]),
                    center: CGPoint(x: size.width/2, y: size.height/2),
                    startRadius: size.width * 0.4,
                    endRadius: size.width * 0.8
                )
                context.fill(Path(CGRect(origin: .zero, size: size)), with: gradient)
            }
        }
        }
    }
}

struct RevealMatrixPattern: View {
    let color: Color
    var isActive: Bool = true

    var body: some View {
        if !isActive || MotionPolicy.reduceMotion {
            RevealLinesPattern(color: color)
        } else {
        TimelineView(.periodic(from: .now, by: 1/20)) { timeline in
            let time = timeline.date.timeIntervalSince1970
            Canvas { context, size in
                let columns = Int(size.width / 20)

                for i in 0..<columns {
                    let x = CGFloat(i * 20) + 10
                    let speed = (sin(Double(i) * 0.5) + 2.0) * 80.0
                    let yOffset = (time * speed).truncatingRemainder(dividingBy: size.height + 200) - 100

                    for segment in 0..<12 {
                        let segmentY = yOffset - CGFloat(segment * 15)
                        let opacity = 1.0 - (Double(segment) / 12.0)

                        if segmentY > 0 && segmentY < size.height {
                            let rect = CGRect(x: x - 4, y: segmentY, width: 8, height: 12)
                            context.fill(Path(rect), with: .color(color.opacity(opacity * 0.6)))

                            if segment == 0 {
                                context.fill(Path(rect), with: .color(.white.opacity(0.4)))
                            }
                        }
                    }
                }
            }
            .drawingGroup(opaque: false)
        }
        }
    }
}

struct RevealScanlinesPattern: View {
    let color: Color
    var isActive: Bool = true

    var body: some View {
        if !isActive || MotionPolicy.reduceMotion {
            RevealLinesPattern(color: color)
        } else {
        TimelineView(.periodic(from: .now, by: 1/30)) { timeline in
            let time = timeline.date.timeIntervalSince1970
            Canvas { context, size in
                let spacing: CGFloat = 8
                let offset = (time * 20).truncatingRemainder(dividingBy: spacing)

                for y in stride(from: -spacing, to: size.height + spacing, by: spacing) {
                    context.fill(
                        Path(CGRect(x: 0, y: y + offset, width: size.width, height: 2.5)),
                        with: .color(color.opacity(0.3))
                    )
                }

                // Efecto de barra de interferencia que baja lentamente
                let interferenceY = (time * 40).truncatingRemainder(dividingBy: size.height + 400) - 200
                let interferenceRect = CGRect(x: 0, y: interferenceY, width: size.width, height: 60)
                context.fill(Path(interferenceRect), with: .color(color.opacity(0.05)))
            }
        }
        }
    }
}

struct RevealWavesPattern: View {
    let color: Color
    var isActive: Bool = true

    var body: some View {
        if !isActive || MotionPolicy.reduceMotion {
            RevealLinesPattern(color: color)
        } else {
        TimelineView(.periodic(from: .now, by: 1/30)) { timeline in
            let time = timeline.date.timeIntervalSince1970
            Canvas { context, size in
                let spacing: CGFloat = 30
                for y in stride(from: -40, to: size.height + 40, by: spacing) {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))

                    for x in stride(from: 0, to: size.width + 20, by: 10) {
                        let relativeX = x / 20
                        let sine = sin(Double(relativeX) + time * 2.5) * 8
                        path.addLine(to: CGPoint(x: CGFloat(x), y: y + CGFloat(sine)))
                    }
                    context.stroke(path, with: .color(color.opacity(0.4)), lineWidth: 2.5)
                }
            }
        }
        }
    }
}

struct RevealHolographicPattern: View {
    let color: Color
    var accentColor: Color = .purple
    var isActive: Bool = true
    @StateObject private var motion = HolographicMotionManager()

    // Hue base del color 1 (dots de purpurina)
    private var baseHue: Double {
        var h: CGFloat = 0
        UIColor(color).getHue(&h, saturation: nil, brightness: nil, alpha: nil)
        return Double(h)
    }

    // Hue del color 2 (tinte de la ola de fondo)
    private var accentHue: Double {
        var h: CGFloat = 0
        UIColor(accentColor).getHue(&h, saturation: nil, brightness: nil, alpha: nil)
        return Double(h)
    }

    var body: some View {
        Group {
            if !isActive || MotionPolicy.reduceMotion {
                RevealLinesPattern(color: color)
            } else {
        TimelineView(.periodic(from: .now, by: 1/24)) { timeline in
            GeometryReader { geometry in
                let size = geometry.size
                let time = timeline.date.timeIntervalSince1970

                let tiltX = motion.roll / .pi
                let tiltY = motion.pitch / (.pi / 2)

                let globalHueShift = (tiltX * 0.4 + tiltY * 0.2).truncatingRemainder(dividingBy: 1.0)

                ZStack {
                    // --- CAPA 1: Fondo plateado denso ---
                    LinearGradient(
                        colors: [Color(white: 0.82), Color(white: 0.70), Color(white: 0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // --- CAPA 2: Ola de color iridiscente (suavizada) ---
                    Canvas { context, canvasSize in
                        let cellSize: CGFloat = canvasSize.width < 150 ? 10 : 20
                        let cols = Int(canvasSize.width / cellSize) + 2
                        let rows = Int(canvasSize.height / cellSize) + 2

                        for col in 0..<cols {
                            for row in 0..<rows {
                                let cx = CGFloat(col) * cellSize
                                let cy = CGFloat(row) * cellSize
                                let posX = Double(col) / Double(cols)
                                let posY = Double(row) / Double(rows)

                                let rawWaveHue = posX + posY * 0.5 + globalHueShift + accentHue * 0.3
                                var hue = rawWaveHue.truncatingRemainder(dividingBy: 1.0)
                                if hue < 0 { hue += 1.0 }

                                let waveX = posX * .pi * 3
                                let waveY = posY * .pi * 2
                                let waveT = time * 0.4
                                let saturation = 0.5 + 0.4 * sin(waveX + waveY + waveT)

                                let rect = CGRect(x: cx, y: cy, width: cellSize + 1, height: cellSize + 1)
                                context.fill(Path(rect), with: .color(Color(hue: hue, saturation: saturation, brightness: 0.95).opacity(0.5)))
                            }
                        }
                    }
                    .blur(radius: size.width < 150 ? 8 : 18)

                    // --- CAPA 3: Puntos de glitter ---
                    Canvas { context, canvasSize in
                        var rng = SeededRandom(seed: 77)
                        let isPreview = canvasSize.width < 150
                        let count = isPreview ? 1000 : 5000

                        let motionIntensity = min(1.0, max(0, (motion.rotationRate - 0.1) / 1.5))
                        let glintAlpha = motionIntensity * 0.95

                        for i in 0..<count {
                            let x = CGFloat(rng.next()) * canvasSize.width
                            let y = CGFloat(rng.next()) * canvasSize.height
                            let dotSize = CGFloat(rng.next()) * (isPreview ? 1.0 : 1.4) + 0.4
                            let phase = rng.next()

                            let hueShift = globalHueShift * 0.35
                            let rawHue = baseHue + hueShift + phase * 0.15
                            var hue = rawHue.truncatingRemainder(dividingBy: 1.0)
                            if hue < 0 { hue += 1.0 }

                            let isBright = i % 8 == 0
                            let dotRect = CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)

                            if isBright {
                                let staticShimmer = abs(sin(time * 2.0 + phase * 10.0)) * 0.3
                                let finalBrightness = 0.7 + staticShimmer + motionIntensity * 0.3

                                let brightColor = Color(hue: hue, saturation: 0.8, brightness: finalBrightness)
                                context.fill(Path(ellipseIn: dotRect), with: .color(brightColor.opacity(0.95)))

                                if dotSize > 1.2 && (glintAlpha > 0.1 || isPreview) {
                                    let gAlpha = isPreview ? 0.3 : glintAlpha
                                    let rayLen = dotSize * (2.5 + motionIntensity * 4.0)
                                    let opacity = gAlpha * (0.5 + rng.next() * 0.5)

                                    for arm in 0..<4 {
                                        let armAngle = Double(arm) * .pi / 2 + (time * 0.4) + phase
                                        var ray = Path()
                                        ray.move(to: CGPoint(x: x, y: y))
                                        ray.addLine(to: CGPoint(x: x + cos(armAngle) * rayLen, y: y + sin(armAngle) * rayLen))
                                        context.stroke(ray, with: .color(.white.opacity(opacity)), lineWidth: 0.4)
                                    }
                                }
                            } else {
                                let baseColor = Color(hue: hue, saturation: 0.4, brightness: 0.9)
                                context.fill(Path(ellipseIn: dotRect), with: .color(baseColor.opacity(0.8)))
                            }
                        }
                    }
                }
            }
        }
            }
        }
        .onAppear { motion.setActive(isActive) }
        .onChange(of: isActive) { _, active in
            motion.setActive(active)
        }
        .onDisappear {
            motion.setActive(false)
        }
    }
}

// Helper para aleatorios consistentes en Canvas
struct SeededRandom {
    var state: UInt64
    init(seed: Int) { state = UInt64(abs(seed)) }
    mutating func next() -> Double {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double(z ^ (z >> 31)) / Double(UInt64.max)
    }
}

class HolographicMotionManager: ObservableObject {
    private let motionManager = CMMotionManager()
    @Published var pitch: Double = 0.0
    @Published var roll: Double = 0.0
    @Published var rotationRate: Double = 0.0
    private var isActive = false

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            startIfNeeded()
        } else {
            stop()
        }
    }

    private func startIfNeeded() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = 1 / 30
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, self.isActive, let motion else { return }
            pitch = motion.attitude.pitch
            roll = motion.attitude.roll
            let rate = motion.rotationRate
            rotationRate = sqrt(rate.x * rate.x + rate.y * rate.y + rate.z * rate.z)
        }
    }

    private func stop() {
        motionManager.stopDeviceMotionUpdates()
        pitch = 0
        roll = 0
        rotationRate = 0
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}
