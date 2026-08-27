import AVFoundation
import SwiftUI

struct GlassmorphicInputBar: View {
    @Binding var text: String
    @Binding var isTyping: Bool
    @Binding var isRecordingVoice: Bool
    @Binding var isVoiceRecordingLocked: Bool
    @Binding var activeAttachmentSheet: ChatAttachmentSheetKind?
    var isVanishModeActive: Bool = false
    var allowsAttachments: Bool = true
    var allowsVoiceRecording: Bool = true
    let recordingTime: TimeInterval
    let recordingInteractionId: UUID?
    let voiceRecordingDraft: VoiceRecordingDraft?
    let isPreparingVoiceRecordingPreview: Bool
    let replyingTo: EnhancedMessage?
    let otherParticipantName: String
    @ObservedObject var voiceGestureState: VoiceRecordingGestureState
    let onCancelReply: () -> Void
    let onSend: () -> Void
    let onStartVoiceRecording: (UUID, Bool) -> Void
    let onFinishVoiceRecording: (UUID, VoiceRecordingFinishAction) -> Void
    let onVoiceRecordingTrimChanged: (Range<TimeInterval>) -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var isMenuOpen: Bool {
        activeAttachmentSheet == .menu
    }

    private var inputPlaceholder: LocalizedStringKey {
        isVanishModeActive ? "chat.input.vanish.placeholder" : "chat.input.placeholder"
    }

    private var inputFieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var vanishStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.22)
    }

    var body: some View {
        // Mantener GlassEffectContainer estable durante el DragGesture del mic.
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: shouldCoordinateComposerGlass ? 10 : 0) {
                inputRow
            }
        } else {
            inputRow
        }
    }

    private var shouldCoordinateComposerGlass: Bool {
        replyingTo == nil
            && !isRecordingVoice
            && voiceRecordingDraft == nil
            && !isPreparingVoiceRecordingPreview
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            leadingControl
            composerSurface
            trailingControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: isVanishModeActive), value: isVanishModeActive)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: isRecordingVoice), value: isRecordingVoice)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: isVoiceRecordingLocked), value: isVoiceRecordingLocked)
    }

    private var composerSurface: some View {
        VStack(spacing: 0) {
            if let replyingTo {
                ChatComposerReplyHeader(
                    message: replyingTo,
                    otherParticipantName: otherParticipantName,
                    onCancel: onCancelReply
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))

                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07))
                    .frame(height: 0.5)
            }

            composerContent
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .momentsChromeGlass(
            in: inputFieldShape,
            interactive: !isVanishModeActive && replyingTo == nil,
            style: .native
        )
        .background {
            if isVanishModeActive {
                inputFieldShape
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
            }
        }
        .compositingGroup()
        .clipShape(inputFieldShape)
        .overlay {
            inputFieldShape
                .stroke(
                    isVanishModeActive
                        ? vanishStrokeColor
                        : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)),
                    style: isVanishModeActive
                        ? StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                        : StrokeStyle(lineWidth: 0.8)
                )
        }
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: replyingTo?.id), value: replyingTo?.id)
        .animation(.easeInOut(duration: 0.2), value: isRecordingVoice)
        .animation(.easeInOut(duration: 0.2), value: isPreparingVoiceRecordingPreview)
        .animation(.easeInOut(duration: 0.2), value: voiceRecordingDraft != nil)
    }

    private var composerContent: some View {
        ZStack {
            if isRecordingVoice {
                VoiceRecordingHeldStatus(
                    isLocked: isVoiceRecordingLocked,
                    recordingTime: recordingTime,
                    cancelDragOffset: voiceGestureState.cancelDragOffset,
                    adaptiveColors: adaptiveColors,
                    onCancel: cancelVoiceRecording
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if voiceRecordingDraft != nil || isPreparingVoiceRecordingPreview {
                VoiceRecordingDraftPreview(
                    draft: voiceRecordingDraft,
                    fallbackDuration: recordingTime,
                    isPreparing: isPreparingVoiceRecordingPreview,
                    adaptiveColors: adaptiveColors,
                    onTrimChanged: onVoiceRecordingTrimChanged
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                TextField(inputPlaceholder, text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .font(.system(size: legacyPoppinsSize(15)))
                    .foregroundStyle(adaptiveColors.primary)
                    .tint(adaptiveColors.primary)
                    .textFieldStyle(.plain)
                    .onChange(of: text) { _, newValue in
                        isTyping = !newValue.isEmpty
                    }
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var leadingControl: some View {
        if voiceRecordingDraft != nil || isPreparingVoiceRecordingPreview {
            circularGlassButton(systemName: "trash.fill", tint: .red, action: cancelVoiceRecording)
                .accessibilityLabel(Text("common.cancel"))
                .transition(.opacity.combined(with: .scale(scale: 0.78)))
        } else if !isRecordingVoice, allowsAttachments {
            ChatAttachmentPlusButton(isMenuOpen: isMenuOpen, action: toggleAttachmentMenu)
                .transition(.opacity.combined(with: .scale(scale: 0.78)))
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isVoiceRecordingLocked {
            VoiceRecordingLockedSendButton(action: sendCurrentContent)
        } else if voiceRecordingDraft != nil || isPreparingVoiceRecordingPreview {
            circularSendButton
                .disabled(isPreparingVoiceRecordingPreview)
                .opacity(isPreparingVoiceRecordingPreview ? 0.45 : 1)
        } else if !text.isEmpty {
            circularSendButton
        } else if allowsAttachments && allowsVoiceRecording {
            VoiceRecordingGestureButton(
                tint: adaptiveColors.mediaIconColor,
                isRecording: isRecordingVoice,
                activeInteractionId: recordingInteractionId,
                isLocked: $isVoiceRecordingLocked,
                gestureState: voiceGestureState,
                glassInteractive: !isVanishModeActive,
                onStart: onStartVoiceRecording,
                onFinish: onFinishVoiceRecording
            )
            .frame(width: 44, height: 44)
        }
    }

    private var circularSendButton: some View {
        Button(action: sendCurrentContent) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(adaptiveColors.userAccentColor, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("notification.action.send"))
    }

    private func circularGlassButton(
        systemName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .momentsChromeGlass(in: Circle(), interactive: true, style: .native)
        }
        .buttonStyle(.plain)
    }

    private func toggleAttachmentMenu() {
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.sheet) {
            activeAttachmentSheet = isMenuOpen ? nil : .menu
        }
    }

    private func sendCurrentContent() {
        if let recordingInteractionId, voiceRecordingDraft != nil || isRecordingVoice {
            onFinishVoiceRecording(recordingInteractionId, .send)
        } else {
            onSend()
        }
    }

    private func cancelVoiceRecording() {
        guard let recordingInteractionId else { return }
        onFinishVoiceRecording(recordingInteractionId, .cancel)
    }
}

enum VoiceRecordingFloatingControlMode: Equatable {
    case locking(progress: CGFloat)
    case pause
    case preparing
    case resume
}

struct VoiceRecordingFloatingControlHost: View {
    let isRecording: Bool
    let isLocked: Bool
    let isPreparing: Bool
    let hasDraft: Bool
    let hasActiveInteraction: Bool
    @ObservedObject var gestureState: VoiceRecordingGestureState
    let primaryTint: Color
    let accentTint: Color
    let onPause: () -> Void
    let onResume: () -> Void

    private var mode: VoiceRecordingFloatingControlMode? {
        if isLocked {
            return .pause
        }
        if isRecording {
            return .locking(progress: gestureState.lockProgress)
        }
        if isPreparing, hasActiveInteraction {
            return .preparing
        }
        if hasDraft, hasActiveInteraction {
            return .resume
        }
        return nil
    }

    /// Mientras arrastras hacia el lock, el candado viaja con el mismo desplazamiento
    /// que el blob: siempre va por delante y el blob nunca lo adelanta.
    private var rideAlongOffsetY: CGFloat {
        if case .locking = mode {
            return gestureState.followOffset.height
        }
        return 0
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let mode {
                VoiceRecordingFloatingControl(
                    mode: mode,
                    primaryTint: primaryTint,
                    accentTint: accentTint,
                    onPause: onPause,
                    onResume: onResume
                )
                .offset(y: rideAlongOffsetY)
                .transition(.opacity.combined(with: .scale(scale: 0.72, anchor: .bottom)))
            }
        }
        .frame(width: 44, height: 72, alignment: .bottom)
        .allowsHitTesting(mode != nil)
        .animation(.easeInOut(duration: 0.2), value: mode != nil)
    }
}

/// Un único control conserva posición, superficie glass y región táctil durante
/// toda la secuencia de grabación: candado → pausa → micrófono → pausa.
struct VoiceRecordingFloatingControl: View {
    let mode: VoiceRecordingFloatingControlMode
    let primaryTint: Color
    let accentTint: Color
    let onPause: () -> Void
    let onResume: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lockProgress: CGFloat {
        if case let .locking(progress) = mode {
            return min(1, max(0, progress))
        }
        return 1
    }

    private var controlHeight: CGFloat {
        if case .locking = mode {
            return 72 - lockProgress * 28
        }
        return 44
    }

    private var isInteractive: Bool {
        mode == .pause || mode == .resume
    }

    var body: some View {
        Button(action: performAction) {
            ZStack {
                switch mode {
                case .locking:
                    VStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 17, weight: .semibold))
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .opacity(max(0, 0.9 - lockProgress))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.72)))
                case .pause:
                    Image(systemName: "pause.fill")
                        .font(.system(size: 16, weight: .bold))
                        .transition(.opacity.combined(with: .scale(scale: 0.72)))
                case .preparing:
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity.combined(with: .scale(scale: 0.72)))
                case .resume:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .transition(.opacity.combined(with: .scale(scale: 0.72)))
                }
            }
            .foregroundStyle(mode == .resume ? accentTint : primaryTint)
            .frame(width: 44, height: controlHeight)
            .contentShape(Capsule())
            .momentsChromeGlass(in: Capsule(), interactive: isInteractive, style: .native)
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .accessibilityLabel(accessibilityLabel)
        .animation(
            reduceMotion ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.86),
            value: mode
        )
    }

    private var accessibilityLabel: Text {
        switch mode {
        case .locking:
            return Text("chat.voice.record.locked")
        case .pause:
            return Text("chat.voice.record.pause")
        case .preparing:
            return Text("common.loading")
        case .resume:
            return Text("chat.voice.record.resume")
        }
    }

    private func performAction() {
        switch mode {
        case .pause:
            onPause()
        case .resume:
            onResume()
        case .locking, .preparing:
            break
        }
    }
}

struct VoiceRecordingAuroraCircleSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                surfaceContent
                    .glassEffect(.clear.interactive(), in: Circle())
            } else {
                surfaceContent
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(colorScheme == .dark ? 0.22 : 0.34), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }

    private var surfaceContent: some View {
        ZStack {
            AuroraMeshLayer()
                .blur(radius: 10)
                .opacity(innerAuroraOpacity)

            content
        }
        .frame(width: VoiceRecordingBlobMetrics.surface, height: VoiceRecordingBlobMetrics.surface)
    }

    private var innerAuroraOpacity: Double {
        if #available(iOS 26.0, *) {
            return colorScheme == .dark ? 0.5 : 0.42
        }
        return 0.92
    }
}

private struct VoiceRecordingLockedSendButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                VoiceRecordingReactiveAura()

                VoiceRecordingAuroraCircleSurface {
                    Image(systemName: "arrow.up")
                        .font(.system(size: VoiceRecordingBlobMetrics.icon + 1, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: VoiceRecordingBlobMetrics.aura, height: VoiceRecordingBlobMetrics.aura)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .accessibilityLabel(Text("notification.action.send"))
    }
}

private struct VoiceRecordingHeldStatus: View {
    let isLocked: Bool
    let recordingTime: TimeInterval
    var cancelDragOffset: CGFloat = 0
    let adaptiveColors: AdaptiveColors
    let onCancel: () -> Void

    private var formattedTime: String {
        let minutes = Int(recordingTime) / 60
        let seconds = Int(recordingTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)

            Text(formattedTime)
                .font(.system(size: legacyPoppinsSize(13), weight: .medium, design: .monospaced))
                .foregroundStyle(adaptiveColors.primary)

            Spacer(minLength: 6)

            if isLocked {
                Button("common.cancel", action: onCancel)
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                    .foregroundStyle(adaptiveColors.accent)
                    .buttonStyle(.plain)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("chat.voice.record.slideToCancel")
                        .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(adaptiveColors.timestampColor)
                // El texto acompaña el arrastre del blob hacia cancelar y se desvanece.
                .offset(x: cancelDragOffset * 0.55)
                .opacity(max(0, 1 + Double(cancelDragOffset) / 130))
            }
        }
        .padding(.trailing, 46)
    }
}

private struct VoiceRecordingDraftPreview: View {
    let draft: VoiceRecordingDraft?
    let fallbackDuration: TimeInterval
    let isPreparing: Bool
    let adaptiveColors: AdaptiveColors
    let onTrimChanged: (Range<TimeInterval>) -> Void

    @StateObject private var player = VoiceRecordingDraftPlayer()
    @State private var workingTrimRange: Range<TimeInterval>?
    @State private var trimGestureOrigin: Range<TimeInterval>?

    private var sourceWaveform: [Float] {
        let samples = draft?.waveform ?? []
        return samples.isEmpty ? Array(repeating: 0.22, count: 16) : samples
    }

    private var duration: TimeInterval {
        draft?.duration ?? fallbackDuration
    }

    private var fullDuration: TimeInterval {
        draft?.fullDuration ?? fallbackDuration
    }

    private var trimRange: Range<TimeInterval> {
        workingTrimRange
            ?? draft?.normalizedTrimRange
            ?? 0..<max(fullDuration, 0)
    }

    var body: some View {
        HStack(spacing: 8) {
            playbackControl

            GeometryReader { proxy in
                let sampleCount = max(18, min(64, Int(proxy.size.width / 4.5)))
                let width = max(proxy.size.width, 1)
                let lowerX = width * trimFraction(trimRange.lowerBound)
                let upperX = width * trimFraction(trimRange.upperBound)

                ZStack(alignment: .leading) {
                    VisualWaveformView(
                        levels: ChatVoiceWaveformSamples.resampled(sourceWaveform, count: sampleCount),
                        color: adaptiveColors.timestampColor.opacity(0.45),
                        activeColor: adaptiveColors.primary.opacity(0.82),
                        progress: player.progress,
                        height: 23,
                        barWidth: 2.5,
                        spacing: 2
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                player.seek(to: value.location.x / width)
                            }
                    )

                    adaptiveColors.background.opacity(0.58)
                        .frame(width: lowerX)
                        .allowsHitTesting(false)

                    adaptiveColors.background.opacity(0.58)
                        .frame(width: max(0, width - upperX))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(adaptiveColors.primary.opacity(0.58), lineWidth: 1)
                        .frame(width: max(1, upperX - lowerX), height: 26)
                        .offset(x: lowerX)
                        .allowsHitTesting(false)

                    trimHandle(isLeading: true, x: lowerX, width: width)
                    trimHandle(isLeading: false, x: upperX, width: width)
                }
                .coordinateSpace(.named("voiceTrimWaveform"))
            }
            .frame(height: 26)
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .onAppear {
            workingTrimRange = draft?.normalizedTrimRange
            player.load(draft?.recording?.data, trimRange: trimRange)
        }
        .onChange(of: draft?.recording?.data.count) { _, _ in
            workingTrimRange = draft?.normalizedTrimRange
            player.load(draft?.recording?.data, trimRange: trimRange)
        }
        .onChange(of: draft?.normalizedTrimRange) { _, newValue in
            workingTrimRange = newValue
            player.setTrimRange(newValue ?? 0..<max(fullDuration, 0))
        }
        .onDisappear { player.stop() }
    }

    private func trimFraction(_ time: TimeInterval) -> CGFloat {
        guard fullDuration > 0 else { return 0 }
        return CGFloat(min(1, max(0, time / fullDuration)))
    }

    private func trimHandle(isLeading: Bool, x: CGFloat, width: CGFloat) -> some View {
        Capsule()
            .fill(adaptiveColors.primary.opacity(0.88))
            .frame(width: 3, height: 26)
            .overlay {
                Color.clear
                    .frame(width: 30, height: 44)
                    .contentShape(Rectangle())
                    .gesture(trimGesture(isLeading: isLeading, width: width))
            }
            .position(x: x, y: 13)
            .accessibilityHidden(true)
    }

    private func trimGesture(isLeading: Bool, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("voiceTrimWaveform"))
            .onChanged { value in
                guard fullDuration > 0 else { return }
                if trimGestureOrigin == nil {
                    trimGestureOrigin = trimRange
                    player.pauseForEditing()
                }
                guard let origin = trimGestureOrigin else { return }
                let proposedTime = min(
                    fullDuration,
                    max(0, Double(value.location.x / width) * fullDuration)
                )
                let minimumDuration = min(2, fullDuration)
                let updatedRange: Range<TimeInterval>
                if isLeading {
                    let lowerBound = min(
                        origin.upperBound - minimumDuration,
                        proposedTime
                    )
                    updatedRange = lowerBound..<origin.upperBound
                } else {
                    let upperBound = max(
                        origin.lowerBound + minimumDuration,
                        proposedTime
                    )
                    updatedRange = origin.lowerBound..<upperBound
                }
                workingTrimRange = updatedRange
            }
            .onEnded { _ in
                if let finalRange = workingTrimRange {
                    player.setTrimRange(finalRange)
                    onTrimChanged(finalRange)
                }
                trimGestureOrigin = nil
                HapticManager.shared.selection()
            }
    }

    private var playbackControl: some View {
        Button(action: player.togglePlayback) {
            HStack(spacing: 4) {
                ZStack {
                    if isPreparing || draft?.recording == nil {
                        ProgressView()
                            .controlSize(.mini)
                            .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    }
                }
                .frame(width: 16, height: 18)

                Text(player.displayTime(fallback: duration))
                    .font(.system(size: legacyPoppinsSize(10), weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }
            .foregroundStyle(adaptiveColors.primary.opacity(0.82))
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(adaptiveColors.timestampColor.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isPreparing || draft?.recording == nil)
        .accessibilityLabel(player.isPlaying ? Text("chat.voice.pause") : Text("chat.voice.play"))
        .animation(.easeInOut(duration: 0.18), value: isPreparing)
        .animation(.easeInOut(duration: 0.18), value: player.isPlaying)
    }
}

private final class VoiceRecordingDraftPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var trimRange: Range<TimeInterval> = 0..<0

    func load(_ data: Data?, trimRange: Range<TimeInterval>) {
        stop()
        self.trimRange = trimRange
        guard let data else { return }
        audioPlayer = try? AVAudioPlayer(data: data)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()
        normalizeTrimRange()
        resetToTrimStart()
    }

    func setTrimRange(_ range: Range<TimeInterval>) {
        trimRange = range
        normalizeTrimRange()
        guard let audioPlayer else { return }
        if audioPlayer.currentTime < trimRange.lowerBound || audioPlayer.currentTime > trimRange.upperBound {
            resetToTrimStart()
        } else {
            updateProgress()
        }
    }

    func togglePlayback() {
        guard let audioPlayer else { return }
        if audioPlayer.isPlaying {
            audioPlayer.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            if audioPlayer.currentTime < trimRange.lowerBound || audioPlayer.currentTime >= trimRange.upperBound {
                resetToTrimStart()
            }
            guard audioPlayer.play() else { return }
            isPlaying = true
            startTimer()
        }
    }

    func seek(to fraction: Double) {
        guard let audioPlayer else { return }
        let clamped = min(1, max(0, fraction))
        let requestedTime = audioPlayer.duration * clamped
        audioPlayer.currentTime = min(trimRange.upperBound, max(trimRange.lowerBound, requestedTime))
        updateProgress()
    }

    func displayTime(fallback: TimeInterval) -> String {
        let currentTime = audioPlayer?.currentTime ?? trimRange.lowerBound
        let elapsed = max(0, currentTime - trimRange.lowerBound)
        let value = elapsed > 0 || isPlaying ? elapsed : fallback
        return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }

    func pauseForEditing() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        timer?.invalidate()
        timer = nil
        isPlaying = false
        progress = 0
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let audioPlayer = self.audioPlayer else { return }
            if audioPlayer.currentTime >= self.trimRange.upperBound {
                audioPlayer.pause()
                self.isPlaying = false
                self.timer?.invalidate()
                self.resetToTrimStart()
                return
            }
            self.updateProgress()
            if !audioPlayer.isPlaying {
                self.isPlaying = false
                self.timer?.invalidate()
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        timer?.invalidate()
        resetToTrimStart()
    }

    private func normalizeTrimRange() {
        guard let audioPlayer else { return }
        let lowerBound = min(audioPlayer.duration, max(0, trimRange.lowerBound))
        let upperBound = min(audioPlayer.duration, max(lowerBound, trimRange.upperBound))
        trimRange = lowerBound..<upperBound
    }

    private func resetToTrimStart() {
        audioPlayer?.currentTime = trimRange.lowerBound
        updateProgress()
    }

    private func updateProgress() {
        guard let audioPlayer, audioPlayer.duration > 0 else {
            progress = 0
            return
        }
        progress = audioPlayer.currentTime / audioPlayer.duration
    }
}
