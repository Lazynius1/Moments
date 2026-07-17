import PencilKit
import SwiftUI
import UIKit

private enum StoryDrawingBrush {
    case pen
    case arrow
    case glow
    case marker
    case pencil
    case eraser
}

struct StoryDrawingEditorOverlay: View {
    @Binding var isPresented: Bool
    @Binding var drawingImage: UIImage?
    let canvasRect: CGRect

    @State private var baseDrawing: UIImage?
    @State private var liveGlowImage: UIImage?
    @State private var brush: StoryDrawingBrush = .pen
    @State private var brushWidth: CGFloat = 7
    @State private var color: UIColor = .white

    @State private var clearToken = 0
    @State private var undoToken = 0
    @State private var redoToken = 0
    @State private var exportToken = 0
    @Environment(\.colorScheme) private var colorScheme

    private var chromeIconColor: Color {
        StoryEditorChromeColor.icon(colorScheme)
    }

    private var chromeSecondaryColor: Color {
        chromeIconColor.opacity(colorScheme == .dark ? 0.58 : 0.62)
    }

    private var chromeDividerColor: Color {
        chromeIconColor.opacity(colorScheme == .dark ? 0.16 : 0.12)
    }

    private var chromeStrokeColor: Color {
        chromeIconColor.opacity(colorScheme == .dark ? 0.12 : 0.10)
    }

    private var chromeTintColor: Color {
        MomentsChromeGlass.canvasTint(for: colorScheme)
    }

    init(isPresented: Binding<Bool>, drawingImage: Binding<UIImage?>, canvasRect: CGRect) {
        self._isPresented = isPresented
        self._drawingImage = drawingImage
        self.canvasRect = canvasRect
        self._baseDrawing = State(initialValue: drawingImage.wrappedValue)
    }

    var body: some View {
        GeometryReader { proxy in
            let windowInsets = keyWindowSafeAreaInsets()
            let safeAreaTop = windowInsets.top
            let safeAreaBottom = windowInsets.bottom
            let captureRect = canvasRect
            let canvasTopScreen = captureRect.minY + safeAreaTop
            let canvasBottomScreen = captureRect.maxY + safeAreaTop
            let canvasBottomGap = max(0, proxy.size.height - canvasBottomScreen)
            let chromeHeight: CGFloat = 92 // 40 (palette) + 8 (spacing) + 44 (toolbar)
            let bottomPadding = max(safeAreaBottom + 44, (canvasBottomGap - chromeHeight) / 2)

            let topButtonsBottom = topBarTopPadding(safeAreaTop) + 52
            let localTopExclude = max(0, topButtonsBottom - canvasTopScreen)
            let localBottomExclude = (proxy.size.height - (chromeHeight + bottomPadding)) - canvasTopScreen

            ZStack {
                // Constraints base drawing, PencilKit canvas, and glow preview inside the story captureRect
                ZStack {
                    if let baseDrawing {
                        Image(uiImage: baseDrawing)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: captureRect.width, height: captureRect.height)
                            .allowsHitTesting(false)
                    }

                    StoryDrawingCanvasView(
                        brush: $brush,
                        color: $color,
                        brushWidth: $brushWidth,
                        clearToken: $clearToken,
                        undoToken: $undoToken,
                        redoToken: $redoToken,
                        exportToken: $exportToken,
                        onExport: { strokesImage, hasStrokes in
                            if hasStrokes {
                                if let base = baseDrawing {
                                    drawingImage = merge(base: base, overlay: strokesImage)
                                } else {
                                    drawingImage = strokesImage
                                }
                            } else {
                                drawingImage = baseDrawing
                            }
                            isPresented = false
                        },
                        onLiveGlowPreview: { image in
                            liveGlowImage = image
                        },
                        localTopExclude: localTopExclude,
                        localBottomExclude: localBottomExclude
                    )
                    .frame(width: captureRect.width, height: captureRect.height)

                    if let liveGlowImage {
                        Image(uiImage: liveGlowImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: captureRect.width, height: captureRect.height)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: captureRect.width, height: captureRect.height)
                .position(x: captureRect.midX, y: captureRect.midY + safeAreaTop)
                .clipped()

                // Left side size slider
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        StoryVerticalBrushSlider(
                            value: $brushWidth,
                            range: 2...26
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 16)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, chromeHeight + bottomPadding)
            }
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                HStack(spacing: 10) {
                    if #available(iOS 26.0, *) {
                        GlassEffectContainer(spacing: 10) {
                            topLeadingButtonsCluster
                        }
                    } else {
                        topLeadingButtonsCluster
                    }

                    Spacer()

                    Button(action: { exportToken += 1 }) {
                        Text(NSLocalizedString("storyTextEditor.done", comment: "Done"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(chromeIconColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .momentsChromeGlass(in: Capsule(), style: .tinted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, topBarTopPadding(safeAreaTop))
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    // 1. Color Palette Row
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            // Custom Color Picker (gradient circle)
                            customColorPicker

                            Divider()
                                .frame(height: 20)
                                .background(chromeDividerColor)

                            // Moments backgrounds: Light (#FAF9F6) & Dark (#0B1215)
                            colorSwatch(UIColor(hex: "FAF9F6"))
                            colorSwatch(UIColor(hex: "0B1215"))

                            Divider()
                                .frame(height: 20)
                                .background(chromeDividerColor)

                            ForEach(drawingPalette, id: \.self) { paletteColor in
                                colorSwatch(paletteColor)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .frame(height: 40)

                    // 2. Brush Toolbar (aligned with text toolbar)
                    HStack(spacing: 0) {
                        brushButton(icon: "paintbrush.pointed.fill", brushType: .pen)
                        toolbarDivider
                        brushButton(icon: "arrow.up.right", brushType: .arrow)
                        toolbarDivider
                        brushButton(icon: "highlighter", brushType: .marker)
                        toolbarDivider
                        brushButton(icon: "pencil", brushType: .pencil)
                        toolbarDivider
                        brushButton(icon: "sparkles", brushType: .glow)
                        toolbarDivider
                        brushButton(icon: "eraser", brushType: .eraser)
                    }
                    .frame(height: 44)
                    .momentsChromeGlass(
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                        interactive: false,
                        tint: chromeTintColor
                    )
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.10), radius: 12, x: 0, y: 6)
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, bottomPadding)
            }
        }
        .ignoresSafeArea()
    }

    private var drawingPalette: [UIColor] {
        [
            UIColor(hex: "FFFFFF"), UIColor(hex: "000000"),
            UIColor(hex: "FF3B30"), UIColor(hex: "FF9500"), UIColor(hex: "FFCC00"),
            UIColor(hex: "34C759"), UIColor(hex: "007AFF"), UIColor(hex: "5856D6"),
            UIColor(hex: "AF52DE"), UIColor(hex: "FF2D55"), UIColor(hex: "A2845E"),
            UIColor(hex: "F2C94C"), UIColor(hex: "00C7BE"), UIColor(hex: "8E8E93"),
            UIColor(hex: "FFD60A"), UIColor(hex: "BF5AF2"), UIColor(hex: "64D2FF"),
            UIColor(hex: "FF6B6B"), UIColor(hex: "C4B5A5"), UIColor(hex: "1C1C1E")
        ]
    }

    private func merge(base: UIImage, overlay: UIImage) -> UIImage {
        let size = base.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
            overlay.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(chromeDividerColor)
            .frame(width: 1, height: 24)
    }

    private var topLeadingButtonsCluster: some View {
        HStack(spacing: 10) {
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundStyle(chromeIconColor)
                    .padding(12)
                    .momentsChromeGlass(in: Circle(), style: .tinted)
            }

            Button(action: { undoToken += 1 }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title2)
                    .foregroundStyle(chromeIconColor)
                    .padding(12)
                    .momentsChromeGlass(in: Circle(), style: .tinted)
            }

            Button(action: { redoToken += 1 }) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.title2)
                    .foregroundStyle(chromeIconColor)
                    .padding(12)
                    .momentsChromeGlass(in: Circle(), style: .tinted)
            }
        }
    }

    private func brushButton(icon: String, brushType: StoryDrawingBrush) -> some View {
        let isSelected = brush == brushType
        return Button(action: { brush = brushType }) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? chromeIconColor : chromeSecondaryColor)
                .shadow(color: isSelected && brushType == .glow ? Color(color).opacity(0.8) : Color.clear, radius: 6)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var customColorPicker: some View {
        ColorPicker("", selection: Binding(
            get: { Color(color) },
            set: { newColor in
                let uiColor = UIColor(newColor)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
                    color = UIColor(red: r, green: g, blue: b, alpha: a)
                } else {
                    color = UIColor(cgColor: uiColor.cgColor)
                }
            }
        ), supportsOpacity: false)
        .labelsHidden()
        .frame(width: 24, height: 24)
        .overlay(
            Circle()
                .stroke(chromeStrokeColor, lineWidth: 1)
        )
    }

    private func colorSwatch(_ paletteColor: UIColor) -> some View {
        let isSelected = color == paletteColor
        let swatchColor = Color(paletteColor)
        let isLightSwatch = isPerceptuallyLight(paletteColor)
        let strokeColor = isLightSwatch ? Color.black.opacity(0.50) : Color.white.opacity(0.92)
        let selectedStrokeColor = isLightSwatch ? Color.black.opacity(0.90) : Color.white

        return Button(action: {
            color = paletteColor
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            Circle()
                .fill(swatchColor)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? selectedStrokeColor : strokeColor,
                            lineWidth: isSelected ? 2.5 : 1
                        )
                )
                .shadow(color: .black.opacity(isLightSwatch ? 0.16 : 0.10), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func isPerceptuallyLight(_ color: UIColor) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return false
        }
        return (0.299 * red + 0.587 * green + 0.114 * blue) > 0.78
    }

    private func topBarTopPadding(_ safeAreaTop: CGFloat) -> CGFloat {
        let fallbackSafeTop = keyWindowSafeAreaInsets().top
        let resolvedSafeTop = max(safeAreaTop, fallbackSafeTop)
        return max(76, resolvedSafeTop + 16)
    }

    private func keyWindowSafeAreaInsets() -> UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

}

private struct StoryVerticalBrushSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let trackHeight = height - 32
            let progress = (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.001)
            let knobY = 16 + (1 - progress) * trackHeight

            ZStack(alignment: .top) {
                // Tapered track background
                TaperedSliderTrack()
                    .fill(Color.white.opacity(0.32))
                    .frame(width: 16)
                    .frame(height: trackHeight)
                    .offset(y: 16)

                // White knob with shadow
                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .shadow(color: Color.black.opacity(isDragging ? 0.35 : 0.22), radius: isDragging ? 5 : 3, x: 0, y: isDragging ? 3 : 1)
                    .scaleEffect(isDragging ? 1.12 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
                    .offset(x: 0, y: knobY - 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let clampedY = min(max(gesture.location.y, 16), height - 16)
                        let inverseProgress = 1 - ((clampedY - 16) / max(trackHeight, 1))
                        let newValue = range.lowerBound + (inverseProgress * (range.upperBound - range.lowerBound))
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(width: 44, height: 220)
    }
}

private final class GlowTouchObserver: UIGestureRecognizer {
    var onBegan: (() -> Void)?
    var onMoved: ((CGPoint) -> Void)?
    var onEnded: (() -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onBegan?()
        if let touch = touches.first, let view { onMoved?(touch.location(in: view)) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view { onMoved?(touch.location(in: view)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        onEnded?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        onEnded?()
    }
}

private class MomentsPKCanvasView: PKCanvasView, UIGestureRecognizerDelegate {
    var localTopExclude: CGFloat = 0
    var localBottomExclude: CGFloat = 999999

    var liveGlowEnabled = false
    var liveGlowColor: UIColor = .white
    var liveGlowCoreWidth: CGFloat = 3
    var liveGlowBlur: CGFloat = 6

    private let liveGlowLayer = CAShapeLayer()
    private var didConfigure = false
    private var glowPoints: [CGPoint] = []

    private func configureIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true
        liveGlowLayer.fillColor = UIColor.clear.cgColor
        liveGlowLayer.lineCap = .round
        liveGlowLayer.lineJoin = .round
        liveGlowLayer.shadowOffset = .zero
        layer.addSublayer(liveGlowLayer)

        let observer = GlowTouchObserver(target: nil, action: nil)
        observer.delegate = self
        observer.onBegan = { [weak self] in self?.glowPoints.removeAll() }
        observer.onMoved = { [weak self] point in self?.appendGlowPoint(point) }
        observer.onEnded = { [weak self] in self?.glowPoints.removeAll() }
        addGestureRecognizer(observer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        configureIfNeeded()
        liveGlowLayer.frame = bounds
    }

    private func appendGlowPoint(_ point: CGPoint) {
        guard liveGlowEnabled else { return }
        glowPoints.append(point)
        updateLiveGlow(path: Self.smoothPath(from: glowPoints))
    }

    private func updateLiveGlow(path: CGPath) {
        configureIfNeeded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        liveGlowLayer.path = path
        liveGlowLayer.strokeColor = UIColor.white.cgColor
        liveGlowLayer.lineWidth = liveGlowCoreWidth
        liveGlowLayer.shadowColor = liveGlowColor.cgColor
        liveGlowLayer.shadowRadius = liveGlowBlur
        liveGlowLayer.shadowOpacity = 1
        CATransaction.commit()
    }

    func clearLiveGlow() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        liveGlowLayer.path = nil
        CATransaction.commit()
    }

    private static func smoothPath(from points: [CGPoint]) -> CGPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path.cgPath }
        path.move(to: first)
        if points.count > 1 {
            for i in 1..<points.count {
                let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
                path.addQuadCurve(to: mid, controlPoint: points[i - 1])
            }
            path.addLine(to: points[points.count - 1])
        }
        return path.cgPath
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if point.y < localTopExclude {
            return false
        }
        if point.y > localBottomExclude {
            return false
        }
        return super.point(inside: point, with: event)
    }
}

private struct StoryDrawingCanvasView: UIViewRepresentable {
    @Binding var brush: StoryDrawingBrush
    @Binding var color: UIColor
    @Binding var brushWidth: CGFloat

    @Binding var clearToken: Int
    @Binding var undoToken: Int
    @Binding var redoToken: Int
    @Binding var exportToken: Int

    let onExport: (UIImage, Bool) -> Void
    let onLiveGlowPreview: (UIImage?) -> Void

    let localTopExclude: CGFloat
    let localBottomExclude: CGFloat

    fileprivate struct StrokeMetadata {
        let brush: StoryDrawingBrush
        let color: UIColor
        let width: CGFloat
    }

    private enum GlowConfig {
        static let coreWidthMultiplier: CGFloat = 0.3

        static let shadowRadiusMultiplier: CGFloat = 0.35
        static let shadowRadiusMinimum: CGFloat = 2

        static func shadowRadius(for width: CGFloat) -> CGFloat {
            max(shadowRadiusMinimum, width * shadowRadiusMultiplier)
        }
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = MomentsPKCanvasView()
        canvas.localTopExclude = localTopExclude
        canvas.localBottomExclude = localBottomExclude
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawingPolicy = .anyInput
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInset = .zero
        canvas.contentSize = .zero
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.currentBrush = brush
        context.coordinator.currentColor = color
        context.coordinator.currentWidth = brushWidth
        uiView.tool = currentTool()

        if let momentsCanvas = uiView as? MomentsPKCanvasView {
            momentsCanvas.localTopExclude = localTopExclude
            momentsCanvas.localBottomExclude = localBottomExclude
            momentsCanvas.liveGlowEnabled = (brush == .glow)
            momentsCanvas.liveGlowColor = color
            momentsCanvas.liveGlowCoreWidth = brushWidth
            momentsCanvas.liveGlowBlur = GlowConfig.shadowRadius(for: brushWidth)
        }

        if uiView.contentSize != uiView.bounds.size {
            uiView.contentSize = uiView.bounds.size
        }

        if clearToken != context.coordinator.lastClearToken {
            context.coordinator.lastClearToken = clearToken
            context.coordinator.strokeMetadata = []
            uiView.drawing = PKDrawing()
        }

        if undoToken != context.coordinator.lastUndoToken {
            context.coordinator.lastUndoToken = undoToken
            uiView.undoManager?.undo()
        }

        if redoToken != context.coordinator.lastRedoToken {
            context.coordinator.lastRedoToken = redoToken
            uiView.undoManager?.redo()
        }

        if exportToken != context.coordinator.lastExportToken {
            context.coordinator.lastExportToken = exportToken
            let hasStrokes = !uiView.drawing.strokes.isEmpty
            let exported = renderExportedImage(
                from: uiView.drawing,
                bounds: uiView.bounds,
                scale: uiView.traitCollection.displayScale,
                strokeMetadata: context.coordinator.strokeMetadata
            )
            onExport(exported, hasStrokes)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLiveGlowPreview: onLiveGlowPreview)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let onLiveGlowPreview: (UIImage?) -> Void

        var lastClearToken = 0
        var lastUndoToken = 0
        var lastRedoToken = 0
        var lastExportToken = 0
        var currentBrush: StoryDrawingBrush = .pen
        var currentColor: UIColor = .white
        var currentWidth: CGFloat = 7
        fileprivate var strokeMetadata: [StrokeMetadata] = []

        private var isActivelyDrawing = false
        private let glowRenderQueue = DispatchQueue(label: "com.moments.story.glowRender", qos: .userInteractive)
        private var pendingBakeWorkItem: DispatchWorkItem?

        init(onLiveGlowPreview: @escaping (UIImage?) -> Void) {
            self.onLiveGlowPreview = onLiveGlowPreview
            super.init()
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            isActivelyDrawing = true
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isActivelyDrawing = false
            scheduleBake(from: canvasView)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let strokeCount = canvasView.drawing.strokes.count

            if strokeCount > strokeMetadata.count {
                let newMetadata = StrokeMetadata(
                    brush: currentBrush,
                    color: currentColor,
                    width: currentWidth
                )
                strokeMetadata.append(contentsOf: Array(repeating: newMetadata, count: strokeCount - strokeMetadata.count))
            } else if strokeCount < strokeMetadata.count {
                strokeMetadata = Array(strokeMetadata.prefix(strokeCount))
            }

            if !isActivelyDrawing {
                scheduleBake(from: canvasView)
            }
        }

        private func scheduleBake(from canvasView: PKCanvasView) {
            pendingBakeWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.bakeOverlay(from: canvasView)
            }
            pendingBakeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: workItem)
        }

        private func bakeOverlay(from canvasView: PKCanvasView) {
            let glowCanvas = canvasView as? MomentsPKCanvasView
            let shouldRender = strokeMetadata.contains(where: { $0.brush == .glow || $0.brush == .arrow })
            guard shouldRender else {
                onLiveGlowPreview(nil)
                glowCanvas?.clearLiveGlow()
                return
            }

            let drawingSnapshot = canvasView.drawing
            let boundsSnapshot = canvasView.bounds
            let metadataSnapshot = strokeMetadata
            let scaleSnapshot = canvasView.traitCollection.displayScale

            glowRenderQueue.async { [onLiveGlowPreview, weak glowCanvas] in
                let preview = StoryDrawingCanvasView.renderLiveOverlayImage(
                    from: drawingSnapshot,
                    bounds: boundsSnapshot,
                    strokeMetadata: metadataSnapshot,
                    scale: scaleSnapshot
                )
                DispatchQueue.main.async {
                    onLiveGlowPreview(preview)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        glowCanvas?.clearLiveGlow()
                    }
                }
            }
        }
    }

    private func currentTool() -> PKTool {
        switch brush {
        case .pen:
            return PKInkingTool(.pen, color: color, width: brushWidth)
        case .arrow:
            return PKInkingTool(.pen, color: color, width: max(3, brushWidth))
        case .glow:
            return PKInkingTool(
                .pen,
                color: color.withAlphaComponent(0.02),
                width: max(2, brushWidth * GlowConfig.coreWidthMultiplier)
            )
        case .marker:
            return PKInkingTool(.marker, color: color.withAlphaComponent(0.40), width: max(10, brushWidth * 2.4))
        case .pencil:
            return PKInkingTool(.pencil, color: color, width: brushWidth)
        case .eraser:
            return PKEraserTool(.bitmap)
        }
    }

    private func renderExportedImage(
        from drawing: PKDrawing,
        bounds: CGRect,
        scale: CGFloat,
        strokeMetadata: [StrokeMetadata]
    ) -> UIImage {
        let hasGlowStrokes = strokeMetadata.contains(where: { $0.brush == .glow })
        let hasArrowStrokes = strokeMetadata.contains(where: { $0.brush == .arrow })

        // Build a "clean" drawing without glow strokes so they don't appear as ghost lines.
        let cleanDrawing: PKDrawing
        if hasGlowStrokes {
            let nonGlowStrokes = drawing.strokes.enumerated().compactMap { (index, stroke) -> PKStroke? in
                guard index < strokeMetadata.count else { return stroke }
                return strokeMetadata[index].brush == .glow ? nil : stroke
            }
            var rebuilt = PKDrawing()
            rebuilt.strokes = nonGlowStrokes
            cleanDrawing = rebuilt
        } else {
            cleanDrawing = drawing
        }

        let baseImage = cleanDrawing.image(from: bounds, scale: scale)

        guard hasGlowStrokes || hasArrowStrokes else {
            return baseImage
        }

        let overlayImage = Self.renderLiveOverlayImage(
            from: drawing,
            bounds: bounds,
            strokeMetadata: strokeMetadata,
            scale: scale
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        return renderer.image { _ in
            // Draw clean base strokes (including arrow lines)
            baseImage.draw(in: CGRect(origin: .zero, size: bounds.size))

            // Draw overlay on top (glow strokes + arrow heads)
            if let overlayImage {
                overlayImage.draw(in: CGRect(origin: .zero, size: bounds.size))
            }
        }
    }

    private static func renderLiveOverlayImage(
        from drawing: PKDrawing,
        bounds: CGRect,
        strokeMetadata: [StrokeMetadata],
        scale: CGFloat
    ) -> UIImage? {
        let hasGlow = strokeMetadata.contains(where: { $0.brush == .glow })
        let hasArrow = strokeMetadata.contains(where: { $0.brush == .arrow })

        guard hasGlow || hasArrow else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = scale

        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        return renderer.image { rendererCtx in
            let ctx = rendererCtx.cgContext

            for (index, stroke) in drawing.strokes.enumerated() {
                guard index < strokeMetadata.count else { continue }
                let metadata = strokeMetadata[index]

                if metadata.brush == .glow {
                    let bezier = strokeToBezierPath(stroke: stroke)
                    guard !bezier.cgPath.isEmpty else { continue }

                    let shapeLayer = CAShapeLayer()
                    shapeLayer.anchorPoint = .zero
                    shapeLayer.frame = CGRect(origin: .zero, size: bounds.size)
                    shapeLayer.contentsScale = scale
                    shapeLayer.path = bezier.cgPath
                    shapeLayer.fillColor = UIColor.clear.cgColor
                    shapeLayer.strokeColor = UIColor.white.cgColor
                    shapeLayer.lineWidth = metadata.width
                    shapeLayer.lineCap = .round
                    shapeLayer.lineJoin = .round
                    shapeLayer.shadowOffset = .zero
                    shapeLayer.shadowColor = metadata.color.cgColor
                    shapeLayer.shadowRadius = GlowConfig.shadowRadius(for: metadata.width)
                    shapeLayer.shadowOpacity = 1

                    ctx.saveGState()
                    shapeLayer.render(in: ctx)
                    ctx.restoreGState()
                } else if metadata.brush == .arrow {
                    drawArrowHead(for: stroke, metadata: metadata, in: ctx)
                }
            }
        }
    }

    private static func strokeToBezierPath(stroke: PKStroke) -> UIBezierPath {
        let pts = stroke.path
        guard !pts.isEmpty else { return UIBezierPath() }

        let bezier = UIBezierPath()
        bezier.move(to: pts[0].location)

        if pts.count > 1 {
            for i in 1..<pts.count {
                let mid = CGPoint(
                    x: (pts[i - 1].location.x + pts[i].location.x) / 2,
                    y: (pts[i - 1].location.y + pts[i].location.y) / 2
                )
                bezier.addQuadCurve(to: mid, controlPoint: pts[i - 1].location)
            }
            bezier.addLine(to: pts[pts.count - 1].location)
        }

        bezier.lineCapStyle = .round
        bezier.lineJoinStyle = .round
        return bezier
    }

    private static func drawArrowHead(for stroke: PKStroke, metadata: StrokeMetadata, in ctx: CGContext) {
        let path = stroke.path
        guard path.count >= 2 else { return }

        let endIndex = path.index(before: path.endIndex)
        let previousIndex = path.index(before: endIndex)
        let endPoint = path[endIndex].location
        let previousPoint = path[previousIndex].location

        let dx = endPoint.x - previousPoint.x
        let dy = endPoint.y - previousPoint.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return }

        let angle = atan2(dy, dx)
        let headLength = max(12, metadata.width * 3.2)
        let spread: CGFloat = .pi / 7

        let left = CGPoint(
            x: endPoint.x - headLength * cos(angle - spread),
            y: endPoint.y - headLength * sin(angle - spread)
        )
        let right = CGPoint(
            x: endPoint.x - headLength * cos(angle + spread),
            y: endPoint.y - headLength * sin(angle + spread)
        )

        ctx.saveGState()
        ctx.setStrokeColor(metadata.color.cgColor)
        ctx.setLineWidth(max(3, metadata.width * 0.9))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        ctx.move(to: left)
        ctx.addLine(to: endPoint)
        ctx.addLine(to: right)
        ctx.strokePath()
        ctx.restoreGState()
    }
}
