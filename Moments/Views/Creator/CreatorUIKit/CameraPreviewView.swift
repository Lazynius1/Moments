import SwiftUI
import AVFoundation
import AVKit
import UIKit
import CoreMedia

struct CameraPreviewRepresentable: UIViewRepresentable {
    @Binding var cameraPosition: AVCaptureDevice.Position
    @Binding var flashMode: AVCaptureDevice.FlashMode
    @Binding var isRecording: Bool
    @Binding var zoomLevel: CGFloat
    @Binding var capturePhotoTrigger: Bool
    @Binding var centerStageEnabled: Bool
    @Binding var centerStageAvailable: Bool
    /// Creator: máxima calidad. Chat: false (preset `.high`, sin maxPhotoDimensions).
    var prefersMaximumCaptureQuality: Bool
    /// Solo Creator: Center Stage cooperative + callbacks de UI.
    var enablesCenterStageControls: Bool
    var deviceOrientation: UIDeviceOrientation
    let onImageCaptured: (UIImage) -> Void
    let onVideoCaptured: (URL) -> Void

    init(
        cameraPosition: Binding<AVCaptureDevice.Position>,
        flashMode: Binding<AVCaptureDevice.FlashMode>,
        isRecording: Binding<Bool>,
        zoomLevel: Binding<CGFloat>,
        capturePhotoTrigger: Binding<Bool>,
        centerStageEnabled: Binding<Bool> = .constant(false),
        centerStageAvailable: Binding<Bool> = .constant(false),
        prefersMaximumCaptureQuality: Bool = false,
        enablesCenterStageControls: Bool = false,
        deviceOrientation: UIDeviceOrientation,
        onImageCaptured: @escaping (UIImage) -> Void,
        onVideoCaptured: @escaping (URL) -> Void
    ) {
        self._cameraPosition = cameraPosition
        self._flashMode = flashMode
        self._isRecording = isRecording
        self._zoomLevel = zoomLevel
        self._capturePhotoTrigger = capturePhotoTrigger
        self._centerStageEnabled = centerStageEnabled
        self._centerStageAvailable = centerStageAvailable
        self.prefersMaximumCaptureQuality = prefersMaximumCaptureQuality
        self.enablesCenterStageControls = enablesCenterStageControls
        self.deviceOrientation = deviceOrientation
        self.onImageCaptured = onImageCaptured
        self.onVideoCaptured = onVideoCaptured
    }

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView(
            frame: .zero,
            prefersMaximumCaptureQuality: prefersMaximumCaptureQuality,
            enablesCenterStageControls: enablesCenterStageControls
        )
        view.delegate = context.coordinator
        bindCenterStageCallbacks(to: view)
        view.updateDeviceOrientation(deviceOrientation)
        if enablesCenterStageControls {
            view.updateCenterStageEnabled(centerStageEnabled)
        }
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.delegate = context.coordinator
        uiView.prefersMaximumCaptureQuality = prefersMaximumCaptureQuality
        uiView.enablesCenterStageControls = enablesCenterStageControls
        bindCenterStageCallbacks(to: uiView)
        uiView.updateCameraPosition(cameraPosition)
        uiView.updateFlashMode(flashMode)
        uiView.updateZoom(zoomLevel)
        uiView.updateDeviceOrientation(deviceOrientation)
        if enablesCenterStageControls {
            uiView.updateCenterStageEnabled(centerStageEnabled)
        }

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

    private func bindCenterStageCallbacks(to view: CameraPreviewView) {
        guard enablesCenterStageControls else {
            view.onCenterStageAvailabilityChange = nil
            view.onCenterStageEnabledChangeFromSystem = nil
            return
        }
        view.onCenterStageAvailabilityChange = { available in
            DispatchQueue.main.async {
                if centerStageAvailable != available {
                    centerStageAvailable = available
                }
            }
        }
        view.onCenterStageEnabledChangeFromSystem = { enabled in
            DispatchQueue.main.async {
                if centerStageEnabled != enabled {
                    centerStageEnabled = enabled
                }
            }
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
    var onCenterStageAvailabilityChange: ((Bool) -> Void)?
    var onCenterStageEnabledChangeFromSystem: ((Bool) -> Void)?
    var prefersMaximumCaptureQuality: Bool
    var enablesCenterStageControls: Bool

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
    private var desiredCenterStageEnabled = true
    private var captureEventInteraction: AVCaptureEventInteraction?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var currentDeviceOrientation: UIDeviceOrientation = .portrait
    private var isObservingCenterStageEnabled = false
    private let centerStageEnabledKeyPath = "centerStageEnabled"

    var isCurrentlyRecording: Bool {
        return movieOutput?.isRecording ?? false
    }

    init(
        frame: CGRect,
        prefersMaximumCaptureQuality: Bool = false,
        enablesCenterStageControls: Bool = false
    ) {
        self.prefersMaximumCaptureQuality = prefersMaximumCaptureQuality
        self.enablesCenterStageControls = enablesCenterStageControls
        super.init(frame: frame)
        configureHardwareCaptureInteraction()
        setupCamera()
    }

    required init?(coder: NSCoder) {
        self.prefersMaximumCaptureQuality = false
        self.enablesCenterStageControls = false
        super.init(coder: coder)
        configureHardwareCaptureInteraction()
        setupCamera()
    }

    deinit {
        stopObservingCenterStageEnabled()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer?.frame = bounds
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
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }

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
        applySessionPreset(to: session)

        guard let camera = captureDevice(for: currentPosition),
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

        let photoOutput = AVCapturePhotoOutput()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            self.photoOutput = photoOutput
        }

        let movieOutput = AVCaptureMovieFileOutput()
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)

            if let connection = movieOutput.connection(with: .video),
               connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }

            self.movieOutput = movieOutput
        }

        if prefersMaximumCaptureQuality {
            applyMaxPhotoDimensions(for: camera)
        }

        self.captureSession = session

        if enablesCenterStageControls {
            applyCenterStageConfiguration(for: camera, position: currentPosition)
            observeCenterStageEnabledChanges()
        }

        DispatchQueue.main.async { [weak self] in
            self?.setupPreviewLayer()

            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }

    /// iPhone 17+ Center Stage frontal = `.builtInUltraWideCamera`, no la wide normal.
    private func captureDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .front, enablesCenterStageControls {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera],
                mediaType: .video,
                position: .front
            )
            if let ultraWideFront = discovery.devices.first {
                return ultraWideFront
            }
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func applySessionPreset(to session: AVCaptureSession) {
        guard prefersMaximumCaptureQuality else {
            session.sessionPreset = .high
            return
        }
        let preferred: [AVCaptureSession.Preset] = [
            .hd4K3840x2160,
            .photo,
            .high
        ]
        for preset in preferred where session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
            return
        }
        session.sessionPreset = .high
    }

    private func applyMaxPhotoDimensions(for camera: AVCaptureDevice) {
        guard let photoOutput else { return }
        let dimensions = Self.largestPhotoDimensions(in: camera.activeFormat.supportedMaxPhotoDimensions)
        guard dimensions.width > 0, dimensions.height > 0 else { return }
        photoOutput.maxPhotoDimensions = dimensions
    }

    private static func largestPhotoDimensions(in values: [CMVideoDimensions]) -> CMVideoDimensions {
        values.max { lhs, rhs in
            Int(lhs.width) * Int(lhs.height) < Int(rhs.width) * Int(rhs.height)
        } ?? CMVideoDimensions(width: 0, height: 0)
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

        if let currentInput = currentCameraInput {
            session.removeInput(currentInput)
        }

        guard let newCamera = captureDevice(for: position),
              let newInput = try? AVCaptureDeviceInput(device: newCamera) else {
            session.commitConfiguration()
            publishCenterStageAvailability(false)
            return
        }

        if session.canAddInput(newInput) {
            session.addInput(newInput)
            currentCamera = newCamera
            currentCameraInput = newInput
        }

        applySessionPreset(to: session)
        if prefersMaximumCaptureQuality {
            applyMaxPhotoDimensions(for: newCamera)
        }
        if enablesCenterStageControls {
            applyCenterStageConfiguration(for: newCamera, position: position)
        } else {
            publishCenterStageAvailability(false)
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

        currentZoom = 1.0
        updateCameraZoom(1.0)
    }

    func updateCenterStageEnabled(_ enabled: Bool) {
        desiredCenterStageEnabled = enabled
        guard enablesCenterStageControls,
              currentPosition == .front,
              let camera = currentCamera,
              camera.activeFormat.isCenterStageSupported else {
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setCenterStageEnabled(enabled)
        }
    }

    private func applyCenterStageConfiguration(for camera: AVCaptureDevice, position: AVCaptureDevice.Position) {
        guard enablesCenterStageControls else {
            publishCenterStageAvailability(false)
            return
        }
        guard position == .front else {
            disableCenterStageIfNeeded()
            publishCenterStageAvailability(false)
            return
        }

        let hasCenterStageFormat = camera.formats.contains(where: \.isCenterStageSupported)
        guard hasCenterStageFormat else {
            disableCenterStageIfNeeded()
            publishCenterStageAvailability(false)
            return
        }

        preferCenterStageFormatIfNeeded(on: camera, session: captureSession)

        let supported = camera.activeFormat.isCenterStageSupported
        publishCenterStageAvailability(supported)
        guard supported else {
            disableCenterStageIfNeeded()
            return
        }

        AVCaptureDevice.centerStageControlMode = .cooperative
        setCenterStageEnabled(desiredCenterStageEnabled)
    }

    private func preferCenterStageFormatIfNeeded(on camera: AVCaptureDevice, session: AVCaptureSession?) {
        let candidates = camera.formats.filter(\.isCenterStageSupported)
        guard !candidates.isEmpty else { return }

        let withThirtyFPS = candidates.filter { format in
            format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 29.0 }
        }
        let pool = withThirtyFPS.isEmpty ? candidates : withThirtyFPS

        guard let best = pool.max(by: { lhs, rhs in
            let lhsDims = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let rhsDims = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return Int(lhsDims.width) * Int(lhsDims.height) < Int(rhsDims.width) * Int(rhsDims.height)
        }) else {
            return
        }

        if camera.activeFormat.isCenterStageSupported {
            let activeDims = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
            let bestDims = CMVideoFormatDescriptionGetDimensions(best.formatDescription)
            if activeDims.width == bestDims.width, activeDims.height == bestDims.height {
                return
            }
        }

        if let session, session.canSetSessionPreset(.inputPriority) {
            session.sessionPreset = .inputPriority
        }

        do {
            try camera.lockForConfiguration()
            camera.activeFormat = best
            if let range = best.videoSupportedFrameRateRanges.first(where: { $0.maxFrameRate >= 30 }) {
                let fps = min(30.0, range.maxFrameRate)
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            }
            camera.unlockForConfiguration()
            if prefersMaximumCaptureQuality {
                applyMaxPhotoDimensions(for: camera)
            }
        } catch {
        }
    }

    private func setCenterStageEnabled(_ enabled: Bool) {
        if AVCaptureDevice.centerStageControlMode != .cooperative
            && AVCaptureDevice.centerStageControlMode != .app {
            AVCaptureDevice.centerStageControlMode = .cooperative
        }
        if AVCaptureDevice.isCenterStageEnabled != enabled {
            AVCaptureDevice.isCenterStageEnabled = enabled
        }
    }

    private func disableCenterStageIfNeeded() {
        guard AVCaptureDevice.centerStageControlMode == .cooperative
                || AVCaptureDevice.centerStageControlMode == .app else {
            return
        }
        if AVCaptureDevice.isCenterStageEnabled {
            AVCaptureDevice.isCenterStageEnabled = false
        }
    }

    private func publishCenterStageAvailability(_ available: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onCenterStageAvailabilityChange?(available)
        }
    }

    private func observeCenterStageEnabledChanges() {
        guard enablesCenterStageControls, !isObservingCenterStageEnabled else { return }
        // `isCenterStageEnabled` es class property: KVO clásico sobre el metatype.
        AVCaptureDevice.self.addObserver(
            self,
            forKeyPath: centerStageEnabledKeyPath,
            options: [.new],
            context: nil
        )
        isObservingCenterStageEnabled = true
    }

    private func stopObservingCenterStageEnabled() {
        guard isObservingCenterStageEnabled else { return }
        AVCaptureDevice.self.removeObserver(self, forKeyPath: centerStageEnabledKeyPath)
        isObservingCenterStageEnabled = false
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == centerStageEnabledKeyPath else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        let enabled = AVCaptureDevice.isCenterStageEnabled
        onCenterStageEnabledChangeFromSystem?(enabled)
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

        let settings = AVCapturePhotoSettings()

        let maxQuality = photoOutput.maxPhotoQualityPrioritization
        if maxQuality == .quality {
            settings.photoQualityPrioritization = .quality
        } else if maxQuality == .balanced {
            settings.photoQualityPrioritization = .balanced
        } else {
            settings.photoQualityPrioritization = .speed
        }

        if prefersMaximumCaptureQuality {
            let dims = photoOutput.maxPhotoDimensions
            if dims.width > 0, dims.height > 0 {
                settings.maxPhotoDimensions = dims
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

        let correctedImage = correctImageOrientation(image)
        let normalizedImage = correctedImage.creatorNormalizedUp()
        let previewMatchedImage = cropImageToVisiblePreview(normalizedImage) ?? normalizedImage

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.parent.onImageCaptured(previewMatchedImage)
        }
    }

    private func correctImageOrientation(_ image: UIImage) -> UIImage {
        if currentPosition == .front {
            return UIImage(cgImage: image.cgImage!, scale: image.scale, orientation: .leftMirrored)
        }
        return image
    }
}

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
