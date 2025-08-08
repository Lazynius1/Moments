import Foundation
import AVFoundation
import UIKit
import SwiftUI

// MARK: - Audio Recording Manager (TU CÓDIGO EXACTO)
class AudioRecordingManager: ObservableObject {
    static let shared = AudioRecordingManager()
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingSession: AVAudioSession?
    
    private init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        recordingSession = AVAudioSession.sharedInstance()
        
        do {
            try recordingSession?.setCategory(.playAndRecord, mode: .default)
            try recordingSession?.setActive(true)
        } catch {
            print("Error setting up audio session: \(error.localizedDescription)")
        }
    }
    
    func startRecording() {
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.m4a")
        
        // ✅ Configuración de ALTA CALIDAD como WhatsApp/Telegram
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48000,        // ✅ 48kHz (4x mejor que antes)
            AVNumberOfChannelsKey: 1,       // Mono (perfecto para voz)
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue, // ✅ Máxima calidad
            AVEncoderBitRateKey: 128000,    // ✅ 128 kbps (muy buena calidad)
            AVLinearPCMBitDepthKey: 16,     // ✅ 16-bit depth
            AVEncoderAudioQualityForVBRKey: AVAudioQuality.max.rawValue // ✅ VBR de máxima calidad
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            print("Started recording audio - HIGH QUALITY")
        } catch {
            print("Error starting audio recording: \(error.localizedDescription)")
        }
    }
    
    func stopRecording(completion: @escaping (Data?) -> Void) {
        audioRecorder?.stop()
        
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.m4a")
        
        do {
            let audioData = try Data(contentsOf: audioFilename)
            completion(audioData)
            print("Audio recording stopped and data retrieved")
        } catch {
            print("Error retrieving audio data: \(error.localizedDescription)")
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

// MARK: - Audio Message con Proximidad Simple
struct GlassmorphicAudioMessage: View {
    let audioUrl: String?
    let duration: Double
    let isCurrentUser: Bool
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var timer: Timer?
    @State private var isAudioAvailable = true
    @State private var isCheckingAvailability = true
    @State private var showErrorMessage = false
    
    @StateObject private var proximityManager = SimpleProximityManager()

    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            Button(action: togglePlayback) {
                Group {
                    if isCheckingAvailability {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: getPlayButtonIcon())
                            .font(.system(size: 32))
                    }
                }
                .foregroundColor(isAudioAvailable ? .white : .white.opacity(0.5))
                .frame(width: 32, height: 32)
            }
            .disabled(!isAudioAvailable || isCheckingAvailability)
            
            VStack(alignment: .leading, spacing: 4) {
                if isCheckingAvailability {
                    // Loading state
                    HStack {
                        ForEach(0..<20, id: \.self) { index in
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 3, height: CGFloat.random(in: 8...24))
                        }
                    }
                    .frame(height: 24)
                    
                    Text("Cargando...")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        
                } else if isAudioAvailable {
                    // Available audio
                    HStack {
                        ForEach(0..<20, id: \.self) { index in
                            Rectangle()
                                .fill(Color.white.opacity(currentTime / duration > Double(index) / 20 ? 0.8 : 0.3))
                                .frame(width: 3, height: CGFloat.random(in: 8...24))
                                .animation(.easeInOut(duration: 0.1), value: currentTime)
                        }
                    }
                    .frame(height: 24)
                    
                    // Duration (sin icono de proximidad)
                    Text(formatDuration(isPlaying ? currentTime : duration))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    // Error state
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        
                        Text("Audio no disponible")
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Text("Este mensaje fue eliminado")
                        .font(.custom("Poppins-Regular", size: 10))
                        .foregroundColor(.white.opacity(0.5))
                        .italic()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Group {
                if isCurrentUser {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(hex: "00A896").opacity(getBackgroundOpacity()))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(getBackgroundOpacity()))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                        )
                }
            }
        )
        .onAppear {
            checkAudioAvailability()
        }
        .onDisappear {
            stopPlayback()
        }
        .onChange(of: proximityManager.isNearEar) { isNear in
            // Cambiar ruta cuando cambia proximidad
            guard isPlaying else { return }
            switchAudioRoute(toEarpiece: isNear)
        }
        .alert("Audio No Disponible", isPresented: $showErrorMessage) {
            Button("OK") { }
        } message: {
            Text("Este mensaje de audio ha sido eliminado y ya no está disponible para reproducir.")
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
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self.isAudioAvailable = false
                    self.showErrorMessage = true
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                DispatchQueue.main.async {
                    self.isAudioAvailable = false
                    self.showErrorMessage = true
                }
                return
            }
            
            DispatchQueue.main.async {
                do {
                    // Crear el player
                    self.audioPlayer = try AVAudioPlayer(data: data)
                    self.audioPlayer?.play()
                    self.isPlaying = true
                    
                    // Iniciar proximidad
                    self.proximityManager.startMonitoring()
                    
                    // Empezar en altavoz
                    self.switchAudioRoute(toEarpiece: false)
                    
                    AnalyticsService.shared.trackInteraction("audio_message_played")
                    
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
        }.resume()
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
