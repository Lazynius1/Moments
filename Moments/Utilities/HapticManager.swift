import SwiftUI
import UIKit
import AudioToolbox

class HapticManager {
    static let shared = HapticManager()

    /// Play sound alert for incoming chat "zumbidos" (Classic tri-tone chime).
    func playBuzzReceivedSound() {
        AudioServicesPlaySystemSound(1022)
    }

    /// Play sound whoosh for outgoing chat "zumbidos" (Sent mail whoosh).
    func playBuzzSentSound() {
        AudioServicesPlaySystemSound(1033)
    }

    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationFeedback = UINotificationFeedbackGenerator()

    private init() {
        // Pre-warm generators for faster response
        selectionFeedback.prepare()
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        notificationFeedback.prepare()
    }

    /// Tick háptico continuo durante pull de vanish (estilo IG).
    func vanishPullStep() {
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    /// Umbral alcanzado al completar el arco.
    func vanishPullThresholdReached() {
        impactLight.impactOccurred(intensity: 0.72)
        impactLight.prepare()
    }

    /// Triggered when the user changes a selection (e.g., Tab Bar)
    func selection() {
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    /// Light impact for minor actions (e.g., button press)
    func lightImpact() {
        impactLight.impactOccurred()
        impactLight.prepare()
    }

    /// Medium impact for key actions (e.g., Like, Follow)
    func mediumImpact() {
        impactMedium.impactOccurred()
        impactMedium.prepare()
    }

    /// Heavy impact for main actions or "physical" collisions
    func heavyImpact() {
        impactHeavy.impactOccurred()
        impactHeavy.prepare()
    }

    /// Notification feedback (Success, Warning, Error)
    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationFeedback.notificationOccurred(type)
        notificationFeedback.prepare()
    }

    /// Impact genérico (p. ej. Explore legacy).
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        switch style {
        case .light, .soft:
            lightImpact()
        case .medium:
            mediumImpact()
        case .heavy, .rigid:
            heavyImpact()
        @unknown default:
            mediumImpact()
        }
    }

    /// Long, physical buzz pattern for incoming chat "zumbidos".
    func chatBuzzReceived(reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled) {
        impactHeavy.impactOccurred(intensity: 1)
        impactHeavy.prepare()

        guard !reduceMotion else { return }

        let pulses: [(delay: TimeInterval, style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat)] = [
            (0.08, .rigid, 1.0),
            (0.16, .heavy, 0.96),
            (0.26, .rigid, 0.9),
            (0.38, .heavy, 0.84),
            (0.52, .rigid, 0.76),
            (0.68, .heavy, 0.68),
            (0.86, .rigid, 0.58)
        ]

        for pulse in pulses {
            DispatchQueue.main.asyncAfter(deadline: .now() + pulse.delay) {
                let generator = UIImpactFeedbackGenerator(style: pulse.style)
                generator.prepare()
                generator.impactOccurred(intensity: pulse.intensity)
            }
        }
    }

    func success() {
        notification(.success)
    }

    func warning() {
        notification(.warning)
    }

    func error() {
        notification(.error)
    }
}
