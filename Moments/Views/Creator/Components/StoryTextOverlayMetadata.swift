import SwiftUI
import UIKit

enum StoryTextCanvasPlacement {
    static func defaultPosition(in canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: canvasSize.width / 2,
            y: max(canvasSize.height * 0.42, 80)
        )
    }

    static func needsSeed(position: CGPoint, canvasSize: CGSize) -> Bool {
        guard canvasSize.width > 1, canvasSize.height > 1 else { return false }
        return position == .zero
            || position.x < 12
            || position.y < 12
            || position.x > canvasSize.width - 12
            || position.y > canvasSize.height - 12
    }
}

struct StoryTextOverlayDraft: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var text: String = ""
    var position: CGPoint = .zero
    var style: StoryEditingView.TextStyle = .modern
    var visualEffect: StoryEditingView.TextEffect = .none
    var textColor: Color = .white
    var textAlignment: TextAlignment = .center
    var textBackgroundFill: StoryEditingView.TextBackgroundFill = .none
    var fontSize: CGFloat = 30
    var textStroke: StoryEditingView.TextStroke = .none
    var textMotion: StoryEditingView.TextMotion = .none
    var forcesAllCaps: Bool = false
    var layerOrder: Int = 0
    var gradientStopHexes: [String] = []
    var gradientAngle: Int = 0

    var gradientColors: [Color] {
        StoryTextGradientSettings.decodeStops(gradientStopHexes, fallback: textColor)
    }

    func metadata(in contentRect: CGRect) -> StoryTextOverlayMetadata? {
        StoryTextOverlayMetadata.build(
            id: id,
            text: text,
            editorPosition: position,
            contentRect: contentRect,
            layerOrder: layerOrder,
            style: style,
            textColor: textColor,
            fontSize: fontSize,
            alignment: textAlignment,
            backgroundFill: textBackgroundFill,
            stroke: textStroke,
            visualEffect: visualEffect,
            motion: textMotion,
            forcesAllCaps: forcesAllCaps,
            gradientStopHexes: gradientStopHexes,
            gradientAngle: gradientAngle
        )
    }

    static func from(metadata: StoryTextOverlayMetadata, canvasSize: CGSize) -> StoryTextOverlayDraft {
        let color = Color(hex: metadata.colorHex)
        return StoryTextOverlayDraft(
            id: metadata.id,
            text: metadata.text,
            position: metadata.displayPosition(in: canvasSize),
            style: StoryEditingView.TextStyle(rawValue: metadata.styleRaw) ?? .modern,
            visualEffect: StoryEditingView.TextEffect(storedRawValue: metadata.visualEffectRaw) ?? .none,
            textColor: color,
            textAlignment: StoryTextOverlayMetadata.decodeAlignment(metadata.alignmentRaw),
            textBackgroundFill: StoryEditingView.TextBackgroundFill(rawValue: metadata.backgroundFillRaw) ?? .none,
            fontSize: CGFloat(metadata.fontSize),
            textStroke: StoryEditingView.TextStroke(rawValue: metadata.strokeRaw) ?? .none,
            textMotion: metadata.motion,
            forcesAllCaps: metadata.forcesAllCaps,
            layerOrder: metadata.layerOrder,
            gradientStopHexes: metadata.gradientStopHexes
                ?? StoryTextGradientSettings.encodeStops(StoryTextGradientSettings.defaultStops(anchoredTo: color)),
            gradientAngle: metadata.gradientAngle ?? 0
        )
    }
}

/// Metadata for live story text overlays (rendered in the viewer, not baked into media).
struct StoryTextOverlayMetadata: Codable, Equatable {
    var id: String
    var text: String
    var normalizedPosition: CGPoint
    var layerOrder: Int
    var styleRaw: String
    var colorHex: String
    var fontSize: Double
    var alignmentRaw: String
    var backgroundFillRaw: String
    var strokeRaw: String
    var visualEffectRaw: String
    var motionRaw: String
    var forcesAllCaps: Bool
    var isLiveOverlay: Bool = true
    var gradientStopHexes: [String]?
    var gradientAngle: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case normalizedPosition
        case layerOrder
        case styleRaw
        case colorHex
        case fontSize
        case alignmentRaw
        case backgroundFillRaw
        case strokeRaw
        case visualEffectRaw
        case motionRaw
        case forcesAllCaps
        case isLiveOverlay
        case gradientStopHexes
        case gradientAngle
    }

    private enum PointCodingKeys: String, CodingKey {
        case x
        case y
    }

    init(
        id: String,
        text: String,
        normalizedPosition: CGPoint,
        layerOrder: Int,
        styleRaw: String,
        colorHex: String,
        fontSize: Double,
        alignmentRaw: String,
        backgroundFillRaw: String,
        strokeRaw: String,
        visualEffectRaw: String,
        motionRaw: String,
        forcesAllCaps: Bool,
        isLiveOverlay: Bool = true,
        gradientStopHexes: [String]? = nil,
        gradientAngle: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.normalizedPosition = normalizedPosition
        self.layerOrder = layerOrder
        self.styleRaw = styleRaw
        self.colorHex = colorHex
        self.fontSize = fontSize
        self.alignmentRaw = alignmentRaw
        self.backgroundFillRaw = backgroundFillRaw
        self.strokeRaw = strokeRaw
        self.visualEffectRaw = visualEffectRaw
        self.motionRaw = motionRaw
        self.forcesAllCaps = forcesAllCaps
        self.isLiveOverlay = isLiveOverlay
        self.gradientStopHexes = gradientStopHexes
        self.gradientAngle = gradientAngle
    }

    static func build(
        id: String = UUID().uuidString,
        text: String,
        editorPosition: CGPoint,
        contentRect: CGRect,
        layerOrder: Int,
        style: StoryEditingView.TextStyle,
        textColor: Color,
        fontSize: CGFloat,
        alignment: TextAlignment,
        backgroundFill: StoryEditingView.TextBackgroundFill,
        stroke: StoryEditingView.TextStroke,
        visualEffect: StoryEditingView.TextEffect,
        motion: StoryEditingView.TextMotion,
        forcesAllCaps: Bool,
        gradientStopHexes: [String] = [],
        gradientAngle: Int = 0
    ) -> StoryTextOverlayMetadata? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let safeWidth = max(contentRect.width, 1)
        let safeHeight = max(contentRect.height, 1)
        let norm = CGPoint(
            x: (editorPosition.x / safeWidth).clamped01,
            y: (editorPosition.y / safeHeight).clamped01
        )

        return StoryTextOverlayMetadata(
            id: id,
            text: trimmed,
            normalizedPosition: norm,
            layerOrder: layerOrder,
            styleRaw: style.rawValue,
            colorHex: textColor.toHex(),
            fontSize: Double(fontSize),
            alignmentRaw: Self.encodeAlignment(alignment),
            backgroundFillRaw: backgroundFill.rawValue,
            strokeRaw: stroke.rawValue,
            visualEffectRaw: visualEffect.rawValue,
            motionRaw: Self.sanitizeMotionRaw(motion.rawValue),
            forcesAllCaps: forcesAllCaps,
            isLiveOverlay: true,
            gradientStopHexes: visualEffect == .gradient && !gradientStopHexes.isEmpty ? gradientStopHexes : nil,
            gradientAngle: visualEffect == .gradient ? gradientAngle : nil
        )
    }

    private static func sanitizeMotionRaw(_ raw: String) -> String {
        switch raw {
        case "shimmer": return StoryEditingView.TextMotion.typewriter.rawValue
        case "jump": return StoryEditingView.TextMotion.bounce.rawValue
        default: return raw
        }
    }

    private static func encodeAlignment(_ alignment: TextAlignment) -> String {
        switch alignment {
        case .leading: return "leading"
        case .trailing: return "trailing"
        default: return "center"
        }
    }

    static func decodeAlignment(_ raw: String?) -> TextAlignment {
        switch raw {
        case "leading": return .leading
        case "trailing": return .trailing
        default: return .center
        }
    }

    func renderConfiguration() -> StoryTextRenderConfiguration? {
        guard let style = StoryEditingView.TextStyle(rawValue: styleRaw) else { return nil }
        let stroke = StoryEditingView.TextStroke(rawValue: strokeRaw) ?? .none
        let effect = StoryEditingView.TextEffect(storedRawValue: visualEffectRaw) ?? .none

        var background = StoryEditingView.TextBackgroundFill(rawValue: backgroundFillRaw) ?? .none
        var resolvedColor = Color(hex: colorHex)

        if backgroundFillRaw == "black" {
            background = .solid
            resolvedColor = .black
        } else if backgroundFillRaw == "white" {
            background = .solid
            resolvedColor = .white
        }

        return StoryTextRenderConfiguration(
            text: text,
            style: style,
            visualEffect: effect,
            textColor: resolvedColor,
            textAlignment: Self.decodeAlignment(alignmentRaw),
            textBackgroundFill: background,
            fontSize: CGFloat(fontSize),
            textStroke: stroke,
            forcesAllCaps: forcesAllCaps,
            gradientStops: StoryTextGradientSettings.decodeStops(gradientStopHexes, fallback: resolvedColor),
            gradientAngle: gradientAngle ?? 0
        )
    }

    func scaledRenderConfiguration(containerWidth: CGFloat) -> StoryTextRenderConfiguration? {
        guard var config = renderConfiguration() else { return nil }
        config.fontSize = scaledFontSize(for: containerWidth)
        return config
    }

    var motion: StoryEditingView.TextMotion {
        let raw = Self.sanitizeMotionRaw(motionRaw)
        return StoryEditingView.TextMotion(legacyRawValue: raw) ?? .none
    }

    func displayPosition(in containerSize: CGSize) -> CGPoint {
        CGPoint(
            x: normalizedPosition.x * max(containerSize.width, 1),
            y: normalizedPosition.y * max(containerSize.height, 1)
        )
    }

    func scaledFontSize(for containerWidth: CGFloat) -> CGFloat {
        let scaleFactor = max(containerWidth, 1) / 375.0
        return CGFloat(fontSize) * scaleFactor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        layerOrder = try container.decode(Int.self, forKey: .layerOrder)
        styleRaw = try container.decode(String.self, forKey: .styleRaw)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        fontSize = try container.decode(Double.self, forKey: .fontSize)
        alignmentRaw = try container.decode(String.self, forKey: .alignmentRaw)
        backgroundFillRaw = try container.decode(String.self, forKey: .backgroundFillRaw)
        strokeRaw = try container.decode(String.self, forKey: .strokeRaw)
        visualEffectRaw = try container.decode(String.self, forKey: .visualEffectRaw)
        motionRaw = try container.decode(String.self, forKey: .motionRaw)
        forcesAllCaps = try container.decode(Bool.self, forKey: .forcesAllCaps)
        isLiveOverlay = try container.decodeIfPresent(Bool.self, forKey: .isLiveOverlay) ?? true
        gradientStopHexes = try container.decodeIfPresent([String].self, forKey: .gradientStopHexes)
        gradientAngle = try container.decodeIfPresent(Int.self, forKey: .gradientAngle)

        if let point = try? container.decode(CGPoint.self, forKey: .normalizedPosition) {
            normalizedPosition = point
        } else {
            let pointContainer = try container.nestedContainer(keyedBy: PointCodingKeys.self, forKey: .normalizedPosition)
            let x = try pointContainer.decode(CGFloat.self, forKey: .x)
            let y = try pointContainer.decode(CGFloat.self, forKey: .y)
            normalizedPosition = CGPoint(x: x, y: y)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(layerOrder, forKey: .layerOrder)
        try container.encode(styleRaw, forKey: .styleRaw)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(alignmentRaw, forKey: .alignmentRaw)
        try container.encode(backgroundFillRaw, forKey: .backgroundFillRaw)
        try container.encode(strokeRaw, forKey: .strokeRaw)
        try container.encode(visualEffectRaw, forKey: .visualEffectRaw)
        try container.encode(motionRaw, forKey: .motionRaw)
        try container.encode(forcesAllCaps, forKey: .forcesAllCaps)
        try container.encode(isLiveOverlay, forKey: .isLiveOverlay)
        try container.encodeIfPresent(gradientStopHexes, forKey: .gradientStopHexes)
        try container.encodeIfPresent(gradientAngle, forKey: .gradientAngle)

        var pointContainer = container.nestedContainer(keyedBy: PointCodingKeys.self, forKey: .normalizedPosition)
        try pointContainer.encode(normalizedPosition.x, forKey: .x)
        try pointContainer.encode(normalizedPosition.y, forKey: .y)
    }
}

extension Story {
    var usesLiveTextOverlay: Bool {
        if let textOverlays, !textOverlays.isEmpty { return true }
        guard let text, !text.isEmpty else { return false }
        if textOverlayLive == true { return true }
        return textColorHex != nil || textMotion != nil || textVisualEffect != nil
    }

    var resolvedTextOverlays: [StoryTextOverlayMetadata] {
        if let textOverlays, !textOverlays.isEmpty {
            return textOverlays
                .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted { lhs, rhs in
                    if lhs.layerOrder == rhs.layerOrder {
                        return lhs.id < rhs.id
                    }
                    return lhs.layerOrder < rhs.layerOrder
                }
        }

        guard let text, !text.isEmpty else { return [] }

        let normX = textPositionNormX ?? inferredNormalizedX
        let normY = textPositionNormY ?? inferredNormalizedY
        guard let normX, let normY else { return [] }

        return [
            StoryTextOverlayMetadata(
                id: "legacy-text-overlay",
                text: text,
                normalizedPosition: CGPoint(x: normX, y: normY),
                layerOrder: textLayerOrder ?? 0,
                styleRaw: textStyle ?? StoryEditingView.TextStyle.modern.rawValue,
                colorHex: textColorHex ?? "FFFFFF",
                fontSize: textFontSize ?? 30,
                alignmentRaw: textAlignment ?? "center",
                backgroundFillRaw: textBackgroundFill ?? StoryEditingView.TextBackgroundFill.none.rawValue,
                strokeRaw: textStroke ?? StoryEditingView.TextStroke.none.rawValue,
                visualEffectRaw: textVisualEffect ?? StoryEditingView.TextEffect.none.rawValue,
                motionRaw: textMotion ?? StoryEditingView.TextMotion.none.rawValue,
                forcesAllCaps: forcesAllCaps ?? false,
                isLiveOverlay: true
            )
        ]
    }

    var resolvedTextOverlayMetadata: StoryTextOverlayMetadata? {
        resolvedTextOverlays.first
    }

    private var inferredNormalizedX: Double? {
        guard let textPosition else { return nil }
        let width = max(UIScreen.main.bounds.width, 1)
        return Double(textPosition.x / width).clamped01
    }

    private var inferredNormalizedY: Double? {
        guard let textPosition else { return nil }
        let height = max(UIScreen.main.bounds.height, 1)
        return Double(textPosition.y / height).clamped01
    }
}

private extension CGFloat {
    var clamped01: CGFloat {
        Swift.min(Swift.max(self, 0), 1)
    }
}

private extension Double {
    var clamped01: Double {
        Swift.min(Swift.max(self, 0), 1)
    }
}
