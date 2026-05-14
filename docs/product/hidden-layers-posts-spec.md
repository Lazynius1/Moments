# Hidden Layers for Posts

Date: 2026-05-14
Status: Draft
Scope: Moments/posts only. Stories are explicitly out of scope.

## Goal

Give image posts more life without turning them into noisy story clones. A post can contain up to three hidden interactive layers placed over the image. Viewers discover them by noticing subtle visual hints and tapping the image.

The feature should feel like a clean post with secrets, not like stickers pasted on top.

## Product Scope

### V1

- Only posts with a single image.
- No videos.
- No carousels.
- Up to 3 hidden layers per post.
- Layer types:
  - Text
  - Audio
  - Image
- Normalized layer placement.
- Secondary media uploaded to Firebase Storage.
- Moderation per layer.
- Viewer shimmer hint on first display.
- Tap to discover.
- Local seen state per user/device.
- Text layers support multiple font styles and presentation styles.

### V2

- Reveal/scratch layers for posts.
- Discovery metrics per layer.
- Time-locked layers, for example "opens at 22:00".

## Non Goals

- No hidden layers in stories.
- No collaborative follower-created layers.
- No interaction in every feed card for V1.
- No Firestore documents with embedded base64 media.
- No storing full hidden layer arrays inside the main Moment document.

## UX Principles

- The post remains visually clean by default.
- Hidden areas should be suggested, not loudly labeled.
- The first-view hint should be brief: a shimmer/glow around hotspots for 1 to 1.5 seconds.
- After the hint, hotspots become almost invisible.
- Discovery should feel intentional and tactile: tap, light haptic, small reveal animation.
- The main interaction should live in the post detail view in V1. Feed cards can show a lightweight indicator only.

## Creator Flow

Hidden layers are available only when the draft has exactly one image and no video.

1. User selects or captures a single image post.
2. User edits/crops normally.
3. Before publish, user can tap `Capas ocultas`.
4. The hidden layer editor opens over the post image.
5. User taps `+ Capa`.
6. User chooses `Texto`, `Audio`, or `Imagen`.
7. User places and resizes the hotspot over the image.
8. User previews the interaction.
9. User publishes.

Limits:

- Maximum layers: 3
- Text maximum length: 120 characters
- Audio maximum duration: 15 seconds
- Secondary image maximum long side: 1080 px
- Minimum normalized layer size: 0.12
- Maximum normalized layer size: 0.55
- Layers cannot be placed too close to the image edges.

## Text Design

Text layers should support two independent style axes.

Font style:

- `clean`
- `serif`
- `handwritten`
- `mono`
- `bubble`
- `editorial`

Presentation style:

- `glassCard`
- `captionPill`
- `paperNote`
- `markerLabel`
- `floatingQuote`
- `minimalText`

This gives variety without exposing too many controls.

## Data Model

The main `Moment` document should only store lightweight summary fields:

```swift
let hasHiddenLayers: Bool
let hiddenLayerCount: Int
```

Hidden layers live in a subcollection:

```text
users/{userId}/moments/{momentId}/hiddenLayers/{layerId}
```

Draft model:

```swift
struct HiddenLayerDraft: Identifiable, Codable {
    let id: String
    var type: MomentHiddenLayer.LayerType
    var anchorX: Double
    var anchorY: Double
    var width: Double
    var height: Double
    var shape: MomentHiddenLayer.LayerShape
    var zIndex: Int

    var text: String?
    var localMediaURL: URL?
    var localImage: UIImage?
    var duration: Double?

    var textStyle: HiddenLayerTextStyle?
    var presentationStyle: HiddenLayerPresentationStyle
}
```

Persisted model:

```swift
struct MomentHiddenLayer: Identifiable, Codable {
    let id: String
    let type: LayerType
    let anchorX: Double
    let anchorY: Double
    let width: Double
    let height: Double
    let shape: LayerShape
    let zIndex: Int

    let text: String?
    let mediaURL: String?
    let thumbnailURL: String?
    let duration: Double?

    let textStyle: HiddenLayerTextStyle?
    let presentationStyle: HiddenLayerPresentationStyle

    let moderationState: ModerationState?
    let moderationReason: String?
    let moderationCategory: String?
    let moderatedAt: Date?
    let createdAt: Date

    enum LayerType: String, Codable {
        case text
        case audio
        case image
    }

    enum LayerShape: String, Codable {
        case circle
        case roundedRect
    }

    enum ModerationState: String, Codable {
        case visible
        case hidden
        case pending
    }
}
```

Important rule: IDs must always use UUIDs. They must not be derived from position or type.

## Coordinate System

All placement values are normalized against the actual displayed image rect, not the full screen.

- `anchorX`: 0.0 to 1.0
- `anchorY`: 0.0 to 1.0
- `width`: normalized width relative to image rect
- `height`: normalized height relative to image rect

The editor and viewer must use the same image layout calculation. If the image is aspect-fit or aspect-fill, both sides must resolve the same render rect before placing layers.

This avoids the class of bugs where the editor position does not match the viewer.

## Upload Flow

Implementation should extend `BackgroundMomentUploadService`.

1. Upload the main post media normally.
2. Create the Moment and get the real `momentId`.
3. Upload hidden layer secondary media:
   - Audio layers go to Storage.
   - Image layers are resized/compressed before upload.
   - Text layers do not need Storage.
4. Create each document in `hiddenLayers`.
5. Update the main Moment document:
   - `hasHiddenLayers = true`
   - `hiddenLayerCount = visibleOrPendingLayerCount`
6. Trigger moderation for secondary media layers.

Failure behavior:

- If the main Moment upload fails, the post fails.
- If one hidden layer upload fails, omit that layer and continue publishing the post.
- If all hidden layers fail, publish the post without hidden layers.
- Never block the main post because an optional layer failed.

## Viewer Flow

V1 should render full interaction in post detail views. Feed cards only show a small indicator such as `Capas ocultas`.

1. If `moment.hasHiddenLayers == true`, fetch `hiddenLayers` lazily.
2. Filter out `moderationState == hidden`.
3. On first view, show shimmer/glow over each visible hotspot for 1 to 1.5 seconds.
4. After shimmer, hotspots become subtle or invisible.
5. User taps a hotspot.
6. The layer reveals:
   - Text: styled card/note/quote.
   - Audio: inline circular player with pause/resume.
   - Image: mini image card or polaroid-style reveal.
7. Save local seen state.

Local seen key:

```text
hiddenLayerSeen:{momentId}:{layerId}
```

If already seen, the layer can show a small discovered state rather than replaying the full hint every time.

## Audio Behavior

- Audio layers should not autoplay.
- Tap opens/reveals the player.
- Playback should pause/resume without resetting.
- Playback should stop when leaving the post detail view.
- Use the existing audio cache infrastructure where possible.
- Avoid interfering with story audio behavior.

## Moderation

V1 moderation applies to secondary image/audio layers.

Text moderation can start with local validation:

- Max length.
- No empty text.
- Trim whitespace.

Later, text moderation can be added server-side if needed.

When a layer is moderated:

- Hide only that layer.
- Keep the main post visible.
- Update the hidden layer document with `moderationState = hidden`.
- Optionally decrement effective visible count or compute visible count client-side.
- Notify the author with copy specific to post layers:

```text
Hemos ocultado una capa de tu post porque no cumple nuestras normas de la comunidad.
```

Plural:

```text
Hemos ocultado algunas capas de tu post porque no cumplen nuestras normas de la comunidad.
```

## Backend And Functions

Needed server/function work:

- Include `hasHiddenLayers` and `hiddenLayerCount` in feed responses.
- Add moderation handling for hidden layer media.
- Add notification copy for hidden layer moderation.
- Keep per-layer moderation separate from Moment media moderation.

Feed response must remain lightweight. Do not include full hidden layer documents in normal feed pages.

## Files Likely To Change

- `Glowsy/Models/Models.swift`
  - Add Moment summary fields.
  - Add hidden layer models.

- `Glowsy/Views/Creator/CreatorView.swift`
  - Add hidden layers entry point.
  - Hold hidden layer drafts.
  - Gate feature to single-image posts.

- `Glowsy/Views/Creator/BackgroundMomentUploadService.swift`
  - Persist drafts.
  - Upload secondary media.
  - Write hidden layer subcollection.

- `Glowsy/Services/FirestoreService.swift`
  - Create/update helpers for hidden layers.
  - Moment summary fields.

- `Glowsy/Services/BackendFeedService.swift`
  - Decode hidden layer summary from function response.

- `Glowsy/Views/Feed/FeedView.swift`
  - Lightweight indicator in feed.
  - Potential shared render hook for detail if needed.

- `Glowsy/Views/Profile/Moments view/ModernMomentDetailView.swift`
  - Full hidden layer viewer interaction.

- `Glowsy/Moderation/MediaModerationService.swift`
  - Hidden layer moderation task support.

- Firebase Functions
  - Feed response fields.
  - Moderation notification handling.

## Implementation Phases

### Phase 1: Foundation

- Add models.
- Add Moment summary fields.
- Add Firestore helper methods.
- Add upload support for text-only hidden layers.
- Add simple detail viewer for text layers.

Success criteria:

- A single-image post can be published with one text hidden layer.
- The layer loads from the subcollection.
- The position matches between editor and viewer.

### Phase 2: Creator UI

- Add hidden layer editor.
- Add drag/resize placement.
- Add max/min size.
- Add text styles and presentation styles.
- Add audio recording.
- Add image layer picker.

Success criteria:

- User can create up to three layers.
- Preview matches final viewer behavior.
- Invalid states are blocked before publish.

### Phase 3: Upload And Moderation

- Upload audio/image secondary media.
- Resize/compress images.
- Use audio cache where useful.
- Trigger per-layer moderation.
- Hide moderated layers.
- Add author notification.

Success criteria:

- Main post still publishes if one optional layer fails.
- Moderated layer disappears while the post remains visible.
- Notification copy is specific and localized.

### Phase 4: Viewer Polish

- Add shimmer intro.
- Add haptics.
- Add local seen state.
- Add discovered state.
- Add audio pause/resume behavior.

Success criteria:

- The feature feels premium and not like a sticker overlay.
- Viewer interactions do not fight scroll/tap gestures.
- Audio stops when leaving the detail view.

## Risks

- Coordinate mismatch between editor and viewer.
- Feed performance regression if layers are loaded too early.
- Gesture conflicts inside scrollable feed cards.
- Upload complexity because secondary media is optional.
- Moderation race conditions where a layer appears briefly before being hidden.
- Local cache inconsistencies if the main Moment is cached without hidden layer summaries.

## Design Decision

For V1, the full interactive experience should live in post detail, not inline in every feed card.

Reason: this avoids scroll/gesture conflicts and keeps feed performance stable. The feed can advertise that a post has hidden layers, then the detail view provides the premium discovery experience.

