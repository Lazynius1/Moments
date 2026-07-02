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
        case clean
        case grotesk
        case oswald
        case spartan
        case poster
        case editorial
        case slab
        case rounded
        case signature
        case casual
        case fancy
        case marker
        case typewriter
        case handwritten
        case indie
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
            case .clean: return "Clean"
            case .grotesk: return "Grotesk"
            case .oswald: return "Condensed"
            case .spartan: return "Geo"
            case .poster: return "Poster"
            case .editorial: return "Editor"
            case .slab: return "Slab"
            case .rounded: return "Bubble"
            case .signature: return "Signature"
            case .casual: return "Script"
            case .fancy: return "Fancy"
            case .marker: return "Marker"
            case .typewriter: return "Mono"
            case .handwritten: return "Journal"
            case .indie: return "Indie"
            case .bold: return "Strong"
            case .neon: return "Neon"
            case .chalk: return "Chalk"
            case .squeeze: return "Squeeze"
            case .elegant: return "Elegant"
            case .deco: return "Deco"
            case .meme: return "Meme"
            }
        }

        /// Tipografías del carrusel Aa.
        static var fontPickerStyles: [TextStyle] {
            [
                .modern, .classic, .clean, .grotesk, .bold, .oswald, .spartan, .squeeze,
                .rounded, .poster, .editorial, .slab, .elegant, .fancy, .deco,
                .signature, .casual, .indie, .handwritten, .marker,
                .typewriter, .meme, .neon, .chalk
            ]
        }

        var preset: StoryTextStylePreset {
            switch self {
            case .modern:
                return StoryTextStylePreset(usesAllCaps: true, letterSpacing: 1.2, defaultColor: .white)
            case .classic:
                return StoryTextStylePreset(defaultColor: .white)
            case .clean:
                return StoryTextStylePreset(defaultColor: .white)
            case .grotesk:
                return StoryTextStylePreset(letterSpacing: 0.4, defaultColor: .white, fontSizeOffset: 1)
            case .oswald:
                return StoryTextStylePreset(usesAllCaps: true, letterSpacing: 0.6, defaultColor: .white, fontSizeOffset: 2)
            case .spartan:
                return StoryTextStylePreset(letterSpacing: 0.5, defaultColor: .white, fontSizeOffset: 1)
            case .poster:
                return StoryTextStylePreset(defaultColor: .white, fontSizeOffset: 4)
            case .editorial:
                return StoryTextStylePreset(letterSpacing: 0.8, defaultColor: .white, fontSizeOffset: 1)
            case .slab:
                return StoryTextStylePreset(letterSpacing: 0.3, defaultColor: .white, fontSizeOffset: 1)
            case .rounded:
                return StoryTextStylePreset(defaultColor: .white)
            case .signature:
                return StoryTextStylePreset(defaultColor: .white, fontSizeOffset: 4)
            case .casual:
                return StoryTextStylePreset(defaultColor: .white, fontSizeOffset: 3)
            case .fancy:
                return StoryTextStylePreset(defaultColor: .white, fontSizeOffset: 6)
            case .marker:
                return StoryTextStylePreset(defaultColor: .black, defaultEffect: .marker)
            case .typewriter:
                return StoryTextStylePreset(
                    defaultColor: .white,
                    defaultBackgroundFill: .solid,
                    defaultBackgroundUIColor: UIColor.gray.withAlphaComponent(0.55)
                )
            case .handwritten:
                return StoryTextStylePreset(defaultColor: .white, fontSizeOffset: 2)
            case .indie:
                return StoryTextStylePreset(defaultColor: .white, fontSizeOffset: 2)
            case .bold:
                return StoryTextStylePreset(
                    defaultColor: .white,
                    defaultBackgroundFill: .solid,
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
            case .clean: return nil
            case .grotesk: return StoryFontRegistry.uiFont(fileName: "Montserrat-Black", size: size)
            case .oswald: return StoryFontRegistry.uiFont(fileName: "Oswald-Bold", size: size)
            case .spartan: return StoryFontRegistry.uiFont(fileName: "LeagueSpartan-Bold", size: size)
            case .poster: return StoryFontRegistry.uiFont(fileName: "PlayfairDisplay-Bold", size: size)
            case .editorial: return StoryFontRegistry.uiFont(fileName: "IBMPlexSerif-Regular", size: size)
            case .slab: return StoryFontRegistry.uiFont(fileName: "RobotoSlab-Bold", size: size)
            case .rounded: return StoryFontRegistry.uiFont(fileName: "VarelaRound-Regular", size: size)
            case .signature: return StoryFontRegistry.uiFont(fileName: "DancingScript-Bold", size: size)
            case .casual: return StoryFontRegistry.uiFont(fileName: "Satisfy-Regular", size: size)
            case .fancy: return StoryFontRegistry.uiFont(fileName: "GreatVibes-Regular", size: size)
            case .marker: return StoryFontRegistry.uiFont(fileName: "PermanentMarker-Regular", size: size)
            case .typewriter: return UIFont.monospacedSystemFont(ofSize: max(12, size - 2), weight: .regular)
            case .handwritten: return StoryFontRegistry.uiFont(fileName: "Caveat-Bold", size: size)
            case .indie: return StoryFontRegistry.uiFont(fileName: "IndieFlower-Regular", size: size)
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
            case .clean:
                if let rounded = UIFont.systemFont(ofSize: size, weight: .semibold).fontDescriptor.withDesign(.rounded) {
                    return UIFont(descriptor: rounded, size: size)
                }
                return .systemFont(ofSize: size, weight: .semibold)
            case .grotesk: return .systemFont(ofSize: size, weight: .black)
            case .oswald: return .boldSystemFont(ofSize: size)
            case .spartan: return .systemFont(ofSize: size, weight: .heavy)
            case .poster: return .boldSystemFont(ofSize: size)
            case .editorial: return UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
            case .slab: return UIFont(name: "Georgia-Bold", size: size) ?? .boldSystemFont(ofSize: size)
            case .rounded: return .systemFont(ofSize: size, weight: .semibold)
            case .signature: return .italicSystemFont(ofSize: size)
            case .casual: return .italicSystemFont(ofSize: size)
            case .fancy: return .italicSystemFont(ofSize: size)
            case .marker: return .systemFont(ofSize: size, weight: .bold)
            case .typewriter: return .monospacedSystemFont(ofSize: size, weight: .regular)
            case .handwritten: return .systemFont(ofSize: size, weight: .semibold)
            case .indie: return .systemFont(ofSize: size, weight: .medium)
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
            case .clean: return Color.black.opacity(0.45)
            case .rounded: return Color.black.opacity(0.22)
            case .marker: return Color.yellow.opacity(0.18)
            case .neon: return Color.purple.opacity(0.8)
            case .typewriter: return Color.gray.opacity(0.55)
            case .chalk: return Color.black.opacity(0.18)
            case .grotesk, .bold: return Color.black.opacity(0.5)
            default: return .clear
            }
        }
    }

    enum TextBackgroundFill: String, CaseIterable {
        case none
        case solid
        case inverted
        case semiTransparent
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
        case sticker
        case outline
        case gradient
        case sparkle
        case neon
        case glow
        case glass
        case holographic
        case tape
        case pulse
        case textShimmer
        case marker
        case chalk
        case pixel
        case shimmer

        var displayName: String {
            momentsToolbarLabel
        }

        /// Decodifica valores legacy de Firestore.
        init?(storedRawValue: String) {
            let normalized: String
            switch storedRawValue {
            case "shimmer": normalized = TextEffect.textShimmer.rawValue
            default: normalized = storedRawValue
            }
            self.init(rawValue: normalized)
        }

        static var toolbarEffects: [TextEffect] {
            momentsVisualToolbar
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
            case .chalk, .pixel:
                return (Color.black.opacity(0.62), 1.0, 1.0, 1.0)
            case .none, .marker, .glow, .neon, .sparkle, .shimmer, .textShimmer,
                 .sticker, .outline, .gradient, .glass, .holographic, .tape, .pulse:
                return nil
            }
        }

        func nsShadow(for textColor: UIColor) -> NSShadow? {
            let shadow = NSShadow()
            switch self {
            case .chalk, .pixel:
                shadow.shadowColor = UIColor.black.withAlphaComponent(0.62)
                shadow.shadowBlurRadius = 1
                shadow.shadowOffset = CGSize(width: 1, height: 1)
                return shadow
            case .none, .marker, .glow, .neon, .sparkle, .shimmer, .textShimmer,
                 .sticker, .outline, .gradient, .glass, .holographic, .tape, .pulse:
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
