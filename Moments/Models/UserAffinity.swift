import Foundation
import SwiftData

/// Represents the locally computed affinity score towards another user.
/// Raw interaction counts stay local. A bounded aggregate score can personalize the shared feed ranking.
@Model
final class UserAffinity {
    /// Unique composite key: ownerUserId + targetUserId
    /// This prevents mixing affinities between multiple local accounts.
    @Attribute(.unique) var affinityKey: String
    
    /// The local account owner for this affinity row.
    var ownerUserId: String
    
    /// The ID of the user being interacted with (e.g., the author of a moment, or recipient of a DM)
    var targetUserId: String
    
    /// The total accumulated affinity score based on implicit and explicit interactions
    var score: Double
    
    /// The timestamp of the last interaction, used for applying time-decay to scores
    var lastInteractionDate: Date
    
    /// Tracks specific interaction counts for analytics or weighted decay (optional)
    var interactionCounts: [String: Int]
    
    init(ownerUserId: String, targetUserId: String, score: Double = 0.0, lastInteractionDate: Date = Date(), interactionCounts: [String: Int] = [:]) {
        self.ownerUserId = ownerUserId
        self.targetUserId = targetUserId
        self.affinityKey = UserAffinity.makeAffinityKey(ownerUserId: ownerUserId, targetUserId: targetUserId)
        self.score = score
        self.lastInteractionDate = lastInteractionDate
        self.interactionCounts = interactionCounts
    }
    
    static func makeAffinityKey(ownerUserId: String, targetUserId: String) -> String {
        "\(ownerUserId)|\(targetUserId)"
    }
}
