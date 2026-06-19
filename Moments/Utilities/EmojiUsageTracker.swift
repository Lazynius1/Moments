import Foundation
import FirebaseAuth
import Combine

enum EmojiReactionDefaults {
    static let chat: [String] = ["❤️", "😂", "😮", "😢", "😡", "👍"]
    static let story: [String] = ReactionType.allCases.map(\.icon)
    static let emojiSlider: [String] = ["😍", "🔥", "😂", "🥹", "❤️", "👏", "🙌", "💯"]
}

enum EmojiUsageStore {
    private static func storageKey(for userId: String) -> String {
        "emojiUsage_\(userId.isEmpty ? "guest" : userId)"
    }

    private static func readCounts(userId: String) -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: storageKey(for: userId)),
              let counts = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return counts
    }

    private static func loadCounts(userId: String) -> [String: Int] {
        migrateLegacySliderUsageIfNeeded(userId: userId)
        return readCounts(userId: userId)
    }

    private static func saveCounts(_ counts: [String: Int], userId: String) {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(for: userId))
    }

    static func increment(_ emoji: String, userId: String? = Auth.auth().currentUser?.uid) {
        let resolvedUserId = userId ?? ""
        guard !emoji.isEmpty else { return }
        var counts = loadCounts(userId: resolvedUserId)
        counts[emoji, default: 0] += 1
        saveCounts(counts, userId: resolvedUserId)
    }

    static func ordered(
        from defaults: [String],
        userId: String? = Auth.auth().currentUser?.uid,
        limit: Int? = nil
    ) -> [String] {
        let resolvedUserId = userId ?? ""
        let counts = loadCounts(userId: resolvedUserId)
        let sorted = defaults.sorted { lhs, rhs in
            let leftCount = counts[lhs] ?? 0
            let rightCount = counts[rhs] ?? 0
            if leftCount != rightCount { return leftCount > rightCount }
            let leftIndex = defaults.firstIndex(of: lhs) ?? 0
            let rightIndex = defaults.firstIndex(of: rhs) ?? 0
            return leftIndex < rightIndex
        }
        if let limit { return Array(sorted.prefix(limit)) }
        return sorted
    }

    private static func migrateLegacySliderUsageIfNeeded(userId: String) {
        guard !userId.isEmpty else { return }
        let legacyKey = "storyEditor.emojiSliderUsage.\(userId)"
        guard let legacy = UserDefaults.standard.dictionary(forKey: legacyKey) as? [String: Int],
              !legacy.isEmpty else { return }

        var counts = readCounts(userId: userId)
        for (emoji, count) in legacy {
            counts[emoji, default: 0] += count
        }
        saveCounts(counts, userId: userId)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }
}

final class EmojiUsageTracker: ObservableObject {
    @Published private var revision = 0
    private let userId: String

    init(userId: String? = nil) {
        self.userId = userId ?? Auth.auth().currentUser?.uid ?? ""
    }

    func increment(_ emoji: String) {
        EmojiUsageStore.increment(emoji, userId: userId)
        revision += 1
    }

    func orderedEmojis(from defaults: [String], limit: Int? = nil) -> [String] {
        _ = revision
        return EmojiUsageStore.ordered(from: defaults, userId: userId, limit: limit)
    }
}
