import AVFoundation
import SwiftUI
import UIKit

// MARK: - Vista de cámara para selfie
struct SelfieCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingImagePicker = false
    let onImageCaptured: (UIImage) -> Void

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()

                Text("stickerview.selfie")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("stickerview.tapForFrontCamera")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding()

                Button(action: {
                    showingImagePicker = true
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)

                        Image(systemName: "camera.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                    }
                }
                .padding()

                Spacer()
            }
            .background(
                LinearGradient(
                    colors: [Color.black, Color.gray.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .navigationInteractivePopEnabled()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("stickerview.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(sourceType: .camera, cameraDevice: .front) { image in
                onImageCaptured(image)
                dismiss()
            }
        }
    }
}

// MARK: - Image picker wrapper
struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let cameraDevice: UIImagePickerController.CameraDevice?
    let onImagePicked: (UIImage) -> Void
    let onCancel: (() -> Void)?

    init(
        sourceType: UIImagePickerController.SourceType,
        cameraDevice: UIImagePickerController.CameraDevice? = nil,
        onImagePicked: @escaping (UIImage) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.sourceType = sourceType
        self.cameraDevice = cameraDevice
        self.onImagePicked = onImagePicked
        self.onCancel = onCancel
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        if let cameraDevice = cameraDevice {
            picker.cameraDevice = cameraDevice
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel?()
            picker.dismiss(animated: true)
        }
    }
}

struct AudioStickerRecordingView: View {
    let onAdd: (Data, Double) -> Void

    @StateObject private var recorder = AudioRecordingManager.shared
    @State private var isRecording = false
    @State private var recordedData: Data?
    @State private var duration: Double = 0
    @State private var timer: Timer?
    @State private var isPlaying = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playbackTimer: Timer?
    @State private var playbackProgress: Double = 0
    // Stable waveform levels generated once per recording.
    @State private var waveformLevels: [Float] = (0..<30).map { _ in Float.random(in: 0.2...0.8) }

    var body: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("stickerview.audio.title", comment: "Add your voice"))
                .font(.system(size: 18, weight: .black, design: .rounded))
                .padding(.top, 8)

            ZStack {
                if isRecording {
                    LiveWaveformView(color: Color(red: 1.0, green: 0.4, blue: 0.3))
                        .frame(height: 44)
                } else if recordedData != nil {
                    VisualWaveformView(
                        levels: waveformLevels,
                        color: Color.white.opacity(0.2),
                        activeColor: Color(red: 1.0, green: 0.4, blue: 0.3),
                        progress: playbackProgress,
                        height: 35
                    )
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { togglePlayback() }
                } else {
                    AttachmentIconView(icon: .voice, preset: .voiceStickerPrompt, tintColor: .secondary)
                        .opacity(0.5)
                        .frame(height: 44)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.clear)
                    .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 20))
            )
            .padding(.vertical, 6)

            VStack(spacing: 6) {
                Text(formatDuration(duration))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(isRecording ? .red : .primary)
                    .contentTransition(.numericText())

                Text(statusLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 32) {
                if recordedData != nil && !isRecording {
                    Button(action: discardRecording) {
                        ZStack {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 44, height: 44)
                                .momentsChromeGlass(in: Circle(), interactive: true)

                            Image(systemName: "trash.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                    }
                }

                Button(action: toggleRecording) {
                    ZStack {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 72, height: 72)
                            .momentsChromeGlass(in: Circle(), interactive: true)

                        if isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.red)
                                .frame(width: 22, height: 22)
                        } else {
                            AttachmentIconView(icon: .voice, preset: .voiceRecording, tintColor: .red)
                        }
                    }
                }
                .scaleEffect(isRecording ? 1.08 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isRecording)

                if recordedData != nil && !isRecording {
                    Button(action: togglePlayback) {
                        ZStack {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 44, height: 44)
                                .momentsChromeGlass(in: Circle(), interactive: true)

                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(.vertical, 8)

            if let data = recordedData, !isRecording {
                Button(action: {
                    HapticManager.shared.mediumImpact()
                    onAdd(data, duration)
                }) {
                    Text(NSLocalizedString("stickerview.audio.add", comment: "Add to Story"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color.clear)
                                .momentsChromeGlass(in: Capsule(), interactive: true)
                        )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .onAppear {
            if recordedData != nil {
                startPlayback()
            }
        }
        .onDisappear {
            stopEverything()
        }
    }

    private var statusLabel: String {
        if isRecording { return NSLocalizedString("stickerview.audio.recording", comment: "Recording...") }
        if recordedData != nil {
            return isPlaying
                ? "▶ \(NSLocalizedString("stickerview.audio.recorded", comment: "Ready to add"))"
                : NSLocalizedString("stickerview.audio.recorded", comment: "Ready to add")
        }
        return NSLocalizedString("stickerview.audio.tapToRecord", comment: "Tap to record")
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        stopPlayback()
        recordedData = nil
        duration = 0
        playbackProgress = 0
        waveformLevels = (0..<30).map { _ in Float.random(in: 0.2...0.8) }

        recorder.startRecording { started in
            guard started else { return }
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                duration += 0.1
                if duration >= 15 {
                    stopRecording()
                }
            }
        }
    }

    private func stopRecording() {
        isRecording = false
        timer?.invalidate()
        timer = nil

        recorder.stopRecording { recording in
            self.recordedData = recording?.data
            if recording != nil {
                self.startPlayback()
            }
        }
    }

    private func discardRecording() {
        stopPlayback()
        recordedData = nil
        duration = 0
        playbackProgress = 0
    }

    private func togglePlayback() {
        if isPlaying { stopPlayback() } else { startPlayback() }
    }

    private func startPlayback() {
        guard let data = recordedData else { return }

        Task { @MainActor in
            // La preview del sheet debe sonar aunque el dispositivo esté en silencio.
            // La sesión debe estar activa antes de crear el player.
            guard await MomentsAudioSession.activate(category: .playback, mode: .default) else { return }

            do {
                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.play()
                isPlaying = true

                playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                    if let player = audioPlayer {
                        playbackProgress = player.currentTime / max(player.duration, 0.001)
                        if !player.isPlaying {
                            stopPlayback()
                        }
                    }
                }
            } catch {
                print("Failed to play: \(error)")
            }
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackProgress = 0
        playbackTimer?.invalidate()
        playbackTimer = nil
        MomentsAudioSession.deactivate()
    }

    private func stopEverything() {
        if isRecording { recorder.stopRecording { _ in } }
        stopPlayback()
        timer?.invalidate()
    }

    private func formatDuration(_ time: Double) -> String {
        let seconds = Int(time)
        let millis = Int((time - Double(seconds)) * 10)
        return String(format: "00:%02d.%d", seconds, millis)
    }
}
