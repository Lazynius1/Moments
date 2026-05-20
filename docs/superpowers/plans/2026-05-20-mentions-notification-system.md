# Mentions Notification System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make story mentions, post tags/mentions, and comment mentions behave consistently, with correct previews, push copy, routing, and privacy-aware targets.

**Architecture:** Centralize mention notification creation through typed notification context instead of treating every mention as the same `.mention`. Keep client-side creation for v1, but write richer notification documents so Cloud Functions and the notification list can route correctly. Story mentions must carry `storyAuthorId`; comment mentions must carry `commentId`; post mentions/tags must carry `momentId` and a clear origin.

**Tech Stack:** SwiftUI, Firebase Auth, Firestore, Firebase Cloud Functions, APNs/FCM localized push payloads, `Localizable.strings`.

---

## Current Diagnosis

Instagram separates these concepts:
- Story mention: opens the story from the author, often behaves like a story/DM-style mention, and the mentioned user gets a direct contextual notification.
- Post tag: tied to a post and can appear in tagged content, subject to privacy.
- Comment/caption mention: tied to the comment/post surface, not the same UX as a story mention.

Our current system is too generic:
- Story mention notifications are created as `.mention` with only `storyId`, so the notification list tries to infer the author.
- `NotificationsView.navigateToStory(storyId:)` falls back to `users/{currentUserId}/stories/{storyId}`, which is wrong when another user mentioned you.
- Story previews already try `storyAuthorId ?? senderId`, but `storyAuthorId` is not written by `NotificationService.sendMentionNotification`.
- Comment mentions and story mentions both show `%@ te mencionó`, with no context.
- The notifications tab groups `.mention` into the comments tab, so story mentions are hidden in the wrong mental bucket.
- Push copy uses one generic `notification.mention.title` and passes a raw Spanish `contentType` from Functions, instead of using specific localized keys.
- Story mention privacy should not bypass the selected story audience: mentioned users only get notified if they can view that story under its audience rules.

## File Structure

- Modify `Glowsy/Models/Models.swift`
  Add lightweight notification context fields without breaking old docs.

- Modify `Glowsy/Notifications/Notificationservice.swift`
  Add explicit APIs for story mentions, moment mentions, and comment mentions.

- Modify `Glowsy/Views/Creator/Components/StickerPickerSupportExtensions.swift`
  Pass story author context when creating story mention notifications.

- Modify `Glowsy/Views/Creator/BackgroundStoryUploadService.swift`
  Call the richer story mention API after the story document exists.

- Modify `Glowsy/Services/Firestore/FirestoreCommentsRepository.swift`
  Include `commentId` and context when creating comment mention notifications.

- Modify `Glowsy/Views/Creator/BackgroundMomentUploadService.swift`
  Keep `.photoTag` for actual tagged users, but write richer context for notification routing.

- Modify `Glowsy/Notifications/NotificationsView.swift`
  Fix preview, routing, grouping, tab placement, and copy for mention contexts.

- Modify `Glowsy/Views/Components/InAppBannerView.swift`
  Make live in-app banners use the same mention context, preview, copy, and routing as the notifications list.

- Modify `Glowsy/Notifications/InAppNotificationService.swift`
  Keep banner delivery intact while ensuring decoded notification IDs and new context fields survive.

- Modify `functions/index.js`
  Use context-aware push payloads and include `storyAuthorId`/`commentId` in data payloads.

- Modify `Glowsy/*/Localizable.strings`
  Add or adjust strings for story mention, comment mention, post mention, and photo tag push/list copy.

## Task 1: Add Typed Mention Context

**Files:**
- Modify: `Glowsy/Models/Models.swift`
- Modify: `Glowsy/Notifications/Notificationservice.swift`

- [ ] **Step 1: Extend `Notification` with optional context**

Add optional fields:

```swift
let mentionContext: String?
let targetAuthorId: String?
```

Encoding/decoding:

```swift
case mentionContext
case targetAuthorId
```

Backward compatibility:
- Existing notifications decode with `nil`.
- `storyAuthorId` remains supported, but new code can use `targetAuthorId` as generic routing metadata.

- [ ] **Step 2: Add context-specific notification methods**

Add methods in `NotificationService`:

```swift
func sendStoryMentionNotification(to userId: String, storyId: String, storyAuthorId: String)
func sendMomentMentionNotification(to userId: String, momentId: String, commentText: String?)
func sendCommentMentionNotification(to userId: String, momentId: String, commentId: String, commentText: String?)
```

Each method creates `.mention` but sets:
- story mention: `storyId`, `storyAuthorId`, `targetAuthorId`, `mentionContext = "story"`
- moment mention: `momentId`, `mentionContext = "moment"`
- comment mention: `momentId`, `commentId`, `reaction/comment text`, `mentionContext = "comment"`

- [ ] **Step 3: Keep legacy API as wrapper**

Keep:

```swift
func sendMentionNotification(to userId: String, momentId: String? = nil, storyId: String? = nil)
```

But route to the new methods when enough data is available, otherwise write a legacy `.mention`.

- [ ] **Step 4: Validate decoding**

Run:

```bash
swiftc -parse Glowsy/Models/Models.swift Glowsy/Notifications/Notificationservice.swift
```

Expected: parse succeeds.

## Task 2: Fix Story Mention Creation

**Files:**
- Modify: `Glowsy/Views/Creator/Components/StickerPickerSupportExtensions.swift`
- Modify: `Glowsy/Views/Creator/BackgroundStoryUploadService.swift`

- [ ] **Step 1: Change helper signature**

Change:

```swift
static func sendMentionNotificationsForStory(storyId: String, stickers: [StickerItem])
```

To:

```swift
static func sendMentionNotificationsForStory(storyId: String, storyAuthorId: String, stickers: [StickerItem])
```

- [ ] **Step 2: Use the new story mention API**

Inside the helper:

```swift
NotificationService.shared.sendStoryMentionNotification(
    to: userId,
    storyId: storyId,
    storyAuthorId: storyAuthorId
)
```

Also dedupe mention recipients with `Set` so one user mentioned twice in the same story gets one notification.

- [ ] **Step 3: Filter mentioned users by story audience**

Before sending, apply the same privacy rule as story viewing:
- `everyone`: mention can notify.
- `connections`, `bestFriends`, `customList`: mention can notify only if the mentioned user belongs to that audience.
- `onlyMe`: never notify mentions.

For v1, if the local upload service already has enough audience metadata, filter locally before writing notifications. If it does not have enough metadata, add a small helper in the story upload path that checks the chosen audience before creating each mention notification.

- [ ] **Step 4: Track skipped mention notifications for future UX**

When a mention is skipped because the mentioned user is outside the selected audience, keep an internal count/result from the mention notification helper:

```swift
struct StoryMentionNotificationResult {
    let sentUserIds: [String]
    let skippedOutsideAudienceUserIds: [String]
}
```

Do not show UI in v1 unless it is trivial. This result exists so a later UX pass can show a creator-facing hint.

- [ ] **Step 5: Update caller after story creation**

In `BackgroundStoryUploadService.processInteractiveStickers`, pass the publishing user:

```swift
StickerPickerView.sendMentionNotificationsForStory(
    storyId: storyId,
    storyAuthorId: currentUserId,
    stickers: mentionStickers
)
```

Use the actual upload owner already available on the upload story object.

- [ ] **Step 6: Verify no old signature remains**

Run:

```bash
rg -n "sendMentionNotificationsForStory" Glowsy
```

Expected: only the new signature and updated call sites appear.

## Task 3: Fix Story Mention Preview and Routing

**Files:**
- Modify: `Glowsy/Notifications/NotificationsView.swift`
- Modify: `Glowsy/Notifications/NotificationNavigationService.swift` if push routing needs author context.

- [ ] **Step 1: Route story mention by author**

In `handleNotificationTap`, for `.mention` with `storyId`, resolve:

```swift
let authorId = firstNotification.storyAuthorId ?? firstNotification.targetAuthorId ?? firstNotification.senderId
```

Then fetch:

```swift
users/{authorId}/stories/{storyId}
```

Do not use the current user as fallback unless the sender is missing.

- [ ] **Step 2: Reuse same author logic for preview**

Update `fetchStoryPreview(storyId:)` to use the same helper:

```swift
private func storyAuthorId(for notification: Notification) -> String {
    notification.storyAuthorId ?? notification.targetAuthorId ?? notification.senderId
}
```

- [ ] **Step 3: Show story preview for mention**

In `setupPreviews`, include:

```swift
first.type == .mention && first.storyId != nil
```

So story mentions get the same story thumbnail treatment as story reactions.

- [ ] **Step 4: Show story thumbnail in trailing content**

Add `.mention` story context to the story thumbnail branch:

```swift
case .storyReaction, .storyChainContinued, .mention where group.notifications.first?.storyId != nil:
```

If Swift switch pattern gets awkward, use a helper:

```swift
private var isStoryMention: Bool {
    group.notifications.first?.type == .mention && group.notifications.first?.storyId != nil
}
```

- [ ] **Step 5: Parse-check**

Run:

```bash
swiftc -parse Glowsy/Notifications/NotificationsView.swift
```

Expected: parse succeeds.

## Task 4: Make Notification Copy Context-Aware

**Files:**
- Modify: `Glowsy/Notifications/NotificationsView.swift`
- Modify: `Glowsy/es.lproj/Localizable.strings`
- Modify: other `Glowsy/*.lproj/Localizable.strings`

- [ ] **Step 1: Add list copy keys**

Add keys:

```text
notifications.message.mention.story.single = "%@ te mencionó en su historia.";
notifications.message.mention.story.multiple = "%@ y %d más te mencionaron en historias.";
notifications.message.mention.comment.single = "%@ te mencionó en un comentario.";
notifications.message.mention.comment.multiple = "%@ y %d más te mencionaron en comentarios.";
notifications.message.mention.moment.single = "%@ te mencionó en un momento.";
notifications.message.mention.moment.multiple = "%@ y %d más te mencionaron en momentos.";
```

Translate equivalent keys in existing locales. If a locale is not ready, use current English fallback but keep keys present so `plutil` stays clean.

- [ ] **Step 2: Add helper for mention context**

In `NotificationsView.messageForGroup`, replace generic `.mention` copy with:

```swift
private func mentionListMessage(for group: NotificationGroup, sender: String, isMultiple: Bool) -> AttributedString
```

Context logic:
- `storyId != nil` or `mentionContext == "story"` -> story copy
- `commentId != nil` or `mentionContext == "comment"` -> comment copy
- `momentId != nil` -> moment copy
- fallback -> current generic mention copy

- [ ] **Step 3: Validate strings**

Run:

```bash
for f in Glowsy/*.lproj/Localizable.strings; do plutil -lint "$f"; done
```

Expected: all OK.

## Task 5: Fix Comment Mention Creation

**Files:**
- Modify: `Glowsy/Services/Firestore/FirestoreCommentsRepository.swift`
- Consider removing/redirecting legacy duplicate: `Glowsy/Services/Firestore/FirestoreService.swift`

- [ ] **Step 1: Pass `commentId` into mention handler**

Change:

```swift
self.handleMentions(mentions, momentId: momentId, fromUserId: authorId, fromUsername: user.username, content: content)
```

To:

```swift
self.handleMentions(
    mentions,
    momentId: momentId,
    commentId: commentId,
    fromUserId: authorId,
    fromUsername: user.username,
    content: content
)
```

- [ ] **Step 2: Write comment mention context**

Use:

```swift
NotificationService.shared.sendCommentMentionNotification(
    to: mentionedUserId,
    momentId: momentId,
    commentId: commentId,
    commentText: content
)
```

- [ ] **Step 3: Gate comment mentions by moment visibility**

Before sending a mention from a comment, verify the mentioned user can currently view the moment:

- `everyone`: respect private profile/follow rules through `ContentVisibilityService`.
- `connections`: require the connection visibility check to pass.
- `bestFriends`: require best friends visibility.
- `custom`: require the user to be in the stored custom audience.
- `customList`: require the user to be in the selected custom list.
- `onlyMe`: never notify.

This also applies to reply notifications. If someone replies to an old comment but the parent author can no longer view the moment, do not send a reply notification.

- [ ] **Step 4: Avoid self notifications**

Before sending:

```swift
guard mentionedUserId != fromUserId else { return }
```

- [ ] **Step 5: Dedupe mentions in one comment**

Convert extracted usernames to unique lowercase usernames:

```swift
Array(Set(mentions.map { $0.lowercased() }))
```

- [ ] **Step 6: Decide edit behavior**

For v1, do not send new mention notifications when editing an old comment unless the mentioned username was not already present before edit. If old content is not available cheaply, skip edit mention notifications for now to avoid spam.

## Task 6: Keep Post Tags Separate From Mentions

**Files:**
- Modify: `Glowsy/Views/Creator/BackgroundMomentUploadService.swift`
- Modify: `Glowsy/Notifications/NotificationsView.swift`

- [ ] **Step 1: Keep `.photoTag` for spatial/user tags**

Do not merge post tags into `.mention`. Instagram treats post tags and mentions differently, and we already have `.photoTag`.

- [ ] **Step 2: Add context fields to photo tag docs**

When sending `.photoTag`, include:

```swift
momentId: momentId
mentionContext: "photoTag"
targetAuthorId: uploadingMoment.userId
```

If `sendInteractionNotification` does not support these fields yet, add a focused overload:

```swift
func sendPhotoTagNotification(to userId: String, momentId: String, momentAuthorId: String)
```

- [ ] **Step 3: Preserve tagged profile behavior**

Do not change `taggedUsers` storage in moment docs. The profile Tagged tab depends on it.

## Task 7: Make In-App Banner Match Notification Context

**Files:**
- Modify: `Glowsy/Views/Components/InAppBannerView.swift`
- Modify: `Glowsy/Notifications/InAppNotificationService.swift` if decoded IDs need stabilization

- [ ] **Step 1: Load story previews for story mentions**

Current banner preview loading treats `.mention` as moment-only. Change `loadImages(for:)` so:

```swift
if notification.type == .mention, let storyId = notification.storyId {
    fetchStoryPreview(
        storyId: storyId,
        authorId: notification.storyAuthorId ?? notification.targetAuthorId ?? notification.senderId
    )
} else if notification.type == .mention, let momentId = notification.momentId {
    fetchMomentPreview(momentId: momentId)
}
```

Expected: story mention banners show the story thumbnail, not the generic `@` icon unless preview fetch fails.

- [ ] **Step 2: Route story mentions from banner correctly**

Current `handleTap` routes `.mention` only if it has a `momentId`. Change it so:

```swift
case .mention:
    if let storyId = notification.storyId {
        navigationService.navigateToStory(storyId: storyId)
    } else if let momentId = notification.momentId {
        navigationService.navigateToMoment(
            momentId: momentId,
            userId: notification.targetAuthorId ?? notification.senderId
        )
    }
```

If `NotificationNavigationService.navigateToStory` cannot carry `storyAuthorId`, do not invent a second navigation path here; route to notifications as a fallback until Task 3 adds author-aware story routing.

- [ ] **Step 3: Make banner verb context-aware**

Replace generic:

```swift
case .mention: return NSLocalizedString("banner.verb.mention", value: "mentioned you", comment: "")
```

With:

```swift
case .mention:
    if notification.storyId != nil || notification.mentionContext == "story" {
        return NSLocalizedString("banner.verb.mention.story", value: "mentioned you in a story", comment: "")
    }
    if notification.commentId != nil || notification.mentionContext == "comment" {
        return NSLocalizedString("banner.verb.mention.comment", value: "mentioned you in a comment", comment: "")
    }
    if notification.momentId != nil || notification.mentionContext == "moment" {
        return NSLocalizedString("banner.verb.mention.moment", value: "mentioned you in a moment", comment: "")
    }
    return NSLocalizedString("banner.verb.mention", value: "mentioned you", comment: "")
```

- [ ] **Step 4: Add banner strings**

Add keys to all current locales:

```text
banner.verb.mention.story = "te mencionó en una historia";
banner.verb.mention.comment = "te mencionó en un comentario";
banner.verb.mention.moment = "te mencionó en un momento";
```

Keep existing `banner.verb.mention` as fallback.

- [ ] **Step 5: Validate banner parse**

Run:

```bash
swiftc -parse Glowsy/Views/Components/InAppBannerView.swift Glowsy/Notifications/InAppNotificationService.swift
```

Expected: parse succeeds.

## Task 8: Make Push Payloads Context-Aware

**Files:**
- Modify: `functions/index.js`
- Modify: `Glowsy/*/Localizable.strings`

- [ ] **Step 1: Derive mention context server-side**

In `handleMentionPush`, derive:

```js
const mentionContext = notification.mentionContext
  || (notification.storyId ? 'story' : notification.commentId ? 'comment' : notification.momentId ? 'moment' : 'default');
```

- [ ] **Step 2: Send specific APNs localization keys**

Use:

```js
const titleKeyByContext = {
  story: 'notification.mention.story.title',
  comment: 'notification.mention.comment.title',
  moment: 'notification.mention.moment.title',
  default: 'notification.mention.title'
};
```

Keys:

```text
notification.mention.story.title = "%@ te mencionó en su historia";
notification.mention.comment.title = "%@ te mencionó en un comentario";
notification.mention.moment.title = "%@ te mencionó en un momento";
notification.mention.body = "Toca para verlo";
```

- [ ] **Step 3: Include routing data**

Add to `data`:

```js
mentionContext,
storyAuthorId: notification.storyAuthorId || notification.targetAuthorId || notification.senderId || '',
commentId: notification.commentId || '',
momentId: notification.momentId || '',
storyId: notification.storyId || ''
```

- [ ] **Step 4: Parse-check Functions**

Run:

```bash
node --check functions/index.js
```

Expected: no syntax errors.

## Task 9: Notification Tab Placement and Grouping

**Files:**
- Modify: `Glowsy/Notifications/NotificationsView.swift`

- [ ] **Step 1: Put story mentions under Stories**

In `groupNotifications`, for selected tab:
- comments tab includes `.comment`, `.like`, comment mentions.
- stories tab includes `.storyReaction`, `.storyChainContinued`, story mentions.
- all tab includes everything.

- [ ] **Step 2: Group by context plus content ID**

Current key:

```swift
let contentId = notification.momentId ?? notification.storyId ?? notification.commentId ?? "general"
key = "\(notification.type.rawValue)_\(contentId)"
```

Replace with:

```swift
let context = notification.mentionContext ?? "default"
let contentId = notification.commentId ?? notification.storyId ?? notification.momentId ?? "general"
key = "\(notification.type.rawValue)_\(context)_\(contentId)"
```

This prevents a story mention and comment mention from being grouped together accidentally.

- [ ] **Step 3: Verify grouping manually**

Create one story mention and one comment mention from the same sender.
Expected:
- All tab shows two rows or two context-correct groups.
- Stories tab shows story mention.
- Comments tab shows comment mention.

## Task 10: QA Matrix

**Files:**
- No code changes.

- [ ] **Step 1: Story mention**

Steps:
- User A publishes a story with mention sticker for User B.
- User B receives in-app notification row with story preview.
- Push says `A te mencionó en su historia`.
- Tapping row opens A's story fullscreen.

- [ ] **Step 2: Story mention privacy**

Steps:
- Publish to everyone, best friends, custom list, only me.
- Verify notification only goes to mentioned user if they can actually view it.
- Verify `onlyMe` never sends mention notifications.
- Verify a custom-list story does not notify a mentioned user outside the list.

- [ ] **Step 2.5: Future UX note for skipped mentions**

Not implemented in v1 unless explicitly prioritized:
- If the creator mentions someone outside the selected story audience, show a subtle non-blocking hint before publishing or after choosing audience.
- Suggested copy: `Algunas menciones no recibirán notificación porque no están incluidas en la audiencia.`
- Keep this as a privacy helper, not as an error. Publishing should not be blocked.

- [ ] **Step 3: Post tag**

Steps:
- User A tags User B in a moment.
- User B gets `.photoTag`, preview image appears, tapping opens moment.
- Tagged profile tab still includes the moment.

- [ ] **Step 4: Comment mention**

Steps:
- User A comments `hola @userB`.
- User B gets comment mention copy and moment preview.
- Tapping opens the moment.
- No self notification when User A mentions themselves.

- [ ] **Step 5: Duplicate protection**

Steps:
- Comment `@userB @userB`.
- Story with two mention stickers for same user.
- Expected: one notification per content.

- [ ] **Step 6: Validation**

Run:

```bash
swiftc -parse Glowsy/Models/Models.swift Glowsy/Notifications/Notificationservice.swift Glowsy/Notifications/NotificationsView.swift Glowsy/Services/Firestore/FirestoreCommentsRepository.swift Glowsy/Views/Creator/BackgroundStoryUploadService.swift Glowsy/Views/Creator/Components/StickerPickerSupportExtensions.swift Glowsy/Views/Creator/BackgroundMomentUploadService.swift
node --check functions/index.js
for f in Glowsy/*.lproj/Localizable.strings; do plutil -lint "$f"; done
```

Expected: all pass.

## Execution Notes

- Do not change the story editor mention UI in this pass.
- Do not add DM-style story mention messages in v1; Instagram does it, but our messaging system is separate and that would be a bigger product decision.
- Do not migrate all notification writes to Functions in this pass. Add richer client writes first, then move creation server-side later if needed.
- Keep old notifications readable. Any new field must be optional.
- Avoid Xcode full builds unless parse checks are not enough or the user asks.

## Suggested Implementation Order

1. Task 1: model + service context fields.
2. Task 2: story mention creation.
3. Task 3: story preview/routing fix.
4. Task 5: comment mention creation.
5. Task 9: grouping/tab placement.
6. Task 7: in-app banner parity.
7. Task 4 and 8: strings + push copy.
8. Task 6: photo tag metadata cleanup.
9. Task 10: QA.

## Self-Review

- Spec coverage: Covers story mentions, post tags/post mention context, and comment mentions.
- Root cause coverage: Fixes missing `storyAuthorId`, wrong story fetch path, generic mention copy, generic grouping, and missing `commentId`.
- Backward compatibility: Existing notifications still decode with optional fields.
- Risk: Push behavior requires Functions deploy after Task 8; app-side preview/routing improves before deploy.
