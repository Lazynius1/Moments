import SwiftUI
import UIKit

enum StoryTextVisualTreatment: String, Equatable {
    case plain
    case sparklePulse
    case neonGlow
    case softGlow
    case markerHighlight
    case chalkDust
    case pixelBitmap
    case boxedCaption
    case memeStrong
}

extension StoryEditingView.TextEffect {
    /// Toolbar visual (A con destello): sparkle, neon, brillo, pixel, marker, chalk.
    static var momentsVisualToolbar: [StoryEditingView.TextEffect] {
        [.none, .sparkle, .neon, .glow, .pixel, .marker, .chalk]
    }

    var visualTreatment: StoryTextVisualTreatment {
        switch self {
        case .sparkle, .shimmer: return .sparklePulse
        case .neon: return .neonGlow
        case .glow: return .softGlow
        case .marker: return .markerHighlight
        case .chalk: return .chalkDust
        case .pixel: return .pixelBitmap
        case .none: return .plain
        }
    }

    var momentsToolbarLabel: String {
        switch self {
        case .none: return "None"
        case .sparkle: return "Sparkle"
        case .neon: return "Neon"
        case .glow: return "Glow"
        case .pixel: return "Pixel"
        case .marker: return "Marker"
        case .chalk: return "Chalk"
        case .shimmer: return "Shimmer"
        }
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
