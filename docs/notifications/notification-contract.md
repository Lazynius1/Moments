# Glowsy Notification Contract

This document is the routing contract for Glowsy notifications. Any new notification family should add or update a row here before app, Functions, or localization changes.

## Naming Rules

- Firestore `Notification.type` uses the Swift `NotificationType` raw value.
- Push payload `data.type` can use server-style snake_case for backward compatibility.
- `NotificationNavigationService` must normalize both forms before routing.
- Localizable keys follow the existing style:
  - List rows: `notifications.message.<family>.<context>.<variant>`
  - In-app banner verbs: `banner.verb.<family>.<context>`
  - Push titles/bodies: `notification.<family>.<context>.title` and `notification.<family>.body`

## Families

| Family | Firestore type | Push `data.type` | Required routing fields | Preview | Writer |
| --- | --- | --- | --- | --- | --- |
| Moment reaction | `reaction` | `moment_reaction` | `momentId`, `momentOwnerId` or `targetAuthorId` | Moment media | Functions |
| Direct moment comment | `comment` | `moment_comment` | `momentId`, `momentOwnerId` or `targetAuthorId`, `commentId` | Moment media | Functions |
| Comment reply | `comment` + `mentionContext = reply` | `moment_comment` | `momentId`, `targetAuthorId`, `commentId` | Moment media | Client doc, Functions push |
| Comment mention | `mention` + `mentionContext = comment` | `mention` | `momentId`, `targetAuthorId`, `commentId` | Moment media | Client doc, Functions push |
| Moment/caption mention | `mention` + `mentionContext = moment` | `mention` | `momentId`, `targetAuthorId` | Moment media | Client doc, Functions push |
| Story mention | `mention` + `mentionContext = story` | `mention` | `storyId`, `storyAuthorId` or `targetAuthorId` | Story media | Client doc, Functions push |
| Photo tag | `photoTag` | `photo_tag` | `momentId` or `targetId`, `targetAuthorId` or `senderId` | Moment media | Client doc, Functions push |
| Story reaction | `storyReaction` | `story_reaction` | `storyId`, `storyOwnerId` or `storyAuthorId` | Story media | Functions |
| Story chain continued | `storyChainContinued` | `story_chain_continued` | `chainId`; fallback `storyId`, `senderId` | Story media or chain icon | Functions |
| New follower | `newFollower` | `new_follower` | `senderId` or `followerId` | Profile avatar | Functions |
| Follow request | `followRequest` | `follow_request` | `requestId`, `senderId` | Profile avatar | Functions |
| Request accepted | `requestAccepted` | `requestAccepted` | `senderId`, optional `requestId` | Profile avatar | Functions |
| Mutual connection | `mutualConnection` | `mutualConnection` | `senderId` | Profile avatar | Functions |
| Profile visit | `profileVisit` | none by default | `senderId`, `visitCount` | Profile avatar | Client |
| Message | local `.message` banner or push-only | `new_message` | `conversationId` | Profile avatar | Functions push, local foreground banner |
| Echo suggestion | `echoSuggestion` | `echo_suggestion` | `echoId` | Echo/system icon | Functions |
| Data export ready | `data_export_ready` | `data_export_ready` | `downloadURL` | System icon | Functions/manual service |
| Media moderation | `mediaModeration` | `media_moderation` | `momentId` or `storyId`, `moderationScope` | System icon or moderated content | Functions |
| Gentle reminder | no row by default | `gentle_reminder` | none | none | Scheduled Functions push |

## Current Sharp Edges

- Local message banners now use `conversationId`; `momentId` remains only as a legacy compatibility fallback.
- Profile visit document ids use a stable `yyyy-MM-dd` day key instead of localized short date formatting.
- Story routing must always carry `authorId` when available; `storyId` alone is not enough in a user-subcollection model.
