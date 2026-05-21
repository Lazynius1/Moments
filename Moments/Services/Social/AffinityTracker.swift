import Foundation
import SwiftData
import FirebaseAuth

/// The type of interaction a user can have with another user
enum AffinityInteractionType: String {
    case directMessage = "directMessage"      // +10
    case storyReaction = "storyReaction"      // +5
    case momentReaction = "momentReaction"    // +5
    case momentComment = "momentComment"      // +5
    case profileVisit = "profileVisit"        // +2
    case momentView = "momentView"            // +1
    
    var scoreValue: Double {
        switch self {
        case .directMessage: return 10.0
        case .storyReaction: return 5.0
        case .momentReaction: return 5.0
        case .momentComment: return 5.0
        case .profileVisit: return 2.0
        case .momentView: return 1.0
        }
    }
}

/// Service responsible for managing local affinity scores between the current user and other users.
@MainActor
class AffinityTracker {
    static let shared = AffinityTracker()
    
    // Configured via Dependency Injection from MomentsApp
    var modelContainer: ModelContainer?
    
    private init() {}
    
    func setup(container: ModelContainer) {
        self.modelContainer = container
    }
    
    private func affinityKey(ownerUserId: String, targetUserId: String) -> String {
        UserAffinity.makeAffinityKey(ownerUserId: ownerUserId, targetUserId: targetUserId)
    }
    
    /// Tracks an interaction and updates the local affinity score for the target user.
    /// - Parameters:
    ///   - type: The interaction type
    ///   - targetUserId: The ID of the user being interacted with
    func trackInteraction(type: AffinityInteractionType, with targetUserId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid, !currentUserId.isEmpty else {
            return
        }
        
        // Prevent tracking affinity for self
        if currentUserId == targetUserId {
            return
        }
        
        guard let container = modelContainer else {
            print("❌ [AffinityTracker] ModelContainer not initialized.")
            return
        }
        
        let context = ModelContext(container)
        let key = affinityKey(ownerUserId: currentUserId, targetUserId: targetUserId)
        
        do {
            // Check if affinity already exists
            let descriptor = FetchDescriptor<UserAffinity>(predicate: #Predicate { $0.affinityKey == key })
            let existingAffinities = try context.fetch(descriptor)
            
            if let affinity = existingAffinities.first {
                // Update existing affinity
                affinity.score += type.scoreValue
                affinity.lastInteractionDate = Date()
                
                let oldCount = affinity.interactionCounts[type.rawValue] ?? 0
                affinity.interactionCounts[type.rawValue] = oldCount + 1
                
                print("🔄 [AffinityTracker] Updated affinity for \(targetUserId). New score: \(affinity.score)")
            } else {
                // Create new affinity
                let newAffinity = UserAffinity(
                    ownerUserId: currentUserId,
                    targetUserId: targetUserId,
                    score: type.scoreValue,
                    lastInteractionDate: Date(),
                    interactionCounts: [type.rawValue: 1]
                )
                context.insert(newAffinity)
                print("✨ [AffinityTracker] Created affinity for \(targetUserId). Score: \(newAffinity.score)")
            }
            
            try context.save()
            
        } catch {
            print("❌ [AffinityTracker] Error saving interaction: \(error)")
        }
    }
    
    /// Returns the affinity score for a given user. If none exists, returns 0.
    func getScore(for targetUserId: String, in context: ModelContext) -> Double {
        guard let currentUserId = Auth.auth().currentUser?.uid, !currentUserId.isEmpty else {
            return 0.0
        }
        
        let key = affinityKey(ownerUserId: currentUserId, targetUserId: targetUserId)
        let descriptor = FetchDescriptor<UserAffinity>(predicate: #Predicate { $0.affinityKey == key })
        
        do {
            if let affinity = try context.fetch(descriptor).first {
                return affinity.score
            }
        } catch {
            print("❌ [AffinityTracker] Error fetching affinity score: \(error)")
        }
        
        return 0.0
    }
    
    /// Returns local affinity scores for a batch of target users with a single fetch.
    func getScores(for targetUserIds: [String], in context: ModelContext) -> [String: Double] {
        guard let currentUserId = Auth.auth().currentUser?.uid, !currentUserId.isEmpty else {
            return [:]
        }
        
        let uniqueIds = Array(Set(targetUserIds.filter { !$0.isEmpty }))
        guard !uniqueIds.isEmpty else { return [:] }
        
        let descriptor = FetchDescriptor<UserAffinity>(
            predicate: #Predicate { $0.ownerUserId == currentUserId && uniqueIds.contains($0.targetUserId) }
        )
        
        do {
            let affinities = try context.fetch(descriptor)
            var scores: [String: Double] = [:]
            scores.reserveCapacity(affinities.count)
            for affinity in affinities {
                scores[affinity.targetUserId] = affinity.score
            }
            return scores
        } catch {
            print("❌ [AffinityTracker] Error fetching affinity scores batch: \(error)")
            return [:]
        }
    }
    
    // MARK: - Time Decay
    
    /// Reduces the scores of older interactions. Called occasionally (e.g., app launch).
    func applyTimeDecayIfNeeded() {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        
        do {
            // Consider "old" interactions as those older than 3 days
            let calendar = Calendar.current
            guard let decayThresholdDate = calendar.date(byAdding: .day, value: -3, to: Date()) else { return }
            
            let descriptor = FetchDescriptor<UserAffinity>(
                predicate: #Predicate { $0.lastInteractionDate < decayThresholdDate }
            )
            
            let staleAffinities = try context.fetch(descriptor)
            
            var didUpdate = false
            for affinity in staleAffinities {
                // Decay rule: reduce score by 15%
                let newScore = affinity.score * 0.85
                affinity.score = newScore
                // Update timestamp so we don't apply the same decay over and over immediately
                affinity.lastInteractionDate = Date()
                didUpdate = true
            }
            
            if didUpdate {
                try context.save()
                print("📉 [AffinityTracker] Applied time-decay to \(staleAffinities.count) old affinities.")
            }
            
        } catch {
            print("❌ [AffinityTracker] Error applying time-decay: \(error)")
        }
    }
    
    /// Removes old affinities that are effectively irrelevant after decay.
    /// This keeps local storage lean without changing ranking behavior.
    func cleanupVeryLowAffinities(minScore: Double = 0.5, olderThanDays: Int = 90) {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -olderThanDays, to: Date()) else { return }
        
        do {
            let descriptor = FetchDescriptor<UserAffinity>(
                predicate: #Predicate {
                    $0.score < minScore && $0.lastInteractionDate < cutoffDate
                }
            )
            
            let staleAffinities = try context.fetch(descriptor)
            guard !staleAffinities.isEmpty else { return }
            
            for affinity in staleAffinities {
                context.delete(affinity)
            }
            
            try context.save()
            print("🧹 [AffinityTracker] Cleaned \(staleAffinities.count) low-value affinities.")
        } catch {
            print("❌ [AffinityTracker] Error cleaning low-value affinities: \(error)")
        }
    }
}
