import SwiftUI
import UIKit

class HapticManager {
    static let shared = HapticManager()
    
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
}
