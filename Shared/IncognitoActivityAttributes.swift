import ActivityKit
import Foundation

public struct IncognitoActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var remainingSeconds: Int
        public var isActive: Bool

        public init(remainingSeconds: Int, isActive: Bool) {
            self.remainingSeconds = remainingSeconds
            self.isActive = isActive
        }
    }

    public var userId: String

    public init(userId: String) {
        self.userId = userId
    }
}
