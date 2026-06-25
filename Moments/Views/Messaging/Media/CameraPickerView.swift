import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import Photos

private let momentsCaptureAspectRatio: CGFloat = 9.0 / 16.0

private func momentsAspectRect(aspectRatio: CGFloat, in rect: CGRect) -> CGRect {
    guard rect.width > 0, rect.height > 0 else { return .zero }

    let candidateHeight = rect.width / aspectRatio
    if candidateHeight <= rect.height {
        let y = rect.minY + ((rect.height - candidateHeight) / 2)
        return CGRect(x: rect.minX, y: y, width: rect.width, height: candidateHeight)
    } else {
        let width = rect.height * aspectRatio
        let x = rect.minX + ((rect.width - width) / 2)
        return CGRect(x: x, y: rect.minY, width: width, height: rect.height)
    }
}

private func momentsCaptureRect(in size: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> CGRect {
    let availableRect = CGRect(
        x: 0,
        y: topInset,
        width: size.width,
        height: max(size.height - topInset - bottomInset, 0)
    )
    return momentsAspectRect(aspectRatio: momentsCaptureAspectRatio, in: availableRect)
}

// MARK: - Enhanced Camera Picker with Fixed Gallery and Useful Options
struct EnhancedCameraPickerView: View {
    let onMediaCaptured: (Data, MediaType, Bool) -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isEphemeralMode = false
    @State private var captureMode: CaptureMode = .photo
    @State private var cameraPosition: CameraPosition = .back
    @State private var flashMode: FlashMode = .off
    @State private var selectedItems: [PhotosPickerItem] = [] // ✅ Para PhotosPicker
    @State private var showPhotoPicker = false // ✅ Control del PhotosPicker
    @State private var modeTransientOffset: CGFloat = 0
    @State private var recentGalleryPreview: UIImage?
    @State private var photoLibraryManager = PHCachingImageManager()
    @State private var pendingPreview: CapturedMediaPreview?
    @State private var isVideoRecording = false
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

    private let ephemeralGradient = LinearGradient(
        colors: [Color(hex: "FFB347"), Color(hex: "FFCC33")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    enum CaptureMode: CaseIterable {
        case photo, video

        var icon: String {
            switch self {
            case .photo: return "camera.fill"
            case .video: return "video.fill"
            }
        }

        var title: String {
            switch self {
            case .photo: return NSLocalizedString("camera.capture.photo", comment: "Photo mode")
            case .video: return NSLocalizedString("camera.capture.video", comment: "Video mode")
            }
        }
    }

    enum CameraPosition {
        case back, front

        var icon: String {
            switch self {
            case .back: return "camera.rotate"
            case .front: return "camera.rotate.fill"
            }
        }
    }

    enum FlashMode: CaseIterable {
        case off, on, auto

        var icon: String {
            switch self {
            case .off: return "bolt.slash"
            case .on: return "bolt.fill"
            case .auto: return "bolt.badge.a"
            }
        }
    }

    enum MediaType {
        case image, video
    }

    struct CapturedMediaPreview: Identifiable {
        let id = UUID()
        let data: Data
        let mediaType: MediaType
        let image: UIImage?
        let videoURL: URL?
        let isEphemeral: Bool
    }

    @State private var cameraViewController: CameraViewController?

    private var controlStrokeColor: Color {
        isEphemeralMode ? Color(hex: "FFCC33").opacity(0.45) : Color.white.opacity(0.18)
    }

    private var controlForegroundColor: Color {
        isEphemeralMode ? Color(hex: "FFCC33") : .white
    }

    private var safeAreaTintColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private let modeControlWidth: CGFloat = 132
    private let modeControlHeight: CGFloat = 36
    private let modePillWidth: CGFloat = 62
    private let modePillHeight: CGFloat = 30
    private let modeInnerPadding: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let captureRect = momentsCaptureRect(in: proxy.size, topInset: proxy.safeAreaInsets.top, bottomInset: proxy.safeAreaInsets.bottom)

            ZStack {
                safeAreaTintColor
                    .ignoresSafeArea()

                CameraView(
                    captureMode: captureMode,
                    cameraPosition: cameraPosition,
                    flashMode: flashMode,
                    isEphemeralMode: isEphemeralMode,
                    showGridLines: false,
                    onMediaCaptured: { data, mediaType, _ in
                        presentPreview(data: data, mediaType: mediaType)
                    },
                    onVideoRecordingStateChange: { isRecording in
                        self.isVideoRecording = isRecording
                    },
                    deviceOrientation: deviceOrientation,
                    cameraViewController: $cameraViewController
                )
                .frame(width: captureRect.width, height: captureRect.height)
                .clipShape(FeedMomentCardLayout.continuousRoundedRect)
                .position(x: captureRect.midX, y: captureRect.midY)

                topBar

                ZStack {
                    VStack(spacing: 12) {
                        EnhancedCaptureButton(
                            captureMode: captureMode,
                            isEphemeralMode: isEphemeralMode,
                            isVideoRecording: $isVideoRecording,
                            onCapture: handleCapture
                        )

                        HStack(alignment: .center, spacing: 40) {
                            galleryButton
                                .rotationEffect(.degrees(rotationAngle))
                                .animation(.spring(), value: rotationAngle)

                            modeSelector

                            topCircleButton(icon: cameraPosition.icon, action: switchCamera)
                                .rotationEffect(.degrees(rotationAngle))
                                .animation(.spring(), value: rotationAngle)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 26)
                }
                .frame(width: captureRect.width, height: captureRect.height, alignment: .bottom)
                .position(x: captureRect.midX, y: captureRect.midY)

                // ✅ EPHEMERAL MODE INDICATOR - Mejorado
                if let pendingPreview {
                    CameraMediaPreviewOverlay(
                        preview: pendingPreview,
                        onClose: discardPendingPreview,
                        onRetake: discardPendingPreview,
                        onSend: sendPendingPreview
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
        }
        .navigationBarHidden(true)
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedItems,
            maxSelectionCount: 1,
            matching: .any(of: [.images, .videos])
        )
        .onAppear {
            orientationManager.startTracking()
        }
        .onDisappear {
            orientationManager.stopTracking()
        }
        .onChange(of: selectedItems) { _, items in
            handleSelectedMedia(items)
        }
        .onAppear {
            loadRecentGalleryPreview()
        }
    }

    private var topBar: some View {
        VStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background {
                            Color.clear
                                .momentsChromeGlass(in: Circle(), interactive: true)
                        }
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }

                Spacer()

                ephemeralHeaderToggle
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var ephemeralHeaderToggle: some View {
        Button(action: { toggleEphemeralMode() }) {
            HStack(spacing: 6) {
                if isEphemeralMode {
                    AttachmentIconView(icon: .ephemeral, preset: .cameraEphemeral)
                } else {
                    Image(systemName: "eye")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(isEphemeralMode ? NSLocalizedString("camera.mode.ephemeral", comment: "Ephemeral mode") : NSLocalizedString("camera.mode.normal", comment: "Normal mode"))
                    .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
            }
            .foregroundColor(isEphemeralMode ? .black : .white)
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background {
                Group {
                    if isEphemeralMode {
                        Capsule().fill(ephemeralGradient)
                    } else {
                        Color.clear
                            .momentsChromeGlass(in: Capsule(), interactive: true)
                    }
                }
            }
            .overlay(
                Capsule()
                    .stroke(controlStrokeColor, lineWidth: 1)
            )
        }
    }

    private func topCircleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(controlForegroundColor)
                .frame(width: 42, height: 42)
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

    private var modeTravel: CGFloat {
        ((modeControlWidth - (modeInnerPadding * 2)) - modePillWidth) / 2
    }

    private var modeBaseOffset: CGFloat {
        captureMode == .photo ? -modeTravel : modeTravel
    }

    private var modePillOffset: CGFloat {
        modeBaseOffset + modeTransientOffset
    }

    private var modeVisualSelection: CaptureMode {
        modePillOffset <= 0 ? .photo : .video
    }

    private func modeLabelColor(for mode: CaptureMode) -> Color {
        modeVisualSelection == mode ? .white.opacity(0.96) : .white.opacity(0.58)
    }

    private func constrainedModeTranslation(_ translation: CGFloat) -> CGFloat {
        let proposedOffset = modeBaseOffset + translation
        let clampedOffset = min(max(proposedOffset, -modeTravel), modeTravel)
        return clampedOffset - modeBaseOffset
    }

    private func settleMode(translation: CGFloat, locationX: CGFloat, width: CGFloat) {
        let threshold = min(width * 0.16, modeTravel * 0.7)
        let targetMode: CaptureMode

        if translation < -threshold {
            targetMode = .photo
        } else if translation > threshold {
            targetMode = .video
        } else {
            targetMode = locationX < width / 2 ? .photo : .video
        }

        withAnimation(.smooth(duration: 0.18, extraBounce: 0.01)) {
            captureMode = targetMode
            modeTransientOffset = 0
        }
    }

    private var modeSelector: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule()
                    .fill(Color.black.opacity(0.28))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Capsule()
                    .fill(Color.white.opacity(0.055))
                    .frame(width: modePillWidth, height: modePillHeight)
                    .momentsChromeGlass(in: Capsule(), interactive: true)
                    .shadow(color: .black.opacity(0.26), radius: 7, x: 0, y: 2)
                    .offset(x: modePillOffset)

                HStack(spacing: 0) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Text(mode.title)
                            .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                            .foregroundColor(modeLabelColor(for: mode))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, modeInnerPadding)
                .animation(.smooth(duration: 0.18, extraBounce: 0.01), value: modeVisualSelection)

                Capsule()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Capsule())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    modeTransientOffset = constrainedModeTranslation(value.translation.width)
                                }
                            }
                            .onEnded { value in
                                settleMode(translation: value.translation.width, locationX: value.location.x, width: proxy.size.width)
                            }
                    )
            }
        }
        .frame(width: modeControlWidth, height: modeControlHeight)
    }

    private var galleryButton: some View {
        Button(action: {
            showPhotoPicker = true
        }) {
            Group {
                if let recentGalleryPreview {
                    Image(uiImage: recentGalleryPreview)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.14))
                        Image(systemName: "photo.stack")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
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

    // ✅ ACTIONS
    private func toggleEphemeralMode() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isEphemeralMode.toggle()
        }
    }

    private func switchCamera() {
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = cameraPosition == .back ? .front : .back
        }
    }

    private func cycleFlashMode() {
        let modes: [FlashMode] = [.off, .on, .auto]
        if let currentIndex = modes.firstIndex(of: flashMode) {
            flashMode = modes[(currentIndex + 1) % modes.count]
        }
    }

    private func loadRecentGalleryPreview() {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch currentStatus {
        case .authorized, .limited:
            fetchLatestPhotoPreview()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                guard status == .authorized || status == .limited else { return }
                fetchLatestPhotoPreview()
            }
        default:
            recentGalleryPreview = nil
        }
    }

    private func fetchLatestPhotoPreview() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        let assets = PHAsset.fetchAssets(with: fetchOptions)
        guard let asset = assets.firstObject else {
            DispatchQueue.main.async {
                recentGalleryPreview = nil
            }
            return
        }

        let targetSize = CGSize(width: 160, height: 160)
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.resizeMode = .exact
        requestOptions.isSynchronous = false
        requestOptions.isNetworkAccessAllowed = true

        photoLibraryManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: requestOptions
        ) { image, _ in
            DispatchQueue.main.async {
                recentGalleryPreview = image
            }
        }
    }

    // ✅ HANDLE SELECTED MEDIA FROM GALLERY
    private func handleSelectedMedia(_ items: [PhotosPickerItem]) {
        guard let item = items.first else { return }


        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                DispatchQueue.main.async {
                    // Determine if it's image or video
                    if let _ = UIImage(data: data) {
                        let normalizedData = self.normalizedGalleryImageData(from: data) ?? data
                        self.presentPreview(data: normalizedData, mediaType: .image)
                    } else {
                        self.presentPreview(data: data, mediaType: .video)
                    }

                    // Clear selection
                    self.selectedItems = []
                }
            } else {
            }
        }
    }

    private func normalizedGalleryImageData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let normalizedImage = normalizedGalleryImage(from: image)
        return normalizedImage.jpegData(compressionQuality: 0.95)
    }

    private func normalizedGalleryImage(from image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }

        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private func handleCapture() {
        guard let cameraVC = cameraViewController else {
            return
        }


        switch captureMode {
        case .photo:
            cameraVC.capturePhoto()
        case .video:
            if cameraVC.videoOutput.isRecording {
                cameraVC.stopVideoRecording()
            } else {
                cameraVC.startVideoRecording()
            }
        }
    }

    private func presentPreview(data: Data, mediaType: MediaType) {
        pendingPreview = CapturedMediaPreview(
            data: data,
            mediaType: mediaType,
            image: mediaType == .image ? UIImage(data: data) : nil,
            videoURL: mediaType == .video ? persistPreviewVideo(data: data) : nil,
            isEphemeral: isEphemeralMode
        )
    }

    private func discardPendingPreview() {
        if let videoURL = pendingPreview?.videoURL {
            try? FileManager.default.removeItem(at: videoURL)
        }
        pendingPreview = nil
    }

    private func sendPendingPreview() {
        guard let pendingPreview else { return }
        onMediaCaptured(pendingPreview.data, pendingPreview.mediaType, pendingPreview.isEphemeral)
        discardPendingPreview()
        dismiss()
    }

    private func persistPreviewVideo(data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("camera_preview_\(UUID().uuidString).mov")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

// ✅ ENHANCED CAPTURE BUTTON
struct EnhancedCaptureButton: View {
    let captureMode: EnhancedCameraPickerView.CaptureMode
    let isEphemeralMode: Bool
    @Binding var isVideoRecording: Bool
    let onCapture: () -> Void
    @State private var isPhotoCaptureFeedback = false
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?

    private let ephemeralGradient = LinearGradient(
        colors: [Color(hex: "FFB347"), Color(hex: "FFCC33")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private var isRecording: Bool {
        captureMode == .video && isVideoRecording
    }

    private var isCaptureActive: Bool {
        isRecording || isPhotoCaptureFeedback
    }

    private var captureFillColor: Color {
        if captureMode == .video {
            return .red
        }
        return .white
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if isRecording && captureMode == .video {
                    Text(formatTime(recordingTime))
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.red)
                                .overlay(
                                    Capsule().stroke(Color.white, lineWidth: 1)
                                )
                        )
                }
            }
            .frame(height: 30)

            Button(action: handleCapture) {
                ZStack {
                    Circle()
                        .fill(isEphemeralMode ? Color(hex: "FFCC33").opacity(0.24) : Color.white.opacity(0.16))
                        .frame(width: 96, height: 96)
                        .blur(radius: isCaptureActive ? 16 : 12)
                        .opacity(isCaptureActive ? 0.22 : 0.12)

                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 82, height: 82)
                        .background {
                            Color.clear
                                .momentsChromeGlass(in: Circle(), interactive: true)
                        }
                        .overlay(
                            Circle()
                                .stroke(isEphemeralMode ? Color(hex: "FFCC33").opacity(0.55) : Color.white.opacity(0.22), lineWidth: 1.5)
                        )

                    Group {
                        if isRecording {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.red)
                                .frame(width: 30, height: 30)
                        } else {
                            Circle()
                                .fill(captureFillColor)
                                .frame(width: captureMode == .photo ? 62 : 54, height: captureMode == .photo ? 62 : 54)
                        }
                    }
                    .scaleEffect(isCaptureActive ? 0.8 : 1.0)
                }
            }
        }
        .buttonStyle(CameraButtonStyle())
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isRecording)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isPhotoCaptureFeedback)
        .onChange(of: isRecording) { _, recording in
            if recording {
                startRecordingTimer()
            } else {
                stopRecordingTimer()
            }
        }
    }

    private func handleCapture() {
        switch captureMode {
        case .photo:
            // Photo capture con feedback visual
            withAnimation(.easeInOut(duration: 0.1)) {
                isPhotoCaptureFeedback = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPhotoCaptureFeedback = false
                }
            }
            onCapture()

        case .video:
            onCapture()
        }
    }

    private func startRecordingTimer() {
        recordingTime = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingTime += 0.1
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingTime = 0
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct CameraMediaPreviewOverlay: View {
    let preview: EnhancedCameraPickerView.CapturedMediaPreview
    let onClose: () -> Void
    let onRetake: () -> Void
    let onSend: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let ephemeralGradient = LinearGradient(
        colors: [Color(hex: "FFB347"), Color(hex: "FFCC33")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private var safeAreaTintColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let bottomInset = proxy.safeAreaInsets.bottom
            let guideRect = momentsCaptureRect(in: proxy.size, topInset: topInset, bottomInset: bottomInset)

            ZStack {
                safeAreaTintColor
                    .ignoresSafeArea()

                Group {
                    ZStack {
                        safeAreaTintColor

                        switch preview.mediaType {
                        case .image:
                            if let image = preview.image {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: guideRect.width, height: guideRect.height)
                                    .clipped()
                            }
                        case .video:
                            if let videoURL = preview.videoURL {
                                CameraPreviewVideoPlayer(url: videoURL)
                                    .frame(width: guideRect.width, height: guideRect.height)
                            }
                        }
                    }
                }
                .clipShape(FeedMomentCardLayout.continuousRoundedRect)
                .position(x: guideRect.midX, y: guideRect.midY)

                VStack(spacing: 0) {
                    HStack {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 42, height: 42)
                                .background {
                                    Color.clear
                                        .momentsChromeGlass(in: Circle(), interactive: true)
                                }
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Spacer()

                    VStack(spacing: 10) {
                        if preview.isEphemeral {
                            HStack(spacing: 8) {
                                AttachmentIconView(icon: .ephemeral, preset: .cameraEphemeralBadge, tintColor: Color(hex: "FFCC33"))
                                Text(NSLocalizedString("camera.preview.ephemeralBadge", comment: "Ephemeral preview badge"))
                                    .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
                            }
                            .foregroundColor(Color(hex: "FFCC33"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background {
                                Color.clear
                                    .momentsChromeGlass(in: Capsule(), interactive: false)
                            }
                            .overlay(
                                Capsule()
                                    .stroke(Color(hex: "FFCC33").opacity(0.45), lineWidth: 1)
                            )
                        }

                        HStack(spacing: 10) {
                            Button(action: onRetake) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(NSLocalizedString("camera.preview.retake", comment: "Retake media"))
                                        .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .frame(minWidth: 112)
                                .frame(height: 42)
                                .background {
                                    Color.clear
                                        .momentsChromeGlass(in: Capsule(), interactive: true)
                                }
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                            }

                            Spacer(minLength: 0)

                            Button(action: onSend) {
                                HStack(spacing: 6) {
                                    if preview.isEphemeral {
                                        AttachmentIconView(icon: .ephemeral, preset: .cameraEphemeral)
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    Text(NSLocalizedString("camera.preview.send", comment: "Send media"))
                                        .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                                }
                                .foregroundColor(preview.isEphemeral ? .black : .white)
                                .padding(.horizontal, 14)
                                .frame(minWidth: 112)
                                .frame(height: 42)
                                .background {
                                    Group {
                                        if preview.isEphemeral {
                                            Capsule().fill(ephemeralGradient)
                                        } else {
                                            Color.clear
                                                .momentsChromeGlass(in: Capsule(), interactive: true)
                                        }
                                    }
                                }
                                .overlay(
                                    Capsule()
                                        .stroke(preview.isEphemeral ? Color.clear : Color.white.opacity(0.14), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 42)
                }
            }
        }
    }
}

private struct CameraPreviewVideoPlayer: View {
    let url: URL
    @State private var isPaused = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var externalSeekTime: Double? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            MomentsVideoPlayer(
                url: url,
                isLooping: true,
                isPaused: isPaused,
                prioritizeSmoothPlayback: true,
                videoGravity: .resizeAspect,
                onDurationReceived: { value in
                    duration = max(value, 0)
                },
                onProgressUpdate: { value in
                    if !isPaused {
                        currentTime = max(value, 0)
                    }
                },
                externalSeekTime: $externalSeekTime
            )
            .contentShape(Rectangle())
            .onTapGesture {
                isPaused.toggle()
            }

            MomentsVideoPlaybackTimeline(
                currentTime: currentTime,
                duration: duration,
                horizontalPadding: 18,
                onSeek: { targetTime in
                    currentTime = targetTime
                    externalSeekTime = targetTime
                }
            )
            .padding(.bottom, 14)
        }
    }
}

// ✅ CAMERA VIEW - ACTUALIZADA CON GRID LINES
struct CameraView: UIViewControllerRepresentable {
    let captureMode: EnhancedCameraPickerView.CaptureMode
    let cameraPosition: EnhancedCameraPickerView.CameraPosition
    let flashMode: EnhancedCameraPickerView.FlashMode
    let isEphemeralMode: Bool
    let showGridLines: Bool // ✅ Nuevo parámetro
    let onMediaCaptured: (Data, EnhancedCameraPickerView.MediaType, Bool) -> Void
    let onVideoRecordingStateChange: (Bool) -> Void
    let deviceOrientation: UIDeviceOrientation // ✅ Propagar orientación
    @Binding var cameraViewController: CameraViewController?
    var zoomFactor: Binding<CGFloat>?
    var lensPresets: Binding<[CGFloat]>?
    var enablesPinchToZoom: Bool = true

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        controller.isPinchToZoomEnabled = enablesPinchToZoom

        DispatchQueue.main.async {
            self.cameraViewController = controller
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.captureMode = captureMode
        uiViewController.cameraPosition = cameraPosition
        uiViewController.flashMode = flashMode
        uiViewController.isEphemeralMode = isEphemeralMode
        uiViewController.showGridLines = showGridLines // ✅ Actualizar grid lines

        // Propagar orientación física para los metadatos de captura
        uiViewController.currentDeviceOrientation = deviceOrientation

        context.coordinator.updateEphemeralMode(isEphemeralMode)

        uiViewController.isPinchToZoomEnabled = enablesPinchToZoom

        // Update camera if position changed
        if uiViewController.currentCameraPosition != cameraPosition {
            uiViewController.switchCamera(to: cameraPosition)
        }

        // Update grid lines
        uiViewController.updateGridLines(showGridLines)

        if let zoomFactor {
            let targetZoom = zoomFactor.wrappedValue
            if abs(uiViewController.currentZoomFactor - targetZoom) > 0.035 {
                uiViewController.setZoomFactor(targetZoom, animated: true, notifyDelegate: false)
            }
        }

        if let lensPresets {
            let presets = uiViewController.lensPresetFactors
            if presets != lensPresets.wrappedValue {
                lensPresets.wrappedValue = presets
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, CameraViewControllerDelegate {
        let parent: CameraView
        private var currentEphemeralMode: Bool = false

        init(_ parent: CameraView) {
            self.parent = parent
            self.currentEphemeralMode = parent.isEphemeralMode
        }

        func updateEphemeralMode(_ isEphemeral: Bool) {
            currentEphemeralMode = isEphemeral
        }

        func didCapturePhoto(_ data: Data) {
            parent.onMediaCaptured(data, .image, currentEphemeralMode)
        }

        func didCaptureVideo(_ data: Data) {
            parent.onMediaCaptured(data, .video, currentEphemeralMode)
        }

        func didChangeVideoRecordingState(_ isRecording: Bool) {
            parent.onVideoRecordingStateChange(isRecording)
        }

        func didUpdateZoomState(zoomFactor: CGFloat, lensPresets: [CGFloat]) {
            if let binding = parent.zoomFactor {
                binding.wrappedValue = zoomFactor
            }
            if let binding = parent.lensPresets {
                binding.wrappedValue = lensPresets
            }
        }
    }
}

// ✅ CAMERA VIEW CONTROLLER - MEJORADO CON GRID LINES
protocol CameraViewControllerDelegate: AnyObject {
    func didCapturePhoto(_ data: Data)
    func didCaptureVideo(_ data: Data)
    func didChangeVideoRecordingState(_ isRecording: Bool)
    func didUpdateZoomState(zoomFactor: CGFloat, lensPresets: [CGFloat])
}

extension CameraViewControllerDelegate {
    func didUpdateZoomState(zoomFactor: CGFloat, lensPresets: [CGFloat]) {}
}

class CameraViewController: UIViewController {
    weak var delegate: CameraViewControllerDelegate?
    var captureMode: EnhancedCameraPickerView.CaptureMode = .photo
    var cameraPosition: EnhancedCameraPickerView.CameraPosition = .back
    var flashMode: EnhancedCameraPickerView.FlashMode = .off
    var isEphemeralMode: Bool = false
    var currentCameraPosition: EnhancedCameraPickerView.CameraPosition = .back
    var showGridLines: Bool = false // ✅ Nuevo
    var currentDeviceOrientation: UIDeviceOrientation = .portrait // ✅ Track para captura
    var isPinchToZoomEnabled = true {
        didSet {
            guard isViewLoaded else { return }
            updatePinchToZoomEnabled()
        }
    }

    private(set) var currentZoomFactor: CGFloat = 1.0
    private(set) var lensPresetFactors: [CGFloat] = [1.0]
    private var currentCaptureDevice: AVCaptureDevice?
    private var pinchAnchorDisplayZoom: CGFloat = 1.0
    private var isPinchGestureActive = false
    private var pinchGestureRecognizer: UIPinchGestureRecognizer?

    /// Zoom en espacio «display» (0,5×, 1×, 2×… como la app Cámara).
    var currentDisplayZoomFactor: CGFloat { currentZoomFactor }

    /// Tope visible como la app Cámara en foto en Pro (~40× display).
    static let photoModeMaxDisplayZoom: CGFloat = 40.0

    var minDisplayZoomFactor: CGFloat {
        guard let device = currentCaptureDevice else { return 1.0 }
        return Self.displayZoom(forVideoZoom: device.minAvailableVideoZoomFactor, device: device)
    }

    var maxDisplayZoomFactor: CGFloat {
        guard let device = currentCaptureDevice else { return 1.0 }
        let hardwareDisplayMax = Self.displayZoom(
            forVideoZoom: device.maxAvailableVideoZoomFactor,
            device: device
        )
        return min(hardwareDisplayMax, Self.photoModeMaxDisplayZoom)
    }

    /// `magnification` es acumulativo desde el inicio del gesto (1 = sin cambio).
    /// `base` debe fijarse una sola vez al empezar el pinch — no actualizarlo en cada frame.
    static func displayZoomFromPinch(
        base: CGFloat,
        magnification: CGFloat,
        sensitivity: CGFloat = 0.32
    ) -> CGFloat {
        guard base > 0, magnification > 0 else { return base }
        let dampedMagnification = 1 + (magnification - 1) * sensitivity
        return base * dampedMagnification
    }

    static func displayZoomMultiplier(for device: AVCaptureDevice) -> CGFloat {
        if #available(iOS 18.0, *) {
            return device.displayVideoZoomFactorMultiplier
        }
        if device.position == .back, device.constituentDevices.count > 1 {
            return 0.5
        }
        return 1.0
    }

    static func displayZoom(forVideoZoom videoZoom: CGFloat, device: AVCaptureDevice) -> CGFloat {
        videoZoom * displayZoomMultiplier(for: device)
    }

    static func videoZoom(forDisplayZoom displayZoom: CGFloat, device: AVCaptureDevice) -> CGFloat {
        let multiplier = displayZoomMultiplier(for: device)
        guard multiplier > 0 else { return displayZoom }
        return displayZoom / multiplier
    }

    private static func roundedPreset(_ value: CGFloat) -> CGFloat {
        if value < 1 {
            return CGFloat(round(value * 10) / 10)
        }
        if abs(value.rounded() - value) < 0.05 {
            return value.rounded()
        }
        return CGFloat(round(value * 10) / 10)
    }

    private func notifyZoomStateChanged() {
        let presets = lensPresetFactors
        let zoom = currentZoomFactor
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.didUpdateZoomState(zoomFactor: zoom, lensPresets: presets)
        }
    }

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    let videoOutput = AVCaptureMovieFileOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var currentCameraInput: AVCaptureDeviceInput?
    private var currentAudioInput: AVCaptureDeviceInput?
    private var gridLinesView: UIView? // ✅ Grid lines overlay
    private var captureEventInteraction: AVCaptureEventInteraction?
    private var systemZoomSlider: AVCaptureSystemZoomSlider?
    private var isApplyingZoomInternally = false
    private let cameraControlQueue = DispatchQueue(label: "com.moments.camera.controls", qos: .userInteractive)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupGridLines() // ✅ Setup grid lines
        configureHardwareCaptureInteraction()
        updatePinchToZoomEnabled()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
        gridLinesView?.frame = view.bounds // ✅ Update grid lines frame
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }

    override var shouldAutorotate: Bool {
        return false
    }

    private func configureHardwareCaptureInteraction() {
        let interaction = AVCaptureEventInteraction { [weak self] event in
            guard event.phase == .ended else { return }
            self?.handleHardwareCapturePress()
        }
        view.addInteraction(interaction)
        captureEventInteraction = interaction
    }

    private func configurePinchToZoom() {
        guard isPinchToZoomEnabled else { return }
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchToZoom(_:)))
        pinch.cancelsTouchesInView = false
        view.addGestureRecognizer(pinch)
        pinchGestureRecognizer = pinch
    }

    private func updatePinchToZoomEnabled() {
        if isPinchToZoomEnabled {
            if pinchGestureRecognizer == nil {
                configurePinchToZoom()
            }
        } else if let pinchGestureRecognizer {
            view.removeGestureRecognizer(pinchGestureRecognizer)
            self.pinchGestureRecognizer = nil
        }
    }

    @objc private func handlePinchToZoom(_ recognizer: UIPinchGestureRecognizer) {
        guard currentCaptureDevice != nil else { return }

        switch recognizer.state {
        case .began:
            isPinchGestureActive = true
            pinchAnchorDisplayZoom = currentZoomFactor
        case .changed:
            if !isPinchGestureActive {
                isPinchGestureActive = true
                pinchAnchorDisplayZoom = currentZoomFactor
            }
            let targetDisplay = Self.displayZoomFromPinch(
                base: pinchAnchorDisplayZoom,
                magnification: recognizer.scale
            )
            setZoomFactor(targetDisplay, animated: false, notifyDelegate: true)
        case .ended, .cancelled:
            isPinchGestureActive = false
        default:
            break
        }
    }

    private func preferredCaptureDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            let typePriority: [AVCaptureDevice.DeviceType] = [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ]

            for deviceType in typePriority {
                if let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) {
                    return device
                }
            }

            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: typePriority,
                mediaType: .video,
                position: .back
            )
            return discovery.devices.max { lhs, rhs in
                let lhsRange = lhs.maxAvailableVideoZoomFactor - lhs.minAvailableVideoZoomFactor
                let rhsRange = rhs.maxAvailableVideoZoomFactor - rhs.minAvailableVideoZoomFactor
                return lhsRange < rhsRange
            }
        }

        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func refreshLensPresets() {
        guard let device = currentCaptureDevice else {
            lensPresetFactors = [1.0]
            return
        }

        let maxDisplay = maxDisplayZoomFactor
        let minDisplay = minDisplayZoomFactor

        var presets: [CGFloat] = [Self.roundedPreset(minDisplay)]

        if 1.0 >= minDisplay - 0.05 && 1.0 <= maxDisplay + 0.05 {
            presets.append(1.0)
        }

        for factor in device.virtualDeviceSwitchOverVideoZoomFactors {
            let display = Self.displayZoom(forVideoZoom: CGFloat(truncating: factor), device: device)
            if display > minDisplay + 0.05 && display <= maxDisplay + 0.05 {
                presets.append(Self.roundedPreset(display))
            }
        }

        for step in [2.0, 4.0, 8.0] {
            if step > minDisplay + 0.05 && step <= maxDisplay + 0.05 {
                presets.append(step)
            }
        }

        lensPresetFactors = Array(Set(presets)).sorted()

        if lensPresetFactors.isEmpty {
            lensPresetFactors = [1.0]
        }
    }

    func setDisplayZoomFactor(_ displayFactor: CGFloat, animated: Bool = true, notifyDelegate: Bool = true) {
        setZoomFactor(displayFactor, animated: animated, notifyDelegate: notifyDelegate)
    }

    func setZoomFactor(_ displayFactor: CGFloat, animated: Bool = true, notifyDelegate: Bool = true) {
        guard let device = currentCaptureDevice else { return }
        let clampedDisplay = min(
            max(displayFactor, minDisplayZoomFactor),
            maxDisplayZoomFactor
        )
        let videoFactor = Self.videoZoom(forDisplayZoom: clampedDisplay, device: device)
        applyVideoZoomFactor(videoFactor, animated: animated, notifyDelegate: notifyDelegate)
    }

    private func applyVideoZoomFactor(_ videoFactor: CGFloat, animated: Bool = true, notifyDelegate: Bool = true) {
        guard let device = currentCaptureDevice else { return }

        let minVideo = device.minAvailableVideoZoomFactor
        let maxVideo = Self.videoZoom(forDisplayZoom: maxDisplayZoomFactor, device: device)
        let clampedVideo = min(max(videoFactor, minVideo), min(device.maxAvailableVideoZoomFactor, maxVideo))

        isApplyingZoomInternally = true
        defer { isApplyingZoomInternally = false }

        do {
            try device.lockForConfiguration()
            if animated {
                device.cancelVideoZoomRamp()
                device.ramp(toVideoZoomFactor: clampedVideo, withRate: 6.0)
            } else {
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = clampedVideo
            }
            device.unlockForConfiguration()
        } catch {
        }

        currentZoomFactor = Self.displayZoom(forVideoZoom: clampedVideo, device: device)
        if notifyDelegate {
            notifyZoomStateChanged()
        }
    }

    // ✅ SETUP GRID LINES
    private func setupGridLines() {
        gridLinesView = UIView(frame: view.bounds)
        gridLinesView?.backgroundColor = UIColor.clear
        gridLinesView?.isUserInteractionEnabled = false

        // Create grid lines
        let gridLayer = CALayer()

        // Vertical lines
        for i in 1...2 {
            let line = CALayer()
            line.backgroundColor = UIColor.white.withAlphaComponent(0.3).cgColor
            line.frame = CGRect(x: CGFloat(i) * view.bounds.width / 3, y: 0, width: 1, height: view.bounds.height)
            gridLayer.addSublayer(line)
        }

        // Horizontal lines
        for i in 1...2 {
            let line = CALayer()
            line.backgroundColor = UIColor.white.withAlphaComponent(0.3).cgColor
            line.frame = CGRect(x: 0, y: CGFloat(i) * view.bounds.height / 3, width: view.bounds.width, height: 1)
            gridLayer.addSublayer(line)
        }

        gridLinesView?.layer.addSublayer(gridLayer)
        gridLinesView?.isHidden = true

        if let gridView = gridLinesView {
            view.addSubview(gridView)
        }
    }

    // ✅ UPDATE GRID LINES VISIBILITY
    func updateGridLines(_ show: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.gridLinesView?.alpha = show ? 1.0 : 0.0
        }
        gridLinesView?.isHidden = !show
    }

    private func setupCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }

            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    if self.captureSession.canSetSessionPreset(.photo) {
                        self.captureSession.sessionPreset = .photo
                    } else {
                        self.captureSession.sessionPreset = .high
                    }
                    self.setupCameraInput(position: .back)
                    self.setupAudioInputIfAvailable()
                    self.setupOutputs()
                    self.setupPreviewLayer()
                    if self.captureSession.supportsControls {
                        self.captureSession.setControlsDelegate(self, queue: self.cameraControlQueue)
                    }

                    DispatchQueue.global(qos: .userInitiated).async {
                        self.captureSession.startRunning()
                    }
                }
            }
        }
    }

    private func setupCameraInput(position: AVCaptureDevice.Position) {
        guard let camera = preferredCaptureDevice(for: position) else {
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)

            captureSession.beginConfiguration()

            if let currentInput = currentCameraInput {
                captureSession.removeInput(currentInput)
            }

            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                currentCameraInput = input
                currentCaptureDevice = camera
                currentCameraPosition = position == .back ? .back : .front
                configureSystemZoomControl(for: camera)
                refreshLensPresets()
                setZoomFactor(1.0, animated: false)
                notifyZoomStateChanged()
            }

            captureSession.commitConfiguration()
        } catch {
        }
    }

    private func configureSystemZoomControl(for device: AVCaptureDevice) {
        systemZoomSlider = nil

        guard captureSession.supportsControls, device.position == .back else { return }

        for control in captureSession.controls {
            captureSession.removeControl(control)
        }

        let slider = AVCaptureSystemZoomSlider(device: device) { [weak self] videoZoom in
            guard let self, !self.isApplyingZoomInternally, let device = self.currentCaptureDevice else { return }
            let displayZoom = Self.displayZoom(forVideoZoom: videoZoom, device: device)
            DispatchQueue.main.async {
                self.currentZoomFactor = displayZoom
                self.notifyZoomStateChanged()
            }
        }

        if captureSession.canAddControl(slider) {
            captureSession.addControl(slider)
            systemZoomSlider = slider
        }
    }

    private func setupOutputs() {
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
    }

    private func setupAudioInputIfAvailable() {
        guard currentAudioInput == nil else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        guard let microphone = AVCaptureDevice.default(for: .audio) else { return }

        do {
            let audioInput = try AVCaptureDeviceInput(device: microphone)
            if captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
                currentAudioInput = audioInput
            }
        } catch {
        }
    }

    private func setupPreviewLayer() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.layer.bounds
        view.layer.addSublayer(previewLayer)
    }

    func switchCamera(to position: EnhancedCameraPickerView.CameraPosition) {
        let avPosition: AVCaptureDevice.Position = position == .back ? .back : .front
        setupCameraInput(position: avPosition)
    }

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()

        // Configure flash
        if cameraPosition == .back {
            switch flashMode {
            case .off:
                settings.flashMode = .off
            case .on:
                settings.flashMode = .on
            case .auto:
                settings.flashMode = .auto
            }
        }

        // Set orientation using iOS 17+ rotation angle API
        if let photoConnection = photoOutput.connection(with: .video) {
            let angle: CGFloat
            switch currentDeviceOrientation {
            case .portrait:           angle = 90
            case .portraitUpsideDown: angle = 270
            case .landscapeLeft:      angle = 0
            case .landscapeRight:     angle = 180
            default:                  angle = 90
            }
            if photoConnection.isVideoRotationAngleSupported(angle) {
                photoConnection.videoRotationAngle = angle
            }
            if photoConnection.isVideoMirroringSupported {
                photoConnection.isVideoMirrored = (currentCameraPosition == .front)
            }
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func visiblePreviewRect() -> CGRect {
        let topInset = view.safeAreaInsets.top
        let bottomInset = view.safeAreaInsets.bottom
        return momentsCaptureRect(in: view.bounds.size, topInset: topInset, bottomInset: bottomInset)
    }

    private func processedCapturedPhotoData(from imageData: Data) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }

        let normalizedImage = image.normalizedUp()
        let previewMatchedImage = cropImageToVisiblePreview(normalizedImage) ?? normalizedImage

        return previewMatchedImage.jpegData(compressionQuality: 0.95)
    }

    private func cropImageToVisiblePreview(_ image: UIImage) -> UIImage? {
        guard let previewLayer, let cgImage = image.cgImage else { return nil }

        let layerRect = visiblePreviewRect()
        guard layerRect.width > 0, layerRect.height > 0 else { return nil }

        let normalizedRect = previewLayer.metadataOutputRectConverted(fromLayerRect: layerRect)
        let imageRect = CGRect(
            x: normalizedRect.origin.x * CGFloat(cgImage.width),
            y: normalizedRect.origin.y * CGFloat(cgImage.height),
            width: normalizedRect.size.width * CGFloat(cgImage.width),
            height: normalizedRect.size.height * CGFloat(cgImage.height)
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard imageRect.width > 0, imageRect.height > 0,
              let croppedImage = cgImage.cropping(to: imageRect) else {
            return nil
        }

        return UIImage(cgImage: croppedImage, scale: image.scale, orientation: .up)
    }

    private func exportVideoMatchingVisiblePreview(from inputURL: URL, completion: @escaping (URL?) -> Void) {
        Task {
            let asset = AVURLAsset(url: inputURL)

            // Load tracks asynchronously (iOS 16+ API)
            guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
                await MainActor.run { completion(nil) }
                return
            }

            // Load duration, naturalSize, preferredTransform, nominalFrameRate asynchronously
            guard let duration = try? await asset.load(.duration) else {
                await MainActor.run { completion(nil) }
                return
            }
            let naturalSize       = (try? await videoTrack.load(.naturalSize))       ?? .zero
            let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
            let nominalFrameRate  = (try? await videoTrack.load(.nominalFrameRate))  ?? 30.0

            let composition = AVMutableComposition()
            guard let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                await MainActor.run { completion(nil) }
                return
            }

            do {
                try compositionVideoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero
                )
            } catch {
                await MainActor.run { completion(nil) }
                return
            }

            if let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
               let audioTrack = audioTracks.first,
               let compositionAudioTrack = composition.addMutableTrack(
                   withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                try? compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: .zero
                )
            }

            let transformedRect = CGRect(origin: .zero, size: naturalSize)
                .applying(preferredTransform).standardized
            let orientedSize = transformedRect.size
            let cropRect = momentsAspectRect(
                aspectRatio: momentsCaptureAspectRatio,
                in: CGRect(origin: .zero, size: orientedSize)
            ).integral

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            let translationToOrigin = CGAffineTransform(translationX: -transformedRect.origin.x, y: -transformedRect.origin.y)
            let cropTranslation     = CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y)
            let finalTransform = preferredTransform
                .concatenating(translationToOrigin)
                .concatenating(cropTranslation)
            layerInstruction.setTransform(finalTransform, at: .zero)

            instruction.layerInstructions = [layerInstruction]

            let videoComposition = AVMutableVideoComposition()
            videoComposition.instructions     = [instruction]
            videoComposition.renderSize       = cropRect.size
            videoComposition.frameDuration    = CMTime(
                value: 1, timescale: max(Int32(nominalFrameRate.rounded()), 30)
            )

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("camera_cropped_\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: outputURL)

            guard let exportSession = AVAssetExportSession(
                asset: composition, presetName: AVAssetExportPresetHighestQuality
            ) else {
                await MainActor.run { completion(nil) }
                return
            }

            exportSession.outputURL              = outputURL
            exportSession.outputFileType         = .mov
            exportSession.shouldOptimizeForNetworkUse = true
            exportSession.videoComposition       = videoComposition

            do {
                try await exportSession.export(to: outputURL, as: .mov)
                await MainActor.run { completion(outputURL) }
            } catch {
                await MainActor.run { completion(nil) }
            }
        }
    }

    func startVideoRecording() {
        guard !videoOutput.isRecording else { return }

        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let videoPath = "\(documentsPath)/temp_video_\(Date().timeIntervalSince1970).mov"
        let videoURL = URL(fileURLWithPath: videoPath)

        if let videoConnection = videoOutput.connection(with: .video) {
            let angle: CGFloat
            switch currentDeviceOrientation {
            case .portrait:           angle = 90
            case .portraitUpsideDown: angle = 270
            case .landscapeLeft:      angle = 0
            case .landscapeRight:     angle = 180
            default:                  angle = 90
            }
            if videoConnection.isVideoRotationAngleSupported(angle) {
                videoConnection.videoRotationAngle = angle
            }
            if videoConnection.isVideoMirroringSupported {
                videoConnection.isVideoMirrored = (currentCameraPosition == .front)
            }
        }

        videoOutput.startRecording(to: videoURL, recordingDelegate: self)
        delegate?.didChangeVideoRecordingState(true)
    }

    func stopVideoRecording() {
        guard videoOutput.isRecording else { return }
        videoOutput.stopRecording()
        delegate?.didChangeVideoRecordingState(false)
    }

    private func handleHardwareCapturePress() {
        switch captureMode {
        case .photo:
            capturePhoto()
        case .video:
            if videoOutput.isRecording {
                stopVideoRecording()
            } else {
                startVideoRecording()
            }
        }
    }
}

// MARK: - Camera Delegates
extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation() else {
            return
        }

        delegate?.didCapturePhoto(processedCapturedPhotoData(from: imageData) ?? imageData)
    }
}

extension CameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        delegate?.didChangeVideoRecordingState(false)

        if error != nil {
            return
        }

        // Ya no recortamos el video a 9:16 si se grabó en horizontal.
        // Pasamos el archivo directamente, ya que AVCaptureConnection ya orientó el video correctamente.
        do {
            let videoData = try Data(contentsOf: outputFileURL)
            delegate?.didCaptureVideo(videoData)
        } catch {
        }
    }
}

extension CameraViewController: AVCaptureSessionControlsDelegate {
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {}

    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {}

    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {}

    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {}
}

private extension UIImage {
    func normalizedUp() -> UIImage {
        if imageOrientation == .up { return self }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// ✅ CAMERA BUTTON STYLE
struct CameraButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
