import SwiftUI
import AVFoundation
import Photos
import UIKit

// MARK: - Story Camera View
struct StoryCameraView: View {
    @Binding var selectedMediaItems: [CreatorMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool
    @Binding var startsInTextMode: Bool

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
    @State private var centerStageEnabled = true
    @State private var centerStageAvailable = false
    @State private var lastGalleryImage: UIImage?
    @StateObject private var orientationManager = OrientationManager.shared
    @StateObject private var cameraKit = CameraKitController()
    @State private var usingCameraKit = false

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
        CameraAccessBoundary(requiresMicrophone: true, onCancel: { currentFlow = .typeSelection }) {
            cameraContent
        }
    }

    private var cameraContent: some View {
        GeometryReader { proxy in
            let captureRect = creatorMomentsCaptureRect(in: proxy.size, topInset: proxy.safeAreaInsets.top, bottomInset: proxy.safeAreaInsets.bottom)
            // Separación extra respecto al LensReel (100pt de alto, con un UICollectionView de ancho completo
            // que puede robar toques aunque esté vacío visualmente) para que la galería/cambio de cámara no queden pegados a su zona táctil.
            let controlY = min(proxy.size.height - proxy.safeAreaInsets.bottom - 20, captureRect.maxY + 104)
            let captureButtonY = captureRect.maxY - 10

            ZStack {
                safeAreaTintColor
                    .ignoresSafeArea()

                // Camera preview: tu cámara nativa por defecto; Camera Kit solo cuando hay lente activa.
                Group {
                    if usingCameraKit {
                        CameraKitPreviewRepresentable(
                            previewView: cameraKit.previewView,
                            canvasSize: captureRect.size,
                            onViewportUpdate: { size in
                            cameraKit.updateViewport(forCanvasSize: size)
                            }
                        )
                    } else {
                        CameraPreviewRepresentable(
                            cameraPosition: $cameraPosition,
                            flashMode: $flashMode,
                            isRecording: $isRecording,
                            zoomLevel: $zoomLevel,
                            capturePhotoTrigger: $capturePhotoTrigger,
                            centerStageEnabled: $centerStageEnabled,
                            centerStageAvailable: $centerStageAvailable,
                            prefersMaximumCaptureQuality: true,
                            enablesCenterStageControls: true,
                            deviceOrientation: deviceOrientation,
                            onImageCaptured: { image in handleCapturedImage(image) },
                            onVideoCaptured: { videoURL in handleCapturedVideo(videoURL) }
                        )
                    }
                }
                .frame(width: captureRect.width, height: captureRect.height)
                .clipShape(RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous))
                .position(x: captureRect.midX, y: captureRect.midY)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let newZoom = lastZoomLevel * value.magnification
                            zoomLevel = min(max(newZoom, 1.0), 5.0)
                            if usingCameraKit { cameraKit.setZoom(zoomLevel) }
                        }
                        .onEnded { value in
                            lastZoomLevel = zoomLevel
                        }
                )

                topControlsOverlay
                    .frame(width: captureRect.width, height: captureRect.height, alignment: .top)
                    .position(x: captureRect.midX, y: captureRect.midY)

                textModeButtonOverlay
                    .position(x: captureRect.maxX - 26, y: captureRect.midY)

                // Bottom controls
                recordingStatusView
                    .position(x: captureRect.midX, y: captureRect.maxY - 108)

                bottomSideControls
                    .frame(width: min(captureRect.width + 54, proxy.size.width - 72))
                    .position(x: captureRect.midX, y: controlY)
                    // Prioridad de toque sobre el UICollectionView de LensReel (ancho completo, declarado después),
                    // que puede robar toques en el margen entre ambos aunque no tenga contenido visible ahí.
                    .zIndex(1)

                // Filtros AR desactivados mientras solo haya lentes demo (ver SnapCameraKitConfiguration.isFeatureEnabled).
                // LensReel siempre se muestra: incluye el botón de disparo (overlay), no solo el carrusel de lentes.
                // Con el flag desactivado, cameraKit.lenses queda vacío (prepareLenses() no llega a cargarlas),
                // así que el carrusel solo ofrece "sin filtro" y el disparador sigue funcionando con la cámara nativa.
                LensReel(
                    lenses: SnapCameraKitConfiguration.isFeatureEnabled ? cameraKit.lenses : [],
                    isRecording: $isRecording,
                    onSelect: { lens in
                        guard SnapCameraKitConfiguration.isFeatureEnabled else { return }
                        if let lens {
                            if usingCameraKit {
                                cameraKit.selectLens(lens)
                            } else {
                                // Sin filtro -> con filtro: ocultar nativa (se para sola) y encender CK, aplicando la lente al arrancar.
                                usingCameraKit = true
                                cameraKit.activateCamera(applyingLens: lens)
                            }
                        } else {
                            // Volver a "sin filtro": apagar CK y volver a la cámara nativa.
                            cameraKit.selectLens(nil)
                            cameraKit.deactivateCamera()
                            usingCameraKit = false
                        }
                    },
                    onCapturePhoto: { takePhoto() },
                    onStartVideo: { startRecording() },
                    onStopVideo: { stopRecording() }
                )
                .frame(width: captureRect.width)
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
            cameraKit.onCapturedPhoto = { image in handleCapturedImage(image) }
            cameraKit.onCapturedVideo = { url in handleCapturedVideo(url) }
            cameraKit.prepareLenses()
        }
        .onDisappear {
            stopRecording()
            orientationManager.stopTracking()
            cameraKit.stop()
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
            HStack(spacing: 10) {
                roundControlButton(systemImage: "xmark", action: {
                    showCreatorView = false
                })
                .rotationEffect(.degrees(rotationAngle))
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: rotationAngle), value: rotationAngle)

                Spacer()

                if cameraPosition == .front && centerStageAvailable {
                    roundControlButton(
                        systemImage: centerStageEnabled
                            ? "person.fill.viewfinder"
                            : "person.crop.rectangle",
                        action: {
                            centerStageEnabled.toggle()
                        }
                    )
                    .rotationEffect(.degrees(rotationAngle))
                    .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: rotationAngle), value: rotationAngle)
                    .accessibilityLabel(
                        NSLocalizedString(
                            centerStageEnabled
                                ? "creator.camera.centerStage.on"
                                : "creator.camera.centerStage.off",
                            comment: "Center Stage accessibility"
                        )
                    )
                }

                roundControlButton(systemImage: flashIcon, action: {
                    toggleFlash()
                })
                .rotationEffect(.degrees(rotationAngle))
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: rotationAngle), value: rotationAngle)
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
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .frame(height: 36)
    }

    private var bottomSideControls: some View {
        HStack {
            galleryButton
                .rotationEffect(.degrees(rotationAngle))
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: rotationAngle), value: rotationAngle)

            Spacer()

            switchCameraButton
                .rotationEffect(.degrees(rotationAngle))
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: rotationAngle), value: rotationAngle)
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

    private var textModeButtonOverlay: some View {
        Button(action: openTextStoryMode) {
            Text("Aa")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(topControlForegroundColor)
                .frame(width: 48, height: 48)
                .background {
                    Color.clear
                        .momentsChromeGlass(in: Circle(), interactive: true, style: .tinted)
                }
                .overlay(
                    Circle()
                        .stroke(topControlStrokeColor, lineWidth: 1)
                )
        }
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
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .background {
                    Color.clear
                        .momentsChromeGlass(in: Circle(), interactive: true, style: .tinted)
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
                .foregroundStyle(topControlForegroundColor)
                .frame(width: 48, height: 48)
                .background {
                    Color.clear
                        .momentsChromeGlass(in: Circle(), interactive: true, style: .tinted)
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
                .foregroundStyle(topControlForegroundColor)
                .frame(width: 42, height: 42)
                .background {
                    Color.clear
                        .momentsChromeGlass(in: Circle(), interactive: true, style: .tinted)
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
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
            cameraPosition = cameraPosition == .back ? .front : .back
            // Reset zoom when switching cameras
            zoomLevel = 1.0
            lastZoomLevel = 1.0
            if cameraPosition == .back {
                centerStageAvailable = false
            } else {
                // Default ON al entrar a frontal; la preview confirmará si el hardware lo soporta.
                centerStageEnabled = true
            }
        }
        if usingCameraKit {
            cameraKit.setCameraPosition(cameraPosition)
            cameraKit.setZoom(1.0)
        }
    }

    private func takePhoto() {
        if usingCameraKit {
            cameraKit.capturePhoto()
        } else {
            capturePhotoTrigger.toggle()
        }
    }

    private func startRecording() {
        isRecording = true
        recordingDuration = 0
        startRecordingTimer()
        if usingCameraKit { cameraKit.startRecording() }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        if usingCameraKit { cameraKit.stopRecording() }
    }

    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingDuration += 0.1
            // Tope real del auto-split (5 partes × 60s); pasar de 60s ya no corta,
            // el vídeo se publica dividido en partes automáticamente.
            if recordingDuration >= StoryVideoProcessingService.maxAutoSplitDuration {
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
        Task {
            await MomentsAudioSession.activate(category: .playAndRecord, mode: .videoRecording)
        }
    }

    private func handleCapturedImage(_ image: UIImage) {
        startsInTextMode = false
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
                let videoDuration = (try? await StoryVideoProcessingService.shared.duration(for: videoURL)) ?? 0

                let detectedRatio = CreatorMedia.AspectRatio.fromRatio(thumbnail.size.width / thumbnail.size.height)
                let needsAutoSplit = videoDuration > StoryVideoProcessingService.maxStorySegmentDuration

                await MainActor.run {
                    startsInTextMode = false
                    let processedMedia = CreatorMedia(
                        id: UUID().uuidString,
                        image: thumbnail,
                        videoURL: videoURL,
                        type: .video,
                        aspectRatio: detectedRatio,
                        recommendedAspectRatio: detectedRatio,
                        storyVideoMode: needsAutoSplit ? .autoSplit : .normal,
                        videoDuration: videoDuration > 0 ? videoDuration : nil
                    )
                    selectedMediaItems = [processedMedia]
                    currentFlow = .storyEditing
                }
            } catch {
            }
        }
    }

    private func openTextStoryMode() {
        startsInTextMode = true
        selectedMediaItems = []
        currentFlow = .storyEditing
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
