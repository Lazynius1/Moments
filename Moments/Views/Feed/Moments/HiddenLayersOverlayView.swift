import SwiftUI
import Kingfisher
import AVFoundation
import FirebaseAuth

struct HiddenLayersOverlayView: View {
    @Environment(\.momentsViewportSize) private var momentsViewportSize
    @Environment(\.colorScheme) private var colorScheme

    let moment: Moment
    let isImmersive: Bool
    var requiresFocusForIntro: Bool = false

    @State private var layers: [MomentHiddenLayer] = []
    @State private var isLoading = false
    @State private var showIntroShimmer = false
    @State private var revealedLayerIds: Set<String> = []
    @State private var revealBurstLayerIds: Set<String> = []
    @State private var viewerNow = Date()
    @State private var temporaryTopMessage: String?
    @State private var temporaryLockedLayerId: String?
    @State private var temporaryLockedMessageExpiry: Date?
    @State private var temporaryLockedMessageToken = UUID()
    @State private var isFocusQualified = false
    @State private var hasPlayedIntro = false

    var body: some View {
        GeometryReader { proxy in
            let focusQualified = !requiresFocusForIntro || overlayHasFocus(frame: proxy.frame(in: .global))

            ZStack {
                if !layers.isEmpty && !isImmersive {
                    ForEach(Array(layers.enumerated()), id: \.element.id) { offset, layer in
                        hotspot(for: layer, index: offset, in: proxy.size)
                    }

                    if let topHintText {
                        VStack {
                            Text(topHintText)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .momentsChromeGlass(in: Capsule())
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
            .onAppear {
                updateFocusQualification(focusQualified)
            }
            .onChange(of: focusQualified) { _, newValue in
                updateFocusQualification(newValue)
            }
        }
        .allowsHitTesting(!layers.isEmpty && !isImmersive)
    }

    private func hotspot(for layer: MomentHiddenLayer, index: Int, in size: CGSize) -> some View {
        let isRevealed = revealedLayerIds.contains(layer.id)
        let _ = layer.isUnlocked(at: viewerNow)
        let frame = layerFrame(layer, in: size)

        return ZStack {
            if isRevealed {
                revealedContent(for: layer, frameSize: frame.size)
                    .frame(width: frame.width, height: frame.height)
                    .transition(revealTransition(for: layer.type))
            } else {
                Color.clear
                    .overlay {
                        if !seen(layer) {
                            HiddenLayerHintAppearanceView(
                                type: layer.type,
                                shape: layer.shape,
                                style: layer.hintStyle ?? .actual,
                                isSeen: seen(layer),
                                delay: Double(index) * 0.12,
                                isIntro: showIntroShimmer
                            )
                        }
                    }
            }

            if revealBurstLayerIds.contains(layer.id) {
                HiddenLayerRevealBurst(color: burstColor(for: layer), shape: layer.shape)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRevealed {
                let currentTime = Date()
                viewerNow = currentTime

                guard layer.isUnlocked(at: currentTime) else {
                    HapticManager.shared.notification(.warning)
                    showTemporaryLockedMessage(for: layer)
                    return
                }
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
                    shouldAutoplay: false
                )
            }
        }
    }

    private func reveal(_ layer: MomentHiddenLayer) {
        let wasSeen = seen(layer)
        HapticManager.shared.lightImpact()
        revealBurstLayerIds.insert(layer.id)
        revealedLayerIds.insert(layer.id)
        markSeen(layer)
        if !wasSeen {
            recordDiscovery(for: layer)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            revealBurstLayerIds.remove(layer.id)
        }
    }

    private func layerFrame(_ layer: MomentHiddenLayer, in size: CGSize) -> CGRect {
        HiddenLayerLayout.frame(for: layer, in: CGRect(origin: .zero, size: size))
    }

    private func burstColor(for layer: MomentHiddenLayer) -> Color {
        switch layer.type {
        case .text:
            switch layer.presentationStyle {
            case .markerLabel: return .yellow
            case .paperNote: return Color(red: 1.0, green: 0.9, blue: 0.6)
            default: return Color(red: 1.0, green: 0.84, blue: 0.42) // Gold/Glass
            }
        case .image: return .white
        case .audio: return Color(red: 0.4, green: 0.8, blue: 1.0) // Light Blue magic
        }
    }

    private func revealTransition(for type: MomentHiddenLayer.LayerType) -> AnyTransition {
        let spring = MotionPolicy.Spring.header
        
        switch type {
        case .text:
            return .asymmetric(
                insertion: .modifier(
                    active: HiddenLayerRevealModifier(scale: 0.82, opacity: 0, blur: 12, offsetY: 15, rotation: -2),
                    identity: HiddenLayerRevealModifier(scale: 1, opacity: 1, blur: 0, offsetY: 0, rotation: 0)
                ).animation(spring),
                removal: .opacity
            )
        case .audio:
            return .asymmetric(
                insertion: .modifier(
                    active: HiddenLayerRevealModifier(scale: 0.75, opacity: 0, blur: 8, offsetY: 20, rotation: 0),
                    identity: HiddenLayerRevealModifier(scale: 1, opacity: 1, blur: 0, offsetY: 0, rotation: 0)
                ).animation(spring),
                removal: .opacity
            )
        case .image:
            return .asymmetric(
                insertion: .modifier(
                    active: HiddenLayerRevealModifier(scale: 0.88, opacity: 0, blur: 10, offsetY: 12, rotation: -6),
                    identity: HiddenLayerRevealModifier(scale: 1, opacity: 1, blur: 0, offsetY: 0, rotation: 0)
                ).animation(spring),
                removal: .opacity
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
                    viewerNow = Date()
                    revealedLayerIds = Set(
                        visible
                            .filter { seen($0) && $0.isUnlocked(at: viewerNow) }
                            .map(\.id)
                    )
                    hasPlayedIntro = false
                    isLoading = false
                    scheduleIntroIfNeeded()
                    scheduleNextUnlockUpdate()
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

    private var topHintText: String? {
        if let temporaryTopMessage {
            return temporaryTopMessage
        }

        if let temporaryLockedLayer {
            return lockedMessage(for: temporaryLockedLayer)
        }

        if let lockedSummaryText = lockedSummaryText {
            return lockedSummaryText
        }

        guard showIntroShimmer, layers.contains(where: { !seen($0) }) else {
            return nil
        }

        return NSLocalizedString("hiddenLayers.viewer.hint", value: "Toca los destellos", comment: "Hidden layers viewer hint")
    }

    private var lockedSummaryText: String? {
        let lockedLayers = layers.filter { !$0.isUnlocked(at: viewerNow) }
        guard !lockedLayers.isEmpty else { return nil }

        if lockedLayers.count == 1, let nextUnlock = lockedLayers.compactMap(\.unlockAt).min() {
            return String(
                format: NSLocalizedString("hiddenLayers.viewer.locked.single", value: "Un secreto se abre %@", comment: "Hidden layer single locked summary"),
                unlockSummaryString(for: nextUnlock)
            )
        }

        if let nextUnlock = lockedLayers.compactMap(\.unlockAt).min() {
            let availableCount = max(0, layers.count - lockedLayers.count)
            if availableCount == 0 {
                return String(
                    format: NSLocalizedString("hiddenLayers.viewer.locked.all", value: "%1$d secretos se abren %@", comment: "Hidden layers all locked summary"),
                    lockedLayers.count,
                    unlockSummaryString(for: nextUnlock)
                )
            }
            return String(
                format: NSLocalizedString("hiddenLayers.viewer.locked.mixed", value: "%1$d secretos ahora · %2$d más %@", comment: "Hidden layers mixed availability summary"),
                availableCount,
                lockedLayers.count,
                unlockSummaryString(for: nextUnlock)
            )
        }

        return nil
    }

    private func lockedMessage(for layer: MomentHiddenLayer) -> String {
        guard let unlockAt = layer.unlockAt else {
            return NSLocalizedString("hiddenLayers.viewer.locked.generic", value: "Aún no", comment: "Hidden layer generic locked message")
        }
        return String(
            format: NSLocalizedString("hiddenLayers.viewer.locked.until", value: "Se abre %@", comment: "Hidden layer locked until"),
            unlockSummaryString(for: unlockAt)
        )
    }

    private func unlockSummaryString(for date: Date) -> String {
        let seconds = date.timeIntervalSince(viewerNow)
        if seconds > 0, seconds < 24 * 60 * 60 {
            return MomentsFormat.relativeTime(
                from: date,
                style: .conversational(unitsStyle: .short),
                relativeTo: viewerNow
            )
        }

        if Calendar.current.isDateInToday(date) {
            return String(
                format: NSLocalizedString("hiddenLayers.viewer.unlock.today", value: "hoy a las %@", comment: "Hidden layer unlock today"),
                MomentsFormat.smartDate(from: date, context: .timeOnly)
            )
        }

        return MomentsFormat.smartDate(from: date, context: .mediumDateTime)
    }

    private var temporaryLockedLayer: MomentHiddenLayer? {
        guard
            let layerId = temporaryLockedLayerId,
            let expiry = temporaryLockedMessageExpiry,
            expiry > Date(),
            let layer = layers.first(where: { $0.id == layerId }),
            !layer.isUnlocked(at: viewerNow)
        else {
            return nil
        }

        return layer
    }

    private func showTemporaryTopMessage(_ message: String) {
        temporaryTopMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if temporaryTopMessage == message {
                temporaryTopMessage = nil
            }
        }
    }

    private func showTemporaryLockedMessage(for layer: MomentHiddenLayer) {
        temporaryTopMessage = nil
        temporaryLockedLayerId = layer.id
        temporaryLockedMessageExpiry = Date().addingTimeInterval(2.4)
        let token = UUID()
        temporaryLockedMessageToken = token
        scheduleTemporaryLockedMessageRefresh(token: token)
    }

    private func scheduleTemporaryLockedMessageRefresh(token: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard temporaryLockedMessageToken == token else { return }

            viewerNow = Date()

            guard let layer = temporaryLockedLayer else {
                temporaryLockedLayerId = nil
                temporaryLockedMessageExpiry = nil
                return
            }

            if let expiry = temporaryLockedMessageExpiry, expiry > Date(), !layer.isUnlocked(at: viewerNow) {
                scheduleTemporaryLockedMessageRefresh(token: token)
            } else {
                temporaryLockedLayerId = nil
                temporaryLockedMessageExpiry = nil
            }
        }
    }

    private func scheduleNextUnlockUpdate() {
        let nextUnlock = layers
            .filter { !$0.isUnlocked(at: viewerNow) }
            .compactMap(\.unlockAt)
            .min()

        guard let nextUnlock else { return }

        let delay = max(0.2, nextUnlock.timeIntervalSince(Date()))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let previousLockedIds = Set(layers.filter { !$0.isUnlocked(at: viewerNow) }.map(\.id))
            viewerNow = Date()
            let newlyUnlockedIds = previousLockedIds.subtracting(layers.filter { !$0.isUnlocked(at: viewerNow) }.map(\.id))
            if !newlyUnlockedIds.isEmpty {
                if let temporaryLockedLayerId, newlyUnlockedIds.contains(temporaryLockedLayerId) {
                    self.temporaryLockedLayerId = nil
                    temporaryLockedMessageExpiry = nil
                }
                HapticManager.shared.lightImpact()
                showTemporaryTopMessage(NSLocalizedString("hiddenLayers.viewer.unlocked", value: "Ya puedes descubrirlo", comment: "Hidden layer unlocked message"))
            }
            scheduleNextUnlockUpdate()
        }
    }

    private func updateFocusQualification(_ value: Bool) {
        guard isFocusQualified != value else { return }
        isFocusQualified = value
        if value {
            scheduleIntroIfNeeded()
        }
    }

    private func scheduleIntroIfNeeded() {
        guard !hasPlayedIntro else { return }
        guard !layers.isEmpty, !isLoading else { return }
        guard layers.contains(where: { !seen($0) }) else { return }
        guard !isImmersive else { return }
        guard isFocusQualified else { return }

        hasPlayedIntro = true
        showIntroShimmer = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            showIntroShimmer = false
        }
    }

    private func overlayHasFocus(frame: CGRect) -> Bool {
        let screen = CGRect(origin: .zero, size: momentsViewportSize)
        let visibleFrame = frame.intersection(screen)
        guard !visibleFrame.isNull, frame.height > 0 else { return false }

        let visibleRatio = visibleFrame.height / frame.height
        let centerDistance = abs(frame.midY - screen.midY)
        let maxCenterDistance = min(screen.height * 0.18, 150)

        return visibleRatio > 0.72 && centerDistance < maxCenterDistance
    }

    private func recordDiscovery(for layer: MomentHiddenLayer) {
        guard let momentId = moment.id else { return }
        guard let viewerId = Auth.auth().currentUser?.uid, viewerId != moment.authorId else { return }

        FirestoreService.shared.recordHiddenLayerDiscovery(
            ownerUserId: moment.authorId,
            momentId: momentId,
            layerId: layer.id,
            viewerId: viewerId
        ) { _ in }
    }
}

private struct HiddenLayerPresenceHint: View {
    let type: MomentHiddenLayer.LayerType
    let shape: MomentHiddenLayer.LayerShape
    let isSeen: Bool
    let delay: Double
    let isIntro: Bool

    @State private var pulse = false
    @State private var shimmerPhase: CGFloat = 0
    @State private var glintOpacity: Double = 0
    @State private var orbitPhase: CGFloat = 0

    private var baseColor: Color {
        Color(red: 1.0, green: 0.92, blue: 0.62)
    }

    private var accentColor: Color {
        Color(red: 0.98, green: 0.82, blue: 0.42)
    }

    var body: some View {
        ZStack {
            // 1. Capa de Bloom Profundo (Fondo)
            RadialGradient(
                colors: [
                    baseColor.opacity(isIntro ? 0.45 : 0.32),
                    accentColor.opacity(isIntro ? 0.22 : 0.14),
                    .clear
                ],
                center: .center,
                startRadius: 4,
                endRadius: radius * 1.6
            )
            .blur(radius: isIntro ? 12 : 8)
            .blendMode(.plusLighter)

            // 2. Capa de Núcleo Líquido
            ZStack {
                // Brillo base
                RadialGradient(
                    colors: [
                        .white.opacity(isIntro ? 0.72 : 0.54),
                        baseColor.opacity(isIntro ? 0.62 : 0.44),
                        .clear
                    ],
                    center: .center,
                    startRadius: 1,
                    endRadius: radius
                )

                // Shimmer de barrido angular (Liquid Glass effect)
                AngularGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.4),
                        .clear
                    ],
                    center: .center,
                    angle: .degrees(shimmerPhase * 360)
                )
                .blur(radius: 4)
                .mask {
                    Circle().inset(by: 4).stroke(lineWidth: 6).blur(radius: 2)
                }
            }
            .scaleEffect(pulse ? 1.06 : 0.94)
            .blendMode(.screen)

            // 3. Specular Glint (Destello puntual de alta intensidad)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, .white.opacity(0.4), .clear],
                        center: .center,
                        startRadius: 0.2,
                        endRadius: 4
                    )
                )
                .frame(width: 8, height: 8)
                .offset(x: -radius * 0.4, y: -radius * 0.4)
                .opacity(glintOpacity)
                .blur(radius: 0.3)

            // 4. Órbita de chispas
            if isIntro || !isSeen {
                HiddenLayerHintOrbit(type: type, progress: orbitPhase, isIntro: isIntro)
                    .opacity(isIntro ? 1 : 0.72)
            }
        }
        .frame(width: radius * 2.5, height: radius * 2.5)
        .transition(.opacity.combined(with: .scale(scale: 0.88)))
        .onAppear {
            let duration = isIntro ? 1.2 : 2.4
            
            withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true).delay(delay)) {
                pulse = true
            }
            
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false).delay(delay)) {
                shimmerPhase = 1
            }
            
            withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false).delay(delay)) {
                orbitPhase = 1
            }
            
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true).delay(delay + 0.4)) {
                glintOpacity = isIntro ? 0.95 : 0.72
            }
        }
        .onDisappear {
            pulse = false
            shimmerPhase = 0
            orbitPhase = 0
        }
    }

    private var radius: CGFloat {
        switch type {
        case .text: return 16
        case .audio: return 14
        case .image: return 18
        }
    }
}

private struct HiddenLayerHintOrbit: View {
    let type: MomentHiddenLayer.LayerType
    let progress: CGFloat
    let isIntro: Bool

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                ZStack {
                    // Estela de la chispa (más suave para muchas partículas)
                    Circle()
                        .fill(sparkColor(for: index).opacity(0.12))
                        .frame(width: sparkSize(for: index) * 2.5)
                        .blur(radius: 2.5)

                    // Chispa core
                    Circle()
                        .fill(sparkColor(for: index))
                        .frame(width: sparkSize(for: index), height: sparkSize(for: index))
                        .shadow(color: sparkColor(for: index).opacity(0.8), radius: 2)
                }
                .offset(orbitOffset(for: index))
                .scaleEffect(sparkScale(for: index))
                .opacity(sparkOpacity(for: index))
                .blur(radius: index % 3 == 0 ? 0.3 : 0) // Algunas chispas están "fuera de foco"
            }
        }
    }

    private func orbitOffset(for index: Int) -> CGSize {
        let baseRadius: CGFloat
        switch type {
        case .text: baseRadius = 18
        case .audio: baseRadius = 16
        case .image: baseRadius = 17
        }
        
        // Cada partícula tiene su propia órbita única (distancia variable)
        let uniqueRadius = baseRadius + CGFloat(sin(Double(index) * 1.5)) * 3 + (isIntro ? sin(progress * .pi * 4 + Double(index)) * 2 : 0)
        
        // Diferentes velocidades para las partículas (algunas más rápidas que otras)
        let speedMultiplier = 1.0 + Double(index % 3) * 0.2
        let angle = (progress * speedMultiplier * CGFloat.pi * 2) + (CGFloat.pi * 2 / 12 * CGFloat(index))
        
        return CGSize(
            width: cos(angle) * uniqueRadius,
            height: sin(angle) * uniqueRadius
        )
    }

    private func sparkSize(for index: Int) -> CGFloat {
        // Tamaños variados reducidos: 1.5pt a 3.5pt
        let sizes: [CGFloat] = [2.5, 1.8, 3.5, 1.5, 2.2, 2.0, 3.0, 1.6, 2.8, 2.4, 3.2, 1.4]
        return sizes[index % sizes.count]
    }

    private func sparkScale(for index: Int) -> CGFloat {
        // Twinkle effect (parpadeo de tamaño)
        let phase = progress * .pi * (8 + Double(index % 4)) + Double(index)
        return 0.7 + abs(sin(phase)) * 0.6
    }

    private func sparkOpacity(for index: Int) -> Double {
        // Twinkle effect (parpadeo de opacidad)
        let phase = progress * .pi * (6 + Double(index % 3)) + Double(index)
        let base = isIntro ? 0.6 : 0.4
        return base + abs(cos(phase)) * (1.0 - base)
    }

    private func sparkColor(for index: Int) -> Color {
        // Variación de "oros" y blancos mágicos
        switch index % 4 {
        case 0: return Color(red: 1.0, green: 0.98, blue: 0.85) // Blanco puro/cálido
        case 1: return Color(red: 1.0, green: 0.92, blue: 0.62) // Oro claro
        case 2: return Color(red: 1.0, green: 0.85, blue: 0.45) // Oro profundo
        default: return Color(red: 1.0, green: 0.95, blue: 0.75) // Champagne
        }
    }
}

/// The production hint uses the same adaptive dark/light treatment explored in
/// the design canvas: a living core and moving stars, without the rotating arc.
struct HiddenLayerHintAppearanceView: View {
    @Environment(\.colorScheme) private var colorScheme

    let type: MomentHiddenLayer.LayerType
    let shape: MomentHiddenLayer.LayerShape
    let style: MomentHiddenLayer.HintStyle
    let isSeen: Bool
    let delay: Double
    let isIntro: Bool
    var isActive: Bool = true
    var isAnimated: Bool = true
    var showsParticles: Bool = true

    @State private var pulse = false
    @State private var orbitPhase: CGFloat = 0
    @State private var glint = false

    private var isDark: Bool { colorScheme == .dark }

    private var starA: Color {
        switch style {
        case .blackAndWhite: return isDark ? .white : .black
        case .actual: return Color(red: 1.0, green: 0.92, blue: 0.62)
        case .polar: return Color(red: 0.55, green: 0.95, blue: 1.0)
        case .ember: return Color(red: 1.0, green: 0.55, blue: 0.28)
        case .ultraviolet: return Color(red: 0.78, green: 0.42, blue: 1.0)
        case .aurora: return Color(red: 0.42, green: 1.0, blue: 0.78)
        case .rose: return Color(red: 1.0, green: 0.62, blue: 0.78)
        case .plasma: return Color(red: 1.0, green: 0.55, blue: 0.92)
        case .daylight: return Color(red: 0.86, green: 0.94, blue: 1.0)
        }
    }

    private var starB: Color {
        switch style {
        case .blackAndWhite: return isDark ? .white : .black
        case .actual: return Color(red: 0.98, green: 0.82, blue: 0.42)
        case .polar: return Color(red: 0.62, green: 0.48, blue: 1.0)
        case .ember: return Color(red: 1.0, green: 0.78, blue: 0.18)
        case .ultraviolet: return Color(red: 0.78, green: 1.0, blue: 0.28)
        case .aurora: return Color(red: 0.22, green: 0.82, blue: 0.95)
        case .rose: return Color(red: 1.0, green: 0.32, blue: 0.58)
        case .plasma: return Color(red: 0.95, green: 0.25, blue: 0.72)
        case .daylight: return Color(red: 0.35, green: 0.72, blue: 1.0)
        }
    }

    private var coreColor: Color {
        if style == .blackAndWhite {
            return (isDark ? Color.white : Color.black).opacity(0.72)
        }
        return .white.opacity(0.78)
    }

    private var usesAdaptiveColorScheme: Bool { style == .blackAndWhite }

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    starB.opacity(usesAdaptiveColorScheme ? (isDark ? (pulse ? 0.52 : 0.34) : (pulse ? 0.34 : 0.20)) : (pulse ? 0.52 : 0.34)),
                    starA.opacity(usesAdaptiveColorScheme ? (isDark ? 0.18 : 0.08) : 0.18),
                    .clear
                ],
                center: .center,
                startRadius: 3,
                endRadius: radius * 1.75
            )
            .blur(radius: isIntro ? 12 : 8)
            .blendMode(usesAdaptiveColorScheme && !isDark ? .multiply : .plusLighter)

            RadialGradient(
                colors: [coreColor, starB.opacity(isDark ? 0.46 : 0.30), .clear],
                center: .center,
                startRadius: 1,
                endRadius: radius
            )
            .scaleEffect(pulse ? 1.06 : 0.94)
            .blendMode(usesAdaptiveColorScheme && !isDark ? .normal : .screen)

            Circle()
                .fill(isDark ? .white : starA)
                .frame(width: 7, height: 7)
                .offset(x: -radius * 0.4, y: -radius * 0.4)
                .opacity(glint ? 0.96 : 0.28)
                .blur(radius: 0.25)

            if isActive && showsParticles && (isIntro || !isSeen) {
                ForEach(0..<12, id: \.self) { index in
                    HiddenLayerMagicStar(points: index.isMultiple(of: 2) ? 4 : 5)
                        .fill(index.isMultiple(of: 3) ? starB : starA)
                        .frame(width: starSize(for: index), height: starSize(for: index))
                        .scaleEffect(starTwinkle(for: index))
                        .opacity(starOpacity(for: index))
                        .blur(radius: starTwinkle(for: index) > 1.25 ? 0.4 : 0)
                        .rotationEffect(.degrees(Double(index) * 16 + Double(orbitPhase) * 100))
                        .offset(sparkOffset(for: index))
                        .shadow(color: starB.opacity(usesAdaptiveColorScheme && !isDark ? 0.38 : 0.72), radius: 3)
                }
            }
        }
        .frame(width: radius * 2.5, height: radius * 2.5)
        .transition(.opacity.combined(with: .scale(scale: 0.88)))
        .onAppear {
            startAnimationsIfNeeded()
        }
        .onChange(of: isActive) { _, isNowActive in
            if isNowActive {
                startAnimationsIfNeeded()
            } else {
                resetAnimationState()
            }
        }
        .onDisappear {
            resetAnimationState()
        }
    }

    private func startAnimationsIfNeeded() {
        guard isActive, isAnimated else { return }
        let pulseDuration = isIntro ? 1.1 : 1.3
        withAnimation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true).delay(delay)) {
            pulse = true
        }
        withAnimation(.linear(duration: 4.8).repeatForever(autoreverses: false).delay(delay)) {
            orbitPhase = 1
        }
        withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true).delay(delay + 0.4)) {
            glint = true
        }
    }

    private func resetAnimationState() {
        pulse = false
        orbitPhase = 0
        glint = false
    }

    private var radius: CGFloat {
        switch type {
        case .text: return 16
        case .audio: return 14
        case .image: return 18
        }
    }

    private func sparkOffset(for index: Int) -> CGSize {
        let speed = 1 + CGFloat(index % 3) * 0.2
        let angle = (CGFloat(index) * .pi * 2 / 12) + orbitPhase * .pi * 2 * speed
        let orbitRadius = radius + 3 + CGFloat(index % 3) * 2
        return CGSize(width: cos(angle) * orbitRadius, height: sin(angle) * orbitRadius)
    }

    private func starSize(for index: Int) -> CGFloat {
        let sizes: [CGFloat] = [6.5, 4.0, 7.5, 3.5, 5.5, 4.5, 7.0, 3.8, 6.0, 5.0, 7.2, 3.2]
        return sizes[index % sizes.count]
    }

    private func starTwinkle(for index: Int) -> CGFloat {
        let phase = orbitPhase * .pi * (8 + CGFloat(index % 5)) + CGFloat(index) * 1.3
        return 0.28 + abs(sin(phase)) * 1.45
    }

    private func starOpacity(for index: Int) -> CGFloat {
        let phase = orbitPhase * .pi * (6 + CGFloat(index % 4)) + CGFloat(index) * 0.9
        return 0.22 + abs(sin(phase)) * 0.78
    }
}

private struct HiddenLayerMagicStar: Shape {
    let points: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * (points == 4 ? 0.28 : 0.38)
        let count = max(points, 3)
        var path = Path()

        for index in 0..<(count * 2) {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = CGFloat(index) * .pi / CGFloat(count) - .pi / 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct HiddenLayerRevealBurst: View {
    let color: Color
    let shape: MomentHiddenLayer.LayerShape

    @State private var animate = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: shape == .circle ? 999 : 18, style: .continuous)
                .stroke(color.opacity(0.4), lineWidth: 1.5)
                .scaleEffect(animate ? 1.35 : 0.8)
                .opacity(animate ? 0 : 1)
                .blur(radius: 0.5)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.8), color.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 1,
                        endRadius: 40
                    )
                )
                .scaleEffect(animate ? 1.5 : 0.4)
                .opacity(animate ? 0 : 0.9)
                .blendMode(.plusLighter)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.65)) {
                animate = true
            }
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

struct HiddenLayerTextReveal: View {
    let layer: MomentHiddenLayer
    let frameSize: CGSize
    var isAnimated = true

    @State private var appearProgress: Double = 0

    var body: some View {
        textRevealContent
            .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
            .onAppear {
                guard isAnimated else {
                    appearProgress = 1.0
                    return
                }
                let charCount = layer.text?.count ?? 0
                let duration = max(0.6, min(2.5, Double(charCount) * 0.045))
                withAnimation(.linear(duration: duration).delay(0.2)) {
                    appearProgress = 1.0
                }
            }
    }

    @ViewBuilder
    private var textRevealContent: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let rawText = layer.text ?? ""

        ZStack {
            if layer.presentationStyle == .glassCard {
                Color.clear
                    .momentsChromeGlass(in: shape)
                    .frame(width: frameSize.width, height: frameSize.height)
            } else {
                shape.fill(background)
                    .frame(width: frameSize.width, height: frameSize.height)
            }

            // Texto con animación de caracteres sincronizada con el barrido
            TypewriterText(
                text: rawText,
                font: font,
                foregroundColor: foreground,
                appearProgress: appearProgress
            )
            .shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1) // Sombra de definición (nítida)
            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 2) // Halo de contraste (suave)
            .lineLimit(5)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .opacity(appearProgress > 0 ? 1 : 0)
            .scaleEffect(0.96 + (appearProgress * 0.04))
            .mask {
                // Mascarilla de desvelado tipo barrido suave
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(.black)
                        .frame(width: appearProgress * frameSize.width)
                    
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 60)
                    
                    Spacer(minLength: 0)
                }
                .offset(x: -30) // Offset para que el degradado empiece antes
            }
        }
    }

    private var font: Font {
        switch layer.textStyle ?? .clean {
        case .clean: return .system(size: 15, weight: .semibold, design: .rounded)
        case .serif: return .system(size: 16, weight: .semibold, design: .serif)
        case .handwritten: 
            // Intentar Caveat (Google Font), fallback a Chalkboard SE (Native)
            return .custom("Caveat-Medium", size: 21, relativeTo: .body)
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

private struct TypewriterText: View {
    let text: String
    let font: Font
    let foregroundColor: Color
    let appearProgress: Double
    
    var body: some View {
        let charCount = text.count
        let visibleCount = Int(Double(charCount) * appearProgress)
        
        Text(text.prefix(visibleCount))
            .font(font)
            .foregroundStyle(foregroundColor)
            + Text(text.dropFirst(visibleCount))
            .font(font)
            .foregroundStyle(.clear)
    }
}


struct HiddenLayerAudioReveal: View {
    let audioURL: String
    let duration: Double
    let frameSize: CGSize
    let shouldAutoplay: Bool
    var isAnimated = true

    var body: some View {
        HiddenLayerAudioTagView(
            audioURL: audioURL,
            duration: duration,
            shouldAutoplay: shouldAutoplay,
            isAnimated: isAnimated
        )
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
    let isAnimated: Bool

    @State private var isPlaying = false
    @State private var isPreparing = false
    @State private var progress: Double = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioSession = MomentsAudioSessionLease()
    @State private var audioLoadTask: Task<Void, Never>?
    @State private var timer: Timer?
    @State private var waveTask: Task<Void, Never>?
    @State private var animatedHeights: [CGFloat] = [10, 14, 10]
    @State private var didAppear = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .momentsChromeGlass(in: Circle())

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [.white, .white.opacity(0.8)], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: .black.opacity(0.3), radius: 3) // Sombra para el anillo de progreso

            VStack(spacing: 6) {
                Image(systemName: isPreparing ? "arrow.down.circle" : (isPlaying ? "pause.fill" : "play.fill"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))

                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(.white)
                            .frame(width: 3, height: isPlaying ? animatedHeights[i] : (didAppear ? 10 : 0))
                    }
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 5, x: 0, y: 1) // Sombra para icono y ondas
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
            if isAnimated {
                MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.delight.delay(0.3)) {
                    didAppear = true
                }
            } else {
                didAppear = true
            }
            if shouldAutoplay {
                startPlayback()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: MomentsAudioSession.interruptionNotification)) { _ in
            pausePlayback()
        }
        .onDisappear {
            waveTask?.cancel()
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

        audioLoadTask?.cancel()
        audioLoadTask = Task {
            do {
                let player: AVAudioPlayer
                if url.scheme == "file" {
                    player = try AVAudioPlayer(contentsOf: url)
                } else {
                    let cachedURL = try await PersistentAudioCache.shared.localURL(for: url)
                    player = try AVAudioPlayer(contentsOf: cachedURL)
                }

                guard !Task.isCancelled else { return }
                let activated = await audioSession.activate(category: userInitiated ? .playback : .ambient)
                guard !Task.isCancelled else { return }
                guard activated else { await MainActor.run { isPreparing = false }; return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.audioPlayer = player
                    guard player.play() else { self.audioSession.deactivate(); self.isPreparing = false; return }
                    self.isPlaying = true
                    self.isPreparing = false
                    self.startProgressTimer()
                }
            } catch {
                guard !Task.isCancelled else { return }
                audioSession.deactivate()
                await MainActor.run {
                    self.isPreparing = false
                }
            }
        }
    }

    private func stopPlayback() {
        audioLoadTask?.cancel()
        audioLoadTask = nil
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
        audioLoadTask?.cancel()
        audioLoadTask = nil
        audioSession.deactivate()
        audioPlayer?.pause()
        isPlaying = false
        isPreparing = false
        timer?.invalidate()
        timer = nil
    }

    private func resumePlayback(promoteToPlayback: Bool) {
        if let audioPlayer {
            audioLoadTask?.cancel()
            audioLoadTask = Task { @MainActor in
                guard await audioSession.activate(), !Task.isCancelled else { return }
                guard audioPlayer.play() else { audioSession.deactivate(); return }
                isPlaying = true
                startProgressTimer()
            }
        } else {
            startPlayback(userInitiated: promoteToPlayback)
        }
    }

    private func finishPlayback() {
        audioLoadTask?.cancel()
        audioLoadTask = nil
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let player = self.audioPlayer {
                self.progress = player.currentTime / max(player.duration, 0.001)
                if !player.isPlaying {
                    finishPlayback()
                }
            }
        }
    }

    private func startWaveAnimation() {
        waveTask?.cancel()
        guard isPlaying else {
            animatedHeights = [10, 14, 10]
            return
        }
        guard !MotionPolicy.reduceMotion else {
            animatedHeights = [12, 16, 12]
            return
        }

        waveTask = Task { @MainActor in
            while isPlaying && !Task.isCancelled {
                animatedHeights = [
                    CGFloat.random(in: 6...16),
                    CGFloat.random(in: 10...20),
                    CGFloat.random(in: 6...16)
                ]
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if !isPlaying {
                animatedHeights = [10, 14, 10]
            }
        }
    }

    private func restoreAudioSessionIfNeeded() {
        audioSession.deactivate()
    }
}

struct HiddenLayerImageReveal: View {
    let url: URL
    let caption: String?
    let captionStyle: HiddenLayerTextStyle?
    let frameStyle: HiddenLayerImageFrameStyle?
    let imageOffset: CGSize
    let imageScale: Double
    let canvasSize: CGSize
    var isAnimated = true

    var body: some View {
        HiddenLayerRemotePolaroidPreview(
            url: url,
            caption: caption,
            captionStyle: captionStyle,
            frameStyle: frameStyle ?? .classic,
            imageOffset: imageOffset,
            imageScale: imageScale,
            canvasSize: canvasSize,
            isAnimated: isAnimated
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .rotationEffect(.degrees(-2))
    }
}
