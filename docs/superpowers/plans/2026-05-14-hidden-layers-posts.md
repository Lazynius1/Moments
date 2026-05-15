# Hidden Layers Posts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add V1 hidden layers for single-image Moments posts: text, audio, and image layers with normalized placement, upload, moderation hooks, shimmer discovery, and local seen state.

**Architecture:** Keep feed Moment documents lightweight with `hasHiddenLayers` and `hiddenLayerCount`, while storing full layer data in `users/{userId}/moments/{momentId}/hiddenLayers/{layerId}`. Creator owns drafts; upload writes media and subdocs after the Moment exists; detail viewers lazy-load and render layers over the resolved image rect.

**Tech Stack:** SwiftUI, Firebase Firestore, Firebase Storage via existing `StorageService`, AVFoundation, Kingfisher, existing moderation/audio cache infrastructure.

---

### Task 1: Models And Firestore Surface

**Files:**
- Modify: `Glowsy/Models/Models.swift`
- Modify: `Glowsy/Services/BackendFeedService.swift`
- Modify: `Glowsy/Services/FirestoreService.swift`

- [x] Add `MomentHiddenLayer`, text/presentation enums, and lightweight `Moment` fields.
- [x] Decode/encode hidden layer summary in `Moment` and backend feed responses.
- [x] Add Firestore helpers to save/fetch/update hidden layers and update Moment summary.
- [x] Keep all layer IDs UUID-based.

### Task 2: Creator Draft State

**Files:**
- Modify: `Glowsy/Views/Creator/CreatorView.swift`
- Create: `Glowsy/Views/Creator/HiddenLayersEditorView.swift`

- [x] Add `HiddenLayerDraft` state to creator.
- [x] Gate hidden layers to exactly one image and zero videos.
- [x] Add entry point in the caption/details flow.
- [x] Implement a simple full-screen editor with image preview, layer list, add text/audio/image, drag/resize, and style selection.

### Task 3: Upload And Persistence

**Files:**
- Modify: `Glowsy/Views/Creator/BackgroundMomentUploadService.swift`
- Modify: `Glowsy/Services/FirestoreService.swift`

Current note: background recovery now skips persistent upload snapshots when a post contains hidden layers, to avoid silently restoring the post without them.

- [ ] Persist layer drafts with offline upload payloads.
- [x] Upload image/audio secondary media after Moment creation.
- [x] Write layer subdocuments.
- [x] Omit failed optional layers without failing the post.
- [x] Update `hasHiddenLayers` and `hiddenLayerCount`.
- [x] Trigger moderation for image/audio layer media.

### Task 4: Viewer

**Files:**
- Create: `Glowsy/Views/Feed/HiddenLayersOverlayView.swift`
- Modify: `Glowsy/Views/Profile/Moments view/ModernMomentDetailView.swift`
- Modify: `Glowsy/Views/Feed/FeedView.swift`

- [x] Add lightweight feed indicator.
- [x] Lazy-load hidden layers in post detail.
- [x] Render hotspots over the displayed image rect.
- [x] Add shimmer on first display.
- [x] Tap to reveal text/audio/image.
- [x] Persist local seen state using `hiddenLayerSeen:{momentId}:{layerId}`.
- [x] Stop layer audio when leaving the detail view.

### Task 5: Localization And Polish

**Files:**
- Modify: `Glowsy/es.lproj/Localizable.strings`
- Modify: `Glowsy/en.lproj/Localizable.strings`
- Modify: `Glowsy/ca.lproj/Localizable.strings`

- [x] Add creator/viewer strings.
- [x] Add moderation notification strings if client-side copy is needed.
- [x] Run `git diff --check`.
- [ ] Do not run Xcode build from Codex.
