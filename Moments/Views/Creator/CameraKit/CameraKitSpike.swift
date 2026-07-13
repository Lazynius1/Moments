import SwiftUI
import AVFoundation
import SCSDKCameraKit

// MARK: - Fase 1-3 (spike): preview + carrusel de lentes + captura foto/vídeo.

@MainActor
final class CameraKitController: NSObject, ObservableObject {
    let previewView: PreviewView = {
        let view = PreviewView()
        view.automaticallyConfiguresTouchHandler = true
        view.contentMode = .aspectFill
        return view
    }()

    @Published var lenses: [Lens] = []
    @Published var selectedLensID: String?
    @Published var appliedLensName: String?
    @Published var statusMessage: String = "Iniciando cámara…"
    @Published var capturedImage: UIImage?
    @Published var capturedVideoURL: URL?
    @Published var isRecording = false

    // Hooks para la Fase 4 (enganche a la subida real). Por ahora solo mostramos.
    var onCapturedPhoto: ((UIImage) -> Void)?
    var onCapturedVideo: ((URL) -> Void)?

    private var cameraKit: CameraKitProtocol?
    private let captureSession = AVCaptureSession()
    private var avInput: AVSessionInput?
    private var cameraPosition: AVCaptureDevice.Position = .back
    private var currentDevice: AVCaptureDevice?
    private var cameraActive = false
    private var lensSelectionRequestID = UUID()

    // Salidas de captura
    private let photoOutput = PhotoCaptureOutput(capturePhotoOutput: nil)
    private var assetWriter: AVAssetWriter?
    private var avWriterOutput: AVWriterOutput?

    // Spike: prepara lentes + enciende cámara CK de una.
    func start() {
        prepareLenses()
        activateCamera()
    }

    // Híbrido: solo carga la lista de lentes para el carrusel (SIN encender la cámara CK).
    func prepareLenses() {
        guard cameraKit == nil else { return }
        guard SnapCameraKitConfiguration.isConfigured else {
            statusMessage = "Faltan credenciales Snap (Secrets.xcconfig)"
            return
        }
        let lensesConfig = LensesConfig(cacheConfig: CacheConfig(lensContentMaxSize: 150 * 1024 * 1024))
        let session = Session(lensesConfig: lensesConfig, errorHandler: self)
        cameraKit = session

        guard let groupID = SnapCameraKitConfiguration.defaultLensGroupID else {
            statusMessage = "Lens Group ID vacío"
            return
        }
        session.lenses.repository.addObserver(self, groupID: groupID)
    }

    // Híbrido: enciende la cámara de CK (al elegir una lente). Aplica la lente cuando ya arrancó.
    func activateCamera(applyingLens lens: Lens? = nil) {
        guard let cameraKit else { return }
        guard !cameraActive else {
            if let lens { selectLens(lens) }
            return
        }
        requestCameraAccess { [weak self] granted in
            guard let self, granted else {
                self?.statusMessage = "Permiso de cámara denegado"
                return
            }
            if self.avInput == nil {
                self.configureCaptureSession()
                cameraKit.add(output: self.previewView)
                cameraKit.add(output: self.photoOutput)
                let input = AVSessionInput(session: self.captureSession)
                self.avInput = input
                cameraKit.start(input: input, arInput: ARSessionInput())
            }
            let input = self.avInput
            DispatchQueue.global(qos: .userInitiated).async { input?.startRunning() }
            self.cameraActive = true
            if let lens { self.selectLens(lens) }
        }
    }

    // Híbrido: apaga la cámara de CK (al volver a "sin filtro"), liberando el device para la cámara nativa.
    func deactivateCamera() {
        guard cameraActive else { return }
        avInput?.stopRunning()
        cameraActive = false
    }

    func stop() {
        avInput?.stopRunning()
        cameraKit?.stop()
        cameraKit = nil
        avInput = nil
        cameraActive = false
    }

    private func requestCameraAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    private func configureCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        for input in captureSession.inputs.compactMap({ $0 as? AVCaptureDeviceInput }) {
            captureSession.removeInput(input)
        }

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition),
           let deviceInput = try? AVCaptureDeviceInput(device: device),
           captureSession.canAddInput(deviceInput) {
            captureSession.addInput(deviceInput)
            currentDevice = device
        }

        captureSession.commitConfiguration()
    }

    // MARK: - Controles de cámara (flip / zoom)

    func setCameraPosition(_ position: AVCaptureDevice.Position) {
        guard cameraPosition != position else { return }
        cameraPosition = position
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.configureCaptureSession()
        }
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 5.0)
            device.videoZoomFactor = max(1.0, min(factor, maxZoom))
            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: - Viewport / safe area (canvas 9:16 compartido con editor/viewer)

    func updateViewport(forCanvasSize canvasSize: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }

        let safeArea = creatorMomentsLensInterfaceSafeArea(in: canvasSize)
        let outputResolution = creatorMomentsStoryOutputResolution(for: canvasSize)

        previewView.automaticallyConfiguresViewport = false

        if let provider = previewView.explicitViewportProvider {
            provider.setViewportSize(canvasSize)
            provider.setOutputResolution(outputResolution)
            provider.setSafeArea(safeArea)
        } else {
            previewView.explicitViewportProvider = ExplicitViewportProvider(
                viewportSize: canvasSize,
                outputResolution: outputResolution,
                safeArea: safeArea
            )
        }
    }

    // MARK: - Selección de lente (carrusel)

    func selectLens(_ lens: Lens?) {
        guard let cameraKit else { return }
        let requestID = UUID()
        lensSelectionRequestID = requestID

        guard let lens else {
            // Passthrough: cámara cruda sin filtro.
            cameraKit.lenses.processor?.clear(completion: nil)
            selectedLensID = nil
            appliedLensName = nil
            statusMessage = "Sin filtro"
            return
        }

        cameraKit.lenses.processor?.apply(lens: lens, launchData: nil) { [weak self] success in
            Task { @MainActor in
                // Las aplicaciones de Camera Kit son asíncronas. Ignora una
                // terminada tarde si el usuario ya ha cruzado otra lente.
                guard self?.lensSelectionRequestID == requestID else { return }
                if success {
                    self?.selectedLensID = lens.id
                    self?.appliedLensName = lens.name ?? lens.id
                    self?.statusMessage = "Lente: \(lens.name ?? lens.id)"
                } else {
                    self?.statusMessage = "No se pudo aplicar la lente"
                }
            }
        }
    }

    // MARK: - Captura foto

    func capturePhoto() {
        photoOutput.capture(with: nil) { [weak self] image, error in
            Task { @MainActor in
                guard let image else {
                    self?.statusMessage = "Error foto: \(error?.localizedDescription ?? "desconocido")"
                    return
                }
                self?.capturedImage = image
                self?.onCapturedPhoto?(image)
            }
        }
    }

    // MARK: - Captura vídeo (AVWriterOutput sobre AVAssetWriter)

    func startRecording() {
        guard let cameraKit, avWriterOutput == nil else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ck_\(UUID().uuidString).mp4")

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            statusMessage = "No se pudo crear el writer"
            return
        }

        // Resolución alineada con el canvas 9:16 del viewer.
        let width = Int(creatorMomentsStoryOutputPixelSize.width)
        let height = Int(creatorMomentsStoryOutputPixelSize.height)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        if writer.canAdd(videoInput) { writer.add(videoInput) }

        let output = AVWriterOutput(avAssetWriter: writer, pixelBufferInput: adaptor, audioInput: nil)
        assetWriter = writer
        avWriterOutput = output
        capturedVideoURL = url

        cameraKit.add(output: output)
        writer.startWriting()
        output.startRecording()

        isRecording = true
        statusMessage = "Grabando…"
    }

    func stopRecording() {
        guard let output = avWriterOutput, let writer = assetWriter else { return }
        output.stopRecording()
        cameraKit?.remove(output: output)
        avWriterOutput = nil
        assetWriter = nil
        isRecording = false

        writer.finishWriting { [weak self] in
            Task { @MainActor in
                if writer.status == .completed, let url = self?.capturedVideoURL {
                    self?.capturedVideoURL = url
                    self?.onCapturedVideo?(url)
                    self?.statusMessage = "Vídeo guardado"
                } else {
                    self?.statusMessage = "Error vídeo: \(writer.error?.localizedDescription ?? "desconocido")"
                }
            }
        }
    }
}

// MARK: - Error handler

extension CameraKitController: ErrorHandler {
    nonisolated func handleError(_ error: NSException) {
        Task { @MainActor in
            self.statusMessage = "Camera Kit: \(error.reason ?? error.name.rawValue)"
            print("[CameraKit] exception: \(error.name.rawValue) — \(error.reason ?? "")")
        }
    }
}

// MARK: - Lens repository observer

extension CameraKitController: LensRepositoryGroupObserver {
    nonisolated func repository(_ repository: LensRepository, didUpdateLenses lenses: [Lens], forGroupID groupID: String) {
        Task { @MainActor in
            self.lenses = lenses
            self.statusMessage = lenses.isEmpty ? "El grupo no tiene lentes." : "Elige una lente"
        }
    }

    nonisolated func repository(_ repository: LensRepository, didFailToUpdateLensesForGroupID groupID: String, error: Error?) {
        Task { @MainActor in
            self.statusMessage = "Error lentes: \(error?.localizedDescription ?? "desconocido")"
        }
    }
}

// MARK: - Preview wrapper

struct CameraKitPreviewRepresentable: UIViewRepresentable {
    let previewView: PreviewView
    var canvasSize: CGSize = .zero
    var onViewportUpdate: ((CGSize) -> Void)?

    func makeUIView(context: Context) -> PreviewView {
        if canvasSize.width > 0, canvasSize.height > 0 {
            onViewportUpdate?(canvasSize)
        }
        return previewView
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        onViewportUpdate?(canvasSize)
    }
}
