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

    init(isPresented: Binding<Bool>, drawingImage: Binding<UIImage?>) {
        self._isPresented = isPresented
        self._drawingImage = drawingImage
        self._baseDrawing = State(initialValue: drawingImage.wrappedValue)
    }

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            let safeAreaTop = proxy.safeAreaInsets.top
            let safeAreaBottom = proxy.safeAreaInsets.bottom
            let captureRect = creatorMomentsCaptureRect(
                in: proxy.size,
                topInset: safeAreaTop,
                bottomInset: safeAreaBottom
            )
            let canvasBottomGap = max(0, proxy.size.height - captureRect.maxY)
            let chromeHeight: CGFloat = 92 // 40 (palette) + 8 (spacing) + 44 (toolbar)
            let bottomPadding = max(8, (canvasBottomGap - chromeHeight) / 2)

            let localTopExclude = max(0, (safeAreaTop + 60) - captureRect.minY)
            let localBottomExclude = (proxy.size.height - (chromeHeight + bottomPadding)) - captureRect.minY

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
                .position(x: captureRect.midX, y: captureRect.midY)
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
                HStack {
                    HStack(spacing: 4) {
                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                                .padding(14)
                        }
                        .buttonStyle(.plain)

                        Button(action: { undoToken += 1 }) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .padding(14)
                        }
                        .buttonStyle(.plain)

                        Button(action: { redoToken += 1 }) {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .padding(14)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button(action: { exportToken += 1 }) {
                        Text(NSLocalizedString("storyTextEditor.done", comment: "Done"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
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
                                .background(Color.white.opacity(0.3))

                            // Moments backgrounds: Light (#FAF9F6) & Dark (#0B1215)
                            colorSwatch(UIColor(hex: "FAF9F6"))
                            colorSwatch(UIColor(hex: "0B1215"))

                            Divider()
                                .frame(height: 20)
                                .background(Color.white.opacity(0.3))

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
                        brushButton(icon: "pencil.tip", brushType: .pen)
                        toolbarDivider
                        brushButton(icon: "arrow.up.right", brushType: .arrow)
                        toolbarDivider
                        brushButton(icon: "highlighter", brushType: .marker)
                        toolbarDivider
                        brushButton(icon: "pencil", brushType: .pencil)
                        toolbarDivider
                        brushButton(icon: "lightbulb.fill", brushType: .glow)
                        toolbarDivider
                        brushButton(icon: "eraser", brushType: .eraser)
                    }
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    )
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
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 24)
    }

    private func brushButton(icon: String, brushType: StoryDrawingBrush) -> some View {
        let isSelected = brush == brushType
        return Button(action: { brush = brushType }) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: isSelected ? .semibold : .medium))
                .foregroundColor(.white.opacity(isSelected ? 1.0 : 0.55))
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
    }

    private func colorSwatch(_ paletteColor: UIColor) -> some View {
        let isSelected = color == paletteColor
        let swatchColor = Color(paletteColor)
        let strokeColor = swatchColor == .white ? Color.gray.opacity(0.9) : Color.white.opacity(0.92)

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
                            isSelected ? Color.white : strokeColor,
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func topBarTopPadding(_ safeAreaTop: CGFloat) -> CGFloat {
        let fallbackSafeTop = keyWindowSafeAreaInsets().top
        let resolvedSafeTop = max(safeAreaTop, fallbackSafeTop)
        return resolvedSafeTop + 10
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

private class MomentsPKCanvasView: PKCanvasView {
    var localTopExclude: CGFloat = 0
    var localBottomExclude: CGFloat = 999999

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
        // Neon: nearly-invisible PK stroke + intense colored glow via CGContext shadow.
        static let coreWidthMultiplier: CGFloat = 0.3

        // Shadow pass 1: tight, intense inner glow
        static let innerShadowBlur: CGFloat = 3
        static let innerShadowAlpha: CGFloat = 1.0
        static let innerStrokeWidthMultiplier: CGFloat = 0.9

        // Shadow pass 2: medium spread
        static let midShadowBlur: CGFloat = 8
        static let midShadowAlpha: CGFloat = 0.9
        static let midStrokeWidthMultiplier: CGFloat = 0.8

        // Shadow pass 3: wide ambient glow
        static let outerShadowBlur: CGFloat = 18
        static let outerShadowAlpha: CGFloat = 0.4
        static let outerStrokeWidthMultiplier: CGFloat = 0.6
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = MomentsPKCanvasView()
        canvas.localTopExclude = localTopExclude
        canvas.localBottomExclude = localBottomExclude
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
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
                scale: UIScreen.main.scale,
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

        private var glowPreviewWorkItem: DispatchWorkItem?

        init(onLiveGlowPreview: @escaping (UIImage?) -> Void) {
            self.onLiveGlowPreview = onLiveGlowPreview
            super.init()
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

            // WYSIWYG overlay preview (debounced).
            glowPreviewWorkItem?.cancel()
            let shouldRenderGlow = strokeMetadata.contains(where: { $0.brush == .glow })
            let shouldRenderArrow = strokeMetadata.contains(where: { $0.brush == .arrow })
            let drawingSnapshot = canvasView.drawing
            let boundsSnapshot = canvasView.bounds
            let metadataSnapshot = strokeMetadata

            let workItem = DispatchWorkItem { [onLiveGlowPreview] in
                guard shouldRenderGlow || shouldRenderArrow else {
                    onLiveGlowPreview(nil)
                    return
                }

                let preview = StoryDrawingCanvasView.renderLiveOverlayImage(
                    from: drawingSnapshot,
                    bounds: boundsSnapshot,
                    strokeMetadata: metadataSnapshot,
                    scale: UIScreen.main.scale
                )
                onLiveGlowPreview(preview)
            }

            glowPreviewWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
        }
    }

    private func currentTool() -> PKTool {
        switch brush {
        case .pen:
            return PKInkingTool(.pen, color: color, width: brushWidth)
        case .arrow:
            return PKInkingTool(.pen, color: color, width: max(3, brushWidth))
        case .glow:
            // Nearly invisible on PK canvas – the glow overlay provides all visual feedback.
            return PKInkingTool(
                .pen,
                color: color.withAlphaComponent(0.08),
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

                    let glowColor = metadata.color
                    let w = metadata.width

                    let outerBlur = max(14, w * 3.0)
                    let midBlur   = max(6,  w * 1.2)
                    let coreBlur  = max(3,  w * 0.6)

                    // -- Pass 1: Wide ambient glow --
                    ctx.saveGState()
                    ctx.setBlendMode(.plusLighter)
                    ctx.setShadow(offset: .zero, blur: outerBlur, color: glowColor.withAlphaComponent(0.45).cgColor)
                    ctx.setStrokeColor(UIColor.clear.cgColor)
                    ctx.setLineWidth(w)
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    ctx.addPath(bezier.cgPath)
                    ctx.strokePath()
                    ctx.restoreGState()

                    // -- Pass 2: Medium glow --
                    ctx.saveGState()
                    ctx.setBlendMode(.plusLighter)
                    ctx.setShadow(offset: .zero, blur: midBlur, color: glowColor.withAlphaComponent(0.65).cgColor)
                    ctx.setStrokeColor(UIColor.clear.cgColor)
                    ctx.setLineWidth(w)
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    ctx.addPath(bezier.cgPath)
                    ctx.strokePath()
                    ctx.restoreGState()

                    // -- Pass 3: White core with colored shadow --
                    ctx.saveGState()
                    ctx.setBlendMode(.normal)
                    ctx.setShadow(offset: .zero, blur: coreBlur, color: glowColor.cgColor)
                    ctx.setStrokeColor(UIColor.white.cgColor)
                    ctx.setLineWidth(w)
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    ctx.addPath(bezier.cgPath)
                    ctx.strokePath()
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
