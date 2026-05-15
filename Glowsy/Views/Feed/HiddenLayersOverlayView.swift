import SwiftUI
import Kingfisher
import AVFoundation
import FirebaseAuth

struct HiddenLayersOverlayView: View {
    let moment: Moment
    let isImmersive: Bool

    @State private var layers: [MomentHiddenLayer] = []
    @State private var isLoading = false
    @State private var showIntroShimmer = false
    @State private var revealedLayerIds: Set<String> = []
    @State private var autoplayLayerIds: Set<String> = []
    @State private var revealBurstLayerIds: Set<String> = []

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if !layers.isEmpty && !isImmersive {
                    ForEach(Array(layers.enumerated()), id: \.element.id) { offset, layer in
                        hotspot(for: layer, index: offset, in: proxy.size)
                    }

                    if showIntroShimmer {
                        VStack {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text(NSLocalizedString("hiddenLayers.viewer.hint", value: "Toca los destellos", comment: "Hidden layers viewer hint"))
                            }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .liquidGlass(in: Capsule())
                            .padding(.top, 14)

                            Spacer()
                        }
                        .transition(.opacity)
                    }
                } else if isLoading && !isImmersive {
                    ProgressView()
                        .tint(.white.opacity(0.8))
                        .scaleEffect(0.9)
                }
            }
            .task(id: moment.id ?? "") {
                await loadLayersIfNeeded()
            }
        }
        .allowsHitTesting(!layers.isEmpty && !isImmersive)
    }

    private func hotspot(for layer: MomentHiddenLayer, index: Int, in size: CGSize) -> some View {
        let isRevealed = revealedLayerIds.contains(layer.id)
        let frame = layerFrame(layer, in: size)

        return ZStack {
            if isRevealed {
                revealedContent(for: layer, frameSize: frame.size)
                    .frame(width: frame.width, height: frame.height)
                    .transition(revealTransition(for: layer.type))
            } else {
                Color.clear
                    .overlay {
                        if showIntroShimmer || !seen(layer) {
                            HiddenLayerPresenceHint(
                                type: layer.type,
                                shape: layer.shape,
                                isSeen: seen(layer),
                                delay: Double(index) * 0.12,
                                isIntro: showIntroShimmer
                            )
                        }
                    }
            }

            if revealBurstLayerIds.contains(layer.id) {
                HiddenLayerRevealBurst(type: layer.type, shape: layer.shape)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRevealed {
                reveal(layer)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: revealedLayerIds)
        .animation(.easeInOut(duration: 0.35), value: showIntroShimmer)
        .position(x: frame.midX, y: frame.midY)
    }

    @ViewBuilder
    private func revealedContent(for layer: MomentHiddenLayer, frameSize: CGSize) -> some View {
        switch layer.type {
        case .text:
            HiddenLayerTextReveal(layer: layer, frameSize: frameSize)
        case .image:
            if let mediaURL = layer.mediaURL, let url = URL(string: mediaURL) {
                HiddenLayerImageReveal(
                    url: url,
                    caption: layer.caption,
                    captionStyle: layer.textStyle,
                    frameStyle: layer.imageFrameStyle,
                    imageOffset: CGSize(width: layer.imageOffsetX ?? 0, height: layer.imageOffsetY ?? 0),
                    imageScale: layer.imageScale ?? 1,
                    canvasSize: frameSize
                )
            }
        case .audio:
            if let mediaURL = layer.mediaURL {
                HiddenLayerAudioReveal(
                    audioURL: mediaURL,
                    duration: layer.duration ?? 15.0,
                    frameSize: frameSize,
                    shouldAutoplay: autoplayLayerIds.contains(layer.id)
                )
            }
        }
    }

    private func reveal(_ layer: MomentHiddenLayer) {
        HapticManager.shared.lightImpact()
        revealBurstLayerIds.insert(layer.id)
        revealedLayerIds.insert(layer.id)
        if layer.type == .audio {
            autoplayLayerIds.insert(layer.id)
        }
        markSeen(layer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            revealBurstLayerIds.remove(layer.id)
        }
    }

    private func layerFrame(_ layer: MomentHiddenLayer, in size: CGSize) -> CGRect {
        HiddenLayerLayout.frame(for: layer, in: CGRect(origin: .zero, size: size))
    }

    private func revealTransition(for type: MomentHiddenLayer.LayerType) -> AnyTransition {
        switch type {
        case .text:
            return .modifier(
                active: HiddenLayerRevealModifier(scale: 0.92, opacity: 0, blur: 16, offsetY: 10, rotation: -1.2),
                identity: HiddenLayerRevealModifier(scale: 1, opacity: 1, blur: 0, offsetY: 0, rotation: 0)
            )
        case .audio:
            return .modifier(
                active: HiddenLayerRevealModifier(scale: 0.84, opacity: 0, blur: 10, offsetY: 12, rotation: 0),
                identity: HiddenLayerRevealModifier(scale: 1, opacity: 1, blur: 0, offsetY: 0, rotation: 0)
            )
        case .image:
            return .modifier(
                active: HiddenLayerRevealModifier(scale: 0.86, opacity: 0, blur: 10, offsetY: 8, rotation: -4),
                identity: HiddenLayerRevealModifier(scale: 1, opacity: 1, blur: 0, offsetY: 0, rotation: 0)
            )
        }
    }

    private func loadLayersIfNeeded() async {
        guard layers.isEmpty, !isLoading, moment.hasHiddenLayers, let momentId = moment.id else { return }
        isLoading = true

        await withCheckedContinuation { continuation in
            FirestoreService.shared.fetchHiddenLayers(userId: moment.authorId, momentId: momentId) { result in
                let fetched = (try? result.get()) ?? []
                let visible = fetched
                    .filter(\.isVisibleInViewer)
                    .sorted { $0.zIndex < $1.zIndex }

                Task { @MainActor in
                    layers = visible
                    revealedLayerIds = Set(visible.filter(seen).map(\.id))
                    autoplayLayerIds.removeAll()
                    isLoading = false
                    if visible.contains(where: { !seen($0) }) {
                        showIntroShimmer = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            showIntroShimmer = false
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func seenKey(_ layer: MomentHiddenLayer) -> String {
        let viewerId = Auth.auth().currentUser?.uid ?? "anonymous"
        return "hiddenLayerSeen:\(viewerId):\(moment.id ?? "unknown"):\(layer.id)"
    }

    private func seen(_ layer: MomentHiddenLayer) -> Bool {
        UserDefaults.standard.bool(forKey: seenKey(layer))
    }

    private func markSeen(_ layer: MomentHiddenLayer) {
        UserDefaults.standard.set(true, forKey: seenKey(layer))
    }
}

private struct HiddenLayerPresenceHint: View {
    let type: MomentHiddenLayer.LayerType
    let shape: MomentHiddenLayer.LayerShape
    let isSeen: Bool
    let delay: Double
    let isIntro: Bool

    @State private var pulse = false
    @State private var haloOpacity: Double = 0.18
    @State private var coreOpacity: Double = 0.34
    @State private var orbitPhase: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: shape == .circle ? 999 : 14, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(coreOpacity),
                            .white.opacity(haloOpacity),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: type == .audio ? 26 : 42
                    )
                )
                .scaleEffect(pulse ? 1.08 : 0.92)
                .blur(radius: isIntro ? 0.4 : 0.8)

            if isIntro {
                HiddenLayerHintOrbit(type: type, progress: orbitPhase)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
        .onAppear {
            if isIntro {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(delay)) {
                    pulse = true
                    haloOpacity = isSeen ? 0.18 : 0.28
                    coreOpacity = isSeen ? 0.4 : 0.58
                }
                withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false).delay(delay)) {
                    orbitPhase = 1
                }
            } else {
                haloOpacity = isSeen ? 0.10 : 0.14
                coreOpacity = isSeen ? 0.22 : 0.28
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(delay)) {
                    pulse = true
                    haloOpacity = isSeen ? 0.15 : 0.2
                    coreOpacity = isSeen ? 0.3 : 0.38
                }
            }
        }
        .onDisappear {
            pulse = false
            orbitPhase = 0
        }
    }

}

private struct HiddenLayerHintOrbit: View {
    let type: MomentHiddenLayer.LayerType
    let progress: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index == 1 ? 0.34 : 0.18))
                    .frame(width: dotSize(for: index), height: dotSize(for: index))
                    .offset(orbitOffset(for: index))
                    .blur(radius: index == 1 ? 0 : 0.3)
            }
        }
    }

    private func orbitOffset(for index: Int) -> CGSize {
        let radius: CGFloat
        switch type {
        case .text: radius = 18
        case .audio: radius = 15
        case .image: radius = 16
        }
        let angle = (progress * CGFloat.pi * 2) + (CGFloat.pi * 2 / 3 * CGFloat(index))
        return CGSize(
            width: CGFloat(cos(Double(angle))) * radius,
            height: CGFloat(sin(Double(angle))) * radius
        )
    }

    private func dotSize(for index: Int) -> CGFloat {
        switch index {
        case 0: return 3.5
        case 1: return 5
        default: return 2.8
        }
    }
}

private struct HiddenLayerRevealBurst: View {
    let type: MomentHiddenLayer.LayerType
    let shape: MomentHiddenLayer.LayerShape

    @State private var animate = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: shape == .circle ? 999 : 18, style: .continuous)
                .stroke(.white.opacity(0.34), lineWidth: 1.2)
                .scaleEffect(animate ? 1.22 : 0.86)
                .opacity(animate ? 0 : 1)
                .blur(radius: 0.4)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.18), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: radialSize
                    )
                )
                .scaleEffect(animate ? 1.3 : 0.6)
                .opacity(animate ? 0 : 0.9)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.52)) {
                animate = true
            }
        }
    }

    private var radialSize: CGFloat {
        switch type {
        case .text: return 32
        case .audio: return 26
        case .image: return 28
        }
    }
}

private struct HiddenLayerRevealModifier: ViewModifier {
    let scale: CGFloat
    let opacity: Double
    let blur: CGFloat
    let offsetY: CGFloat
    let rotation: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .blur(radius: blur)
            .offset(y: offsetY)
            .rotationEffect(.degrees(rotation))
    }
}

private struct HiddenLayerTextReveal: View {
    let layer: MomentHiddenLayer
    let frameSize: CGSize

    var body: some View {
        textRevealContent
            .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
    }

    private var font: Font {
        switch layer.textStyle ?? .clean {
        case .clean: return .system(size: 15, weight: .semibold, design: .rounded)
        case .serif: return .system(size: 16, weight: .semibold, design: .serif)
        case .handwritten: return .custom("Marker Felt", size: 17)
        case .mono: return .system(size: 14, weight: .semibold, design: .monospaced)
        case .bubble: return .system(size: 16, weight: .black, design: .rounded)
        case .editorial: return .system(size: 18, weight: .bold, design: .serif)
        }
    }

    private var foreground: Color {
        switch layer.presentationStyle {
        case .paperNote: return .black.opacity(0.82)
        case .markerLabel: return .black
        default: return .white
        }
    }

    private var cornerRadius: CGFloat {
        switch layer.presentationStyle {
        case .captionPill: return 999
        case .markerLabel: return 10
        default: return 18
        }
    }

    @ViewBuilder
    private var textRevealContent: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if layer.presentationStyle == .glassCard {
            Text(layer.text ?? "")
                .font(font)
                .foregroundColor(foreground)
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(width: frameSize.width, height: frameSize.height)
                .background(Color.clear)
                .liquidGlass(in: shape)
        } else {
            Text(layer.text ?? "")
                .font(font)
                .foregroundColor(foreground)
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(width: frameSize.width, height: frameSize.height)
                .background(background)
                .clipShape(shape)
        }
    }

    private var background: some ShapeStyle {
        switch layer.presentationStyle {
        case .glassCard:
            return AnyShapeStyle(Color.clear)
        case .captionPill:
            return AnyShapeStyle(Color.black.opacity(0.58))
        case .paperNote:
            return AnyShapeStyle(Color(red: 1.0, green: 0.94, blue: 0.76))
        case .markerLabel:
            return AnyShapeStyle(Color.yellow.opacity(0.9))
        case .floatingQuote:
            return AnyShapeStyle(LinearGradient(colors: [.black.opacity(0.72), .black.opacity(0.34)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .minimalText:
            return AnyShapeStyle(Color.clear)
        }
    }
}

private struct HiddenLayerAudioReveal: View {
    let audioURL: String
    let duration: Double
    let frameSize: CGSize
    let shouldAutoplay: Bool

    var body: some View {
        HiddenLayerAudioTagView(audioURL: audioURL, duration: duration, shouldAutoplay: shouldAutoplay)
            .frame(width: frameSize.width, height: frameSize.height)
            .scaleEffect(scale)
    }

    private var scale: CGFloat {
        max(0.7, min(2.4, frameSize.width / 88))
    }
}

private struct HiddenLayerAudioTagView: View {
    let audioURL: String
    let duration: Double
    let shouldAutoplay: Bool

    @State private var isPlaying = false
    @State private var isPreparing = false
    @State private var progress: Double = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var timer: Timer?
    @State private var animatedHeights: [CGFloat] = [10, 14, 10]
    @State private var previousAudioCategory: AVAudioSession.Category?
    @State private var previousAudioMode: AVAudioSession.Mode?
    @State private var previousAudioOptions: AVAudioSession.CategoryOptions = []
    @State private var didConfigureAudioSession = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .liquidGlass(in: Circle())

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [.white, .white.opacity(0.8)], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 6) {
                Image(systemName: isPreparing ? "arrow.down.circle" : (isPlaying ? "pause.fill" : "play.fill"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .contentTransition(.symbolEffect(.replace))

                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(.white)
                            .frame(width: 3, height: isPlaying ? animatedHeights[i] : 10)
                    }
                }
            }
        }
        .frame(width: 72, height: 72)
        .contentShape(Circle())
        .highPriorityGesture(
            TapGesture()
                .onEnded {
                    togglePlayback()
                }
        )
        .onAppear {
            if shouldAutoplay {
                startPlayback()
            }
        }
        .onDisappear {
            stopPlayback()
        }
        .onChange(of: isPlaying) { _, newValue in
            if newValue {
                startWaveAnimation()
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            resumePlayback(promoteToPlayback: true)
        }
    }

    private func startPlayback(userInitiated: Bool = false) {
        guard let url = URL(string: audioURL) else { return }
        isPreparing = true

        let session = AVAudioSession.sharedInstance()

        if !didConfigureAudioSession {
            previousAudioCategory = session.category
            previousAudioMode = session.mode
            previousAudioOptions = session.categoryOptions
            didConfigureAudioSession = true
        }

        configureAudioSession(forUserInitiatedPlayback: userInitiated)
        try? session.setActive(true)

        Task {
            do {
                let player: AVAudioPlayer
                if url.scheme == "file" {
                    player = try AVAudioPlayer(contentsOf: url)
                } else {
                    let cachedURL = try await PersistentAudioCache.shared.localURL(for: url)
                    player = try AVAudioPlayer(contentsOf: cachedURL)
                }

                await MainActor.run {
                    self.audioPlayer = player
                    self.audioPlayer?.play()
                    self.isPlaying = true
                    self.isPreparing = false
                    self.startProgressTimer()
                }
            } catch {
                await MainActor.run {
                    self.isPreparing = false
                }
            }
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        isPreparing = false
        withAnimation {
            progress = 0
        }
        timer?.invalidate()
        timer = nil
        restoreAudioSessionIfNeeded()
    }

    private func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        isPreparing = false
        timer?.invalidate()
        timer = nil
    }

    private func resumePlayback(promoteToPlayback: Bool) {
        if let audioPlayer {
            if promoteToPlayback {
                configureAudioSession(forUserInitiatedPlayback: true)
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            audioPlayer.play()
            isPlaying = true
            startProgressTimer()
        } else {
            startPlayback(userInitiated: promoteToPlayback)
        }
    }

    private func finishPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        isPreparing = false
        withAnimation {
            progress = 0
        }
        timer?.invalidate()
        timer = nil
        restoreAudioSessionIfNeeded()
    }

    private func startProgressTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if let player = self.audioPlayer {
                withAnimation(.linear(duration: 0.05)) {
                    self.progress = player.currentTime / player.duration
                }
                if !player.isPlaying {
                    finishPlayback()
                }
            }
        }
    }

    private func startWaveAnimation() {
        guard isPlaying else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            animatedHeights = [
                CGFloat.random(in: 6...16),
                CGFloat.random(in: 10...20),
                CGFloat.random(in: 6...16)
            ]
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if self.isPlaying {
                self.startWaveAnimation()
            } else {
                withAnimation {
                    self.animatedHeights = [10, 14, 10]
                }
            }
        }
    }

    private func restoreAudioSessionIfNeeded() {
        guard didConfigureAudioSession else { return }
        let session = AVAudioSession.sharedInstance()
        if let previousAudioCategory, let previousAudioMode {
            try? session.setCategory(previousAudioCategory, mode: previousAudioMode, options: previousAudioOptions)
        }
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        didConfigureAudioSession = false
    }

    private func configureAudioSession(forUserInitiatedPlayback: Bool) {
        let session = AVAudioSession.sharedInstance()
        let category: AVAudioSession.Category = forUserInitiatedPlayback ? .playback : .ambient
        let options: AVAudioSession.CategoryOptions = forUserInitiatedPlayback ? [.mixWithOthers] : []
        try? session.setCategory(category, mode: .default, options: options)
    }
}

private struct HiddenLayerImageReveal: View {
    let url: URL
    let caption: String?
    let captionStyle: HiddenLayerTextStyle?
    let frameStyle: HiddenLayerImageFrameStyle?
    let imageOffset: CGSize
    let imageScale: Double
    let canvasSize: CGSize

    var body: some View {
        HiddenLayerRemotePolaroidPreview(
            url: url,
            caption: caption,
            captionStyle: captionStyle,
            frameStyle: frameStyle ?? .classic,
            imageOffset: imageOffset,
            imageScale: imageScale,
            canvasSize: canvasSize
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .rotationEffect(.degrees(-2))
    }
}
