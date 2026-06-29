import Foundation
import AVFoundation
import UIKit
import SwiftUI

// MARK: - Audio Recording Manager
final class AudioRecordingManager: NSObject, ObservableObject {
    static let shared = AudioRecordingManager()

    @Published var audioPower: Float = 0.0

    private var powerTimer: Timer?
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var stopCompletion: ((Data?) -> Void)?

    private override init() {
        super.init()
    }

    /// Si el micrófono ya está autorizado, `completion(true)` se llama sin mostrar diálogo.
    func startRecording(completion: @escaping (Bool) -> Void) {
        requestMicrophonePermission { [weak self] granted in
            guard let self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            DispatchQueue.main.async {
                completion(granted ? self.beginRecording() : false)
            }
        }
    }

    func stopRecording(completion: @escaping (Data?) -> Void) {
        powerTimer?.invalidate()
        powerTimer = nil
        audioPower = 0.0

        guard let recorder = audioRecorder, recorder.isRecording else {
            completion(nil)
            return
        }

        stopCompletion = completion
        recorder.stop()
    }

    // MARK: - Private

    private func requestMicrophonePermission(_ completion: @escaping (Bool) -> Void) {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        @unknown default:
            completion(false)
        }
    }

    private func beginRecording() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            return false
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat_voice_\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: fileURL)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64_000
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                return false
            }
            audioRecorder = recorder
            recordingURL = fileURL
            startPowerMonitoring()
            return true
        } catch {
            return false
        }
    }

    private func startPowerMonitoring() {
        powerTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder, recorder.isRecording else { return }
            recorder.updateMeters()
            let decibels = recorder.averagePower(forChannel: 0)
            let level = self.normalizedPowerLevel(fromDecibels: decibels)
            DispatchQueue.main.async {
                self.audioPower = Float(level)
            }
        }
    }

    private func normalizedPowerLevel(fromDecibels decibels: Float) -> Float {
        if decibels < -60.0 { return 0.0 }
        if decibels >= 0.0 { return 1.0 }
        return (decibels + 60.0) / 60.0
    }

    private func deliverRecordingResult(success: Bool) {
        let completion = stopCompletion
        stopCompletion = nil
        audioRecorder = nil

        guard success, let url = recordingURL else {
            recordingURL = nil
            completion?(nil)
            return
        }

        defer { recordingURL = nil }
        let data = try? Data(contentsOf: url)
        if let data, data.count > 512 {
            completion?(data)
        } else {
            completion?(nil)
        }
        try? FileManager.default.removeItem(at: url)
    }
}

extension AudioRecordingManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        deliverRecordingResult(success: flag)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        deliverRecordingResult(success: false)
    }
}

// MARK: - Simple Proximity Manager (Limpio)
class SimpleProximityManager: ObservableObject {
    @Published var isNearEar = false
    private var wasProximityEnabled = false
    
    func startMonitoring() {
        wasProximityEnabled = UIDevice.current.isProximityMonitoringEnabled
        UIDevice.current.isProximityMonitoringEnabled = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(proximityChanged),
            name: UIDevice.proximityStateDidChangeNotification,
            object: nil
        )
    }
    
    func stopMonitoring() {
        UIDevice.current.isProximityMonitoringEnabled = wasProximityEnabled
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func proximityChanged() {
        isNearEar = UIDevice.current.proximityState
    }
    
    deinit {
        stopMonitoring()
    }
}

// MARK: - Voice message spacing

enum VoiceMessageLayout {
    static let playButtonSize: CGFloat = 38
    static let playIconSize: CGFloat = 26
    static let waveformHeight: CGFloat = 30
    static let barWidth: CGFloat = 3.5
    static let barSpacing: CGFloat = 2.5
    static let outerSpacing: CGFloat = 10
    static let waveformLeadingInset: CGFloat = 12
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 15
    static let bubbleWidthFraction: CGFloat = 0.75
    static let trailingGapMinLength: CGFloat = 10
    static let timeLabelWidth: CGFloat = 36
    static let speedControlWidth: CGFloat = 34

    static var bubbleWidth: CGFloat {
        UIScreen.main.bounds.width * bubbleWidthFraction
    }

    static func availableWaveformWidth(includesSpeedControl: Bool) -> CGFloat {
        let innerWidth = bubbleWidth - horizontalPadding * 2
        let trailingBlock = timeLabelWidth
            + (includesSpeedControl ? outerSpacing + speedControlWidth : 0)
        let leadingBlock = playButtonSize + outerSpacing + waveformLeadingInset
        return max(
            96,
            innerWidth - leadingBlock - trailingBlock - trailingGapMinLength
        )
    }

    static func waveformBarCount(for trackWidth: CGFloat) -> Int {
        let unit = barWidth + barSpacing
        guard unit > 0 else { return 32 }
        return max(24, min(50, Int((trackWidth / unit).rounded(.down))))
    }

    static func waveformTrackWidth(includesSpeedControl: Bool) -> CGFloat {
        let target = availableWaveformWidth(includesSpeedControl: includesSpeedControl)
        let barCount = waveformBarCount(for: target)
        return CGFloat(barCount) * barWidth + CGFloat(max(barCount - 1, 0)) * barSpacing
    }
}

enum ChatVoiceWaveformGenerator {
    static func levels(seed: String, count: Int) -> [Float] {
        guard count > 0 else { return [] }
        var hash = seed.utf8.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1) }
        return (0..<count).map { index in
            hash = hash &* 1_103_515_245 &+ 12_345 &+ UInt64(index)
            let normalized = Float(hash % 10_000) / 10_000
            return 0.2 + normalized * 0.6
        }
    }
}

// MARK: - Single active voice playback (como WhatsApp / Instagram)

@MainActor
final class ChatAudioPlaybackCenter {
    static let shared = ChatAudioPlaybackCenter()

    private(set) var activeMessageId: String?
    private var stopHandler: (() -> Void)?

    private init() {}

    func activate(messageId: String, stopOthers: @escaping () -> Void) {
        if activeMessageId != messageId {
            stopHandler?()
        }
        activeMessageId = messageId
        stopHandler = stopOthers
    }

    func deactivate(messageId: String) {
        guard activeMessageId == messageId else { return }
        activeMessageId = nil
        stopHandler = nil
    }

    func stopCurrent() {
        stopHandler?()
        activeMessageId = nil
        stopHandler = nil
    }
}

// MARK: - Waveform Visualization Components

struct VisualWaveformView: View {
    let levels: [Float]
    let color: Color
    let activeColor: Color
    let progress: Double
    var height: CGFloat = VoiceMessageLayout.waveformHeight
    var barWidth: CGFloat = VoiceMessageLayout.barWidth
    var spacing: CGFloat = VoiceMessageLayout.barSpacing

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<levels.count, id: \.self) { index in
                let level = levels[index]
                let isActive = Double(index) / Double(levels.count) <= progress

                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                    .fill(isActive ? activeColor : color)
                    .frame(width: barWidth, height: max(6, CGFloat(level) * height))
                    .animation(.easeInOut(duration: 0.1), value: isActive)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: level)
            }
        }
    }
}

struct LiveWaveformView: View {
    @ObservedObject var manager = AudioRecordingManager.shared
    @State private var levels: [Float] = Array(repeating: 0.1, count: 20)
    let color: Color
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<levels.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: max(4, CGFloat(levels[index]) * 35))
            }
        }
        .onReceive(manager.$audioPower) { power in
            withAnimation(.linear(duration: 0.05)) {
                levels.removeFirst()
                levels.append(power)
            }
        }
    }
}

// MARK: - Audio Message con Proximidad Simple
struct GlassmorphicAudioMessage: View {
    let messageId: String
    let audioUrl: String?
    let duration: Double
    let isCurrentUser: Bool
    let isSending: Bool
    let progress: Double?
    let adaptiveColors: AdaptiveColors

    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playbackFileURL: URL?
    @State private var timer: Timer?
    @State private var isAudioAvailable = true
    @State private var isCheckingAvailability = true
    @State private var showErrorMessage = false
    @State private var playbackRate: Float = 1.0
    @State private var isScrubbing = false
    @State private var scrubFraction: Double?
    @State private var wasPlayingBeforeScrub = false
    @State private var waveformLevels: [Float] = ChatVoiceWaveformGenerator.levels(
        seed: "voice",
        count: VoiceMessageLayout.waveformBarCount(
            for: VoiceMessageLayout.availableWaveformWidth(includesSpeedControl: true)
        )
    )

    @StateObject private var proximityManager = SimpleProximityManager()
    @Environment(\.colorScheme) var colorScheme

    /// Tuyos: burbuja invertida (#FAF9F6 / #0B1215). Del otro: glass como el resto del chat.
    private var contentColor: Color {
        if isCurrentUser {
            return colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
        }
        return adaptiveColors.messageTextColor
    }

    private var waveformInactiveColor: Color {
        if isCurrentUser {
            return contentColor.opacity(colorScheme == .dark ? 0.22 : 0.28)
        }
        return adaptiveColors.primary.opacity(colorScheme == .dark ? 0.28 : 0.22)
    }

    private var durationLabelColor: Color {
        if isCurrentUser {
            return contentColor.opacity(0.9)
        }
        return adaptiveColors.timestampColor
    }

    private var bubbleStrokeColor: Color {
        if isCurrentUser {
            return contentColor.opacity(0.12)
        }
        return adaptiveColors.messageBubbleStroke
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isCurrentUser {
            RoundedRectangle(cornerRadius: 18)
                .fill(colorScheme == .dark ? Color(hex: "FAF9F6") : Color(hex: "0B1215"))
        } else {
            RoundedRectangle(cornerRadius: 18)
                .fill(adaptiveColors.messageBubbleBackground)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                )
        }
    }

    var body: some View {
        HStack(spacing: VoiceMessageLayout.outerSpacing) {
            playButton

            if isCheckingAvailability {
                VStack(alignment: .leading, spacing: 4) {
                    loadingWaveformPlaceholder
                    Text(NSLocalizedString("chat.loading", comment: "Loading audio message"))
                        .font(.system(size: legacyPoppinsSize(11)))
                        .foregroundColor(durationLabelColor)
                }
                Spacer(minLength: VoiceMessageLayout.trailingGapMinLength)
            } else if isAudioAvailable {
                scrubbableWaveform
                    .frame(
                        width: VoiceMessageLayout.waveformTrackWidth(includesSpeedControl: !isSending),
                        height: VoiceMessageLayout.waveformHeight
                    )
                    .padding(.leading, VoiceMessageLayout.waveformLeadingInset)

                timeLabel
                    .padding(.leading, VoiceMessageLayout.trailingGapMinLength)

                if !isSending {
                    speedButton
                }
            } else {
                unavailableRow
                Spacer(minLength: VoiceMessageLayout.trailingGapMinLength)
            }
        }
        .padding(.horizontal, VoiceMessageLayout.horizontalPadding)
        .padding(.vertical, VoiceMessageLayout.verticalPadding)
        .frame(width: VoiceMessageLayout.bubbleWidth, alignment: .leading)
        .background(bubbleBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(bubbleStrokeColor, lineWidth: 0.5)
        )
        .onAppear {
            refreshWaveformLevels()
            checkAudioAvailability()
        }
        .onChange(of: audioUrl) { _, _ in
            refreshWaveformLevels()
            checkAudioAvailability()
        }
        .onChange(of: isSending) { _, _ in
            refreshWaveformLevels()
            checkAudioAvailability()
        }
        .onDisappear {
            if ChatAudioPlaybackCenter.shared.activeMessageId == messageId {
                ChatAudioPlaybackCenter.shared.deactivate(messageId: messageId)
            }
            stopPlayback(resetTime: false)
        }
        .onChange(of: proximityManager.isNearEar) { _, isNear in
            guard isPlaying else { return }
            switchAudioRoute(toEarpiece: isNear)
        }
    }

    private var playButton: some View {
        Button(action: togglePlayback) {
            ZStack {
                if isCheckingAvailability {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(contentColor)
                } else {
                    Image(systemName: getPlayButtonIcon())
                        .font(.system(size: VoiceMessageLayout.playIconSize, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                }

                if isSending, let uploadProgress = progress {
                    MediaProgressRing(progress: uploadProgress, size: 34, lineWidth: 2)
                }
            }
            .foregroundColor(contentColor)
            .frame(width: VoiceMessageLayout.playButtonSize, height: VoiceMessageLayout.playButtonSize)
        }
        .disabled(!isAudioAvailable || isCheckingAvailability)
    }

    private var loadingWaveformPlaceholder: some View {
        let trackWidth = VoiceMessageLayout.waveformTrackWidth(includesSpeedControl: true)
        let barCount = VoiceMessageLayout.waveformBarCount(for: trackWidth)

        return HStack(spacing: VoiceMessageLayout.barSpacing) {
            ForEach(0..<barCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: VoiceMessageLayout.barWidth / 2, style: .continuous)
                    .fill(waveformInactiveColor)
                    .frame(width: VoiceMessageLayout.barWidth, height: 12)
            }
        }
        .frame(width: trackWidth, height: 24)
        .padding(.leading, VoiceMessageLayout.waveformLeadingInset)
    }

    private var scrubbableWaveform: some View {
        let trackWidth = VoiceMessageLayout.waveformTrackWidth(includesSpeedControl: !isSending)

        return VisualWaveformView(
            levels: waveformLevels,
            color: waveformInactiveColor,
            activeColor: contentColor,
            progress: displayedProgress
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .local)
                .onChanged { value in
                    if !isScrubbing {
                        isScrubbing = true
                        wasPlayingBeforeScrub = isPlaying
                        if isPlaying {
                            audioPlayer?.pause()
                            isPlaying = false
                            timer?.invalidate()
                        }
                        HapticManager.shared.lightImpact()
                    }

                    let width = trackWidth
                    let fraction = max(0, min(1, value.location.x / width))
                    scrubFraction = fraction
                    seekToFraction(fraction)
                }
                .onEnded { _ in
                    isScrubbing = false
                    scrubFraction = nil
                    if wasPlayingBeforeScrub {
                        resumeAfterScrub()
                    }
                }
        )
        .accessibilityLabel(Text("chat.audio.scrub.accessibility"))
    }

    private var unavailableRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(.orange)

            Text(NSLocalizedString("chat.audio.unavailable", comment: "Audio message unavailable"))
                .font(.system(size: legacyPoppinsSize(12)))
                .foregroundColor(durationLabelColor)
        }
    }

    @ViewBuilder
    private var timeLabel: some View {
        Text(formatDuration(displayedTimeSeconds))
            .font(.system(size: legacyPoppinsSize(11), weight: .medium))
            .monospacedDigit()
            .foregroundColor(durationLabelColor)
            .frame(minWidth: 34, alignment: .trailing)
            .accessibilityLabel(
                Text(
                    String(
                        format: NSLocalizedString(
                            "chat.audio.duration.accessibility",
                            comment: "Voice message duration for accessibility"
                        ),
                        formatDuration(displayedTimeSeconds)
                    )
                )
            )
    }

    @ViewBuilder
    private var speedButton: some View {
        Button(action: cyclePlaybackRate) {
            Text(speedLabel)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(contentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(contentColor.opacity(colorScheme == .dark ? 0.15 : 0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var speedLabel: String {
        switch playbackRate {
        case 1.5: return "1.5×"
        case 2.0: return "2×"
        default: return "1×"
        }
    }

    private func refreshWaveformLevels() {
        let seed = audioUrl ?? messageId
        let includesSpeed = isAudioAvailable && !isCheckingAvailability && !isSending
        let trackWidth = VoiceMessageLayout.waveformTrackWidth(includesSpeedControl: includesSpeed)
        waveformLevels = ChatVoiceWaveformGenerator.levels(
            seed: seed,
            count: VoiceMessageLayout.waveformBarCount(for: trackWidth)
        )
    }
    
    private func configurePlaybackSession(speaker: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if speaker {
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [])
                try session.setActive(true)
                try session.overrideOutputAudioPort(.none)
            }
        } catch {
        }
    }

    /// Cambia altavoz / auricular durante la reproducción (usa el archivo, no `player.data`).
    private func switchAudioRoute(toEarpiece: Bool) {
        guard let player = audioPlayer, player.isPlaying, let url = playbackFileURL else { return }

        let currentTime = player.currentTime
        player.stop()
        audioPlayer = nil

        configurePlaybackSession(speaker: !toEarpiece)

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.enableRate = true
            newPlayer.rate = playbackRate
            newPlayer.currentTime = currentTime
            newPlayer.prepareToPlay()
            guard newPlayer.play() else { return }
            audioPlayer = newPlayer
            isPlaying = true
        } catch {
            isAudioAvailable = false
        }
    }
    
    private func getPlayButtonIcon() -> String {
        if !isAudioAvailable {
            return "exclamationmark.triangle.fill"
        }
        return isPlaying ? "pause.fill" : "play.fill"
    }
    
    private func checkAudioAvailability() {
        if isSending {
            isAudioAvailable = true
            isCheckingAvailability = false
            return
        }

        guard let audioUrl = audioUrl, let url = URL(string: audioUrl) else {
            isAudioAvailable = false
            isCheckingAvailability = false
            return
        }

        if url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
            isAudioAvailable = true
            isCheckingAvailability = false
            return
        }

        if let cachedURL = PersistentAudioCache.shared.cachedURL(for: url.absoluteString),
           FileManager.default.fileExists(atPath: cachedURL.path) {
            isAudioAvailable = true
            isCheckingAvailability = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10.0
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                self.isCheckingAvailability = false
                
                if error != nil {
                    self.isAudioAvailable = false
                } else if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        self.isAudioAvailable = true
                    } else {
                        self.isAudioAvailable = false
                    }
                } else {
                    self.isAudioAvailable = false
                }
            }
        }.resume()
    }
    
    private func togglePlayback() {
        guard isAudioAvailable else {
            showErrorMessage = true
            return
        }

        if isPlaying {
            pausePlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        if let player = audioPlayer, playbackFileURL != nil {
            ChatAudioPlaybackCenter.shared.activate(messageId: messageId) {
                self.pausePlayback(notifyCenter: false)
            }
            player.enableRate = true
            player.rate = playbackRate
            player.currentTime = currentTime
            guard player.play() else {
                isAudioAvailable = false
                return
            }
            isPlaying = true
            proximityManager.startMonitoring()
            startProgressTimer()
            return
        }

        guard let audioUrl = audioUrl, let url = URL(string: audioUrl) else {
            isAudioAvailable = false
            return
        }

        Task {
            do {
                let playbackURL: URL
                if url.isFileURL {
                    playbackURL = url
                } else {
                    playbackURL = try await PersistentAudioCache.shared.localURL(for: url)
                }

                await MainActor.run {
                    do {
                        self.playbackFileURL = playbackURL
                        self.configurePlaybackSession(speaker: true)

                        let player = try AVAudioPlayer(contentsOf: playbackURL)
                        player.enableRate = true
                        player.rate = self.playbackRate
                        if self.currentTime > 0 && self.currentTime < self.duration {
                            player.currentTime = self.currentTime
                        }
                        player.prepareToPlay()
                        guard player.play() else {
                            self.isAudioAvailable = false
                            return
                        }
                        self.audioPlayer = player
                        self.isPlaying = true
                        self.proximityManager.startMonitoring()
                        ChatAudioPlaybackCenter.shared.activate(messageId: self.messageId) {
                            self.pausePlayback(notifyCenter: false)
                        }
                        self.startProgressTimer()
                    } catch {
                        self.isAudioAvailable = false
                        self.showErrorMessage = true
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAudioAvailable = false
                    self.showErrorMessage = true
                }
            }
        }
    }

    private func resumeAfterScrub() {
        guard isAudioAvailable, wasPlayingBeforeScrub else { return }

        if let player = audioPlayer {
            ChatAudioPlaybackCenter.shared.activate(messageId: messageId) {
                self.pausePlayback(notifyCenter: false)
            }
            player.enableRate = true
            player.rate = playbackRate
            guard player.play() else { return }
            isPlaying = true
            proximityManager.startMonitoring()
            startProgressTimer()
        } else {
            startPlayback()
        }
    }

    private func startProgressTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let player = self.audioPlayer else { return }
            self.currentTime = player.currentTime
            if !player.isPlaying {
                self.stopPlayback(resetTime: true)
            }
        }
    }

    private func pausePlayback(notifyCenter: Bool = true) {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
        proximityManager.stopMonitoring()
        if notifyCenter {
            ChatAudioPlaybackCenter.shared.deactivate(messageId: messageId)
        }
    }

    private func stopPlayback(resetTime: Bool = true) {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackFileURL = nil
        isPlaying = false
        if resetTime {
            currentTime = 0
        }
        timer?.invalidate()
        timer = nil
        proximityManager.stopMonitoring()
        if ChatAudioPlaybackCenter.shared.activeMessageId == messageId {
            ChatAudioPlaybackCenter.shared.deactivate(messageId: messageId)
        }
    }
    
    private func cyclePlaybackRate() {
        if playbackRate == 1.0 {
            playbackRate = 1.5
        } else if playbackRate == 1.5 {
            playbackRate = 2.0
        } else {
            playbackRate = 1.0
        }
        audioPlayer?.rate = playbackRate
    }

    private func seekToFraction(_ fraction: Double) {
        let targetTime = fraction * duration
        currentTime = max(0, min(duration, targetTime))
        if let player = audioPlayer {
            player.currentTime = currentTime
        }
    }

    private var playbackProgress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    private var displayedProgress: Double {
        if let scrubFraction {
            return scrubFraction
        }
        return playbackProgress
    }

    private var displayedTimeSeconds: Double {
        guard duration > 0 else { return 0 }
        if isScrubbing {
            return currentTime
        }
        if isPlaying || currentTime > 0.01 {
            return max(0, duration - currentTime)
        }
        return duration
    }

    private func formatDuration(_ time: Double) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
