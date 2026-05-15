# Hidden Layers for Posts

Date: 2026-05-14
Status: In progress
Scope: Moments/posts only. Stories are explicitly out of scope.

## Current Implementation Notes

- Hidden Layers is live only for single-image posts.
- Text and audio layers are not moderated for now.
- Image/polaroid layers are the only moderated Hidden Layer media.
- Hidden image layers stay out of the viewer while `moderationState == pending`.
- Viewer seen-state is local per user/device using `hiddenLayerSeen:{viewerId}:{momentId}:{layerId}`.
- Partial moderation feedback for hidden image layers uses its own `postHiddenLayer` notification scope.
- The current viewer hint uses a subtle presence/bloom treatment instead of a literal shimmer sweep.
- Feed/detail behavior has evolved: interactive overlay currently exists in key post surfaces, not only detail.

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
- Moderation for image layers.
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
- The first-view hint should be brief: a soft glow/presence state around hotspots for roughly 1.5 to 2.5 seconds.
- After the hint, hotspots become almost invisible.
- Discovery should feel intentional and tactile: tap, light haptic, small reveal animation.
- The interaction should feel premium and low-noise even when rendered over post surfaces outside a dedicated detail screen.

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

    var unlockMode: HiddenLayerUnlockMode
    var unlockAtUTC: Date?
    var authorTimezoneIdentifier: String?
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

    let unlockMode: HiddenLayerUnlockMode
    let unlockAtUTC: Date?
    let authorTimezoneIdentifier: String?

    let discoverCount: Int?
    let uniqueDiscovererCount: Int?
    let lastDiscoveredAt: Date?

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

    enum HiddenLayerUnlockMode: String, Codable {
        case immediate
        case scheduled
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

V1 currently renders the overlay on key post surfaces when the media is a single image and the viewer context can support the interaction cleanly.

1. If `moment.hasHiddenLayers == true`, fetch `hiddenLayers` lazily.
2. Filter out `moderationState == hidden`.
3. On first view, show a subtle presence hint over each visible hotspot for roughly 1.5 to 2.5 seconds.
4. After the hint, hotspots become subtle or invisible.
5. User taps a hotspot.
6. The layer reveals:
   - Text: styled card/note/quote.
   - Audio: inline circular player with pause/resume.
   - Image: mini image card or polaroid-style reveal.
7. Save local seen state.

Local seen key:

```text
hiddenLayerSeen:{viewerId}:{momentId}:{layerId}
```

If already seen, the layer can show a small discovered state rather than replaying the full hint every time.

## Audio Behavior

- Current product direction: audio can autoplay on reveal using ambient-style behavior, then promote to playback on direct interaction.
- Tap opens/reveals the player.
- Playback should pause/resume without resetting.
- Playback should stop when leaving the post detail view.
- Use the existing audio cache infrastructure where possible.
- Avoid interfering with story audio behavior.

## V2: Discovery Metrics

The first V2 layer should give authors feedback without turning Hidden Layers into a dashboard product.

### Author Overlay Placement

- Show a `Capas ocultas` metrics block only to the post author.
- Place it inside the existing `ModernContextMenuOverlay` flow opened from the three-dot rail action.
- Within that menu, place it above `Editar momento` / author-only actions.
- Keep the first level compact:
  - Title
  - One primary summary line
  - Up to 3 supporting chips

Example:

- `Capas ocultas`
- `18 descubrimientos en 3 secretos`
- `Más descubierta: Polaroid`
- `7 personas`
- `Ratio 42%`

### Overlay States

- No hidden layers: no block.
- Hidden layers, zero discovery:
  - `Aún nadie ha descubierto tus secretos`
  - `Cuando alguien toque una capa, lo verás aquí`
- With some discovery:
  - `3 descubrimientos en 2 secretos`
  - lightweight chips for most-discovered layer and people count
- With healthy volume:
  - add ratio as a secondary chip

### Drilldown Flow

- Tap the summary block to open a lightweight activity view inside the current overlay flow.
- Reuse the same author/non-author split that already governs `Editar momento` and `Eliminar`.
- Show layers ordered by discovery count.
- Each layer row should include:
  - mini preview
  - short label
  - status
  - `discoverCount`
  - `uniqueDiscovererCount`
  - `lastDiscoveredAt`
- Tap a layer for a second-level detail view:
  - `discoverCount`
  - `unique discoverers`
  - ratio
  - latest 3 people if product decides the social layer is valuable

### Metrics Data Model

Per layer:

- `discoverCount`
- `uniqueDiscovererCount`
- `lastDiscoveredAt`

Optional social subcollection:

```text
users/{userId}/moments/{momentId}/hiddenLayers/{layerId}/discoveries/{viewerId}
```

Suggested document:

```swift
struct HiddenLayerDiscovery: Codable {
    let viewerId: String
    let discoveredAt: Date
}
```

Suggested moment summary helpers:

- `hiddenLayerCountTotal`
- `hiddenLayerCountUnlockedNow`
- `hiddenLayerCountLocked`
- `nextHiddenLayerUnlockAt`

### What Not To Do

- No charts in the first overlay level.
- No giant analytics vocabulary.
- No full user list in the first tap.
- No mixing metrics UI with time-lock controls in the same summary block.

## V2: Time-Locked Layers

Time-locked layers should feel like scheduled secrets, not like another gimmick sticker.

### Core Rule

Separate:

- `unlock`
- `reveal`

Unlock can happen automatically at a scheduled time.
Reveal should still require a tap by default.

### Creator Flow

Each layer mini sheet gets a compact `Disponibilidad` section:

- `Ahora`
- `Programada`

If `Programada` is selected:

- show quick picks:
  - `Esta noche`
  - `Mañana`
  - `Elegir fecha`
- `Elegir fecha` opens a lightweight date/time picker sheet

Microcopy examples:

- `Se abrirá hoy a las 22:00`
- `Se abrirá el 18 may a las 22:00`

Canvas/editor hint:

- scheduled layers can show a tiny editorial badge like `22:00` or `18 may`
- avoid loud clock icons

### Viewer Before Unlock

- Do not reveal content or type.
- Use a quieter, more sealed hotspot state than a normal hidden layer.
- If the user taps too early:
  - small resist/shake feedback
  - brief microcopy:
    - `Aún no`
    - `Se abre en 1 h 12 min`

Global chip/hint examples:

- `Un secreto se abre en 2 h`
- `Se abre hoy a las 22:00`
- `2 secretos ahora · 1 más a las 22:00`

### Viewer At Unlock Time

- The layer automatically becomes discoverable.
- If the viewer is on the post at that moment:
  - subtle bloom
  - light haptic
  - optional brief copy: `Ya puedes descubrirlo`
- The content should not auto-open by default.

### Time Data Model

Per layer:

- `unlockMode: immediate | scheduled`
- `unlockAtUTC`
- `authorTimezoneIdentifier` optional for traceability

Rules:

- store unlock time in UTC
- author edits in local timezone
- viewer sees relative countdown and local absolute time
- a previously discovered layer stays discovered; time-lock only gates availability

### Edge Cases

- Mixed states in the same post:
  - immediate layers behave normally
  - scheduled locked layers stay sealed
  - scheduled unlocked layers behave like normal discoverable layers
- If the app opens after unlock time, the layer simply starts in discoverable state.
- If more than one scheduled layer exists, summarize with the nearest unlock.

## Moderation

V1 moderation currently applies only to secondary image layers.

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
  - Persist drafts or explicitly skip recovery until hidden-layer recovery is implemented.
  - Upload secondary media.
  - Write hidden layer subcollection.

- `Glowsy/Services/FirestoreService.swift`
  - Create/update helpers for hidden layers.
  - Moment summary fields.

- `Glowsy/Services/BackendFeedService.swift`
  - Decode hidden layer summary from function response.

- `Glowsy/Views/Feed/FeedView.swift`
  - Shared overlay hook for supported single-image post surfaces.

- `Glowsy/Views/Profile/Moments view/ModernMomentDetailView.swift`
  - Hidden layer viewer interaction.

- `Glowsy/Views/Feed/HiddenLayersOverlayView.swift`
  - Hidden layer viewer interaction and V2 unlock states.

- Post author overlay views
  - Hidden layer metrics summary block and drilldown.

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

- Add subtle hotspot intro.
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
- Complexity growth if per-layer metrics and time-locking ship without clear summary fields.

## Design Decision

V1 is allowed to render Hidden Layers on supported single-image post surfaces as long as the interaction remains visually clean and does not introduce gesture conflicts.

Reason: the premium part of the feature is the discovery itself, so the product can expose it beyond a strict detail screen if the overlay remains lightweight and the media rect is stable.
