import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import Combine

func isPerActorSocialNotification(_ type: NotificationType) -> Bool {
    switch type {
    case .newFollower, .mutualConnection, .followRequest, .requestAccepted:
        return true
    default:
        return false
    }
}

enum NotificationRowMetrics {
    static let avatarSize: CGFloat = 48
    static let stackedAvatarSize: CGFloat = 46
    static let stackedOverlapRatio: CGFloat = 0.34
    static var stackedOverlap: CGFloat { stackedAvatarSize * stackedOverlapRatio }
    static var stackedRowWidth: CGFloat { stackedAvatarSize * 2 - stackedOverlap }
    static let storyThumbnailWidth: CGFloat = 44
    static let storyThumbnailHeight: CGFloat = 58
    static let storyThumbnailCornerRadius: CGFloat = 8
}

struct NotificationGroupedActors {
    let primary: String
    let secondary: String?
    let othersCount: Int

    var hasExactlyTwo: Bool { secondary != nil && othersCount == 0 }
}

func uniqueSenderIds(in group: NotificationGroup) -> [String] {
    var seen = Set<String>()
    return group.notifications.compactMap { notification -> String? in
        let id = notification.senderId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, seen.insert(id).inserted else { return nil }
        return id
    }
}

enum NotificationProfileLink {
    private static let host = "notification-profile"

    static func url(userId: String) -> URL? {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "moments://\(host)/\(encoded)")
    }

    static func userId(from url: URL) -> String? {
        guard url.scheme == "moments", url.host == host else { return nil }
        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !raw.isEmpty else { return nil }
        return raw.removingPercentEncoding ?? raw
    }
}

func styledNotificationMessage(
    _ plain: String,
    boldNames: [String],
    nameToUserId: [String: String],
    baseColor: Color,
    largeEmoji: String? = nil
) -> AttributedString {
    var attributed = AttributedString(plain)
    attributed.foregroundColor = baseColor

    let uniqueBoldNames = boldNames
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .reduce(into: [String]()) { result, name in
            if !result.contains(name) { result.append(name) }
        }
        .sorted { $0.count > $1.count }

    let nameFont = Font.system(size: 14, weight: .semibold)
    for name in uniqueBoldNames {
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let range = attributed[searchStart...].range(of: name) {
            attributed[range].font = nameFont
            attributed[range].foregroundColor = baseColor
            if let userId = nameToUserId[name], let link = NotificationProfileLink.url(userId: userId) {
                attributed[range].link = link
            }
            searchStart = range.upperBound
        }
    }

    if let largeEmoji, !largeEmoji.isEmpty, let range = attributed.range(of: largeEmoji) {
        attributed[range].font = .system(size: 18)
    }

    return attributed
}

func notificationGroupedMessage(
    twoKey: String,
    threePlusKey: String,
    multipleKey: String,
    actors: NotificationGroupedActors,
    nameToUserId: [String: String],
    baseColor: Color
) -> AttributedString {
    var boldNames = [actors.primary]
    if let secondary = actors.secondary { boldNames.append(secondary) }

    let plain: String
    if actors.hasExactlyTwo, let secondary = actors.secondary {
        plain = String(format: NSLocalizedString(twoKey, comment: ""), actors.primary, secondary)
    } else if let secondary = actors.secondary, actors.othersCount > 0 {
        plain = String(format: NSLocalizedString(threePlusKey, comment: ""), actors.primary, secondary, actors.othersCount)
    } else {
        let moreCount = max(actors.othersCount, 1)
        plain = String(format: NSLocalizedString(multipleKey, comment: ""), actors.primary, moreCount)
    }

    return styledNotificationMessage(plain, boldNames: boldNames, nameToUserId: nameToUserId, baseColor: baseColor)
}

func normalizedCommentPreview(from notification: Notification) -> String? {
    let candidates = [notification.reaction, notification.message]
    for raw in candidates {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
        if ReactionType(rawValue: text) != nil { continue }
        if text.count > 140 {
            return String(text.prefix(137)) + "…"
        }
        return text
    }
    return nil
}
