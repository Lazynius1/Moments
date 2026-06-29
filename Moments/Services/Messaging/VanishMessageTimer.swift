import Foundation

enum VanishMessageTimer: String, CaseIterable, Codable, Identifiable {
    case onceSeen
    case hours24
    case days7

    var id: String { rawValue }

    static let `default`: VanishMessageTimer = .hours24

    init(storedValue: String?) {
        guard let storedValue, let timer = VanishMessageTimer(rawValue: storedValue) else {
            self = .default
            return
        }
        self = timer
    }

    var localizationKey: String {
        switch self {
        case .onceSeen: return "chat.vanish.timer.onceSeen"
        case .hours24: return "chat.vanish.timer.24h"
        case .days7: return "chat.vanish.timer.7d"
        }
    }

    var enabledNoticeToken: String {
        "disappearing:enabled:\(rawValue)"
    }

    static func parseEnabledNotice(_ content: String) -> VanishMessageTimer? {
        let parts = content.split(separator: ":").map(String.init)
        guard parts.count == 3, parts[0] == "disappearing", parts[1] == "enabled" else { return nil }
        return VanishMessageTimer(rawValue: parts[2])
    }

    static let disabledNoticeToken = "disappearing:disabled"
    static let screenshotNoticeToken = "disappearing:screenshot"
    static let screenRecordingNoticeToken = "disappearing:screenRecording"

    /// Offset desde el ancla "everyone has seen" (no desde el envío).
    func expiresAt(from date: Date = Date()) -> Date? {
        switch self {
        case .onceSeen:
            return nil
        case .hours24:
            return date.addingTimeInterval(86_400)
        case .days7:
            return date.addingTimeInterval(7 * 86_400)
        }
    }

    static func isExpired(_ expiresAt: Date?) -> Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}
