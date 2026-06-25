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

// MARK: - Waveform Visualization Components
struct VisualWaveformView: View {
    let levels: [Float]
    let color: Color
    let activeColor: Color
    let progress: Double
    var height: CGFloat = 30
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<levels.count, id: \.self) { index in
                let level = levels[index]
                let isActive = Double(index) / Double(levels.count) <= progress
                
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isActive ? activeColor : color)
                    .frame(width: 3, height: max(6, CGFloat(level) * height))
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
    let audioUrl: String?
    let duration: Double
    let isCurrentUser: Bool
    let isSending: Bool
    let progress: Double?
    let adaptiveColors: AdaptiveColors // ✅ Pass adaptive colors
    
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playbackFileURL: URL?
    @State private var timer: Timer?
    @State private var isAudioAvailable = true
    @State private var isCheckingAvailability = true
    @State private var showErrorMessage = false
    
    // Generar niveles "estáticos" pero consistentes para el waveform
    @State private var waveformLevels: [Float] = (0..<25).map { _ in Float.random(in: 0.2...0.8) }
    
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
        HStack(spacing: 12) {
            // Play/Pause button
            Button(action: togglePlayback) {
                ZStack {
                    if isCheckingAvailability {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(contentColor)
                    } else {
                        Image(systemName: getPlayButtonIcon())
                            .font(.system(size: 26, weight: .semibold))
                            .symbolRenderingMode(.monochrome)
                    }
                    
                    if isSending, let uploadProgress = progress {
                        MediaProgressRing(progress: uploadProgress, size: 34, lineWidth: 2)
                    }
                }
                .foregroundColor(contentColor)
                .frame(width: 36, height: 36)
            }
            .disabled(!isAudioAvailable || isCheckingAvailability)
            
            VStack(alignment: .leading, spacing: 4) {
                if isCheckingAvailability {
                    HStack(spacing: 3) {
                        ForEach(0..<20, id: \.self) { _ in
                            Rectangle()
                                .fill(waveformInactiveColor)
                                .frame(width: 3, height: 12)
                        }
                    }
                    .frame(height: 24)
                    
                    Text(NSLocalizedString("chat.loading", comment: "Loading audio message"))
                        .font(.system(size: legacyPoppinsSize(11)))
                        .foregroundColor(durationLabelColor)
                        
                } else if isAudioAvailable {
                    HStack(alignment: .center, spacing: 8) {
                        VisualWaveformView(
                            levels: waveformLevels,
                            color: waveformInactiveColor,
                            activeColor: contentColor,
                            progress: playbackProgress
                        )
                        .frame(height: 30)
                        .frame(maxWidth: .infinity)

                        Text(formatDuration(displayedDurationSeconds))
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
                                        formatDuration(displayedDurationSeconds)
                                    )
                                )
                            )
                    }
                    
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        
                        Text(NSLocalizedString("chat.audio.unavailable", comment: "Audio message unavailable"))
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundColor(durationLabelColor)
                    }
                }
            }
            .frame(minWidth: 168, maxWidth: 220)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bubbleBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(bubbleStrokeColor, lineWidth: 0.5)
        )
        .onAppear {
            checkAudioAvailability()
        }
        .onChange(of: audioUrl) { _, _ in
            checkAudioAvailability()
        }
        .onChange(of: isSending) { _, _ in
            checkAudioAvailability()
        }
        .onDisappear {
            stopPlayback()
        }
        .onChange(of: proximityManager.isNearEar) { _, isNear in
            guard isPlaying else { return }
            switchAudioRoute(toEarpiece: isNear)
        }
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
                        player.prepareToPlay()
                        guard player.play() else {
                            self.isAudioAvailable = false
                            return
                        }
                        self.audioPlayer = player
                        self.isPlaying = true
                        self.proximityManager.startMonitoring()

                        self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                            if let player = self.audioPlayer {
                                self.currentTime = player.currentTime
                                if !player.isPlaying {
                                    self.stopPlayback()
                                }
                            }
                        }
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
    
    private func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
        proximityManager.stopMonitoring()
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackFileURL = nil
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
        timer = nil
        proximityManager.stopMonitoring()
    }
    
    private var playbackProgress: Double {
        guard duration > 0 else { return 0 }
        if isPlaying { return min(1, currentTime / duration) }
        return 0
    }

    private var displayedDurationSeconds: Double {
        guard duration > 0 else { return 0 }
        if isPlaying {
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
