import SwiftUI
import AVFoundation
import PhotosUI

// MARK: - Enhanced Camera Picker with Fixed Gallery and Useful Options
struct EnhancedCameraPickerView: View {
    let onMediaCaptured: (Data, MediaType, Bool) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var isEphemeralMode = false
    @State private var captureMode: CaptureMode = .photo
    @State private var cameraPosition: CameraPosition = .back
    @State private var flashMode: FlashMode = .off
    @State private var selectedItems: [PhotosPickerItem] = [] // ✅ Para PhotosPicker
    @State private var showGridLines = false // ✅ Para grid lines
    @State private var showPhotoPicker = false // ✅ Control del PhotosPicker
    @State private var pressScale: CGFloat = 1.0
    
    private let signatureGradient = LinearGradient(
        colors: [Color.blue, Color.purple, Color.pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
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
            case .photo: return "FOTO"
            case .video: return "VIDEO"
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
    
    @State private var cameraViewController: CameraViewController?
    
    var body: some View {
        ZStack {
            // Camera View
            CameraView(
                captureMode: captureMode,
                cameraPosition: cameraPosition,
                flashMode: flashMode,
                isEphemeralMode: isEphemeralMode,
                showGridLines: showGridLines, // ✅ Pasar grid lines
                onMediaCaptured: onMediaCaptured,
                cameraViewController: $cameraViewController
            )
            
            VStack(spacing: 0) {
                // ✅ TOP CONTROLS - Mejorados
                topControlsBar
                
                Spacer()
                
                // ✅ MODE SELECTOR - Diseño elegante
                modeSelector
                
                // ✅ BOTTOM CONTROLS - Rediseñados con galería funcional
                bottomControlsBar
            }
            
            // ✅ EPHEMERAL MODE INDICATOR - Mejorado
            ephemeralModeIndicator
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
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
        }
    }
    
    // ✅ TOP CONTROLS BAR
    private var topControlsBar: some View {
        HStack {
            // Cancel Button
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                    Text(NSLocalizedString("camera.actions.cancel", comment: "Cancel camera action"))
                        .font(.custom("Poppins-Medium", size: 14))
                }
                .foregroundColor(isEphemeralMode ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        if isEphemeralMode {
                            Capsule().fill(ephemeralGradient.opacity(0.2))
                        }
                        Capsule().fill(.ultraThinMaterial)
                    }
                    .overlay(Capsule().stroke(isEphemeralMode ? Color(hex: "FFCC33").opacity(0.5) : Color.white.opacity(0.2), lineWidth: 1))
                )
            }
            
            Spacer()
            
            // Flash Control (solo para cámara trasera y modo foto)
            if cameraPosition == .back && captureMode == .photo {
                Button(action: { cycleFlashMode() }) {
                    Image(systemName: flashMode.icon)
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            ZStack {
                                if isEphemeralMode {
                                    Circle().fill(ephemeralGradient.opacity(0.2))
                                }
                                Circle().fill(.ultraThinMaterial)
                            }
                            .overlay(Circle().stroke(isEphemeralMode ? Color(hex: "FFCC33").opacity(0.5) : Color.white.opacity(0.2), lineWidth: 1))
                        )
                }
            }
            
            // Camera Switch
            Button(action: { switchCamera() }) {
                Image(systemName: cameraPosition.icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        ZStack {
                            if isEphemeralMode {
                                Circle().fill(ephemeralGradient.opacity(0.2))
                            }
                            Circle().fill(.ultraThinMaterial)
                        }
                        .overlay(Circle().stroke(isEphemeralMode ? Color(hex: "FFCC33").opacity(0.5) : Color.white.opacity(0.2), lineWidth: 1))
                    )
            }
            
            // Ephemeral Mode Toggle
            Button(action: { toggleEphemeralMode() }) {
                HStack(spacing: 6) {
                    Image(systemName: isEphemeralMode ? "eye.slash.circle.fill" : "eye.circle")
                        .font(.system(size: 16))
                    Text(isEphemeralMode ? NSLocalizedString("camera.mode.ephemeral", comment: "Ephemeral mode") : NSLocalizedString("camera.mode.normal", comment: "Normal mode"))
                        .font(.custom("Poppins-SemiBold", size: 12))
                }
                .foregroundColor(isEphemeralMode ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        if isEphemeralMode {
                            Capsule().fill(ephemeralGradient)
                        } else {
                            Capsule().fill(.ultraThinMaterial)
                        }
                    }
                    .overlay(
                        Capsule()
                            .stroke(isEphemeralMode ? Color(hex: "FFCC33") : Color.white.opacity(0.2), lineWidth: 1)
                    )
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    // ✅ MODE SELECTOR - Elegante
    private var modeSelector: some View {
        HStack(spacing: 0) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        captureMode = mode
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 24, weight: .medium))
                        Text(mode.title)
                            .font(.custom("Poppins-SemiBold", size: 12))
                    }
                    .foregroundColor(captureMode == mode ? (isEphemeralMode ? Color(hex: "FFCC33") : Color.white) : .white.opacity(0.5))
                    .frame(width: 80, height: 60)
                    .background(
                        ZStack {
                            if captureMode == mode {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isEphemeralMode ? ephemeralGradient.opacity(0.3) : signatureGradient.opacity(0.3))
                                    .blur(radius: 8)
                                    .offset(y: 2)
                                
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(captureMode == mode ? (isEphemeralMode ? ephemeralGradient : signatureGradient) : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                        )
                    )
                }
                .scaleEffect(captureMode == mode ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: captureMode)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
    }
    
    // ✅ BOTTOM CONTROLS BAR - CORREGIDO
    private var bottomControlsBar: some View {
        HStack(spacing: 40) {
            // Gallery Button - FUNCIONAL ✅
            Button(action: {
                showPhotoPicker = true
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .frame(width: 54, height: 54)
                    
                    if isEphemeralMode {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(ephemeralGradient.opacity(0.1))
                            .frame(width: 54, height: 54)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isEphemeralMode ? Color(hex: "FFCC33").opacity(0.4) : Color.white.opacity(0.2), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "photo.stack")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                )
            }
            
            // Main Capture Button
            EnhancedCaptureButton(
                captureMode: captureMode,
                isEphemeralMode: isEphemeralMode,
                onCapture: handleCapture
            )
            
            // Grid Lines Toggle - ÚTIL ✅
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showGridLines.toggle()
                }
                
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 54, height: 54)
                    
                    if isEphemeralMode {
                        Circle()
                            .fill(ephemeralGradient.opacity(0.1))
                            .frame(width: 54, height: 54)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(showGridLines ? (isEphemeralMode ? Color(hex: "FFCC33") : Color.white) : Color.white.opacity(0.2), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: showGridLines ? "grid.circle.fill" : "grid.circle")
                        .font(.system(size: 22))
                        .foregroundColor(showGridLines ? (isEphemeralMode ? Color(hex: "FFCC33") : .white) : .white.opacity(0.6))
                )
            }
        }
        .padding(.bottom, 50)
    }
    
    // ✅ EPHEMERAL MODE INDICATOR
    private var ephemeralModeIndicator: some View {
        VStack {
            if isEphemeralMode {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundColor(Color(hex: "FFCC33"))
                        Text(NSLocalizedString("camera.ephemeral.deleteOnView", comment: "Ephemeral delete on view message"))
                            .font(.custom("Poppins-SemiBold", size: 12))
                            .foregroundColor(Color(hex: "FFCC33"))
                        Text(NSLocalizedString("camera.ephemeral.onceOnly", comment: "Ephemeral once only message"))
                            .font(.custom("Poppins-Medium", size: 10))
                            .foregroundColor(Color(hex: "FFCC33").opacity(0.8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 16)
                                .fill(ephemeralGradient.opacity(0.2))
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(ephemeralGradient.opacity(0.5), lineWidth: 1)
                        )
                        .shadow(color: Color(hex: "FFCC33").opacity(0.3), radius: 10, x: 0, y: 5)
                    )
                    .padding(.trailing, 20)
                    .padding(.top, 120)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            Spacer()
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
    
    // ✅ HANDLE SELECTED MEDIA FROM GALLERY
    private func handleSelectedMedia(_ items: [PhotosPickerItem]) {
        guard let item = items.first else { return }
        
        
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                DispatchQueue.main.async {
                    // Determine if it's image or video
                    if let _ = UIImage(data: data) {
                        let normalizedData = self.normalizedGalleryImageData(from: data) ?? data
                        self.onMediaCaptured(normalizedData, .image, self.isEphemeralMode)
                    } else {
                        self.onMediaCaptured(data, .video, self.isEphemeralMode)
                    }
                    
                    // Clear selection and dismiss
                    self.selectedItems = []
                    self.dismiss()
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
}

// ✅ ENHANCED CAPTURE BUTTON
struct EnhancedCaptureButton: View {
    let captureMode: EnhancedCameraPickerView.CaptureMode
    let isEphemeralMode: Bool
    let onCapture: () -> Void
    @State private var isRecording = false
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    
    private let signatureGradient = LinearGradient(
        colors: [Color.blue, Color.purple, Color.pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    private let ephemeralGradient = LinearGradient(
        colors: [Color(hex: "FFB347"), Color(hex: "FFCC33")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        Button(action: handleCapture) {
            ZStack {
                // Glow Layer
                Circle()
                    .fill(isEphemeralMode ? Color(hex: "FFCC33") : Color.white)
                    .frame(width: 95, height: 95)
                    .blur(radius: isRecording ? 15 : 0)
                    .opacity(isRecording ? 0.4 : 0)
                
                // Outer Ring
                Circle()
                    .stroke(
                        isEphemeralMode ? ephemeralGradient : signatureGradient,
                        lineWidth: isRecording ? 6 : 4
                    )
                    .frame(width: 90, height: 90)
                
                // Glass Ring
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 82, height: 82)
                    .opacity(isRecording ? 0.3 : 1)
                
                // Inner Circle/Square
                Group {
                    if isRecording {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red)
                            .frame(width: 32, height: 32)
                            .shadow(color: .red.opacity(0.5), radius: 10)
                    } else {
                        ZStack {
                            Circle()
                                .fill(isEphemeralMode ? Color(hex: "FFCC33") : Color.white)
                            
                            Image(systemName: captureMode.icon)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.black)
                                .opacity(captureMode == .photo ? 1 : 0)
                        }
                        .frame(width: 70, height: 70)
                    }
                }
                .scaleEffect(isRecording ? 0.8 : 1.0)
                
                Circle()
                    .stroke(isEphemeralMode ? Color(hex: "FFCC33") : Color.white, lineWidth: 1)
                    .frame(width: 100, height: 100)
                    .opacity(0)
                    .scaleEffect(0.8)
                
                // Recording Timer restored
                if isRecording && captureMode == .video {
                    VStack {
                        Spacer()
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
                            .offset(y: 65)
                    }
                }
            }
        }
        .buttonStyle(CameraButtonStyle())
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isRecording)
    }
    
    private func handleCapture() {
        switch captureMode {
        case .photo:
            // Photo capture con feedback visual
            withAnimation(.easeInOut(duration: 0.1)) {
                isRecording = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isRecording = false
                }
            }
            onCapture()
            
        case .video:
            isRecording.toggle()
            if isRecording {
                startRecordingTimer()
            } else {
                stopRecordingTimer()
            }
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

// ✅ CAMERA VIEW - ACTUALIZADA CON GRID LINES
struct CameraView: UIViewControllerRepresentable {
    let captureMode: EnhancedCameraPickerView.CaptureMode
    let cameraPosition: EnhancedCameraPickerView.CameraPosition
    let flashMode: EnhancedCameraPickerView.FlashMode
    let isEphemeralMode: Bool
    let showGridLines: Bool // ✅ Nuevo parámetro
    let onMediaCaptured: (Data, EnhancedCameraPickerView.MediaType, Bool) -> Void
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
    }
}

// ✅ CAMERA VIEW CONTROLLER - MEJORADO CON GRID LINES
protocol CameraViewControllerDelegate: AnyObject {
    func didCapturePhoto(_ data: Data)
    func didCaptureVideo(_ data: Data)
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
    private var gridLinesView: UIView? // ✅ Grid lines overlay
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupGridLines() // ✅ Setup grid lines
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
        gridLinesView?.frame = view.bounds // ✅ Update grid lines frame
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
        captureSession.sessionPreset = .high
        setupCameraInput(position: .back)
        setupOutputs()
        setupPreviewLayer()
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
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
    }
    
    func stopVideoRecording() {
        guard videoOutput.isRecording else { return }
        videoOutput.stopRecording()
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
