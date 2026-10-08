import Foundation

extension Date {
    /// Tiempo corto sin «hace» («5 min», «3 h»). Para posts usa `MomentsFormat.smartDate(context: .feedTimestamp)`.
    func timeAgoDisplay() -> String {
        MomentsFormat.relativeTime(from: self)
    }
}
