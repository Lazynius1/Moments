import Foundation
import AVFoundation
import UIKit
import SwiftUI

// MARK: - Audio Recording Manager (TU CÓDIGO EXACTO)
class AudioRecordingManager: ObservableObject {
    static let shared = AudioRecordingManager()
    
    @Published var audioPower: Float = 0.0
    private var powerTimer: Timer?
    private var audioRecorder: AVAudioRecorder?
    private var recordingSession: AVAudioSession?
    
    private init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        self.recordingSession = session
        
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }
    
    func startRecording() {
        setupAudioSession()

        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.m4a")
        
        // ✅ Configuración de ALTA CALIDAD como WhatsApp/Telegram
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,        // ✅ CD Quality (standard for voice)
            AVNumberOfChannelsKey: 1,       // Mono
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64000,     // 64kbps is perfect for AAC mono voice
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.isMeteringEnabled = true // ✅ ENABLE METERING for waveforms
            audioRecorder?.record()
            
            // Start power monitoring
            startPowerMonitoring()
        } catch {
            print("Could not start recording: \(error.localizedDescription)")
        }
    }
    
    private func startPowerMonitoring() {
        powerTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder, recorder.isRecording else { return }
            recorder.updateMeters()
            
            // Convert decibels to power 0.0 - 1.0 range
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
    
    func stopRecording(completion: @escaping (Data?) -> Void) {
        powerTimer?.invalidate()
        powerTimer = nil
        audioPower = 0.0
        
        audioRecorder?.stop()
        
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.m4a")
        
        do {
            let audioData = try Data(contentsOf: audioFilename)
            completion(audioData)
        } catch {
            completion(nil)
        }
        
        audioRecorder = nil
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
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
    @State private var timer: Timer?
    @State private var isAudioAvailable = true
    @State private var isCheckingAvailability = true
    @State private var showErrorMessage = false
    
    // Generar niveles "estáticos" pero consistentes para el waveform
    @State private var waveformLevels: [Float] = (0..<25).map { _ in Float.random(in: 0.2...0.8) }
    
    @StateObject private var proximityManager = SimpleProximityManager()
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            Button(action: togglePlayback) {
                ZStack {
                    if isCheckingAvailability {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(isCurrentUser ? .white : adaptiveColors.primary)
                    } else {
                        Image(systemName: getPlayButtonIcon())
                            .font(.system(size: 28))
                            .symbolRenderingMode(.hierarchical)
                    }
                    
                    if isSending, let uploadProgress = progress {
                        MediaProgressRing(progress: uploadProgress, size: 36, lineWidth: 2)
                    }
                }
                .foregroundColor(isCurrentUser ? .white : adaptiveColors.primary)
                .frame(width: 36, height: 36)
            }
            .disabled(!isAudioAvailable || isCheckingAvailability)
            
            VStack(alignment: .leading, spacing: 4) {
                if isCheckingAvailability {
                    HStack(spacing: 3) {
                        ForEach(0..<20, id: \.self) { _ in
                            Rectangle()
                                .fill(isCurrentUser ? Color.white.opacity(0.3) : adaptiveColors.primary.opacity(0.2))
                                .frame(width: 3, height: 12)
                        }
                    }
                    .frame(height: 24)
                    
                    Text("chat.loading")
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(isCurrentUser ? .white.opacity(0.7) : adaptiveColors.messageTextColor.opacity(0.5))
                        
                } else if isAudioAvailable {
                    VisualWaveformView(
                        levels: waveformLevels,
                        color: isCurrentUser ? Color.white.opacity(0.3) : adaptiveColors.primary.opacity(0.2),
                        activeColor: isCurrentUser ? .white : adaptiveColors.primary,
                        progress: currentTime / (duration > 0 ? duration : 1)
                    )
                    .frame(height: 30)
                    
                    HStack {
                        Text(formatDuration(isPlaying ? currentTime : duration))
                        Spacer()
                        if !isPlaying && duration > 0 {
                            Image(systemName: "waveform")
                                .font(.system(size: 10))
                        }
                    }
                    .font(.custom("Poppins-Medium", size: 11))
                    .foregroundColor(isCurrentUser ? .white.opacity(0.8) : adaptiveColors.messageTextColor.opacity(0.6))
                    
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        
                        Text("chat.audio.unavailable")
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(isCurrentUser ? .white.opacity(0.7) : adaptiveColors.messageTextColor.opacity(0.5))
                    }
                }
            }
            .frame(width: 140) // Fixed width for waveform consistency
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                if isCurrentUser {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(
                            colors: [Color(hex: "4F46E5"), Color(hex: "3B82F6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                } else {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(adaptiveColors.messageBubbleBackground)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(.ultraThinMaterial)
                        )
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isCurrentUser ? Color.white.opacity(0.2) : adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
        )
        .onAppear {
            checkAudioAvailability()
            // Consistencia visual: si tenemos una duración guardada, generar un waveform basado en el ID del mensaje si fuera posible, si no random
        }
        .onDisappear {
            stopPlayback()
        }
        .onChange(of: proximityManager.isNearEar) { isNear in
            guard isPlaying else { return }
            switchAudioRoute(toEarpiece: isNear)
        }
    }
    
    // Función para cambiar audio (recreando el player)
    private func switchAudioRoute(toEarpiece: Bool) {
        guard let player = audioPlayer, player.isPlaying else { return }
        
        // Guardar estado actual
        let currentTime = player.currentTime
        let audioData = player.data
        
        // Parar y destruir el player completamente
        player.stop()
        audioPlayer = nil
        
        // Cambiar la configuración de audio
        do {
            let session = AVAudioSession.sharedInstance()
            
            if toEarpiece {
                // Auricular: configurar para earpiece
                try session.setCategory(.playAndRecord, mode: .voiceChat)
                try session.overrideOutputAudioPort(.none)
            } else {
                // Altavoz: configurar para speaker
                try session.setCategory(.playback, mode: .default)
                try session.overrideOutputAudioPort(.speaker)
            }
            
            // Recrear el player con la nueva configuración
            if let audioData = audioData {
                audioPlayer = try AVAudioPlayer(data: audioData)
                audioPlayer?.currentTime = currentTime
                audioPlayer?.play()
            }
            
        } catch {
            // Si falla, recrear con configuración básica
            if let audioData = audioData {
                do {
                    audioPlayer = try AVAudioPlayer(data: audioData)
                    audioPlayer?.currentTime = currentTime
                    audioPlayer?.play()
                } catch {
                    // Error silencioso
                }
            }
        }
    }
    
    // Todas tus funciones exactas
    private func getBackgroundOpacity() -> Double {
        if isCheckingAvailability {
            return isCurrentUser ? 0.6 : 0.10
        }
        return isAudioAvailable ? (isCurrentUser ? 0.8 : 0.15) : (isCurrentUser ? 0.5 : 0.08)
    }
    
    private func getPlayButtonIcon() -> String {
        if !isAudioAvailable {
            return "exclamationmark.circle.fill"
        }
        return isPlaying ? "pause.circle.fill" : "play.circle.fill"
    }
    
    private func checkAudioAvailability() {
        guard let audioUrl = audioUrl, let url = URL(string: audioUrl) else {
            isAudioAvailable = false
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
                
                if let error = error {
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
                        self.audioPlayer = try AVAudioPlayer(contentsOf: playbackURL)
                        self.audioPlayer?.play()
                        self.isPlaying = true

                        self.proximityManager.startMonitoring()
                        self.switchAudioRoute(toEarpiece: false)

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
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
        timer = nil
        proximityManager.stopMonitoring()
    }
    
    private func formatDuration(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
