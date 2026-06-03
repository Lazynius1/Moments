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

/// Metadata for live story text overlays (rendered in the viewer, not baked into media).
struct StoryTextOverlayMetadata: Codable, Equatable {
    var normalizedPosition: CGPoint
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

    static func build(
        text: String,
        editorPosition: CGPoint,
        contentRect: CGRect,
        style: StoryEditingView.TextStyle,
        textColor: Color,
        fontSize: CGFloat,
        alignment: TextAlignment,
        backgroundFill: StoryEditingView.TextBackgroundFill,
        stroke: StoryEditingView.TextStroke,
        visualEffect: StoryEditingView.TextEffect,
        motion: StoryEditingView.TextMotion,
        forcesAllCaps: Bool
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
            normalizedPosition: norm,
            styleRaw: style.rawValue,
            colorHex: textColor.toHex(),
            fontSize: Double(fontSize),
            alignmentRaw: Self.encodeAlignment(alignment),
            backgroundFillRaw: backgroundFill.rawValue,
            strokeRaw: stroke.rawValue,
            visualEffectRaw: visualEffect.rawValue,
            motionRaw: Self.sanitizeMotionRaw(motion.rawValue),
            forcesAllCaps: forcesAllCaps,
            isLiveOverlay: true
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

    func renderConfiguration(text: String) -> StoryTextRenderConfiguration? {
        guard let style = StoryEditingView.TextStyle(rawValue: styleRaw) else { return nil }
        let background = StoryEditingView.TextBackgroundFill(rawValue: backgroundFillRaw) ?? .none
        let stroke = StoryEditingView.TextStroke(rawValue: strokeRaw) ?? .none

        let effect = StoryEditingView.TextEffect(storedRawValue: visualEffectRaw) ?? .none

        return StoryTextRenderConfiguration(
            text: text,
            style: style,
            visualEffect: effect,
            textColor: Color(hex: colorHex),
            textAlignment: Self.decodeAlignment(alignmentRaw),
            textBackgroundFill: background,
            fontSize: CGFloat(fontSize),
            textStroke: stroke,
            forcesAllCaps: forcesAllCaps
        )
    }

    func scaledRenderConfiguration(text: String, containerWidth: CGFloat) -> StoryTextRenderConfiguration? {
        guard var config = renderConfiguration(text: text) else { return nil }
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
}

extension Story {
    var usesLiveTextOverlay: Bool {
        guard let text, !text.isEmpty else { return false }
        if textOverlayLive == true { return true }
        return textColorHex != nil || textMotion != nil || textVisualEffect != nil
    }

    var resolvedTextOverlayMetadata: StoryTextOverlayMetadata? {
        guard usesLiveTextOverlay else { return nil }
        guard let text, !text.isEmpty else { return nil }

        let normX = textPositionNormX ?? inferredNormalizedX
        let normY = textPositionNormY ?? inferredNormalizedY
        guard let normX, let normY else { return nil }

        return StoryTextOverlayMetadata(
            normalizedPosition: CGPoint(x: normX, y: normY),
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
