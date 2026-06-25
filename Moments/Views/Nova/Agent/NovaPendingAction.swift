import Foundation
import FirebaseAI
import UIKit

struct NovaPendingAction: Identifiable {
    enum Kind: Equatable {
        case createMoment
        case rememberFact
        case updatePreference
        case sendFollowRequest
        case updatePrivacySettings
        case updateProfileBio
        case updateProfileWebsite
        case updateActiveHours
        case updateNotificationPreferences
    }

    let id = UUID()
    let kind: Kind
    let toolName: String
    let title: String
    let detail: String
    let audienceLabel: String?
    let previewImage: UIImage?
    let args: JSONObject

    static func from(toolName: String, args: JSONObject, previewImage: UIImage? = nil) -> NovaPendingAction? {
        switch toolName {
        case "create_moment":
            guard previewImage != nil else { return nil }
            let content = {
                if case let .string(text) = args["content"], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
                return NSLocalizedString("nova.confirm.photoOnly", comment: "")
            }()

            let audienceRaw = {
                if case let .string(text) = args["audience"] { return text }
                return "everyone"
            }()

            let targetUsername: String? = {
                if case let .string(text) = args["target_username"] { return text }
                return nil
            }()

            let customListName: String? = {
                if case let .string(text) = args["custom_list_name"] { return text }
                return nil
            }()

            let audienceLabel = NovaMomentAudienceResolver.audienceSummary(
                audienceRaw: audienceRaw,
                targetUsername: targetUsername,
                customListName: customListName
            )

            var detailParts: [String] = []
            if !content.isEmpty {
                detailParts.append(content)
            }
            detailParts.append(
                String(
                    format: NSLocalizedString("nova.confirm.audienceLine", comment: ""),
                    audienceLabel
                )
            )

            return NovaPendingAction(
                kind: .createMoment,
                toolName: toolName,
                title: NSLocalizedString("nova.confirm.createMoment.title", comment: ""),
                detail: detailParts.joined(separator: "\n\n"),
                audienceLabel: audienceLabel,
                previewImage: previewImage,
                args: args
            )
        case "remember_fact":
            guard case let .string(content) = args["content"], !content.isEmpty else { return nil }
            return NovaPendingAction(
                kind: .rememberFact,
                toolName: toolName,
                title: NSLocalizedString("nova.confirm.rememberFact.title", comment: ""),
                detail: content,
                audienceLabel: nil,
                previewImage: nil,
                args: args
            )
        case "update_user_preference":
            guard case let .string(key) = args["key"],
                  case let .string(value) = args["value"],
                  !value.isEmpty else { return nil }
            return NovaPendingAction(
                kind: .updatePreference,
                toolName: toolName,
                title: NSLocalizedString("nova.confirm.updatePreference.title", comment: ""),
                detail: "\(key): \(value)",
                audienceLabel: nil,
                previewImage: nil,
                args: args
            )
        case "send_follow_request":
            let username = {
                if case let .string(text) = args["username"] { return text }
                return ""
            }()
            guard !username.isEmpty else { return nil }
            return NovaPendingAction(
                kind: .sendFollowRequest,
                toolName: toolName,
                title: localizedTitle(for: .sendFollowRequest),
                detail: "@\(username.trimmingCharacters(in: CharacterSet(charactersIn: "@")))",
                audienceLabel: nil,
                previewImage: nil,
                args: args
            )
        case "update_profile_privacy_settings":
            return NovaPendingAction(
                kind: .updatePrivacySettings,
                toolName: toolName,
                title: localizedTitle(for: .updatePrivacySettings),
                detail: describePrivacyArgs(args),
                audienceLabel: nil,
                previewImage: nil,
                args: args
            )
        case "update_profile_bio":
            guard case let .string(bio) = args["bio"] else { return nil }
            return NovaPendingAction(
                kind: .updateProfileBio,
                toolName: toolName,
                title: localizedTitle(for: .updateProfileBio),
                detail: bio.isEmpty ? localizedEmptyValueLabel() : bio,
                audienceLabel: nil,
                previewImage: nil,
                args: args
            )
        case "update_profile_website":
            guard case let .string(website) = args["website"] else { return nil }
            return NovaPendingAction(
                kind: .updateProfileWebsite,
                toolName: toolName,
                title: localizedTitle(for: .updateProfileWebsite),
                detail: website.isEmpty ? localizedEmptyValueLabel() : website,
                audienceLabel: nil,
                previewImage: nil,
                args: args
            )
        case "update_active_hours":
            return NovaPendingAction(
                kind: .updateActiveHours,
                toolName: toolName,
                title: localizedTitle(for: .updateActiveHours),
                detail: describeActiveHoursArgs(args),
                audienceLabel: nil,
                previewImage: nil,
                args: args
            )
        case "update_notification_preferences":
            return NovaPendingAction(
                kind: .updateNotificationPreferences,
                toolName: toolName,
                title: localizedTitle(for: .updateNotificationPreferences),
                detail: describeNotificationPreferenceArgs(args),
                audienceLabel: nil,
                previewImage: nil,
                args: args
            )
        default:
            return nil
        }
    }

    private static func localizedTitle(for kind: Kind) -> String {
        switch kind {
        case .createMoment:
            return NSLocalizedString("nova.confirm.createMoment.title", comment: "")
        case .rememberFact:
            return NSLocalizedString("nova.confirm.rememberFact.title", comment: "")
        case .updatePreference:
            return NSLocalizedString("nova.confirm.updatePreference.title", comment: "")
        case .sendFollowRequest:
            return NSLocalizedString("nova.confirm.sendFollowRequest.title", comment: "")
        case .updatePrivacySettings:
            return NSLocalizedString("nova.confirm.updatePrivacySettings.title", comment: "")
        case .updateProfileBio:
            return NSLocalizedString("nova.confirm.updateProfileBio.title", comment: "")
        case .updateProfileWebsite:
            return NSLocalizedString("nova.confirm.updateProfileWebsite.title", comment: "")
        case .updateActiveHours:
            return NSLocalizedString("nova.confirm.updateActiveHours.title", comment: "")
        case .updateNotificationPreferences:
            return NSLocalizedString("nova.confirm.updateNotificationPreferences.title", comment: "")
        }
    }

    private static func localizedEmptyValueLabel() -> String {
        NSLocalizedString("nova.confirm.clearField", comment: "")
    }

    private static func describePrivacyArgs(_ args: JSONObject) -> String {
        var lines: [String] = []
        appendBoolLine(args["is_private"], labelKey: "nova.confirm.field.privateAccount", to: &lines)
        appendBoolLine(args["show_mutual_connections"], labelKey: "nova.confirm.field.showMutuals", to: &lines)
        appendBoolLine(args["show_following"], labelKey: "nova.confirm.field.showFollowing", to: &lines)
        appendBoolLine(args["show_followers"], labelKey: "nova.confirm.field.showFollowers", to: &lines)
        return lines.joined(separator: "\n")
    }

    private static func describeActiveHoursArgs(_ args: JSONObject) -> String {
        if case .bool(true) = args["clear"] {
            return NSLocalizedString("nova.confirm.activeHours.clear", comment: "")
        }

        let start = {
            if case let .string(text) = args["start_hour"] { return text }
            return "--:--"
        }()
        let end = {
            if case let .string(text) = args["end_hour"] { return text }
            return "--:--"
        }()

        return String(
            format: NSLocalizedString("nova.confirm.activeHours.range", comment: ""),
            start,
            end
        )
    }

    private static func describeNotificationPreferenceArgs(_ args: JSONObject) -> String {
        let object: JSONObject
        if case let .object(nested) = args["preferences"] {
            object = nested
        } else {
            object = args.filter { _, value in
                if case .bool = value { return true }
                return false
            }
        }
        let pairs = object.compactMap { key, value -> String? in
            guard case let .bool(flag) = value else { return nil }
            let label = localizedNotificationPreferenceLabel(for: key)
            let state = localizedToggleState(flag)
            return "\(label): \(state)"
        }
        return pairs.sorted().joined(separator: "\n")
    }

    private static func appendBoolLine(_ value: JSONValue?, labelKey: String, to lines: inout [String]) {
        guard case let .bool(flag) = value else { return }
        let key = NSLocalizedString(labelKey, comment: "")
        let state = localizedYesNoState(flag)
        lines.append("\(key): \(state)")
    }

    private static func localizedYesNoState(_ flag: Bool) -> String {
        NSLocalizedString(flag ? "nova.confirm.state.yes" : "nova.confirm.state.no", comment: "")
    }

    private static func localizedToggleState(_ flag: Bool) -> String {
        NSLocalizedString(flag ? "nova.confirm.state.enabled" : "nova.confirm.state.disabled", comment: "")
    }

    private static func localizedNotificationPreferenceLabel(for key: String) -> String {
        switch key {
        case NotificationType.like.rawValue:
            return NotificationType.like.displayName
        case NotificationType.reaction.rawValue:
            return NotificationType.reaction.displayName
        case NotificationType.comment.rawValue:
            return NotificationType.comment.displayName
        case NotificationType.mention.rawValue:
            return NotificationType.mention.displayName
        case NotificationType.newFollower.rawValue:
            return NotificationType.newFollower.displayName
        case NotificationType.followRequest.rawValue:
            return NotificationType.followRequest.displayName
        case NotificationType.requestAccepted.rawValue:
            return NotificationType.requestAccepted.displayName
        case NotificationType.mutualConnection.rawValue:
            return NotificationType.mutualConnection.displayName
        case NotificationType.storyReaction.rawValue:
            return NotificationType.storyReaction.displayName
        case NotificationType.message.rawValue:
            return NotificationType.message.displayName
        case NotificationType.photoTag.rawValue:
            return NotificationType.photoTag.displayName
        case NotificationType.echoSuggestion.rawValue:
            return NotificationType.echoSuggestion.displayName
        case NotificationType.dataExportReady.rawValue:
            return NotificationType.dataExportReady.displayName
        case NotificationType.storyChainContinued.rawValue:
            return NotificationType.storyChainContinued.displayName
        case NotificationType.mediaModeration.rawValue:
            return NotificationType.mediaModeration.displayName
        case "gentleReminders":
            return NSLocalizedString("settings.notifications.gentleReminders.title", comment: "")
        case "commentsMutualsOnly":
            return NSLocalizedString("settings.notifications.mutualsOnly", comment: "")
        case "muteOldPostReactions":
            return NSLocalizedString("settings.notifications.muteOldReactions", comment: "")
        default:
            return key
        }
    }
}
