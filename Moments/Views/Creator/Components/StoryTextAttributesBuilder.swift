import SwiftUI
import UIKit

struct StoryTextRenderConfiguration: Equatable {
    var text: String
    var style: StoryEditingView.TextStyle
    var visualEffect: StoryEditingView.TextEffect
    var textColor: Color
    var textAlignment: TextAlignment
    var textBackgroundFill: StoryEditingView.TextBackgroundFill
    var fontSize: CGFloat
    var textStroke: StoryEditingView.TextStroke
    var forcesAllCaps: Bool = false
    var appliesDisplayTransform: Bool = true

    var effect: StoryEditingView.TextEffect { visualEffect }

    var visualTreatment: StoryTextVisualTreatment {
        let fromEffect = visualEffect.visualTreatment
        if fromEffect != .plain { return fromEffect }
        return style.styleAccentTreatment
    }

    var displayText: String {
        guard appliesDisplayTransform else { return text }
        if forcesAllCaps || style.preset.usesAllCaps {
            return text.uppercased()
        }
        return text
    }

    var uiTextAlignment: NSTextAlignment {
        switch textAlignment {
        case .leading: return .left
        case .trailing: return .right
        default: return .center
        }
    }
}

enum StoryTextAttributesBuilder {
    static func contrastUIColor(for color: Color) -> UIColor {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.68 ? .black : .white
    }

    static func backgroundUIColor(
        fill: StoryEditingView.TextBackgroundFill,
        selectedColor: Color,
        effect: StoryEditingView.TextEffect,
        style: StoryEditingView.TextStyle
    ) -> UIColor? {
        switch fill {
        case .none:
            if let preset = style.preset.defaultBackgroundUIColor {
                return preset
            }
            if effect.visualTreatment == .markerHighlight {
                return nil
            }
            return effect.uiBackgroundColor
        case .solid:
            return UIColor(selectedColor)
        case .semiTransparent:
            return UIColor(selectedColor).withAlphaComponent(0.70)
        case .inverted:
            return contrastUIColor(for: selectedColor) == .black ? .white : .black
        }
    }

    static func coreAttributes(for config: StoryTextRenderConfiguration) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        switch config.textAlignment {
        case .leading: paragraphStyle.alignment = .left
        case .trailing: paragraphStyle.alignment = .right
        default: paragraphStyle.alignment = .center
        }
        paragraphStyle.lineBreakMode = .byWordWrapping

        let selectedColor = config.textColor
        var textBackgroundColor: UIColor? = nil
        var textForegroundColor: UIColor = UIColor(selectedColor)

        if config.visualTreatment == .plain || config.visualTreatment == .boxedCaption {
            textBackgroundColor = backgroundUIColor(
                fill: config.textBackgroundFill,
                selectedColor: selectedColor,
                effect: config.effect,
                style: config.style
            )
        }

        switch config.textBackgroundFill {
        case .none:
            break
        case .solid, .semiTransparent:
            textForegroundColor = contrastUIColor(for: selectedColor)
        case .inverted:
            textForegroundColor = UIColor(selectedColor)
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: config.style.uiFont(size: config.fontSize),
            .foregroundColor: textForegroundColor,
            .paragraphStyle: paragraphStyle
        ]

        if let bg = textBackgroundColor, config.visualTreatment != .markerHighlight {
            attributes[.backgroundColor] = bg
        }

        if let shadow = config.effect.nsShadow(for: textForegroundColor) {
            attributes[.shadow] = shadow
        }

        if config.textStroke != .none, config.visualTreatment != .memeStrong {
            attributes[.strokeColor] = textForegroundColor
            attributes[.strokeWidth] = config.textStroke.strokeWidth
        }

        let tracking = config.style.preset.letterSpacing
        if tracking != 0 {
            attributes[.kern] = tracking
        }

        return attributes
    }

    static func typingAttributes(for config: StoryTextRenderConfiguration) -> [NSAttributedString.Key: Any] {
        coreAttributes(for: config)
    }

    static func attributedString(for config: StoryTextRenderConfiguration) -> NSAttributedString {
        NSAttributedString(
            string: config.displayText,
            attributes: typingAttributes(for: config)
        )
    }

    static func measure(attributed: NSAttributedString, maxWidth: CGFloat) -> CGSize {
        attributed.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).integral.size
    }

    static func measuredSize(
        for config: StoryTextRenderConfiguration,
        maxWidth: CGFloat
    ) -> CGSize {
        measure(attributed: attributedString(for: config), maxWidth: maxWidth)
    }

    /// Tamaño del overlay UIKit (incluye margen para glow, placa marker, etc.).
    static func overlayContentSize(
        for config: StoryTextRenderConfiguration,
        maxWidth: CGFloat
    ) -> CGSize {
        let measured = measuredSize(for: config, maxWidth: maxWidth)
        let glowPad: CGFloat
        switch config.visualTreatment {
        case .neonGlow, .softGlow, .sparklePulse:
            glowPad = 28
        case .markerHighlight, .boxedCaption:
            glowPad = 32
        case .memeStrong:
            glowPad = 16
        default:
            glowPad = 12
        }
        return CGSize(
            width: min(maxWidth, measured.width + glowPad),
            height: measured.height + glowPad
        )
    }
}
