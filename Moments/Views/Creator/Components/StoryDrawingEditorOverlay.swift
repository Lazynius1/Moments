import PencilKit
import SwiftUI
import UIKit

private enum StoryDrawingBrush {
    case pen
    case arrow
    case glow
    case marker
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
        ZStack {
            if let baseDrawing {
                Image(uiImage: baseDrawing)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
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
                }
            )
            .ignoresSafeArea()

            if let liveGlowImage {
                Image(uiImage: liveGlowImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                    .allowsHitTesting(false)
            }

            VStack {
                HStack(spacing: 10) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(chromeIconColor)
                            .padding(12)
                            .liquidGlass(in: Circle())
                    }

                    Spacer(minLength: 6)

                    HStack(spacing: 12) {
                        brushButton(icon: "pencil", brushType: .pen)
                        brushButton(icon: "arrow.up.right", brushType: .arrow)
                        brushButton(icon: "highlighter", brushType: .marker)
                        brushButton(icon: "sparkles", brushType: .glow)
                        brushButton(icon: "eraser", brushType: .eraser)
                    }

                    Spacer(minLength: 6)

                    Button(action: {
                        exportToken += 1
                    }) {
                        Text("creator.done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(chromeIconColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .liquidGlass(in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 76)

                Spacer()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Eyedropper / Custom Color Picker
                        ZStack {
                            Circle()
                                .fill(Color(color))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                                )

                            Image(systemName: "eyedropper")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(color == .white ? .black : .white)

                            ColorPicker("", selection: Binding(
                                get: { Color(color) },
                                set: { newColor in
                                    let uiColor = UIColor(newColor)
                                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                                    // Force color into standard RGBA space so CoreGraphics (.cgColor) shadowing works.
                                    if uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
                                        color = UIColor(red: r, green: g, blue: b, alpha: a)
                                    } else {
                                        color = UIColor(cgColor: uiColor.cgColor)
                                    }
                                }
                            ), supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 40, height: 40)
                            .scaleEffect(2.2)
                            .contentShape(Rectangle())
                            .opacity(0.011)
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())

                        Divider()
                            .frame(height: 24)
                            .background(Color.white.opacity(0.3))
                            .padding(.horizontal, 2)

                        ForEach(drawingPalette, id: \.self) { paletteColor in
                            Button(action: { color = paletteColor }) {
                                Circle()
                                    .fill(Color(paletteColor))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(color == paletteColor ? 0.95 : 0.26), lineWidth: color == paletteColor ? 2.5 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 44)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .liquidGlass(in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 76)
            }

            HStack {
                Spacer()
                VStack(spacing: 10) {
                    sideToolButton(icon: "arrow.uturn.backward") {
                        undoToken += 1
                    }

                    sideToolButton(icon: "arrow.uturn.forward") {
                        redoToken += 1
                    }

                    StoryVerticalBrushSlider(
                        value: $brushWidth,
                        range: 2...26
                    )
                }
                .padding(.trailing, 16)
                .padding(.bottom, 116)
            }
            .padding(.top, 148)
        }
        .ignoresSafeArea()
    }

    private var drawingPalette: [UIColor] {
        [
            .white, .black, .darkGray, .lightGray,
            .systemRed, .systemOrange, .systemYellow, .systemGreen,
            .systemCyan, .systemBlue, .systemIndigo, .systemPurple, .systemPink, .brown
        ]
    }

    private func merge(base: UIImage, overlay: UIImage) -> UIImage {
        let size = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
            overlay.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    @ViewBuilder
    private func brushButton(icon: String, brushType: StoryDrawingBrush) -> some View {
        let isSelected = brush == brushType
        Button(action: { brush = brushType }) {
            Image(systemName: icon)
                .font(.system(size: isSelected ? 20 : 18, weight: .semibold))
                .foregroundColor(chromeIconColor.opacity(isSelected ? 1 : 0.58))
                .frame(width: 30, height: 30)
                .scaleEffect(isSelected ? 1.08 : 1)
                .shadow(color: .black.opacity(isSelected ? 0.18 : 0), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sideToolButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(chromeIconColor)
                .frame(width: 38, height: 38)
                .liquidGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

}

private struct StoryVerticalBrushSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    var body: some View {
        GeometryReader { proxy in
            let trackHeight = proxy.size.height
            let thumbSize: CGFloat = 34
            let normalized = normalizedValue
            let thumbTravel = max(0, trackHeight - thumbSize)
            let thumbY = (1 - normalized) * thumbTravel

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 6)
                    .frame(maxHeight: .infinity)

                Capsule()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 6, height: max(thumbSize * 0.7, trackHeight * normalized))
                    .frame(maxHeight: .infinity, alignment: .bottom)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .offset(y: thumbY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let clampedY = min(max(gesture.location.y, 0), trackHeight)
                        let normalized = 1 - (clampedY / max(trackHeight, 1))
                        value = range.lowerBound + ((range.upperBound - range.lowerBound) * normalized)
                    }
            )
        }
        .frame(width: 34, height: 208)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .liquidGlass(in: Capsule())
    }

    private var normalizedValue: CGFloat {
        let distance = range.upperBound - range.lowerBound
        guard distance > 0 else { return 0 }
        return min(max((value - range.lowerBound) / distance, 0), 1)
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
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInset = .zero
        canvas.contentSize = UIScreen.main.bounds.size
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.currentBrush = brush
        context.coordinator.currentColor = color
        context.coordinator.currentWidth = brushWidth
        uiView.tool = currentTool()

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

            // WYSIWYG glow preview (debounced).
            glowPreviewWorkItem?.cancel()
            let shouldRenderGlow = strokeMetadata.contains(where: { $0.brush == .glow })
            let drawingSnapshot = canvasView.drawing
            let boundsSnapshot = canvasView.bounds
            let metadataSnapshot = strokeMetadata

            let workItem = DispatchWorkItem { [onLiveGlowPreview] in
                guard shouldRenderGlow else {
                    onLiveGlowPreview(nil)
                    return
                }

                let preview = StoryDrawingCanvasView.renderBlurredGlowImage(
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

        let glowImage: UIImage? = hasGlowStrokes
            ? Self.renderBlurredGlowImage(from: drawing, bounds: bounds, strokeMetadata: strokeMetadata, scale: scale)
            : nil

        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image { ctx in
            // Glow image first (it includes its own white core)
            if let glowImage {
                glowImage.draw(in: CGRect(origin: .zero, size: bounds.size))
            }

            // Non-glow strokes on top
            baseImage.draw(in: CGRect(origin: .zero, size: bounds.size))

            for (index, stroke) in drawing.strokes.enumerated() {
                guard index < strokeMetadata.count else { continue }
                let metadata = strokeMetadata[index]
                guard metadata.brush == .arrow else { continue }
                drawArrowHead(for: stroke, metadata: metadata)
            }
        }
    }

    private static func renderBlurredGlowImage(
        from drawing: PKDrawing,
        bounds: CGRect,
        strokeMetadata: [StrokeMetadata],
        scale: CGFloat
    ) -> UIImage? {
        let glowStrokes = drawing.strokes.enumerated().compactMap { (index, stroke) -> (index: Int, stroke: PKStroke)? in
            guard index < strokeMetadata.count else { return nil }
            return strokeMetadata[index].brush == .glow ? (index: index, stroke: stroke) : nil
        }

        guard !glowStrokes.isEmpty else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = scale

        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        return renderer.image { rendererCtx in
            let ctx = rendererCtx.cgContext

            for glow in glowStrokes {
                let metadata = strokeMetadata[glow.index]
                let bezier = strokeToBezierPath(stroke: glow.stroke)
                guard !bezier.cgPath.isEmpty else { continue }

                let glowColor = metadata.color
                let w = metadata.width

                // Scale the glow extent with the brush size so fat strokes
                // get a proportionally bigger, more dramatic outer halo.
                let outerBlur = max(14, w * 3.0)   // wide ambient spill
                let midBlur   = max(6,  w * 1.2)   // medium intensity halo
                let coreBlur  = max(3,  w * 0.6)   // tight colored edge around white

                // -- Pass 1: Wide ambient glow (soft light spill) --
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

                // -- Pass 2: Medium glow (tighter, more intense) --
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

    private func drawArrowHead(for stroke: PKStroke, metadata: StrokeMetadata) {
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

        let arrowPath = UIBezierPath()
        arrowPath.move(to: left)
        arrowPath.addLine(to: endPoint)
        arrowPath.addLine(to: right)
        arrowPath.lineWidth = max(3, metadata.width * 0.9)
        arrowPath.lineCapStyle = .round
        arrowPath.lineJoinStyle = .round

        metadata.color.setStroke()
        arrowPath.stroke()
    }
}
