# Notification System Stabilization Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to implement this plan task-by-task. Keep changes small and verify after each notification family.

**Goal:** Stabilize the rest of Glowsy's notification system after the mention/tag pass, without redoing the completed work for story mentions, post tags, comment mentions, and comment replies.

**Scope:** Push payload routing, in-app banners, notification list grouping, badge counts, writers, privacy/mute settings, and cleanup for reactions, follows, requests, messages, profile visits, Echo, story chains, data export, and media moderation.

**Out of scope for this plan:** Rebuilding the already-completed mention/tag/comment/reply flow from `2026-05-20-mentions-notification-system.md`, except for legacy cleanup and regression checks.

---

## Current Diagnosis

The previous plan covered:
- Story mention stickers, including `storyAuthorId` and audience checks.
- Post photo tags as `.photoTag`, separate from text mentions.
- Comment mentions with validated mention entities.
- Replies to comments with `mentionContext = "reply"`.
- Context-aware copy, previews, banners, push payloads, and QA for those flows.

What still needs attention:
- `NotificationType` stored in Firestore is mostly camelCase (`storyReaction`, `followRequest`, `newFollower`), while push data uses snake_case (`story_reaction`, `follow_request`, `new_follower`). `NotificationNavigationService` only handles part of that matrix.
- Story push/banner navigation still only carries `storyId` in the global router. The list can fetch with author context, but push tap and banner tap can still lose `storyAuthorId`.
- Notification creation is split between client code and Cloud Functions. Some families are server-owned, some are client-owned, and some are mixed.
- `requestAccepted` now needs to remain server-owned after accepting a follow request, so DND/mute/server idempotency stay centralized.
- Profile visit notifications now use a stable `yyyy-MM-dd` day key instead of a localized `DateFormatter.short` value.
- Messages now have a real `conversationId` field, with `momentId` only kept as a legacy fallback.
- Media moderation, Echo suggestions, story chains, data export, and gentle reminders need a routing/copy/settings audit so they do not regress as we keep adding richer notification behavior.

---

## Task 1: Build A Notification Contract Matrix

**Files:**
- Add or update: `docs/notifications/notification-contract.md`
- Read: `Glowsy/Models/Models.swift`
- Read: `functions/index.js`
- Read: `Glowsy/Notifications/NotificationNavigationService.swift`
- Read: `Glowsy/Views/Components/InAppBannerView.swift`

- [x] List every notification family and its canonical Firestore `NotificationType`.
- [x] List every push `data.type` sent by Functions.
- [x] List required routing fields per family: `momentId`, `targetAuthorId`, `storyId`, `storyAuthorId`, `conversationId`, `requestId`, `echoId`, `chainId`.
- [x] List preview source per family: moment preview, story thumbnail, profile avatar, system icon, none.
- [x] Mark owner for creation: client, Functions, scheduled function, or local-only banner.

Expected result:
- One table becomes the source of truth before code changes.
- Any future notification must add a row before implementation.

---

## Task 2: Normalize Push Routing Types

**Files:**
- Modify: `Glowsy/Notifications/NotificationNavigationService.swift`
- Reference: `functions/index.js`

- [x] Add a small normalization layer that accepts both server push names and Firestore raw values:

```swift
private func normalizedType(_ rawType: String) -> String
```

- [x] Map these aliases:

```text
moment_reaction -> reaction
moment_comment -> comment
story_reaction -> storyReaction
story_chain_continued -> storyChainContinued
new_follower -> newFollower
follow_request -> followRequest
new_message -> message
photo_tag -> photoTag
media_moderation -> mediaModeration
echo_suggestion -> echoSuggestion
```

- [x] Keep current legacy names working.
- [x] Make `handleNotificationData(_:)` switch on normalized type.
- [x] For unknown types, route to `.notifications(nil)` and log the raw type in debug builds only.

Expected result:
- Push taps and app-open navigation do not depend on whether the payload came from old Functions, new Functions, or a local Firestore document.

---

## Task 3: Make Story Routing Author-Aware Everywhere

**Files:**
- Modify: `Glowsy/Notifications/NotificationNavigationService.swift`
- Modify: `Glowsy/Views/Components/InAppBannerView.swift`
- Modify: `Glowsy/Views/Feed/Core/FeedNotificationRoutingModifier.swift`

- [x] Change pending story navigation from:

```swift
case story(String)
```

to:

```swift
case story(storyId: String, authorId: String?)
```

- [x] Add:

```swift
func navigateToStory(storyId: String, authorId: String?)
```

and keep the old `navigateToStory(storyId:)` as a wrapper.

- [x] Route story reactions with `storyOwnerId`, `storyAuthorId`, `targetAuthorId`, or `senderId` fallback.
- [x] Route story mentions with `storyAuthorId`, then `targetAuthorId`, then `senderId`.
- [x] Route story chain fallback with `senderId` only if no `chainId` exists.
- [x] Update `FeedNotificationRoutingModifier` so it opens the story fullscreen flow with the resolved author context.

Expected result:
- Story-related push taps and banner taps no longer open blank stories or rely on refetching under the current user.

---

## Task 4: Decide Single Writer Per Notification Family

**Files:**
- Modify: `Glowsy/Notifications/Notificationservice.swift`
- Modify: `Glowsy/Services/Firestore/FirestoreService.swift`
- Modify: `functions/index.js`

- [ ] Mark these as server-owned in the contract:

```text
reaction
comment
storyReaction
newFollower
followRequest
mutualConnection
message push
mediaModeration
echoSuggestion
storyChainContinued
dataExportReady
gentleReminder
```

- [ ] Mark these as client-owned only if we deliberately keep them client-side:

```text
mention
photoTag
profileVisit
requestAccepted
local in-app message banner
```

- [x] Audit `NotificationService.sendInteractionNotification` call sites and remove or redirect legacy writers that overlap with Functions.
- [x] Specifically review `FirestoreService.notifyUserMention(...)`; it still sends a generic `.mention` and should either be removed or routed through the new typed comment mention flow if unused.
- [x] Decide whether `requestAccepted` should move to Functions. Preferred: server-owned, triggered when the follower relationship is created or the request state changes.

Expected result:
- One event creates one notification document.
- One notification document triggers at most one push.
- We stop accumulating "works but duplicated later" paths.

---

## Task 5: Stabilize Moment Reactions

**Files:**
- Modify: `functions/index.js`
- Modify: `Glowsy/Notifications/NotificationsView.swift`
- Modify: `Glowsy/Views/Components/InAppBannerView.swift`

- [ ] Keep the current Instagram-like aggregate document id: `reaction_{momentId}`.
- [ ] Verify remove reaction updates or deletes only that aggregate notification.
- [ ] Verify the app decodes `reactionType` into `Notification.reaction`.
- [ ] Ensure the Reactions tab includes only `.reaction`, not comment likes.
- [ ] Confirm banner color/icon/copy for moment reactions matches the list.
- [ ] Add or verify regression test steps:

```text
1 reaction -> single copy.
2 reactions same moment -> one grouped row.
Remove visible actor reaction -> row picks latest remaining actor.
Remove final reaction -> row disappears.
```

Expected result:
- Moment reactions behave as one grouped row per moment, never as a pile of duplicate rows.

---

## Task 6: Stabilize Comments And Comment Likes

**Files:**
- Modify: `functions/index.js`
- Modify: `Glowsy/Notifications/NotificationsView.swift`
- Modify: comment-like writer if found

- [ ] Keep `.comment` for direct comments on your moment.
- [ ] Keep `.like` only for likes/reactions on comments, not moment reactions.
- [ ] Verify comment reply notifications remain covered by the previous plan using `mentionContext = "reply"`.
- [ ] Ensure direct comment push uses `targetAuthorId` or `momentOwnerId` consistently so push tap opens the right moment.
- [ ] Confirm comment preview text uses the comment body, but the row preview image uses the moment media.
- [ ] Check if comment-like notifications have a Function writer or client writer. Pick one.

Expected result:
- Direct comments, comment replies, comment mentions, and comment likes remain separate concepts in copy and routing.

---

## Task 7: Stabilize Follow, Request, Accepted, And Mutual Connection

**Files:**
- Modify: `functions/index.js`
- Modify: `Glowsy/Services/Firestore/FirestoreService.swift`
- Modify: `Glowsy/Notifications/NotificationsView.swift`
- Modify: `Glowsy/Notifications/NotificationNavigationService.swift`

- [x] Keep `followRequest` in the Requests tab and route push taps to requests.
- [x] When a request is accepted or rejected, remove the pending request notification.
- [x] Move `requestAccepted` to server-owned if feasible so DND/mute and idempotency are centralized.
- [x] Normalize `new_follower`, `newFollower`, `follow_request`, `followRequest`, `mutualConnection`, and `requestAccepted` in push routing.
- [ ] Decide if mutual connection should be localized through APNs loc keys instead of hardcoded Spanish in Functions.
- [ ] Verify unfollow cleanup removes stale `.newFollower` notifications if that is still product-intended.

Expected result:
- Follow-related notifications feel like one coherent social system, not three different implementations.

---

## Task 8: Stabilize Messages And Local In-App Banners

**Files:**
- Modify: `Glowsy/Notifications/InAppNotificationService.swift`
- Modify: `Glowsy/Models/Models.swift` if adding `conversationId`
- Modify: `Glowsy/Views/Components/InAppBannerView.swift`
- Modify: `functions/index.js`

- [x] Add `conversationId` to `Notification` or introduce a lightweight local banner model.
- [x] Stop storing local message banner routing in `momentId` unless we explicitly document it as a temporary compatibility bridge.
- [x] Keep push payload `type = new_message` and `conversationId`.
- [x] Make in-app banner and push tap route through the same navigation case.
- [x] Verify muted conversation logic exists in Functions and local banner listener. If local banner ignores muted conversations, fix it or remove local message banners.

Expected result:
- Messages do not abuse moment fields and do not show in-app banners for conversations the user muted.

---

## Task 9: Stabilize Profile Visits

**Files:**
- Modify: `Glowsy/Notifications/Notificationservice.swift`
- Modify: `Glowsy/Notifications/NotificationsView.swift`

- [x] Replace localized `DateFormatter.localizedString(..., .short, ...)` in `updateVisitNotification` with a stable id format:

```text
visit_yyyy-MM-dd
```

- [ ] Use a fixed calendar/time zone decision:

```text
Europe/Madrid if product-day based, or UTC if data-retention based.
```

- [ ] Confirm profile visits should not send push unless product explicitly wants it.
- [ ] Group visits by day in the list as today already does.
- [ ] Keep old localized ids readable; do not migrate unless necessary.

Expected result:
- Visit aggregation does not break when device locale/date format changes.

---

## Task 10: Audit System Notifications

**Files:**
- Modify: `functions/index.js`
- Modify: `Glowsy/Notifications/NotificationsView.swift`
- Modify: `Glowsy/Views/Components/InAppBannerView.swift`
- Modify: `Glowsy/*/Localizable.strings`

- [ ] Media moderation:
  - Verify push type `media_moderation` maps to `.mediaModeration`.
  - Verify post/story/storySticker/postHiddenLayer copy is localized.
  - Verify tapping routes to the moderated moment or story when possible, otherwise notifications.

- [ ] Data export:
  - Verify `.dataExportReady` appears in All and has a working download action.
  - Verify push routing opens notifications or a dedicated export destination.

- [ ] Echo suggestion:
  - Verify `echo_suggestion` maps to `.echoSuggestion`.
  - Verify pending navigation opens the Echo flow.
  - Verify badge `unreadEchoes` is updated.

- [ ] Story chain continued:
  - Verify `story_chain_continued` maps to `.storyChainContinued`.
  - Verify chain fallback does not use story viewer without author context.

- [ ] Gentle reminders:
  - Confirm they are push-only and do not create notification rows unless intended.

Expected result:
- System notifications are boring in the best way: predictable, localized, and routable.

---

## Task 11: Notification Settings And Silence Rules

**Files:**
- Read/modify: `Glowsy/Views/Settings/SettingsSections/NotificationSettingsView.swift`
- Modify: `functions/index.js`
- Modify: `Glowsy/Notifications/InAppNotificationService.swift`

- [ ] Create a settings matrix:

```text
notification family -> user setting -> server check -> local banner check
```

- [ ] Verify DND is respected by all push-sending Functions.
- [ ] Verify muted account/content filters use `shouldSilenceNotificationForUser(...)` for all relevant social notifications.
- [ ] Verify muted conversations are respected by message push and local in-app banners.
- [ ] Decide whether local-only in-app banners should also honor DND. Preferred: yes, unless foreground app behavior intentionally ignores DND.
- [ ] Ensure deleting a notification or marking as read updates badge counts consistently.

Expected result:
- User settings mean the same thing whether the notification arrives as push, row, badge, or in-app banner.

---

## Task 12: Routing Regression QA

**Files:**
- No code changes.

- [ ] Push tap from killed app:
  - moment reaction -> moment
  - direct comment -> moment
  - story reaction -> story viewer with correct author
  - story mention -> story viewer with correct author
  - follow request -> requests tab
  - new follower -> profile
  - message -> conversation
  - media moderation -> content or notifications fallback
  - echo suggestion -> Echo flow

- [ ] In-app banner tap:
  - same routes as push tap.

- [ ] Notification list tap:
  - same routes as push tap.

- [ ] Badge:
  - pending rows match app badge/widget counts after receiving, opening, marking read, and deleting.

- [ ] Settings:
  - DND and mute suppress push.
  - Muted conversations suppress message push and local banner.

---

## Validation Commands

Use focused validation unless a full build is necessary:

```bash
node --check functions/index.js
for f in Glowsy/*.lproj/Localizable.strings; do plutil -lint "$f"; done
xcrun swiftc -parse Glowsy/Notifications/NotificationNavigationService.swift Glowsy/Notifications/Notificationservice.swift Glowsy/Notifications/InAppNotificationService.swift Glowsy/Views/Components/InAppBannerView.swift Glowsy/Notifications/NotificationsView.swift Glowsy/Models/Models.swift
```

Only run the full Xcode build when changing shared models/navigation signatures or when parse checks cannot catch the integration risk.

---

## Suggested Implementation Order

1. Task 1: contract matrix.
2. Task 2: normalize push type routing.
3. Task 3: author-aware story routing.
4. Task 4: single-writer audit and legacy cleanup.
5. Task 5 and Task 6: reactions/comments family pass.
6. Task 7: follows/requests family pass.
7. Task 8: messages family pass.
8. Task 9 and Task 10: profile visits/system notifications.
9. Task 11: settings/silence parity.
10. Task 12: manual QA.

---

## Self-Review

- This plan does not duplicate the previous mention/tag/comment/reply plan.
- It focuses on the remaining fragile parts: type contracts, routing, ownership, settings, and system families.
- Highest risk changes are `PendingNavigation.story` signature and moving `requestAccepted` to Functions.
- Highest value quick win is Task 2: normalize push type routing before deeper cleanup.
