import SwiftUI
import AVFoundation
import CoreMedia

// MARK: - Sticker de clima (familia tap-cycle)
struct AnimatedWeatherSticker: View {
    let weatherSymbol: String
    let temperature: String
    var styleVariant: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let foregroundStyle = momentsTapCycleStickerForegroundStyle(for: colorScheme, styleVariant: styleVariant)

        HStack(spacing: 8) {
            Image(systemName: weatherStickerSystemImageName(for: weatherSymbol))
                .font(.system(size: 20, weight: .heavy))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(foregroundStyle)
                .frame(width: 20, height: 20)

            Text(temperature)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(foregroundStyle)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(momentsTapCycleStickerBackground(for: colorScheme, styleVariant: styleVariant))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    momentsTapCycleStickerStroke(for: colorScheme, styleVariant: styleVariant),
                    lineWidth: momentsTapCycleStickerStrokeWidth(styleVariant: styleVariant)
                )
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Floating Hearts Animation Components

struct FloatingHeart: Identifiable, Equatable {
    let id = UUID()
    let emoji: String
    let startX: CGFloat
    let startY: CGFloat
    let fontSize: CGFloat
    let rotation: Double
    let delay: TimeInterval
    let duration: TimeInterval
    let lateralDrift: CGFloat
    let verticalTravel: CGFloat
    let peakScale: CGFloat
    let targetScale: CGFloat
    let rotationDelta: Double
    let swayAmplitude: CGFloat
    let swayFrequency: Double

    init(
        emoji: String,
        startX: CGFloat,
        startY: CGFloat,
        fontSize: CGFloat = 44,
        rotation: Double = 0,
        delay: TimeInterval = 0,
        duration: TimeInterval = 2.0,
        lateralDrift: CGFloat = 0,
        verticalTravel: CGFloat = 400,
        peakScale: CGFloat = 1.08,
        targetScale: CGFloat = 1.1,
        rotationDelta: Double = 0,
        swayAmplitude: CGFloat = 0,
        swayFrequency: Double = 0
    ) {
        self.emoji = emoji
        self.startX = startX
        self.startY = startY
        self.fontSize = fontSize
        self.rotation = rotation
        self.delay = delay
        self.duration = duration
        self.lateralDrift = lateralDrift
        self.verticalTravel = verticalTravel
        self.peakScale = peakScale
        self.targetScale = targetScale
        self.rotationDelta = rotationDelta
        self.swayAmplitude = swayAmplitude
        self.swayFrequency = swayFrequency
    }
}

struct FloatingHeartsView: View {
    let hearts: [FloatingHeart]
    var containerSize: CGSize = .zero

    var body: some View {
        ZStack {
            ForEach(hearts) { heart in
                FloatingHeartParticleView(heart: heart)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .allowsHitTesting(false)
    }
}

struct FloatingHeartParticleView: View {
    let heart: FloatingHeart
    @State private var progress: CGFloat = 0.0

    var body: some View {
        Text(heart.emoji)
            .font(.system(size: heart.fontSize))
            .shadow(color: .black.opacity(0.25), radius: heart.fontSize > 42 ? 3 : 1.5, x: 0, y: 1)
            .modifier(FloatingHeartFlightModifier(progress: progress, heart: heart))
            .onAppear {
                startAnimation()
            }
    }

    private func startAnimation() {
        if MotionPolicy.reduceMotion {
            progress = 0.0
            withAnimation(.easeOut(duration: min(heart.duration, 1.4))) {
                progress = 1.0
            }
            return
        }

        progress = 0.0
        withAnimation(.easeOut(duration: heart.duration).delay(heart.delay)) {
            progress = 1.0
        }
    }
}

/// Animatable modifier that SwiftUI interpolates per-frame, so all
/// derived transforms (sway, opacity fade-in/out, scale pop) evaluate
/// with intermediate `progress` values rather than just start/end.
private struct FloatingHeartFlightModifier: ViewModifier, Animatable {
    var progress: CGFloat
    let heart: FloatingHeart

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scaleValue)
            .opacity(opacityValue)
            .rotationEffect(.degrees(rotationValue))
            .position(
                x: heart.startX + xOffset,
                y: heart.startY + yOffset
            )
    }

    // MARK: - Per-frame derived values

    private var yOffset: CGFloat {
        if MotionPolicy.reduceMotion {
            return -progress * heart.verticalTravel * 0.55
        }
        return -progress * heart.verticalTravel
    }

    private var xOffset: CGFloat {
        if MotionPolicy.reduceMotion {
            return progress * heart.lateralDrift * 0.5
        }
        let sway = sin(progress * .pi * CGFloat(heart.swayFrequency)) * heart.swayAmplitude
        let drift = progress * heart.lateralDrift
        return sway + drift
    }

    private var scaleValue: CGFloat {
        if MotionPolicy.reduceMotion {
            return progress < 0.2 ? (progress / 0.2) * heart.peakScale : heart.peakScale
        }

        if progress < 0.15 {
            return (progress / 0.15) * heart.peakScale
        } else {
            let t = (progress - 0.15) / 0.85
            return heart.peakScale + t * (heart.targetScale - heart.peakScale)
        }
    }

    private var opacityValue: Double {
        if progress < 0.05 {
            return Double(progress / 0.05)
        } else if progress > 0.75 {
            return Double(1.0 - (progress - 0.75) / 0.25)
        } else {
            return 1.0
        }
    }

    private var rotationValue: Double {
        heart.rotation + Double(progress) * heart.rotationDelta
    }
}

// MARK: - ✅ UIKit Wrapper to Disable Automatic Keyboard Avoidance
/// This wrapper prevents the automatic keyboard avoidance behavior that SwiftUI inherits from UIKit.
/// Use this when you need full control over keyboard positioning in fullScreenCover presentations.
struct KeyboardIgnoringContainer<Content: View>: UIViewControllerRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> KeyboardIgnoringHostingController<Content> {
        let controller = KeyboardIgnoringHostingController(rootView: content)
        return controller
    }

    func updateUIViewController(_ uiViewController: KeyboardIgnoringHostingController<Content>, context: Context) {
        uiViewController.rootView = content
    }
}

/// Custom UIHostingController that prevents keyboard from pushing content up
class KeyboardIgnoringHostingController<Content: View>: UIHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        // Disable automatic keyboard adjustment
        // This is done by not adjusting the safe area insets when keyboard appears
    }

    // Override to prevent keyboard from affecting layout
    override var additionalSafeAreaInsets: UIEdgeInsets {
        get { .zero }
        set { /* Ignore changes from keyboard */ }
    }
}

// MARK: - 🎥 NUEVO REPRODUCTOR DEDICADO PARA STICKERS
// Diseñado específicamente para el visor de historias, manejando el ciclo de vida y loop correctamente.
struct StickerVideoPlayer: UIViewRepresentable {
    let url: URL
    var isMuted: Bool = true
    var onDuration: ((TimeInterval) -> Void)? = nil

    func makeUIView(context: Context) -> StickerPlayerUIView {
        let view = StickerPlayerUIView(frame: .zero)
        return view
    }

    func updateUIView(_ uiView: StickerPlayerUIView, context: Context) {
        uiView.onDuration = onDuration
        uiView.play(url: url, isMuted: isMuted)
    }

    class StickerPlayerUIView: UIView {
        private let playerLayer = AVPlayerLayer()
        private var player: AVPlayer?
        private var playerItem: AVPlayerItem?
        private var loopObserver: NSObjectProtocol?
        private var reportedDurationURL: URL?
        var onDuration: ((TimeInterval) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupLayer()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupLayer() {
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.backgroundColor = UIColor.clear.cgColor // ✅ Transparente para ver la base estática
            layer.addSublayer(playerLayer)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }

        func play(url: URL, isMuted: Bool) {
            if !isMuted {
                // Misma sesión que el visor: .playback ignora el switch de silencio.
                // Hay que encolarla antes de play(); si no, el primer arranque queda mudo.
                StoryAudioSession.activate()
            }

            // Evitar recrear si es la misma URL
            if let currentUrl = (player?.currentItem?.asset as? AVURLAsset)?.url, currentUrl == url {
                player?.isMuted = isMuted
                player?.volume = isMuted ? 0 : 1
                if player?.timeControlStatus != .playing {
                    player?.play()
                }
                return
            }

            // Limpiar observador anterior
            if let observer = loopObserver {
                NotificationCenter.default.removeObserver(observer)
            }

            let item = AVPlayerItem(url: url)
            playerItem = item

            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.isMuted = isMuted
            newPlayer.volume = isMuted ? 0 : 1
            newPlayer.automaticallyWaitsToMinimizeStalling = false // Intentar reproducir ASAP

            player = newPlayer
            playerLayer.player = newPlayer

            newPlayer.play()
            loadDuration(from: item, url: url)

            // ✅ Loop Infinito Robust
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak newPlayer] _ in
                newPlayer?.seek(to: .zero)
                newPlayer?.play()
            }
        }

        private func emitDuration(_ seconds: TimeInterval, for url: URL) {
            guard reportedDurationURL != url else { return }
            reportedDurationURL = url
            DispatchQueue.main.async { [weak self] in
                self?.onDuration?(seconds)
            }
        }

        private func loadDuration(from item: AVPlayerItem, url: URL) {
            let immediate = item.duration
            if immediate.isNumeric {
                let seconds = CMTimeGetSeconds(immediate)
                if seconds.isFinite, seconds > 0 {
                    emitDuration(seconds, for: url)
                    return
                }
            }
            Task { [weak self] in
                guard let asset = item.asset as? AVURLAsset else { return }
                guard let duration = try? await asset.load(.duration) else { return }
                let seconds = CMTimeGetSeconds(duration)
                guard seconds.isFinite, seconds > 0 else { return }
                self?.emitDuration(seconds, for: url)
            }
        }

        deinit {
            if let observer = loopObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            player?.pause()
            player = nil
        }
    }
}
