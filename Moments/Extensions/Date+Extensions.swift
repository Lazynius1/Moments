import Foundation

extension Date {
    /// Compact relative time for feed and social surfaces. Prefer `MomentsFormat.relativeTime(from:)`.
    func timeAgoDisplay() -> String {
        MomentsFormat.relativeTime(from: self)
    }
}
