import SwiftUI
import UIKit
import PencilKit

// MARK: - Drawing View Implementation

struct DrawingView: UIViewControllerRepresentable {
    let backgroundImage: UIImage?
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

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .white, width: 3)
        view.addSubview(canvasView)

        let topToolbar = UIView()
        topToolbar.translatesAutoresizingMaskIntoConstraints = false
        topToolbar.backgroundColor = UIColor.black.withAlphaComponent(0.16)
        topToolbar.layer.cornerRadius = 22
        topToolbar.layer.borderWidth = 1
        topToolbar.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        topToolbar.clipsToBounds = true
        view.addSubview(topToolbar)
        addBlurBackground(to: topToolbar)

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

        var doneButtonConfig = UIButton.Configuration.filled()
        var doneTitleAttr = AttributeContainer()
        doneTitleAttr.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        doneButtonConfig.attributedTitle = AttributedString(NSLocalizedString("creator.done", comment: "Done"), attributes: doneTitleAttr)
        doneButtonConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        doneButtonConfig.background.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        doneButtonConfig.background.cornerRadius = 15
        doneButtonConfig.baseForegroundColor = .white

        let doneButton = UIButton(configuration: doneButtonConfig)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        topToolbar.addSubview(doneButton)

        let bottomToolbar = UIView()
        bottomToolbar.translatesAutoresizingMaskIntoConstraints = false
        bottomToolbar.backgroundColor = UIColor.black.withAlphaComponent(0.16)
        bottomToolbar.layer.cornerRadius = 26
        bottomToolbar.layer.borderWidth = 1
        bottomToolbar.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        bottomToolbar.clipsToBounds = true
        view.addSubview(bottomToolbar)
        addBlurBackground(to: bottomToolbar)

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

        let colorStack = createColorPicker()
        colorStack.translatesAutoresizingMaskIntoConstraints = false
        bottomToolbar.addSubview(colorStack)

        NSLayoutConstraint.activate([
            canvasView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topToolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            topToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            topToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            topToolbar.heightAnchor.constraint(equalToConstant: 58),

            closeButton.leadingAnchor.constraint(equalTo: topToolbar.leadingAnchor, constant: 12),
            closeButton.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            undoButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 10),
            undoButton.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),

            redoButton.leadingAnchor.constraint(equalTo: undoButton.trailingAnchor, constant: 8),
            redoButton.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),

            doneButton.trailingAnchor.constraint(equalTo: topToolbar.trailingAnchor, constant: -12),
            doneButton.centerYAnchor.constraint(equalTo: topToolbar.centerYAnchor),

            bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            bottomToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            bottomToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            bottomToolbar.heightAnchor.constraint(equalToConstant: 154),

            toolStack.centerXAnchor.constraint(equalTo: bottomToolbar.centerXAnchor),
            toolStack.topAnchor.constraint(equalTo: bottomToolbar.topAnchor, constant: 14),

            widthSlider.leadingAnchor.constraint(equalTo: bottomToolbar.leadingAnchor, constant: 16),
            widthSlider.trailingAnchor.constraint(equalTo: bottomToolbar.trailingAnchor, constant: -16),
            widthSlider.topAnchor.constraint(equalTo: toolStack.bottomAnchor, constant: 10),

            colorStack.centerXAnchor.constraint(equalTo: bottomToolbar.centerXAnchor),
            colorStack.bottomAnchor.constraint(equalTo: bottomToolbar.bottomAnchor, constant: -12),
            colorStack.topAnchor.constraint(equalTo: widthSlider.bottomAnchor, constant: 8)
        ])

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
        let renderer = UIGraphicsImageRenderer(bounds: canvasView.bounds)
        let image = renderer.image { context in
            UIColor.clear.setFill()
            context.fill(canvasView.bounds)
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
