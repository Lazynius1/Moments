// MARK: - Story Upload Progress Manager
class StoryUploadProgressManager: ObservableObject {
    static let shared = StoryUploadProgressManager()
    
    @Published var isUploading = false
    @Published var progress: Double = 0.0
    
    func startUpload() {
        isUploading = true
        progress = 0.0
    }
    
    func updateProgress(_ value: Double) {
        progress = value
    }
    
    func finishUpload() {
        isUploading = false
        progress = 1.0
    }
    
    func cancelUpload() {
        isUploading = false
        progress = 0.0
    }
}
struct ProcessedMedia: Identifiable {
    let id: String
    var image: UIImage
    var videoURL: URL?
    let type: MediaType
    var aspectRatio: AspectRatio
    var hasEdits: Bool = false
    var thumbnailURL: URL?
    var videoDuration: Double?
    var videoFileSize: Int64?
    var videoResolution: String?
    
    enum MediaType {
        case image, video
    }
    
    enum AspectRatio {
        case square          // 1:1
        case portrait        // 4:5
        case landscape       // 16:9
        case nineBySixteen   // 9:16 (stories)
        
        var value: CGFloat {
            switch self {
            case .square: return 1.0
            case .portrait: return 0.8  // 4:5
            case .landscape: return 1.777 // 16:9
            case .nineBySixteen: return 0.5625 // 9:16
            }
        }
        
        var displayName: String {
            switch self {
            case .square: return "1:1"
            case .portrait: return "4:5"
            case .landscape: return "16:9"
            case .nineBySixteen: return "9:16"
            }
        }
        
        var ratio: CGFloat {
            switch self {
            case .square: return 1.0
            case .portrait: return 4.0/5.0
            case .landscape: return 16.0/9.0
            case .nineBySixteen: return 9.0/16.0
            }
        }
    }
    
    init(id: String, image: UIImage, videoURL: URL?, type: MediaType, aspectRatio: AspectRatio, hasEdits: Bool = false) {
        self.id = id
        self.image = image
        self.videoURL = videoURL
        self.type = type
        self.aspectRatio = aspectRatio
        self.hasEdits = hasEdits
    }
    
    init(type: MediaType, image: UIImage, videoURL: URL?, aspectRatio: AspectRatio) {
        self.id = UUID().uuidString
        self.image = image
        self.videoURL = videoURL
        self.type = type
        self.aspectRatio = aspectRatio
        self.hasEdits = false
    }
    
    // Método `with` actualizado para aceptar todos los parámetros necesarios
    func with(videoURL: URL? = nil, aspectRatio: AspectRatio? = nil, hasEdits: Bool? = nil, image: UIImage? = nil) -> ProcessedMedia {
        ProcessedMedia(
            id: self.id,
            image: image ?? self.image,
            videoURL: videoURL ?? self.videoURL,
            type: self.type,
            aspectRatio: aspectRatio ?? self.aspectRatio,
            hasEdits: hasEdits ?? self.hasEdits
        )
    }
    
    var isValidVideo: Bool {
        return type == .video && videoURL != nil && FileManager.default.fileExists(atPath: videoURL!.path)
    }
    
    var videoInfo: (duration: Double, fileSize: Int64)? {
        guard let videoURL = videoURL, type == .video else { return nil }
        
        do {
            let asset = AVAsset(url: videoURL)
            let duration = asset.duration.seconds
            
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
            let fileSize = fileAttributes[FileAttributeKey.size] as? Int64 ?? 0
            
            return (duration: duration, fileSize: fileSize)
        } catch {
            return nil
        }
    }
}
// MARK: - Drawing View Implementation

import PencilKit

struct DrawingView: UIViewControllerRepresentable {
    let backgroundImage: UIImage? // Agregar imagen de fondo
    let onComplete: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> DrawingViewController {
        let controller = DrawingViewController()
        controller.backgroundImage = backgroundImage
        controller.onComplete = onComplete
        controller.onDismiss = {
            dismiss()
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: DrawingViewController, context: Context) {}
}

class DrawingViewController: UIViewController {
    var onComplete: ((UIImage) -> Void)?
    var onDismiss: (() -> Void)?
    var backgroundImage: UIImage?
    
    private let canvasView = PKCanvasView()
    private let toolPicker = PKToolPicker()
    private var selectedColor: UIColor = .white
    private var backgroundImageView: UIImageView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // Agregar imagen de fondo si existe
        if let backgroundImage = backgroundImage {
            let imageView = UIImageView(image: backgroundImage)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFill
            view.addSubview(imageView)
            backgroundImageView = imageView
            
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: view.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
        
        // Canvas setup - TRANSPARENTE
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .white, width: 3)
        view.addSubview(canvasView)
        
        // Top toolbar
        let topToolbar = UIView()
        topToolbar.translatesAutoresizingMaskIntoConstraints = false
        topToolbar.backgroundColor = .black.withAlphaComponent(0.8)
        view.addSubview(topToolbar)
        
        // Close button
        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        topToolbar.addSubview(closeButton)
        
        // Done button
        let doneButton = UIButton(type: .system)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Hecho", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        topToolbar.addSubview(doneButton)
        
        // Bottom toolbar
        let bottomToolbar = UIView()
        bottomToolbar.translatesAutoresizingMaskIntoConstraints = false
        bottomToolbar.backgroundColor = .black.withAlphaComponent(0.8)
        view.addSubview(bottomToolbar)
        
        // Tool buttons
        let penButton = createToolButton(imageName: "pencil", action: #selector(penSelected))
        let markerButton = createToolButton(imageName: "highlighter", action: #selector(markerSelected))
        let eraserButton = createToolButton(imageName: "eraser", action: #selector(eraserSelected))
        let undoButton = createToolButton(imageName: "arrow.uturn.backward", action: #selector(undoTapped))
        let clearButton = createToolButton(imageName: "trash", action: #selector(clearTapped))
        
        let toolStack = UIStackView(arrangedSubviews: [penButton, markerButton, eraserButton, undoButton, clearButton])
        toolStack.translatesAutoresizingMaskIntoConstraints = false
        toolStack.axis = .horizontal
        toolStack.distribution = .equalSpacing
        toolStack.spacing = 30
        bottomToolbar.addSubview(toolStack)
        
        // Color picker
        let colorStack = createColorPicker()
        colorStack.translatesAutoresizingMaskIntoConstraints = false
        bottomToolbar.addSubview(colorStack)
        
        // Constraints
        NSLayoutConstraint.activate([
            // Canvas
            canvasView.topAnchor.constraint(equalTo: topToolbar.bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor),
            
            // Top toolbar
            topToolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topToolbar.heightAnchor.constraint(equalToConstant: 60),
            
            // Close button
            closeButton.leadingAnchor.constraint(equalTo: topToolbar.leadingAnchor, constant: 20),
            closeButton.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),
            
            // Done button
            doneButton.trailingAnchor.constraint(equalTo: topToolbar.trailingAnchor, constant: -20),
            doneButton.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),
            
            // Bottom toolbar
            bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomToolbar.heightAnchor.constraint(equalToConstant: 120),
            
            // Tool stack
            toolStack.centerXAnchor.constraint(equalTo: bottomToolbar.centerXAnchor),
            toolStack.topAnchor.constraint(equalTo: bottomToolbar.topAnchor, constant: 20),
            
            // Color stack
            colorStack.centerXAnchor.constraint(equalTo: bottomToolbar.centerXAnchor),
            colorStack.bottomAnchor.constraint(equalTo: bottomToolbar.bottomAnchor, constant: -20)
        ])
        
        // Setup tool picker
        toolPicker.setVisible(false, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvasView.becomeFirstResponder()
    }
    
    private func createToolButton(imageName: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: imageName), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
    
    private func createColorPicker() -> UIStackView {
        let colors: [UIColor] = [.white, .black, .red, .orange, .yellow, .green, .blue, .purple]
        let buttons = colors.map { color in
            let button = UIButton(type: .system)
            button.backgroundColor = color
            button.layer.cornerRadius = 15
            button.layer.borderWidth = color == selectedColor ? 3 : 1
            button.layer.borderColor = UIColor.white.cgColor
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 30).isActive = true
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            button.addTarget(self, action: #selector(colorSelected(_:)), for: .touchUpInside)
            return button
        }
        
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal
        stack.spacing = 15
        stack.distribution = .equalSpacing
        return stack
    }
    
    @objc private func closeTapped() {
        onDismiss?()
    }
    
    @objc private func doneTapped() {
        // Renderizar solo el dibujo sin fondo
        let renderer = UIGraphicsImageRenderer(bounds: canvasView.bounds)
        let image = renderer.image { context in
            // Fondo transparente
            UIColor.clear.setFill()
            context.fill(canvasView.bounds)
            
            // Dibujar solo el canvas
            canvasView.drawHierarchy(in: canvasView.bounds, afterScreenUpdates: true)
        }
        onComplete?(image)
        onDismiss?()
    }
    
    @objc private func penSelected() {
        canvasView.tool = PKInkingTool(.pen, color: selectedColor, width: 3)
    }
    
    @objc private func markerSelected() {
        canvasView.tool = PKInkingTool(.marker, color: selectedColor.withAlphaComponent(0.5), width: 20)
    }
    
    @objc private func eraserSelected() {
        canvasView.tool = PKEraserTool(.bitmap)
    }
    
    @objc private func undoTapped() {
        canvasView.drawing = canvasView.drawing
        canvasView.undoManager?.undo()
    }
    
    @objc private func clearTapped() {
        canvasView.drawing = PKDrawing()
    }
    
    @objc private func colorSelected(_ sender: UIButton) {
        selectedColor = sender.backgroundColor ?? .white
        
        // Update border for all color buttons
        if let superview = sender.superview {
            for subview in superview.subviews {
                if let button = subview as? UIButton {
                    button.layer.borderWidth = button == sender ? 3 : 1
                }
            }
        }
        
        // Update current tool with new color
        if let inkingTool = canvasView.tool as? PKInkingTool {
            canvasView.tool = PKInkingTool(inkingTool.inkType, color: selectedColor, width: inkingTool.width)
        }
    }
}
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import AVKit
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import TOCropViewController
import CoreLocation
import MapKit
import UIKit

// Add Photos import at the top
import Photos

// MARK: - Main Creator View
struct CreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isCreatingStory: Bool
    @Binding var showCreatorView: Bool
    let initialSticker: StickerItem? // ✅ NUEVO: Sticker inicial
    let openInStoryMode: Bool // ✅ NUEVO: Abrir directamente en modo historia
    
    @State private var currentFlow: CreatorFlow = .typeSelection
    @State private var contentType: ContentType = .moment
    
    init(isCreatingStory: Binding<Bool>, showCreatorView: Binding<Bool>, initialSticker: StickerItem? = nil, openInStoryMode: Bool = false) {
        self._isCreatingStory = isCreatingStory
        self._showCreatorView = showCreatorView
        self.initialSticker = initialSticker
        self.openInStoryMode = openInStoryMode
    }
    @State private var selectedMediaItems: [ProcessedMedia] = []
    @State private var captionText: String = ""
    @State private var taggedUsers: [String] = []
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var locationName: String = ""
    @State private var responseSticker: StickerItem? = nil
    
    // 🔗 NUEVO: Variables para contexto de cadena
    @State private var pendingChainId: String? = nil
    @State private var pendingChainTitle: String? = nil
    @State private var pendingChainPosition: Int? = nil
    
    enum CreatorFlow {
        case typeSelection
        case mediaSelection
        case mediaEditing
        case videoEditing
        case captionAndDetails
        case storyCamera
        case storyEditing
    }
    
    enum ContentType {
        case moment
        case story
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            switch currentFlow {
            case .typeSelection:
                ContentTypeSelectionView(
                    contentType: $contentType,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView
                )
            case .mediaSelection:
                MediaSelectionView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView
                )
            case .mediaEditing:
                MediaEditingView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView
                )
            case .videoEditing:
                SocialVideoEditorView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView
                )
            case .captionAndDetails:
                CaptionAndDetailsView(
                    selectedMediaItems: $selectedMediaItems,
                    captionText: $captionText,
                    taggedUsers: $taggedUsers,
                    selectedLocation: $selectedLocation,
                    locationName: $locationName,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView
                )
            case .storyCamera:
                StoryCameraView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView
                )
            case .storyEditing:
                StoryEditingView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView,
                    initialSticker: responseSticker,
                    initialChainId: pendingChainId,
                    initialChainTitle: pendingChainTitle,
                    initialChainPosition: pendingChainPosition
                )
            }
        }
        .onChange(of: contentType) { _, newType in
            if newType == .story {
                currentFlow = .storyCamera
                isCreatingStory = true
            } else {
                currentFlow = .mediaSelection
                isCreatingStory = false
            }
        }
        .onAppear {
            setupResponseStickerListener()
            setupContinueChainListener()
            
            // ✅ AGREGAR STICKER INICIAL SI EXISTE
            if let initialSticker = initialSticker {
                responseSticker = initialSticker
                contentType = .story
                currentFlow = .storyEditing
                isCreatingStory = true
            } else if openInStoryMode {
                // ✅ Abrir directamente en modo historia (desde widget)
                contentType = .story
            }
        }
        .onDisappear {
            removeResponseStickerListener()
            removeContinueChainListener()
            
            // ✅ Limpiar video y audio cuando se cierra CreatorView
            cleanupVideoAndAudio()
        }
    }
    
    // MARK: - Response Sticker Handling
    private func setupResponseStickerListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AddResponseStickerToCreator"),
            object: nil,
            queue: .main
        ) { notification in
            if let sticker = notification.object as? StickerItem {
                addResponseStickerToStory(sticker)
            }
        }
    }
    
    private func removeResponseStickerListener() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("AddResponseStickerToCreator"),
            object: nil
        )
    }
    
    // MARK: - Continue Chain Handling
    private func setupContinueChainListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ContinueStoryChain"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let chainId = userInfo["chainId"] as? String,
               let chainTitle = userInfo["chainTitle"] as? String,
               let chainPosition = userInfo["chainPosition"] as? Int {
                continueStoryChain(chainId: chainId, chainTitle: chainTitle, chainPosition: chainPosition)
            }
        }
        
        // 🔗 NUEVO: Listener para configurar tipo de contenido
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SetContentType"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let contentTypeString = userInfo["contentType"] as? String {
                if contentTypeString == "story" {
                    contentType = .story
                    currentFlow = .storyCamera  // ✅ MANTENER: Ir a cámara para seleccionar medios
                    isCreatingStory = true
                }
            }
        }
        
        // 🔗 NUEVO: Listener para guardar contexto de cadena
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SetChainContext"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let chainId = userInfo["chainId"] as? String,
               let chainTitle = userInfo["chainTitle"] as? String,
               let chainPosition = userInfo["chainPosition"] as? Int {
                pendingChainId = chainId
                pendingChainTitle = chainTitle
                pendingChainPosition = chainPosition
            }
        }
    }
    
    private func removeContinueChainListener() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("ContinueStoryChain"),
            object: nil
        )
        
        // 🔗 NUEVO: Limpiar listener de tipo de contenido
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("SetContentType"),
            object: nil
        )
    }
    
    private func continueStoryChain(chainId: String, chainTitle: String, chainPosition: Int) {
        // Configurar para continuar cadena
        contentType = .story
        currentFlow = .storyCamera
        isCreatingStory = true
        
        // Pasar datos de cadena al StoryEditingView
        // Esto se manejará en el StoryEditingView cuando se abra
        NotificationCenter.default.post(
            name: NSNotification.Name("SetChainContext"),
            object: nil,
            userInfo: [
                "chainId": chainId,
                "chainTitle": chainTitle,
                "chainPosition": chainPosition
            ]
        )
    }
    
    private func addResponseStickerToStory(_ sticker: StickerItem) {
        // ✅ GUARDAR EL STICKER EN EL ESTADO ANTES DE ABRIR StoryEditingView
        responseSticker = sticker
        
        // Ir directamente a la edición de historia con el sticker
        contentType = .story
        currentFlow = .storyEditing
        isCreatingStory = true
    }
    
    // ✅ FUNCIÓN PARA LIMPIAR VIDEO Y AUDIO
    private func cleanupVideoAndAudio() {
        // ✅ Limpiar los media items seleccionados
        selectedMediaItems.removeAll()
        
        // ✅ Pausar cualquier audio que esté reproduciéndose
        try? AVAudioSession.sharedInstance().setActive(false)
        
        // ✅ Notificar limpieza de video
        NotificationCenter.default.post(name: NSNotification.Name("CleanupVideoPlayer"), object: nil)
        
    }
}
// MARK: - Content Type Selection
struct ContentTypeSelectionView: View {
    @Binding var contentType: CreatorView.ContentType
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    showCreatorView = false
                }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .padding()
                
                Spacer()
                
                Text("creator.title")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Color.clear
                    .frame(width: 44, height: 44)
            }
            .background(Color.black)
            
            Spacer()
            
            // Options
            VStack(spacing: 40) {
                // Moment Option
                Button(action: {
                    contentType = .moment
                    currentFlow = .mediaSelection
                }) {
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 8) {
                            Text("creator.moment.title")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text("creator.moment.subtitle")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // Story Option
                Button(action: {
                    contentType = .story
                    currentFlow = .storyCamera
                }) {
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.purple, .pink, .orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: "circle.dashed")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 8) {
                            Text("creator.story.title")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text("creator.story.subtitle")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            
            Spacer()
        }
    }
}

// MARK: - Media Selection View
import SwiftUI
import Photos
import AVFoundation

struct MediaSelectionView: View {
    @Binding var selectedMediaItems: [ProcessedMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    @State private var mediaAssets: [PHAsset] = []
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selectedAssetIDs: [String] = []
    @State private var isLoadingLibrary = true
    @State private var showingCamera = false
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    // ✅ Estados para manejo de álbumes
    @State private var availableAlbums: [AlbumInfo] = []
    @State private var selectedAlbum: AlbumInfo?
    @State private var showingAlbumPicker = false
    
    private let imageManager = PHImageManager.default()
    private let thumbnailSize = CGSize(width: 300, height: 300)
    
    // Grid layout mejorado con columnas fijas para mejor control
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Preview del archivo seleccionado principal
            if !selectedAssetIDs.isEmpty {
                mainPreviewSection
            }
            
            // Grid de fotos y videos
            mediaGridSection
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .onAppear {
            requestPhotoLibraryAccess()
        }
        .sheet(isPresented: $showingCamera) {
            CameraCapture { media in
                selectedMediaItems.append(media)
                currentFlow = .mediaEditing
            }
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button(action: {
                currentFlow = .typeSelection
            }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            
            Spacer()
            
            Text("creator.newMoment")
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Spacer()
            
            Button(action: {
                if !selectedAssetIDs.isEmpty {
                    processSelectedAssets()
                }
            }) {
                Text("creator.next")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(selectedAssetIDs.isEmpty ? .gray : Color(hex: "00A896"))
            }
            .disabled(selectedAssetIDs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
    
    // MARK: - Preview principal
    private var mainPreviewSection: some View {
        VStack(spacing: 0) {
            // Preview grande del archivo seleccionado
            if let currentAssetID = selectedAssetIDs.first,
               let currentAsset = mediaAssets.first(where: { $0.localIdentifier == currentAssetID }) {
                
                ZStack {
                    (colorScheme == .dark ? Color.black : Color.white)
                    
                    if let thumbnail = thumbnails[currentAssetID] {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .clipped()
                    } else {
                        ProgressView()
                            .tint(Color(hex: "00A896"))
                    }
                    
                    // Indicador de video
                    if currentAsset.mediaType == .video {
                        VStack {
                            HStack {
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: "video.fill")
                                        .font(.caption)
                                    Text(formatDuration(currentAsset.duration))
                                        .font(.caption.bold())
                                }
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background((colorScheme == .dark ? Color.black : Color.white).opacity(0.7))
                                .clipShape(Capsule())
                                .padding(.trailing, 12)
                                .padding(.top, 12)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(height: 300)
                .background(Color.black)
            }
            
            // Contador de selección
            HStack {
                Text("\(selectedAssetIDs.count) \(String(format: NSLocalizedString("creator.files.selected", comment: "Files selected")))")
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(.gray)
                
                Spacer()
                
                if selectedAssetIDs.count > 1 {
                    Text("creator.multiple")
                        .font(.custom("Poppins-SemiBold", size: 12))
                        .foregroundColor(Color(hex: "00A896"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "00A896").opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
    }
    
    // MARK: - Grid de medios
    private var mediaGridSection: some View {
        VStack(spacing: 0) {
            // Separador
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)
            
            // Header con selector de álbum y botón de cámara
            HStack {
                // Selector de álbum con dropdown
                Button(action: {
                    showingAlbumPicker = true
                }) {
                    HStack(spacing: 6) {
                        Text(selectedAlbum?.title ?? "Recientes")
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .rotationEffect(.degrees(showingAlbumPicker ? 180 : 0))
                            .animation(.easeInOut(duration: 0.2), value: showingAlbumPicker)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                }
                
                Spacer()
                
                Button(action: {
                    showingCamera = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14))
                        Text("creator.camera")
                            .font(.custom("Poppins-Medium", size: 14))
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "00A896"))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(colorScheme == .dark ? Color.black : Color.white)
            
            // Grid de fotos
            if isLoadingLibrary {
                loadingView
            } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                permissionDeniedView
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2, pinnedViews: []) {
                        ForEach(mediaAssets, id: \.localIdentifier) { asset in
                            MediaGridCell(
                                asset: asset,
                                thumbnail: thumbnails[asset.localIdentifier],
                                isSelected: selectedAssetIDs.contains(asset.localIdentifier),
                                selectionNumber: selectedAssetIDs.firstIndex(of: asset.localIdentifier).map { $0 + 1 },
                                onTap: { toggleAssetSelection(asset) }
                            )
                            .frame(minHeight: 100) // ✅ NUEVO: Altura mínima para consistencia
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showingAlbumPicker) {
            AlbumPickerView(
                albums: availableAlbums,
                selectedAlbum: selectedAlbum,
                onAlbumSelected: { album in
                    selectedAlbum = album
                    showingAlbumPicker = false
                    loadMediaFromAlbum(album)
                }
            )
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Color(hex: "00A896"))
            
                            Text("creator.gallery.loading")
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(50)
    }
    
    // MARK: - Funciones
    
    private func requestPhotoLibraryAccess() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        if authorizationStatus == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    authorizationStatus = status
                    if status == .authorized || status == .limited {
                        loadAvailableAlbums()
                        loadMediaFromLibrary()
                    } else {
                        isLoadingLibrary = false
                    }
                }
            }
        } else if authorizationStatus == .authorized || authorizationStatus == .limited {
            loadAvailableAlbums()
            loadMediaFromLibrary()
        } else {
            isLoadingLibrary = false
        }
    }
    
    private func loadAvailableAlbums() {
        var albums: [AlbumInfo] = []
        
        // Álbum "Recientes" (Camera Roll)
        let recentsFetchResult = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumUserLibrary,
            options: nil
        )
        
        recentsFetchResult.enumerateObjects { collection, _, _ in
            let assetCount = PHAsset.fetchAssets(in: collection, options: nil).count
            if assetCount > 0 {
                albums.append(AlbumInfo(
                    id: collection.localIdentifier,
                    title: "Recientes",
                    assetCollection: collection,
                    assetCount: assetCount
                ))
            }
        }
        
        // Álbumes del usuario
        let userAlbumsFetchResult = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        
        userAlbumsFetchResult.enumerateObjects { collection, _, _ in
            let assetCount = PHAsset.fetchAssets(in: collection, options: nil).count
            if assetCount > 0 {
                albums.append(AlbumInfo(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? "Álbum sin título",
                    assetCollection: collection,
                    assetCount: assetCount
                ))
            }
        }
        
        // Álbumes inteligentes adicionales
        let smartAlbumTypes: [PHAssetCollectionSubtype] = [
            .smartAlbumFavorites,
            .smartAlbumScreenshots,
            .smartAlbumSelfPortraits,
            .smartAlbumVideos,
            .smartAlbumRecentlyAdded
        ]
        
        for subtype in smartAlbumTypes {
            let smartAlbumFetchResult = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: subtype,
                options: nil
            )
            
            smartAlbumFetchResult.enumerateObjects { collection, _, _ in
                let assetCount = PHAsset.fetchAssets(in: collection, options: nil).count
                if assetCount > 0 {
                    let title = collection.localizedTitle ?? getSmartAlbumTitle(for: subtype)
                    albums.append(AlbumInfo(
                        id: collection.localIdentifier,
                        title: title,
                        assetCollection: collection,
                        assetCount: assetCount
                    ))
                }
            }
        }
        
        // Ordenar álbumes
        albums.sort { first, second in
            if first.title == "Recientes" { return true }
            if second.title == "Recientes" { return false }
            return first.assetCount > second.assetCount
        }
        
        DispatchQueue.main.async {
            self.availableAlbums = albums
            self.selectedAlbum = albums.first
        }
    }
    
    private func getSmartAlbumTitle(for subtype: PHAssetCollectionSubtype) -> String {
        switch subtype {
        case .smartAlbumFavorites: return "Favoritos"
        case .smartAlbumScreenshots: return "Capturas de pantalla"
        case .smartAlbumSelfPortraits: return "Selfies"
        case .smartAlbumVideos: return "Videos"
        case .smartAlbumRecentlyAdded: return "Añadidos recientemente"
        default: return "Álbum"
        }
    }
    
    private func loadMediaFromAlbum(_ album: AlbumInfo) {
        isLoadingLibrary = true
        mediaAssets = []
        thumbnails = [:]
        selectedAssetIDs = []
        
        Task {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let assets = PHAsset.fetchAssets(in: album.assetCollection, options: fetchOptions)
            var assetArray: [PHAsset] = []
            
            assets.enumerateObjects { asset, _, _ in
                assetArray.append(asset)
            }
            
            await MainActor.run {
                self.mediaAssets = assetArray
                loadThumbnails()
            }
        }
    }
    
    private func loadMediaFromLibrary() {
        isLoadingLibrary = true
        
        Task {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 500
            
            let assets = PHAsset.fetchAssets(with: fetchOptions)
            var assetArray: [PHAsset] = []
            
            assets.enumerateObjects { asset, _, _ in
                assetArray.append(asset)
            }
            
            await MainActor.run {
                self.mediaAssets = assetArray
                loadThumbnails()
            }
        }
    }
    
    private func loadThumbnails() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        
        for asset in mediaAssets.prefix(50) {
            imageManager.requestImage(
                for: asset,
                targetSize: thumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                if let image = image {
                    DispatchQueue.main.async {
                        self.thumbnails[asset.localIdentifier] = image
                        
                        if self.thumbnails.count == 20 && self.isLoadingLibrary {
                            self.isLoadingLibrary = false
                        }
                    }
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if isLoadingLibrary {
                isLoadingLibrary = false
            }
        }
        
        DispatchQueue.global(qos: .background).async {
            for asset in mediaAssets.dropFirst(50) {
                imageManager.requestImage(
                    for: asset,
                    targetSize: thumbnailSize,
                    contentMode: .aspectFill,
                    options: options
                ) { image, _ in
                    if let image = image {
                        DispatchQueue.main.async {
                            self.thumbnails[asset.localIdentifier] = image
                        }
                    }
                }
            }
        }
    }
    
    private func toggleAssetSelection(_ asset: PHAsset) {
        let assetID = asset.localIdentifier
        
        if selectedAssetIDs.contains(assetID) {
            selectedAssetIDs.removeAll { $0 == assetID }
        } else {
            if selectedAssetIDs.count < 10 {
                selectedAssetIDs.append(assetID)
            }
        }
        
        if thumbnails[assetID] == nil {
            loadHighQualityThumbnail(for: asset)
        }
    }
    
    private func loadHighQualityThumbnail(for asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 500, height: 500),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    self.thumbnails[asset.localIdentifier] = image
                }
            }
        }
    }
    
    // Reemplaza tu función processSelectedAssets() con esta versión mejorada

    private func processSelectedAssets() {
        Task {
            var processedMedia: [ProcessedMedia] = []
            
            for assetID in selectedAssetIDs {
                guard let asset = mediaAssets.first(where: { $0.localIdentifier == assetID }) else { continue }
                
                if asset.mediaType == .image {
                    if let image = await loadFullImage(for: asset) {
                        // ✅ Detectar aspect ratio automáticamente
                        let detectedAspectRatio = detectAspectRatio(from: image)
                        
                        let media = ProcessedMedia(
                            id: assetID,
                            image: image,
                            videoURL: nil,
                            type: .image,
                            aspectRatio: detectedAspectRatio
                        )
                        processedMedia.append(media)
                    }
                } else if asset.mediaType == .video {
                    let (thumbnail, videoURL) = await loadFullVideo(for: asset)
                    
                    let finalImage = thumbnail ?? createVideoPlaceholder()
                    
                    // ✅ Detectar aspect ratio del video
                    let detectedAspectRatio = detectAspectRatio(from: finalImage)
                    
                    let media = ProcessedMedia(
                        id: assetID,
                        image: finalImage,
                        videoURL: videoURL,
                        type: .video,
                        aspectRatio: detectedAspectRatio
                    )
                    processedMedia.append(media)
                }
            }
            
            await MainActor.run {
                selectedMediaItems = processedMedia
                
                // ✅ NUEVA LÓGICA: Determinar flujo basado en tipo de medios
                let hasImages = processedMedia.contains { $0.type == .image }
                let hasVideos = processedMedia.contains { $0.type == .video }
                
                
                if hasVideos && !hasImages {
                    // Solo videos: ir al editor de videos
                    currentFlow = .videoEditing
                } else if hasImages && !hasVideos {
                    // Solo imágenes: ir al editor de fotos
                    currentFlow = .mediaEditing
                } else if hasImages && hasVideos {
                    // Mezcla: permitir al usuario elegir o ir directo a caption
                    currentFlow = .captionAndDetails
                } else {
                    // Fallback (no debería pasar)
                    currentFlow = .mediaEditing
                }
            }
        }
    }

    // ✅ FUNCIÓN AUXILIAR: Validar videos antes de continuar
    private func validateSelectedMedia() {
        let videoItems = selectedMediaItems.filter { $0.type == .video }
        
        for (index, videoItem) in videoItems.enumerated() {
            if videoItem.videoURL == nil {
            } else {
            }
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Detectar aspect ratio automáticamente SOLO para momentos
    // Reemplaza tu función detectAspectRatio en MediaSelectionView con esta versión mejorada

    private func detectAspectRatio(from image: UIImage) -> ProcessedMedia.AspectRatio {
        let imageRatio = image.size.width / image.size.height
        
        
        // Tolerancia del 8% para variaciones
        let tolerance: CGFloat = 0.08
        
        // Detectar ratios específicos con mayor precisión
        
        // 9:16 (Stories/Reels) - ratio ≈ 0.5625
        if abs(imageRatio - 0.5625) < tolerance {
            return .nineBySixteen
        }
        
        // 4:5 (Portrait posts) - ratio = 0.8
        if abs(imageRatio - 0.8) < tolerance {
            return .portrait
        }
        
        // 1:1 (Square) - ratio = 1.0
        if abs(imageRatio - 1.0) < tolerance {
            return .square
        }
        
        // 16:9 (Landscape) - ratio ≈ 1.777
        if abs(imageRatio - 1.777) < tolerance {
            return .landscape
        }
        
        // Detección por rangos si no coincide exactamente
        if imageRatio < 0.7 {
            return .nineBySixteen
        } else if imageRatio < 0.9 {
            return .portrait
        } else if imageRatio < 1.2 {
            return .square
        } else {
            return .landscape
        }
    }

    
    private func loadFullImage(for asset: PHAsset) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    private func loadFullVideo(for asset: PHAsset) async -> (UIImage?, URL?) {
        
        // Cargar thumbnail del video
        let thumbnail = await loadFullImage(for: asset)
        
        // ✅ MÉTODO MEJORADO: Solicitar video con opciones específicas
        let videoURL: URL? = await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current // Usar versión actual, no la original
            
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, audioMix, info in
                
                
                // Verificar si es degraded (baja calidad)
                if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                    return // Esperar la versión de alta calidad
                }
                
                // Verificar si hay error
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Verificar si necesita descargar de iCloud
                if let needsDownload = info?[PHImageResultIsInCloudKey] as? Bool, needsDownload {
                    // Ya configuramos isNetworkAccessAllowed = true
                    return
                }
                
                // Extraer URL del AVAsset
                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let videoURL = urlAsset.url
                
                // Verificar tamaño del archivo
                do {
                    let fileAttributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
                    let fileSize = fileAttributes[FileAttributeKey.size] as? Int64 ?? 0
                } catch {
                }
                
                continuation.resume(returning: videoURL)
            }
        }
        
        if let videoURL = videoURL {
        } else {
        }
        
        return (thumbnail, videoURL)
    }

    // ✅ FUNCIÓN AUXILIAR: Verificar permisos de acceso a video
    private func checkVideoAccess(for asset: PHAsset) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = false // Solo check local
        options.deliveryMode = .fastFormat
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, audioMix, info in
            DispatchQueue.main.async {
                if let error = info?[PHImageErrorKey] as? Error {
                } else if let isInCloud = info?[PHImageResultIsInCloudKey] as? Bool, isInCloud {
                } else if avAsset != nil {
                }
            }
        }
    }
    
    private func createVideoPlaceholder() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300))
        return renderer.image { context in
            UIColor.systemGray3.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 300, height: 300)))
            
            let videoIcon = "▶️"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 60),
                .foregroundColor: UIColor.white
            ]
            let textSize = videoIcon.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (300 - textSize.width) / 2,
                y: (300 - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            videoIcon.draw(in: textRect, withAttributes: attributes)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Permission Denied View (con instrucciones opcionales)
    private var permissionDeniedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 60))
                .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.6))
            
            Text("creator.gallery.permission")
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // ✅ Instrucciones opcionales para el usuario
            VStack(spacing: 12) {
                Text("creator.permissions.instructions.title")
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text("creator.permissions.instructions.path")
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.7))
                    .multilineTextAlignment(.center)
                
                Button("creator.permissions.openSettings") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.purple, Color.pink]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}

// MARK: - Modelo para información de álbumes
struct AlbumInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let assetCollection: PHAssetCollection
    let assetCount: Int
    
    static func == (lhs: AlbumInfo, rhs: AlbumInfo) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Vista del selector de álbumes (ESTILO ELEGANTE)
struct AlbumPickerView: View {
    let albums: [AlbumInfo]
    let selectedAlbum: AlbumInfo?
    let onAlbumSelected: (AlbumInfo) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var albumThumbnails: [String: UIImage] = [:]
    
    private let imageManager = PHImageManager.default()
    
    var body: some View {
        VStack(spacing: 0) {
            // ✅ Header compacto y elegante
            headerView
            
            // ✅ Lista de álbumes
            albumListView
            
            // ✅ Botón cerrar elegante
            cancelButton
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color(hex: "00A896").opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(false)
        .presentationBackground(.clear)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // ✅ Header compacto sin padding extra
    private var headerView: some View {
        VStack(spacing: 0) {
            // Handle del sheet
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.white.opacity(0.6))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)
            
            // Título centrado
            Text("creator.album.select")
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.bottom, 20)
        }
    }
    
    // ✅ Lista de álbumes con scroll
    private var albumListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(albums) { album in
                    AlbumRowView(
                        album: album,
                        thumbnail: albumThumbnails[album.id],
                        isSelected: selectedAlbum?.id == album.id,
                        onTap: {
                            onAlbumSelected(album)
                        }
                    )
                    .onAppear {
                        loadAlbumThumbnail(for: album)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
    
    // ✅ Botón cancelar elegante
    private var cancelButton: some View {
        Button("Cancelar") {
            withAnimation(.easeOut(duration: 0.3)) {
                dismiss()
            }
        }
        .font(.custom("Poppins-SemiBold", size: 16))
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }
    
    private func loadAlbumThumbnail(for album: AlbumInfo) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let assets = PHAsset.fetchAssets(in: album.assetCollection, options: fetchOptions)
        
        guard let firstAsset = assets.firstObject else { return }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = false
        
        imageManager.requestImage(
            for: firstAsset,
            targetSize: CGSize(width: 150, height: 150),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    albumThumbnails[album.id] = image
                }
            }
        }
    }
}

// MARK: - Vista de fila de álbum
struct AlbumRowView: View {
    let album: AlbumInfo
    let thumbnail: UIImage?
    let isSelected: Bool
    let onTap: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Thumbnail del álbum
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                    
                    if let thumbnail = thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                }
                
                // Info del álbum
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(String(format: NSLocalizedString("creator.album.elements", comment: "Album elements"), album.assetCount))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer()
                
                // Indicador de selección
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "00A896"))
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 20))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color(hex: "00A896").opacity(0.1) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Celda del grid individual
struct MediaGridCell: View {
    let asset: PHAsset
    let thumbnail: UIImage?
    let isSelected: Bool
    let selectionNumber: Int?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // ✅ NUEVO: Usar el aspect ratio real de la imagen
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.3))
                        .clipped()
                        .contentShape(Rectangle())
                        .overlay(
                            // Overlay sutil para mejorar contraste
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.clear, Color.black.opacity(0.1)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(1, contentMode: .fit)
                    
                    ProgressView()
                        .tint(Color(hex: "00A896"))
                }
                
                // Overlay de selección
                if isSelected {
                    Color(hex: "00A896").opacity(0.3)
                }
                
                // Indicador de video
                if asset.mediaType == .video {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "video.fill")
                                .font(.caption)
                            Text(formatDuration(asset.duration))
                                .font(.caption.bold())
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                
                // Número de selección
                VStack {
                    HStack {
                        Spacer()
                        if let number = selectionNumber {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "00A896"))
                                    .frame(width: 24, height: 24)
                                
                                Text("\(number)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.trailing, 6)
                            .padding(.top, 6)
                        } else if !isSelected {
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 24, height: 24)
                                .padding(.trailing, 6)
                                .padding(.top, 6)
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Media Editing View
struct MediaEditingView: View {
    @Binding var selectedMediaItems: [ProcessedMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool
    
    @State private var currentMediaIndex = 0
    @State private var showingCropView = false
    @State private var showingFilterView = false
    @State private var appliedFilters: [String: FilterSettings] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    currentFlow = .mediaSelection
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Text("creator.edit")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    currentFlow = .captionAndDetails
                }) {
                    Text("creator.next")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color.black.opacity(0.9))
            
            // Media preview
            TabView(selection: $currentMediaIndex) {
                ForEach(selectedMediaItems.indices, id: \.self) { index in
                    ZStack {
                        Color.black
                        
                        Image(uiImage: selectedMediaItems[index].image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
            
            // Media thumbnails
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedMediaItems.indices, id: \.self) { index in
                        Button(action: {
                            currentMediaIndex = index
                        }) {
                            ZStack {
                                Image(uiImage: selectedMediaItems[index].image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(currentMediaIndex == index ? Color.white : Color.clear, lineWidth: 2)
                                    )
                                
                                if selectedMediaItems[index].hasEdits {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .background(Color.blue)
                                        .clipShape(Circle())
                                        .offset(x: 20, y: -20)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 80)
            .background(Color.black.opacity(0.8))
            
            // Aspect ratio selector
            HStack(spacing: 20) {
                Text("creator.format")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                ForEach([ProcessedMedia.AspectRatio.square, .portrait, .landscape], id: \.self) { ratio in
                    Button(action: {
                        if currentMediaIndex < selectedMediaItems.count {
                            selectedMediaItems[currentMediaIndex].aspectRatio = ratio
                            showingCropView = true
                        }
                    }) {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(selectedMediaItems[currentMediaIndex].aspectRatio == ratio ? Color.blue : Color.gray, lineWidth: 2)
                                .frame(
                                    width: ratio == .landscape ? 50 : (ratio == .square ? 40 : 32),
                                    height: 40
                                )
                            
                            Text(ratio.displayName)
                                .font(.caption2)
                                .foregroundColor(selectedMediaItems[currentMediaIndex].aspectRatio == ratio ? .blue : .gray)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.8))
            
            // Editing tools
            HStack(spacing: 30) {
                EditingToolButton(icon: "crop.rotate", title: "Recortar") {
                    showingCropView = true
                }
                
                EditingToolButton(icon: "slider.horizontal.3", title: "Filtros") {
                    showingFilterView = true
                }
            }
            .padding()
            .background(Color.black)
        }
        .sheet(isPresented: $showingCropView) {
            if currentMediaIndex < selectedMediaItems.count {
                CropViewWrapper(
                    image: selectedMediaItems[currentMediaIndex].image,
                    aspectRatio: selectedMediaItems[currentMediaIndex].aspectRatio
                ) { croppedImage, newAspectRatio in
                    selectedMediaItems[currentMediaIndex].image = croppedImage
                    selectedMediaItems[currentMediaIndex].aspectRatio = newAspectRatio
                    selectedMediaItems[currentMediaIndex].hasEdits = true
                }
            }
        }
        .sheet(isPresented: $showingFilterView) {
            FilterSelectionView(
                image: selectedMediaItems[currentMediaIndex].image,
                currentFilter: appliedFilters[selectedMediaItems[currentMediaIndex].id]
            ) { filterSettings in
                appliedFilters[selectedMediaItems[currentMediaIndex].id] = filterSettings
                selectedMediaItems[currentMediaIndex].hasEdits = true
                // Apply filter to image
            }
        }
    }
}

// MARK: - Caption and Details View
struct CaptionAndDetailsView: View {
    @Binding var selectedMediaItems: [ProcessedMedia]
    @Binding var captionText: String
    @Binding var taggedUsers: [String]
    @Binding var selectedLocation: CLLocationCoordinate2D?
    @Binding var locationName: String
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool
    
    @StateObject private var uploadService = BackgroundMomentUploadService.shared
    
    @State private var isPublishing = false
    @State private var showingUserSearch = false
    @State private var showingLocationPicker = false
    @State private var showingAudience = false
    @State private var audienceSetting: AudienceSetting = .everyone
    
    // New variables for custom lists
    @State private var selectedListId: String?
    @State private var selectedListName: String?
    @State private var customSelectedUsers: [String] = []
    
    @FocusState private var isCaptionFocused: Bool
    
    enum AudienceSetting {
        case everyone
        case mutuals
        case admirers
        case bestFriends
        case custom
        
        var title: String {
            switch self {
            case .everyone: return NSLocalizedString("audience.type.everyone", comment: "Everyone audience type")
            case .mutuals: return NSLocalizedString("audience.type.connections", comment: "Connections audience type")
            case .admirers: return NSLocalizedString("audience.type.connections", comment: "Connections audience type (admirers maps to connections)")
            case .bestFriends: return NSLocalizedString("audience.type.bestFriends", comment: "Best friends audience type")
            case .custom: return NSLocalizedString("audience.type.custom", comment: "Custom audience type")
            }
        }
        
        var icon: String {
            switch self {
            case .everyone: return "globe"
            case .mutuals: return "person.2.fill"
            case .admirers: return "person.3"
            case .bestFriends: return "star"
            case .custom: return "gearshape"
            }
        }
    }
    
    // New function to map AudienceSetting to ContentAudience
    func toContentAudience() -> ContentAudience {
        switch audienceSetting {
        case .everyone: return .everyone
        case .mutuals: return .connections
        case .admirers: return .connections
        case .bestFriends: return .bestFriends
        case .custom: return selectedListId != nil ? .customList : .custom
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: {
                            currentFlow = .mediaEditing
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        Text("creator.newMoment")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: {
                            publishMoment()
                        }) {
                            if isPublishing {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                Text("creator.share")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                        }
                        .disabled(isPublishing)
                    }
                    .padding()
                    .background(Color.black)
                    
                    ScrollView {
                        VStack(spacing: 0) {
                            // Caption section
                            HStack(alignment: .top, spacing: 12) {
                                // Media preview
                                if let firstMedia = selectedMediaItems.first {
                                    Image(uiImage: firstMedia.image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 65, height: 65)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                
                                // Caption input
                                VStack(alignment: .leading, spacing: 8) {
                                    ZStack(alignment: .topLeading) {
                                        TextEditor(text: $captionText)
                                            .font(.system(size: 16))
                                            .foregroundColor(.white)
                                            .scrollContentBackground(.hidden)
                                            .background(Color.clear)
                                            .frame(minHeight: 80)
                                            .focused($isCaptionFocused)
                                        
                                        if captionText.isEmpty {
                                            Text("creator.caption.placeholder")
                                                .font(.system(size: 16))
                                                .foregroundColor(.gray)
                                                .padding(.top, 8)
                                                .padding(.leading, 4)
                                                .allowsHitTesting(false)
                                        }
                                    }
                                    
                                    if selectedMediaItems.count > 1 {
                                        Text(String(format: NSLocalizedString("creator.files.selected.count", comment: "Files selected count"), selectedMediaItems.count))
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding()
                            
                            Divider()
                                .background(Color.gray.opacity(0.3))
                            
                            // Options
                            VStack(spacing: 0) {
                                // Tag people
                                OptionRow(
                                    icon: "person.crop.circle.badge.plus",
                                    title: "Etiquetar personas",
                                    value: taggedUsers.isEmpty ? nil : "\(taggedUsers.count) personas"
                                ) {
                                    showingUserSearch = true
                                }
                                
                                // Add location
                                OptionRow(
                                    icon: "location",
                                    title: "Añadir ubicación",
                                    value: locationName.isEmpty ? nil : locationName
                                ) {
                                    showingLocationPicker = true
                                }
                                
                                // Audience - ✅ ACTUALIZADO para mostrar lista personalizada
                                OptionRow(
                                    icon: getAudienceIcon(),
                                    title: "Audiencia",
                                    value: getAudienceText()
                                ) {
                                    showingAudience = true
                                }
                                
                                // Advanced settings
                                NavigationLink(destination: AdvancedSettingsView()) {
                                    HStack {
                                        Image(systemName: "gearshape")
                                            .foregroundColor(.white)
                                            .frame(width: 30)
                                        
                                        Text("creator.advancedSettings")
                                            .foregroundColor(.white)
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.gray)
                                            .font(.caption)
                                    }
                                    .padding()
                                    .background(Color.gray.opacity(0.1))
                                }
                            }
                        }
                    }
                }
                
                if isPublishing {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("creator.publishing")
                            .foregroundColor(.white)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingUserSearch) {
            UserSearchView(selectedUsers: $taggedUsers)
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView(
                selectedLocation: $selectedLocation,
                locationName: $locationName
            )
        }
        .sheet(isPresented: $showingAudience) {
            // ✅ USAR EL SELECTOR MEJORADO
            AudienceSelectionView(
                selectedAudience: convertToContentAudience(),
                selectedListId: $selectedListId,
                selectedListName: $selectedListName,
                customSelectedUsers: $customSelectedUsers
            )
            .onDisappear {
                // Actualizar audienceSetting basado en la selección
                updateAudienceSetting()
            }
        }
    }
    
    // ✅ NUEVAS FUNCIONES AUXILIARES
    private func getAudienceIcon() -> String {
        if audienceSetting == .custom && selectedListId != nil {
            return "list.bullet.rectangle"
        }
        return audienceSetting.icon
    }
    
    private func getAudienceText() -> String {
        if audienceSetting == .custom {
            if let listName = selectedListName {
                return listName
            } else if !customSelectedUsers.isEmpty {
                return "\(customSelectedUsers.count) personas"
            }
        }
        return audienceSetting.title
    }
    
    private func convertToContentAudience() -> Binding<ContentAudience> {
        Binding<ContentAudience>(
            get: {
                switch audienceSetting {
                case .everyone: return .everyone
                case .mutuals: return .connections
                case .admirers: return .connections
                case .bestFriends: return .bestFriends
                case .custom:
                    return selectedListId != nil ? .customList : .custom
                }
            },
            set: { newValue in
                switch newValue {
                case .everyone: audienceSetting = .everyone
                case .connections: audienceSetting = .mutuals
                case .bestFriends: audienceSetting = .bestFriends
                case .custom: audienceSetting = .custom
                case .customList: audienceSetting = .custom
                case .onlyMe: audienceSetting = .everyone // Fallback
                }
            }
        )
    }
    
    private func updateAudienceSetting() {
        // Esta función se llama cuando el sheet se cierra
        // La lógica ya está manejada por los bindings
    }
    
    // ✅ FUNCIÓN ACTUALIZADA: Publicar momento con soporte para listas
    private func publishMoment() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isPublishing = true
        
        let disableComments = UserDefaults.standard.object(forKey: "disableComments") as? Bool ?? false
        let hideLikeCounts = UserDefaults.standard.object(forKey: "hideLikeCounts") as? Bool ?? false
        let allowSharing = UserDefaults.standard.object(forKey: "allowSharing") as? Bool ?? true
        
        
        // Detectar aspect ratio del primer media item
        var detectedAspectRatio = "1:1" // Default
        if let firstMedia = selectedMediaItems.first {
            detectedAspectRatio = firstMedia.aspectRatio.displayName
            
        }
        
        
        // 🔥 USAR EL SERVICIO DE BACKGROUND UPLOAD
        let uploadingMoment = uploadService.uploadMoment(
            content: captionText,
            mediaItems: selectedMediaItems,
            taggedUsers: taggedUsers.isEmpty ? nil : taggedUsers,
            location: locationName.isEmpty ? nil : locationName,
            locationCoordinate: selectedLocation != nil ? Moment.LocationCoordinate(
                latitude: selectedLocation!.latitude,
                longitude: selectedLocation!.longitude
            ) : nil,  // ✅ NUEVO: Convertir coordenadas a LocationCoordinate
            audienceSetting: audienceSetting,
            customViewers: customSelectedUsers.isEmpty ? nil : customSelectedUsers,
            customListId: selectedListId,
            aspectRatio: detectedAspectRatio,
            disableComments: disableComments,
            hideLikeCounts: hideLikeCounts,
            allowSharing: allowSharing
        )
        
        // 🔥 CERRAR PANTALLA INMEDIATAMENTE
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.isPublishing = false
            self.showCreatorView = false
            
            if uploadingMoment != nil {
                
                // 🎉 Feedback háptico de éxito
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                // 🧹 Limpiar formulario para próximo uso
                self.resetForm()
                
                // 📊 Analytics
                AnalyticsService.shared.trackInteraction("moment_published_background", details: [
                    "mediaCount": selectedMediaItems.count,
                    "hasCaption": !captionText.isEmpty,
                    "hasLocation": !locationName.isEmpty,
                    "audienceType": audienceSetting.title
                ])
                
            } else {
                
                // ❌ Feedback háptico de error
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.error)
                
                // Mostrar error (opcional)
                // Podrías agregar una alerta aquí si quieres
            }
        }
    }
    
    // 🧹 NUEVA FUNCIÓN: Limpiar formulario después de publicar
    private func resetForm() {
        captionText = ""
        taggedUsers = []
        locationName = ""
        selectedLocation = nil
        customSelectedUsers = []
        selectedListId = nil
        selectedListName = nil
        audienceSetting = .everyone
        
    }
}

extension ProcessedMedia.AspectRatio {
    // ✅ NUEVO: Inicializar desde string guardado en Firestore
    init(from string: String?) {
        switch string {
        case "1:1": self = .square
        case "4:5": self = .portrait
        case "16:9": self = .landscape
        case "9:16": self = .nineBySixteen
        default: self = .square // Default fallback
        }
    }
    
    // ✅ NUEVO: Convertir aspect ratio numérico a tipo
    static func fromRatio(_ ratio: CGFloat) -> ProcessedMedia.AspectRatio {
        if ratio > 1.5 {
            return .landscape // 16:9
        } else if ratio < 0.9 {
            return .portrait // 4:5
        } else if ratio < 0.7 {
            return .nineBySixteen // 9:16 (stories)
        } else {
            return .square // 1:1
        }
    }
}

// MARK: - Story Camera View
struct StoryCameraView: View {
    @Binding var selectedMediaItems: [ProcessedMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool
    
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
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewRepresentable(
                cameraPosition: $cameraPosition,
                flashMode: $flashMode,
                isRecording: $isRecording,
                zoomLevel: $zoomLevel,
                capturePhotoTrigger: $capturePhotoTrigger,
                onImageCaptured: { image in
                    handleCapturedImage(image)
                },
                onVideoCaptured: { videoURL in
                    handleCapturedVideo(videoURL)
                }
            )
            .ignoresSafeArea()
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
            
            // Controls overlay
            VStack {
                // Top controls
                HStack {
                    Button(action: {
                        showCreatorView = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    // Flash button
                    Button(action: {
                        toggleFlash()
                    }) {
                        Image(systemName: flashIcon)
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                }
                .padding()
                
                Spacer()
                
                // Recording indicator
                if isRecording {
                    HStack {
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
                
                Spacer()
                
                // Bottom controls
                HStack(alignment: .center, spacing: 50) {
                    // Gallery button with last image preview
                    Button(action: {
                        showingGallery = true
                    }) {
                        if let lastImage = lastGalleryImage {
                            Image(uiImage: lastImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white, lineWidth: 2)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(.black)
                                )
                        }
                    }
                    
                    // Capture button
                    CaptureButton(
                        isRecording: $isRecording,
                        onTap: {
                            takePhoto()
                        },
                        onLongPressStart: { startRecording() },
                        onLongPressEnd: { stopRecording() }
                    )
                    
                    // Switch camera button
                    Button(action: {
                        switchCamera()
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, 50)
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
        }
        .onDisappear {
            stopRecording()
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
        let processedMedia = ProcessedMedia(
            id: UUID().uuidString,
            image: image,
            videoURL: nil,
            type: .image,
            aspectRatio: .nineBySixteen
        )
        selectedMediaItems = [processedMedia]
        currentFlow = .storyEditing
    }
    
    private func handleCapturedVideo(_ videoURL: URL) {
        // Generate thumbnail from video
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        Task {
            do {
                let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)
                
                await MainActor.run {
                    let processedMedia = ProcessedMedia(
                        id: UUID().uuidString,
                        image: thumbnail,
                        videoURL: videoURL,
                        type: .video,
                        aspectRatio: .nineBySixteen
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
            do {
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
            } catch {
            }
        }
    }
}

// MARK: - Capture Button with Long Press
struct CaptureButton: View {
    @Binding var isRecording: Bool
    let onTap: () -> Void
    let onLongPressStart: () -> Void
    let onLongPressEnd: () -> Void
    
    @State private var isPressed = false
    @State private var longPressTimer: Timer?
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 4)
                .frame(width: 80, height: 80)
            
            Circle()
                .fill(isRecording ? Color.red : Color.white)
                .frame(width: isPressed ? 60 : 70, height: isPressed ? 60 : 70)
                .scaleEffect(isRecording ? 0.8 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
                .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
        .scaleEffect(isPressed ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        // Start long press timer
                        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                            if isPressed {
                                onLongPressStart()
                            }
                        }
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    
                    // Cancel timer if it hasn't fired yet
                    if let timer = longPressTimer {
                        timer.invalidate()
                        longPressTimer = nil
                        
                        // If we were recording, stop it, otherwise take photo
                        if isRecording {
                            onLongPressEnd()
                        } else {
                            onTap()
                        }
                    } else if isRecording {
                        // Timer had fired, so we were recording
                        onLongPressEnd()
                    }
                }
        )
    }
}



// MARK: - Camera Preview View Implementation
class CameraPreviewView: UIView {
    weak var delegate: CameraPreviewRepresentable.Coordinator?
    
    private var captureSession: AVCaptureSession?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var currentCamera: AVCaptureDevice?
    private var currentCameraInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var currentFlashMode: AVCaptureDevice.FlashMode = .off
    private var currentZoom: CGFloat = 1.0
    
    var isCurrentlyRecording: Bool {
        return movieOutput?.isRecording ?? false
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCamera()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer?.frame = bounds
    }
    
    private func setupCamera() {
        // Request camera permission first
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else {
                return
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                self?.configureCaptureSession()
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
        
        // Reset zoom
        currentZoom = 1.0
        updateCameraZoom(1.0)
    }
    
    func updateFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        currentFlashMode = mode
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
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func startRecording() {
        guard let movieOutput = movieOutput,
              !movieOutput.isRecording else { return }
        
        let outputURL = createTempVideoURL()
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
    }
    
    func stopRecording() {
        guard let movieOutput = movieOutput,
              movieOutput.isRecording else { return }
        
        movieOutput.stopRecording()
    }
    
    private func createTempVideoURL() -> URL {
        let documentsPath = FileManager.default.temporaryDirectory
        let fileName = "story_video_\(Date().timeIntervalSince1970).mov"
        return documentsPath.appendingPathComponent(fileName)
    }
}

// MARK: - Crop View Implementation
struct CropViewWrapper: UIViewControllerRepresentable {
    let image: UIImage
    let aspectRatio: ProcessedMedia.AspectRatio
    let onComplete: (UIImage, ProcessedMedia.AspectRatio) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let cropViewController = TOCropViewController(croppingStyle: .default, image: image)
        cropViewController.delegate = context.coordinator
        
        // ✅ MEJORADO: Set aspect ratio basado en selección incluyendo landscape
        switch aspectRatio {
        case .square:
            cropViewController.aspectRatioPreset = .presetSquare
            cropViewController.aspectRatioLockEnabled = true
        case .portrait:
            cropViewController.customAspectRatio = CGSize(width: 4, height: 5)
            cropViewController.aspectRatioLockEnabled = true
        case .landscape:
            cropViewController.customAspectRatio = CGSize(width: 16, height: 9)
            cropViewController.aspectRatioLockEnabled = true
        case .nineBySixteen:
            cropViewController.customAspectRatio = CGSize(width: 9, height: 16)
            cropViewController.aspectRatioLockEnabled = true
        }
        
        cropViewController.rotateButtonsHidden = false
        cropViewController.resetButtonHidden = false
        
        // Style the crop controller
        cropViewController.toolbar.tintColor = UIColor.white
        cropViewController.toolbar.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        if let titleLabel = cropViewController.titleLabel {
            titleLabel.textColor = UIColor.white
        }
        cropViewController.view.backgroundColor = UIColor.black
        
        let navController = UINavigationController(rootViewController: cropViewController)
        navController.navigationBar.barStyle = UIBarStyle.black
        navController.navigationBar.tintColor = UIColor.white
        navController.modalPresentationStyle = .fullScreen
        
        return navController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, TOCropViewControllerDelegate {
        let parent: CropViewWrapper
        
        init(_ parent: CropViewWrapper) {
            self.parent = parent
        }
        
        func cropViewController(_ cropViewController: TOCropViewController, didCropTo image: UIImage, with cropRect: CGRect, angle: Int) {
            parent.onComplete(image, parent.aspectRatio)
            parent.dismiss()
        }
        
        func cropViewControllerDidCancel(_ cropViewController: TOCropViewController) {
            parent.dismiss()
        }
    }
}
// MARK: - Filter Selection Implementation

struct FilterSelectionView: View {
    let image: UIImage
    let currentFilter: FilterSettings?
    let onSelect: (FilterSettings) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedFilter: FilterType = .original
    @State private var filterIntensity: Double = 1.0
    
    enum FilterType: String, CaseIterable {
        case original = "Original"
        case clarendon = "Clarendon"
        case gingham = "Gingham"
        case moon = "Moon"
        case lark = "Lark"
        case reyes = "Reyes"
        case juno = "Juno"
        case slumber = "Slumber"
        case crema = "Crema"
        case ludwig = "Ludwig"
        case aden = "Aden"
        case perpetua = "Perpetua"
        
        var ciFilterName: String? {
            switch self {
            case .original: return nil
            case .clarendon: return "CIPhotoEffectChrome"
            case .gingham: return "CIPhotoEffectTransfer"
            case .moon: return "CIPhotoEffectTonal"
            case .lark: return "CIPhotoEffectProcess"
            case .reyes: return "CIPhotoEffectFade"
            case .juno: return "CIVignetteEffect"
            case .slumber: return "CIPhotoEffectInstant"
            case .crema: return "CISepiaTone"
            case .ludwig: return "CIPhotoEffectNoir"
            case .aden: return "CIColorMonochrome"
            case .perpetua: return "CIPhotoEffectMono"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Preview
                ZStack {
                    Color.black
                    
                    Image(uiImage: applyFilter(to: image))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
                }
                
                // Intensity slider
                if selectedFilter != .original {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("creator.intensity")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        HStack {
                            Text("0")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            
                            Slider(value: $filterIntensity, in: 0...1)
                                .tint(.white)
                            
                            Text("100")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.5))
                }
                
                // Filter options
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 15) {
                        ForEach(FilterType.allCases, id: \.self) { filter in
                            FilterOption(
                                image: image,
                                filter: filter,
                                isSelected: selectedFilter == filter
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedFilter = filter
                                    if filter == .original {
                                        filterIntensity = 1.0
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color.black)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Aplicar") {
                        let settings = FilterSettings(
                            name: selectedFilter.rawValue,
                            intensity: filterIntensity
                        )
                        onSelect(settings)
                        dismiss()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.large])
    }
    
    private func applyFilter(to inputImage: UIImage) -> UIImage {
        guard selectedFilter != .original,
              let ciImage = CIImage(image: inputImage),
              let filterName = selectedFilter.ciFilterName else {
            return inputImage
        }
        
        let filter = CIFilter(name: filterName)
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        
        // Apply intensity for certain filters
        if filterName == "CISepiaTone" || filterName == "CIColorMonochrome" {
            filter?.setValue(filterIntensity, forKey: kCIInputIntensityKey)
        }
        
        guard let outputImage = filter?.outputImage else { return inputImage }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return inputImage
        }
        
        return UIImage(cgImage: cgImage)
    }
}

struct FilterOption: View {
    let image: UIImage
    let filter: FilterSelectionView.FilterType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    Image(uiImage: applyFilterThumbnail())
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                        )
                }
                
                Text(filter.rawValue)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .gray)
            }
        }
    }
    
    private func applyFilterThumbnail() -> UIImage {
        guard filter != .original,
              let ciImage = CIImage(image: image),
              let filterName = filter.ciFilterName,
              let ciFilter = CIFilter(name: filterName) else {
            return image
        }
        
        ciFilter.setValue(ciImage, forKey: kCIInputImageKey)
        
        guard let outputImage = ciFilter.outputImage else { return image }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return image
        }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - User Search Implementation

struct UserSearchView: View {
    @Binding var selectedUsers: [String]
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @State private var selectedUserIds = Set<String>()
    
    private let firestoreService = FirestoreService()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Buscar usuarios...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.white)
                        .onChange(of: searchText) { _, newValue in
                            searchUsers(query: newValue)
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
                .padding()
                
                // Selected users
                if !selectedUserIds.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(selectedUserIds), id: \.self) { userId in
                                if let user = searchResults.first(where: { $0.id == userId }) {
                                    SelectedUserChip(user: user) {
                                        selectedUserIds.remove(userId)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 10)
                }
                
                // Search results
                if isSearching {
                    HStack {
                        ProgressView()
                            .tint(.white)
                        Text("creator.searching")
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(searchResults) { user in
                                UserSearchRow(
                                    user: user,
                                    isSelected: selectedUserIds.contains(user.id)
                                ) {
                                    toggleUserSelection(user)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .background(Color.black)
            .navigationTitle("Etiquetar personas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") {
                        selectedUsers = Array(selectedUserIds)
                        dismiss()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            // Load initial suggestions
            loadSuggestions()
        }
    }
    
    private func searchUsers(query: String) {
        guard !query.isEmpty else {
            loadSuggestions()
            return
        }
        
        isSearching = true
        
        firestoreService.searchUsers(query: query, limit: 10) { result in
            DispatchQueue.main.async {
                self.isSearching = false
                
                switch result {
                case .success(let users):
                    self.searchResults = users
                case .failure(let error):
                    self.searchResults = []
                }
            }
        }
    }
    
    private func loadSuggestions() {
        // Load suggested users
        searchResults = []
    }
    
    private func toggleUserSelection(_ user: AppUser) {
        if selectedUserIds.contains(user.id) {
            selectedUserIds.remove(user.id)
        } else {
            selectedUserIds.insert(user.id)
        }
    }
}

struct UserSearchRow: View {
    let user: AppUser
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Profile image
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 44, height: 44)
                    
                    if let imagePath = user.profileImagePath {
                        // AsyncImage for profile
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    } else {
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.username)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.title2)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct SelectedUserChip: View {
    let user: AppUser
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Text(user.username)
                .font(.caption)
                .foregroundColor(.white)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue)
        .clipShape(Capsule())
    }
}

// MARK: - Location Picker Implementation

struct LocationPickerView: View {
    @Binding var selectedLocation: CLLocationCoordinate2D?
    @Binding var locationName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var searchText = ""
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.3874, longitude: 2.1686), // Barcelona por defecto
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var showingNearbyPlaces = true
    @State private var nearbyPlaces: [MKMapItem] = []
    @State private var isRequestingLocation = false
    @State private var locationError: String?
    
    @StateObject private var locationManager = LocationUtilities.shared
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(adaptiveColors.secondary)
                    
                    TextField("Buscar ubicación...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(adaptiveColors.primary)
                        .onSubmit {
                            searchLocation()
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            showingNearbyPlaces = true
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(adaptiveColors.secondary)
                        }
                    }
                }
                .padding()
                .background(
                    colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1)
                )
                .cornerRadius(10)
                .padding()
                
                // Map
                Map(coordinateRegion: $region, annotationItems: selectedLocation != nil ? [LocationAnnotation(coordinate: selectedLocation!)] : []) { location in
                    MapMarker(coordinate: location.coordinate, tint: .blue)
                }
                .frame(height: 200)
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Current location button
                HStack {
                    Button(action: {
                        requestCurrentLocation()
                    }) {
                        HStack {
                            if isRequestingLocation {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.blue)
                            } else {
                                Image(systemName: "location.fill")
                            }
                            Text("creator.location.useCurrent")
                        }
                        .foregroundColor(.blue)
                        .padding(.vertical, 8)
                    }
                    .disabled(isRequestingLocation)
                    
                    // Botón para actualizar ubicación si ya tenemos permisos
                    if locationManager.authorizationStatus == .authorizedWhenInUse || 
                       locationManager.authorizationStatus == .authorizedAlways {
                        Button(action: {
                            updateCurrentLocationAndNearbyPlaces()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Actualizar")
                            }
                            .foregroundColor(.green)
                            .padding(.vertical, 8)
                        }
                        .disabled(isRequestingLocation)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Error message
                if let error = locationError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                
                // Places list
                if isSearching {
                    Spacer()
                    ProgressView()
                        .tint(adaptiveColors.accent)
                    Text("creator.searching")
                        .foregroundColor(adaptiveColors.secondary)
                        .padding(.top, 8)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if showingNearbyPlaces {
                                Text("creator.location.nearby")
                                    .font(.headline)
                                    .foregroundColor(adaptiveColors.primary)
                                    .padding(.horizontal)
                                    .padding(.top, 20)
                                    .padding(.bottom, 10)
                            }
                            
                            ForEach(showingNearbyPlaces ? nearbyPlaces : searchResults, id: \.self) { place in
                                LocationRow(place: place) {
                                    selectLocation(place)
                                }
                            }
                        }
                    }
                }
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        colorScheme == .dark ? Color.black : Color.white,
                        colorScheme == .dark ? Color(hex: "1a1a2e").opacity(0.9) : Color.gray.opacity(0.1),
                        colorScheme == .dark ? Color(hex: "16213e").opacity(0.8) : Color.gray.opacity(0.05)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .navigationTitle("Añadir ubicación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .foregroundColor(adaptiveColors.primary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                    .disabled(selectedLocation == nil)
                }
            }
            .toolbarBackground(
                colorScheme == .dark ? Color.black : Color.white,
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            loadNearbyPlaces()
        }
        .onReceive(locationManager.$currentLocation) { location in
            if let location = location, isRequestingLocation {
                let coordinate = location.coordinate
                selectedLocation = coordinate
                
                // Usar geocoding inverso para obtener el nombre real de la ubicación
                getLocationNameFromCoordinates(coordinate)
                
                withAnimation {
                    region.center = coordinate
                }
                isRequestingLocation = false
                loadNearbyPlaces() // Recargar lugares cercanos con nueva ubicación
            }
        }
        .onReceive(locationManager.$authorizationStatus) { status in
            if status == .denied || status == .restricted {
                locationError = "Permisos de ubicación denegados. Ve a Ajustes > Privacidad > Ubicación"
                isRequestingLocation = false
            }
        }
    }
    
    private func searchLocation() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        showingNearbyPlaces = false
        
        // Usar ubicación del usuario si está disponible, si no usar la región del mapa
        let searchRegion = locationManager.currentLocation != nil ? 
            MKCoordinateRegion(
                center: locationManager.currentLocation!.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            ) : region
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = searchRegion
        request.resultTypes = [.pointOfInterest, .address] // Incluir direcciones y POIs
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                isSearching = false
                
                if let response = response {
                    // Ordenar resultados por relevancia y distancia
                    let sortedResults = response.mapItems.sorted { item1, item2 in
                        // Priorizar lugares con nombre
                        let hasName1 = item1.name != nil && !item1.name!.isEmpty
                        let hasName2 = item2.name != nil && !item2.name!.isEmpty
                        
                        if hasName1 != hasName2 {
                            return hasName1
                        }
                        
                        // Si ambos tienen nombre, priorizar por tipo (POI primero)
                        if hasName1 && hasName2 {
                            let isPOI1 = item1.pointOfInterestCategory != nil
                            let isPOI2 = item2.pointOfInterestCategory != nil
                            if isPOI1 != isPOI2 {
                                return isPOI1
                            }
                        }
                        
                        return true
                    }
                    
                    searchResults = sortedResults
                } else {
                    searchResults = []
                }
            }
        }
    }
    
    private func loadNearbyPlaces() {
        // Priorizar ubicación del usuario, luego ubicación seleccionada, luego región por defecto
        let centerCoordinate: CLLocationCoordinate2D
        
        if let currentLocation = locationManager.currentLocation {
            centerCoordinate = currentLocation.coordinate
        } else if let selectedLocation = selectedLocation {
            centerCoordinate = selectedLocation
        } else {
            centerCoordinate = region.center
        }
        
        let searchRegion = MKCoordinateRegion(
            center: centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        
        // Búsqueda más específica para lugares útiles
        let searchQueries = [
            "restaurantes",
            "cafés",
            "tiendas",
            "parques",
            "museos",
            "hoteles",
            "farmacias",
            "bancos",
            "estaciones de metro",
            "bibliotecas"
        ]
        
        var allPlaces: [MKMapItem] = []
        let group = DispatchGroup()
        
        for query in searchQueries.prefix(5) { // Solo usar los primeros 5 para no sobrecargar
            group.enter()
            
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = searchRegion
            request.resultTypes = .pointOfInterest
            
            let search = MKLocalSearch(request: request)
            search.start { response, error in
                defer { group.leave() }
                
                if let response = response {
                    DispatchQueue.main.async {
                        allPlaces.append(contentsOf: response.mapItems.prefix(3)) // Máximo 3 por categoría
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            // Filtrar duplicados y ordenar por distancia
            let uniquePlaces = Array(Set(allPlaces)).prefix(15)
            self.nearbyPlaces = Array(uniquePlaces)
        }
    }
    
    private func requestCurrentLocation() {
        isRequestingLocation = true
        locationError = nil
        
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestLocationPermission()
        case .denied, .restricted:
            locationError = "Permisos de ubicación denegados. Ve a Ajustes > Privacidad > Ubicación"
            isRequestingLocation = false
        case .authorizedWhenInUse, .authorizedAlways:
            if let currentLocation = locationManager.currentLocation {
                let coordinate = currentLocation.coordinate
                selectedLocation = coordinate
                
                // Usar geocoding inverso para obtener el nombre real de la ubicación
                getLocationNameFromCoordinates(coordinate)
                
                withAnimation {
                    region.center = coordinate
                }
                isRequestingLocation = false
            } else {
                // Si no hay ubicación actual, solicitar una nueva
                locationManager.requestLocationPermission()
            }
        @unknown default:
            locationError = "Estado de permisos desconocido"
            isRequestingLocation = false
        }
    }
    
    private func getLocationNameFromCoordinates(_ coordinate: CLLocationCoordinate2D) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    // Generar nombre limpio y conciso (estilo Instagram)
                    self.locationName = self.generateCleanLocationName(from: placemark)
                } else {
                    self.locationName = "Ubicación actual"
                }
            }
        }
    }
    
    private func generateCleanLocationName(from placemark: CLPlacemark) -> String {
        // Priorizar el nombre del lugar si existe
        if let name = placemark.name, !name.isEmpty {
            // Si es un lugar específico, usar solo el nombre + ciudad
            if let locality = placemark.locality, !locality.isEmpty {
                return "\(name), \(locality)"
            }
            return name
        }
        
        // Si no hay nombre específico, usar calle + ciudad
        if let thoroughfare = placemark.thoroughfare, !thoroughfare.isEmpty {
            if let locality = placemark.locality, !locality.isEmpty {
                return "\(thoroughfare), \(locality)"
            }
            return thoroughfare
        }
        
        // Fallback a ciudad
        if let locality = placemark.locality, !locality.isEmpty {
            return locality
        }
        
        if let administrativeArea = placemark.administrativeArea, !administrativeArea.isEmpty {
            return administrativeArea
        }
        
        return "Ubicación actual"
    }
    
    private func updateCurrentLocationAndNearbyPlaces() {
        isRequestingLocation = true
        locationError = nil
        
        // Solicitar nueva ubicación
        locationManager.requestLocationPermission()
        
        // También actualizar la región del mapa si tenemos ubicación actual
        if let currentLocation = locationManager.currentLocation {
            let coordinate = currentLocation.coordinate
            
            // Actualizar la región del mapa
            withAnimation {
                region.center = coordinate
            }
            
            // Actualizar la ubicación seleccionada si no hay ninguna
            if selectedLocation == nil {
                selectedLocation = coordinate
                getLocationNameFromCoordinates(coordinate)
            }
            
            // Recargar lugares cercanos con la nueva ubicación
            loadNearbyPlaces()
        }
    }
    
    private func selectLocation(_ place: MKMapItem) {
        selectedLocation = place.placemark.coordinate
        locationName = place.name ?? "Ubicación seleccionada"
        
        withAnimation {
            region.center = place.placemark.coordinate
        }
    }
}

struct LocationAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct LocationRow: View {
    let place: MKMapItem
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    private var categoryIcon: String {
        guard let category = place.pointOfInterestCategory else { return "mappin" }
        
        switch category {
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer"
        case .store: return "bag"
        case .park: return "tree"
        case .museum: return "building.columns"
        case .hotel: return "bed.double"
        case .pharmacy: return "cross.case"
        case .bank: return "building.columns"
        case .school: return "graduationcap"
        case .hospital: return "cross.case"
        case .gasStation: return "fuelpump"
        case .airport: return "airplane"
        case .beach: return "beach.umbrella"
        case .theater: return "theatermasks"
        case .stadium: return "sportscourt"
        case .university: return "building.columns"
        case .library: return "books.vertical"
        case .postOffice: return "envelope"
        case .police: return "shield"
        case .fireStation: return "flame"
        default: return "mappin"
        }
    }
    
    private var categoryName: String {
        guard let category = place.pointOfInterestCategory else { return "Lugar" }
        
        switch category {
        case .restaurant: return "Restaurante"
        case .cafe: return "Café"
        case .store: return "Tienda"
        case .park: return "Parque"
        case .museum: return "Museo"
        case .hotel: return "Hotel"
        case .pharmacy: return "Farmacia"
        case .bank: return "Banco"
        case .school: return "Escuela"
        case .hospital: return "Hospital"
        case .gasStation: return "Gasolinera"
        case .airport: return "Aeropuerto"
        case .beach: return "Playa"
        case .theater: return "Teatro"
        case .stadium: return "Estadio"
        case .university: return "Universidad"
        case .library: return "Biblioteca"
        case .postOffice: return "Oficina de Correos"
        case .police: return "Policía"
        case .fireStation: return "Bomberos"
        default: return "Lugar"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icono de categoría
                Image(systemName: categoryIcon)
                    .font(.title2)
                    .foregroundColor(adaptiveColors.accent)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name ?? "Ubicación sin nombre")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(adaptiveColors.primary)
                    
                    HStack {
                        Text(categoryName)
                            .font(.caption)
                            .foregroundColor(adaptiveColors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(adaptiveColors.accent.opacity(0.2))
                            .cornerRadius(8)
                        
                        if let address = place.placemark.title {
                            Text(address)
                                .font(.caption)
                                .foregroundColor(adaptiveColors.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(adaptiveColors.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        Divider()
            .background(
                colorScheme == .dark ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2)
            )
    }
}

// MARK: - Advanced Settings Implementation

struct AdvancedSettingsView: View {
    @AppStorage("disableComments") private var disableComments = false
    @AppStorage("hideLikeCounts") private var hideLikeCounts = false
    @AppStorage("allowSharing") private var allowSharing = true
    @Environment(\.colorScheme) private var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        ZStack {
            // ✅ Fondo adaptativo
            LinearGradient(
                gradient: Gradient(colors: [
                    colorScheme == .dark ? Color.black : Color.white,
                    colorScheme == .dark ? Color(hex: "1a1a2e").opacity(0.9) : Color.gray.opacity(0.1),
                    colorScheme == .dark ? Color(hex: "16213e").opacity(0.8) : Color.gray.opacity(0.05)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            List {
                Section(header: Text("creator.interactions.title")
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(adaptiveColors.secondary)) {
                    Toggle(isOn: $disableComments) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("creator.interactions.disableComments")
                                .font(.custom("Poppins-Medium", size: 16))
                                .foregroundColor(adaptiveColors.primary)
                            Text("creator.interactions.disableComments.description")
                                .font(.custom("Poppins-Regular", size: 12))
                                .foregroundColor(adaptiveColors.tertiary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "00A896")))
                    
                    Toggle(isOn: $allowSharing) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("creator.interactions.allowSharing")
                                .font(.custom("Poppins-Medium", size: 16))
                                .foregroundColor(adaptiveColors.primary)
                            Text("creator.interactions.allowSharing.description")
                                .font(.custom("Poppins-Regular", size: 12))
                                .foregroundColor(adaptiveColors.tertiary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "00A896")))
                }
                
                Section(header: Text("creator.visualization.title")
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(adaptiveColors.secondary)) {
                    Toggle(isOn: $hideLikeCounts) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("creator.visualization.hideReactions")
                            .font(.custom("Poppins-Medium", size: 16))
                            .foregroundColor(adaptiveColors.primary)
                        Text("creator.visualization.hideReactions.description")
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(adaptiveColors.tertiary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "00A896")))
                }
            }
            .listStyle(InsetGroupedListStyle())
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(NSLocalizedString("creator.advancedSettings.title", comment: "Advanced Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
    }
}

// MARK: - Story Gallery Picker Implementation

struct StoryGalleryPicker: View {
    let onSelect: (ProcessedMedia) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var selectedImage: UIImage?
    @State private var selectedVideoURL: URL?
    @State private var showingMediaPicker = false
    @State private var showingVideoLengthAlert = false
    @State private var videoDuration: Double = 0
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    var body: some View {
        // ✅ Vista invisible que abre directamente la galería
        Color.clear
            .onAppear {
                // ✅ Verificar permisos antes de abrir el picker
                checkPhotoLibraryPermission()
                
                // ✅ Abrir el picker si el estado inicial permite (authorized, limited, o notDetermined)
                // PHPickerViewController funciona incluso sin permisos, pero es mejor verificar
                if authorizationStatus == .authorized || authorizationStatus == .limited || authorizationStatus == .notDetermined {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showingMediaPicker = true
                    }
                }
            }
            .onChange(of: authorizationStatus) { newStatus in
                // ✅ Abrir el picker cuando cambie el estado a autorizado o limitado
                if (newStatus == .authorized || newStatus == .limited) && !showingMediaPicker {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showingMediaPicker = true
                    }
                }
            }
            .sheet(isPresented: $showingMediaPicker) {
                StoryMediaPicker(
                    selectedImage: $selectedImage,
                    selectedVideoURL: $selectedVideoURL,
                    onSelect: { image, videoURL in
                        if let image = image {
                            // ✅ Imagen seleccionada - ir directamente a edición
                            let media = ProcessedMedia(
                                id: UUID().uuidString,
                                image: image,
                                videoURL: nil,
                                type: .image,
                                aspectRatio: .nineBySixteen
                            )
                            onSelect(media)
                            dismiss()
                        } else if let videoURL = videoURL {
                            // ✅ Video seleccionado - verificar duración
                            let asset = AVAsset(url: videoURL)
                            asset.loadValuesAsynchronously(forKeys: ["duration"]) {
                                DispatchQueue.main.async {
                                    let duration = CMTimeGetSeconds(asset.duration)
                                    
                                    if duration <= 60.0 {
                                        // ✅ Video corto - ir directamente a edición
                                        let imageGenerator = AVAssetImageGenerator(asset: asset)
                                        imageGenerator.appliesPreferredTrackTransform = true
                                        imageGenerator.maximumSize = CGSize(width: 300, height: 300)
                                        
                                        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                                        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { requestedTime, cgImage, actualTime, result, error in
                                            DispatchQueue.main.async {
                                                let thumbnail: UIImage
                                                if let cgImage = cgImage {
                                                    thumbnail = UIImage(cgImage: cgImage)
                                                } else {
                                                    thumbnail = UIImage(systemName: "video.fill") ?? UIImage()
                                                }
                                                
                                                let media = ProcessedMedia(
                                                    id: UUID().uuidString,
                                                    image: thumbnail,
                                                    videoURL: videoURL,
                                                    type: .video,
                                                    aspectRatio: .nineBySixteen
                                                )
                                                onSelect(media)
                                                dismiss()
                                            }
                                        }
                                    } else {
                                        // ✅ Video muy largo - mostrar mensaje informativo
                                        
                                        // Guardar la duración y mostrar alert
                                        videoDuration = duration
                                        showingVideoLengthAlert = true
                                    }
                                }
                            }
                        }
                    }
                )
            }
            .alert("Video muy largo", isPresented: $showingVideoLengthAlert) {
                Button("Entendido") {
                    showingVideoLengthAlert = false
                }
            } message: {
                Text(String(format: NSLocalizedString("creator.video.length.warning", comment: "Video length warning"), String(format: "%.0f", videoDuration)))
            }
            .overlay(
                // ✅ Mostrar mensaje si el permiso está denegado
                Group {
                    if authorizationStatus == .denied || authorizationStatus == .restricted {
                        permissionDeniedOverlay
                    }
                }
            )
    }
    
    // MARK: - Helper Functions
    private func checkPhotoLibraryPermission() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        // Si el estado es notDetermined, solicitar permiso
        if authorizationStatus == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    authorizationStatus = status
                }
            }
        }
    }
    
    // MARK: - Permission Denied Overlay (con instrucciones opcionales)
    private var permissionDeniedOverlay: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white).opacity(0.95)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 60))
                    .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.6))
                
                Text("creator.gallery.permission")
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // ✅ Instrucciones opcionales para el usuario
                VStack(spacing: 12) {
                    Text("creator.permissions.instructions.title")
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text("creator.permissions.instructions.path")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.7))
                        .multilineTextAlignment(.center)
                    
                    Button("creator.permissions.openSettings") {
                        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsUrl)
                        }
                    }
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple, Color.pink]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                }
                
                Button("Cerrar") {
                    dismiss()
                }
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.7))
            }
        }
    }
}

// ✅ StoryMediaPicker que abre directamente la galería (imágenes y videos) - Sin editor nativo
struct StoryMediaPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var selectedVideoURL: URL?
    let onSelect: (UIImage?, URL?) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: StoryMediaPicker
        
        init(_ parent: StoryMediaPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                parent.onSelect(nil, nil)
                parent.dismiss()
                return
            }
            
            
            if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                // ✅ Procesar imagen
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    DispatchQueue.main.async {
                        if let image = object as? UIImage {
                            self.parent.selectedImage = image
                            self.parent.onSelect(image, nil)
                        } else {
                            self.parent.onSelect(nil, nil)
                        }
                        self.parent.dismiss()
                    }
                }
            } else if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                // ✅ Procesar video - cargar en memoria y guardar
                result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.movie.identifier) { data, error in
                    DispatchQueue.main.async {
                        if let videoData = data {
                            
                            // ✅ Guardar datos en archivo temporal
                            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                            let tempFileName = "temp_video_\(UUID().uuidString).mp4"
                            let tempURL = documentsPath.appendingPathComponent(tempFileName)
                            
                            do {
                                // ✅ Escribir datos al archivo
                                try videoData.write(to: tempURL)
                                self.parent.selectedVideoURL = tempURL
                                self.parent.onSelect(nil, tempURL)
                            } catch {
                                self.parent.onSelect(nil, nil)
                            }
                        } else {
                            self.parent.onSelect(nil, nil)
                        }
                        self.parent.dismiss()
                    }
                }
            } else {
                parent.onSelect(nil, nil)
                parent.dismiss()
            }
        }
    }
}



// MARK: - Story Text Editor Implementation

struct StoryTextEditor: View {
    @Binding var text: String
    @Binding var selectedStyle: StoryEditingView.TextStyle
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    
    @State private var textColor: Color = .white
    @State private var textAlignment: TextAlignment = .center
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }
            
            VStack(spacing: 0) {
                Spacer()
                
                // Text input area
                VStack(spacing: 20) {
                    TextField("", text: $text, prompt: Text("creator.addText").foregroundColor(.gray))
                        .font(selectedStyle.font)
                        .foregroundColor(textColor)
                        .multilineTextAlignment(textAlignment)
                        .focused($isTextFieldFocused)
                        .padding()
                        .background(selectedStyle.backgroundColor)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    
                    // Style options
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach([StoryEditingView.TextStyle.modern, .classic, .neon, .typewriter, .bold], id: \.self) { style in
                                TextStyleOption(
                                    style: style,
                                    isSelected: selectedStyle == style
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedStyle = style
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Color picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach([Color.white, .black, .red, .orange, .yellow, .green, .blue, .purple, .pink], id: \.self) { color in
                                ColorOption(
                                    color: color,
                                    isSelected: textColor == color
                                ) {
                                    textColor = color
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Alignment options
                    HStack(spacing: 30) {
                        AlignmentButton(
                            alignment: .leading,
                            currentAlignment: $textAlignment,
                            icon: "text.alignleft"
                        )
                        
                        AlignmentButton(
                            alignment: .center,
                            currentAlignment: $textAlignment,
                            icon: "text.aligncenter"
                        )
                        
                        AlignmentButton(
                            alignment: .trailing,
                            currentAlignment: $textAlignment,
                            icon: "text.alignright"
                        )
                    }
                    .padding()
                }
                
                // Done button
                Button(action: {
                    dismiss()
                }) {
                    Text("creator.done")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                .padding(.bottom)
            }
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

struct TextStyleOption: View {
    let style: StoryEditingView.TextStyle
    let isSelected: Bool
    let onTap: () -> Void
    
    var stylePreview: String {
        switch style {
        case .modern: return "Aa"
        case .classic: return "Aa"
        case .neon: return "AA"
        case .typewriter: return "Aa"
        case .bold: return "Aa"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            Text(stylePreview)
                .font(style.font)
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(
                    ZStack {
                        style.backgroundColor
                        
                        if style.backgroundColor == .clear {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        }
                    }
                )
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                )
        }
    }
}

struct ColorOption: View {
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(color)
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .stroke(color == .white ? Color.gray : Color.white, lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 3)
                        .padding(-4)
                )
        }
    }
}

struct AlignmentButton: View {
    let alignment: TextAlignment
    @Binding var currentAlignment: TextAlignment
    let icon: String
    
    var body: some View {
        Button(action: {
            currentAlignment = alignment
        }) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(currentAlignment == alignment ? .white : .gray)
                .frame(width: 44, height: 44)
                .background(
                    currentAlignment == alignment ? Color.gray.opacity(0.3) : Color.clear
                )
                .cornerRadius(8)
        }
    }
}


// MARK: - Camera Capture Implementation

struct CameraCapture: UIViewControllerRepresentable {
    let onCapture: (ProcessedMedia) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image", "public.movie"]
        picker.delegate = context.coordinator
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 60
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        
        init(_ parent: CameraCapture) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                let media = ProcessedMedia(
                    id: UUID().uuidString,
                    image: image,
                    videoURL: nil,
                    type: .image,
                    aspectRatio: .square
                )
                parent.onCapture(media)
            } else if let videoURL = info[.mediaURL] as? URL {
                // Get thumbnail from video
                let asset = AVAsset(url: videoURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                
                do {
                    let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                    let thumbnail = UIImage(cgImage: cgImage)
                    
                    let media = ProcessedMedia(
                        id: UUID().uuidString,
                        image: thumbnail,
                        videoURL: videoURL,
                        type: .video,
                        aspectRatio: .square
                    )
                    parent.onCapture(media)
                } catch {
                }
            }
            
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}


// MARK: - StoryOverlaysView FINAL - Sin cuadrado X, con navegación funcional
struct StoryOverlaysView: View {
    @Binding var text: String
    @Binding var textPosition: CGPoint
    @Binding var textStyle: StoryEditingView.TextStyle
    @Binding var stickers: [StickerItem]
    @Binding var drawingImage: UIImage?
    
    let onNavigateToProfile: (String) -> Void
    let onNavigateToLocation: (String, CLLocationCoordinate2D?) -> Void
    
    @State private var selectedStickerId: String?
    @State private var isEditingText = false
    @State private var isDraggingItem = false
    @State private var showTrashZone = false
    @State private var isOverTrash = false
    
    var body: some View {
        ZStack {
            // Drawing overlay
            if let drawing = drawingImage {
                Image(uiImage: drawing)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                    .scaleEffect(isDraggingItem && selectedStickerId == nil && !text.isEmpty ? 1.0 :
                                 isDraggingItem && selectedStickerId == nil ? 0.8 : 1.0)
                    .opacity(isDraggingItem && selectedStickerId == nil && text.isEmpty ? 0.8 : 1.0)
                    .allowsHitTesting(true)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !text.isEmpty { return }
                                
                                if !isDraggingItem {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isDraggingItem = true
                                        showTrashZone = true
                                    }
                                }
                                
                                let trashY = UIScreen.main.bounds.height - 150
                                isOverTrash = value.location.y > trashY
                            }
                            .onEnded { value in
                                if !text.isEmpty { return }
                                
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isDraggingItem = false
                                    showTrashZone = false
                                    
                                    if isOverTrash {
                                        drawingImage = nil
                                    }
                                    isOverTrash = false
                                }
                            }
                    )
                    .onTapGesture {
                        // Deseleccionar al tocar el fondo
                        selectedStickerId = nil
                    }
            }
            
            // Text overlay
            if !text.isEmpty {
                Text(text)
                    .font(textStyle.font)
                    .foregroundColor(.white)
                    .padding()
                    .background(textStyle.backgroundColor)
                    .cornerRadius(8)
                    .position(textPosition)
                    .scaleEffect(isDraggingItem && selectedStickerId == nil ? 0.8 : 1.0)
                    .opacity(isDraggingItem && selectedStickerId == nil ? 0.8 : 1.0)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                textPosition = value.location
                                
                                if !isDraggingItem {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isDraggingItem = true
                                        showTrashZone = true
                                    }
                                }
                                
                                let trashY = UIScreen.main.bounds.height - 150
                                isOverTrash = value.location.y > trashY
                            }
                            .onEnded { value in
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isDraggingItem = false
                                    showTrashZone = false
                                    
                                    if isOverTrash {
                                        text = ""
                                    }
                                    isOverTrash = false
                                }
                            }
                    )
                    .onTapGesture {
                        selectedStickerId = nil
                        isEditingText = true
                    }
                    .animation(.easeInOut(duration: 0.2), value: isDraggingItem)
            }
            
            // ✅ STICKERS COMPLETAMENTE LIBRES - Sin interfaz de selección
            ForEach(stickers.indices, id: \.self) { index in
                StickerOverlayView(
                    sticker: $stickers[index], // ✅ USAR BINDING PARA ACTUALIZACIÓN DIRECTA
                    isSelected: selectedStickerId == stickers[index].id, // Solo para tracking
                    isDragging: isDraggingItem && selectedStickerId == stickers[index].id,
                    onUpdate: { updatedSticker in
                        stickers[index] = updatedSticker
                    },
                    onDelete: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            stickers.remove(at: index)
                            selectedStickerId = nil
                        }
                    },
                    onDragChanged: { position in
                        if !isDraggingItem {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isDraggingItem = true
                                showTrashZone = true
                                selectedStickerId = stickers[index].id
                            }
                        }
                        
                        let trashY = UIScreen.main.bounds.height - 150
                        isOverTrash = position.y > trashY
                    },
                    onDragEnded: { position in
                        withAnimation(.easeOut(duration: 0.2)) {
                            isDraggingItem = false
                            showTrashZone = false
                            
                            if isOverTrash {
                                stickers.remove(at: index)
                            }
                            isOverTrash = false
                        }
                    },
                    onStickerTapped: { tappedSticker in
                        handleStickerTap(tappedSticker)
                        selectedStickerId = tappedSticker.id // Solo para tracking
                    }
                )
            }

            
            // Zona de papelera
            if showTrashZone {
                VStack {
                    Spacer()
                    
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(0.4),
                                Color.black.opacity(0.6)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 200)
                        .ignoresSafeArea()
                        
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(isOverTrash ? Color.red.opacity(0.2) : Color.black.opacity(0.3))
                                    .frame(width: 80, height: 80)
                                    .scaleEffect(isOverTrash ? 1.1 : 1.0)
                                
                                Image(systemName: isOverTrash ? "trash.circle.fill" : "trash.circle")
                                    .font(.system(size: 40))
                                    .foregroundColor(isOverTrash ? .red : .white)
                                    .scaleEffect(isOverTrash ? 1.1 : 1.0)
                            }
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isOverTrash)
                            
                            Text(isOverTrash ? "Soltar para eliminar" : "Arrastra aquí para eliminar")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .opacity(isOverTrash ? 1.0 : 0.8)
                                .animation(.easeInOut(duration: 0.2), value: isOverTrash)
                        }
                        .padding(.bottom, 50)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onTapGesture {
            // Deseleccionar al tocar el fondo
            selectedStickerId = nil
        }

    }
    
    private func handleStickerTap(_ sticker: StickerItem) {
        switch sticker.type {
        case .mention:
            if let username = sticker.interactionData?.username {
                findUserIdByUsername(username) { userId in
                    if let userId = userId {
                        DispatchQueue.main.async {
                            onNavigateToProfile(userId)
                        }
                    }
                }
            }
            
        case .hashtag:
            if let hashtag = sticker.interactionData?.hashtag {
                // Handle hashtag tap
            }
            
        case .location:
            if let interactionData = sticker.interactionData,
               let location = interactionData.location {
                onNavigateToLocation(location, interactionData.locationCoordinate)
            }
            
        case .poll:
            // Handle poll tap
            break
            
        case .question:
            // Handle question tap
            break
            
        case .questionResponse:
            // Handle question response tap
            break
            
        default:
            break
        }
    }
    
    private func findUserIdByUsername(_ username: String, completion: @escaping (String?) -> Void) {
        let firestoreService = FirestoreService()
        firestoreService.searchUsers(query: username, limit: 10) { result in
            switch result {
            case .success(let users):
                if let user = users.first(where: { $0.username.lowercased() == username.lowercased() }) {
                    completion(user.id)
                } else {
                    completion(nil)
                }
            case .failure(let error):
                completion(nil)
            }
        }
    }

    
    // ✅ FUNCIONES AUXILIARES: Mostrar toasts informativos
    private func showUserNotFoundToast(username: String) {
        // Implementar toast: "Usuario @username no encontrado"
    }
    
    private func showHashtagToast(hashtag: String) {
        // Implementar toast: "Ver publicaciones con #hashtag"
    }
    
    private func showLocationToast(location: String) {
        // Implementar toast: "Ver ubicación: location"
    }
    
    private func showPollToast() {
        // Implementar toast: "Toca para votar en la encuesta"
    }
    
    private func showQuestionToast() {
        // Implementar toast: "Toca para responder la pregunta"
    }
    
    private func showQuestionResponseToast() {
        // Implementar toast: "Respuesta anónima compartida"
    }
}


// Vista mejorada para cada sticker individual
struct StickerOverlayView: View {
    @Binding var sticker: StickerItem // ✅ USAR BINDING PARA ACTUALIZACIÓN DIRECTA
    let isSelected: Bool
    let isDragging: Bool
    let onUpdate: (StickerItem) -> Void
    let onDelete: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (CGPoint) -> Void
    let onStickerTapped: (StickerItem) -> Void
    
    @State private var currentPosition: CGPoint
    @State private var scale: CGFloat
    @State private var rotation: Angle
    @State private var showInteractionFeedback = false
    
    init(sticker: Binding<StickerItem>, isSelected: Bool, isDragging: Bool,
         onUpdate: @escaping (StickerItem) -> Void,
         onDelete: @escaping () -> Void,
         onDragChanged: @escaping (CGPoint) -> Void,
         onDragEnded: @escaping (CGPoint) -> Void,
         onStickerTapped: @escaping (StickerItem) -> Void) {
        self._sticker = sticker
        self.isSelected = isSelected
        self.isDragging = isDragging
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.onStickerTapped = onStickerTapped
        _currentPosition = State(initialValue: sticker.wrappedValue.position)
        _scale = State(initialValue: sticker.wrappedValue.scale)
        _rotation = State(initialValue: sticker.wrappedValue.rotation)
    }
    
    var body: some View {
        ZStack {
            // ✅ SOLUCIÓN: Usar AnimatedStickerView para GIFs animados
            if sticker.isAnimated, let gifURL = sticker.gifURL {
                // Para GIFs animados usar AnimatedStickerView
                AnimatedStickerView(sticker: sticker, size: CGSize(width: 100 * scale, height: 100 * scale))
                    .frame(width: 100 * scale, height: 100 * scale)
                    .allowsHitTesting(false) // ✅ PERMITIR QUE LOS GESTOS PASEN AL PADRE
            } else {
                // Para stickers estáticos usar imagen normal
                Image(uiImage: sticker.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100 * scale, height: 100 * scale)
                    .allowsHitTesting(false) // ✅ PERMITIR QUE LOS GESTOS PASEN AL PADRE
            }
        }
        .rotationEffect(rotation)
        .scaleEffect(isDragging ? 0.9 : (showInteractionFeedback ? 1.05 : 1.0))
        .opacity(isDragging ? 0.8 : 1.0)
        .position(currentPosition)
        .contentShape(Rectangle()) // ✅ ASEGURAR QUE TODA EL ÁREA SEA INTERACTIVA
        .onTapGesture {
            handleStickerTap()
        }
        .gesture(
            // ✅ DRAG GESTURE - Completamente libre
            DragGesture()
                .onChanged { value in
                    currentPosition = value.location
                    onDragChanged(value.location)
                    
                    // ✅ ACTUALIZAR DIRECTAMENTE EL BINDING
                    sticker.position = currentPosition
                }
                .onEnded { value in
                    onDragEnded(value.location)
                }
        )
        .simultaneousGesture(
            // ✅ PINCH TO SCALE - Completamente libre, rango amplio
            MagnificationGesture()
                .onChanged { value in
                    // ✅ NO PERMITIR ESCALAR POLLS, QUESTIONS, LOCATIONS, HASHTAGS Y QUESTION RESPONSES
                    if sticker.type == .poll || sticker.type == .question || sticker.type == .location || sticker.type == .hashtag || sticker.type == .questionResponse {
                        return
                    }
                    let newScale = sticker.scale * value
                    scale = min(max(newScale, 0.2), 5.0) // Rango muy amplio
                }
                .onEnded { value in
                    // ✅ ACTUALIZAR DIRECTAMENTE EL BINDING
                    if sticker.type != .poll && sticker.type != .question && sticker.type != .location && sticker.type != .hashtag && sticker.type != .questionResponse {
                        sticker.scale = scale
                    }
                }
        )
        .simultaneousGesture(
            // ✅ ROTATION GESTURE - Completamente libre
            RotationGesture()
                .onChanged { value in
                    rotation = sticker.rotation + value
                }
                .onEnded { value in
                    // ✅ ACTUALIZAR DIRECTAMENTE EL BINDING
                    sticker.rotation = rotation
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showInteractionFeedback)
        .animation(.easeInOut(duration: 0.1), value: isDragging)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: scale)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: rotation)
    }
    
    private func handleStickerTap() {
        // ✅ Feedback visual MUY sutil
        withAnimation(.spring(response: 0.15, dampingFraction: 0.9)) {
            showInteractionFeedback = true
        }
        
        // ✅ Feedback háptico ligero
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // ✅ Llamar al handler
        onStickerTapped(sticker)
        
        // Reset feedback visual rápido
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.15)) {
                showInteractionFeedback = false
            }
        }
    }
}

// MARK: - Interfaz de selección moderna y elegante
struct ModernSelectionInterface: View {
    let size: CGSize
    let scale: CGFloat
    @Binding var isScaling: Bool
    @Binding var isRotating: Bool
    let onScaleChanged: (CGFloat) -> Void
    let onRotationChanged: (Angle) -> Void
    let onDelete: () -> Void
    
    @State private var initialScale: CGFloat = 1.0
    @State private var initialRotation: Angle = .zero
    @State private var showDeleteButton = false
    
    var body: some View {
        ZStack {
            // ✅ BORDE ELEGANTE - Solo líneas en las esquinas
            CornerBorders(size: size)
            
            // ✅ CONTROLES EN LAS ESQUINAS
            VStack {
                HStack {
                    // Botón eliminar (esquina superior izquierda)
                    DeleteButton(onDelete: onDelete)
                    
                    Spacer()
                    
                    // Control de rotación (esquina superior derecha)
                    RotationControl(
                        scale: scale,
                        isRotating: $isRotating,
                        onRotationChanged: { newRotation in
                            onRotationChanged(newRotation)
                        }
                    )
                }
                
                Spacer()
                
                HStack {
                    Spacer()
                    
                    // Control de escala (esquina inferior derecha)
                    ScaleControl(
                        scale: scale,
                        isScaling: $isScaling,
                        onScaleChanged: { newScale in
                            onScaleChanged(newScale)
                        }
                    )
                }
            }
            .frame(width: size.width + 40, height: size.height + 40)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.2)) {
                showDeleteButton = true
            }
        }
    }
}

// MARK: - Bordes de esquina elegantes
struct CornerBorders: View {
    let size: CGSize
    
    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                CornerBorder()
                    .rotationEffect(.degrees(Double(index * 90)))
            }
        }
        .frame(width: size.width + 20, height: size.height + 20)
    }
}

struct CornerBorder: View {
    var body: some View {
        VStack {
            HStack {
                VStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 2, height: 12)
                    Spacer()
                }
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 12, height: 2)
                    Spacer()
                }
            }
            Spacer()
        }
        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Botón de eliminar moderno
struct DeleteButton: View {
    let onDelete: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            onDelete()
        }) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        .offset(x: -10, y: -10)
    }
}

// MARK: - Control de rotación
struct RotationControl: View {
    let scale: CGFloat
    @Binding var isRotating: Bool
    let onRotationChanged: (Angle) -> Void
    
    @State private var lastRotation: Angle = .zero
    @State private var currentRotation: Angle = .zero
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
            
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .rotationEffect(isRotating ? .degrees(180) : .degrees(0))
                .animation(.easeInOut(duration: 0.3), value: isRotating)
        }
        .offset(x: 10, y: -10)
        .gesture(
            RotationGesture()
                .onChanged { value in
                    if !isRotating {
                        isRotating = true
                        lastRotation = currentRotation
                    }
                    currentRotation = lastRotation + value
                    onRotationChanged(currentRotation)
                }
                .onEnded { value in
                    isRotating = false
                    lastRotation = currentRotation
                }
        )
    }
}

// MARK: - Control de escala
struct ScaleControl: View {
    let scale: CGFloat
    @Binding var isScaling: Bool
    let onScaleChanged: (CGFloat) -> Void
    
    @State private var lastScale: CGFloat = 1.0
    @State private var currentScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
            
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .scaleEffect(isScaling ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isScaling)
        }
        .offset(x: 10, y: 10)
        .onAppear {
            lastScale = scale
            currentScale = scale
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    if !isScaling {
                        isScaling = true
                    }
                    let newScale = lastScale * value
                    currentScale = min(max(newScale, 0.3), 4.0)
                    onScaleChanged(currentScale)
                }
                .onEnded { value in
                    isScaling = false
                    lastScale = currentScale
                }
        )
    }
}



// MARK: - Additional Extensions

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Preview Provider

struct CreatorView_Previews: PreviewProvider {
    static var previews: some View {
        CreatorView(
            isCreatingStory: .constant(false),
            showCreatorView: .constant(true),
            initialSticker: nil
        )
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
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.parent.onImageCaptured(correctedImage)
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
        if let error = error {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.parent.onVideoCaptured(outputFileURL)
        }
    }
}

