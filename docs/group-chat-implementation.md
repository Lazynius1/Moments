# Group chat — implementation and deployment status

Updated: 7 September 2026.

## Group invitation policy (separate from 1:1)

Instagram-style split: `messageRequestPolicy` still gates direct message requests. `groupInvitePolicy` (`everyone` | `following` | `nobody`, default `everyone`) gates who can invite you to a group. It does not hide messages inside a group you already belong to. Backend check lives in `manageGroup` (`create`/`add`) and returns `inviteForbidden`. Settings row sits under message requests on iOS and Android.

## User requirements

- One inbox and the existing full Moments chat screen on iOS and Android. No separate Groups inbox or reduced GroupChatView.
- Reuse current bubbles, composer, voice, view-once, GIF, stickers, reactions, translation, attachments, search, mute and archive. Keep direct-chat behavior.
- Exclude vanish and buzz from groups.
- Group name, members, administrators, invitations and notifications.
- Select people on Moments without requiring mutual following or direct-message consent. Blocks do not filter messages, determine membership or suppress notifications inside groups.
- Keep groups distinct even when only two members remain.
- Both apps and all 16 locales. No app builds, runtime tests or subagents. Finish the implementation and deploy only the necessary group backend/rules.
- Latest reminder: fix the group copy as well, including the obsolete mutual-connections wording.

## Implemented locally

- In both apps, creation starts at Messages → New conversation → New group. Android no longer has a New group row in the messages inbox; returning from creation restores the new-conversation screen.
- iOS and Android group conversations merge into the existing inbox and open the existing GlassmorphicChatView. The temporary text/photo-only group screens and separate inbox have been removed.
- `group-UUID` IDs preserve group identity across cached conversations and offline queues. Transport helpers route group conversations/messages/reactions to isolated collections, without changing direct conversation IDs or direct-only discovery/consent operations.
- The shared encrypted message and media pipeline handles group messages; group key resolution only unwraps the authenticated member’s envelope and does not fall back to direct-chat key migration.
- Group headers and sender names; name changes update the open chat. Existing settings retain shared content/search/preferences and add group management. Vanish and buzz are disabled for groups; direct block/profile availability checks are skipped in group chat.
- Create a group by inviting at least two other people; maximum 50 members including pending invitations. Invitees accept or decline in the messages inbox. Administrators can see/cancel pending invitations, invite people, rename, promote/demote and remove members. Ownership passes to another member when the owner leaves.
- Invitations carry a wrapped group key. Only accepted members gain access to group documents/messages. Accepted members can read ordinary group history; view-once media remains limited to its original recipients.
- Creation retains a request ID across retries with unchanged inputs. Search works beyond the initially suggested people.
- View-once read/consumption state is interpreted per recipient. Storage denies consumed media to that recipient; backend cleanup waits until all remaining intended recipients have consumed it. Another recipient opening media cannot consume it for everyone.
- Read state, stars, reactions, pin/mute/archive and clearing one’s own history use group paths. Message badges include groups. Leaving/removal closes the active group chat after the inbox membership update.
- Group message and invitation notifications route to the chat/inbox and show native banners when appropriate, without applying direct-message block suppression.

## Copy and translations

46 group keys are provided in all 16 existing locales for both apps: en, es, ca, de, fr, it, pt-BR, pt-PT, nl, pl, hi, id, ja, ko, zh-Hant and tr.

The copy now says to choose/invite people on Moments, without mutual-follow requirements. It explains invitation acceptance and access to group history and includes accept, decline and pending-invitation actions.

Source/generator: `scripts/sync-group-chat-localizations.py` (resolves the shared workspace automatically). Outputs are each iOS `Localizable.strings`, Android `strings_groups.xml`, and `GroupStrings.kt`.

## Backend deployed

Project: `glowsy-6a40e`, database `(default)` (Standard), region `europe-southwest1`.

Firebase CLI confirmed successful creation of:

- `manageGroup`
- `sendGroupMessage`
- `consumeGroupViewOnceMessage`
- `onGroupMessageAdded`
- `onGroupInvitationCreated`

Firestore and Storage rules were compiled by Firebase and released successfully. Existing direct rule blocks were preserved; group rules are isolated additions.

Collections: `groupConversations/{id}/groupMessages/{id}`, per-message `groupMessageReactions`, and `groupInvitations`. Encrypted media: `groupChat/{groupId}/{ownerId}/{messageId}/{fileName}`.

The deployment used the configured codebase name to target only those five functions, plus `firestore:rules` and `storage`. No other functions were deployed.

## Index status — READY

Only new group indexes were requested; existing direct indexes were not replaced or deleted:

- `groupMessages`: `isRead` + `senderId`, collection scope.
- `groupMessages`: `status` + `senderId`, collection scope.
- `groupMessageReactions`: `conversationId` + `messageId`, collection-group scope.
- `groupMessageReactions.conversationId`: ascending collection-group index, preserving ordinary field indexes.

Final read confirmed all three composite indexes and the collection-group field index are `READY`. A separate read also confirmed all five deployed functions are `ACTIVE`. Definitions are retained in `firestore.indexes.json`.

Composite index IDs: `CICAgJi0yJkJ`, `CICAgJiWkpMK`, `CICAgJi0yJkL`.

## Verification and limits

Completed: JavaScript syntax check, `git diff --check` in both repositories, parsing all 16 Android group XML files, linting iOS localization files, Firebase rules compilation and successful targeted deployment.

No iOS/Android app builds or runtime/unit/UI tests were run, as requested. Client behavior is statically reviewed, not runtime-verified. Changes remain local and uncommitted; no app binaries were published.
