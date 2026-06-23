import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher

extension EnhancedNotificationRow {
    func messageForGroup(_ group: NotificationGroup) -> AttributedString {
        let firstNotification = group.notifications.first!
        let nameToUserId = senderDisplayNamesToUserIds()
        let messageColor = notificationMessageColor
        let effectiveSenderUsername = senderDisplayName(for: firstNotification)
        let reactionAggregateCount = (firstNotification.type == .reaction)
            ? max(1, firstNotification.reactionCount ?? group.notifications.count)
            : group.notifications.count
        let hasMultipleActors: Bool
        if firstNotification.type == .reaction {
            hasMultipleActors = reactionAggregateCount > 1
        } else if firstNotification.type == .newFollower || firstNotification.type == .mutualConnection {
            // Agregación: "X y N más comenzaron a seguirte" / "...conexión mutua con X y N más"
            // (grupo ya deduplicado por persona)
            hasMultipleActors = group.notifications.count > 1
        } else if isPerActorSocialNotification(firstNotification.type) {
            // requestAccepted / followRequest: una fila por persona (evento o acción individual)
            hasMultipleActors = false
        } else {
            hasMultipleActors = uniqueSenderIds(in: group).count > 1
        }

        if hasMultipleActors {
            let actors = groupedActorsForMessage()
            switch firstNotification.type {
            case .like:
                return notificationGroupedMessage(
                    twoKey: "notifications.message.like.two",
                    threePlusKey: "notifications.message.like.threePlus",
                    multipleKey: "notifications.message.like.multiple",
                    actors: actors,
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .reaction:
                if let reactionString = firstNotification.reaction,
                   let reactionType = ReactionType(rawValue: reactionString) {
                    let text: String
                    var boldNames = [actors.primary]
                    if let secondary = actors.secondary { boldNames.append(secondary) }
                    if actors.hasExactlyTwo, let secondary = actors.secondary {
                        text = String(
                            format: NSLocalizedString("notifications.message.reaction.two.withType", comment: "Two reactions with type"),
                            actors.primary,
                            reactionType.icon,
                            secondary
                        )
                    } else if let secondary = actors.secondary, actors.othersCount > 0 {
                        text = String(
                            format: NSLocalizedString("notifications.message.reaction.threePlus.withType", comment: "Three or more reactions with type"),
                            actors.primary,
                            reactionType.icon,
                            secondary,
                            actors.othersCount
                        )
                    } else {
                        text = String(
                            format: NSLocalizedString("notifications.message.reaction.multiple.withType", comment: "Multiple reactions with type"),
                            actors.primary,
                            reactionType.icon,
                            max(actors.othersCount, reactionAggregateCount - 1)
                        )
                    }
                    return styledNotificationMessage(
                        text,
                        boldNames: boldNames,
                        nameToUserId: nameToUserId,
                        baseColor: messageColor,
                        largeEmoji: reactionType.icon
                    )
                } else {
                    return notificationGroupedMessage(
                        twoKey: "notifications.message.reaction.two",
                        threePlusKey: "notifications.message.reaction.threePlus",
                        multipleKey: "notifications.message.reaction.multiple",
                        actors: actors,
                        nameToUserId: nameToUserId,
                        baseColor: messageColor
                    )
                }
            case .mention:
                return mentionMessage(for: firstNotification, actors: actors, nameToUserId: nameToUserId, baseColor: messageColor)
            case .newFollower:
                return notificationGroupedMessage(
                    twoKey: "notifications.message.follow.two",
                    threePlusKey: "notifications.message.follow.threePlus",
                    multipleKey: "notifications.message.follow.multiple",
                    actors: actors,
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .followRequest:
                return notificationGroupedMessage(
                    twoKey: "notifications.message.request.two",
                    threePlusKey: "notifications.message.request.threePlus",
                    multipleKey: "notifications.message.request.multiple",
                    actors: actors,
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .requestAccepted:
                return notificationGroupedMessage(
                    twoKey: "notifications.message.requestAccepted.two",
                    threePlusKey: "notifications.message.requestAccepted.threePlus",
                    multipleKey: "notifications.message.requestAccepted.multiple",
                    actors: actors,
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .mutualConnection:
                return notificationGroupedMessage(
                    twoKey: "notifications.message.mutual.two",
                    threePlusKey: "notifications.message.mutual.threePlus",
                    multipleKey: "notifications.message.mutual.multiple",
                    actors: actors,
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .comment:
                return commentMessage(for: firstNotification, actors: actors, nameToUserId: nameToUserId, baseColor: messageColor)
            case .storyReaction:
                return notificationGroupedMessage(
                    twoKey: "notifications.message.story.two",
                    threePlusKey: "notifications.message.story.threePlus",
                    multipleKey: "notifications.message.story.multiple",
                    actors: actors,
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .message:
                return styledNotificationMessage(
                    String(format: NSLocalizedString("notifications.message.message.multiple", comment: "Multiple messages"), effectiveSenderUsername, group.notifications.count - 1),
                    boldNames: [effectiveSenderUsername],
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .photoTag:
                return photoTagMessage(for: firstNotification, actors: actors, nameToUserId: nameToUserId, baseColor: messageColor)
            case .echoSuggestion:
                return AttributedString(NSLocalizedString("notifications.message.echo", comment: "Echo suggestion"))
            case .dataExportReady:
                let exportMessage = firstNotification.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if exportMessage.isEmpty {
                    return AttributedString(NSLocalizedString("notifications.message.dataExportReady", comment: "Data export ready notification"))
                }
                return AttributedString(exportMessage)
            case .storyChainContinued:
                let chainTitle = firstNotification.chainTitle ?? ""
                let isCreator = firstNotification.chainRole != "participant"
                let key = isCreator
                    ? "notifications.message.storyChain.creator.multiple"
                    : "notifications.message.storyChain.participant.multiple"
                return styledNotificationMessage(
                    String(format: NSLocalizedString(key, comment: "Multiple story chain continuations"), effectiveSenderUsername, chainTitle, group.notifications.count - 1),
                    boldNames: [effectiveSenderUsername],
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .mediaModeration:
                return AttributedString(NSLocalizedString("notifications.message.mediaModeration", comment: "Media moderation notification"))
            case .messageReaction, .chatBuzz, .gentleReminder:
                let copy = NotificationCopyResolver.resolve(firstNotification)
                return AttributedString(copy.body ?? copy.title)
            }
        } else {
            switch firstNotification.type {
            case .like:
                return styledNotificationMessage(
                    String(format: NSLocalizedString("notifications.message.like.single", comment: "Single like"), effectiveSenderUsername),
                    boldNames: [effectiveSenderUsername],
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .reaction:
                if let reactionString = firstNotification.reaction,
                   let reactionType = ReactionType(rawValue: reactionString) {
                    let text = String(format: NSLocalizedString("notifications.message.reaction.single.withType", comment: "Single reaction with type"), effectiveSenderUsername, reactionType.icon)
                    return styledNotificationMessage(
                        text,
                        boldNames: [effectiveSenderUsername],
                        nameToUserId: nameToUserId,
                        baseColor: messageColor,
                        largeEmoji: reactionType.icon
                    )
                } else {
                    return styledNotificationMessage(
                        String(format: NSLocalizedString("notifications.message.reaction.single", comment: "Single reaction"), effectiveSenderUsername),
                        boldNames: [effectiveSenderUsername],
                        nameToUserId: nameToUserId,
                        baseColor: messageColor
                    )
                }
            case .mention:
                return mentionMessage(for: firstNotification, actors: groupedActorsForMessage(), nameToUserId: nameToUserId, baseColor: messageColor)
            case .newFollower:
                return styledNotificationMessage(
                    String(format: NSLocalizedString("notifications.message.follow.single", comment: "Single follow"), effectiveSenderUsername),
                    boldNames: [effectiveSenderUsername],
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .followRequest:
                return styledNotificationMessage(
                    String(format: NSLocalizedString("notifications.message.request.single", comment: "Single request"), effectiveSenderUsername),
                    boldNames: [effectiveSenderUsername],
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .requestAccepted:
                return styledNotificationMessage(
                    String(format: NSLocalizedString("notifications.message.requestAccepted.single", comment: "Single accepted request"), effectiveSenderUsername),
                    boldNames: [effectiveSenderUsername],
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .mutualConnection:
                return styledNotificationMessage(
                    String(format: NSLocalizedString("notifications.message.mutual.single", comment: "Single mutual connection"), effectiveSenderUsername),
                    boldNames: [effectiveSenderUsername],
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .comment:
                return commentMessage(for: firstNotification, actors: groupedActorsForMessage(), nameToUserId: nameToUserId, baseColor: messageColor)
            case .storyReaction:
                return styledNotificationMessage(
                    String(format: NSLocalizedString("notifications.message.story.single", comment: "Single story reaction"), effectiveSenderUsername),
                    boldNames: [effectiveSenderUsername],
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .message:
                return styledNotificationMessage(
                    String(format: NSLocalizedString("notifications.message.message.single", comment: "Single message"), effectiveSenderUsername),
                    boldNames: [effectiveSenderUsername],
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .photoTag:
                return photoTagMessage(for: firstNotification, actors: groupedActorsForMessage(), nameToUserId: nameToUserId, baseColor: messageColor)
            case .echoSuggestion:
                return AttributedString(NSLocalizedString("notifications.message.echo", comment: "Echo suggestion"))
            case .dataExportReady:
                let exportMessage = firstNotification.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if exportMessage.isEmpty {
                    return AttributedString(NSLocalizedString("notifications.message.dataExportReady", comment: "Data export ready notification"))
                }
                return AttributedString(exportMessage)
            case .storyChainContinued:
                let chainTitle = firstNotification.chainTitle ?? ""
                let isCreator = firstNotification.chainRole != "participant"
                let totalParts = firstNotification.totalParts ?? firstNotification.chainPosition ?? 1
                let key = isCreator
                    ? "notifications.message.storyChain.creator.single"
                    : "notifications.message.storyChain.participant.single"
                return styledNotificationMessage(
                    String(format: NSLocalizedString(key, comment: "Single story chain continuation"), effectiveSenderUsername, chainTitle, totalParts),
                    boldNames: [effectiveSenderUsername],
                    nameToUserId: nameToUserId,
                    baseColor: messageColor
                )
            case .mediaModeration:
                return AttributedString(NSLocalizedString("notifications.message.mediaModeration", comment: "Media moderation notification"))
            case .messageReaction, .chatBuzz, .gentleReminder:
                let copy = NotificationCopyResolver.resolve(firstNotification)
                return AttributedString(copy.body ?? copy.title)
            }
        }
    }

    func mentionMessage(
        for notification: Notification,
        actors: NotificationGroupedActors,
        nameToUserId: [String: String],
        baseColor: Color
    ) -> AttributedString {
        let context = notification.mentionContext
            ?? (notification.storyId != nil ? "story" : (notification.commentId != nil ? "comment" : "moment"))

        let keyPrefix: String
        switch context {
        case "story":
            keyPrefix = "notifications.message.mention.story"
        case "comment":
            keyPrefix = notification.targetAuthorUsername?.isEmpty == false
                ? "notifications.message.mention.comment.withAuthor"
                : "notifications.message.mention.comment"
        default:
            keyPrefix = "notifications.message.mention.moment"
        }

        func boldMentionNames(extra: String? = nil) -> [String] {
            var names = [actors.primary]
            if let secondary = actors.secondary { names.append(secondary) }
            if let extra, !extra.isEmpty { names.append(extra) }
            return names
        }

        if actors.hasExactlyTwo, let secondary = actors.secondary {
            if context == "comment", let targetAuthorUsername = notification.targetAuthorUsername, !targetAuthorUsername.isEmpty {
                return styledNotificationMessage(
                    String(
                        format: NSLocalizedString("\(keyPrefix).two", comment: "Two mentions with moment author"),
                        actors.primary,
                        secondary,
                        targetAuthorUsername
                    ),
                    boldNames: boldMentionNames(extra: targetAuthorUsername),
                    nameToUserId: nameToUserId,
                    baseColor: baseColor
                )
            }
            return styledNotificationMessage(
                String(
                    format: NSLocalizedString("\(keyPrefix).two", comment: "Two contextual mentions"),
                    actors.primary,
                    secondary
                ),
                boldNames: boldMentionNames(),
                nameToUserId: nameToUserId,
                baseColor: baseColor
            )
        }

        if let secondary = actors.secondary, actors.othersCount > 0 {
            if context == "comment", let targetAuthorUsername = notification.targetAuthorUsername, !targetAuthorUsername.isEmpty {
                return styledNotificationMessage(
                    String(
                        format: NSLocalizedString("\(keyPrefix).threePlus", comment: "Three or more mentions with moment author"),
                        actors.primary,
                        secondary,
                        actors.othersCount,
                        targetAuthorUsername
                    ),
                    boldNames: boldMentionNames(extra: targetAuthorUsername),
                    nameToUserId: nameToUserId,
                    baseColor: baseColor
                )
            }
            return styledNotificationMessage(
                String(
                    format: NSLocalizedString("\(keyPrefix).threePlus", comment: "Three or more contextual mentions"),
                    actors.primary,
                    secondary,
                    actors.othersCount
                ),
                boldNames: boldMentionNames(),
                nameToUserId: nameToUserId,
                baseColor: baseColor
            )
        }

        if actors.othersCount > 0 {
            if context == "comment", let targetAuthorUsername = notification.targetAuthorUsername, !targetAuthorUsername.isEmpty {
                return styledNotificationMessage(
                    String(
                        format: NSLocalizedString("\(keyPrefix).multiple", comment: "Multiple contextual comment mentions with moment author"),
                        actors.primary,
                        actors.othersCount,
                        targetAuthorUsername
                    ),
                    boldNames: boldMentionNames(extra: targetAuthorUsername),
                    nameToUserId: nameToUserId,
                    baseColor: baseColor
                )
            }

            return styledNotificationMessage(
                String(
                    format: NSLocalizedString("\(keyPrefix).multiple", comment: "Multiple contextual mentions"),
                    actors.primary,
                    actors.othersCount
                ),
                boldNames: boldMentionNames(),
                nameToUserId: nameToUserId,
                baseColor: baseColor
            )
        }

        if context == "comment", let targetAuthorUsername = notification.targetAuthorUsername, !targetAuthorUsername.isEmpty {
            return styledNotificationMessage(
                String(
                    format: NSLocalizedString("\(keyPrefix).single", comment: "Single contextual comment mention with moment author"),
                    actors.primary,
                    targetAuthorUsername
                ),
                boldNames: boldMentionNames(extra: targetAuthorUsername),
                nameToUserId: nameToUserId,
                baseColor: baseColor
            )
        }

        return styledNotificationMessage(
            String(
                format: NSLocalizedString("\(keyPrefix).single", comment: "Single contextual mention"),
                actors.primary
            ),
            boldNames: boldMentionNames(),
            nameToUserId: nameToUserId,
            baseColor: baseColor
        )
    }

    func photoTagMessage(
        for notification: Notification,
        actors: NotificationGroupedActors,
        nameToUserId: [String: String],
        baseColor: Color
    ) -> AttributedString {
        let momentTitle = notification.reaction?.trimmingCharacters(in: .whitespacesAndNewlines)

        func boldTagNames() -> [String] {
            var names = [actors.primary]
            if let secondary = actors.secondary { names.append(secondary) }
            return names
        }

        if actors.hasExactlyTwo, let secondary = actors.secondary {
            if let momentTitle, !momentTitle.isEmpty {
                return styledNotificationMessage(
                    String(
                        format: NSLocalizedString("notifications.message.tagged.withTitle.two", comment: "Two photo tags with moment title"),
                        actors.primary,
                        secondary,
                        momentTitle
                    ),
                    boldNames: boldTagNames(),
                    nameToUserId: nameToUserId,
                    baseColor: baseColor
                )
            }
            return styledNotificationMessage(
                String(
                    format: NSLocalizedString("notifications.message.tagged.two", comment: "Two photo tags"),
                    actors.primary,
                    secondary
                ),
                boldNames: boldTagNames(),
                nameToUserId: nameToUserId,
                baseColor: baseColor
            )
        }

        if let secondary = actors.secondary, actors.othersCount > 0 {
            if let momentTitle, !momentTitle.isEmpty {
                return styledNotificationMessage(
                    String(
                        format: NSLocalizedString("notifications.message.tagged.withTitle.threePlus", comment: "Three or more photo tags with moment title"),
                        actors.primary,
                        secondary,
                        actors.othersCount,
                        momentTitle
                    ),
                    boldNames: boldTagNames(),
                    nameToUserId: nameToUserId,
                    baseColor: baseColor
                )
            }
            return styledNotificationMessage(
                String(
                    format: NSLocalizedString("notifications.message.tagged.threePlus", comment: "Three or more photo tags"),
                    actors.primary,
                    secondary,
                    actors.othersCount
                ),
                boldNames: boldTagNames(),
                nameToUserId: nameToUserId,
                baseColor: baseColor
            )
        }

        if actors.othersCount > 0 {
            if let momentTitle, !momentTitle.isEmpty {
                return styledNotificationMessage(
                    String(
                        format: NSLocalizedString("notifications.message.tagged.withTitle.multiple", comment: "Multiple photo tags with moment title"),
                        actors.primary,
                        actors.othersCount,
                        momentTitle
                    ),
                    boldNames: [actors.primary],
                    nameToUserId: nameToUserId,
                    baseColor: baseColor
                )
            }

            return styledNotificationMessage(
                String(
                    format: NSLocalizedString("notifications.message.tagged.multiple", comment: "Multiple photo tags"),
                    actors.primary,
                    actors.othersCount
                ),
                boldNames: [actors.primary],
                nameToUserId: nameToUserId,
                baseColor: baseColor
            )
        }

        if let momentTitle, !momentTitle.isEmpty {
            return styledNotificationMessage(
                String(
                    format: NSLocalizedString("notifications.message.tagged.withTitle.single", comment: "Single photo tag with moment title"),
                    actors.primary,
                    momentTitle
                ),
                boldNames: [actors.primary],
                nameToUserId: nameToUserId,
                baseColor: baseColor
            )
        }

        return styledNotificationMessage(
            String(
                format: NSLocalizedString("notifications.message.tagged.single", comment: "Single photo tag"),
                actors.primary
            ),
            boldNames: [actors.primary],
            nameToUserId: nameToUserId,
            baseColor: baseColor
        )
    }

    func commentMessage(
        for notification: Notification,
        actors: NotificationGroupedActors,
        nameToUserId: [String: String],
        baseColor: Color
    ) -> AttributedString {
        let keyPrefix = notification.mentionContext == "reply"
            ? "notifications.message.reply"
            : "notifications.message.comment"

        func boldCommentNames() -> [String] {
            var names = [actors.primary]
            if let secondary = actors.secondary { names.append(secondary) }
            return names
        }

        if actors.hasExactlyTwo, let secondary = actors.secondary {
            return styledNotificationMessage(
                String(
                    format: NSLocalizedString("\(keyPrefix).two", comment: "Two comments or replies"),
                    actors.primary,
                    secondary
                ),
                boldNames: boldCommentNames(),
                nameToUserId: nameToUserId,
                baseColor: baseColor
            )
        }

        if let secondary = actors.secondary, actors.othersCount > 0 {
            return styledNotificationMessage(
                String(
                    format: NSLocalizedString("\(keyPrefix).threePlus", comment: "Three or more comments or replies"),
                    actors.primary,
                    secondary,
                    actors.othersCount
                ),
                boldNames: boldCommentNames(),
                nameToUserId: nameToUserId,
                baseColor: baseColor
            )
        }

        if actors.othersCount > 0 {
            return styledNotificationMessage(
                String(
                    format: NSLocalizedString("\(keyPrefix).multiple", comment: "Multiple comments or replies"),
                    actors.primary,
                    actors.othersCount
                ),
                boldNames: [actors.primary],
                nameToUserId: nameToUserId,
                baseColor: baseColor
            )
        }

        return styledNotificationMessage(
            String(
                format: NSLocalizedString("\(keyPrefix).single", comment: "Single comment or reply"),
                actors.primary
            ),
            boldNames: [actors.primary],
            nameToUserId: nameToUserId,
            baseColor: baseColor
        )
    }

}
