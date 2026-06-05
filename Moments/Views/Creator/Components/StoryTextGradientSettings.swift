import SwiftUI
import UIKit

enum StoryTextGradientSettings {
    static let minStops = 2
    static let maxStops = 6

    static let presetMoments: [Color] = [
        Color(hex: "FF2D55"),
        Color(hex: "FF9500"),
        Color(hex: "FFD60A"),
        Color(hex: "5E5CE6")
    ]

    static let presetSunset: [Color] = [
        Color(hex: "FF6B6B"),
        Color(hex: "FF8E53"),
        Color(hex: "FECA57"),
        Color(hex: "FF9FF3")
    ]

    static let presetOcean: [Color] = [
        Color(hex: "007AFF"),
        Color(hex: "00C7BE"),
        Color(hex: "5AC8FA"),
        Color(hex: "30B0C7")
    ]

    static func defaultStops(anchoredTo color: Color) -> [Color] {
        [color, Color(hex: "FF2D55"), Color(hex: "5E5CE6")]
    }

    static func normalizedStops(_ stops: [Color], fallback: Color) -> [Color] {
        let trimmed = stops.filter { _ in true }
        if trimmed.count >= minStops {
            return Array(trimmed.prefix(maxStops))
        }
        return defaultStops(anchoredTo: fallback)
    }

    static func encodeStops(_ stops: [Color]) -> [String] {
        normalizedStops(stops, fallback: .white).map { $0.toHex() }
    }

    static func decodeStops(_ hexes: [String]?, fallback: Color) -> [Color] {
        guard let hexes, hexes.count >= minStops else {
            return defaultStops(anchoredTo: fallback)
        }
        return Array(hexes.prefix(maxStops)).map { Color(hex: $0) }
    }

    static func gradientPoints(angleDegrees: Int) -> (start: CGPoint, end: CGPoint) {
        switch angleDegrees {
        case 90:
            return (CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1))
        case 45:
            return (CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1))
        default:
            return (CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5))
        }
    }

    static func cycleAngle(_ current: Int) -> Int {
        switch current {
        case 0: return 90
        case 90: return 45
        default: return 0
        }
    }

    static func angleSymbol(_ degrees: Int) -> String {
        switch degrees {
        case 90: return "↕"
        case 45: return "↗"
        default: return "↔"
        }
    }
}

extension StoryTextRenderConfiguration {
    var resolvedGradientStops: [UIColor] {
        let colors = StoryTextGradientSettings.normalizedStops(gradientStops, fallback: textColor)
        return colors.map { UIColor($0) }
    }

    var gradientUnitPoints: (start: CGPoint, end: CGPoint) {
        StoryTextGradientSettings.gradientPoints(angleDegrees: gradientAngle)
    }
}
