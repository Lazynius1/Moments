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
    
    @State private var selectedIndex: Int?
    @State private var showConfetti = false
    @State private var confettiStart: Date = .now
    
    init(storyId: String, userId: String, stickerId: String, question: String, options: [String], correctIndex: Int, isEditing: Bool = false) {
        self.storyId = storyId
        self.userId = userId
        self.stickerId = stickerId
        self.question = question
        self.options = options
        self.correctIndex = correctIndex
        self.isEditing = isEditing
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
    // Colores de confetti estilo Instagram
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
    let isEditing: Bool
    let onPauseStory: (() -> Void)?
    let onResumeStory: (() -> Void)?
    
    @State private var revealProgress: Double
    @State private var motionManager = CMMotionManager()
    @State private var lastAcceleration: CMAcceleration?
    @State private var shakeTimer: Timer? = nil

    private var persistenceKey: String { "frame_revealed_\(storyId)" }
    
    init(storyId: String = "", image: UIImage?, caption: String? = nil, isEditing: Bool = false, onPauseStory: (() -> Void)? = nil, onResumeStory: (() -> Void)? = nil) {
        self.storyId = storyId
        self.image = image
        self.caption = caption
        self.isEditing = isEditing
        self.onPauseStory = onPauseStory
        self.onResumeStory = onResumeStory
        self._revealProgress = State(initialValue: isEditing ? 1.0 : 0.0)
    }
    
    var body: some View {
        StickerPolaroidFrameView(image: image, progress: revealProgress, caption: caption)
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
            // Fallback for simulator
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.linear(duration: 2.5)) { revealProgress = 1.0 }
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
                    
                    let increment = 0.06
                    withAnimation(.easeInOut(duration: 0.2)) {
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
    /// Identificador único de la historia para persistir el estado revelado
    var storyId: String = ""
    var onPauseStory: (() -> Void)? = nil
    var onResumeStory: (() -> Void)? = nil
    
    @State private var points: [CGPoint] = []
    @State private var isRevealed = false
    @State private var scratchedGrid: Set<Int> = [] // Para seguimiento de área
    @State private var showHint = false
    @State private var animateHint = false
    private let gridSize: Int = 12 // Cuadrícula de 12x12
    
    private var persistenceKey: String { "reveal_revealed_\(storyId)" }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if !isRevealed {
                    ZStack {
                        // Fondo negro opaco + Patrón
                        Color.black
                        StickerDitherPattern(color: .white.opacity(0.8))
                    }
                    .mask(
                        Canvas { context, size in
                            // Dibujar todo como opaco excepto donde rascamos
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
                    )

                    if showHint {
                        VStack {
                            Spacer()

                            HStack(spacing: 8) {
                                Image(systemName: "hand.draw.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .rotationEffect(.degrees(animateHint ? -8 : 6))
                                    .offset(x: animateHint ? 6 : -5, y: animateHint ? 2 : -2)
                                Text(NSLocalizedString("reveal.viewerHint", comment: "Reveal hint"))
                                    .font(.custom("Poppins-SemiBold", size: 12))
                            }
                            .foregroundColor(.white.opacity(0.96))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.001))
                            .liquidGlass(in: Capsule())
                            .scaleEffect(animateHint ? 1.03 : 0.985)
                            .opacity(animateHint ? 1.0 : 0.82)
                            .padding(.bottom, 140)
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isRevealed else { return }
                        if showHint {
                            withAnimation(.easeOut(duration: 0.18)) {
                                animateHint = false
                                showHint = false
                            }
                        }
                        onPauseStory?()
                        points.append(value.location)
                        checkRevealStatus(in: geo.size)
                    }
                    .onEnded { _ in
                        if !isRevealed {
                            onResumeStory?()
                        }
                    }
            )
        }
        .animation(.easeOut(duration: 0.6), value: isRevealed)
        .onAppear {
            // Restaurar estado persistido
            if !storyId.isEmpty {
                isRevealed = UserDefaults.standard.bool(forKey: persistenceKey)
            }

            guard !isRevealed else { return }

            showHint = true
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                animateHint = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) {
                guard points.isEmpty, !isRevealed else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    animateHint = false
                    showHint = false
                }
            }
        }
    }
    
    private func checkRevealStatus(in size: CGSize) {
        guard !isRevealed, let lastPoint = points.last else { return }
        
        // 1. Mapear punto actual a la cuadrícula
        let col = Int((lastPoint.x / size.width) * CGFloat(gridSize))
        let row = Int((lastPoint.y / size.height) * CGFloat(gridSize))
        
        // Validar límites
        if col >= 0 && col < gridSize && row >= 0 && row < gridSize {
            let index = row * gridSize + col
            scratchedGrid.insert(index)
        }
        
        // 2. Calcular porcentaje (Umbral 65%)
        let totalCells = gridSize * gridSize
        let percentage = Double(scratchedGrid.count) / Double(totalCells)
        
        if percentage > 0.65 {
            withAnimation(.easeOut(duration: 0.8)) {
                isRevealed = true
            }
            HapticManager.shared.notification(.success)
            
            // Reanudar historia inmediatamente al completar el revelado
            onResumeStory?()
            
            // Persistir para no tener que rascar de nuevo
            if !storyId.isEmpty {
                UserDefaults.standard.set(true, forKey: persistenceKey)
            }
        }
    }
}
