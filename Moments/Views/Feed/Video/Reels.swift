import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth
import Combine

private struct ReelsStoryRoute: Identifiable {
    let id: String
}

/// Lee la posición animada real del sheet para que el Reel siga el gesto.
private struct ReelCommentsSheetObserver: UIViewRepresentable {
    let onOriginYChanged: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOriginYChanged: onOriginYChanged)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            context.coordinator.startObserving(view.superview?.superview ?? view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onOriginYChanged = onOriginYChanged
    }

    final class Coordinator {
        var onOriginYChanged: (CGFloat) -> Void
        private weak var observedView: UIView?
        private var displayLink: CADisplayLink?
        private var lastOriginY: CGFloat?

        init(onOriginYChanged: @escaping (CGFloat) -> Void) {
            self.onOriginYChanged = onOriginYChanged
        }

        deinit {
            displayLink?.invalidate()
        }

        func startObserving(_ view: UIView) {
            observedView = view
            displayLink?.invalidate()
            let displayLink = CADisplayLink(target: self, selector: #selector(readPresentationFrame))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }

        @objc private func readPresentationFrame() {
            guard let observedView,
                  let presentationLayer = observedView.layer.presentation() else { return }
            let originY = presentationLayer.convert(presentationLayer.frame, to: nil).origin.y
            guard lastOriginY.map({ abs($0 - originY) > 0.25 }) ?? true else { return }
            lastOriginY = originY
            onOriginYChanged(originY)
        }
    }
}

private func flyingLerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

/// Convierte el progreso global del vuelo en una fase local suave y reversible.
/// El vídeo lidera la transición y el chrome se incorpora después.
private func flyingPhaseProgress(_ progress: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
    guard end > start else { return progress >= end ? 1 : 0 }
    let x = min(max((progress - start) / (end - start), 0), 1)
    return x * x * (3 - (2 * x))
}

/// Radio adaptativo: parte del de la card, crece a mitad del vuelo y cae a 0 al completar.
private func flyingAdaptiveCornerRadius(_ t: CGFloat) -> CGFloat {
    let card = FeedMomentCardLayout.mediaCornerRadius
    let peak: CGFloat = 40
    let x = min(max(t, 0), 1)
    if x <= 0.001 { return card }
    if x >= 0.995 { return 0 }
    let bump = sin(.pi * x)
    let base = flyingLerp(card, 0, x * x)
    return max(0, base + (peak - card) * bump)
}

/// Marco interpolado card → pantalla (coordenadas locales del contenedor).
private struct FlyingCardFrame {
    let rect: CGRect
    let cornerRadius: CGFloat

    static func compute(
        containerSize: CGSize,
        sourceRect: CGRect,
        containerOriginInGlobal: CGPoint,
        progress: CGFloat
    ) -> FlyingCardFrame {
        let from = CGRect(
            x: sourceRect.minX - containerOriginInGlobal.x,
            y: sourceRect.minY - containerOriginInGlobal.y,
            width: sourceRect.width,
            height: sourceRect.height
        )
        let hasFrom = from.width > 8 && from.height > 8
            && containerSize.width > 0 && containerSize.height > 0
        let t = hasFrom ? progress : 1
        guard hasFrom, t < 0.999 else {
            return FlyingCardFrame(
                rect: CGRect(origin: .zero, size: containerSize),
                cornerRadius: 0
            )
        }
        return FlyingCardFrame(
            rect: CGRect(
                x: flyingLerp(from.minX, 0, t),
                y: flyingLerp(from.minY, 0, t),
                width: flyingLerp(from.width, containerSize.width, t),
                height: flyingLerp(from.height, containerSize.height, t)
            ),
            cornerRadius: flyingAdaptiveCornerRadius(t)
        )
    }
}

/// `Shape` animable: SwiftUI interpola el recorte en cada frame, en lugar de
/// depender de que `frame` y `offset` dentro de una máscara hereden la animación.
private struct FlyingCardMaskShape: Shape {
    let sourceRect: CGRect
    let containerOriginInGlobal: CGPoint
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let frame = FlyingCardFrame.compute(
            containerSize: rect.size,
            sourceRect: sourceRect,
            containerOriginInGlobal: containerOriginInGlobal,
            progress: progress
        )
        return Path(
            roundedRect: frame.rect,
            cornerRadius: frame.cornerRadius
        )
    }
}

/// Reels a tamaño real; la tarjeta crece y va revelando media + chrome (no escala todo junto).
private struct FlyingCardClipModifier: ViewModifier {
    let sourceRect: CGRect
    let progress: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            content
                .frame(width: geo.size.width, height: geo.size.height)
                .mask(
                    FlyingCardMaskShape(
                        sourceRect: sourceRect,
                        containerOriginInGlobal: origin,
                        progress: progress
                    )
                )
        }
        .ignoresSafeArea()
    }
}

private extension View {
    func flyingCardClip(sourceRect: CGRect, progress: CGFloat) -> some View {
        modifier(FlyingCardClipModifier(sourceRect: sourceRect, progress: progress))
    }
}

// ✅ PRIVACIDAD: ReelsViewer solo muestra videos que ya pasaron los filtros de privacidad
struct ReelsViewer: View {
    let videos: [VideoMoment]
    let startIndex: Int
    let initialStartSeconds: Double
    let handoffConsumerId: String?
    let sourceRectInWindow: CGRect
    let onWillDismiss: (() -> Void)?
    let onClosed: (() -> Void)?
    @State private var currentIndex: Int = 0
    @State private var scrollPosition: Int?
    @State private var isDismissRequested = false
    @State private var expandProgress: CGFloat
    @Environment(\.dismiss) private var dismiss

    private var canFlyFromCard: Bool {
        sourceRectInWindow.width > 8 && sourceRectInWindow.height > 8
    }

    init(
        videos: [VideoMoment],
        startIndex: Int = 0,
        initialStartSeconds: Double = 0,
        handoffConsumerId: String? = nil,
        sourceRectInWindow: CGRect = .zero,
        onWillDismiss: (() -> Void)? = nil,
        onClosed: (() -> Void)? = nil
    ) {
        self.videos = videos
        self.startIndex = startIndex
        self.initialStartSeconds = initialStartSeconds
        self.handoffConsumerId = handoffConsumerId
        self.sourceRectInWindow = sourceRectInWindow
        self.onWillDismiss = onWillDismiss
        self.onClosed = onClosed
        let safeStart = videos.isEmpty ? 0 : min(max(0, startIndex), videos.count - 1)
        self._currentIndex = State(initialValue: safeStart)
        self._scrollPosition = State(initialValue: safeStart)
        let fly = sourceRectInWindow.width > 8 && sourceRectInWindow.height > 8
        self._expandProgress = State(initialValue: fly ? 0 : 1)
    }

    var body: some View {
        ZStack {
            if !videos.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            // id por índice de sesión (lista congelada) — evita recrear páginas al swipe
                            ForEach(Array(videos.enumerated()), id: \.offset) { index, video in
                                ReelsPagerPage(
                                    index: index,
                                    video: video,
                                    currentIndex: currentIndex,
                                    startIndex: startIndex,
                                    initialStartSeconds: initialStartSeconds,
                                    handoffConsumerId: index == startIndex ? handoffConsumerId : nil,
                                    flyProgress: expandProgress,
                                    onClose: closeViewer
                                )
                                .id(index)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollDisabled(expandProgress < 0.98)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $scrollPosition)
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea(.container, edges: .all)
                    .flyingCardClip(sourceRect: sourceRectInWindow, progress: expandProgress)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 30)
                            .onEnded { value in
                                guard expandProgress > 0.98,
                                      abs(value.translation.width) > 100,
                                      abs(value.translation.width) > abs(value.translation.height) else {
                                    return
                                }

                                HapticManager.shared.lightImpact()
                                closeViewer()
                            }
                    )
                    .onAppear {
                        scrollPosition = currentIndex
                        // LazyVStack a veces no ancla el scrollPosition inicial → vídeo 0 en vez del tap.
                        proxy.scrollTo(currentIndex, anchor: .top)
                        preloadUpcomingVideos(from: currentIndex)
                    }
                    .onChange(of: scrollPosition) { _, newIndex in
                        guard let newIndex, newIndex != currentIndex else { return }
                        guard videos.indices.contains(newIndex) else { return }
                        currentIndex = newIndex
                    }
                    .onChange(of: currentIndex) { _, newIndex in
                        preloadUpcomingVideos(from: newIndex)
                    }
                    .onDisappear {
                        ReelPrebufferService.shared.discard()
                    }
                }
            }
        }
        .onAppear {
            guard canFlyFromCard, expandProgress < 1 else { return }
            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.reelsFly) {
                expandProgress = 1
            }
        }
        // Status bar visible: el chrome top se ancla bajo el safe area.
    }

    private func closeViewer() {
        guard !isDismissRequested else { return }
        isDismissRequested = true
        onWillDismiss?()
        let finish: () -> Void = {
            // El layer sigue en Reels hasta que el encoger termina.
            FlyingVideoSurface.shared.land(consumerId: handoffConsumerId)
            VideoLayerLease.shared.returnToFeed()
            if let onClosed {
                onClosed()
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dismiss()
                }
            }
        }
        guard canFlyFromCard,
              expandProgress > 0.01,
              currentIndex == startIndex,
              !MotionPolicy.reduceMotion else {
            finish()
            return
        }
        withAnimation(MotionPolicy.Spring.reelsFly, completionCriteria: .logicallyComplete) {
            expandProgress = 0
        } completion: {
            finish()
        }
    }
    
    // ✅ INSTANT PLAYBACK: Lógica de preloading para Reels
    private func preloadUpcomingVideos(from index: Int) {
        // Precargar solo los próximos 2 vídeos para no saturar la caché
        // (maxCacheSize) ni la red/decoders. Antes eran 6 × variantes ABR.
        let preloadCount = 2
        let endIndex = min(index + preloadCount, videos.count)
        
        if index + 1 < endIndex {
            let upcomingVideos = videos[(index + 1)..<endIndex]
            let urls = upcomingVideos.flatMap(\.preloadURLStrings)
            VideoPreloader.shared.preloadAssets(urls: urls)

            let nextVideo = videos[index + 1]
            let nextURL = nextVideo.moment.videoPlaybackSource()?.playbackURL ?? nextVideo.playbackURL
            if let nextURL {
                ReelPrebufferService.shared.prebuffer(urlString: nextURL.absoluteString)
            }
        }
    }
}

private struct ReelsPagerPage: View {
    let index: Int
    let video: VideoMoment
    let currentIndex: Int
    let startIndex: Int
    let initialStartSeconds: Double
    let handoffConsumerId: String?
    var flyProgress: CGFloat = 1
    let onClose: () -> Void

    var body: some View {
        Group {
            if abs(index - currentIndex) <= 1 {
                ReelVideoView(
                    video: video,
                    isCurrentVideo: currentIndex == index,
                    startAtSeconds: index == startIndex ? initialStartSeconds : 0,
                    handoffConsumerId: handoffConsumerId,
                    flyProgress: flyProgress,
                    onClose: onClose
                )
            } else {
                // Páginas lejanas: poster (nunca negro vacío al pasar rápido).
                ReelsPosterPage(video: video)
            }
        }
        .containerRelativeFrame(.vertical)
    }
}

private struct ReelsPosterPage: View {
    let video: VideoMoment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AdaptiveColors(colorScheme: colorScheme).surfaceBackground
            VideoPosterOverlay(
                posterURLString: video.posterURLString,
                isReadyToPlay: false,
                contentMode: .fit
            )
        }
    }
}

struct ReelVideoView: View {
    let video: VideoMoment
    let isCurrentVideo: Bool
    let startAtSeconds: Double
    var handoffConsumerId: String? = nil
    var flyProgress: CGFloat = 1
    let onClose: () -> Void
    
    @StateObject private var playerManager = ReelVideoPlayerManager()
    @State private var showUserActions = false
    @State private var showComments = false
    @State private var commentsDetent: PresentationDetent = .medium
    @State private var commentsSheetOriginY: CGFloat?
    @State private var commentCount: Int = 0
    @State private var isDoubleTapAnimating = false
    @State private var showContextMenu = false
    @State private var showReportSheet = false
    @State private var showDeleteAlert = false
    @State private var isSaved: Bool = false
    @State private var profileRoute: FeedProfileSheetRoute?
    @Namespace private var profileZoomNamespace
    @State private var hasStory = false
    @State private var hasUnseenStory = false
    @State private var storyCount: Int = 0
    @State private var storyViewedStatus: [Bool] = []
    @State private var storyAudiences: [String?] = []
    @State private var storyRoute: ReelsStoryRoute?
    @State private var liveAuthorUsername: String = ""
    @State private var isDraggingProgress = false
    @State private var wasPlayingBeforeDrag = false
    @State private var isReelCaptionExpanded = false
    @State private var isLayerReadyForDisplay = false
    
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var firestoreService: FirestoreService
    private let privacyService = PrivacyService()

    private var chromeInteractive: Bool {
        flyProgress > 0.98
    }

    private var topChromeProgress: CGFloat {
        flyingPhaseProgress(flyProgress, from: 0.18, to: 0.58)
    }

    private var actionChromeProgress: CGFloat {
        flyingPhaseProgress(flyProgress, from: 0.34, to: 0.76)
    }

    private var metadataChromeProgress: CGFloat {
        flyingPhaseProgress(flyProgress, from: 0.42, to: 0.84)
    }

    private var commentChromeProgress: CGFloat {
        flyingPhaseProgress(flyProgress, from: 0.60, to: 0.94)
    }

    private var displayAuthorUsername: String {
        let fallback = video.moment.username
        let live = liveAuthorUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return live.isEmpty ? fallback : live
    }

    private var layerConsumerId: String {
        if let handoffConsumerId, !handoffConsumerId.isEmpty {
            return handoffConsumerId
        }
        return GlobalVideoManager.profileVideoConsumerId(for: video.moment)
    }

    private var canvasColor: Color {
        AdaptiveColors(colorScheme: colorScheme).surfaceBackground
    }

    private var playerVideoGravity: AVLayerVideoGravity {
        if handoffConsumerId != nil || flyProgress < 0.995 {
            return .resizeAspectFill
        }
        return videoContentMode == .fill ? .resizeAspectFill : .resizeAspect
    }

    private var bottomBarBackgroundColor: Color {
        canvasColor
    }

    private var chromePrimaryColor: Color {
        colorScheme == .dark ? .white : Color(hex: "0B1215")
    }

    private var chromeSecondaryColor: Color {
        colorScheme == .dark ? .white.opacity(0.78) : Color(hex: "0B1215").opacity(0.72)
    }

    private var chromeTertiaryColor: Color {
        colorScheme == .dark ? .white.opacity(0.72) : Color(hex: "0B1215").opacity(0.58)
    }

    private var bottomBarHeight: CGFloat {
        46
    }

    private var progressLineHeight: CGFloat {
        2.5
    }

    /// GeometryReader bajo `ignoresSafeArea` suele dar insets = 0; leemos los reales del window.
    private var keyWindowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
    }

    private var systemSafeTopInset: CGFloat {
        keyWindowSafeAreaInsets.top
    }

    private var systemSafeBottomInset: CGFloat {
        keyWindowSafeAreaInsets.bottom
    }

    @ViewBuilder
    private var reelCommentBar: some View {
        HStack {
            if !video.moment.disableComments {
                Button(action: {
                    commentsDetent = .medium
                    showComments = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(chromeTertiaryColor)

                        Text(NSLocalizedString("comments.add.placeholder", comment: "Add comment placeholder"))
                            .font(.system(size: legacyPoppinsSize(15)))
                            .foregroundStyle(chromeTertiaryColor)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.06))
                    )
                    .overlay(
                        Capsule()
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.momentsPressSubtle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, minHeight: bottomBarHeight, alignment: .bottom)
        .background(bottomBarBackgroundColor)
    }
    
    var body: some View {
        GeometryReader { geometry in
            // Con ScrollView + ignoresSafeArea, geometry.safeAreaInsets suele ser 0.
            let safeTop = max(geometry.safeAreaInsets.top, systemSafeTopInset)
            let bottomInset = max(geometry.safeAreaInsets.bottom, systemSafeBottomInset)
            // Baja el input hacia el home indicator (sigue usable).
            let chromeBottomPadding = max(2, bottomInset - 12)
            // Caption acaba justo donde empieza la línea de progreso.
            let bottomChromeClearance = progressLineHeight + bottomBarHeight + chromeBottomPadding
            let sheetBottomPadding = commentsSheetOriginY.map {
                max(geometry.size.height - $0, 0)
            } ?? 0
            let mediumDetentHeight = max(geometry.size.height * 0.5, 1)
            let sheetProgress = min(sheetBottomPadding / mediumDetentHeight, 1)
            let videoTopOffset = sheetProgress * safeTop
            let videoScale = max(
                (geometry.size.height - sheetBottomPadding - videoTopOffset) / geometry.size.height,
                0.04
            )

            ZStack {
                // Video Player completamente fullscreen sin controles nativos
                ZStack {
                    if let player = playerManager.player {
                        VideoPlayerRepresentable(
                            player: player,
                            videoGravity: playerVideoGravity,
                            consumerId: layerConsumerId,
                            layerRole: .reels,
                            cornerRadius: 0,
                            readinessDelay: handoffConsumerId == nil && startAtSeconds < 0.75 ? 0.09 : 0,
                            showControls: .constant(false), // Siempre oculto
                            progress: $playerManager.progress,
                            isBuffering: $playerManager.isBuffering,
                            isReadyForDisplay: $isLayerReadyForDisplay
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    } else if handoffConsumerId == nil {
                        canvasColor
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }

                    // El handoff desde feed ya trae el mismo AVPlayer reproduciendo:
                    // no interponer un póster, porque convertiría la continuidad en
                    // un fotograma congelado. Los reels sin handoff sí lo necesitan.
                    if handoffConsumerId == nil {
                        VideoPosterOverlay(
                            posterURLString: video.posterURLString,
                            isReadyToPlay: playerManager.isLoaded
                                && playerManager.player != nil
                                && isLayerReadyForDisplay,
                            contentMode: videoContentMode
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(videoScale, anchor: .top)
                .offset(y: videoTopOffset)
                
                // Capa invisible para capturar gestos de reproducción y likes en el fondo,
                // evitando que interfieran con los botones interactivos del overlay superior.
                Color.black.opacity(0.001)
                    .ignoresSafeArea(.all)
                    .allowsHitTesting(!showComments && flyProgress > 0.95)
                    .onTapGesture {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        
                        // Solo toggle play/pause silencioso
                        playerManager.togglePlayback()
                    }
                    .onTapGesture(count: 2) {
                        // Double tap para like
                        handleDoubleTap()
                    }
                
                // Double tap heart animation - usando feel reaction color
                if isDoubleTapAnimating && !showComments {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundStyle(.pink) // Color de la reacción "feel"
                        .scaleEffect(isDoubleTapAnimating ? 1.5 : 0.1)
                        .opacity(isDoubleTapAnimating ? 0 : 1)
                        .animation(MotionPolicy.animation(MotionPolicy.Spring.delight, value: isDoubleTapAnimating), value: isDoubleTapAnimating)
                }

                // Al pausar: mute (pequeño) + play centrado con glass native.
                if playerManager.player != nil, !playerManager.isPlaying, !isDraggingProgress, !showComments {
                    VStack(spacing: 14) {
                        Button(action: {
                            HapticManager.shared.lightImpact()
                            playerManager.toggleMute()
                        }) {
                            Image(systemName: playerManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(chromePrimaryColor)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.001))
                                .contentShape(Circle())
                                .momentsChromeGlass(in: Circle(), interactive: true, style: .native)
                        }
                        .buttonStyle(.momentsPress(scale: 0.9, haptic: .none))
                        .accessibilityLabel(
                            playerManager.isMuted
                            ? NSLocalizedString("feed.video.unmute", comment: "Unmute video")
                            : NSLocalizedString("feed.video.mute", comment: "Mute video")
                        )

                        Button(action: {
                            HapticManager.shared.lightImpact()
                            playerManager.play()
                        }) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(chromePrimaryColor)
                                .offset(x: 1) // Óptico: el triángulo play se ve centrado
                                .frame(width: 64, height: 64)
                                .background(Color.white.opacity(0.001))
                                .contentShape(Circle())
                                .momentsChromeGlass(in: Circle(), interactive: true, style: .native)
                        }
                        .buttonStyle(.momentsPress(scale: 0.92, haptic: .none))
                        .accessibilityLabel(NSLocalizedString("feed.video.play", comment: "Play video"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .opacity(Double(topChromeProgress))
                    .allowsHitTesting(chromeInteractive)
                    .zIndex(40)
                }
                
                // Sin controles visuales - solo play/pause silencioso
                VStack(spacing: 0) {
                    HStack {
                        Spacer()

                        Button(action: {
                            HapticManager.shared.mediumImpact()
                            onClose()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(chromePrimaryColor)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.001))
                                .contentShape(Circle())
                                .momentsChromeGlass(in: Circle(), interactive: true, style: .native)
                        }
                        .buttonStyle(.momentsPress(scale: 0.9, haptic: .none))
                    }
                    .padding(.horizontal, 20)
                    // Bajo la status bar (safe area), con un pequeño respiro.
                    .padding(.top, safeTop + 8)
                    .opacity(Double(topChromeProgress))
                    .offset(y: -6 * (1 - topChromeProgress))

                    Spacer()

                    // Gradiente con altura estática — sin animación propia de frame.
                    // Esto elimina la "doble animación" que causaba que el header
                    // y el caption se movieran de forma desincronizada al expandir.
                    LinearGradient(
                        colors: [Color.clear, canvasColor.opacity(0.2), canvasColor.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 300)
                    .overlay(alignment: .bottom) {
                        HStack(alignment: .bottom, spacing: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Button(action: {
                                        if !video.moment.authorId.isEmpty {
                                            if hasStory {
                                                storyRoute = ReelsStoryRoute(id: video.moment.authorId)
                                            } else {
                                                profileRoute = FeedProfileSheetRoute(userId: video.moment.authorId)
                                            }
                                        }
                                    }) {
                                        AsyncProfileImageView(userId: video.moment.authorId)
                                            .frame(width: 42, height: 42)
                                            .clipShape(Circle())
                                            .userProfileZoomSource(
                                                userId: video.moment.authorId,
                                                namespace: profileZoomNamespace,
                                                cornerRadius: 21
                                            )
                                            .overlay(
                                                StorySegmentedRing(
                                                    storyCount: storyCount,
                                                    hasStory: hasStory,
                                                    hasUnseenStory: hasUnseenStory,
                                                    storyViewedStatus: storyViewedStatus,
                                                    storyAudiences: storyAudiences,
                                                    isOwnStory: video.moment.authorId == Auth.auth().currentUser?.uid,
                                                    colorScheme: colorScheme,
                                                    ringSize: 42,
                                                    lineWidth: 2.5
                                                )
                                            )
                                    }
                                    .buttonStyle(.momentsPress(scale: 0.94, haptic: .none))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Button(action: {
                                            if !video.moment.authorId.isEmpty {
                                                profileRoute = FeedProfileSheetRoute(userId: video.moment.authorId)
                                            }
                                        }) {
                                            HStack(spacing: 6) {
                                                Text(displayAuthorUsername)
                                                    .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                                                    .foregroundStyle(chromePrimaryColor)
                                                    .lineLimit(1)

                                                if video.moment.authorId == Auth.auth().currentUser?.uid {
                                                    CurrentUserVerifiedBadge(size: 14)
                                                } else {
                                                    VerifiedBadgeView(userId: video.moment.authorId, size: 14)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)

                                        HStack(spacing: 8) {
                                            Text(formatTimeAgo(video.moment.timestamp))
                                                .font(.system(size: legacyPoppinsSize(12)))
                                                .foregroundStyle(chromeSecondaryColor)

                                            if let location = video.moment.location, !location.isEmpty {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "location.fill")
                                                        .font(.system(size: 9))
                                                    Text(location)
                                                        .lineLimit(1)
                                                }
                                                .font(.system(size: legacyPoppinsSize(12)))
                                                .foregroundStyle(chromeTertiaryColor)
                                            }
                                        }
                                    }
                                }

                                MomentCaptionView(
                                    moment: video.moment,
                                    style: .reels,
                                    colorScheme: colorScheme,
                                    onHashtagTap: { _ in },
                                    isReelsCaptionExpanded: $isReelCaptionExpanded
                                )
                                .padding(.leading, -12)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, bottomChromeClearance + 6)
                            .opacity(Double(metadataChromeProgress))
                            .offset(y: 10 * (1 - metadataChromeProgress))

                            VStack(spacing: 12) {
                                EpicReactionButton(
                                    moment: video.moment,
                                    showCount: video.moment.authorId == Auth.auth().currentUser?.uid || !video.moment.hideLikeCounts,
                                    size: 44,
                                    emojiSize: 22,
                                    pickerXOffset: -110
                                )
                                .environmentObject(firestoreService)

                                if !video.moment.disableComments {
                                    EnhancedReelActionButton(
                                        icon: "bubble.left.fill",
                                        count: commentCount,
                                        isActive: commentCount > 0,
                                        activeColor: .blue,
                                        action: {
                                            commentsDetent = .medium
                                            showComments = true
                                        }
                                    )
                                }

                                EnhancedReelActionButton(
                                    icon: AttachmentIcon.bookmark.rawValue,
                                    count: nil,
                                    isActive: isSaved,
                                    activeColor: .yellow,
                                    action: {
                                        toggleSave()
                                    }
                                )

                                EnhancedReelActionButton(
                                    icon: "ellipsis",
                                    count: nil,
                                    isActive: false,
                                    activeColor: .white,
                                    action: {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            showContextMenu.toggle()
                                        }
                                    }
                                )
                            }
                            .padding(.bottom, bottomChromeClearance + 18)
                            .opacity(Double(actionChromeProgress))
                            .offset(x: 8 * (1 - actionChromeProgress))
                        }
                        .padding(.horizontal, 20)
                        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: isReelCaptionExpanded)
                    }
                }
                .opacity(showComments ? 0 : 1)
                .allowsHitTesting(!showComments && chromeInteractive)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.smooth(duration: 0.32), value: showComments)
            .ignoresSafeArea(.container, edges: .all)
            .overlay(alignment: .bottom) {
                // Contenido por encima del home indicator; fondo Moments hasta el borde.
                // Se oculta con el context menu para que nunca quede por encima del sheet.
                if !showContextMenu && !showComments {
                    // Progress arriba del todo (donde acaba el VStack de caption); input abajo.
                    VStack(spacing: 0) {
                        if playerManager.duration > 0 {
                            let barHeight: CGFloat = isDraggingProgress ? 6 : progressLineHeight
                            let thumbSize: CGFloat = 12

                            ZStack(alignment: .topLeading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.24))
                                    .frame(height: barHeight)

                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "4158D0"), Color(hex: "C850C0")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(0, geometry.size.width * playerManager.progress), height: barHeight)

                                if isDraggingProgress {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: thumbSize, height: thumbSize)
                                        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                                        .offset(
                                            x: (geometry.size.width * playerManager.progress) - (thumbSize / 2),
                                            y: (barHeight - thumbSize) / 2
                                        )
                                        .transition(MotionPolicy.Transition.enterPop)
                                }

                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 28)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                if !isDraggingProgress {
                                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                                    haptic.impactOccurred()

                                                    wasPlayingBeforeDrag = playerManager.isPlaying
                                                    playerManager.pause()

                                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                                        isDraggingProgress = true
                                                    }
                                                }
                                                let stableTouchX = value.startLocation.x + value.translation.width
                                                let newProgress = max(0, min(1, stableTouchX / geometry.size.width))
                                                playerManager.updateProgress(to: newProgress)
                                                playerManager.seekToProgress(newProgress)
                                            }
                                            .onEnded { value in
                                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                                    isDraggingProgress = false
                                                }
                                                let stableTouchX = value.startLocation.x + value.translation.width
                                                let finalProgress = max(0, min(1, stableTouchX / geometry.size.width))
                                                playerManager.seekToProgress(finalProgress, precise: true)

                                                if wasPlayingBeforeDrag {
                                                    playerManager.play()
                                                }
                                            }
                                    )
                            }
                            .frame(
                                width: geometry.size.width,
                                height: isDraggingProgress ? 6 : progressLineHeight,
                                alignment: .top
                            )
                            .zIndex(1)
                        }

                        reelCommentBar
                            .zIndex(0)
                    }
                    .padding(.bottom, chromeBottomPadding)
                    .background(bottomBarBackgroundColor)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .opacity(Double(commentChromeProgress))
                    .offset(y: 8 * (1 - commentChromeProgress))
                    .allowsHitTesting(chromeInteractive)
                }
            }
            // Context menu SIEMPRE por encima del chrome inferior (overlay posterior + clearance).
            .overlay {
                if showContextMenu {
                    ModernContextMenuOverlay(
                        moment: video.moment,
                        isPresented: $showContextMenu,
                        onEdit: {
                            // No implementado en reels por ahora
                        },
                        onDelete: {
                            showDeleteAlert = true
                        },
                        onReport: {
                            // showReportSheet = true // ❌ Ya no se usa sheet
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .zIndex(1000)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showContextMenu)
                }
            }
        }
        /*.sheet(isPresented: $showReportSheet) {
            ReportBottomSheet(moment: video.moment)
        }*/
        .fullScreenCover(item: $profileRoute) { route in
            NavigationStack {
                UserProfileView(userId: route.userId)
            }
        }
        .fullScreenCover(item: $storyRoute) { route in
            StoriesView(startWithUserId: .constant(route.id))
                .environmentObject(firestoreService)
        }
        .alert("reels.delete.title", isPresented: $showDeleteAlert) {
            Button("common.delete", role: .destructive) {
                deleteMoment()
            }
            Button("common.cancel", role: .cancel) { }
        } message: {
            Text("reels.delete.message")
        }
        .onAppear {
            if isCurrentVideo {
                setupVideo()
                loadVideoData()
                checkUserStories()
                refreshAuthorUsername()
                preloadNextVideos()
            }
            checkIfSaved()
        }
        .onChange(of: firestoreService.savedMomentIds) { _, ids in
            guard let momentId = video.moment.id else { return }
            isSaved = ids.contains(momentId)
        }
        .onChange(of: isCurrentVideo) { _, isActive in
            if isActive {
                setupVideo()
                loadVideoData()
                refreshAuthorUsername()
                checkIfSaved()
            } else {
                // Pausar inmediatamente cuando no está activo
                playerManager.pause()
            }
        }
        .onChange(of: video.moment.id) { _, _ in
            isReelCaptionExpanded = false
        }
        .onDisappear {
            // Cleanup inmediato al desaparecer
            playerManager.cleanup()
        }
        .sheet(isPresented: $showComments) {
            ModernCommentsView(moment: video.moment)
                .environmentObject(firestoreService)
                .onDisappear {
                    commentsSheetOriginY = nil
                    loadCommentCount()
                }
                .presentationDetents([.medium, .large], selection: $commentsDetent)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .background {
                    ReelCommentsSheetObserver { originY in
                        commentsSheetOriginY = originY
                    }
                }
        }
    }
    
    private var videoContentMode: ContentMode {
        // Si el video es vertical/cuadrado → llenar pantalla
        // Si es horizontal → mostrar completo
        if video.moment.aspectRatio == "9:16" ||
           video.moment.aspectRatio == "1:1" ||
           video.moment.aspectRatio == "4:5" {
            return .fill  // Videos verticales llenan pantalla
        } else {
            return .fit   // Videos horizontales se muestran completos
        }
    }
    
    // MARK: - Funciones auxiliares
    
    // ✅ NUEVO: Función para verificar historias del usuario (con filtrado de privacidad como en el feed)
    private func checkUserStories() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let otherUserId = video.moment.authorId
        guard !otherUserId.isEmpty else { return }

        StoryRingResolverService.shared.resolve(
            viewerId: currentUserId,
            authorId: otherUserId,
            privacyService: privacyService,
            db: firestoreService.db
        ) { snapshot in
            self.hasStory = snapshot.hasStory
            self.hasUnseenStory = snapshot.hasUnseenStory
            self.storyCount = snapshot.storyCount
            self.storyViewedStatus = snapshot.storyViewedStatus
            self.storyAudiences = snapshot.storyAudiences
        }
    }

    private func refreshAuthorUsername() {
        let authorId = video.moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authorId.isEmpty else {
            liveAuthorUsername = ""
            return
        }

        UserCacheService.shared.refreshUser(userId: authorId) { user in
            let fetchedUsername = user?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard self.video.moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines) == authorId else { return }
                self.liveAuthorUsername = fetchedUsername
            }
        }
    }
    
    private func deleteMoment() {
        guard let momentId = video.moment.id else { return }
        
        // Cerrar context menu
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
            showContextMenu = false
        }
        
        // Eliminar de Firestore (igual que en FeedView)
        firestoreService.deleteMoment(
            userId: video.moment.authorId,
            momentId: momentId
        ) { error in
            DispatchQueue.main.async {
                if error != nil {
                    // Aquí podrías mostrar un alert de error
                } else {
                    // ✅ SwiftData: Eliminar del caché local
                    LocalPersistenceService.shared.deleteMoment(momentId: momentId)
                    // Cerrar el reels viewer
                    onClose()
                }
            }
        }
    }
    
    private func handleDoubleTap() {
        let haptic = UIImpactFeedbackGenerator(style: .heavy)
        haptic.impactOccurred()
        
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.delight) {
            isDoubleTapAnimating = true
        }
        
        // ✅ ACTIVAR REACCIÓN "FEEL" DIRECTAMENTE CON DOBLE TAP
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = video.moment.id else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                isDoubleTapAnimating = false
            }
            return
        }
        
        // Agregar reacción "feel" directamente
        firestoreService.addReaction(
            to: momentId,
            reaction: ReactionType.feel.rawValue,
            userId: currentUserId,
            authorId: video.moment.authorId
        ) { error in
            if error != nil {
            } else {
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isDoubleTapAnimating = false
        }
    }
    
    // Sin controles visuales - comportamiento optimizado
    
    // Funciones auxiliares para formateo
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    private func formatTimeAgo(_ date: Date) -> String {
        MomentsFormat.relativeTime(from: date)
    }
    
    // ... (resto de funciones existentes)
    private func setupVideo() {
        playerManager.setupPlayer(
            with: video,
            startAtSeconds: startAtSeconds,
            consumerId: handoffConsumerId
        )
    }
    
    private func loadVideoData() {
        loadCommentCount()
    }
    
    private func loadCommentCount() {
        guard let momentId = video.moment.id else { return }
        
        firestoreService.db.collection("users").document(video.moment.authorId)
            .collection("moments").document(momentId)
            .collection("comments")
            .getDocuments { snapshot, error in
                if error == nil {
                    DispatchQueue.main.async {
                        self.commentCount = snapshot?.documents.count ?? 0
                    }
                }
            }
    }

    private func checkIfSaved() {
        guard let userId = Auth.auth().currentUser?.uid,
              let momentId = video.moment.id else { return }

        if firestoreService.hasLoadedSavedMoments(for: userId) {
            isSaved = firestoreService.savedMomentIds.contains(momentId)
            return
        }

        firestoreService.checkIfSaved(userId: userId, momentId: momentId) { result in
            if case .success(let saved) = result {
                DispatchQueue.main.async {
                    self.isSaved = saved
                }
            }
        }
    }

    private func toggleSave() {
        guard let userId = Auth.auth().currentUser?.uid,
              let momentId = video.moment.id else { return }

        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
            isSaved.toggle()
        }

        firestoreService.toggleSaveMoment(userId: userId, momentId: momentId) { error in
            if error != nil {
                DispatchQueue.main.async {
                    MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                        self.isSaved.toggle()
                    }
                }
            }
        }
    }
    
    // ✅ INSTANT PLAYBACK: Lógica de preloading inteligente
    private func preloadNextVideos() {
        // Encontrar el index actual (esto es un poco hacky porque ReelsViewer controla el index, 
        // pero ReelVideoView no lo conoce directamente. 
        // Sin embargo, podemos inferirlo o simplemente precargar los videos "alrededor" de este si tuviéramos acceso a la lista.
        // DADO QUE ReelVideoView solo conoce "un" video, esta lógica debería estar en ReelsViewer (el padre).
        // Moveré esta lógica arriba, pero aquí podemos al menos asegurar que ESTE video esté listo.
        // VideoPreloader.shared.preload(urls: [video.videoUrl]) 
        // (Esto ya se hace al init el player, así que aquí es redundante)
    }
}

// Enhanced Reaction Button
struct EnhancedReelReactionButton: View {
    let moment: Moment
    @Binding var currentReaction: ReactionType?
    @Binding var hasReacted: Bool
    @Binding var reactionCount: Int
    
    @State private var showReactionPicker = false
    @State private var pulseAnimation = false
    @EnvironmentObject private var firestoreService: FirestoreService
    
    var body: some View {
        VStack(spacing: 8) {
            Button(action: {
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                
                if hasReacted {
                    removeReaction()
                } else {
                    MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                        showReactionPicker = true
                    }
                }
            }) {
                ZStack {
                    // Background with glassmorphism effect
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(
                                    hasReacted
                                    ? (currentReaction?.color.opacity(0.6) ?? Color.red.opacity(0.6))
                                    : Color.white.opacity(0.2),
                                    lineWidth: hasReacted ? 2 : 1
                                )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    // Pulse effect when reacted
                    if hasReacted && pulseAnimation {
                        Circle()
                            .stroke(currentReaction?.color ?? .red, lineWidth: 2)
                            .frame(width: 56, height: 56)
                            .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                            .opacity(pulseAnimation ? 0 : 1)
                            .animation(.easeOut(duration: 0.6), value: pulseAnimation)
                    }
                    
                    // Heart icon with better styling
                    Image(systemName: hasReacted ? (currentReaction?.filledIcon ?? "heart.fill") : "heart")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(hasReacted ? (currentReaction?.color ?? .red) : .white)
                        .scaleEffect(hasReacted ? 1.2 : 1.0)
                        .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: hasReacted), value: hasReacted)
                }
            }
            
            // Count with better styling
            if reactionCount > 0 {
                Text(MomentsFormat.count(reactionCount, style: .socialMetric))
                    .font(.system(size: legacyPoppinsSize(12), weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .opacity(0.8)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            }
            
            // Reaction picker with better animations
            if showReactionPicker {
                VStack(spacing: 12) {
                    ForEach(ReactionType.allCases.prefix(3), id: \.self) { reaction in
                        Button(action: {
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                            
                            addReaction(reaction)
                            showReactionPicker = false
                        }) {
                            Image(systemName: reaction.filledIcon)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(reaction.color)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.9)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(reaction.color.opacity(0.6), lineWidth: 1.5)
                                )
                                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
                        }
                        .scaleEffect(0.9)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(ReactionType.allCases.firstIndex(of: reaction) ?? 0) * 0.1), value: showReactionPicker)
                    }
                }
                .padding(.vertical, 12)
                .transition(MotionPolicy.Transition.enterPop)
            }
        }
        .onChange(of: hasReacted) { _, reacted in
            if reacted {
                pulseAnimation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pulseAnimation = false
                }
            }
        }
    }
    
    private func addReaction(_ reactionType: ReactionType) {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
            hasReacted = true
            currentReaction = reactionType
            reactionCount += 1
        }
        
        firestoreService.addReaction(
            to: momentId,
            reaction: reactionType.rawValue,
            userId: currentUserId,
            authorId: moment.authorId
        ) { error in
            if error != nil {
                DispatchQueue.main.async {
                    withAnimation {
                        self.hasReacted = false
                        self.currentReaction = nil
                        self.reactionCount -= 1
                    }
                }
            }
        }
    }
    
    private func removeReaction() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id,
              let reactionType = currentReaction else { return }
        
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
            hasReacted = false
            currentReaction = nil
            reactionCount -= 1
        }
        
        firestoreService.removeReaction(
            from: momentId,
            reaction: reactionType.rawValue,
            userId: currentUserId,
            authorId: moment.authorId
        ) { error in
            if error != nil {
                DispatchQueue.main.async {
                    withAnimation {
                        self.hasReacted = true
                        self.currentReaction = reactionType
                        self.reactionCount += 1
                    }
                }
            }
        }
    }
}

// Enhanced Action Button
struct EnhancedReelActionButton: View {
    let icon: String
    let count: Int?
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 6) {
            Button(action: {
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    isPressed = true
                }
                
                action()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isPressed = false
                    }
                }
            }) {
                ZStack {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .momentsChromeGlass(in: Circle(), interactive: true, style: .native)
                        .scaleEffect(isPressed ? 0.95 : 1.0)
                    
                    // Icon with better styling
                    if let customIcon = AttachmentIcon(rawValue: icon) {
                        AttachmentIconView(icon: customIcon, preset: .reelsSidebar, tintColor: isActive ? activeColor : .white)
                            .scaleEffect(isActive ? 1.05 : 0.92)
                            .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: isActive), value: isActive)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isActive ? activeColor : .white)
                            .scaleEffect(isActive ? 1.05 : 1.0)
                            .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: isActive), value: isActive)
                    }

                    if isActive {
                        Circle()
                            .stroke(activeColor.opacity(0.55), lineWidth: 1.5)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            
            // Count badge
            if let count = count, count > 0 {
                Text(MomentsFormat.count(count, style: .socialMetric))
                    .font(.system(size: legacyPoppinsSize(12), weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .opacity(0.8)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            }
        }
    }
}

// Enhanced Video Player Manager con seek optimizado
class ReelVideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var isMuted = true
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var isBuffering = false
    @Published var isLoaded = false
    
    private var timeObserver: Any?
    private var loopObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var playerItem: AVPlayerItem?
    private var isSeeking = false
    private var lastSeekTime: Date = Date()
    private var pendingStartAtSeconds: Double?
    private var adaptiveController: VideoAdaptiveTierController?
    private var stalledObserver: NSObjectProtocol?
    private var consumerId: String?
    private var leaseGeneration: UInt64 = 0
    
    func setupPlayer(with video: VideoMoment, startAtSeconds: Double = 0, consumerId handoffConsumerId: String? = nil) {
        let moment = video.moment
        let newConsumerId: String
        if let handoffConsumerId, !handoffConsumerId.isEmpty {
            newConsumerId = handoffConsumerId
        } else {
            newConsumerId = GlobalVideoManager.profileVideoConsumerId(for: moment)
        }

        if let previousId = consumerId, previousId != newConsumerId {
            let preserve = GlobalVideoManager.shared.shouldPreserveSharedPlayer(consumerId: previousId)
            cleanup(releaseFromPool: !preserve)
        } else if consumerId != nil {
            teardownObserversOnly()
        }

        consumerId = newConsumerId
        leaseGeneration = VideoLayerLease.shared.generation
        pendingStartAtSeconds = startAtSeconds > 0 ? startAtSeconds : nil

        let mediaItem = moment.primaryVisibleMediaItem
        let source = moment.videoPlaybackSource()
        let playbackURL = source?.playbackURL ?? video.playbackURL
        guard let url = playbackURL else { return }

        if let mediaItem, mediaItem.type == .video {
            adaptiveController = VideoAdaptiveTierController(
                mediaItem: mediaItem,
                moment: moment,
                initialTier: source?.tier
            )
        } else {
            adaptiveController = nil
        }

        SharedVideoPlayerPool.shared.setEvictionHandler(for: newConsumerId) { [weak self] in
            DispatchQueue.main.async { self?.handlePoolEviction() }
        }

        let pooledPlayer = SharedVideoPlayerPool.shared.player(for: newConsumerId)
        let reuseExistingItem = pooledPlayer.currentItem != nil && pooledPlayer.currentItem?.status != .failed

        if reuseExistingItem, let existingItem = pooledPlayer.currentItem {
            playerItem = existingItem
            player = pooledPlayer
            isLoaded = existingItem.status == .readyToPlay
            pooledPlayer.automaticallyWaitsToMinimizeStalling = false
            pooledPlayer.allowsExternalPlayback = false
            applySessionMuteState()
            configureAudioSession()
            observePlayerItem()
            setupLooping()
            observePlayback()
            if isLoaded {
                applyPendingStartAndPlayIfNeeded()
            }
            return
        }

        if let preparedItem = ReelPrebufferService.shared.takePreparedItem(for: url.absoluteString) {
            playerItem = preparedItem
        } else {
            playerItem = VideoPreloader.shared.getPlayerItem(for: url.absoluteString)
        }
        let tier = adaptiveController?.currentTier ?? VideoPlaybackSelector.shared.recommendedTier()
        if let playerItem {
            VideoPlaybackSelector.shared.configure(playerItem: playerItem, tier: tier)
        }

        // Nunca asociar un item que ya esté en otro player (crash AVFoundation).
        if pooledPlayer.currentItem === playerItem {
            // Ya montado en este player (p.ej. re-setup).
        } else {
            pooledPlayer.replaceCurrentItem(with: playerItem)
        }
        pooledPlayer.automaticallyWaitsToMinimizeStalling = false
        pooledPlayer.allowsExternalPlayback = false
        player = pooledPlayer
        isLoaded = playerItem?.status == .readyToPlay
        applySessionMuteState()
        configureAudioSession()
        observePlayerItem()
        setupLooping()
        observePlayback()
    }

    private func handlePoolEviction() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
            self.stalledObserver = nil
        }
        cancellables.removeAll()
        adaptiveController = nil
        player = nil
        playerItem = nil
        consumerId = nil
        isPlaying = false
        isLoaded = false
        isBuffering = false
        progress = 0
        duration = 0
    }

    private func teardownObserversOnly() {
        let preserve = consumerId.map {
            GlobalVideoManager.shared.shouldPreserveSharedPlayer(consumerId: $0)
        } ?? false
        if !preserve {
            player?.pause()
            isPlaying = false
        }

        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        cancellables.removeAll()
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
            self.stalledObserver = nil
        }
        adaptiveController = nil
        progress = 0
        duration = 0
        isBuffering = false
        isLoaded = false
        isSeeking = false
        pendingStartAtSeconds = nil
    }
    
    // MARK: - Seek optimizado
    func updateProgress(to newProgress: Double) {
        self.progress = newProgress
    }
    
    func seekToProgress(_ targetProgress: Double, precise: Bool = false) {
        guard let player = player, duration > 0 else { return }
        
        let targetTime = targetProgress * duration
        let cmTime = CMTime(seconds: targetTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        
        if precise {
            // Seek preciso al soltar
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
                if completed {
                    self?.isSeeking = false
                }
            }
        } else {
            // Seek ultra-rápido y suave a keyframe durante el arrastre
            player.seek(to: cmTime, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
        }
        
        isSeeking = true
    }
    
    private func configureAudioSession() {
        Task {
            await MomentsAudioSession.activate(
                category: .playback,
                mode: .moviePlayback,
                options: [.mixWithOthers, .allowBluetoothHFP]
            )
        }
    }
    
    private func observePlayerItem() {
        guard let playerItem = playerItem else { return }
        
        // Observar estado de carga
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    self?.isLoaded = true
                    self?.isBuffering = false
                    self?.applyPendingStartAndPlayIfNeeded()
                case .failed:
                    self?.isBuffering = false
                case .unknown:
                    self?.isBuffering = true
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Observar buffering
        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEmpty in
                if isEmpty && self?.isPlaying == true && self?.isSeeking == false {
                    self?.isBuffering = true
                    self?.recoverFromPlaybackStall()
                }
            }
            .store(in: &cancellables)
        
        playerItem.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] likelyToKeepUp in
                if likelyToKeepUp {
                    self?.isBuffering = false
                    self?.adaptiveController?.notePlaybackHealthy()
                }
            }
            .store(in: &cancellables)

        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
        }
        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.recoverFromPlaybackStall()
        }
    }

    private func recoverFromPlaybackStall() {
        guard let player else { return }
        VideoPlaybackRecovery.recoverFromStall(
            player: player,
            isPlaying: isPlaying,
            adaptive: adaptiveController,
            onTierDowngrade: { [weak self] in
                self?.isLoaded = false
                self?.isBuffering = true
            }
        ) { [weak self] newItem in
            guard let self else { return }
            self.playerItem = newItem
            self.cancellables.removeAll()
            self.observePlayerItem()
            self.setupLooping()
        }
    }
    
    private func setupLooping() {
        guard let playerItem = playerItem else { return }

        // Remover un observer previo para evitar acumularlos en cada setup (fuga + loops duplicados).
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { completed in
                guard completed, let self, self.isCurrentLeaseGeneration() else { return }
                self.pendingStartAtSeconds = nil
                self.player?.play()
            }
        }
    }

    private func applyPendingStartAndPlayIfNeeded() {
        guard isCurrentLeaseGeneration() else { return }
        guard let player else {
            play()
            return
        }

        guard let startAt = pendingStartAtSeconds else {
            play()
            return
        }

        let boundedStart = max(0, startAt)
        pendingStartAtSeconds = nil
        let current = CMTimeGetSeconds(player.currentTime())
        if current.isFinite, abs(current - boundedStart) < 0.35 {
            play()
            return
        }
        let target = CMTime(seconds: boundedStart, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let generation = leaseGeneration
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self, self.leaseGeneration == generation, self.isCurrentLeaseGeneration() else { return }
            self.play()
        }
    }

    private func isCurrentLeaseGeneration() -> Bool {
        leaseGeneration == VideoLayerLease.shared.generation
    }
    
    func togglePlayback() {
        guard let player = player, isLoaded else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
    
    func play() {
        guard isCurrentLeaseGeneration() else { return }
        guard let player = player, isLoaded else { return }
        player.currentItem?.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        player.play()
        isPlaying = true
    }
    
    func pause() {
        guard let player = player else { return }
        player.pause()
        player.currentItem?.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        isPlaying = false
    }

    func toggleMute() {
        guard let player = player else { return }

        let volume = AVAudioSession.sharedInstance().outputVolume
        if isMuted && volume == 0.0 {
            return
        }

        let wasMuted = isMuted
        isMuted.toggle()
        player.isMuted = isMuted

        if wasMuted && !isMuted {
            GlobalVideoManager.shared.enableSoundForSession()
        } else if !wasMuted && isMuted {
            GlobalVideoManager.shared.disableSoundForSession()
        }
    }

    private func applySessionMuteState() {
        isMuted = !GlobalVideoManager.shared.userHasEnabledSoundInSession
        player?.isMuted = isMuted
    }
    
    private func observePlayback() {
        guard let player = player else { return }
        
        // Observer menos frecuente para mejor performance durante seeks
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self,
                  let currentItem = player.currentItem,
                  !self.isSeeking else { return } // No actualizar durante seeks
            
            let duration = currentItem.duration
            if CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration) {
                let durationSeconds = CMTimeGetSeconds(duration)
                let currentSeconds = CMTimeGetSeconds(time)
                
                if !durationSeconds.isNaN && !currentSeconds.isNaN && durationSeconds > 0 {
                    self.duration = durationSeconds
                    self.progress = currentSeconds / durationSeconds
                }
            }
        }
    }
    
    func cleanup(releaseFromPool: Bool = true) {
        let shouldPreserve = consumerId.map {
            GlobalVideoManager.shared.shouldPreserveSharedPlayer(consumerId: $0)
        } ?? false

        // Mismo AVPlayer que el feed: no pausar ni soltar el slot. El feed re-enlaza el layer.
        teardownObserversOnly()

        let actuallyRelease = releaseFromPool && !shouldPreserve
        if let consumerId, actuallyRelease {
            SharedVideoPlayerPool.shared.release(consumerId: consumerId)
        }

        player = nil
        playerItem = nil
        self.consumerId = nil
        isMuted = !GlobalVideoManager.shared.userHasEnabledSoundInSession
    }

    deinit {
        cleanup(releaseFromPool: false)
    }
}

// MARK: - Additional Enhancements

// Custom transition for smooth reel changes
struct ReelTransition: ViewModifier {
    let isVisible: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.95)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
    }
}

extension View {
    func reelTransition(isVisible: Bool) -> some View {
        modifier(ReelTransition(isVisible: isVisible))
    }
}

// Elegant loading shimmer effect
struct ShimmerEffect: View {
    @State private var shimmerOffset: CGFloat = -200
    
    var body: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.3),
                Color.white.opacity(0.1),
                Color.white.opacity(0.3)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: shimmerOffset)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 200
            }
        }
    }
}

// Data models and extensions (existing ones enhanced)
struct VideoMoment: Identifiable {
    /// Estable (≡ Android): no usar UUID — regenerar la cola no debe romper el ForEach del pager.
    let id: String
    let moment: Moment
    let videoUrl: String

    var playbackURL: URL? {
        moment.videoPlaybackSource()?.playbackURL ?? URL(string: videoUrl)
    }

    var preloadURLStrings: [String] {
        if let strings = moment.videoPlaybackSource()?.preheatURLStrings, !strings.isEmpty {
            return strings
        }
        return videoUrl.isEmpty ? [] : [videoUrl]
    }

    /// Poster para placeholders del pager / carga (thumbnail → imagePath).
    var posterURLString: String? {
        if let thumb = moment.thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !thumb.isEmpty {
            return thumb
        }
        if let imagePath = moment.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !imagePath.isEmpty {
            return imagePath
        }
        return nil
    }

    init(moment: Moment) {
        self.moment = moment
        let resolved = moment.previewVideoURLString ?? moment.videoUrl ?? ""
        self.videoUrl = resolved
        if let momentId = moment.id, !momentId.isEmpty {
            self.id = momentId
        } else {
            self.id = "url:\(resolved)"
        }
    }
}

extension Array where Element == Moment {
    var videoMoments: [VideoMoment] {
        return self.compactMap { moment in
            guard let videoUrl = moment.previewVideoURLString ?? moment.videoUrl,
                  !videoUrl.isEmpty else { return nil }
            return VideoMoment(moment: moment)
        }
    }
}
