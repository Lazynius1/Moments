import Foundation
import SwiftUI
import UIKit

enum VoiceRecordingFinishAction: Equatable {
    case send
    case cancel
}

private enum VoiceRecordingGesturePhase: Equatable {
    case idle
    case pressing
    case recordingHeld
    case recordingLocked
}

private enum VoiceRecordingDragAxis {
    case vertical
    case horizontal
}

struct VoiceRecordingGestureButton: View {
    let tint: Color
    let isRecording: Bool
    let activeInteractionId: UUID?
    @Binding var isLocked: Bool
    let onStart: (UUID, Bool) -> Void
    let onFinish: (UUID, VoiceRecordingFinishAction) -> Void

    @ObservedObject private var recorder = AudioRecordingManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @State private var phase: VoiceRecordingGesturePhase = .idle
    @State private var interactionId: UUID?
    @State private var holdTask: Task<Void, Never>?
    @State private var dragAxis: VoiceRecordingDragAxis?
    @State private var lockProgress: CGFloat = 0
    @State private var cancelProgress: CGFloat = 0
    @State private var smoothedLevel: CGFloat = 0
    @State private var lastLockTick = 0
    @State private var latestTranslation: CGSize = .zero

    private let holdNanoseconds: UInt64 = 190_000_000
    private let directionThreshold: CGFloat = 8
    private let lockDistance: CGFloat = 72
    private let cancelDistance: CGFloat = 70

    private var showsRecordingOverlay: Bool {
        phase == .recordingHeld || phase == .recordingLocked
    }

    var body: some View {
        Button(action: accessibilityActivate) {
            AttachmentIconView(
                icon: .voice,
                preset: .chatVoiceInput,
                tintColor: tint
            )
            .frame(width: 44, height: 44)
            .contentShape(Circle())
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
        }
        .buttonStyle(.plain)
        .simultaneousGesture(recordingGesture)
        .accessibilityLabel(Text("chat.voice.record.accessibility"))
        .accessibilityHint(Text("chat.voice.record.holdHint"))
        .onReceive(recorder.$audioPower) { power in
            let target = CGFloat(min(1, max(0, power)))
            if reduceMotion {
                smoothedLevel = target
            } else {
                withAnimation(.linear(duration: 0.08)) {
                    smoothedLevel = smoothedLevel * 0.72 + target * 0.28
                }
            }
        }
        .onChange(of: isRecording) { _, recording in
            if !recording, interactionId == nil {
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
            lockAffordance

            AuroraMeshLayer(speed: 0.65)
                .frame(width: 160, height: 160)
                .clipShape(Circle())
                .blur(radius: 10)
                .opacity(colorScheme == .dark ? 0.88 : 0.78)
                .scaleEffect(auraScale)

            VoiceRecordingAuroraCircleSurface()
                .frame(width: 110, height: 110)

            Image(systemName: "mic.fill")
                .font(.system(size: 37, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, options: .repeating, isActive: isRecording && !reduceMotion)
        }
        .frame(width: 260, height: 250)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.press, value: isLocked), value: isLocked)
    }

    private var auraScale: CGFloat {
        let minimum = 110.0 / 160.0
        let activity = reduceMotion ? smoothedLevel * 0.18 : smoothedLevel
        return minimum + activity * (1 - minimum)
    }

    private var lockAffordance: some View {
        VStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 17, weight: .semibold))

            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .bold))
                .opacity(0.5 + lockProgress * 0.5)
        }
        .foregroundStyle(tint)
        .frame(width: 40, height: 72)
        .background {
            Color.clear
                .momentsChromeGlass(in: Capsule(), interactive: false)
        }
        .offset(y: -130 - (reduceMotion ? 0 : lockProgress * 12))
        .scaleEffect(isLocked ? 1.06 : 0.94 + lockProgress * 0.06)
        .opacity(phase == .recordingHeld || phase == .recordingLocked ? 1 : 0)
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
        dragAxis = nil
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

    private func updateDrag(translation: CGSize) {
        if dragAxis == nil {
            let horizontal = abs(translation.width)
            let vertical = abs(translation.height)
            guard max(horizontal, vertical) >= directionThreshold else { return }
            dragAxis = vertical > horizontal ? .vertical : .horizontal
        }

        switch dragAxis {
        case .vertical:
            cancelProgress = 0
            lockProgress = min(1, max(0, -translation.height / lockDistance))
            emitLockTickIfNeeded()
            if lockProgress >= 1 {
                commitLock()
            }
        case .horizontal:
            lockProgress = 0
            cancelProgress = min(1, max(0, -translation.width / cancelDistance))
            if cancelProgress >= 1 {
                commitCancellation()
            }
        case nil:
            break
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
        dragAxis = nil
        lockProgress = 1
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
        dragAxis = nil
        lockProgress = 0
        cancelProgress = 0
        lastLockTick = 0
        latestTranslation = .zero
        smoothedLevel = 0
    }
}
