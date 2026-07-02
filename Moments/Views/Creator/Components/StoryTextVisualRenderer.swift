import SwiftUI
import UIKit

enum StoryTextVisualTreatment: String, Equatable {
    case plain
    case sparklePulse
    case neonGlow
    case softGlow
    case pulseHalo
    case markerHighlight
    case chalkDust
    case pixelBitmap
    case boxedCaption
    case memeStrong
    case outlinePop
    case stickerCutout
    case gradientFill
    case glassText
    case holographicFill
    case tapeLabel
    case textShimmer
    case echoStack
    case longShadow
    case glitchSplit
}

extension StoryEditingView.TextEffect {
    static var momentsVisualToolbar: [StoryEditingView.TextEffect] {
        [
            .none, .sticker, .outline, .gradient, .neon, .glitch, .echo, .depth,
            .glow, .glass, .sparkle, .pixel, .holographic, .tape, .pulse
        ]
    }

    var visualTreatment: StoryTextVisualTreatment {
        switch self {
        case .sparkle: return .sparklePulse
        case .neon: return .neonGlow
        case .glow: return .softGlow
        case .pulse: return .pulseHalo
        case .marker: return .markerHighlight
        case .chalk: return .chalkDust
        case .pixel: return .pixelBitmap
        case .outline: return .outlinePop
        case .sticker: return .stickerCutout
        case .gradient: return .gradientFill
        case .glass: return .glassText
        case .holographic: return .holographicFill
        case .tape: return .tapeLabel
        case .textShimmer, .shimmer: return .textShimmer
        case .echo: return .echoStack
        case .depth: return .longShadow
        case .glitch: return .glitchSplit
        case .none: return .plain
        }
    }

    var momentsToolbarLabel: String {
        switch self {
        case .none: return NSLocalizedString("storyTextEffect.none", comment: "No effect")
        case .sticker: return NSLocalizedString("storyTextEffect.sticker", comment: "Sticker")
        case .outline: return NSLocalizedString("storyTextEffect.outline", comment: "Outline")
        case .gradient: return NSLocalizedString("storyTextEffect.gradient", comment: "Gradient")
        case .neon: return NSLocalizedString("storyTextEffect.neon", comment: "Neon")
        case .glow: return NSLocalizedString("storyTextEffect.glow", comment: "Glow")
        case .glass: return NSLocalizedString("storyTextEffect.glass", comment: "Glass")
        case .sparkle: return NSLocalizedString("storyTextEffect.sparkle", comment: "Sparkle")
        case .pixel: return NSLocalizedString("storyTextEffect.pixel", comment: "Pixel")
        case .holographic: return NSLocalizedString("storyTextEffect.holographic", comment: "Holo")
        case .tape: return NSLocalizedString("storyTextEffect.tape", comment: "Tape")
        case .pulse: return NSLocalizedString("storyTextEffect.pulse", comment: "Pulse")
        case .marker: return NSLocalizedString("storyTextEffect.marker", comment: "Marker")
        case .chalk: return NSLocalizedString("storyTextEffect.chalk", comment: "Chalk")
        case .textShimmer, .shimmer: return NSLocalizedString("storyTextEffect.textShimmer", comment: "Shimmer")
        case .echo: return NSLocalizedString("storyTextEffect.echo", comment: "Echo")
        case .depth: return NSLocalizedString("storyTextEffect.depth", comment: "Depth")
        case .glitch: return NSLocalizedString("storyTextEffect.glitch", comment: "Glitch")
        }
    }

    var usesGradientEditor: Bool {
        self == .gradient
    }

    var opensColorContextOnSelect: Bool {
        usesGradientEditor
    }
}

extension StoryEditingView.TextStyle {
    /// Tipografía pura; el look visual vive en `TextEffect` (toolbar visual).
    var styleAccentTreatment: StoryTextVisualTreatment {
        switch self {
        case .typewriter, .bold: return .boxedCaption
        case .meme: return .memeStrong
        default: return .plain
        }
    }
}
