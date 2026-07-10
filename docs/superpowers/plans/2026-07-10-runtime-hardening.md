# Runtime Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove message-cache work from the UI executor, avoid whole-video encryption buffers, and improve accessibility of custom interactive chat surfaces.

**Architecture:** Keep the existing main-actor persistence service for non-chat models while routing message hot paths through a dedicated SwiftData `@ModelActor`. Use a versioned chunked AES-GCM file format for new chat videos and preserve the existing single-box decryptor for legacy media. Keep gesture-driven chat views intact while exposing their semantics to VoiceOver.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, CryptoKit, Firebase Storage.

## Global Constraints

- Do not enable Firebase App Check in this change.
- Do not run builds or automated test suites; the user will test the app manually.
- Preserve all existing local changes in the dirty worktree.
- Preserve compatibility with encrypted chat media metadata version 1.0.

---

### Task 1: Message persistence executor

**Files:**
- Create: `Moments/Services/Persistence/MessagePersistenceStore.swift`
- Modify: `Moments/Services/Persistence/LocalPersistenceService.swift`
- Modify: `Moments/Services/Messaging/MessageIngestService.swift`
- Modify: `Moments/Services/Messaging/MessageCatchUpService.swift`
- Modify: `Moments/Views/Messaging/Core/ChatViewModel.swift`
- Modify: `Shared/MessageIngestQueue.swift`

**Interfaces:**
- Produces: `loadRecentMessagesInBackground`, `loadMessagesBeforeInBackground`, `loadMessagesAfterInBackground`, `saveMessagesInBackground`, `appendMessagesInBackground`, and `reconcileMessagesInBackground`.

- [x] Add a dedicated `@ModelActor` backed by its own `ModelContext`.
- [x] Cross the actor boundary using encoded `Data`, never SwiftData models or observable message instances.
- [x] Route initial cache load, history prepend, message navigation, catch-up ingestion, and listener reconciliation through the actor.
- [x] Keep synchronous APIs available for unrelated legacy callers.

### Task 2: Chunked encrypted video files

**Files:**
- Create: `Moments/Services/Messaging/ChatMediaChunkedCipher.swift`
- Create: `Moments/Views/Messaging/Services/ChatService+ChunkedVideoUpload.swift`
- Modify: `Moments/Services/Messaging/EncryptionService.swift`
- Modify: `Moments/Services/Storage/MediaUploadService.swift`
- Modify: `Moments/Services/Messaging/ChatCacheStore.swift`
- Modify: `Moments/Views/Messaging/Services/ChatService+MediaPipeline.swift`
- Modify: `Moments/Views/Messaging/Services/ChatService+EncryptedMediaResolver.swift`

**Interfaces:**
- Produces: metadata version `2.0`, algorithm `AES.GCM.CHUNKED+HKDF-SHA256`, file-based upload, and file-based decrypt.

- [x] Encrypt video in 1 MiB independently authenticated chunks.
- [x] Authenticate each chunk index and validate header, sizes, ordering, and final plaintext length.
- [x] Upload ciphertext with Firebase Storage `putFile`.
- [x] Download ciphertext to a temporary file and decrypt directly into the cache.
- [x] Continue using the version 1.0 decrypt path for existing messages.

### Task 3: Interactive accessibility

**Files:**
- Modify: Nova overlays and history.
- Modify: chat toolbar, vanish notices, ephemeral cards, media grids, clusters, and menu backdrops.

**Interfaces:**
- Produces: native button semantics where gestures are unnecessary; explicit labels, hints, and button traits where gestures must remain.

- [x] Hide dismiss-only scrims from the accessibility tree.
- [x] Convert the conversation title and vanish actions to native buttons.
- [x] Add VoiceOver semantics to media, ephemeral content, reply previews, and media clusters.

### Task 4: Manual verification handoff

- [ ] Open a long conversation and repeatedly load older pages while continuing to drag.
- [ ] Send and receive a video, relaunch, remove its local cache, and open it again.
- [ ] Open a legacy encrypted video sent before this change.
- [ ] Navigate Nova and chat media controls with VoiceOver.
