import SwiftUI
import UIKit

extension StoryEditingView {

    struct StoryTextStylePreset: Equatable {
        var usesAllCaps: Bool = false
        var letterSpacing: CGFloat = 0
        var defaultColor: Color = .white
        var defaultBackgroundFill: TextBackgroundFill = .none
        var defaultEffect: TextEffect = .none
        var defaultStroke: TextStroke = .none
        var defaultBackgroundUIColor: UIColor? = nil
        var fontSizeOffset: CGFloat = 0
    }

    enum TextStyle: String, CaseIterable {
        case modern
        case classic
        case poster
        case editorial
        case rounded
        case signature
        case marker
        case typewriter
        case handwritten
        case bold
        case neon
        case chalk
        case squeeze
        case elegant
        case deco
        case meme

        var displayName: String {
            switch self {
            case .modern: return "Modern"
            case .classic: return "Classic"
            case .poster: return "Poster"
            case .editorial: return "Editor"
            case .rounded: return "Bubble"
            case .signature: return "Signature"
            case .marker: return "Marker"
            case .typewriter: return "Mono"
            case .handwritten: return "Journal"
            case .bold: return "Strong"
            case .neon: return "Neon"
            case .chalk: return "Chalk"
            case .squeeze: return "Squeeze"
            case .elegant: return "Elegant"
            case .deco: return "Deco"
            case .meme: return "Meme"
            }
        }

        /// Solo tipografía (Aa). Neon/Marker/Pixel van en la toolbar de efectos visuales.
        static var fontPickerStyles: [TextStyle] {
            [
                .modern, .classic, .editorial, .rounded, .signature,
                .typewriter, .handwritten, .bold, .poster, .meme,
                .squeeze, .elegant, .deco
            ]
        }

        var preset: StoryTextStylePreset {
            switch self {
            case .modern:
                return StoryTextStylePreset(usesAllCaps: true, letterSpacing: 1.2, defaultColor: .white)
            case .classic:
                return StoryTextStylePreset(defaultColor: .white)
            case .poster:
                return StoryTextStylePreset(defaultColor: .white, fontSizeOffset: 4)
            case .editorial:
                return StoryTextStylePreset(letterSpacing: 0.8, defaultColor: .white, fontSizeOffset: 1)
            case .rounded:
                return StoryTextStylePreset(defaultColor: .white)
            case .signature:
                return StoryTextStylePreset(defaultColor: .white, fontSizeOffset: 4)
            case .marker:
                return StoryTextStylePreset(defaultColor: .black, defaultEffect: .marker)
            case .typewriter:
                return StoryTextStylePreset(
                    defaultColor: .white,
                    defaultBackgroundFill: .black,
                    defaultBackgroundUIColor: UIColor.gray.withAlphaComponent(0.55)
                )
            case .handwritten:
                return StoryTextStylePreset(defaultColor: .white, fontSizeOffset: 2)
            case .bold:
                return StoryTextStylePreset(
                    defaultColor: .white,
                    defaultBackgroundFill: .black,
                    defaultBackgroundUIColor: UIColor.black.withAlphaComponent(0.6)
                )
            case .neon:
                return StoryTextStylePreset(defaultColor: Color(hex: "FF2D55"), defaultEffect: .neon, fontSizeOffset: 2)
            case .chalk:
                return StoryTextStylePreset(defaultColor: .white, defaultEffect: .chalk)
            case .squeeze:
                return StoryTextStylePreset(defaultColor: .white, fontSizeOffset: 2)
            case .elegant:
                return StoryTextStylePreset(defaultColor: .white, fontSizeOffset: 2)
            case .deco:
                return StoryTextStylePreset(letterSpacing: 2.0, defaultColor: .white)
            case .meme:
                return StoryTextStylePreset(defaultColor: .white, defaultStroke: .thick, fontSizeOffset: 3)
            }
        }

        func displayText(_ raw: String) -> String {
            preset.usesAllCaps ? raw.uppercased() : raw
        }

        func applyPreset(
            textColor: inout Color,
            textBackgroundFill: inout TextBackgroundFill,
            selectedEffect: inout TextEffect,
            textStroke: inout TextStroke
        ) {
            let p = preset
            textColor = p.defaultColor
            textBackgroundFill = p.defaultBackgroundFill
            selectedEffect = p.defaultEffect
            textStroke = p.defaultStroke
        }

        func font(size: CGFloat) -> Font {
            Font(uiFont(size: size))
        }

        func uiFont(size: CGFloat) -> UIFont {
            let resolved = size + preset.fontSizeOffset
            if let bundled = bundledFont(size: resolved) {
                return bundled
            }
            return systemFallback(size: resolved)
        }

        private func bundledFont(size: CGFloat) -> UIFont? {
            switch self {
            case .modern: return StoryFontRegistry.uiFont(fileName: "BebasNeue-Regular", size: size)
            case .classic: return StoryFontRegistry.uiFont(fileName: "Lora-Regular", size: size)
            case .poster: return StoryFontRegistry.uiFont(fileName: "PlayfairDisplay-Bold", size: size)
            case .editorial: return StoryFontRegistry.uiFont(fileName: "IBMPlexSerif-Regular", size: size)
            case .rounded: return StoryFontRegistry.uiFont(fileName: "VarelaRound-Regular", size: size)
            case .signature: return StoryFontRegistry.uiFont(fileName: "DancingScript-Bold", size: size)
            case .marker: return StoryFontRegistry.uiFont(fileName: "Caveat-Bold", size: size)
            case .typewriter: return UIFont.monospacedSystemFont(ofSize: max(12, size - 2), weight: .regular)
            case .handwritten: return StoryFontRegistry.uiFont(fileName: "Caveat-Bold", size: size)
            case .bold: return StoryFontRegistry.uiFont(fileName: "Anton-Regular", size: size)
            case .neon: return StoryFontRegistry.uiFont(fileName: "Pacifico-Regular", size: size)
            case .chalk: return UIFont(name: "ChalkboardSE-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
            case .squeeze: return StoryFontRegistry.uiFont(fileName: "BarlowCondensed-Bold", size: size)
            case .elegant: return StoryFontRegistry.uiFont(fileName: "CormorantGaramond-Italic", size: size)
            case .deco: return StoryFontRegistry.uiFont(fileName: "PoiretOne-Regular", size: size)
            case .meme: return StoryFontRegistry.uiFont(fileName: "Bangers-Regular", size: size)
            }
        }

        private func systemFallback(size: CGFloat) -> UIFont {
            switch self {
            case .modern: return .systemFont(ofSize: size, weight: .medium)
            case .classic: return UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
            case .poster: return .boldSystemFont(ofSize: size)
            case .editorial: return UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
            case .rounded: return .systemFont(ofSize: size, weight: .semibold)
            case .signature: return .italicSystemFont(ofSize: size)
            case .marker: return .systemFont(ofSize: size, weight: .bold)
            case .typewriter: return .monospacedSystemFont(ofSize: size, weight: .regular)
            case .handwritten: return .systemFont(ofSize: size, weight: .semibold)
            case .bold: return .systemFont(ofSize: size, weight: .heavy)
            case .neon: return .systemFont(ofSize: size, weight: .black)
            case .chalk: return .systemFont(ofSize: size, weight: .bold)
            case .squeeze: return .boldSystemFont(ofSize: size)
            case .elegant: return .italicSystemFont(ofSize: size)
            case .deco: return .systemFont(ofSize: size, weight: .light)
            case .meme: return .boldSystemFont(ofSize: size)
            }
        }

        var backgroundColor: Color {
            if let ui = preset.defaultBackgroundUIColor {
                return Color(ui)
            }
            switch self {
            case .modern: return Color.black.opacity(0.6)
            case .rounded: return Color.black.opacity(0.22)
            case .marker: return Color.yellow.opacity(0.18)
            case .neon: return Color.purple.opacity(0.8)
            case .typewriter: return Color.gray.opacity(0.55)
            case .chalk: return Color.black.opacity(0.18)
            default: return .clear
            }
        }
    }

    enum TextBackgroundFill: String, CaseIterable {
        case none
        case black
        case white
    }

    enum TextStroke: String, CaseIterable {
        case none
        case thin
        case thick

        var strokeWidth: CGFloat {
            switch self {
            case .none: return 0
            case .thin: return -2.0
            case .thick: return -4.0
            }
        }

        func cycled() -> TextStroke {
            switch self {
            case .none: return .thin
            case .thin: return .thick
            case .thick: return .none
            }
        }
    }

    enum TextEffect: String, CaseIterable {
        case none
        case sparkle
        case neon
        case glow
        case marker
        case chalk
        case pixel
        case shimmer

        var displayName: String {
            switch self {
            case .none: return "None"
            case .sparkle: return "Sparkle"
            case .neon: return "Neon"
            case .glow: return "Glow"
            case .marker: return "Marker"
            case .chalk: return "Chalk"
            case .pixel: return "Pixel"
            case .shimmer: return "Shimmer"
            }
        }

        /// Decodifica valores legacy de Firestore (`shimmer` → destello visual).
        init?(storedRawValue: String) {
            let normalized: String
            switch storedRawValue {
            case "shimmer": normalized = TextEffect.sparkle.rawValue
            default: normalized = storedRawValue
            }
            self.init(rawValue: normalized)
        }

        static var toolbarEffects: [TextEffect] {
            [.none, .sparkle, .neon, .glow, .marker, .chalk, .pixel]
        }

        func cycled() -> TextEffect {
            let all = Self.toolbarEffects
            guard let idx = all.firstIndex(of: self) else { return .none }
            return all[(idx + 1) % all.count]
        }

        var backgroundColor: Color? {
            switch self {
            case .marker: return Color.yellow.opacity(0.28)
            default: return nil
            }
        }

        var uiBackgroundColor: UIColor? {
            switch self {
            case .marker: return UIColor.systemYellow.withAlphaComponent(0.28)
            default: return nil
            }
        }

        func shadow(for textColor: Color) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)? {
            switch self {
            case .glow, .shimmer, .sparkle, .neon:
                return (textColor.opacity(0.92), 12, 0, 0)
            case .chalk, .pixel:
                return (Color.black.opacity(0.62), 1.0, 1.0, 1.0)
            case .none, .marker:
                return nil
            }
        }

        func nsShadow(for textColor: UIColor) -> NSShadow? {
            let shadow = NSShadow()
            switch self {
            case .glow, .shimmer, .sparkle, .neon:
                shadow.shadowColor = textColor.withAlphaComponent(0.92)
                shadow.shadowBlurRadius = 12
                shadow.shadowOffset = .zero
                return shadow
            case .chalk, .pixel:
                shadow.shadowColor = UIColor.black.withAlphaComponent(0.62)
                shadow.shadowBlurRadius = 1
                shadow.shadowOffset = CGSize(width: 1, height: 1)
                return shadow
            case .none, .marker:
                return nil
            }
        }
    }

    enum TextMotion: String, CaseIterable {
        case none
        case typewriter
        case pop
        case bounce
        case wave
        case reveal

        var displayName: String {
            switch self {
            case .none: return "None"
            case .typewriter: return "Type"
            case .pop: return "Pop"
            case .bounce: return "Jump"
            case .wave: return "Wave"
            case .reveal: return "Reveal"
            }
        }

        /// Barra Moments: máquina de escribir, pop y salto (+ extras en `toolbarMotions`).
        static var toolbarMotions: [TextMotion] {
            [.none, .typewriter, .pop, .bounce, .wave, .reveal]
        }

        static var momentsToolbarMotions: [TextMotion] {
            [.none, .typewriter, .pop, .bounce]
        }

        /// Legacy Firestore / decode mapping.
        init?(legacyRawValue: String) {
            let mapped: String
            switch legacyRawValue {
            case "jump": mapped = TextMotion.bounce.rawValue
            case "shimmer": mapped = TextMotion.typewriter.rawValue
            default: mapped = legacyRawValue
            }
            self.init(rawValue: mapped)
        }

        func cycled() -> TextMotion {
            let all = Self.toolbarMotions
            guard let idx = all.firstIndex(of: self) else { return .none }
            return all[(idx + 1) % all.count]
        }
    }

    typealias TextAnimation = TextMotion

    enum ActiveEditorMode {
        case idle
        case text
        case drawing
        case filters
    }
}
