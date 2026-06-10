import SwiftUI
import UIKit

private struct StoryEffectsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var storyEffectsActive: Bool {
        get { self[StoryEffectsActiveKey.self] }
        set { self[StoryEffectsActiveKey.self] = newValue }
    }
}

/// Política central de animación: reduce motion, LOD de partículas y duraciones.
enum MotionPolicy {
    static var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// Densidad original del reveal noise (calidad visual prioritaria).
    static func revealParticleCount(for size: CGSize) -> Int {
        if reduceMotion { return 0 }
        let area = max(size.width * size.height, 1)
        return min(max(Int(area / 90), 80), 600)
    }

    /// Cap más bajo solo para efectos secundarios del feed, no reveal.
    static var maxParticleCount: Int {
        if reduceMotion { return 0 }
        let area = UIScreen.main.bounds.width * UIScreen.main.bounds.height
        switch area {
        case ..<350_000: return 80
        case ..<450_000: return 140
        default: return 220
        }
    }

    static var canvasFPS: Double { 30 }

    static func animation<V>(_ animation: Animation?, value: V) -> Animation? where V: Equatable {
        reduceMotion ? nil : animation
    }

    static func withOptionalAnimation<Result>(
        _ animation: Animation? = .default,
        _ body: () throws -> Result
    ) rethrows -> Result {
        if reduceMotion {
            try body()
        } else if let animation {
            try withAnimation(animation, body)
        } else {
            try body()
        }
    }
}
