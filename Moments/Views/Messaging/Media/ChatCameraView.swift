import SwiftUI
import AVFoundation
import Photos
import PhotosUI

// Cámara del chat estilo story (Instagram DM): captura full-bleed 9:16 con la
// misma base de cámara que las historias, y compose posterior con edición
// ligera + selector cíclico de modo (ver una vez / repetir / guardar en chat).
struct ChatCameraView: View {
    let otherUserId: String
    let otherUsername: String
    let onSend: (Data, EnhancedCameraPickerView.MediaType, ChatMediaSendMode, ChatMediaOverlayPayload?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var cameraPosition: AVCaptureDevice.Position = .front
    @State private var flashMode: AVCaptureDevice.FlashMode = .off
    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var zoomLevel: CGFloat = 1.0
    @State private var lastZoomLevel: CGFloat = 1.0
    @State private var capturePhotoTrigger = false
    @State private var lastGalleryImage: UIImage?
    @State private var showPhotoPicker = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var editorMediaItems: [ProcessedMedia] = []
    @State private var editorFlow: CreatorView.CreatorFlow = .storyCamera
    @State private var editorStartsInTextMode = false
    @State private var editorHostVisible = true
    @StateObject private var orientationManager = OrientationManager.shared

    private var isEditorActive: Bool {
        editorFlow == .storyEditing
    }

    private var safeAreaTintColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var controlForegroundColor: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.82)
    }

    private var controlStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var body: some View {
        GeometryReader { proxy in
            let captureRect = creatorMomentsCaptureRect(
                in: proxy.size,
                topInset: proxy.safeAreaInsets.top,
                bottomInset: proxy.safeAreaInsets.bottom
            )
            let captureButtonY = captureRect.maxY - 10
            let bottomControlsWidth = max(0, min(captureRect.width + 54, proxy.size.width - 72))

            ZStack {
                safeAreaTintColor
                    .ignoresSafeArea()

                CameraPreviewRepresentable(
                    cameraPosition: $cameraPosition,
                    flashMode: $flashMode,
                    isRecording: $isRecording,
                    zoomLevel: $zoomLevel,
                    capturePhotoTrigger: $capturePhotoTrigger,
                    deviceOrientation: orientationManager.orientation,
                    onImageCaptured: { image in
                        handleCapturedImage(image)
                    },
                    onVideoCaptured: { videoURL in
                        handleCapturedVideo(videoURL)
                    }
                )
                .frame(width: captureRect.width, height: captureRect.height)
                .clipShape(RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous))
                .position(x: captureRect.midX, y: captureRect.midY)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let newZoom = lastZoomLevel * value
                            zoomLevel = min(max(newZoom, 1.0), 5.0)
                        }
                        .onEnded { _ in
                            lastZoomLevel = zoomLevel
                        }
                )
                .onTapGesture(count: 2) {
                    switchCamera()
                }

                topControlsOverlay
                    .frame(width: captureRect.width, height: captureRect.height, alignment: .top)
                    .position(x: captureRect.midX, y: captureRect.midY)

                textModeButton
                    .position(x: captureRect.maxX - 26, y: captureRect.midY)

                recordingStatusView
                    .position(x: captureRect.midX, y: captureRect.maxY - 108)

                bottomSideControls
                    .frame(width: bottomControlsWidth)
                    .position(x: captureRect.midX, y: proxy.size.height - proxy.safeAreaInsets.bottom - 30)

                CaptureButton(
                    isRecording: $isRecording,
                    onTap: { capturePhotoTrigger.toggle() },
                    onLongPressStart: { startRecording() },
                    onLongPressEnd: { stopRecording() }
                )
                .position(x: captureRect.midX, y: captureButtonY)

                if isEditorActive {
                    StoryEditingView(
                        selectedMediaItems: $editorMediaItems,
                        currentFlow: $editorFlow,
                        showCreatorView: $editorHostVisible,
                        startInTextMode: $editorStartsInTextMode,
                        initialSticker: nil,
                        initialChainId: nil,
                        initialChainTitle: nil,
                        initialChainPosition: nil,
                        chatRecipientUserId: otherUserId,
                        onChatSend: { data, mediaType, mode, overlayPayload in
                            onSend(data, mediaType, mode, overlayPayload)
                        }
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedItems,
            maxSelectionCount: 1,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedItems) { _, items in
            handleSelectedGalleryMedia(items)
        }
        .onChange(of: editorFlow) { _, newFlow in
            guard newFlow == .storyCamera else { return }
            editorMediaItems = []
            editorStartsInTextMode = false
        }
        .onAppear {
            orientationManager.startTracking()
            loadLastGalleryImage()
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
                roundControlButton(systemImage: "xmark") {
                    dismiss()
                }

                Spacer()

                headerBadge

                Spacer()

                roundControlButton(systemImage: flashIcon) {
                    toggleFlash()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Spacer()
        }
    }

    private var headerBadge: some View {
        HStack(spacing: 8) {
            AsyncProfileImageView(userId: otherUserId)
                .frame(width: 26, height: 26)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text("chat.camera.header")
                    .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                Text(otherUsername)
                    .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Color.clear
                .momentsChromeGlass(in: Capsule(), interactive: false)
        }
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var textModeButton: some View {
        Button(action: openTextMode) {
            Text("Aa")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(controlForegroundColor)
                .frame(width: 48, height: 48)
                .background {
                    Color.clear
                        .momentsChromeGlass(in: Circle(), interactive: true)
                }
                .overlay(
                    Circle()
                        .stroke(controlStrokeColor, lineWidth: 1)
                )
        }
    }

    private var recordingStatusView: some View {
        ZStack {
            if isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)

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

            Spacer()

            roundControlButton(systemImage: "arrow.triangle.2.circlepath.camera", size: 48) {
                switchCamera()
            }
        }
        .padding(.horizontal, 18)
    }

    private var galleryButton: some View {
        Button(action: { showPhotoPicker = true }) {
            if let lastGalleryImage {
                Image(uiImage: lastGalleryImage)
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
            }
        }
    }

    private func roundControlButton(systemImage: String, size: CGFloat = 42, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(controlForegroundColor)
                .frame(width: size, height: size)
                .background {
                    Color.clear
                        .momentsChromeGlass(in: Circle(), interactive: true)
                }
                .overlay(
                    Circle()
                        .stroke(controlStrokeColor, lineWidth: 1)
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
            zoomLevel = 1.0
            lastZoomLevel = 1.0
        }
    }

    private func startRecording() {
        isRecording = true
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingDuration += 0.1
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func openTextMode() {
        editorStartsInTextMode = true
        editorMediaItems = []
        editorFlow = .storyEditing
    }

    private func handleCapturedImage(_ image: UIImage) {
        HapticManager.shared.lightImpact()
        openEditor(image: image, videoURL: nil)
    }

    private func handleCapturedVideo(_ videoURL: URL) {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        Task {
            let thumbnail = (try? await generator.image(at: .zero)).map { UIImage(cgImage: $0.image) }
            let videoDuration = (try? await StoryVideoProcessingService.shared.duration(for: videoURL)) ?? 0
            await MainActor.run {
                openEditor(
                    image: thumbnail ?? UIImage(),
                    videoURL: videoURL,
                    videoDuration: videoDuration > 0 ? videoDuration : nil
                )
            }
        }
    }

    private func openEditor(image: UIImage, videoURL: URL?, videoDuration: Double? = nil) {
        let detectedRatio = CreatorMedia.AspectRatio.fromRatio(
            image.size.height > 0 ? image.size.width / image.size.height : 9.0 / 16.0
        )
        editorStartsInTextMode = false
        editorMediaItems = [
            CreatorMedia(
                id: UUID().uuidString,
                image: image,
                videoURL: videoURL,
                type: videoURL == nil ? .image : .video,
                aspectRatio: detectedRatio,
                recommendedAspectRatio: detectedRatio,
                videoDuration: videoDuration
            )
        ]
        editorFlow = .storyEditing
    }

    private func handleSelectedGalleryMedia(_ items: [PhotosPickerItem]) {
        guard let item = items.first else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run { selectedItems = [] }
                return
            }
            await MainActor.run {
                selectedItems = []
                if let image = UIImage(data: data) {
                    openEditor(image: image.chatCameraNormalizedUp(), videoURL: nil)
                } else {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("chat_camera_gallery_\(UUID().uuidString).mov")
                    try? data.write(to: url, options: .atomic)
                    handleCapturedVideo(url)
                }
            }
        }
    }

    private func loadLastGalleryImage() {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized ||
              PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited else { return }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        guard let lastAsset = PHAsset.fetchAssets(with: .image, options: fetchOptions).firstObject else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        PHImageManager.default().requestImage(
            for: lastAsset,
            targetSize: CGSize(width: 120, height: 120),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                lastGalleryImage = image
            }
        }
    }
}

private extension UIImage {
    func chatCameraNormalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
