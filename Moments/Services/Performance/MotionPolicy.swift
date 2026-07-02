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

    /// Presets de spring alineados con micro-interacciones de la app.
    enum Spring {
        static var press: Animation { .spring(response: 0.28, dampingFraction: 0.72) }
        static var toggle: Animation { .spring(response: 0.32, dampingFraction: 0.78) }
        static var sheet: Animation { .smooth(duration: 0.18, extraBounce: 0.01) }
        static var header: Animation { .spring(response: 0.32, dampingFraction: 0.86) }
        static var row: Animation { .spring(response: 0.3, dampingFraction: 0.8) }

        static func repeatingPulse(duration: TimeInterval = 1.2) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: duration).repeatForever(autoreverses: true)
        }
    }
}
