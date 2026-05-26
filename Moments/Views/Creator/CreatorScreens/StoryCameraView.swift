import SwiftUI
import AVFoundation
import Photos
import UIKit

// MARK: - Story Camera View
struct StoryCameraView: View {
    @Binding var selectedMediaItems: [CreatorMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var safeAreaTintColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }
    private var topControlForegroundColor: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.82)
    }
    private var topControlStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    @State private var showingGallery = false
    @State private var cameraPosition: AVCaptureDevice.Position = .back
    @State private var flashMode: AVCaptureDevice.FlashMode = .off
    @State private var isRecording = false
    @State private var recordingTimer: Timer?
    @State private var recordingDuration: TimeInterval = 0
    @State private var zoomLevel: CGFloat = 1.0
    @State private var lastZoomLevel: CGFloat = 1.0
    @State private var capturePhotoTrigger = false
    @State private var lastGalleryImage: UIImage?
    @StateObject private var orientationManager = OrientationManager.shared

    private var deviceOrientation: UIDeviceOrientation {
        orientationManager.orientation
    }

    private var rotationAngle: Double {
        switch deviceOrientation {
        case .landscapeLeft: return 90
        case .landscapeRight: return -90
        case .portraitUpsideDown: return 180
        default: return 0
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let captureRect = creatorMomentsCaptureRect(in: proxy.size, topInset: proxy.safeAreaInsets.top, bottomInset: proxy.safeAreaInsets.bottom)
            let controlY = min(proxy.size.height - proxy.safeAreaInsets.bottom - 20, captureRect.maxY + 50)
            let captureButtonY = captureRect.maxY - 10

            ZStack {
                safeAreaTintColor
                    .ignoresSafeArea()

                // Camera preview
                CameraPreviewRepresentable(
                    cameraPosition: $cameraPosition,
                    flashMode: $flashMode,
                    isRecording: $isRecording,
                    zoomLevel: $zoomLevel,
                    capturePhotoTrigger: $capturePhotoTrigger,
                    deviceOrientation: deviceOrientation,
                    onImageCaptured: { image in
                        handleCapturedImage(image)
                    },
                    onVideoCaptured: { videoURL in
                        handleCapturedVideo(videoURL)
                    }
                )
                .frame(width: captureRect.width, height: captureRect.height)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .position(x: captureRect.midX, y: captureRect.midY)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let newZoom = lastZoomLevel * value
                            zoomLevel = min(max(newZoom, 1.0), 5.0)
                        }
                        .onEnded { value in
                            lastZoomLevel = zoomLevel
                        }
                )

                topControlsOverlay
                    .frame(width: captureRect.width, height: captureRect.height, alignment: .top)
                    .position(x: captureRect.midX, y: captureRect.midY)

                // Bottom controls
                recordingStatusView
                    .position(x: captureRect.midX, y: captureRect.maxY - 58)

                bottomSideControls
                    .frame(width: min(captureRect.width + 54, proxy.size.width - 72))
                    .position(x: captureRect.midX, y: controlY)

                captureButtonOverlay
                    .position(x: captureRect.midX, y: captureButtonY)
            }
        }
        .sheet(isPresented: $showingGallery) {
            StoryGalleryPicker { media in
                selectedMediaItems = [media]
                currentFlow = .storyEditing
            }
        }

        .onAppear {
            setupAudioSession()
            loadLastGalleryImage()
            orientationManager.startTracking()
        }
        .onDisappear {
            stopRecording()
            orientationManager.stopTracking()
        }
    }

    private var flashIcon: String {
        switch flashMode {
        case .off: return "bolt.slash"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a"
        @unknown default: return "bolt.slash"
        }
    }

    private var topControlsOverlay: some View {
        VStack {
            HStack {
                roundControlButton(systemImage: "xmark", action: {
                    showCreatorView = false
                })
                .rotationEffect(.degrees(rotationAngle))
                .animation(.spring(), value: rotationAngle)

                Spacer()

                roundControlButton(systemImage: flashIcon, action: {
                    toggleFlash()
                })
                .rotationEffect(.degrees(rotationAngle))
                .animation(.spring(), value: rotationAngle)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Spacer()
        }
    }

    private var recordingStatusView: some View {
        ZStack {
            if isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: isRecording)

                    Text(formatTime(recordingDuration))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.5))
                .cornerRadius(20)
            }
        }
        .frame(height: 36)
    }

    private var bottomSideControls: some View {
        HStack {
            galleryButton
                .rotationEffect(.degrees(rotationAngle))
                .animation(.spring(), value: rotationAngle)

            Spacer()

            switchCameraButton
                .rotationEffect(.degrees(rotationAngle))
                .animation(.spring(), value: rotationAngle)
        }
        .padding(.horizontal, 18)
    }

    private var captureButtonOverlay: some View {
        CaptureButton(
            isRecording: $isRecording,
            onTap: {
                takePhoto()
            },
            onLongPressStart: { startRecording() },
            onLongPressEnd: { stopRecording() }
        )
    }

    private var galleryButton: some View {
        Button(action: {
            showingGallery = true
        }) {
            if let lastImage = lastGalleryImage {
                Image(uiImage: lastImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            } else {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                    Image(systemName: "photo.stack")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .background {
                    Color.clear
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
            }
        }
    }

    private var switchCameraButton: some View {
        Button(action: {
            switchCamera()
        }) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(topControlForegroundColor)
                .frame(width: 48, height: 48)
                .background {
                    Color.clear
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .overlay(
                    Circle()
                        .stroke(topControlStrokeColor, lineWidth: 1)
                )
        }
    }

    private func roundControlButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(topControlForegroundColor)
                .frame(width: 42, height: 42)
                .background {
                    Color.clear
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .overlay(
                    Circle()
                        .stroke(topControlStrokeColor, lineWidth: 1)
                )
        }
    }

    private func toggleFlash() {
        switch flashMode {
        case .off: flashMode = .on
        case .on: flashMode = .auto
        case .auto: flashMode = .off
        @unknown default: flashMode = .off
        }
    }

    private func switchCamera() {
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = cameraPosition == .back ? .front : .back
            // Reset zoom when switching cameras
            zoomLevel = 1.0
            lastZoomLevel = 1.0
        }
    }

    private func takePhoto() {
        capturePhotoTrigger.toggle()
    }

    private func startRecording() {
        isRecording = true
        recordingDuration = 0
        startRecordingTimer()
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingDuration += 0.1
            if recordingDuration >= 60 { // Max 60 seconds
                stopRecording()
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [])
            try session.setActive(true)
        } catch {
        }
    }

    private func handleCapturedImage(_ image: UIImage) {
        let detectedRatio = CreatorMedia.AspectRatio.fromRatio(image.size.width / image.size.height)
        let processedMedia = CreatorMedia(
            id: UUID().uuidString,
            image: image,
            videoURL: nil,
            type: .image,
            aspectRatio: detectedRatio,
            recommendedAspectRatio: detectedRatio
        )
        selectedMediaItems = [processedMedia]
        currentFlow = .storyEditing
    }

    private func handleCapturedVideo(_ videoURL: URL) {
        // Generate thumbnail from video
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        Task {
            do {
                let (cgImage, _) = try await generator.image(at: .zero)
                let thumbnail = UIImage(cgImage: cgImage)

                let detectedRatio = CreatorMedia.AspectRatio.fromRatio(thumbnail.size.width / thumbnail.size.height)

                await MainActor.run {
                    let processedMedia = CreatorMedia(
                        id: UUID().uuidString,
                        image: thumbnail,
                        videoURL: videoURL,
                        type: .video,
                        aspectRatio: detectedRatio,
                        recommendedAspectRatio: detectedRatio
                    )
                    selectedMediaItems = [processedMedia]
                    currentFlow = .storyEditing
                }
            } catch {
            }
        }
    }

    private func loadLastGalleryImage() {
        // ✅ Cargar la última imagen de la galería en background
        Task {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 1

            let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)

            if let lastAsset = fetchResult.firstObject {
                let manager = PHImageManager.default()
                let options = PHImageRequestOptions()
                options.deliveryMode = .fastFormat
                options.isSynchronous = false

                manager.requestImage(
                    for: lastAsset,
                    targetSize: CGSize(width: 120, height: 120),
                    contentMode: .aspectFill,
                    options: options
                ) { image, _ in
                    DispatchQueue.main.async {
                        self.lastGalleryImage = image
                    }
                }
            }
        }
    }
}
