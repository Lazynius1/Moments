import SwiftUI
import AVFoundation
import AVKit
import UIKit

struct CameraPreviewRepresentable: UIViewRepresentable {
    @Binding var cameraPosition: AVCaptureDevice.Position
    @Binding var flashMode: AVCaptureDevice.FlashMode
    @Binding var isRecording: Bool
    @Binding var zoomLevel: CGFloat
    @Binding var capturePhotoTrigger: Bool
    var deviceOrientation: UIDeviceOrientation
    let onImageCaptured: (UIImage) -> Void
    let onVideoCaptured: (URL) -> Void

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView(frame: .zero)
        view.delegate = context.coordinator
        view.updateDeviceOrientation(deviceOrientation)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.updateCameraPosition(cameraPosition)
        uiView.updateFlashMode(flashMode)
        uiView.updateZoom(zoomLevel)
        uiView.updateDeviceOrientation(deviceOrientation)

        if capturePhotoTrigger {
            uiView.capturePhoto()
            DispatchQueue.main.async {
                capturePhotoTrigger = false
            }
        }

        if isRecording && !uiView.isCurrentlyRecording {
            uiView.startRecording()
        } else if !isRecording && uiView.isCurrentlyRecording {
            uiView.stopRecording()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
        var parent: CameraPreviewRepresentable

        init(_ parent: CameraPreviewRepresentable) {
            self.parent = parent
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            guard let imageData = photo.fileDataRepresentation(),
                  let image = UIImage(data: imageData) else { return }
            parent.onImageCaptured(image)
        }

        func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
            parent.onVideoCaptured(outputFileURL)
        }
    }
}

class CameraPreviewView: UIView {
    weak var delegate: CameraPreviewRepresentable.Coordinator?

    private var captureSession: AVCaptureSession?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var currentCamera: AVCaptureDevice?
    private var currentCameraInput: AVCaptureDeviceInput?
    private var currentAudioInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var currentFlashMode: AVCaptureDevice.FlashMode = .off
    private var currentZoom: CGFloat = 1.0
    private var captureEventInteraction: AVCaptureEventInteraction?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var currentDeviceOrientation: UIDeviceOrientation = .portrait

    var isCurrentlyRecording: Bool {
        return movieOutput?.isRecording ?? false
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHardwareCaptureInteraction()
        setupCamera()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureHardwareCaptureInteraction()
        setupCamera()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer?.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
    }

    private func configureHardwareCaptureInteraction() {
        let interaction = AVCaptureEventInteraction { [weak self] event in
            guard event.phase == .ended else { return }
            self?.handleHardwareCapturePress()
        }
        addInteraction(interaction)
        captureEventInteraction = interaction
    }

    private func setupCamera() {
        // Request camera permission first
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else {
                return
            }

            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.global(qos: .userInitiated).async {
                    self?.configureCaptureSession()
                }
            }
        }
    }

    private func configureCaptureSession() {
        guard captureSession == nil else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .high

        // Setup camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }

        currentCamera = camera
        currentCameraInput = input

        if session.canAddInput(input) {
            session.addInput(input)
        }

        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let microphone = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
            currentAudioInput = audioInput
        }

        // Setup photo output
        let photoOutput = AVCapturePhotoOutput()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            self.photoOutput = photoOutput
        }

        // Setup video output
        let movieOutput = AVCaptureMovieFileOutput()
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)

            // Configure video settings
            if let connection = movieOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }

            self.movieOutput = movieOutput
        }

        self.captureSession = session

        // ✅ UI setup en main thread
        DispatchQueue.main.async { [weak self] in
            self?.setupPreviewLayer()

            // ✅ Heavy camera operation en background thread
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }

    private func setupPreviewLayer() {
        guard let session = captureSession else { return }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = bounds
        previewLayer.videoGravity = .resizeAspectFill

        layer.addSublayer(previewLayer)
        self.videoPreviewLayer = previewLayer
        if let camera = currentCamera {
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: previewLayer)
        }
        configurePreviewConnection()
    }

    func updateCameraPosition(_ position: AVCaptureDevice.Position) {
        guard position != currentPosition else { return }
        currentPosition = position

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.switchCamera(to: position)
        }
    }

    private func switchCamera(to position: AVCaptureDevice.Position) {
        guard let session = captureSession else { return }

        session.beginConfiguration()

        // Remove current input
        if let currentInput = currentCameraInput {
            session.removeInput(currentInput)
        }

        // Add new input
        guard let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let newInput = try? AVCaptureDeviceInput(device: newCamera) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(newInput) {
            session.addInput(newInput)
            currentCamera = newCamera
            currentCameraInput = newInput
        }

        session.commitConfiguration()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                device: newCamera,
                previewLayer: self.videoPreviewLayer
            )
            self.configurePreviewConnection()
        }

        // Reset zoom
        currentZoom = 1.0
        updateCameraZoom(1.0)
    }

    private func configurePreviewConnection() {
        guard let previewConnection = videoPreviewLayer?.connection else { return }
        applyRotation(to: previewConnection, forPreview: true)
        if previewConnection.isVideoMirroringSupported {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            previewConnection.isVideoMirrored = (currentPosition == .front)
        }
    }

    func updateFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        currentFlashMode = mode
    }

    func updateDeviceOrientation(_ orientation: UIDeviceOrientation) {
        guard orientation.isValidInterfaceOrientation,
              orientation != currentDeviceOrientation else {
            return
        }

        currentDeviceOrientation = orientation
        configurePreviewConnection()
    }

    func updateZoom(_ level: CGFloat) {
        guard abs(level - currentZoom) > 0.1 else { return }
        currentZoom = level
        updateCameraZoom(level)
    }

    private func updateCameraZoom(_ level: CGFloat) {
        guard let camera = currentCamera else { return }

        do {
            try camera.lockForConfiguration()
            let maxZoom = min(camera.activeFormat.videoMaxZoomFactor, 5.0)
            camera.videoZoomFactor = min(max(level, 1.0), maxZoom)
            camera.unlockForConfiguration()
        } catch {
        }
    }

    func capturePhoto() {
        guard let photoOutput = photoOutput else { return }

        // ✅ CONFIGURACIÓN SEGURA DE ALTA CALIDAD
        let settings = AVCapturePhotoSettings()

        // ✅ VERIFICAR Y CONFIGURAR CALIDAD SEGÚN LOS LÍMITES DEL DISPOSITIVO
        if #available(iOS 13.0, *) {
            let maxQuality = photoOutput.maxPhotoQualityPrioritization

            // Solo usar la calidad que el dispositivo permite
            if maxQuality == .quality {
                settings.photoQualityPrioritization = .quality
            } else if maxQuality == .balanced {
                settings.photoQualityPrioritization = .balanced
            } else {
                settings.photoQualityPrioritization = .speed
            }
        }

        settings.flashMode = currentFlashMode

        if let photoConnection = photoOutput.connection(with: .video) {
            applyRotation(to: photoConnection, forPreview: false)
            if photoConnection.isVideoMirroringSupported {
                photoConnection.automaticallyAdjustsVideoMirroring = false
                photoConnection.isVideoMirrored = (currentPosition == .front)
            }
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func startRecording() {
        guard let movieOutput = movieOutput,
              !movieOutput.isRecording else { return }

        if let videoConnection = movieOutput.connection(with: .video) {
            applyRotation(to: videoConnection, forPreview: false)
            if videoConnection.isVideoMirroringSupported {
                videoConnection.automaticallyAdjustsVideoMirroring = false
                videoConnection.isVideoMirrored = (currentPosition == .front)
            }
        }

        let outputURL = createTempVideoURL()
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
    }

    func stopRecording() {
        guard let movieOutput = movieOutput,
              movieOutput.isRecording else { return }

        movieOutput.stopRecording()
    }

    private func handleHardwareCapturePress() {
        if isCurrentlyRecording {
            stopRecording()
        } else {
            capturePhoto()
        }
    }

    private func createTempVideoURL() -> URL {
        let documentsPath = FileManager.default.temporaryDirectory
        let fileName = "story_video_\(Date().timeIntervalSince1970).mov"
        return documentsPath.appendingPathComponent(fileName)
    }

    private func applyRotation(to connection: AVCaptureConnection, forPreview: Bool) {
        let rotationAngle: CGFloat
        if #available(iOS 17.0, *), let rotationCoordinator {
            rotationAngle = forPreview
                ? rotationCoordinator.videoRotationAngleForHorizonLevelPreview
                : rotationCoordinator.videoRotationAngleForHorizonLevelCapture
        } else {
            rotationAngle = fallbackVideoRotationAngle()
        }

        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
    }

    private func fallbackVideoRotationAngle() -> CGFloat {
        switch currentDeviceOrientation {
        case .portrait: return 90.0
        case .portraitUpsideDown: return 270.0
        case .landscapeLeft: return 0.0
        case .landscapeRight: return 180.0
        default: return 90.0
        }
    }

    private func cropImageToVisiblePreview(_ image: UIImage) -> UIImage? {
        guard let previewLayer = videoPreviewLayer, let cgImage = image.cgImage else { return nil }

        let guideRect = creatorMomentsAspectRect(aspectRatio: creatorMomentsCaptureAspectRatio, in: bounds)
        let normalizedRect = previewLayer.metadataOutputRectConverted(fromLayerRect: guideRect)
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
}
extension CameraPreviewView: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            return
        }

        // Correct orientation for front camera
        let correctedImage = correctImageOrientation(image)
        let normalizedImage = correctedImage.creatorNormalizedUp()
        let previewMatchedImage = cropImageToVisiblePreview(normalizedImage) ?? normalizedImage

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.parent.onImageCaptured(previewMatchedImage)
        }
    }

    private func correctImageOrientation(_ image: UIImage) -> UIImage {
        if currentPosition == .front {
            // Flip horizontally for front camera
            return UIImage(cgImage: image.cgImage!, scale: image.scale, orientation: .leftMirrored)
        }
        return image
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension CameraPreviewView: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if error != nil {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.parent.onVideoCaptured(outputFileURL)
        }
    }
}
