# Telegram-style Voice Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace tap-to-record with Telegram's press, hold, drag-to-lock, and drag-to-cancel voice recording interaction, including its large microphone aura.

**Architecture:** A focused SwiftUI gesture component owns transient touch progress and emits tokenized start/finish events. `GlassmorphicChatView` owns the active token so asynchronous microphone permission cannot start an abandoned recording. The existing `AudioRecordingManager`, waveform persistence, and send pipeline remain unchanged.

**Tech Stack:** SwiftUI, AVFoundation, existing `MotionPolicy`, `HapticManager`, and `AudioRecordingManager`.

## Global Constraints

- Minimum behavior target remains iOS 18.6.
- Hold duration is 190 ms; upward lock distance is 72 pt; left cancellation distance is 70 pt.
- Inner microphone circle is 110 pt with the Welcome login Aurora mesh plus clear Liquid Glass; the 160 pt outer aura uses the same mesh.
- The aura follows `AudioRecordingManager.audioPower`.
- The gesture is attached only to the microphone hit target and must not interfere with chat scrolling.
- A short tap never starts recording.
- Locked mode requires an explicit cancel or send action.
- VoiceOver activation starts directly in locked hands-free mode.
- No build or automated test commands are run; the user performs runtime testing.

---

### Task 1: Define the tokenized recording interaction contract

**Files:**
- Create: `Moments/Views/Messaging/Components/VoiceRecordingGestureViews.swift`
- Modify: `Moments/Views/Messaging/Screens/Chat/GlassmorphicChatView.swift`

**Interfaces:**
- Produces: `VoiceRecordingFinishAction`, `VoiceRecordingGesturePhase`, and `VoiceRecordingGestureButton`.
- Produces: `voiceRecordingInteractionId: UUID?` in `GlassmorphicChatView`.

- [ ] **Step 1: Add interaction types**

```swift
enum VoiceRecordingFinishAction {
    case send
    case cancel
}

private enum VoiceRecordingGesturePhase: Equatable {
    case idle
    case pressing
    case recordingHeld
    case recordingLocked
}
```

- [ ] **Step 2: Add the active token to the chat screen**

```swift
@State var voiceRecordingInteractionId: UUID?
```

- [ ] **Step 3: Keep the new source focused**

The new file owns only microphone gesture state, overlay rendering, progress calculation, and gesture haptics. It does not access the view model or stop the recorder directly.

### Task 2: Implement Telegram's microphone gesture and aura

**Files:**
- Create: `Moments/Views/Messaging/Components/VoiceRecordingGestureViews.swift`

**Interfaces:**
- Consumes: `AudioRecordingManager.shared.audioPower`.
- Produces:

```swift
VoiceRecordingGestureButton(
    tint: Color,
    isRecording: Bool,
    onStart: (UUID, Bool) -> Void,
    onFinish: (UUID, VoiceRecordingFinishAction) -> Void
)
```

- [ ] **Step 1: Implement the 190 ms hold task**

On first `DragGesture(minimumDistance: 0)` update, create a UUID, enter `.pressing`, and start a cancellable `Task`. After 190 ms, verify the UUID is still active, enter `.recordingHeld`, emit a light haptic, and call `onStart(token, false)`.

- [ ] **Step 2: Implement directional progress**

After 8 pt of movement, lock the interaction axis. For vertical movement use `min(1, max(0, -translation.height / 72))`; for horizontal movement use `min(1, max(0, -translation.width / 70))`.

- [ ] **Step 3: Commit lock and cancellation exactly once**

When lock progress reaches 1, enter `.recordingLocked`, emit success feedback, announce the locked state, and keep recording after touch release. When cancellation reaches 1, emit warning feedback, call `onFinish(token, .cancel)`, and reset.

- [ ] **Step 4: Send on ordinary release**

Release during `.recordingHeld` calls `onFinish(token, .send)`. Release during `.pressing` cancels the delayed task without recording. Release during `.recordingLocked` does nothing.

- [ ] **Step 5: Draw the microphone overlay**

Render the Welcome login `AuroraMeshLayer` beneath a 110 pt clear Liquid Glass circle and reuse the same mesh as a 160 pt aura. Smooth the live level and map it from `110 / 160` to `1.0`. Animate only scale, offset, and opacity with interruptible `MotionPolicy` springs.

- [ ] **Step 6: Draw lock and cancel affordances**

Place a 40 by 72 pt glass lock pill above the microphone. Its chevron, lock glyph, opacity, and vertical translation follow lock progress. Move the cancel hint left as cancellation progress increases.

- [ ] **Step 7: Add accessibility behavior**

The semantic button action checks `accessibilityVoiceOverEnabled`; when enabled it creates a token, enters `.recordingLocked`, and calls `onStart(token, true)`. Expose localized accessibility labels and announcements. Reduce Motion removes large travel and spring overshoot while retaining state opacity and subtle audio activity.

### Task 3: Integrate the gesture into the composer

**Files:**
- Modify: `Moments/Views/Messaging/Components/ChatInputViews.swift`
- Modify: `Moments/Views/Messaging/Screens/Chat/GlassmorphicChatView+ComposerAndChrome.swift`

**Interfaces:**
- Replaces: `onStartVoiceRecording: () -> Void`.
- Adds:

```swift
let onStartVoiceRecording: (UUID, Bool) -> Void
let onFinishVoiceRecording: (UUID, VoiceRecordingFinishAction) -> Void
```

- [ ] **Step 1: Replace the existing microphone button**

Use `VoiceRecordingGestureButton` when the text field is empty. Keep attachments, send button, input glass, and vanish styling unchanged.

- [ ] **Step 2: Preserve the locked recording bar**

Continue using `VoiceRecordingBar` after the gesture locks or VoiceOver starts hands-free mode. Its existing cancel and send buttons emit tokenized `.cancel` and `.send` actions.

- [ ] **Step 3: Wire callbacks from the screen**

Pass the UUID and hands-free flag into `startVoiceRecording(interactionId:startsLocked:)`. Pass finish actions into `finishVoiceRecording(interactionId:action:)`.

### Task 4: Make recorder lifecycle token-safe

**Files:**
- Modify: `Moments/Views/Messaging/Screens/Chat/GlassmorphicChatView+Voice.swift`

**Interfaces:**
- Produces:

```swift
func startVoiceRecording(interactionId: UUID, startsLocked: Bool)
func finishVoiceRecording(interactionId: UUID, action: VoiceRecordingFinishAction)
func resetVoiceRecordingInteraction()
```

- [ ] **Step 1: Validate asynchronous permission completion**

Set `voiceRecordingInteractionId` before requesting permission. In the permission callback, start the timer only when the stored UUID still matches. A release or cancellation clears the UUID so a late permission response is ignored.

- [ ] **Step 2: Make finish idempotent**

`finishVoiceRecording` returns unless the UUID matches, clears it before stopping the recorder, invalidates the timer, resets UI state, and sends only for `.send`.

- [ ] **Step 3: Preserve the 60-second limit**

The existing timer calls the tokenized finish method with `.send`. View disappearance and interruption call `.cancel` when an interaction is active.

- [ ] **Step 4: Reject clips shorter than 0.5 seconds**

If a send action captures a shorter duration, stop and discard the result, emit error feedback, and restore the idle composer.

### Task 5: Localize and review the motion

**Files:**
- Modify: `Moments/es.lproj/Localizable.strings`
- Modify: `Moments/en.lproj/Localizable.strings`
- Modify: `Moments/ca.lproj/Localizable.strings`
- Modify: `Moments/de.lproj/Localizable.strings`
- Modify: `Moments/fr.lproj/Localizable.strings`
- Modify: `Moments/it.lproj/Localizable.strings`
- Modify: `Moments/pt-BR.lproj/Localizable.strings`
- Modify: `Moments/pt-PT.lproj/Localizable.strings`

**Interfaces:**
- Produces localization keys for hold hint, cancel hint, lock hint, recording started, locked, cancelled, and too-short feedback.

- [ ] **Step 1: Add all supported translations**

Use concise native copy. Spanish examples are “Mantén pulsado para grabar”, “Desliza para cancelar”, and “Desliza arriba para bloquear”.

- [ ] **Step 2: Review motion rules manually**

Confirm every animation uses `.animation(_:value:)`, gesture progress updates directly without fixed keyframes, no width or height is animated, Reduce Motion removes large movement, and lock/cancel completion fires only once.

- [ ] **Step 3: Perform the permitted source check**

Run only `git diff --check` and focused `rg` searches for obsolete callback signatures. Do not run `xcodebuild`, Swift parsing, simulators, or automated tests.
