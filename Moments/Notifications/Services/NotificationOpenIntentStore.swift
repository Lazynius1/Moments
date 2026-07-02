import Foundation

/// Filtro de pestaña al abrir Notificaciones desde banner, push o deep link.
enum NotificationOpenIntentStore {
    private(set) static var pendingFilter: String?

    static func enqueue(filter: String?) {
        pendingFilter = filter
    }

    static func consumeFilter() -> String? {
        defer { pendingFilter = nil }
        return pendingFilter
    }

    static func tab(for filter: String) -> NotificationsView.NotificationTab? {
        switch filter {
        case "requests":
            return .requests
        case "reactions":
            return .reactions
        case "comments":
            return .comments
        case "stories":
            return .storyReactions
        case "follows":
            return .follows
        default:
            return nil
        }
    }
}
