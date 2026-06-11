import Foundation

enum FeatureDiscoveryStore {
    private static let seenKey = "hasSeenFeatureDiscovery"
    private static let pendingKey = "pendingFeatureDiscovery"

    static var shouldPresent: Bool {
        !UserDefaults.standard.bool(forKey: seenKey)
            && UserDefaults.standard.bool(forKey: pendingKey)
    }

    static func markPending() {
        UserDefaults.standard.set(true, forKey: pendingKey)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }
}
