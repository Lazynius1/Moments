import Foundation

struct InterestEmojiHelper {
    static func emoji(for interest: String) -> String {
        InterestCatalog.emoji(for: interest)
    }

    static var supportedInterests: [(name: String, emoji: String)] {
        InterestCatalog.all.map { def in
            (InterestCatalog.localize(def.firestoreKey), def.emoji)
        }
    }

    static func randomInterest() -> (name: String, emoji: String) {
        guard let def = InterestCatalog.all.randomElement() else {
            return (NSLocalizedString("profile.interests.title", comment: ""), "✨")
        }
        return (InterestCatalog.localize(def.firestoreKey), def.emoji)
    }
}
