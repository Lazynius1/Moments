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
// ProcessedMedia moved to CreatorSharedModels.swift
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
    private var brushWidth: CGFloat = 7
    private var isEraserSelected = false
    private var colorButtons: [UIButton] = []
    private weak var penButton: UIButton?
    private weak var neonButton: UIButton?
    private weak var markerButton: UIButton?
    private weak var arrowButton: UIButton?
    private weak var eraserButton: UIButton?

    enum BrushType {
        case pen, neon, marker, arrow
    }
    private var selectedBrush: BrushType = .pen

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = .clear

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

            let dimView = UIView()
            dimView.translatesAutoresizingMaskIntoConstraints = false
            dimView.backgroundColor = UIColor.black.withAlphaComponent(0.10)
            view.addSubview(dimView)
            NSLayoutConstraint.activate([
                dimView.topAnchor.constraint(equalTo: view.topAnchor),
                dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        } else {
            view.backgroundColor = .black
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
        topToolbar.backgroundColor = UIColor.black.withAlphaComponent(0.16)
        topToolbar.layer.cornerRadius = 22
        topToolbar.layer.borderWidth = 1
        topToolbar.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        topToolbar.clipsToBounds = true
        view.addSubview(topToolbar)
        addBlurBackground(to: topToolbar)

        // Close button
        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        closeButton.layer.cornerRadius = 15
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        topToolbar.addSubview(closeButton)

        let undoButton = createToolButton(imageName: "arrow.uturn.backward", action: #selector(undoTapped))
        topToolbar.addSubview(undoButton)

        let redoButton = createToolButton(imageName: "arrow.uturn.forward", action: #selector(redoTapped))
        topToolbar.addSubview(redoButton)

        // Done button
        let doneButton = UIButton(type: .system)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle(NSLocalizedString("creator.done", comment: "Done"), for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        doneButton.layer.cornerRadius = 15
        doneButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        topToolbar.addSubview(doneButton)

        // Bottom toolbar
        let bottomToolbar = UIView()
        bottomToolbar.translatesAutoresizingMaskIntoConstraints = false
        bottomToolbar.backgroundColor = UIColor.black.withAlphaComponent(0.16)
        bottomToolbar.layer.cornerRadius = 26
        bottomToolbar.layer.borderWidth = 1
        bottomToolbar.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        bottomToolbar.clipsToBounds = true
        view.addSubview(bottomToolbar)
        addBlurBackground(to: bottomToolbar)

        // Tool buttons
        let penButton = createToolButton(imageName: "pencil", action: #selector(penSelected))
        let neonButton = createToolButton(imageName: "sparkles", action: #selector(neonSelected))
        let markerButton = createToolButton(imageName: "highlighter", action: #selector(markerSelected))
        let arrowButton = createToolButton(imageName: "arrow.up.right", action: #selector(arrowSelected))
        let eraserButton = createToolButton(imageName: "eraser", action: #selector(eraserSelected))
        let clearButton = createToolButton(imageName: "trash", action: #selector(clearTapped))

        self.penButton = penButton
        self.neonButton = neonButton
        self.markerButton = markerButton
        self.arrowButton = arrowButton
        self.eraserButton = eraserButton

        let toolStack = UIStackView(arrangedSubviews: [penButton, neonButton, markerButton, arrowButton, eraserButton, clearButton])
        toolStack.translatesAutoresizingMaskIntoConstraints = false
        toolStack.axis = .horizontal
        toolStack.distribution = .equalSpacing
        toolStack.spacing = 10
        bottomToolbar.addSubview(toolStack)

        let widthSlider = UISlider()
        widthSlider.translatesAutoresizingMaskIntoConstraints = false
        widthSlider.minimumValue = 2
        widthSlider.maximumValue = 26
        widthSlider.value = Float(brushWidth)
        widthSlider.minimumTrackTintColor = .white
        widthSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.28)
        widthSlider.thumbTintColor = .white
        widthSlider.addTarget(self, action: #selector(brushWidthChanged(_:)), for: .valueChanged)
        bottomToolbar.addSubview(widthSlider)

        // Color picker
        let colorStack = createColorPicker()
        colorStack.translatesAutoresizingMaskIntoConstraints = false
        bottomToolbar.addSubview(colorStack)

        // Constraints
        NSLayoutConstraint.activate([
            // Canvas
            canvasView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Top toolbar
            topToolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            topToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            topToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            topToolbar.heightAnchor.constraint(equalToConstant: 58),

            // Close button
            closeButton.leadingAnchor.constraint(equalTo: topToolbar.leadingAnchor, constant: 12),
            closeButton.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            // Undo button
            undoButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 10),
            undoButton.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),

            // Redo button
            redoButton.leadingAnchor.constraint(equalTo: undoButton.trailingAnchor, constant: 8),
            redoButton.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),

            // Done button
            doneButton.trailingAnchor.constraint(equalTo: topToolbar.trailingAnchor, constant: -12),
            doneButton.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),

            // Bottom toolbar
            bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            bottomToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            bottomToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            bottomToolbar.heightAnchor.constraint(equalToConstant: 154),

            // Tool stack
            toolStack.centerXAnchor.constraint(equalTo: bottomToolbar.centerXAnchor),
            toolStack.topAnchor.constraint(equalTo: bottomToolbar.topAnchor, constant: 14),

            // Width slider
            widthSlider.leadingAnchor.constraint(equalTo: bottomToolbar.leadingAnchor, constant: 16),
            widthSlider.trailingAnchor.constraint(equalTo: bottomToolbar.trailingAnchor, constant: -16),
            widthSlider.topAnchor.constraint(equalTo: toolStack.bottomAnchor, constant: 10),

            // Color stack
            colorStack.centerXAnchor.constraint(equalTo: bottomToolbar.centerXAnchor),
            colorStack.bottomAnchor.constraint(equalTo: bottomToolbar.bottomAnchor, constant: -12),
            colorStack.topAnchor.constraint(equalTo: widthSlider.bottomAnchor, constant: 8)
        ])

        // Setup tool picker
        toolPicker.setVisible(false, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()

        updateCurrentTool()
        updateToolSelectionUI()
        updateColorSelectionUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvasView.becomeFirstResponder()
    }

    private func createToolButton(imageName: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        button.setImage(UIImage(systemName: imageName, withConfiguration: symbolConfig), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        button.layer.cornerRadius = 16
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
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
        colorButtons = buttons

        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal
        stack.spacing = 11
        stack.distribution = .equalSpacing
        return stack
    }

    private func addBlurBackground(to container: UIView) {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        container.insertSubview(blur, at: 0)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: container.topAnchor),
            blur.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
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

    private func updateCurrentTool() {
        guard !isEraserSelected else {
            canvasView.tool = PKEraserTool(.bitmap)
            return
        }

        switch selectedBrush {
        case .pen:
            canvasView.tool = PKInkingTool(.pen, color: selectedColor, width: brushWidth)
        case .neon:
            canvasView.tool = PKInkingTool(.marker, color: selectedColor.withAlphaComponent(0.9), width: max(4, brushWidth * 1.35))
        case .marker:
            canvasView.tool = PKInkingTool(.marker, color: selectedColor.withAlphaComponent(0.40), width: max(10, brushWidth * 2.4))
        case .arrow:
            canvasView.tool = PKInkingTool(.pen, color: selectedColor, width: max(3, brushWidth * 0.9))
        }
    }

    @objc private func eraserSelected() {
        isEraserSelected = true
        updateToolSelectionUI()
        updateCurrentTool()
    }

    @objc private func undoTapped() {
        canvasView.drawing = canvasView.drawing
        canvasView.undoManager?.undo()
    }

    @objc private func redoTapped() {
        canvasView.undoManager?.redo()
    }

    @objc private func clearTapped() {
        canvasView.drawing = PKDrawing()
    }

    @objc private func brushWidthChanged(_ sender: UISlider) {
        brushWidth = CGFloat(sender.value)
        updateCurrentTool()
    }

    @objc private func colorSelected(_ sender: UIButton) {
        selectedColor = sender.backgroundColor ?? .white
        if isEraserSelected {
            isEraserSelected = false
            updateToolSelectionUI()
        }
        updateColorSelectionUI()
        updateCurrentTool()
    }

    @objc private func penSelected() {
        selectedBrush = .pen
        isEraserSelected = false
        updateToolSelectionUI()
        updateCurrentTool()
    }

    @objc private func neonSelected() {
        selectedBrush = .neon
        isEraserSelected = false
        updateToolSelectionUI()
        updateCurrentTool()
    }

    @objc private func markerSelected() {
        selectedBrush = .marker
        isEraserSelected = false
        updateToolSelectionUI()
        updateCurrentTool()
    }

    @objc private func arrowSelected() {
        selectedBrush = .arrow
        isEraserSelected = false
        updateToolSelectionUI()
        updateCurrentTool()
    }

    private func updateColorSelectionUI() {
        for button in colorButtons {
            let isSelected = button.backgroundColor == selectedColor
            button.layer.borderWidth = isSelected ? 3 : 1
            button.layer.borderColor = UIColor.white.cgColor
            button.transform = isSelected ? CGAffineTransform(scaleX: 1.08, y: 1.08) : .identity
        }
    }

    private func updateToolSelectionUI() {
        let active: UIButton? = {
            if isEraserSelected { return eraserButton }
            switch selectedBrush {
            case .pen: return penButton
            case .neon: return neonButton
            case .marker: return markerButton
            case .arrow: return arrowButton
            }
        }()

        let all = [penButton, neonButton, markerButton, arrowButton, eraserButton]
        for button in all {
            let isActive = (button === active)
            button?.backgroundColor = isActive ? UIColor.white.withAlphaComponent(0.28) : UIColor.black.withAlphaComponent(0.22)
            button?.layer.borderWidth = isActive ? 1 : 0
            button?.layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
        }
    }
}
import SwiftUI
import PhotosUI
import Kingfisher
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

// MARK: - Main Creator View
struct CreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isCreatingStory: Bool
    @Binding var showCreatorView: Bool
    let initialSticker: StickerItem? // ✅ NUEVO: Sticker inicial
    let initialMedia: [CreatorMedia]? // ✅ NUEVO: Media inicial (foto/video de fondo)
    let openInStoryMode: Bool // ✅ NUEVO: Abrir directamente en modo historia
    let startInCameraWhenOnlySticker: Bool

    @State private var currentFlow: CreatorFlow = .typeSelection
    @State private var contentType: ContentType = .moment

    init(isCreatingStory: Binding<Bool>, showCreatorView: Binding<Bool>, initialSticker: StickerItem? = nil, initialMedia: [CreatorMedia]? = nil, openInStoryMode: Bool = false, startInCameraWhenOnlySticker: Bool = false) {
        self._isCreatingStory = isCreatingStory
        self._showCreatorView = showCreatorView
        self.initialSticker = initialSticker
        self.initialMedia = initialMedia
        self.openInStoryMode = openInStoryMode
        self.startInCameraWhenOnlySticker = startInCameraWhenOnlySticker

        // ✅ Inicialización de estado sincronizada
        if initialMedia != nil {
            _contentType = State(initialValue: .story)
            _currentFlow = State(initialValue: .storyEditing)
            _responseSticker = State(initialValue: initialSticker)
            _selectedMediaItems = State(initialValue: initialMedia ?? [])
        } else if initialSticker != nil {
            _contentType = State(initialValue: .story)
            _currentFlow = State(initialValue: startInCameraWhenOnlySticker ? .storyCamera : .storyEditing)
            _responseSticker = State(initialValue: initialSticker)
        } else if openInStoryMode {
            _contentType = State(initialValue: .story)
            _currentFlow = State(initialValue: .storyCamera)
        }
    }
    @State private var selectedMediaItems: [CreatorMedia] = []
    @State private var captionText: String = ""
    @State private var taggedUsers: [String] = []
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var locationName: String = ""
    @State private var responseSticker: StickerItem? = nil

    // 🔗 NUEVO: Variables para contexto de cadena
    @State private var pendingChainId: String? = nil
    @State private var pendingChainTitle: String? = nil
    @State private var pendingChainPosition: Int? = nil

    // ✅ Geometry Effect Namespace
    @Namespace private var animation

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
                    showCreatorView: $showCreatorView,
                    animation: animation // ✅ Pass namespace
                )
            case .mediaSelection:
                MediaSelectionView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView,
                    animation: animation // ✅ Pass namespace
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
        .ignoresSafeArea(.keyboard)
        .onChange(of: contentType) { _, newType in
            // ✅ SEGURIDAD CRÍTICA: No cambiar el flujo si ya estamos editando (especialmente con Stickers)
            if initialSticker != nil || responseSticker != nil {
                if currentFlow == .storyEditing { return }
            }

            // ✅ EVITAR RESET: Si ya estamos en edición o cámara story, no sobrescribir el flujo
            guard currentFlow == .typeSelection else { return }

            if newType == .story {
                // ✅ FIX: Si hay un sticker, ir al editor en lugar de la cámara
                if initialMedia != nil {
                    currentFlow = .storyEditing
                } else {
                    currentFlow = .storyCamera
                }
                isCreatingStory = true
            } else {
                currentFlow = .mediaSelection
                isCreatingStory = false
            }
        }
        .onAppear {
            setupResponseStickerListener()
            setupContinueChainListener()

            // Si llega solo un sticker de pregunta, abrimos la cámara primero y lo conservamos para el editor.
            if let sticker = initialSticker {
                if responseSticker == nil { responseSticker = sticker }

                contentType = .story
                if initialMedia != nil || !startInCameraWhenOnlySticker {
                    currentFlow = .storyEditing
                } else {
                    currentFlow = .storyCamera
                }

                isCreatingStory = true
            } else if openInStoryMode {
                isCreatingStory = true
                if currentFlow == .typeSelection {
                    contentType = .story
                    currentFlow = .storyCamera
                }
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

    // ✅ Helper to create gradient image for sticker-only stories
    private func createDefaultGradientImage() -> UIImage {
        let size = UIScreen.main.bounds.size
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let colors = [
                UIColor(Color(hex: "4158D0") ?? .blue).cgColor,
                UIColor(Color(hex: "C850C0") ?? .purple).cgColor,
                UIColor(Color(hex: "FFCC70") ?? .pink).cgColor
            ]

            let gradient = sectionGradient(colors: colors, size: size)
            gradient.render(in: context.cgContext)
        }
    }

    private func sectionGradient(colors: [CGColor], size: CGSize) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.frame = CGRect(origin: .zero, size: size)
        layer.colors = colors
        layer.startPoint = CGPoint(x: 0, y: 0)
        layer.endPoint = CGPoint(x: 1, y: 1)
        return layer
        return layer
    }
}
// MARK: - Content Type Selection ("The Dial")
struct ContentTypeSelectionView: View {
    @Binding var contentType: CreatorView.ContentType
    @Binding var currentFlow: CreatorView.CreatorFlow

    @Binding var showCreatorView: Bool
    var animation: Namespace.ID // ✅ Accept Namespace
    @Environment(\.colorScheme) var colorScheme

    // State
    @State private var selectedMode: CreatorView.ContentType = .moment
    @State private var recentImages: [UIImage] = [] // ✅ Changed to array for collage
    @State private var shutterScale: CGFloat = 1.0
    @State private var isBreathing: Bool = false // ✅ For collage animation
    @State private var hasCameraPermission: Bool = false
    @State private var dialTransientOffset: CGFloat = 0

    // Constants
    private let dialModes: [CreatorView.ContentType] = [.moment, .story]
    private let dialControlWidth: CGFloat = 170
    private let dialControlHeight: CGFloat = 44
    private let dialInnerPadding: CGFloat = 4
    private let dialPillWidth: CGFloat = 84
    private let dialPillHeight: CGFloat = 36

    var body: some View {
        ZStack {
            // 1. Dynamic Background
            backgroundLayer

            // 2. Content & Controls
            VStack(spacing: 0) {
                // Top Toolbar (Close)
                topToolbar

                Spacer()

                // Center Shutter/Trigger
                shutterButton
                    .padding(.bottom, 28)

                // Bottom Dial Selector
                dialSelector
                    .padding(.bottom, 30)
            }
        }
        .onAppear {
            checkCameraPermission()
            loadRecentPhotos()
            // Start breathing animation
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    // MARK: - Components

    private var backgroundLayer: some View {
        ZStack {
            // Base layer
            Color.black.ignoresSafeArea()

            if selectedMode == .moment {
                // Moment: Floating Collage Blur
                if !recentImages.isEmpty {
                    ZStack {
                        ForEach(0..<recentImages.count, id: \.self) { index in
                            FloatingImageView(image: recentImages[index], index: index)
                        }
                    }
                    .ignoresSafeArea()
                    .blur(radius: 8) // ✅ Reduced blur (was 40) to make photos recognizable
                    .overlay(Color.black.opacity(0.15)) // ✅ Reduced opacity (was 0.3)
                    .overlay(
                        // Gradient fade from bottom
                        LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .center)
                            .ignoresSafeArea()
                    )
                    .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                } else {
                    // Placeholder
                    Color.gray.opacity(0.1)
                        .ignoresSafeArea()
                }
            } else {
                // Story: Blurred Camera Feed or Gradient
                if hasCameraPermission {
                    BackgroundCameraView()
                        .ignoresSafeArea()
                        .blur(radius: 10) // ✅ Reduced blur (was 30) to see silhouettes
                        .overlay(Color.black.opacity(0.1)) // ✅ Reduced opacity (was 0.2)
                        .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                } else {
                    // Fallback Gradient
                    LinearGradient(
                        colors: [Color.black, Color.purple.opacity(0.2), Color.pink.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: selectedMode)
    }

    // ✅ NEW: Floating Image View Helper
    private struct FloatingImageView: View {
        let image: UIImage
        let index: Int

        @State private var offset: CGSize = .zero
        @State private var scale: CGFloat = 1.0
        @State private var rotation: Double = 0

        var body: some View {
            GeometryReader { geometry in
                // Calculate quadrant position based on index
                let quadrantX = index % 2 == 0 ? geometry.size.width * 0.25 : geometry.size.width * 0.75
                let quadrantY = index < 2 ? geometry.size.height * 0.25 : geometry.size.height * 0.75

                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.6) // Reduced size slightly to avoid total overlap
                    .position(
                        x: quadrantX + CGFloat.random(in: -30...30),
                        y: quadrantY + CGFloat.random(in: -30...30)
                    )
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(rotation))
                    .offset(offset)
                    .opacity(0.8)
                    .onAppear {
                        // Randomize animation parameters for organic feel
                        let duration = Double.random(in: 15...25)
                        let delay = Double.random(in: 0...5)

                        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true).delay(delay)) {
                            offset = CGSize(
                                width: CGFloat.random(in: -100...100),
                                height: CGFloat.random(in: -100...100)
                            )
                            scale = CGFloat.random(in: 1.1...1.4)
                            rotation = Double.random(in: -10...10)
                        }
                    }
            }
        }
    }

    private var topToolbar: some View {
        HStack {
            Button(action: {
                withAnimation { showCreatorView = false }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .liquidGlass(in: Circle(), interactive: true)
            }
            .padding(.leading)

            Spacer()
        }
        .padding(.top, 10)
    }

    private var shutterButton: some View {
        Button(action: {
            confirmSelection()
        }) {
            ZStack {
                if selectedMode == .moment {
                    // Moment Shutter: Dynamic Memory Stack
                    ZStack {
                        // Card 1 (Bottom)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(-10))
                            .offset(x: -5, y: 0)

                        // Card 2 (Middle)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(5))
                            .offset(x: 5, y: -2)

                        // Card 3 (Top - Photo)
                        Group {
                            if let topImage = recentImages.first {
                                Image(uiImage: topImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 65, height: 65)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                            } else {
                                // Fallback
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .frame(width: 65, height: 65)
                                    .overlay(
                                        Image(systemName: "photo.stack.fill")
                                            .foregroundColor(.black)
                                    )
                            }
                        }
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .frame(width: 80, height: 80) // Hit area container
                    .matchedGeometryEffect(id: "momentSource", in: animation) // ✅ Unfold Source
                } else {
                    // Story Shutter: Ring
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.purple, .pink, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 5
                        )
                        .frame(width: 80, height: 80)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 70, height: 70)
                        )
                        .shadow(color: .purple.opacity(0.4), radius: 15, x: 0, y: 0)
                }
            }
        }
        .scaleEffect(shutterScale)
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                shutterScale = pressing ? 0.9 : 1.0
            }
        }, perform: {})
    }

    private var dialSelector: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule()
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Capsule()
                    .fill(Color.white.opacity(0.055))
                    .frame(width: dialPillWidth, height: dialPillHeight)
                    .liquidGlass(in: Capsule(), interactive: true)
                    .shadow(color: .black.opacity(0.26), radius: 7, x: 0, y: 2)
                    .offset(x: dialPillOffset)

                HStack(spacing: 0) {
                    ForEach(dialModes, id: \.self) { mode in
                        Text(titleFor(mode))
                            .font(.custom("Poppins-Medium", size: 15))
                            .foregroundColor(dialLabelColor(for: mode))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, dialInnerPadding)
                .animation(.smooth(duration: 0.18, extraBounce: 0.01), value: dialVisualMode)

                Capsule()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Capsule())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    dialTransientOffset = constrainedDialTranslation(value.translation.width)
                                }
                            }
                            .onEnded { value in
                                settleDial(
                                    translation: value.translation.width,
                                    locationX: value.location.x,
                                    width: proxy.size.width
                                )
                            }
                    )
            }
        }
        .frame(width: dialControlWidth, height: dialControlHeight)
    }

    private var dialTravel: CGFloat {
        ((dialControlWidth - (dialInnerPadding * 2)) - dialPillWidth) / 2
    }

    private var dialBaseOffset: CGFloat {
        selectedMode == .moment ? -dialTravel : dialTravel
    }

    private var dialPillOffset: CGFloat {
        dialBaseOffset + dialTransientOffset
    }

    private var dialVisualMode: CreatorView.ContentType {
        dialPillOffset <= 0 ? .moment : .story
    }

    private func dialLabelColor(for mode: CreatorView.ContentType) -> Color {
        let isActive = dialVisualMode == mode
        return isActive ? .white.opacity(0.96) : .white.opacity(0.58)
    }

    private func constrainedDialTranslation(_ translation: CGFloat) -> CGFloat {
        let proposedOffset = dialBaseOffset + translation
        let clampedOffset = min(max(proposedOffset, -dialTravel), dialTravel)
        return clampedOffset - dialBaseOffset
    }

    private func settleDial(translation: CGFloat, locationX: CGFloat, width: CGFloat) {
        let threshold = min(width * 0.16, dialTravel * 0.7)
        let targetMode: CreatorView.ContentType

        if translation < -threshold {
            targetMode = .moment
        } else if translation > threshold {
            targetMode = .story
        } else {
            targetMode = locationX < width / 2 ? .moment : .story
        }

        if targetMode != selectedMode {
            HapticManager.shared.selection()
        }

        withAnimation(.smooth(duration: 0.18, extraBounce: 0.01)) {
            selectedMode = targetMode
            dialTransientOffset = 0
        }
    }

    // MARK: - Logic

    private func titleFor(_ mode: CreatorView.ContentType) -> String {
        switch mode {
        case .moment: return NSLocalizedString("creator.moment.title", comment: "Moment")
        case .story: return NSLocalizedString("creator.story.title", comment: "Story")
        }
    }

    private func confirmSelection() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        withAnimation {
            contentType = selectedMode
            switch selectedMode {
            case .moment:
                currentFlow = .mediaSelection
            case .story:
                // ✅ Stop background camera session BEFORE opening real camera
                NotificationCenter.default.post(name: NSNotification.Name("StopBackgroundCameraSession"), object: nil)

                // ✅ Small delay to ensure session is fully released
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    currentFlow = .storyCamera
                }
            }
        }
    }

    private func loadRecentPhotos() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 4

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .fastFormat // ✅ Optimized for speed (Medium Quality)
        options.resizeMode = .fast

        // Use a temporary array to collect images, then update state
        var loadedImages: [UIImage] = []
        let processingGroup = DispatchGroup()

        assets.enumerateObjects { asset, _, _ in
            processingGroup.enter()
            manager.requestImage(for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: options) { image, info in
                if let image = image {
                    // Check if this is a degraded image (thumbnail)
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if !isDegraded {
                        loadedImages.append(image)
                    }
                }
                // Only leave if not degraded, OR just ensure we only use high quality format which calls once
                processingGroup.leave()
            }
        }

        processingGroup.notify(queue: .main) {
            withAnimation {
                self.recentImages = loadedImages
            }
        }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasCameraPermission = true
        case .notDetermined:
            // Don't request yet, just default to gradient to be non-intrusive
            hasCameraPermission = false
        default:
            hasCameraPermission = false
        }
    }
}

// MARK: - Background Camera View Helper
struct BackgroundCameraView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .black

        // Lightweight Session
        let session = AVCaptureSession()
        session.sessionPreset = .medium // Setup for performance since it's blurred

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return controller
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = controller.view.bounds
        controller.view.layer.addSublayer(previewLayer)

        // Store session and layer in Coordinator
        context.coordinator.session = session
        context.coordinator.previewLayer = previewLayer

        // ✅ Listen for stop notification
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("StopBackgroundCameraSession"),
            object: nil,
            queue: .main
        ) { _ in
            context.coordinator.stopSession()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let layer = context.coordinator.previewLayer {
            layer.frame = uiViewController.view.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?

        // ✅ Stop session method
        func stopSession() {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session?.stopRunning()
                self?.session = nil
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            stopSession()
        }
    }
}

// MARK: - Media Selection View
import SwiftUI
import Photos
import AVFoundation

struct MediaSelectionView: View {
    @Binding var selectedMediaItems: [CreatorMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool
    var animation: Namespace.ID // ✅ Accept Namespace

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
        .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
        .matchedGeometryEffect(id: "momentSource", in: animation) // ✅ Unfold Target
        .onAppear {
            requestPhotoLibraryAccess()
        }
        .fullScreenCover(isPresented: $showingCamera) {
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 40, height: 40)
                    .liquidGlass(in: Circle(), interactive: true)
            }

            Spacer()

            Text(NSLocalizedString("creator.newMoment", comment: ""))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Spacer()

            if !selectedAssetIDs.isEmpty {
                GlowSharePill(
                    title: "creator.next",
                    icon: "chevron.right",
                    isSmall: true
                ) {
                    processSelectedAssets()
                }
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .ignoresSafeArea(edges: .top)
        )
        .zIndex(10)
    }

    // MARK: - Preview principal
    private var mainPreviewSection: some View {
        VStack(spacing: 0) {
            // Preview grande del archivo seleccionado
            if let currentAssetID = selectedAssetIDs.last, // Usar el último seleccionado para el preview principal
               let currentAsset = mediaAssets.first(where: { $0.localIdentifier == currentAssetID }) {

                ZStack {
                    // Fondo Cinemático (Blur)
                    if let thumbnail = thumbnails[currentAssetID] {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: UIScreen.main.bounds.width, height: 320)
                            .blur(radius: 30)
                            .opacity(0.6)
                            .overlay(Color.black.opacity(0.2))
                    }

                    if let thumbnail = thumbnails[currentAssetID] {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 300)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                            .padding(.vertical, 10)
                    } else {
                        ProgressView()
                            .tint(.white)
                    }

                    // Indicador de video
                    if currentAsset.mediaType == .video {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: "video.fill")
                                        .font(.caption)
                                    Text(formatDuration(currentAsset.duration))
                                        .font(.caption.bold())
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.5))
                                .clipShape(Capsule())
                                .padding(12)
                            }
                        }
                    }

                    // Botón para deseleccionar rápido
                    VStack {
                        HStack {
                            Button(action: { toggleAssetSelection(currentAsset) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(12)
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                }
                .frame(height: 320)
                .clipped()
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.95)), removal: .opacity))
            }

            // Carrusel de Multiselección
            if selectedAssetIDs.count > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedAssetIDs, id: \.self) { id in
                            if let thumb = thumbnails[id] {
                                ZStack {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 50, height: 50)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(id == selectedAssetIDs.last ? Color.pink : Color.white.opacity(0.3), lineWidth: 2)
                                        )
                                }
                                .onTapGesture {
                                    // Mover al final para que sea el preview principal
                                    if let index = selectedAssetIDs.firstIndex(of: id) {
                                        let item = selectedAssetIDs.remove(at: index)
                                        selectedAssetIDs.append(item)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(
                    (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                        .opacity(colorScheme == .dark ? 0.92 : 0.98)
                )
            }
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
                Button(action: {
                    showingAlbumPicker = true
                }) {
                    HStack(spacing: 6) {
                        Text(selectedAlbum?.title ?? NSLocalizedString("creator.album.recents", comment: "Recents"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.5))
                            .rotationEffect(.degrees(showingAlbumPicker ? 180 : 0))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    .clipShape(Capsule())
                }

                Spacer()

                Button(action: {
                    showingCamera = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14))
                        Text(NSLocalizedString("creator.camera", comment: ""))
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))

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
                .tint(Color(hex: "007AFF"))

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
                    title: NSLocalizedString("creator.album.recents", comment: "Recents"),
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
                    title: collection.localizedTitle ?? NSLocalizedString("creator.album.untitled", comment: "Untitled album"),
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
            if first.title == NSLocalizedString("creator.album.recents", comment: "Recents") { return true }
            if second.title == NSLocalizedString("creator.album.recents", comment: "Recents") { return false }
            return first.assetCount > second.assetCount
        }

        DispatchQueue.main.async {
            self.availableAlbums = albums
            self.selectedAlbum = albums.first
        }
    }

    private func getSmartAlbumTitle(for subtype: PHAssetCollectionSubtype) -> String {
        switch subtype {
        case .smartAlbumFavorites: return NSLocalizedString("creator.album.smart.favorites", comment: "Favorites")
        case .smartAlbumScreenshots: return NSLocalizedString("creator.album.smart.screenshots", comment: "Screenshots")
        case .smartAlbumSelfPortraits: return NSLocalizedString("creator.album.smart.selfies", comment: "Selfies")
        case .smartAlbumVideos: return NSLocalizedString("creator.album.smart.videos", comment: "Videos")
        case .smartAlbumRecentlyAdded: return NSLocalizedString("creator.album.smart.recentlyAdded", comment: "Recently added")
        default: return NSLocalizedString("creator.album.default", comment: "Album")
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

                        let media = CreatorMedia(
                            id: assetID,
                            image: image,
                            videoURL: nil,
                            type: .image,
                            aspectRatio: detectedAspectRatio,
                            recommendedAspectRatio: detectedAspectRatio // ✅ Guardar el aspect ratio detectado como recomendado
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
                        aspectRatio: detectedAspectRatio,
                        recommendedAspectRatio: detectedAspectRatio // ✅ Guardar el aspect ratio detectado como recomendado
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

    private func detectAspectRatio(from image: UIImage) -> CreatorMedia.AspectRatio {
        let imageRatio = image.size.width / image.size.height

        // ✅ MEJORADO: Tolerancia más amplia (15%) para detectar mejor ratios comunes
        let tolerance: CGFloat = 0.15

        // ✅ MEJORADO: Detectar ratios específicos con mayor precisión y tolerancia

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

        // ✅ MEJORADO: Detección por rangos más precisos y amplios
        // Rangos ajustados para cubrir más casos comunes
        if imageRatio < 0.65 {
            // Muy vertical (más vertical que 9:16)
            return .nineBySixteen
        } else if imageRatio < 0.85 {
            // Vertical moderado (entre 9:16 y 4:5)
            return .portrait
        } else if imageRatio < 1.15 {
            // Casi cuadrado o cuadrado (entre 4:5 y 16:9)
            return .square
        } else if imageRatio < 2.0 {
            // Horizontal moderado (16:9 o similar)
            return .landscape
        } else {
            // Muy horizontal (panorámica)
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
                                    Color.pink.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 20, x: 0, y: 10)
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
            Text(NSLocalizedString("creator.album.select", comment: "Select Album"))
                .font(.system(size: 18, weight: .bold))
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
        Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
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
                    Color.pink.opacity(0.3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color.pink, lineWidth: 3)
                        )
                }

                // Indicador de video
                if asset.mediaType == .video {
                    VStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(formatDuration(asset.duration))
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())
                        .padding(6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }

                // Número de selección
                VStack {
                    HStack {
                        Spacer()
                        if let number = selectionNumber {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 22, height: 22)
                                    .shadow(radius: 2)

                                Text("\(number)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(6)
                        } else {
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 22, height: 22)
                                .padding(6)
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
    @Binding var selectedMediaItems: [CreatorMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool

    @Environment(\.colorScheme) var colorScheme

    @State private var currentMediaIndex = 0
    @State private var showingCropView = false
    @State private var showingFilterToolbar = false // Nueva flag para el modo edición filtros
    @State private var appliedFilters: [String: FilterSettings] = [:]

    // Filtro temporal para el modo edición (antes de aplicar)
    @State private var tempFilterType: FilterService.FilterType = .normal
    @State private var tempFilterIntensity: Double = 1.0
    @State private var previewImage: UIImage? = nil
    @State private var filterTask: Task<Void, Never>? = nil

    // ✅ NUEVO: Aspect ratio recomendado (detectado automáticamente de la imagen original)
    private var recommendedAspectRatio: CreatorMedia.AspectRatio {
        guard currentMediaIndex < selectedMediaItems.count else { return .square }
        // Usar el aspect ratio recomendado guardado, o el actual si no hay recomendado
        return selectedMediaItems[currentMediaIndex].recommendedAspectRatio ?? selectedMediaItems[currentMediaIndex].aspectRatio
    }

    var body: some View {

            VStack(spacing: 0) {
                // Header (Branded)
                HStack {
                    if showingFilterToolbar {
                        Button(action: {
                            cancelFilter()
                        }) {
                            Text(NSLocalizedString("common.cancel", comment: ""))
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Text(NSLocalizedString("creator.edit", comment: ""))
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(.white)

                        Spacer()

                        Button(action: {
                            applyFilter()
                        }) {
                            Text(NSLocalizedString("common.done", comment: ""))
                                .foregroundColor(.pink)
                                .font(.system(size: 16, weight: .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.pink.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    } else {
                        Button(action: {
                            currentFlow = .mediaSelection
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(10)
                                .liquidGlass(in: Circle(), interactive: true)
                        }

                        Spacer()

                        Text(NSLocalizedString("creator.edit", comment: ""))
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 5)

                        Spacer()

                        GlowSharePill(title: "creator.next", icon: "arrow.right", isLoading: false) {
                            currentFlow = .captionAndDetails
                        }
                    }
                }
                .padding()
                .background(
                    LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                )

                Spacer()

                // Media preview (con aspecto mejorado)
                ZStack {
                    TabView(selection: $currentMediaIndex) {
                        ForEach(selectedMediaItems.indices, id: \.self) { index in
                            ZStack {
                                if index == currentMediaIndex, let preview = previewImage, showingFilterToolbar {
                                    Image(uiImage: preview)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    Image(uiImage: selectedMediaItems[index].image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                }
                            }
                            .cornerRadius(12)
                            .padding(.horizontal, 10)
                            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.6)

                    // Recommended Dimensions badge
                    VStack {
                        if recommendedAspectRatio != .square || (currentMediaIndex < selectedMediaItems.count && selectedMediaItems[currentMediaIndex].aspectRatio != recommendedAspectRatio) {
                            Text("creator.recommendedDimensions")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                                .padding(.top, 12)
                        }
                        Spacer()
                    }
                }

                Spacer()

                // Bottom Area: Thumbnails, Format and Tools
                VStack(spacing: 0) {
                    if showingFilterToolbar {
                        // Filter Mode View
                        VStack(spacing: 20) {
                            // Intensity Slider
                            if tempFilterType != .normal {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("creator.intensity")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.white.opacity(0.8))
                                        Spacer()
                                        Text("\(Int(tempFilterIntensity * 100))%")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.pink)
                                    }

                                    Slider(value: $tempFilterIntensity, in: 0...1)
                                        .tint(.pink)
                                        .onChange(of: tempFilterIntensity) { _ in
                                            updatePreviewTask()
                                        }
                                }
                                .padding(.horizontal, 25)
                            }

                            // Filter Carousel
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 15) {
                                    ForEach(FilterService.FilterType.allCases, id: \.self) { filter in
                                        FilterOption(
                                            image: selectedMediaItems[currentMediaIndex].image,
                                            filter: filter,
                                            isSelected: tempFilterType == filter
                                        ) {
                                            hapticFeedback(.light)
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                tempFilterType = filter
                                                if filter == .normal {
                                                    tempFilterIntensity = 1.0
                                                }
                                            }
                                            updatePreviewTask()
                                        }
                                    }
                                }
                                .padding(.horizontal, 25)
                            }
                            .frame(height: 140)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.vertical, 20)
                    } else {
                        // Regular Edit Mode View
                        VStack(spacing: 0) {
                            // Media thumbnails
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(selectedMediaItems.indices, id: \.self) { index in
                                        Button(action: {
                                            withAnimation(.spring()) {
                                                currentMediaIndex = index
                                            }
                                        }) {
                                            ZStack {
                                                Image(uiImage: selectedMediaItems[index].image)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 55, height: 55)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                                    .opacity(currentMediaIndex == index ? 1.0 : 0.6)
                                                    .scaleEffect(currentMediaIndex == index ? 1.05 : 0.95)

                                                if currentMediaIndex == index {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(
                                                            LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                                                            lineWidth: 2
                                                        )
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .frame(height: 60)
                            .padding(.bottom, 15)

                            // Controls Row
                            HStack(spacing: 0) {
                                // Aspect ratio selector
                                HStack(spacing: 20) {
                                    ForEach([CreatorMedia.AspectRatio.square, .portrait, .landscape], id: \.self) { ratio in
                                        Button(action: {
                                            if currentMediaIndex < selectedMediaItems.count {
                                                hapticFeedback(.light)
                                                selectedMediaItems[currentMediaIndex].aspectRatio = ratio
                                                showingCropView = true
                                            }
                                        }) {
                                            VStack(spacing: 4) {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(
                                                        selectedMediaItems[currentMediaIndex].aspectRatio == ratio ? Color.pink :
                                                        (ratio == recommendedAspectRatio ? Color.green.opacity(0.6) : Color.white.opacity(0.3)),
                                                        lineWidth: selectedMediaItems[currentMediaIndex].aspectRatio == ratio ? 2 : 1
                                                    )
                                                    .frame(
                                                        width: ratio == .landscape ? 35 : (ratio == .square ? 25 : 20),
                                                        height: 25
                                                    )

                                                Text(ratio.displayName)
                                                    .font(.system(size: 8, weight: .medium))
                                                    .foregroundColor(selectedMediaItems[currentMediaIndex].aspectRatio == ratio ? .pink : .white.opacity(0.6))
                                            }
                                        }
                                    }
                                }
                                .padding(.leading, 20)

                                Spacer()

                                // Editing tools (Glassmorphic)
                                HStack(spacing: 12) {
                                    ToolIconButton(icon: "crop.rotate") { showingCropView = true }
                                    ToolIconButton(icon: "camera.filters") {
                                        enterFilterMode()
                                    }
                                }
                                .padding(.trailing, 20)
                            }
                            .padding(.bottom, 30)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                )
            }
        .navigationBarHidden(true)
        .background(
            ZStack {
                Color.black.ignoresSafeArea()
                if currentMediaIndex < selectedMediaItems.count {
                    Image(uiImage: selectedMediaItems[currentMediaIndex].image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                        .blur(radius: 40)
                        .overlay(Color.black.opacity(0.4))
                        .ignoresSafeArea()
                }
            }
        )
        .sheet(isPresented: $showingCropView) {
            if currentMediaIndex < selectedMediaItems.count {
                // ✅ MEJORADO: Usar el aspect ratio recomendado si el usuario no ha seleccionado uno manualmente
                let currentAspectRatio = selectedMediaItems[currentMediaIndex].aspectRatio
                let aspectRatioToUse = currentAspectRatio == .square && recommendedAspectRatio != .square
                    ? recommendedAspectRatio
                    : currentAspectRatio

                CropViewWrapper(
                    image: selectedMediaItems[currentMediaIndex].image,
                    aspectRatio: aspectRatioToUse,
                    allowFreeCrop: true // ✅ NUEVO: Permitir crop libre (no bloquear ratio)
                ) { croppedImage, newAspectRatio in
                    selectedMediaItems[currentMediaIndex].image = croppedImage
                    selectedMediaItems[currentMediaIndex].aspectRatio = newAspectRatio
                    selectedMediaItems[currentMediaIndex].hasEdits = true
                    // ✅ Reset filter task and applied filters if needed when image changes
                    updatePreviewTask()
                }
            }
        }
    }

    // MARK: - Filter Logic Integration

    private func enterFilterMode() {
        guard currentMediaIndex < selectedMediaItems.count else { return }
        let currentItem = selectedMediaItems[currentMediaIndex]

        // Cargar ajustes actuales si existen
        if let settings = appliedFilters[currentItem.id],
           let type = FilterService.FilterType(rawValue: settings.name) {
            tempFilterType = type
            tempFilterIntensity = settings.intensity
        } else {
            tempFilterType = .normal
            tempFilterIntensity = 1.0
        }

        withAnimation(.spring()) {
            showingFilterToolbar = true
        }
        updatePreviewTask()
    }

    private func cancelFilter() {
        filterTask?.cancel()
        withAnimation(.spring()) {
            showingFilterToolbar = false
            previewImage = nil
        }
    }

    private func applyFilter() {
        guard currentMediaIndex < selectedMediaItems.count else { return }
        let currentItemId = selectedMediaItems[currentMediaIndex].id

        // Guardar ajustes
        let settings = FilterSettings(name: tempFilterType.rawValue, intensity: tempFilterIntensity)
        appliedFilters[currentItemId] = settings

        // Aplicar permanentemente a la imagen de la lista si no es normal
        if let preview = previewImage {
            selectedMediaItems[currentMediaIndex].image = preview
            selectedMediaItems[currentMediaIndex].hasEdits = true
        }

        withAnimation(.spring()) {
            showingFilterToolbar = false
            previewImage = nil
        }
    }

    private func updatePreviewTask() {
        guard currentMediaIndex < selectedMediaItems.count else { return }
        let baseImage = selectedMediaItems[currentMediaIndex].image

        filterTask?.cancel()

        if tempFilterType == .normal {
            previewImage = nil
            return
        }

        let tempFilterType = self.tempFilterType
        let tempFilterIntensity = self.tempFilterIntensity

        filterTask = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 45_000_000)

            if Task.isCancelled { return }

            let filtered = FilterService.shared.applyFilter(tempFilterType, to: baseImage, intensity: tempFilterIntensity)

            if !Task.isCancelled {
                await MainActor.run {
                    self.previewImage = filtered
                }
            }
        }
    }
}

// MARK: - Media Stack Preview
struct MediaStackPreview: View {
    let items: [CreatorMedia]

    var body: some View {
        ZStack {
            ForEach(Array(items.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                Image(uiImage: item.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .rotationEffect(.degrees(Double(index) * 3))
                    .offset(x: CGFloat(index) * 4, y: CGFloat(index) * 2)
            }
        }
    }
}

// MARK: - Caption and Details View
struct CaptionAndDetailsView: View {
    @Binding var selectedMediaItems: [CreatorMedia]
    @Binding var captionText: String
    @Binding var taggedUsers: [String]
    @Binding var selectedLocation: CLLocationCoordinate2D?
    @Binding var locationName: String
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool

    // Total tags across all media
    private var totalTagsCount: Int {
        selectedMediaItems.reduce(0) { $0 + ($1.tags?.count ?? 0) }
    }

    @Environment(\.colorScheme) var colorScheme
    @StateObject private var uploadService = BackgroundMomentUploadService.shared

    @State private var isPublishing = false
    @State private var showingUserSearch = false
    @State private var showingLocationPicker = false
    @State private var showingAudience = false
    @State private var audienceSetting: AudienceSetting = .everyone
    @State private var customViewers: [String] = []
    @State private var customListId: String? = nil

    // Interaction Settings (from AdvancedSettingsView)
    @AppStorage("disableComments") private var disableComments = false
    @AppStorage("hideLikeCounts") private var hideLikeCounts = false
    @AppStorage("allowSharing") private var allowSharing = true

    // Scheduling (New)
    @State private var isSchedulingEnabled = false
    @State private var scheduledDate = Date().addingTimeInterval(3600) // Default to 1 hour from now

    // New variables for custom lists
    @State private var selectedListId: String?
    @State private var selectedListName: String?
    @State private var customSelectedUsers: [String] = []

    @FocusState private var isCaptionFocused: Bool
    @State private var isLaunching = false // 🔥 Control para la animación de lanzamiento
    @State private var isPreviewingMedia = false
    @State private var showingTagSelector = false
    @State private var currentMediaTagIndex = 0
    @State private var tagSelectorDetent: PresentationDetent = .large

    enum AudienceSetting {
        case everyone
        case mutuals
        case admirers
        case bestFriends
        case custom
        case onlyMe

        var title: String {
            switch self {
            case .everyone: return NSLocalizedString("audience.type.everyone", comment: "Everyone audience type")
            case .mutuals: return NSLocalizedString("audience.type.connections", comment: "Connections audience type")
            case .admirers: return NSLocalizedString("audience.type.connections", comment: "Connections audience type (admirers maps to connections)")
            case .bestFriends: return NSLocalizedString("audience.type.bestFriends", comment: "Best friends audience type")
            case .custom: return NSLocalizedString("audience.type.custom", comment: "Custom audience type")
            case .onlyMe: return NSLocalizedString("audience.type.onlyMe", comment: "Only me audience type")
            }
        }

        var icon: String {
            switch self {
            case .everyone: return "globe"
            case .mutuals: return "person.2.fill"
            case .admirers: return "person.3"
            case .bestFriends: return "star"
            case .custom: return "gearshape"
            case .onlyMe: return "lock.fill"
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
        case .onlyMe: return .onlyMe
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                // 1. Immersive Background (Mosaic Blur)
                SelectedMediaBlurView(mediaItems: selectedMediaItems)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: {
                            currentFlow = .mediaEditing
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(10)
                                .liquidGlass(in: Circle(), interactive: true)
                        }

                        Spacer()

                        Text("creator.newMoment")
                            .font(.headline)
                            .foregroundColor(.white)

                        Spacer()

                        GlowSharePill(title: "creator.share", isLoading: isPublishing, action: {
                            publishMoment()
                        })
                    }
                    .padding()


                    ScrollView {
                        VStack(spacing: 15) { // Tight spacing to bring options right under

                            // SECTION 1: Caption & Media Preview
                            HStack(alignment: .top, spacing: 30) { // Aumentado spacing de 20 a 30
                                // Media Preview with "Press to Unfold" gesture
                                ZStack {
                                    MediaStackPreview(items: selectedMediaItems)
                                        .frame(width: 100, height: 150)
                                        .contentShape(Rectangle())
                                        .scaleEffect(isPreviewingMedia ? 0.95 : 1.0)
                                        .onLongPressGesture(minimumDuration: 0.2, pressing: { isPressing in
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                isPreviewingMedia = isPressing
                                            }
                                        }) {
                                            // Action on complete
                                        }

                                    // Helper hint
                                    if !isPreviewingMedia {
                                        Text("creator.media_preview.hint")
                                            .font(.system(size: 8, weight: .bold)) // Un poco más pequeño y bold para legibilidad
                                            .foregroundColor(.white.opacity(0.7))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(.ultraThinMaterial)
                                            .cornerRadius(6)
                                            .offset(y: 60) // Bajado de 50 a 60 para que tape menos la imagen
                                            .allowsHitTesting(false)
                                    }
                                }

                                // Caption Input
                                ZStack(alignment: .topLeading) {
                                    if captionText.isEmpty {
                                        Text("creator.caption.placeholder")
                                            .foregroundColor(.white.opacity(0.6))
                                            .padding(.top, 8)
                                    }

                                    TextEditor(text: $captionText)
                                        .scrollContentBackground(.hidden)
                                        .foregroundColor(.white)
                                        .frame(minHeight: 120) // Restored a bit of height
                                        .tint(.white)
                                        .focused($isCaptionFocused)
                                }
                                .padding(.top, 4) // Tight top-only padding
                            }
                            .padding(.horizontal)
                            .padding(.top, 10) // Tighter top spacing from header

                            // SECTION 2: Options List
                            VStack(spacing: 0) {
                                // Tag people
                                MinimalOptionRow(
                                    icon: "person.crop.circle.badge.plus",
                                    title: NSLocalizedString("creator.tagPeople", comment: "Tag people"),
                                    value: totalTagsCount == 0 ? nil : String.localizedStringWithFormat(NSLocalizedString("audience.people.count", comment: ""), totalTagsCount)
                                ) {
                                    if selectedMediaItems.indices.contains(currentMediaTagIndex) {
                                        tagSelectorDetent = preferredTagSelectorDetent(for: selectedMediaItems[currentMediaTagIndex])
                                    } else {
                                        tagSelectorDetent = .large
                                    }
                                    showingTagSelector = true
                                }

                                Divider().background(Color.white.opacity(0.1)).padding(.leading, 50)

                                // Add location
                                MinimalOptionRow(
                                    icon: "location",
                                    title: NSLocalizedString("creator.addLocation", comment: "Add location"),
                                    value: locationName.isEmpty ? nil : locationName
                                ) {
                                    showingLocationPicker = true
                                }

                                Divider().background(Color.white.opacity(0.1)).padding(.leading, 50)

                                // Audience
                                MinimalOptionRow(
                                    icon: getAudienceIcon(),
                                    title: NSLocalizedString("audience.title", comment: "Audience title"),
                                    value: getAudienceText()
                                ) {
                                    showingAudience = true
                                }

                                Divider().background(Color.white.opacity(0.1)).padding(.leading, 50)

                                // Advanced settings removed (moved to quick access)
                            }
                            .padding(.top, 10) // Pull options closer to preview

                            // SECTION 3: Interaction Settings (Quick Access)
                            VStack(spacing: 0) {
                                Text("creator.interactions.title")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 16)
                                    .padding(.bottom, 8)

                                MinimalToggleRow(
                                    icon: "bubble.left.and.bubble.right",
                                    title: NSLocalizedString("creator.interactions.disableComments", comment: ""),
                                    isOn: $disableComments
                                )

                                Divider().background(Color.white.opacity(0.1)).padding(.leading, 50)

                                MinimalToggleRow(
                                    icon: "heart.slash",
                                    title: NSLocalizedString("creator.visualization.hideReactions", comment: ""),
                                    isOn: $hideLikeCounts
                                )

                                Divider().background(Color.white.opacity(0.1)).padding(.leading, 50)

                                MinimalToggleRow(
                                    icon: "bookmark",
                                    title: NSLocalizedString("creator.interactions.allowSharing", comment: ""),
                                    isOn: $allowSharing
                                )
                            }
                            .padding(.top, 25)

                            // SECTION 4: Scheduling
                            VStack(spacing: 0) {
                                Text("creator.scheduling.title")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 16)
                                    .padding(.bottom, 8)

                                MinimalToggleRow(
                                    icon: "calendar.badge.clock",
                                    title: NSLocalizedString("creator.scheduling.enable", comment: ""),
                                    isOn: $isSchedulingEnabled
                                )

                                if isSchedulingEnabled {
                                    Divider().background(Color.white.opacity(0.1)).padding(.leading, 50)

                                    HStack {
                                        Image(systemName: "clock")
                                            .foregroundColor(.white.opacity(0.7))
                                            .frame(width: 24)

                                        DatePicker(
                                            NSLocalizedString("creator.scheduling.date", comment: ""),
                                            selection: $scheduledDate,
                                            in: Date()...,
                                            displayedComponents: [.date, .hourAndMinute]
                                        )
                                        .colorScheme(.dark)
                                        .accentColor(.pink)
                                        .labelsHidden()

                                        Spacer()

                                        Text(scheduledDate.formatted())
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                }
                            }
                            .padding(.top, 25)
                            .padding(.bottom, 30) // Extra bottom padding for the scroll
                        }
                    }
                }

                    if isPublishing && !isLaunching {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()

                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)

                            Text("creator.publishing")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }

                    // 🔥 OVERLAY DE LANZAMIENTO (Cinematic Handoff)
                    if isLaunching {
                        ZStack {
                            Color.black.ignoresSafeArea()

                            VStack(spacing: 24) {
                                Text(NSLocalizedString("creator.uploading.success_fly", comment: "Successfully shared"))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                        }
                        .transition(.opacity)
                    }

                    // Full Screen Media Preview Overlay
                    if isPreviewingMedia {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .zIndex(99)

                        TabView {
                            ForEach(selectedMediaItems) { item in
                                Image(uiImage: item.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .cornerRadius(20)
                                    .padding()
                                    .shadow(radius: 20)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .frame(height: 500)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .zIndex(100)
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
            AudienceSelectionView(
                selectedAudience: convertToContentAudience(),
                selectedListId: $selectedListId,
                selectedListName: $selectedListName,
                customSelectedUsers: $customSelectedUsers
            )
            .onDisappear {
                updateAudienceSetting()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $showingTagSelector) {
            if !selectedMediaItems.isEmpty {
                PhotoTagSelectionView(mediaItem: $selectedMediaItems[currentMediaTagIndex])
                    .presentationDetents([.medium, .large], selection: $tagSelectorDetent)
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            loadDefaultPostAudience()
        }
    }

    // ✅ FUNCIÓN ACTUALIZADA: Publicar momento con soporte para listas
    private func publishMoment() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        isPublishing = true

        // Use local properties (managed by @AppStorage)
        let finalDisableComments = disableComments
        let finalHideLikeCounts = hideLikeCounts
        let finalAllowSharing = allowSharing
        let finalScheduledDate = isSchedulingEnabled ? scheduledDate : nil


        let detectedAspectRatio = preferredMomentAspectRatio(for: selectedMediaItems)

        // 🔥 USAR EL SERVICIO DE BACKGROUND UPLOAD
        // Combinar etiquetas espaciales con la lista legacy para notificaciones y búsquedas
        let spatialTaggedUsers = selectedMediaItems.flatMap { $0.tags ?? [] }.map { $0.userId }
        let allTaggedUsers = Array(Set(taggedUsers + spatialTaggedUsers))

        let uploadingMoment = uploadService.uploadMoment(
            content: captionText,
            mediaItems: selectedMediaItems,
            taggedUsers: allTaggedUsers.isEmpty ? nil : allTaggedUsers,
            location: locationName.isEmpty ? nil : locationName,
            locationCoordinate: selectedLocation != nil ? Moment.LocationCoordinate(
                latitude: selectedLocation!.latitude,
                longitude: selectedLocation!.longitude
            ) : nil,  // ✅ NUEVO: Convertir coordenadas a LocationCoordinate
            audienceSetting: audienceSetting,
            customViewers: customSelectedUsers.isEmpty ? nil : customSelectedUsers,
            customListId: selectedListId,
            aspectRatio: detectedAspectRatio,
            disableComments: finalDisableComments,
            hideLikeCounts: finalHideLikeCounts,
            allowSharing: finalAllowSharing,
            scheduledDate: finalScheduledDate
        )

        // 🔥 CERRAR PANTALLA CON ANIMACIÓN CINEMÁTICA
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            self.isLaunching = true
        }

        hapticNotification(.success)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.isPublishing = false
            self.showCreatorView = false

            if uploadingMoment != nil {
                // 🧹 Limpiar formulario para próximo uso
                self.resetForm()

                // 📊 Analytics

            } else {
                // ❌ Feedback háptico de error
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.error)

                // Revertir estado si falló el inicio del servicio
                withAnimation {
                    self.isLaunching = false
                }
            }
        }
    }

    private func preferredTagSelectorDetent(for mediaItem: CreatorMedia) -> PresentationDetent {
        let aspectRatio = mediaItem.image.size.width / max(mediaItem.image.size.height, 1)
        return aspectRatio >= 0.95 ? .medium : .large
    }

    private func preferredMomentAspectRatio(for mediaItems: [CreatorMedia]) -> String {
        guard !mediaItems.isEmpty else { return "1:1" }

        let preferredRatios = mediaItems.map { mediaItem -> CreatorMedia.AspectRatio in
            if let recommended = mediaItem.recommendedAspectRatio {
                return recommended
            }

            if mediaItem.aspectRatio != .square {
                return mediaItem.aspectRatio
            }

            let imageRatio = mediaItem.image.size.width / max(mediaItem.image.size.height, 1)
            return CreatorMedia.AspectRatio.fromRatio(imageRatio)
        }

        let mostVerticalRatio = preferredRatios.min { lhs, rhs in
            lhs.value < rhs.value
        } ?? .square

        return mostVerticalRatio.displayName
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

    // MediaStackPreview eliminado (reemplazado por imagen grande inline)

    // ✅ FUNCIONES AUXILIARES RESTAURADAS
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
                case .onlyMe: return .onlyMe
                }
            },
            set: { newValue in
                switch newValue {
                case .everyone: audienceSetting = .everyone
                case .connections: audienceSetting = .mutuals
                case .bestFriends: audienceSetting = .bestFriends
                case .custom: audienceSetting = .custom
                case .customList: audienceSetting = .custom
                case .onlyMe: audienceSetting = .onlyMe
                }
            }
        )
    }

    private func updateAudienceSetting() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let audienceRaw: String
        switch audienceSetting {
        case .everyone:    audienceRaw = ContentAudience.everyone.rawValue
        case .mutuals:     audienceRaw = ContentAudience.connections.rawValue
        case .admirers:    audienceRaw = ContentAudience.connections.rawValue
        case .bestFriends: audienceRaw = ContentAudience.bestFriends.rawValue
        case .custom:      audienceRaw = (selectedListId != nil) ? ContentAudience.customList.rawValue : ContentAudience.custom.rawValue
        case .onlyMe:      audienceRaw = ContentAudience.onlyMe.rawValue
        }

        var update: [String: Any] = [
            "contentVisibilitySettings.postAudience": audienceRaw
        ]
        if let listId = selectedListId {
            update["contentVisibilitySettings.postCustomListId"] = listId
            update["contentVisibilitySettings.postCustomListName"] = selectedListName ?? ""
        }
        if !customSelectedUsers.isEmpty {
            update["contentVisibilitySettings.postCustomUsers"] = customSelectedUsers
        }

        FirestoreService().db.collection("users").document(userId).updateData(update)
    }

    private func loadDefaultPostAudience() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        FirestoreService().db.collection("users").document(userId).getDocument { document, _ in
            DispatchQueue.main.async {
                guard let data = document?.data(),
                      let visibilitySettings = data["contentVisibilitySettings"] as? [String: Any] else { return }

                if let postAudienceRaw = visibilitySettings["postAudience"] as? String,
                   let contentAudience = ContentAudience(rawValue: postAudienceRaw) {
                    switch contentAudience {
                    case .everyone:    self.audienceSetting = .everyone
                    case .connections: self.audienceSetting = .mutuals
                    case .bestFriends: self.audienceSetting = .bestFriends
                    case .custom:
                        self.audienceSetting = .custom
                        self.customSelectedUsers = visibilitySettings["postCustomUsers"] as? [String] ?? []
                    case .customList:
                        self.audienceSetting = .custom
                        self.selectedListId = visibilitySettings["postCustomListId"] as? String
                        self.selectedListName = visibilitySettings["postCustomListName"] as? String
                    case .onlyMe:      self.audienceSetting = .onlyMe
                    }
                }
            }
        }
    }

    private func hapticNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    // MARK: - 📍 MINIMAL OPTION ROW (Clean Design)

    struct MinimalOptionRow: View {
        let icon: String
        let title: String
        let value: String?
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                MinimalOptionRowContent(icon: icon, title: title, value: value)
            }
            .pressAnimation()
        }
    }

    struct MinimalToggleRow: View {
        let icon: String
        let title: String
        @Binding var isOn: Bool

        var body: some View {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 32)

                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Spacer()

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(.pink)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }

    struct MinimalOptionRowContent: View {
        let icon: String
        let title: String
        let value: String?

        var body: some View {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 32)

                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Spacer()

                if let value = value {
                    Text(value)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.7))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .contentShape(Rectangle()) // Full width tap area
        }
    }
}

extension CreatorMedia.AspectRatio {
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

    // ✅ NOTA: La función fromRatio está definida dentro del enum AspectRatio (línea 78)
    // para usar la lógica mejorada de detección con tolerancia y rangos más precisos
}

// MARK: - Story Camera View
struct StoryCameraView: View {
    @Binding var selectedMediaItems: [CreatorMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var safeAreaTintColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
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
            let captureRect = momentsCaptureRect(in: proxy.size, topInset: proxy.safeAreaInsets.top, bottomInset: proxy.safeAreaInsets.bottom)

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


                // Top controls
                VStack {
                    HStack {
                        Button(action: {
                            showCreatorView = false
                        }) {
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
                        .rotationEffect(.degrees(rotationAngle))
                        .animation(.spring(), value: rotationAngle)

                        Spacer()

                        // Flash button
                        Button(action: {
                            toggleFlash()
                        }) {
                            Image(systemName: flashIcon)
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
                        .rotationEffect(.degrees(rotationAngle))
                        .animation(.spring(), value: rotationAngle)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Spacer()
                }

                // Bottom controls
                ZStack {
                    VStack(spacing: 12) {
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

                        HStack(alignment: .bottom, spacing: 40) {
                            // Gallery button with last image preview
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
                            .rotationEffect(.degrees(rotationAngle))
                            .animation(.spring(), value: rotationAngle)

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
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 48, height: 48)
                                    .background {
                                        Color.clear
                                            .liquidGlass(in: Circle(), interactive: true)
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                            }
                            .rotationEffect(.degrees(rotationAngle))
                            .animation(.spring(), value: rotationAngle)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 26)
                }
                .frame(width: captureRect.width, height: captureRect.height, alignment: .bottom)
                .position(x: captureRect.midX, y: captureRect.midY)
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
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        Task {
            do {
                let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
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

private struct MomentsStoryGuideOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let guideRect = momentsAspectRect(aspectRatio: momentsCaptureAspectRatio, in: CGRect(origin: .zero, size: proxy.size))
            let topMaskHeight = max(guideRect.minY, 0)
            let bottomMaskHeight = max(proxy.size.height - guideRect.maxY, 0)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.black.opacity(0.34))
                    .frame(height: topMaskHeight)

                Color.clear
                    .frame(height: guideRect.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                    )

                Rectangle()
                    .fill(Color.black.opacity(0.34))
                    .frame(height: bottomMaskHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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
                .fill(Color.white.opacity(0.14))
                .frame(width: 88, height: 88)
                .background {
                    Color.clear
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1.5)
                )

            Circle()
                .fill(isRecording ? Color.red : Color.white)
                .frame(width: isPressed ? 58 : 68, height: isPressed ? 58 : 68)
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
        view.currentDeviceOrientation = deviceOrientation
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.updateCameraPosition(cameraPosition)
        uiView.updateFlashMode(flashMode)
        uiView.updateZoom(zoomLevel)
        uiView.currentDeviceOrientation = deviceOrientation

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
    var currentDeviceOrientation: UIDeviceOrientation = .portrait

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

        if let photoConnection = photoOutput.connection(with: .video) {
            let orientation = currentDeviceOrientation
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
            if photoConnection.isVideoMirroringSupported {
                photoConnection.isVideoMirrored = (currentPosition == .front)
            }
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func startRecording() {
        guard let movieOutput = movieOutput,
              !movieOutput.isRecording else { return }

        if let videoConnection = movieOutput.connection(with: .video) {
            let orientation = currentDeviceOrientation
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
            if videoConnection.isVideoMirroringSupported {
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

    private func exportVideoMatchingVisiblePreview(from inputURL: URL, completion: @escaping (URL?) -> Void) {
        let asset = AVAsset(url: inputURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(nil)
            return
        }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(nil)
            return
        }

        do {
            try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
        } catch {
            completion(nil)
            return
        }

        if let audioTrack = asset.tracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: audioTrack, at: .zero)
        }

        let transformedRect = CGRect(origin: .zero, size: videoTrack.naturalSize).applying(videoTrack.preferredTransform).standardized
        let orientedSize = transformedRect.size
        let cropRect = momentsAspectRect(aspectRatio: momentsCaptureAspectRatio, in: CGRect(origin: .zero, size: orientedSize)).integral

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        let translationToOrigin = CGAffineTransform(translationX: -transformedRect.origin.x, y: -transformedRect.origin.y)
        let cropTranslation = CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y)
        let finalTransform = videoTrack.preferredTransform.concatenating(translationToOrigin).concatenating(cropTranslation)
        layerInstruction.setTransform(finalTransform, at: .zero)

        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = cropRect.size
        videoComposition.frameDuration = CMTime(value: 1, timescale: max(Int32(videoTrack.nominalFrameRate.rounded()), 30))

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("story_cropped_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(nil)
            return
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                completion(exportSession.status == .completed ? outputURL : nil)
            }
        }
    }

    private func cropImageToVisiblePreview(_ image: UIImage) -> UIImage? {
        guard let previewLayer = videoPreviewLayer, let cgImage = image.cgImage else { return nil }

        let guideRect = momentsAspectRect(aspectRatio: momentsCaptureAspectRatio, in: bounds)
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

// MARK: - Crop View Implementation
struct CropViewWrapper: UIViewControllerRepresentable {
    let image: UIImage
    let aspectRatio: CreatorMedia.AspectRatio
    let allowFreeCrop: Bool // ✅ NUEVO: Permitir crop libre (no bloquear ratio)
    let onComplete: (UIImage, CreatorMedia.AspectRatio) -> Void
    @Environment(\.dismiss) private var dismiss

    init(image: UIImage, aspectRatio: CreatorMedia.AspectRatio, allowFreeCrop: Bool = false, onComplete: @escaping (UIImage, CreatorMedia.AspectRatio) -> Void) {
        self.image = image
        self.aspectRatio = aspectRatio
        self.allowFreeCrop = allowFreeCrop
        self.onComplete = onComplete
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let cropViewController = TOCropViewController(croppingStyle: .default, image: image)
        cropViewController.delegate = context.coordinator

        // ✅ MEJORADO: Set aspect ratio basado en selección, pero permitir ajuste libre si allowFreeCrop es true
        if allowFreeCrop {
            // ✅ NUEVO: No bloquear el aspect ratio, solo sugerirlo como inicial
            switch aspectRatio {
            case .square:
                cropViewController.aspectRatioPreset = .presetSquare
            case .portrait:
                cropViewController.customAspectRatio = CGSize(width: 4, height: 5)
            case .landscape:
                cropViewController.customAspectRatio = CGSize(width: 16, height: 9)
            case .nineBySixteen:
                cropViewController.customAspectRatio = CGSize(width: 9, height: 16)
            }
            cropViewController.aspectRatioLockEnabled = false // ✅ Permitir ajuste libre
        } else {
            // Comportamiento original: bloquear el aspect ratio
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
            // ✅ NUEVO: Si allowFreeCrop es true, detectar el aspect ratio final de la imagen recortada
            let finalAspectRatio: CreatorMedia.AspectRatio
            if parent.allowFreeCrop {
                // Detectar el aspect ratio de la imagen recortada
                let imageRatio = image.size.width / image.size.height
                finalAspectRatio = CreatorMedia.AspectRatio.fromRatio(imageRatio)
            } else {
                // Usar el aspect ratio que estaba bloqueado
                finalAspectRatio = parent.aspectRatio
            }

            parent.onComplete(image, finalAspectRatio)
            parent.dismiss()
        }

        func cropViewControllerDidCancel(_ cropViewController: TOCropViewController) {
            parent.dismiss()
        }
    }
}
// MARK: - Filter Selection Implementation

struct FilterOption: View {
    let image: UIImage
    let filter: FilterService.FilterType
    let isSelected: Bool
    let onTap: () -> Void

    @State private var previewImage: UIImage? = nil

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    if let preview = previewImage {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 100) // Changed to 100 height for standard filter look
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Color.gray.opacity(0.2)
                            .frame(width: 80, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 2
                            )
                            .frame(width: 80, height: 100) // Fix size of border
                    }
                }
                .frame(width: 80, height: 100) // Constrain ZStack height
                .shadow(color: isSelected ? .pink.opacity(0.3) : .clear, radius: 8)

                Text(filter.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : .gray)
            }
        }
        .onAppear {
            generatePreview()
        }
    }

    private func generatePreview() {
        // Generate a small thumbnail for the carousel to save memory
        let size = CGSize(width: 100, height: 120) // Swapped to match new aspect ratio
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumb = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        Task.detached(priority: .background) {
            let filtered = FilterService.shared.applyFilterToThumbnail(filter, to: thumb)
            await MainActor.run {
                withAnimation {
                    self.previewImage = filtered
                }
            }
        }
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

                    TextField(NSLocalizedString("creator.tag.search", comment: ""), text: $searchText)
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
            .navigationTitle("creator.tagPeople")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common.cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("creator.tag.done", comment: "")) {
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

                    TextField(NSLocalizedString("creator.location.search", comment: ""), text: $searchText)
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
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .liquidGlass(in: Capsule(), interactive: true)
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
                                    .tint(adaptiveColors.primary)
                            } else {
                                Image(systemName: "location.fill")
                            }
                            Text("creator.location.useCurrent")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(adaptiveColors.primary)
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
                                Text("common.update")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(adaptiveColors.primary)
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
            .navigationTitle("creator.addLocation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(adaptiveColors.primary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("creator.tag.done", comment: "")) {
                        dismiss()
                    }
                    .foregroundColor(adaptiveColors.primary)
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
                locationError = NSLocalizedString("creator.location.permissionDenied", comment: "")
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
            locationError = NSLocalizedString("creator.location.permissionDenied", comment: "")
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
            locationError = NSLocalizedString("creator.location.unknownPermissionState", comment: "")
            isRequestingLocation = false
        }
    }

    private func getLocationNameFromCoordinates(_ coordinate: CLLocationCoordinate2D) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    // Generar nombre limpio y conciso (estilo nativo)
                    self.locationName = self.generateCleanLocationName(from: placemark)
                } else {
                    self.locationName = NSLocalizedString("creator.location.current", comment: "")
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

        return NSLocalizedString("creator.location.current", comment: "")
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
        locationName = place.name ?? NSLocalizedString("creator.location.selected", comment: "")

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
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(adaptiveColors.primary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name ?? "Ubicación sin nombre")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(adaptiveColors.primary)

                    Text(categoryName)
                        .font(.caption)
                        .foregroundColor(adaptiveColors.secondary)

                    if let address = place.placemark.title {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(adaptiveColors.secondary.opacity(0.8))
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

// MARK: - Story Gallery Picker Implementation

struct StoryGalleryPicker: View {
    let onSelect: (CreatorMedia) -> Void
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
                            let media = CreatorMedia(
                                id: UUID().uuidString,
                                image: image,
                                videoURL: nil,
                                type: .image,
                                aspectRatio: .nineBySixteen,
                                recommendedAspectRatio: .nineBySixteen
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

                                                let media = CreatorMedia(
                                                    id: UUID().uuidString,
                                                    image: thumbnail,
                                                    videoURL: videoURL,
                                                    type: .video,
                                                    aspectRatio: .nineBySixteen,
                                                    recommendedAspectRatio: .nineBySixteen
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
            .alert("creator.video.length.title", isPresented: $showingVideoLengthAlert) {
                Button("common.understood") {
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

                Button("common.close") {
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
    @Environment(\.colorScheme) private var colorScheme

    private var pickerBackgroundColor: UIColor {
        colorScheme == .dark
            ? UIColor(red: 11.0 / 255.0, green: 18.0 / 255.0, blue: 21.0 / 255.0, alpha: 1.0)
            : UIColor(red: 250.0 / 255.0, green: 249.0 / 255.0, blue: 246.0 / 255.0, alpha: 1.0)
    }

    private var pickerForegroundColor: UIColor {
        colorScheme == .dark ? .white : .black
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        picker.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        picker.view.backgroundColor = pickerBackgroundColor
        applyAppearance(to: picker)

        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        uiViewController.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        uiViewController.view.backgroundColor = pickerBackgroundColor
        applyAppearance(to: uiViewController)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func applyAppearance(to picker: PHPickerViewController) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = pickerBackgroundColor
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: pickerForegroundColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: pickerForegroundColor]

        picker.navigationController?.navigationBar.standardAppearance = appearance
        picker.navigationController?.navigationBar.scrollEdgeAppearance = appearance
        picker.navigationController?.navigationBar.compactAppearance = appearance
        picker.navigationController?.navigationBar.tintColor = pickerForegroundColor
        picker.navigationController?.view.backgroundColor = pickerBackgroundColor
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
    @Binding var isPresented: Bool
    @Binding var text: String
    @Binding var selectedStyle: StoryEditingView.TextStyle
    @Binding var selectedEffect: StoryEditingView.TextEffect
    @Binding var textColor: Color
    @Binding var textAlignment: TextAlignment
    @Binding var textBackgroundFill: StoryEditingView.TextBackgroundFill
    @Binding var textFontSize: CGFloat
    @State private var isTextFieldFocused = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var activeTool: EditorTool = .font

    enum EditorTool {
        case font
        case color
        case effect
    }

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            let keyboardInset = max(0, keyboardHeight - proxy.safeAreaInsets.bottom)
            let textCanvasLift = keyboardInset > 0 ? min(108, keyboardInset * 0.34) : 0

            ZStack {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.10),
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.28)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .frame(width: canvasSize.width, height: canvasSize.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    hideKeyboard()
                }

                HStack(alignment: .center, spacing: 8) {
                    FontSizeSlider(value: $textFontSize, range: 20...56)

                    StoryStyledTextView(
                        text: $text,
                        isFocused: $isTextFieldFocused,
                        style: selectedStyle,
                        effect: selectedEffect,
                        fontSize: textFontSize,
                        textColor: textColor,
                        textAlignment: textAlignment,
                        backgroundColor: editorTextBackgroundUIColor
                    )
                    .frame(minHeight: 130, maxHeight: 240)
                }
                .frame(maxWidth: .infinity, alignment: alignmentForText(textAlignment))
                .padding(.leading, 2)
                .padding(.trailing, 24)
                .offset(y: -textCanvasLift)
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .overlay(alignment: .top) {
                HStack {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .liquidGlass(in: Circle())
                    }
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Text(NSLocalizedString("storyTextEditor.done", comment: "Done"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .liquidGlass(in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 76)
            }
            .overlay(alignment: .bottom) {
                textEditorBottomToolbar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .offset(y: -textEditorToolbarBottomPadding())
                    .animation(.easeOut(duration: 0.24), value: textEditorToolbarBottomPadding())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard, edges: .all)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isTextFieldFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardHeight(notification as Foundation.Notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
    }

    @ViewBuilder
    private var toolTray: some View {
        switch activeTool {
        case .font:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(StoryEditingView.TextStyle.fontPickerStyles, id: \.self) { style in
                        fontPill(for: style)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 48)

        case .color:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([Color.white, .black, .red, .orange, .yellow, .green, .blue, .purple, .pink], id: \.self) { color in
                        ColorOption(
                            color: color,
                            isSelected: textColor == resolvedColorSelection(for: color)
                        ) {
                            if textBackgroundFill == .white && isLightColor(color) {
                                textColor = .black
                            } else if textBackgroundFill == .black && isDarkColor(color) {
                                textColor = .white
                            } else {
                                textColor = color
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 48)

        case .effect:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StoryEditingView.TextEffect.allCases, id: \.self) { effect in
                        effectPill(for: effect)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 48)
        }
    }

    private var textEditorBottomToolbar: some View {
        VStack(spacing: 10) {
            toolTray

            HStack(spacing: 10) {
                toolButton(
                    isSelected: activeTool == .font,
                    action: { activeTool = .font }
                ) {
                    Text("Aa")
                        .font(.system(size: 24, weight: .regular))
                }

                toolButton(
                    isSelected: activeTool == .color,
                    action: { activeTool = .color }
                ) {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.red, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                                center: .center
                            )
                        )
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.9), lineWidth: 1.4)
                        )
                }

                toolButton(
                    isSelected: activeTool == .effect,
                    action: { activeTool = .effect }
                ) {
                    Text("≋A")
                        .font(.system(size: 22, weight: .medium))
                }

                toolButton(
                    isSelected: false,
                    action: cycleTextAlignment
                ) {
                    Image(systemName: alignmentIcon)
                        .font(.system(size: 24, weight: .medium))
                }

                toolButton(
                    isSelected: textBackgroundFill != .none,
                    action: cycleTextBackgroundFill
                ) {
                    backgroundFillButtonIcon
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func fontPill(for style: StoryEditingView.TextStyle) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedStyle = style
            }
        } label: {
            Text(style.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selectedStyle == style ? Color.white.opacity(0.26) : Color.white.opacity(0.10))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(selectedStyle == style ? Color.white.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func effectPill(for effect: StoryEditingView.TextEffect) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedEffect = effect
            }
        } label: {
            Text(effect.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selectedEffect == effect ? Color.white.opacity(0.26) : Color.white.opacity(0.10))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(selectedEffect == effect ? Color.white.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func toolButton<Content: View>(
        isSelected: Bool,
        foregroundColor: Color = .white,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .foregroundColor(foregroundColor)
                .frame(width: 44, height: 44)
                .background(isSelected ? Color.white.opacity(0.22) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var alignmentIcon: String {
        switch textAlignment {
        case .leading:
            return "text.alignleft"
        case .trailing:
            return "text.alignright"
        default:
            return "text.aligncenter"
        }
    }

    private var backgroundFillButtonIcon: some View {
        let fillColor: Color = {
            switch textBackgroundFill {
            case .none:
                return .clear
            case .black:
                return Color.black.opacity(0.92)
            case .white:
                return Color.white.opacity(0.96)
            }
        }()

        let strokeColor: Color = textBackgroundFill == .white ? Color.black.opacity(0.22) : Color.white.opacity(0.55)
        let textColor: Color = {
            switch textBackgroundFill {
            case .white:
                return .black.opacity(0.88)
            case .none, .black:
                return .white
            }
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(fillColor)
                .frame(width: 24, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(strokeColor, lineWidth: 1.2)
                )

            Text("A")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(textColor)
        }
    }

    private func cycleTextAlignment() {
        withAnimation(.easeInOut(duration: 0.18)) {
            switch textAlignment {
            case .leading:
                textAlignment = .center
            case .center:
                textAlignment = .trailing
            case .trailing:
                textAlignment = .leading
            }
        }
    }

    private func cycleTextBackgroundFill() {
        withAnimation(.easeInOut(duration: 0.18)) {
            switch textBackgroundFill {
            case .none:
                textBackgroundFill = .black
                if isDarkColor(textColor) {
                    textColor = .white
                }
            case .black:
                textBackgroundFill = .white
                if isLightColor(textColor) {
                    textColor = .black
                }
            case .white:
                textBackgroundFill = .none
            }
        }
    }

    private func resolvedColorSelection(for color: Color) -> Color {
        if textBackgroundFill == .white && isLightColor(color) {
            return .black
        }
        if textBackgroundFill == .black && isDarkColor(color) {
            return .white
        }
        return color
    }

    private func isLightColor(_ color: Color) -> Bool {
        let uiColor = UIColor(color)

        var white: CGFloat = 0
        var alpha: CGFloat = 0
        if uiColor.getWhite(&white, alpha: &alpha) {
            return white > 0.82
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
            return luminance > 0.82
        }

        return false
    }

    private func isDarkColor(_ color: Color) -> Bool {
        let uiColor = UIColor(color)

        var white: CGFloat = 0
        var alpha: CGFloat = 0
        if uiColor.getWhite(&white, alpha: &alpha) {
            return white < 0.22
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
            return luminance < 0.22
        }

        return false
    }

    private func alignmentForText(_ alignment: TextAlignment) -> Alignment {
        switch alignment {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        default:
            return .center
        }
    }

    private func updateKeyboardHeight(_ notification: Foundation.Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let screenHeight = UIScreen.main.bounds.height
        keyboardHeight = max(0, screenHeight - keyboardFrame.minY)
    }

    private func textEditorToolbarBottomPadding() -> CGFloat {
        if keyboardHeight > 0 {
            return keyboardHeight + 52
        }
        return 60
    }

    private var editorTextBackgroundUIColor: UIColor? {
        switch textBackgroundFill {
        case .none:
            return selectedEffect.uiBackgroundColor
        case .black:
            return UIColor.black.withAlphaComponent(0.58)
        case .white:
            return UIColor.white.withAlphaComponent(0.90)
        }
    }
}

struct TextEffectModifier: ViewModifier {
    let effect: StoryEditingView.TextEffect
    let textColor: Color

    func body(content: Content) -> some View {
        if let shadow = effect.shadow(for: textColor) {
            content.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        } else {
            content
        }
    }
}

struct StoryStyledTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    let style: StoryEditingView.TextStyle
    let effect: StoryEditingView.TextEffect
    let fontSize: CGFloat
    let textColor: Color
    let textAlignment: TextAlignment
    let backgroundColor: UIColor?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.keyboardAppearance = .dark
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.tintColor = UIColor(textColor)
        textView.typingAttributes = typingAttributes()
        textView.attributedText = NSAttributedString(string: text, attributes: typingAttributes())
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self

        let selectedRange = uiView.selectedRange
        let attributes = typingAttributes()

        uiView.tintColor = UIColor(textColor)
        uiView.textAlignment = nsTextAlignment
        uiView.typingAttributes = attributes

        if uiView.attributedText.string != text || context.coordinator.lastAppliedSignature != attributesSignature {
            uiView.attributedText = NSAttributedString(string: text, attributes: attributes)
            context.coordinator.lastAppliedSignature = attributesSignature

            let safeLocation = min(selectedRange.location, uiView.attributedText.length)
            let remaining = uiView.attributedText.length - safeLocation
            uiView.selectedRange = NSRange(location: safeLocation, length: min(selectedRange.length, remaining))
        }

        if isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    private var attributesSignature: String {
        let background = backgroundColor?.description ?? "nil"
        return [
            style.rawValue,
            effect.rawValue,
            "\(textColor.description)",
            "\(textAlignment)",
            background,
            "\(fontSize)",
            style.uiFont(size: fontSize).fontName
        ].joined(separator: "|")
    }

    private var nsTextAlignment: NSTextAlignment {
        switch textAlignment {
        case .leading:
            return .left
        case .trailing:
            return .right
        default:
            return .center
        }
    }

    private func typingAttributes() -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = nsTextAlignment
        paragraphStyle.lineBreakMode = .byWordWrapping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: style.uiFont(size: fontSize),
            .foregroundColor: UIColor(textColor),
            .paragraphStyle: paragraphStyle
        ]

        if let backgroundColor {
            attributes[.backgroundColor] = backgroundColor
        }

        if let shadow = effect.nsShadow(for: UIColor(textColor)) {
            attributes[.shadow] = shadow
        }

        return attributes
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: StoryStyledTextView
        var lastAppliedSignature: String

        init(parent: StoryStyledTextView) {
            self.parent = parent
            self.lastAppliedSignature = parent.attributesSignature
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            textView.typingAttributes = parent.typingAttributes()
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
        case .poster: return "AA"
        case .editorial: return "Aa"
        case .rounded: return "Aa"
        case .signature: return "Aa"
        case .marker: return "Aa"
        case .neon: return "AA"
        case .typewriter: return "Aa"
        case .handwritten: return "Aa"
        case .bold: return "Aa"
        case .chalk: return "Aa"
        }
    }

    var body: some View {
        Button(action: onTap) {
            Text(stylePreview)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(
                    ZStack {
                        style.backgroundColor

                        if style.backgroundColor == .clear {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                )
        }
    }
}

struct FontSizeSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let progress = (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.001)
            let knobY = (1 - progress) * (height - 18)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.34))
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)

                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .offset(y: knobY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let clampedY = min(max(gesture.location.y, 9), height - 9)
                        let inverseProgress = 1 - ((clampedY - 9) / max(height - 18, 1))
                        value = range.lowerBound + (inverseProgress * (range.upperBound - range.lowerBound))
                    }
            )
        }
        .frame(width: 18, height: 176)
    }
}

struct ColorOption: View {
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(color == .white ? Color.gray : Color.white, lineWidth: 1.2)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Color.white.opacity(0.26) : Color.white.opacity(0.10))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.white.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(currentAlignment == alignment ? .white : .gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(currentAlignment == alignment ? Color.white.opacity(0.26) : Color.white.opacity(0.10))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(currentAlignment == alignment ? Color.white.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Camera Capture Implementation

struct CameraCapture: UIViewControllerRepresentable {
    let onCapture: (CreatorMedia) -> Void
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
                // ✅ Detectar aspect ratio de la imagen capturada
                let detectedRatio = CreatorMedia.AspectRatio.fromRatio(image.size.width / image.size.height)
                let media = CreatorMedia(
                    id: UUID().uuidString,
                    image: image,
                    videoURL: nil,
                    type: .image,
                    aspectRatio: detectedRatio,
                    recommendedAspectRatio: detectedRatio
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

                    // ✅ Detectar aspect ratio del video capturado
                    let detectedRatio = CreatorMedia.AspectRatio.fromRatio(thumbnail.size.width / thumbnail.size.height)
                    let media = CreatorMedia(
                        id: UUID().uuidString,
                        image: thumbnail,
                        videoURL: videoURL,
                        type: .video,
                        aspectRatio: detectedRatio,
                        recommendedAspectRatio: detectedRatio
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
    @Binding var textEffect: StoryEditingView.TextEffect
    @Binding var textColor: Color
    @Binding var textAlignment: TextAlignment
    @Binding var textBackgroundFill: StoryEditingView.TextBackgroundFill
    @Binding var textFontSize: CGFloat
    @Binding var isTextEditorPresented: Bool
    @Binding var stickers: [StickerItem]
    @Binding var drawingImage: UIImage?
    @Binding var isEditingSticker: Bool // ✅ NUEVO: Para ocultar la UI del padre

    let onNavigateToProfile: (String) -> Void
    let onNavigateToLocation: (String, CLLocationCoordinate2D?) -> Void

    @State private var selectedStickerId: String?
    @State private var isEditingText = false
    @State private var isDraggingItem = false
    @State private var showTrashZone = false
    @State private var isOverTrash = false
    @State private var pinchStartTextFontSize: CGFloat?
    @State private var dragOffset: CGSize = .zero // ✅ Offset para evitar el salto al centro al tocar el texto

    // 📸 NUEVO: Estado para editar el pie de foto de la Polaroid
    @State private var editingPolaroidId: String? = nil
    @State private var polaroidCaptionBuffer: String = ""
    @State private var originalStickerTransform: (pos: CGPoint, scale: CGFloat, rot: Angle)? = nil
    @State private var keyboardHeight: CGFloat = 0

    // ✨ NUEVO: Estado para editar el diseño del Reveal
    @State private var editingRevealId: String? = nil

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
            if !text.isEmpty && !isTextEditorPresented {
                Text(text)
                    .font(textStyle.font(size: textFontSize))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(nil)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        Group {
                            if let backgroundColor = effectiveTextBackgroundColor {
                                backgroundColor
                            }
                        }
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: effectiveTextBackgroundColor == nil ? 0 : 10, style: .continuous)
                    )
                    .padding(.horizontal, 24)
                    .scaleEffect(isDraggingItem && selectedStickerId == nil ? 0.8 : 1.0)
                    .opacity(isDraggingItem && selectedStickerId == nil ? 0.8 : 1.0)
                    .modifier(TextEffectModifier(effect: textEffect, textColor: textColor))
                    .contentShape(Rectangle()) // ✅ Área táctil limitada al texto
                    .gesture(
                        DragGesture(coordinateSpace: .named("storyCanvas")) // ✅ Estabilidad absoluta en el canvas
                            .onChanged { value in
                                if dragOffset == .zero {
                                    dragOffset = CGSize(
                                        width: value.startLocation.x - textPosition.x,
                                        height: value.startLocation.y - textPosition.y
                                    )
                                }

                                let newPos = CGPoint(
                                    x: value.location.x - dragOffset.width,
                                    y: value.location.y - dragOffset.height
                                )

                                textPosition = newPos

                                if !isDraggingItem {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isDraggingItem = true
                                        showTrashZone = true
                                    }
                                }

                                let trashY = UIScreen.main.bounds.height - 150
                                isOverTrash = newPos.y > trashY
                            }
                            .onEnded { value in
                                dragOffset = .zero
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
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let baseFontSize = pinchStartTextFontSize ?? textFontSize
                                if pinchStartTextFontSize == nil {
                                    pinchStartTextFontSize = textFontSize
                                }
                                textFontSize = min(max(baseFontSize * value, 20), 56)
                            }
                            .onEnded { _ in
                                pinchStartTextFontSize = nil
                            }
                    )
                    .onTapGesture {
                        selectedStickerId = nil
                        isEditingText = true
                        isTextEditorPresented = true
                    }
                    .position(textPosition) // ✅ Posicionar al final
                    .animation(.easeInOut(duration: 0.2), value: isDraggingItem)
            }

            // ✅ STICKERS COMPLETAMENTE LIBRES - Sin interfaz de selección
            ForEach(stickers.indices, id: \.self) { index in
                // Ocultar stickers de tipo REVEAL del canvas (se muestran como badge arriba)
                if stickers[index].type != .reveal {
                    StickerOverlayView(
                        sticker: $stickers[index],
                        isSelected: selectedStickerId == stickers[index].id,
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
                            selectedStickerId = tappedSticker.id
                        }
                    )
                    .zIndex(editingPolaroidId == stickers[index].id ? 2000 : (selectedStickerId == stickers[index].id ? 500 : 1))
                }
            }

            // ✅ REVEAL STATUS BADGE (Top)
            if stickers.contains(where: { $0.type == .reveal }) {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "magicmouse.fill")
                                .font(.system(size: 12))
                            Text(NSLocalizedString("storyEditor.reveal.active", comment: "Reveal effect active status"))
                                .font(.custom("Poppins-Medium", size: 11))

                            Button {
                                withAnimation(.spring()) {
                                    stickers.removeAll(where: { $0.type == .reveal })
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .liquidGlass(in: Capsule(), interactive: true)
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                        .onTapGesture {
                            if let revealSticker = stickers.first(where: { $0.type == .reveal }) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    editingRevealId = revealSticker.id
                                }
                                HapticManager.shared.mediumImpact()
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, 100) // Debajo de los controles superiores
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
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

            // 📸 FONDO OSCURO DE EDICIÓN (Dentro del ZStack para controlar el zIndex)
            if editingPolaroidId != nil {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                    .zIndex(1500) // Entre los stickers normales y el "Hero"
                    .onTapGesture {
                        savePolaroidCaption()
                    }
                    .transition(.opacity)

                // INPUT DE TEXTO (Encima de todo)
                VStack {
                    Spacer()
                    TextField(NSLocalizedString("storyEditor.polaroid.addNote", comment: "Prompt to add a note to a polaroid"), text: $polaroidCaptionBuffer)
                        .font(.custom("MarkerFelt-Wide", size: 24)) // Un pelín más pequeña
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12) // Mucho más fino
                        .padding(.horizontal, 25)
                        .liquidGlass(in: Capsule(), interactive: true)
                        .padding(.horizontal, 40)
                        .submitLabel(.done)
                        .onSubmit {
                            savePolaroidCaption()
                        }
                        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 80 : 160)
                }
                .zIndex(2500)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: keyboardHeight)
                .onChange(of: polaroidCaptionBuffer) { _, newValue in
                    // ✅ ACTUALIZACIÓN EN TIEMPO REAL
                    if let editingId = editingPolaroidId,
                       let index = stickers.firstIndex(where: { $0.id == editingId }) {
                        var interaction = stickers[index].interactionData ?? StickerItem.StickerInteractionData()
                        interaction.caption = newValue
                        stickers[index].interactionData = interaction
                    }
                }
            }

            // ✨ REVEAL EDITOR OVERLAY
            if editingRevealId != nil {
                RevealStickerEditorView(
                    stickers: $stickers,
                    editingId: $editingRevealId
                )
                .zIndex(3000)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: editingPolaroidId) { _, newValue in
            // ✅ AVISAR AL PADRE PARA OCULTAR LA UI
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isEditingSticker = newValue != nil || editingRevealId != nil
            }
        }
        .onChange(of: editingRevealId) { _, newValue in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isEditingSticker = newValue != nil || editingPolaroidId != nil
            }
        }
        .coordinateSpace(name: "storyCanvas")
        .onTapGesture {
            // Deseleccionar al tocar el fondo
            selectedStickerId = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenHeight = UIScreen.main.bounds.height
            let overlap = max(0, screenHeight - endFrame.minY)
            keyboardHeight = overlap
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }

    }

    private var effectiveTextBackgroundColor: Color? {
        switch textBackgroundFill {
        case .none:
            return textEffect.backgroundColor
        case .black:
            return Color.black.opacity(0.58)
        case .white:
            return Color.white.opacity(0.90)
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

        case .frame:
            // 📸 EFECTO ENFOQUE: Guardar posición y centrar para editar
            if let index = stickers.firstIndex(where: { $0.id == sticker.id }) {
                let original = stickers[index]
                originalStickerTransform = (original.position, original.scale, original.rotation)

                editingPolaroidId = sticker.id
                polaroidCaptionBuffer = sticker.interactionData?.caption ?? ""

                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    // Mover al centro (un poco arriba por el teclado) y ampliar
                    stickers[index].position = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 3)
                    stickers[index].scale = 1.4
                    stickers[index].rotation = .zero
                }

                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            }

        default:
            break
        }
    }


    private func savePolaroidCaption() {
        guard let editingId = editingPolaroidId else { return }

        if let index = stickers.firstIndex(where: { $0.id == editingId }) {
            // Actualizar el caption en los datos de interacción
            var interactionData = stickers[index].interactionData ?? StickerItem.StickerInteractionData()
            interactionData.caption = polaroidCaptionBuffer
            stickers[index].interactionData = interactionData

            // 🚀 VOLVER A LA POSICIÓN ORIGINAL CON ANIMACIÓN
            if let original = originalStickerTransform {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    stickers[index].position = original.pos
                    stickers[index].scale = original.scale
                    stickers[index].rotation = original.rot
                }
            }
        }

        withAnimation(.easeOut(duration: 0.25)) {
            editingPolaroidId = nil
            polaroidCaptionBuffer = ""
            originalStickerTransform = nil
        }

        // Ocultar teclado
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
    @State private var selfieCaptureTrigger = false
    @State private var selfieSwitchCameraTrigger = false
    @State private var lastSelfieSwitchAt: Date = .distantPast
    @State private var dragOffset: CGSize = .zero // ✅ Offset para evitar el salto al centro al tocar

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

    private var stickerSize: CGSize {
        switch sticker.type {
        case .frame: return CGSize(width: 200, height: 240)
        case .quiz, .poll, .question: return CGSize(width: 300, height: 320)
        case .weather: return CGSize(width: 140, height: 50)
        case .time: return CGSize(width: 180, height: 80)
        default: return sticker.image.size
        }
    }

    private var minimumStickerScale: CGFloat {
        switch sticker.type {
        case .poll, .question, .quiz:
            return 0.42
        case .time, .weather, .location, .mention, .hashtag, .link, .countdown, .emojiSlider:
            return 0.35
        case .frame, .selfie:
            return 0.3
        default:
            return 0.28
        }
    }

    private var maximumStickerScale: CGFloat {
        let maxDimension: CGFloat = 2048
        let maxScaleWidth = maxDimension / max(stickerSize.width, 1)
        let maxScaleHeight = maxDimension / max(stickerSize.height, 1)
        let safeMaxScale = min(maxScaleWidth, maxScaleHeight)
        return min(4.5, safeMaxScale)
    }

    var body: some View {
        ZStack {
            // ... (resto del contenido del ZStack sin cambios hasta la línea 7405)
            // ✅ SOLUCIÓN DEFINITIVA: Renderizado idéntico al Viewer
            if sticker.isAnimated {
                if let videoURL = sticker.videoURL {
                    // ✅ VIDEO STICKER (Loop)
                    ZStack(alignment: .top) {
                        StoryVideoPlayerView(videoURL: videoURL, videoGravity: .resizeAspectFill)
                            .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                            .allowsHitTesting(false)

                        // Header Overlay (Username)
                        if let interactionData = sticker.interactionData, let username = interactionData.username {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(.white.opacity(0.1))
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5))

                                Text(username)
                                    .font(.custom("Poppins-Bold", size: 10))
                                    .foregroundColor(.white)

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                Rectangle()
                                    .fill(.ultraThinMaterial)
                                    .mask(
                                        LinearGradient(
                                            colors: [.black, .black, .clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                        }

                        // Caption Overlay (Bottom)
                        if let caption = sticker.interactionData?.caption, !caption.isEmpty {
                            VStack {
                                Spacer()
                                Text(caption)
                                    .font(.custom("Poppins-Medium", size: 9))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .padding(.bottom, 10)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                }
                else if let gifURL = sticker.gifURL {
                    AnimatedStickerView(
                        sticker: sticker,
                        size: CGSize(width: sticker.image.size.width, height: sticker.image.size.height)
                    )
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                        .allowsHitTesting(false)
                }
            } else if isLiveSelfieSticker {
                ZStack {
                    SelfieStickerLiveCameraView(
                        captureTrigger: $selfieCaptureTrigger,
                        switchCameraTrigger: $selfieSwitchCameraTrigger
                    ) { capturedImage in
                        let targetSize = max(sticker.image.size.width, 100)
                        let stickerImage = makeCapturedSelfieStickerImage(from: capturedImage, size: targetSize)
                        let capturedSticker = StickerItem(
                            id: sticker.id,
                            image: stickerImage,
                            position: currentPosition,
                            scale: scale,
                            rotation: rotation,
                            gifURL: nil,
                            videoURL: nil,
                            isAnimated: false,
                            type: .selfie,
                            interactionData: nil
                        )
                        sticker = capturedSticker
                        onUpdate(capturedSticker)
                    }
                    .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                    .clipShape(Circle())

                    Circle()
                        .stroke(Color.black.opacity(0.04), lineWidth: max(0.5, sticker.image.size.width * 0.005))
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                                .padding(8)
                        }
                    }
                }
                .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                .allowsHitTesting(false)
            } else if sticker.type == .poll, let pollData = sticker.interactionData?.pollData {
                // POLL INTERACTIVO
                InteractivePollSticker(
                    pollData: pollData,
                    storyId: "preview",
                    userId: "preview",
                    stickerId: sticker.id,
                    selectedOption: .constant(nil),
                    hasVoted: .constant(false),
                    voteCounts: .constant([:]),
                    totalVotes: .constant(0),
                    onVote: { _ in }
                )
                .frame(width: 300, height: 172)
                .allowsHitTesting(false)
            } else if sticker.type == .question, let questionText = sticker.interactionData?.questionText {
                // QUESTION INTERACTIVO
                InteractiveQuestionSticker(
                    questionText: questionText,
                    storyId: "preview",
                    userId: "preview",
                    stickerId: sticker.id,
                    onPauseStory: {},
                    onResumeStory: {}
                )
                .frame(width: 300, height: 132)
                .allowsHitTesting(false)
            } else if sticker.type == .location, let locationName = sticker.interactionData?.location {
                // LOCATION INTERACTIVO
                InteractiveLocationSticker(
                    locationName: locationName,
                    coordinate: sticker.interactionData?.locationCoordinate,
                    onPauseStory: {},
                    onResumeStory: {}
                )
                .allowsHitTesting(false)
            } else if sticker.type == .hashtag, let hashtag = sticker.interactionData?.hashtag {
                // HASHTAG INTERACTIVO
                InteractiveHashtagSticker(
                    hashtag: hashtag,
                    onPauseStory: {},
                    onResumeStory: {}
                )
                .allowsHitTesting(false)
            } else if sticker.type == .mention, let username = sticker.interactionData?.username {
                // MENTION INTERACTIVO
                InteractiveMentionSticker(
                    username: username,
                    onTap: {}
                )
                .allowsHitTesting(false)
            } else if sticker.type == .link, let linkURL = sticker.interactionData?.linkURL {
                StickerLinkCardView(
                    title: sticker.interactionData?.linkTitle ?? stickerHostLabel(from: linkURL)
                )
                .allowsHitTesting(false)
            } else if sticker.type == .countdown,
                      let countdownTitle = sticker.interactionData?.countdownTitle,
                      let targetAtMs = sticker.interactionData?.countdownTargetAtMs {
                StickerCountdownCardView(title: countdownTitle, targetAtMs: targetAtMs)
                    .allowsHitTesting(false)
            } else if sticker.type == .emojiSlider,
                      let sliderPrompt = sticker.interactionData?.sliderPrompt,
                      let sliderEmoji = sticker.interactionData?.sliderEmoji {
                StickerEmojiSliderCardView(
                    prompt: sliderPrompt,
                    emoji: sliderEmoji,
                    value: 0.5
                )
                .frame(width: emojiSliderRenderingSize(prompt: sliderPrompt).width, height: emojiSliderRenderingSize(prompt: sliderPrompt).height)
                .allowsHitTesting(false)
            } else if sticker.type == .shareMoment {
                // ✅ SHARE MOMENT: Renderizado dinámico de overlays (Header + Caption)
                ZStack(alignment: .top) {
                    // 1. Imagen base (Captura limpia del marco glass + media)
                    Image(uiImage: sticker.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)

                    // 2. Video Overlay (si existe)
                    if let videoURL = sticker.videoURL {
                        StickerVideoPlayer(url: videoURL)
                           .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                           .allowsHitTesting(false)
                    }

                    // 3. Dynamic Overlays (Mismo diseño que en el Viewer)
                    ZStack(alignment: .top) {
                        Color.clear // Contenedor

                        // Header (Username + Profile)
                        HStack(spacing: 10) {
                            if let interactionData = sticker.interactionData,
                               let userId = interactionData.userId {
                                AsyncProfileImageView(userId: userId)
                                    .frame(width: 34, height: 34)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.5), .clear],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 34, height: 34)
                                    .foregroundColor(.white.opacity(0.5))
                            }

                            VStack(alignment: .leading, spacing: 0) {
                                Text(sticker.interactionData?.username ?? "User")
                                    .font(.custom("Poppins-Bold", size: 13))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .mask(
                                    LinearGradient(
                                        colors: [.black, .black, .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )

                        // Caption Overlay (Bottom)
                        if let caption = sticker.interactionData?.caption, !caption.isEmpty {
                            VStack {
                                Spacer()
                                Text(caption)
                                    .font(.custom("Poppins-Medium", size: 9))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .padding(.bottom, 10)
                            }
                        }

                        // Gallery Indicator (Top Right)
                        if (sticker.interactionData?.mediaCount ?? 0) > 1 {
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "square.on.square.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .padding(12)
                                        .padding(.top, 42) // Below header text
                                }
                                Spacer()
                            }
                        }
                    }
                    .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .allowsHitTesting(false)

            } else if sticker.type == .weather, let weatherSymbol = sticker.interactionData?.weatherSymbol {

                // WEATHER ANIMADO
                AnimatedWeatherSticker(
                    weatherSymbol: weatherSymbol,
                    temperature: sticker.interactionData?.questionText ?? "🌤️"
                )
                .frame(width: 140, height: 50)
                .allowsHitTesting(false)
            } else if sticker.type == .time {
                StickerTimeCardView(
                    timeText: sticker.interactionData?.questionText ?? Date.now.formatted(date: .omitted, time: .shortened),
                    dateText: sticker.interactionData?.caption ?? Date.now.formatted(date: .numeric, time: .omitted)
                )
                .allowsHitTesting(false)
            } else if sticker.type == .frame {
                InteractiveFrameSticker(
                    image: sticker.image,
                    caption: sticker.interactionData?.caption,
                    isEditing: true
                )
                .frame(width: 200, height: 240)
                .allowsHitTesting(false)
            } else if sticker.type == .quiz,
                      let question = sticker.interactionData?.quizQuestion,
                      let options = sticker.interactionData?.quizOptions {
                InteractiveQuizSticker(
                    storyId: "preview",
                    userId: "preview",
                    stickerId: sticker.id,
                    question: question,
                    options: options,
                    correctIndex: sticker.interactionData?.quizCorrectIndex ?? 0,
                    isEditing: true
                )
                .frame(width: 300)
                .allowsHitTesting(false)
            } else if sticker.type == .audio {
                InteractiveAudioStickerView(
                    audioURL: sticker.interactionData?.audioURL ?? "",
                    duration: sticker.interactionData?.audioDuration ?? 15.0
                )
                .allowsHitTesting(false)
            } else {
                // STICKER ESTÁTICO / IMAGEN (Emoji, Generic, etc.)
                // ✅ FIX: Usar tamaño natural de la imagen
                if sticker.type == .selfie {
                    Image(uiImage: sticker.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                        .clipShape(Circle())
                        .allowsHitTesting(false)
                } else {
                    Image(uiImage: sticker.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit) // Asegurar aspecto correcto
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .allowsHitTesting(false)
                }
            }
        }
        .rotationEffect(rotation)
        .scaleEffect(isDragging ? 0.9 : (showInteractionFeedback ? 1.05 : 1.0))
        .scaleEffect(scale)
        .opacity(isDragging ? 0.8 : 1.0)
        .frame(width: stickerSize.width, height: stickerSize.height)
        .contentShape(Rectangle())
        .onTapGesture {
            handleStickerTap()
        }
        // ✅ SINCRONIZAR CON EL PADRE PARA EL "VUELO HERO"
        .onChange(of: sticker.position) { _, newPos in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                currentPosition = newPos
            }
        }
        .onChange(of: sticker.scale) { _, newScale in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                scale = min(max(newScale, minimumStickerScale), maximumStickerScale)
            }
        }
        .onChange(of: sticker.rotation) { _, newRot in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                rotation = newRot
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    guard isLiveSelfieSticker else { return }
                    lastSelfieSwitchAt = Date()
                    selfieSwitchCameraTrigger.toggle()
                    let feedback = UIImpactFeedbackGenerator(style: .rigid)
                    feedback.impactOccurred()
                }
        )
        .gesture(
            DragGesture(coordinateSpace: .named("storyCanvas")) // ✅ Usar el canvas global para estabilidad absoluta
                .onChanged { value in
                    if dragOffset == .zero {
                        // Calcular la distancia desde el centro del sticker hasta donde pusimos el dedo
                        dragOffset = CGSize(
                            width: value.startLocation.x - currentPosition.x,
                            height: value.startLocation.y - currentPosition.y
                        )
                    }

                    let newPos = CGPoint(
                        x: value.location.x - dragOffset.width,
                        y: value.location.y - dragOffset.height
                    )

                    currentPosition = newPos
                    onDragChanged(newPos)
                    sticker.position = newPos
                }
                .onEnded { _ in
                    dragOffset = .zero // Resetear para el próximo arrastre
                    onDragEnded(currentPosition)
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    let newScale = sticker.scale * value
                    scale = min(max(newScale, minimumStickerScale), maximumStickerScale)
                }
                .onEnded { _ in
                    sticker.scale = scale
                }
        )
        .simultaneousGesture(
            RotationGesture()
                .onChanged { value in
                    rotation = sticker.rotation + value
                }
                .onEnded { value in
                    sticker.rotation = rotation
                }
        )
        .position(currentPosition) // ✅ Posicionar en el lienzo global al final
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showInteractionFeedback)
        .animation(.easeInOut(duration: 0.1), value: isDragging)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: scale)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: rotation)
    }

    private func handleStickerTap() {
        if isLiveSelfieSticker {
            // Evita capturar justo después de long-press para cambiar cámara.
            if Date().timeIntervalSince(lastSelfieSwitchAt) < 0.35 { return }
            selfieCaptureTrigger.toggle()
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            return
        }

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

    private var isLiveSelfieSticker: Bool {
        sticker.type == .selfie && sticker.interactionData?.caption == "selfie_live"
    }

    private func makeCapturedSelfieStickerImage(from originalImage: UIImage, size: CGFloat) -> UIImage {
        let selfieImage = downscaleSelfieImageIfNeeded(originalImage)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let circlePath = UIBezierPath(ovalIn: rect)

            context.cgContext.saveGState()
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 4), blur: 10, color: UIColor.black.withAlphaComponent(0.12).cgColor)
            UIColor.white.setFill()
            circlePath.fill()
            context.cgContext.restoreGState()

            let imageRect = rect.insetBy(dx: size * 0.012, dy: size * 0.012)
            let imageCirclePath = UIBezierPath(ovalIn: imageRect)
            context.cgContext.saveGState()
            imageCirclePath.addClip()

            let aspectRatio = selfieImage.size.width / max(selfieImage.size.height, 1)
            let drawRect: CGRect
            if aspectRatio > 1 {
                let drawHeight = imageRect.height
                let drawWidth = drawHeight * aspectRatio
                let drawX = imageRect.midX - drawWidth / 2
                drawRect = CGRect(x: drawX, y: imageRect.minY, width: drawWidth, height: drawHeight)
            } else {
                let drawWidth = imageRect.width
                let drawHeight = drawWidth / max(aspectRatio, 0.0001)
                let drawY = imageRect.midY - drawHeight / 2
                drawRect = CGRect(x: imageRect.minX, y: drawY, width: drawWidth, height: drawHeight)
            }

            selfieImage.draw(in: drawRect)
            context.cgContext.restoreGState()

            UIColor.black.withAlphaComponent(0.04).setStroke()
            circlePath.lineWidth = max(0.5, size * 0.005)
            circlePath.stroke()
        }
    }

    private func downscaleSelfieImageIfNeeded(_ image: UIImage, maxDimension: CGFloat = 900) -> UIImage {
        if image.size.width <= maxDimension && image.size.height <= maxDimension {
            return image
        }

        let aspectRatio = image.size.width / max(image.size.height, 1)
        let newSize: CGSize
        if image.size.width > image.size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

struct SelfieStickerLiveCameraView: UIViewRepresentable {
    @Binding var captureTrigger: Bool
    @Binding var switchCameraTrigger: Bool
    let onPhotoCaptured: (UIImage) -> Void

    func makeUIView(context: Context) -> SelfieStickerCameraPreviewView {
        let view = SelfieStickerCameraPreviewView()
        view.onPhotoCaptured = onPhotoCaptured
        return view
    }

    func updateUIView(_ uiView: SelfieStickerCameraPreviewView, context: Context) {
        if captureTrigger != context.coordinator.lastCaptureState {
            context.coordinator.lastCaptureState = captureTrigger
            uiView.capturePhoto()
        }
        if switchCameraTrigger != context.coordinator.lastSwitchCameraState {
            context.coordinator.lastSwitchCameraState = switchCameraTrigger
            uiView.toggleCamera()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastCaptureState = false
        var lastSwitchCameraState = false
    }
}

final class SelfieStickerCameraPreviewView: UIView, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "moments.selfieSticker.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var currentCameraPosition: AVCaptureDevice.Position = .front
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var captureEventInteraction: AVCaptureEventInteraction?

    var onPhotoCaptured: ((UIImage) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.cornerRadius = 18
        clipsToBounds = true
        configureHardwareCaptureInteraction()
        configureCamera()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        layer.cornerRadius = 18
        clipsToBounds = true
        configureHardwareCaptureInteraction()
        configureCamera()
    }

    deinit {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
    }

    private func configureHardwareCaptureInteraction() {
        let interaction = AVCaptureEventInteraction { [weak self] event in
            guard event.phase == .ended else { return }
            self?.capturePhoto()
        }
        addInteraction(interaction)
        captureEventInteraction = interaction
    }

    func capturePhoto() {
        sessionQueue.async {
            guard self.isConfigured else { return }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            if let connection = self.photoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = (self.currentCameraPosition == .front)
                }
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func toggleCamera() {
        sessionQueue.async {
            guard self.isConfigured else { return }
            let newPosition: AVCaptureDevice.Position = self.currentCameraPosition == .front ? .back : .front
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

            self.session.beginConfiguration()
            if let existing = self.currentInput {
                self.session.removeInput(existing)
            }

            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.currentInput = newInput
                self.currentCameraPosition = newPosition
            } else if let oldInput = self.currentInput, self.session.canAddInput(oldInput) {
                self.session.addInput(oldInput)
            }
            self.session.commitConfiguration()

            DispatchQueue.main.async {
                self.applyPreviewConnectionConfiguration()
            }
        }
    }

    private func configureCamera() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.setupSession()
                }
            }
        default:
            break
        }
    }

    private func setupSession() {
        sessionQueue.async {
            guard !self.isConfigured else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentCameraPosition),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)
            self.currentInput = input

            guard self.session.canAddOutput(self.photoOutput) else {
                self.session.commitConfiguration()
                return
            }

            self.session.addOutput(self.photoOutput)
            self.photoOutput.isHighResolutionCaptureEnabled = false
            self.session.commitConfiguration()
            self.isConfigured = true

            DispatchQueue.main.async {
                let previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
                previewLayer.videoGravity = .resizeAspectFill
                previewLayer.frame = self.bounds
                self.layer.insertSublayer(previewLayer, at: 0)
                self.previewLayer = previewLayer
                self.applyPreviewConnectionConfiguration()
            }

            self.session.startRunning()
        }
    }

    private func applyPreviewConnectionConfiguration() {
        guard let previewConnection = previewLayer?.connection else { return }
        if previewConnection.isVideoOrientationSupported {
            previewConnection.videoOrientation = .portrait
        }
        if previewConnection.isVideoMirroringSupported {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            previewConnection.isVideoMirrored = (currentCameraPosition == .front)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        let normalized = image.normalizedUp()
        DispatchQueue.main.async {
            self.onPhotoCaptured?(normalized)
        }
    }
}

private extension UIImage {
    func normalizedUp() -> UIImage {
        if imageOrientation == .up { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
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
        let normalizedImage = correctedImage.normalizedUp()
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
        if let error = error {
            return
        }

        // Ya no recortamos el video a 9:16 si se grabó en horizontal.
        // AVCaptureConnection ya orientó y capturó el video de forma óptima.
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.parent.onVideoCaptured(outputFileURL)
        }
    }
}


// MARK: - 🎨 COMPONENTES PREMIUM COMPARTIDOS (The Cinematic Handoff)

// GlowSharePill moved to CreatorSharedModels.swift

@ViewBuilder
fileprivate func ToolIconButton(icon: String, action: @escaping () -> Void) -> some View {
    Button(action: {
        hapticFeedback(.light)
        action()
    }) {
        Image(systemName: icon)
            .font(.system(size: 18))
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
    }
}

// MARK: - ✨ REVEAL STICKER EDITOR

struct RevealStickerEditorView: View {
    @Binding var stickers: [StickerItem]
    @Binding var editingId: String?

    @State private var selectedTab: EditorTab = .presets
    @State private var selectedPresetId: String = "classic"

    // Custom state
    @State private var customType: String = "solid"
    @State private var customPattern: String = "dots"
    @State private var customPrimary: Color = .black
    @State private var customSecondary: Color = .black

    enum EditorTab {
        case presets
        case custom
    }

    private var currentStickerIndex: Int? {
        stickers.firstIndex(where: { $0.id == editingId })
    }

    var body: some View {
        ZStack {
            // 1. Preview Background (Full Screen)
            if let index = currentStickerIndex {
                RevealSurfaceView(
                    type: stickers[index].interactionData?.revealType,
                    pattern: stickers[index].interactionData?.revealPattern,
                    primaryColor: stickers[index].interactionData?.revealPrimaryColor,
                    secondaryColor: stickers[index].interactionData?.revealSecondaryColor
                )
                .ignoresSafeArea()
            }

            // 2. Editor UI
            VStack(spacing: 0) {
                headerView

                Spacer()

                VStack(spacing: 24) {
                    tabSelector

                    if selectedTab == .presets {
                        presetsGrid
                    } else {
                        customControls
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 65) // Ajustado a 65 según preferencia
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6), .black.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .onAppear {
            loadCurrentState()
        }
    }

    private var headerView: some View {
        HStack {
            Button(action: { editingId = nil }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .liquidGlass(in: Circle())
            }

            Spacer()

            Text(NSLocalizedString("revealEditor.title", comment: "Customize Reveal"))
                .font(.custom("Poppins-SemiBold", size: 17))
                .foregroundColor(.white)
                .shadow(radius: 4)

            Spacer()

            Button(action: { editingId = nil }) {
                Text(NSLocalizedString("common.done", comment: "Done"))
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .liquidGlass(in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            tabButton(title: NSLocalizedString("revealEditor.tab.presets", comment: "Presets"), tab: .presets)
            tabButton(title: NSLocalizedString("revealEditor.tab.custom", comment: "Custom"), tab: .custom)
        }
        .padding(4)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
    }

    private func tabButton(title: String, tab: EditorTab) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab
            }
        }) {
            Text(title)
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(selectedTab == tab ? Color.white.opacity(0.2) : Color.clear)
                )
        }
    }

    private var presetsGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(revealPresets) { preset in
                    Button(action: { applyPreset(preset) }) {
                        VStack(spacing: 8) {
                            RevealSurfaceView(
                                type: preset.type,
                                pattern: preset.pattern,
                                primaryColor: preset.primary,
                                secondaryColor: preset.secondary
                            )
                            .frame(width: 80, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(selectedPresetId == preset.id ? Color.white : Color.white.opacity(0.2), lineWidth: 2)
                            )

                            Text(NSLocalizedString("revealEditor.preset.\(preset.id)", comment: ""))
                                .font(.custom("Poppins-Medium", size: 12))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(.horizontal, 5)
        }
        .frame(height: 160)
    }

    private var customControls: some View {
        VStack(spacing: 20) {
            // Pattern Picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(["none", "dots", "noise", "static", "scanlines", "grid", "lines", "waves", "matrix", "holographic"], id: \.self) { p in
                        Button(action: { updateCustomPattern(p) }) {
                            Text(NSLocalizedString("revealEditor.pattern.\(p)", comment: ""))
                                .font(.custom("Poppins-Medium", size: 13))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(customPattern == p ? Color.white : Color.white.opacity(0.1))
                                .foregroundColor(customPattern == p ? .black : .white)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            HStack(spacing: 30) {
                VStack(spacing: 4) {
                    ColorPicker(selection: $customPrimary, supportsOpacity: false) {
                        Circle()
                            .fill(customPrimary)
                            .frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                    .labelsHidden()

                    Text(NSLocalizedString("revealEditor.color1", comment: ""))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
                .onChange(of: customPrimary) { updateCustomColors() }

                // Color 2 (Optional)
                if customType == "gradient" {
                    VStack(spacing: 4) {
                        ColorPicker(selection: $customSecondary, supportsOpacity: false) {
                            Circle()
                                .fill(customSecondary)
                                .frame(width: 44, height: 44)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        }
                        .labelsHidden()

                        Text(NSLocalizedString("revealEditor.color2", comment: ""))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .onChange(of: customSecondary) { updateCustomColors() }
                }

                Button(action: toggleType) {
                    Image(systemName: customType == "solid" ? "plus" : "minus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
    }


    // MARK: - Logic

    private func loadCurrentState() {
        guard let index = currentStickerIndex else { return }
        let data = stickers[index].interactionData

        customType = data?.revealType ?? "solid"
        customPattern = data?.revealPattern ?? "dots"
        customPrimary = Color(hex: data?.revealPrimaryColor ?? "#000000") ?? .black
        customSecondary = Color(hex: data?.revealSecondaryColor ?? "#000000") ?? .black

        // Try to match preset
        if let preset = revealPresets.first(where: {
            $0.type == customType &&
            $0.pattern == customPattern &&
            $0.primary.lowercased() == data?.revealPrimaryColor?.lowercased()
        }) {
            selectedPresetId = preset.id
            selectedTab = .presets
        } else {
            selectedTab = .custom
        }
    }

    private func applyPreset(_ preset: RevealPreset) {
        selectedPresetId = preset.id
        updateSticker(type: preset.type, pattern: preset.pattern, primary: preset.primary, secondary: preset.secondary)
        HapticManager.shared.lightImpact()
    }

    private func updateCustomPattern(_ p: String) {
        customPattern = p
        updateSticker(type: customType, pattern: p, primary: customPrimary.toHex() ?? "#000000", secondary: customSecondary.toHex() ?? "#000000")
    }

    private func updateCustomColors() {
        updateSticker(type: customType, pattern: customPattern, primary: customPrimary.toHex() ?? "#000000", secondary: customSecondary.toHex() ?? "#000000")
    }

    private func toggleType() {
        withAnimation {
            customType = customType == "solid" ? "gradient" : "solid"
        }
        updateCustomColors()
    }

    private func updateSticker(type: String, pattern: String, primary: String, secondary: String) {
        guard let index = currentStickerIndex else { return }
        var data = stickers[index].interactionData ?? StickerItem.StickerInteractionData()

        data.revealType = type
        data.revealPattern = pattern
        data.revealPrimaryColor = primary
        data.revealSecondaryColor = secondary

        stickers[index].interactionData = data
    }
}

struct RevealPreset: Identifiable {
    let id: String
    let name: String
    let type: String
    let pattern: String
    let primary: String
    let secondary: String
}

let revealPresets: [RevealPreset] = [
    RevealPreset(id: "classic", name: "Classic", type: "solid", pattern: "dots", primary: "#000000", secondary: "#000000"),
    RevealPreset(id: "midnight", name: "Midnight", type: "solid", pattern: "grid", primary: "#0B1215", secondary: "#0B1215"),
    RevealPreset(id: "golden", name: "Golden", type: "gradient", pattern: "noise", primary: "#BF953F", secondary: "#8E6E2D"),
    RevealPreset(id: "neon", name: "Neon Glow", type: "gradient", pattern: "lines", primary: "#430089", secondary: "#82009F"),
    RevealPreset(id: "silver", name: "Silver", type: "gradient", pattern: "dots", primary: "#C0C0C0", secondary: "#708090"),
    RevealPreset(id: "retro", name: "Old TV", type: "solid", pattern: "static", primary: "#FFFFFF", secondary: "#FFFFFF"),
    RevealPreset(id: "matrix", name: "Matrix", type: "solid", pattern: "matrix", primary: "#000000", secondary: "#000000"),
    RevealPreset(id: "blueprint", name: "Blueprint", type: "solid", pattern: "grid", primary: "#003366", secondary: "#003366"),
    RevealPreset(id: "magic", name: "Magic", type: "solid", pattern: "holographic", primary: "#C8C8C8", secondary: "#C8C8C8")
]

fileprivate func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
    let generator = UIImpactFeedbackGenerator(style: style)
    generator.prepare()
    generator.impactOccurred()
}

fileprivate func hapticNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    let generator = UINotificationFeedbackGenerator()
    generator.prepare()
    generator.notificationOccurred(type)
}
