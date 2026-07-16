import Foundation
import SwiftUI
import UIKit

enum VoiceRecordingFinishAction: Equatable {
    case send
    case cancel
}

/// Estado del gesto de grabación compartido entre el botón (que lo escribe) y la
/// barra (que mueve texto de cancelar y píldora del candado a juego).
final class VoiceRecordingGestureState: ObservableObject {
    @Published var cancelDragOffset: CGFloat = 0
    @Published var lockProgress: CGFloat = 0
    @Published var followOffset: CGSize = .zero
}

/// Medidas compartidas del blob de grabación (botón mantenido y send en locked).
enum VoiceRecordingBlobMetrics {
    static let surface: CGFloat = 110
    static let aura: CGFloat = 176
    static let innerAura: CGFloat = 150
    static let icon: CGFloat = 30
    static let lockOffset: CGFloat = -122

    static var auraScaleMinimum: CGFloat { surface / aura }
    static var innerAuraScaleMinimum: CGFloat { surface / innerAura }
}

/// Dos ondas con distinta inercia: la interior sigue los picos de voz y la
/// exterior conserva parte de esa energía para producir un halo orgánico.
struct VoiceRecordingReactiveAura: View {
    @ObservedObject private var recorder = AudioRecordingManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var fastLevel: CGFloat = 0
    @State private var slowLevel: CGFloat = 0

    private let outerMorph = VoiceBlobMorphProfile(seed: 0x51A1_7E55, segmentDuration: 1.35, pointsCount: 8)
    private let innerMorph = VoiceBlobMorphProfile(seed: 0xC0DE_FACE, segmentDuration: 0.95, pointsCount: 8)

    private var motionMultiplier: CGFloat {
        reduceMotion ? 0.18 : 1
    }

    private var innerScale: CGFloat {
        let minimum = VoiceRecordingBlobMetrics.innerAuraScaleMinimum
        return minimum + fastLevel * motionMultiplier * (1 - minimum)
    }

    private var outerScale: CGFloat {
        let minimum = VoiceRecordingBlobMetrics.auraScaleMinimum
        let energy = max(slowLevel, fastLevel * 0.62)
        return minimum + energy * motionMultiplier * (1 - minimum)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            ZStack {
                blobLayer(morph: outerMorph, now: now, size: VoiceRecordingBlobMetrics.aura, meshSpeed: 0.42)
                    .opacity(outerOpacity)
                    .scaleEffect(outerScale)

                blobLayer(morph: innerMorph, now: now, size: VoiceRecordingBlobMetrics.innerAura, meshSpeed: 0.78)
                    .opacity(innerOpacity)
                    .scaleEffect(innerScale)
            }
        }
        .frame(width: VoiceRecordingBlobMetrics.aura, height: VoiceRecordingBlobMetrics.aura)
        .allowsHitTesting(false)
        .animation(.linear(duration: 0.055), value: fastLevel)
        .animation(.linear(duration: 0.11), value: slowLevel)
        .onReceive(recorder.$audioPower) { power in
            updateLevels(with: power)
        }
    }

    @ViewBuilder
    private func blobLayer(morph: VoiceBlobMorphProfile, now: TimeInterval, size: CGFloat, meshSpeed: Double) -> some View {
        let points = reduceMotion ? VoiceBlobShape.circlePoints(count: morph.pointsCount) : morph.points(at: now)
        AuroraMeshLayer(speed: meshSpeed)
            .frame(width: size, height: size)
            .mask(VoiceBlobShape(points: points))
    }

    private var innerOpacity: Double {
        let base = colorScheme == .dark ? 0.34 : 0.28
        return base + Double(fastLevel) * 0.22
    }

    private var outerOpacity: Double {
        let base = colorScheme == .dark ? 0.22 : 0.18
        return base + Double(slowLevel) * 0.18
    }

    private func updateLevels(with power: Float) {
        let rawLevel = CGFloat(min(1, max(0, power)))
        let gatedLevel = max(0, (rawLevel - 0.12) / 0.88)
        let voiceEnergy = pow(gatedLevel, 0.48)

        let fastCoefficient: CGFloat = voiceEnergy > fastLevel ? 0.72 : 0.34
        fastLevel += (voiceEnergy - fastLevel) * fastCoefficient
        slowLevel += (voiceEnergy - slowLevel) * 0.18
    }
}

private struct VoiceBlobMorphProfile {
    let seed: UInt64
    let segmentDuration: Double
    let pointsCount: Int

    func points(at time: TimeInterval) -> [CGPoint] {
        guard segmentDuration > 0 else { return VoiceBlobShape.circlePoints(count: pointsCount) }
        let segment = floor(time / segmentDuration)
        let localT = (time - segment * segmentDuration) / segmentDuration
        let eased = Self.easeInOut(localT)
        let from = Self.randomPoints(seed: seed, segment: Int64(segment), count: pointsCount)
        let to = Self.randomPoints(seed: seed, segment: Int64(segment) + 1, count: pointsCount)
        return zip(from, to).map {
            CGPoint(x: $0.x + ($1.x - $0.x) * eased, y: $0.y + ($1.y - $0.y) * eased)
        }
    }

    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    private static func randomPoints(seed: UInt64, segment: Int64, count: Int) -> [CGPoint] {
        var rng = SplitMix64(seed: seed &+ UInt64(bitPattern: segment) &* 0x9E37_79B9_7F4A_7C15)
        let angle = (Double.pi * 2) / Double(count)
        let randomness = 1.0
        let rangeStart = 1 / (1 + randomness / 10)
        let startAngle = angle * Double.random(in: 0..<1, using: &rng)

        return (0..<count).map { i -> CGPoint in
            let randPointOffset = (rangeStart + Double.random(in: 0..<1, using: &rng) * (1 - rangeStart)) / 2
            let angleRandomness = angle * 0.1
            let randAngle = angle + angle * (angleRandomness * Double.random(in: 0..<1, using: &rng) - angleRandomness * 0.5)
            let a = startAngle + Double(i) * randAngle
            return CGPoint(x: sin(a) * randPointOffset, y: cos(a) * randPointOffset)
        }
    }
}

private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private struct VoiceBlobShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard points.count >= 3 else { return Circle().path(in: rect) }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let scaled = points.map {
            CGPoint(x: center.x + $0.x * rect.width, y: center.y + $0.y * rect.height)
        }
        return Self.smoothClosedPath(through: scaled, smoothness: Self.smoothness(for: points.count))
    }

    static func circlePoints(count: Int) -> [CGPoint] {
        (0..<count).map { i in
            let a = (Double.pi * 2) * Double(i) / Double(count)
            return CGPoint(x: cos(a) * 0.46, y: sin(a) * 0.46)
        }
    }

    private static func smoothness(for count: Int) -> CGFloat {
        let angle = (CGFloat.pi * 2) / CGFloat(count)
        return ((4 / 3) * tan(angle / 4)) / sin(angle / 2) / 2
    }

    private struct SmoothPoint {
        let point: CGPoint
        let inAngle: CGFloat
        let inLength: CGFloat
        let outAngle: CGFloat
        let outLength: CGFloat

        func smoothIn() -> CGPoint { smooth(angle: inAngle, length: inLength) }
        func smoothOut() -> CGPoint { smooth(angle: outAngle, length: outLength) }
        private func smooth(angle: CGFloat, length: CGFloat) -> CGPoint {
            CGPoint(x: point.x + length * cos(angle), y: point.y + length * sin(angle))
        }
    }

    private static func smoothClosedPath(through points: [CGPoint], smoothness: CGFloat) -> Path {
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
        }

        var smoothPoints: [SmoothPoint] = []
        smoothPoints.reserveCapacity(points.count)
        for index in points.indices {
            let prevIndex = index - 1
            let prev = points[prevIndex >= 0 ? prevIndex : points.count + prevIndex]
            let curr = points[index]
            let next = points[(index + 1) % points.count]

            let dx = next.x - prev.x
            let dy = -next.y + prev.y
            let rawAngle = atan2(dy, dx)
            let angle: CGFloat = rawAngle < 0 ? abs(rawAngle) : 2 * .pi - rawAngle

            smoothPoints.append(
                SmoothPoint(
                    point: curr,
                    inAngle: angle + .pi,
                    inLength: smoothness * distance(curr, prev),
                    outAngle: angle,
                    outLength: smoothness * distance(curr, next)
                )
            )
        }

        var path = Path()
        guard let first = smoothPoints.first else { return path }
        path.move(to: first.point)
        for index in smoothPoints.indices {
            let curr = smoothPoints[index]
            let next = smoothPoints[(index + 1) % smoothPoints.count]
            path.addCurve(to: next.point, control1: curr.smoothOut(), control2: next.smoothIn())
        }
        path.closeSubpath()
        return path
    }
}

private enum VoiceRecordingGesturePhase: Equatable {
    case idle
    case pressing
    case recordingHeld
    case recordingLocked
}

struct VoiceRecordingGestureButton: View {
    let tint: Color
    let isRecording: Bool
    let activeInteractionId: UUID?
    @Binding var isLocked: Bool
    /// Estado compartido con la barra (texto de cancelar, píldora del candado).
    @ObservedObject var gestureState: VoiceRecordingGestureState
    let glassInteractive: Bool
    let onStart: (UUID, Bool) -> Void
    let onFinish: (UUID, VoiceRecordingFinishAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @State private var phase: VoiceRecordingGesturePhase = .idle
    @State private var interactionId: UUID?
    @State private var holdTask: Task<Void, Never>?
    @State private var lockProgress: CGFloat = 0
    @State private var cancelProgress: CGFloat = 0
    @State private var lastLockTick = 0
    @State private var latestTranslation: CGSize = .zero
    // El blob sigue al dedo con retardo (spring interactivo): es lo que da el
    // tacto "líquido" al gesto, en vez de un blob clavado en su sitio.
    @State private var blobFollowOffset: CGSize = .zero

    private let holdNanoseconds: UInt64 = 190_000_000
    private let directionThreshold: CGFloat = 8
    // Recorrido largo: el blob viaja con el dedo hasta el candado (~105pt de arrastre
    // real); con distancias cortas el gesto se siente rígido en vez de líquido.
    private let lockDistance: CGFloat = 105
    private let cancelDistance: CGFloat = 150
    private let followOvershoot: CGFloat = 46

    private var showsRecordingOverlay: Bool {
        // `GlassmorphicInputBar` cambia de contenedor al arrancar la grabación. SwiftUI puede
        // recrear este botón durante esa transición y perder `phase`, pero la sesión real sigue
        // viva en `isRecording`; el aura debe seguir a la sesión, no a la identidad efímera de la vista.
        isRecording || phase == .recordingHeld || phase == .recordingLocked
    }

    var body: some View {
        Button(action: accessibilityActivate) {
            ZStack {
                AttachmentIconView(
                    icon: .voice,
                    preset: .chatVoiceInput,
                    tintColor: tint
                )
                .opacity(showsRecordingOverlay ? 0 : 1)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .momentsChromeGlass(in: Circle(), interactive: glassInteractive)
            .overlay {
                if showsRecordingOverlay {
                    recordingOverlay
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .scale(scale: 0.68, anchor: .bottom).combined(with: .opacity)
                        )
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.1), value: showsRecordingOverlay)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(recordingGesture)
        .accessibilityLabel(Text("chat.voice.record.accessibility"))
        .accessibilityHint(Text("chat.voice.record.holdHint"))
        .onChange(of: isRecording) { _, recording in
            if !recording, !isLocked, activeInteractionId == nil {
                resetLocalState()
            }
        }
        .onChange(of: isLocked) { _, locked in
            if !locked, !isRecording {
                resetLocalState()
            }
        }
        .onChange(of: activeInteractionId) { _, activeId in
            if activeId == nil, phase != .pressing, !isRecording {
                resetLocalState()
            }
        }
        .onDisappear {
            holdTask?.cancel()
            holdTask = nil
        }
    }

    private var recordingOverlay: some View {
        ZStack {
            Group {
                VoiceRecordingReactiveAura()

                VoiceRecordingAuroraCircleSurface {
                    Image(systemName: "mic.fill")
                        .font(.system(size: VoiceRecordingBlobMetrics.icon, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, options: .repeating, isActive: isRecording && !reduceMotion)
                }
            }
            // El blob viaja con el dedo en ambos ejes; el botón base permanece anclado.
            .offset(x: blobFollowOffset.width, y: blobFollowOffset.height)
        }
        .frame(width: 44, height: 44)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.press, value: isLocked), value: isLocked)
    }

    private var recordingGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if interactionId == nil {
                    beginPress()
                }
                latestTranslation = value.translation
                guard phase == .recordingHeld else { return }
                updateDrag(translation: value.translation)
            }
            .onEnded { _ in
                endPress()
            }
    }

    private func beginPress() {
        guard !voiceOverEnabled else { return }
        let id = UUID()
        interactionId = id
        phase = .pressing
        lockProgress = 0
        cancelProgress = 0
        lastLockTick = 0

        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: holdNanoseconds)
            guard !Task.isCancelled, interactionId == id, phase == .pressing else { return }
            phase = .recordingHeld
            HapticManager.shared.lightImpact()
            UIAccessibility.post(
                notification: .announcement,
                argument: NSLocalizedString("chat.voice.record.started", comment: "Voice recording started")
            )
            onStart(id, false)
            if latestTranslation != .zero {
                updateDrag(translation: latestTranslation)
            }
        }
    }

    /// Sin jaula de ejes: lock y cancelar se evalúan a la vez y el blob sigue al
    /// dedo en cualquier dirección (con goma hacia abajo/derecha).
    private func updateDrag(translation: CGSize) {
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        guard max(horizontal, vertical) >= directionThreshold || blobFollowOffset != .zero else { return }

        lockProgress = min(1, max(0, -translation.height / lockDistance))
        cancelProgress = min(1, max(0, -translation.width / cancelDistance))
        gestureState.lockProgress = lockProgress
        if lockProgress == 0 {
            lastLockTick = 0
        }
        updateBlobFollow(x: translation.width, y: translation.height)
        emitLockTickIfNeeded()

        if lockProgress >= 1, lockProgress >= cancelProgress {
            commitLock()
        } else if cancelProgress >= 1 {
            commitCancellation()
        }
    }

    /// Seguimiento amortiguado del dedo: 1:1 hacia lock/cancelar (con margen suave
    /// pasado el objetivo) y con resistencia de goma en las direcciones "sin destino".
    private func updateBlobFollow(x: CGFloat, y: CGFloat) {
        guard !reduceMotion else { return }

        let followY = y <= 0
            ? max(-(lockDistance + followOvershoot), y)
            : min(26, y * 0.3)
        let followX = x <= 0
            ? max(-(cancelDistance + followOvershoot), x)
            : min(26, x * 0.3)

        withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.82)) {
            blobFollowOffset = CGSize(width: followX, height: followY)
            gestureState.followOffset = blobFollowOffset
            gestureState.cancelDragOffset = min(0, x)
        }
    }

    private func settleBlobFollow() {
        guard blobFollowOffset != .zero || gestureState.cancelDragOffset != 0 else { return }
        if reduceMotion {
            blobFollowOffset = .zero
            gestureState.followOffset = .zero
            gestureState.cancelDragOffset = 0
            return
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            blobFollowOffset = .zero
            gestureState.followOffset = .zero
            gestureState.cancelDragOffset = 0
        }
    }

    private func emitLockTickIfNeeded() {
        let tick = min(4, Int((lockProgress * 4).rounded(.down)))
        guard tick > lastLockTick else { return }
        lastLockTick = tick
        HapticManager.shared.selection()
    }

    private func commitLock() {
        guard phase == .recordingHeld else { return }
        phase = .recordingLocked
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.press) {
            isLocked = true
        }
        lockProgress = 1
        settleBlobFollow()
        HapticManager.shared.success()
        UIAccessibility.post(
            notification: .announcement,
            argument: NSLocalizedString("chat.voice.record.locked", comment: "Voice recording locked")
        )
    }

    private func commitCancellation() {
        guard phase == .recordingHeld, let id = interactionId else { return }
        HapticManager.shared.warning()
        UIAccessibility.post(
            notification: .announcement,
            argument: NSLocalizedString("chat.voice.record.cancelled", comment: "Voice recording cancelled")
        )
        onFinish(id, .cancel)
        resetLocalState()
    }

    private func endPress() {
        holdTask?.cancel()
        holdTask = nil

        guard let id = interactionId else {
            resetLocalState()
            return
        }

        switch phase {
        case .pressing:
            resetLocalState()
        case .recordingHeld:
            onFinish(id, .send)
            resetLocalState()
        case .recordingLocked:
            interactionId = nil
        case .idle:
            resetLocalState()
        }
    }

    private func accessibilityActivate() {
        guard voiceOverEnabled, !isRecording else { return }
        let id = UUID()
        interactionId = id
        phase = .recordingLocked
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.press) {
            isLocked = true
        }
        HapticManager.shared.lightImpact()
        onStart(id, true)
    }

    private func resetLocalState() {
        holdTask?.cancel()
        holdTask = nil
        phase = .idle
        interactionId = nil
        lockProgress = 0
        cancelProgress = 0
        lastLockTick = 0
        latestTranslation = .zero
        blobFollowOffset = .zero
        gestureState.followOffset = .zero
        gestureState.cancelDragOffset = 0
        gestureState.lockProgress = 0
    }
}
