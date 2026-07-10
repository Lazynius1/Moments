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
    let recordingTime: TimeInterval
    let recordingInteractionId: UUID?
    let voiceRecordingDraft: VoiceRecordingDraft?
    let isPreparingVoiceRecordingPreview: Bool
    let onSend: () -> Void
    let onStartVoiceRecording: (UUID, Bool) -> Void
    let onFinishVoiceRecording: (UUID, VoiceRecordingFinishAction) -> Void

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
        inputRow
    }

    private var inputRow: some View {
        HStack(alignment: .center, spacing: 10) {
            leadingControl
            composerSurface
            trailingControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: isVanishModeActive), value: isVanishModeActive)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: isVoiceRecordingLocked), value: isVoiceRecordingLocked)
    }

    private var composerSurface: some View {
        ZStack {
            if isRecordingVoice {
                VoiceRecordingHeldStatus(
                    isLocked: isVoiceRecordingLocked,
                    recordingTime: recordingTime,
                    adaptiveColors: adaptiveColors,
                    onCancel: cancelVoiceRecording
                )
            } else if let voiceRecordingDraft {
                VoiceRecordingDraftPreview(
                    draft: voiceRecordingDraft,
                    isPreparing: isPreparingVoiceRecordingPreview,
                    adaptiveColors: adaptiveColors
                )
            } else if isPreparingVoiceRecordingPreview {
                ProgressView()
                    .controlSize(.small)
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
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44)
        .momentsChromeGlass(in: inputFieldShape, interactive: !isVanishModeActive)
        .background {
            if isVanishModeActive {
                inputFieldShape
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
            }
        }
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
    }

    @ViewBuilder
    private var leadingControl: some View {
        if voiceRecordingDraft != nil || isPreparingVoiceRecordingPreview {
            circularGlassButton(systemName: "trash.fill", tint: .red, action: cancelVoiceRecording)
                .accessibilityLabel(Text("common.cancel"))
        } else if !isRecordingVoice && allowsAttachments {
            ChatAttachmentPlusButton(isMenuOpen: isMenuOpen, action: toggleAttachmentMenu)
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
        } else if allowsAttachments {
            ZStack {
                Color.clear
                    .momentsChromeGlass(in: Circle(), interactive: !isVanishModeActive)

                VoiceRecordingGestureButton(
                    tint: adaptiveColors.mediaIconColor,
                    isRecording: isRecordingVoice,
                    activeInteractionId: recordingInteractionId,
                    isLocked: $isVoiceRecordingLocked,
                    onStart: onStartVoiceRecording,
                    onFinish: onFinishVoiceRecording
                )
            }
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
            ZStack {
                Color.clear.momentsChromeGlass(in: Circle(), interactive: true)
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)
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

struct VoiceRecordingFloatingPauseButton: View {
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear
                    .momentsChromeGlass(in: Circle(), interactive: true)

                Image(systemName: "pause.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(Text("chat.voice.record.pause"))
    }
}

struct VoiceRecordingFloatingResumeButton: View {
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear
                    .momentsChromeGlass(in: Circle(), interactive: true)

                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(Text("chat.voice.record.resume"))
    }
}

struct VoiceRecordingAuroraCircleSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AuroraMeshLayer()
                .blur(radius: 10)
                .opacity(0.92)

            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.clear.interactive(), in: Circle())
            } else {
                Circle().fill(.ultraThinMaterial)
            }
        }
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(colorScheme == .dark ? 0.22 : 0.34), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }
}

private struct VoiceRecordingLockedSendButton: View {
    let action: () -> Void

    @ObservedObject private var recorder = AudioRecordingManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var smoothedLevel: CGFloat = 0

    private var auraScale: CGFloat {
        let minimum = 110.0 / 160.0
        let activity = reduceMotion ? smoothedLevel * 0.18 : smoothedLevel
        return minimum + activity * (1 - minimum)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                AuroraMeshLayer(speed: 0.65)
                    .frame(width: 160, height: 160)
                    .clipShape(Circle())
                    .blur(radius: 10)
                    .opacity(colorScheme == .dark ? 0.88 : 0.78)
                    .scaleEffect(auraScale)

                VoiceRecordingAuroraCircleSurface()
                    .frame(width: 110, height: 110)

                Image(systemName: "arrow.up")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 160, height: 160)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .accessibilityLabel(Text("notification.action.send"))
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
    }
}

private struct VoiceRecordingHeldStatus: View {
    let isLocked: Bool
    let recordingTime: TimeInterval
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
            }
        }
        .padding(.trailing, 46)
    }
}

private struct VoiceRecordingDraftPreview: View {
    let draft: VoiceRecordingDraft
    let isPreparing: Bool
    let adaptiveColors: AdaptiveColors

    @StateObject private var player = VoiceRecordingDraftPlayer()

    private var waveform: [Float] {
        ChatVoiceWaveformSamples.resampled(draft.waveform, count: 28)
    }

    var body: some View {
        HStack(spacing: 9) {
            if isPreparing || draft.recording == nil {
                ProgressView().controlSize(.small)
            } else {
                Button(action: player.togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(adaptiveColors.primary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            GeometryReader { proxy in
                VisualWaveformView(
                    levels: waveform,
                    color: adaptiveColors.timestampColor.opacity(0.45),
                    activeColor: adaptiveColors.accent,
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
                            player.seek(to: value.location.x / max(proxy.size.width, 1))
                        }
                )
            }
            .frame(height: 26)

            Text(player.displayTime(fallback: draft.duration))
                .font(.system(size: legacyPoppinsSize(11), weight: .medium, design: .monospaced))
                .foregroundStyle(adaptiveColors.timestampColor)
        }
        .onAppear { player.load(draft.recording?.data) }
        .onChange(of: draft.recording?.data.count) { _, _ in
            player.load(draft.recording?.data)
        }
        .onDisappear { player.stop() }
    }
}

private final class VoiceRecordingDraftPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    func load(_ data: Data?) {
        stop()
        guard let data else { return }
        audioPlayer = try? AVAudioPlayer(data: data)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()
    }

    func togglePlayback() {
        guard let audioPlayer else { return }
        if audioPlayer.isPlaying {
            audioPlayer.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            if audioPlayer.currentTime >= audioPlayer.duration {
                audioPlayer.currentTime = 0
            }
            guard audioPlayer.play() else { return }
            isPlaying = true
            startTimer()
        }
    }

    func seek(to fraction: Double) {
        guard let audioPlayer else { return }
        let clamped = min(1, max(0, fraction))
        audioPlayer.currentTime = audioPlayer.duration * clamped
        progress = clamped
    }

    func displayTime(fallback: TimeInterval) -> String {
        let currentTime = audioPlayer?.currentTime ?? 0
        let value = currentTime > 0 || isPlaying ? currentTime : fallback
        return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
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
            self.progress = audioPlayer.duration > 0 ? audioPlayer.currentTime / audioPlayer.duration : 0
            if !audioPlayer.isPlaying {
                self.isPlaying = false
                self.timer?.invalidate()
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        progress = 0
        timer?.invalidate()
        player.currentTime = 0
    }
}
