import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import Photos

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
            ZStack {
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
                    cameraViewController: $cameraViewController
                )

                VStack(spacing: 0) {
                    if proxy.safeAreaInsets.top > 0 {
                        Rectangle()
                            .fill(safeAreaTintColor)
                            .frame(height: proxy.safeAreaInsets.top)
                    }

                    Spacer(minLength: 0)

                    if proxy.safeAreaInsets.bottom > 0 {
                        Rectangle()
                            .fill(safeAreaTintColor)
                            .frame(height: proxy.safeAreaInsets.bottom)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            
                VStack(spacing: 0) {
                    // ✅ TOP CONTROLS - Mejorados
                    topControlsBar

                    Spacer()

                    // ✅ MODE SELECTOR - Separado del capturador
                    modeSelector
                        .padding(.bottom, 18)

                    // ✅ BOTTOM CONTROLS - Rediseñados con galería funcional
                    bottomControlsBar
                }

                // ✅ EPHEMERAL MODE INDICATOR - Mejorado
                ephemeralModeIndicator

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
        .onChange(of: selectedItems) { items in
            handleSelectedMedia(items)
        }
        .onAppear {
            loadRecentGalleryPreview()
        }
    }

    private var topControlsBar: some View {
        VStack(spacing: 14) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background {
                            Color.clear
                                .liquidGlass(in: Circle(), interactive: true)
                        }
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }

                Spacer()

                HStack(spacing: 10) {
                    ephemeralHeaderToggle

                    if cameraPosition == .back && captureMode == .photo {
                        topCircleButton(icon: flashMode.icon, action: cycleFlashMode)
                    }

                    topCircleButton(icon: cameraPosition.icon, action: switchCamera)
                }
            }

        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var ephemeralHeaderToggle: some View {
        Button(action: { toggleEphemeralMode() }) {
            HStack(spacing: 6) {
                Image(systemName: isEphemeralMode ? "sparkles" : "eye")
                    .font(.system(size: 12, weight: .semibold))
                Text(isEphemeralMode ? NSLocalizedString("camera.mode.ephemeral", comment: "Ephemeral mode") : NSLocalizedString("camera.mode.normal", comment: "Normal mode"))
                    .font(.custom("Poppins-SemiBold", size: 11))
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
                            .liquidGlass(in: Capsule(), interactive: true)
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
                        .liquidGlass(in: Circle(), interactive: true)
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
                    .liquidGlass(in: Capsule(), interactive: true)
                    .shadow(color: .black.opacity(0.26), radius: 7, x: 0, y: 2)
                    .offset(x: modePillOffset)

                HStack(spacing: 0) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Text(mode.title)
                            .font(.custom("Poppins-Medium", size: 12))
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
    
    private var bottomControlsBar: some View {
        HStack(alignment: .bottom, spacing: 32) {
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
                            .liquidGlass(in: Circle(), interactive: true)
                    }
                    .overlay(
                        Circle()
                            .stroke(controlStrokeColor, lineWidth: 1)
                    )
            }
            .padding(.bottom, 16)
            
            EnhancedCaptureButton(
                captureMode: captureMode,
                isEphemeralMode: isEphemeralMode,
                isVideoRecording: $isVideoRecording,
                onCapture: handleCapture
            )
            
            Color.clear
                .frame(width: 48, height: 48)
                .padding(.bottom, 16)
        }
        .padding(.bottom, 42)
    }
    
    private var ephemeralModeIndicator: some View {
        VStack {
            if isEphemeralMode {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Text(NSLocalizedString("camera.ephemeral.deleteOnView", comment: "Ephemeral delete on view message"))
                        .font(.custom("Poppins-SemiBold", size: 12))
                }
                .foregroundColor(Color(hex: "FFCC33"))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    Color.clear
                        .liquidGlass(in: Capsule(), interactive: false)
                }
                .overlay(
                    Capsule()
                        .stroke(Color(hex: "FFCC33").opacity(0.45), lineWidth: 1)
                )
                .padding(.top, 132)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if isRecording && captureMode == .video {
                    Text(formatTime(recordingTime))
                        .font(.custom("Poppins-SemiBold", size: 14))
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
                        .fill(isEphemeralMode ? Color(hex: "FFCC33") : Color.white)
                        .frame(width: 96, height: 96)
                        .blur(radius: isCaptureActive ? 16 : 0)
                        .opacity(isCaptureActive ? 0.18 : 0)

                    Circle()
                        .stroke(
                            isEphemeralMode ? AnyShapeStyle(ephemeralGradient) : AnyShapeStyle(Color.white),
                            lineWidth: isCaptureActive ? 5 : 3
                        )
                        .frame(width: 88, height: 88)

                    Circle()
                        .fill(Color.white.opacity(isCaptureActive ? 0.1 : 0.16))
                        .frame(width: 78, height: 78)
                        .background {
                            Color.clear
                                .liquidGlass(in: Circle(), interactive: true)
                        }

                    Group {
                        if isRecording {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.red)
                                .frame(width: 28, height: 28)
                        } else {
                            Circle()
                                .fill(isEphemeralMode ? Color(hex: "FFCC33") : Color.white)
                                .frame(width: captureMode == .photo ? 62 : 54, height: captureMode == .photo ? 62 : 54)
                                .overlay {
                                    if captureMode == .video {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 18, height: 18)
                                    }
                                }
                        }
                    }
                    .scaleEffect(isCaptureActive ? 0.8 : 1.0)
                }
            }
        }
        .buttonStyle(CameraButtonStyle())
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isRecording)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isPhotoCaptureFeedback)
        .onChange(of: isRecording) { recording in
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

            ZStack {
                Group {
                    switch preview.mediaType {
                    case .image:
                        if let image = preview.image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else {
                            Color.black
                        }
                    case .video:
                        if let videoURL = preview.videoURL {
                            CameraPreviewVideoPlayer(url: videoURL)
                        } else {
                            Color.black
                        }
                    }
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    if topInset > 0 {
                        Rectangle()
                            .fill(safeAreaTintColor)
                            .frame(height: topInset)
                    }

                    Spacer(minLength: 0)

                    if bottomInset > 0 {
                        Rectangle()
                            .fill(safeAreaTintColor)
                            .frame(height: bottomInset)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    HStack {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 42, height: 42)
                                .background {
                                    Color.clear
                                        .liquidGlass(in: Circle(), interactive: true)
                                }
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    Spacer()

                    VStack(spacing: 10) {
                        if preview.isEphemeral {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(NSLocalizedString("camera.preview.ephemeralBadge", comment: "Ephemeral preview badge"))
                                    .font(.custom("Poppins-SemiBold", size: 11))
                            }
                            .foregroundColor(Color(hex: "FFCC33"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background {
                                Color.clear
                                    .liquidGlass(in: Capsule(), interactive: false)
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
                                        .font(.custom("Poppins-SemiBold", size: 13))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .frame(minWidth: 112)
                                .frame(height: 42)
                                .background {
                                    Color.clear
                                        .liquidGlass(in: Capsule(), interactive: true)
                                }
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                            }

                            Spacer(minLength: 0)

                            Button(action: onSend) {
                                HStack(spacing: 6) {
                                    Image(systemName: preview.isEphemeral ? "sparkles" : "paperplane.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(NSLocalizedString("camera.preview.send", comment: "Send media"))
                                        .font(.custom("Poppins-SemiBold", size: 13))
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
                                                .liquidGlass(in: Capsule(), interactive: true)
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

private struct CameraPreviewVideoPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.configure(url: url)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.configure(url: url)
    }
}

private final class PlayerContainerView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playbackObserver: NSObjectProtocol?
    private var currentURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(togglePlayback))
        addGestureRecognizer(tapGesture)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(togglePlayback))
        addGestureRecognizer(tapGesture)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    func configure(url: URL) {
        guard currentURL != url else { return }
        cleanup()

        currentURL = url
        let player = AVPlayer(url: url)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.addSublayer(layer)

        playbackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        self.player = player
        self.playerLayer = layer
        player.play()
    }

    @objc
    private func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    private func cleanup() {
        player?.pause()
        if let playbackObserver {
            NotificationCenter.default.removeObserver(playbackObserver)
            self.playbackObserver = nil
        }
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
        currentURL = nil
    }

    deinit {
        cleanup()
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
    @Binding var cameraViewController: CameraViewController?
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        
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
        
        context.coordinator.updateEphemeralMode(isEphemeralMode)
        
        // Update camera if position changed
        if uiViewController.currentCameraPosition != cameraPosition {
            uiViewController.switchCamera(to: cameraPosition)
        }
        
        // Update grid lines
        uiViewController.updateGridLines(showGridLines)
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
    }
}

// ✅ CAMERA VIEW CONTROLLER - MEJORADO CON GRID LINES
protocol CameraViewControllerDelegate: AnyObject {
    func didCapturePhoto(_ data: Data)
    func didCaptureVideo(_ data: Data)
    func didChangeVideoRecordingState(_ isRecording: Bool)
}

class CameraViewController: UIViewController {
    weak var delegate: CameraViewControllerDelegate?
    var captureMode: EnhancedCameraPickerView.CaptureMode = .photo
    var cameraPosition: EnhancedCameraPickerView.CameraPosition = .back
    var flashMode: EnhancedCameraPickerView.FlashMode = .off
    var isEphemeralMode: Bool = false
    var currentCameraPosition: EnhancedCameraPickerView.CameraPosition = .back
    var showGridLines: Bool = false // ✅ Nuevo
    
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    let videoOutput = AVCaptureMovieFileOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var currentCameraInput: AVCaptureDeviceInput?
    private var currentAudioInput: AVCaptureDeviceInput?
    private var gridLinesView: UIView? // ✅ Grid lines overlay
    private var captureEventInteraction: AVCaptureEventInteraction?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupGridLines() // ✅ Setup grid lines
        configureHardwareCaptureInteraction()
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
                    self.captureSession.sessionPreset = .high
                    self.setupCameraInput(position: .back)
                    self.setupAudioInputIfAvailable()
                    self.setupOutputs()
                    self.setupPreviewLayer()

                    DispatchQueue.global(qos: .userInitiated).async {
                        self.captureSession.startRunning()
                    }
                }
            }
        }
    }
    
    private func setupCameraInput(position: AVCaptureDevice.Position) {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            
            if let currentInput = currentCameraInput {
                captureSession.removeInput(currentInput)
            }
            
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                currentCameraInput = input
                currentCameraPosition = position == .back ? .back : .front
            }
        } catch {
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
        
        // Set orientation
        if let photoConnection = photoOutput.connection(with: .video) {
            let orientation = UIDevice.current.orientation
            let videoOrientation: AVCaptureVideoOrientation = {
                switch orientation {
                case .portrait: return .portrait
                case .portraitUpsideDown: return .portraitUpsideDown
                case .landscapeLeft: return .landscapeRight
                case .landscapeRight: return .landscapeLeft
                default: return .portrait
                }
            }()
            
            if photoConnection.isVideoOrientationSupported {
                photoConnection.videoOrientation = videoOrientation
            }
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func startVideoRecording() {
        guard !videoOutput.isRecording else { return }
        
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let videoPath = "\(documentsPath)/temp_video_\(Date().timeIntervalSince1970).mov"
        let videoURL = URL(fileURLWithPath: videoPath)
        
        if let videoConnection = videoOutput.connection(with: .video) {
            let orientation = UIDevice.current.orientation
            let videoOrientation: AVCaptureVideoOrientation = {
                switch orientation {
                case .portrait: return .portrait
                case .portraitUpsideDown: return .portraitUpsideDown
                case .landscapeLeft: return .landscapeRight
                case .landscapeRight: return .landscapeLeft
                default: return .portrait
                }
            }()
            
            if videoConnection.isVideoOrientationSupported {
                videoConnection.videoOrientation = videoOrientation
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
        
        delegate?.didCapturePhoto(imageData)
    }
}

extension CameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        delegate?.didChangeVideoRecordingState(false)

        if let error = error {
            return
        }
        
        do {
            let videoData = try Data(contentsOf: outputFileURL)
            delegate?.didCaptureVideo(videoData)
            
            try FileManager.default.removeItem(at: outputFileURL)
        } catch {
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
