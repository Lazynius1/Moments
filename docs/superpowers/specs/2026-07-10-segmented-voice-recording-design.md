# Telegram-style voice recording gesture

## Goal

Replace the current tap-to-record flow with Telegram's press-and-hold interaction while preserving Moments' visual language and existing audio pipeline.

The interaction must feel continuous: the microphone, aura, lock indicator, cancellation hint, recording bar, and haptics all reflect the same gesture state. It must not interfere with chat scrolling or message gestures.

## Reference behavior

The implementation follows Telegram iOS's open-source recording controls:

- A short tap does not start recording.
- Holding for 190 ms starts recording.
- Releasing while still held sends the recording.
- Dragging upward progressively reveals and commits the hands-free lock.
- Dragging left progressively cancels the recording.
- Once locked, releasing the finger does nothing; explicit delete and send controls remain available.
- The enlarged microphone has a solid inner circle and a translucent outer aura driven by the live microphone level.

Telegram source references:

- `ChatTextInputAudioRecordingOverlayButton.swift`: 110 pt inner circle, 160 pt outer aura, live microphone-level scaling.
- `ChatTextInputMediaRecordingButton.swift`: 190 ms hold delay, gesture updates, cancellation and lock callbacks.
- `LockView.swift`: progressive lock animation.
- `ChatControllerMediaRecording.swift`: recording state transitions and locked state.

## Interaction state

Use one explicit state machine owned by the chat composer:

1. `idle`: normal microphone button.
2. `pressing`: finger is down but the 190 ms hold threshold has not elapsed.
3. `recordingHeld`: recording is active and follows the finger.
4. `recordingLocked`: hands-free recording; touch release no longer sends.
5. `finishing`: recorder is stopping and producing the audio payload.

Starting a new press creates an interaction token. Permission callbacks, delayed hold callbacks, and gesture endings must verify that token so a microphone permission dialog or delayed callback cannot start an abandoned recording.

## Gesture rules

- Attach a zero-distance drag gesture only to the microphone's hit target.
- Begin the hold timer on touch-down. Start recording at 190 ms if the same touch is still active.
- Before 190 ms, release returns to `idle` without recording.
- While recording, vertical movement has priority when its absolute distance exceeds horizontal movement; horizontal movement has priority in the opposite case. This prevents diagonal jitter from switching actions repeatedly.
- Upward lock progress is continuous from 0 to 1 over 72 pt. Reaching 1 locks once and emits success haptic feedback.
- Left cancellation progress is continuous over 70 pt. Crossing the threshold cancels once and emits warning haptic feedback.
- Releasing in `recordingHeld` sends. Releasing in `recordingLocked` keeps recording.
- The existing 60-second maximum remains. Reaching it sends automatically from either held or locked mode.
- Recordings shorter than 0.5 seconds are discarded with error feedback, matching Telegram's guard against accidental clips.

The gesture must be local to the microphone. No full-composer `DragGesture` is added, so ordinary chat scrolling remains owned by the collection view.

## Visual design

### Held recording

- Replace the small microphone with a 110 pt circle using the same animated Aurora mesh and clear Liquid Glass treatment as the Welcome login button.
- Add a 160 pt aura made from that same Aurora mesh behind it, so the center and halo remain one visual material.
- Scale the aura from `110 / 160` toward full size using the smoothed live microphone level.
- Keep a white microphone glyph centered and enlarge it proportionally.
- Present the circle and aura with an interruptible spring and opacity transition; dismiss in 180 ms.
- Show a vertical glass lock pill above the microphone. Its lock glyph and translation follow lock progress directly.
- Show a leftward cancel affordance in the recording bar whose translation and opacity follow cancellation progress.

### Locked recording

- Settle the microphone back into the composer with a short spring.
- Replace the hold hints with the existing live waveform, timer, delete control, and explicit send control.
- The lock completion should feel conclusive: one haptic, a brief lock-glyph settle, and no looping celebration.

### Reduced motion

When Reduce Motion is enabled, retain opacity, color, and state changes but remove large positional travel and aura spring overshoot. The aura may still react subtly to audio because it communicates recording activity.

## Haptics

- Light impact when recording actually starts, not on initial touch-down.
- Selection-style ticks while crossing meaningful lock-progress intervals; never on every frame.
- Success feedback when lock commits.
- Warning/error feedback when cancellation or too-short recording completes.

Haptics are state-transition driven so reversing the drag does not produce duplicate lock or cancellation feedback.

## Audio and data flow

No backend or message-format changes are needed. The gesture continues to call the existing `AudioRecordingManager`, which already captures real waveform samples and returns `RecordedVoiceNote`. The existing send flow persists those samples for sent and received messages.

Cancellation stops the recorder and discards its result. Sending stops the recorder and forwards the recorded data, duration, and waveform exactly once.

## Accessibility

- The microphone remains a semantic button with a clear recording hint.
- VoiceOver activation cannot depend on a hold-and-drag gesture. Its primary action starts hands-free recording directly; while recording, accessible Cancel and Send actions are exposed.
- Announce “Recording started”, “Recording locked”, and “Recording cancelled” through localized accessibility notifications.
- Keep all visible controls at least 44 by 44 pt even when their artwork is smaller.

## Components and files

- `ChatInputViews.swift`: gesture surface, recording overlay, lock/cancel progress, and locked controls.
- `GlassmorphicChatView.swift`: explicit recording interaction state and progress.
- `GlassmorphicChatView+ComposerAndChrome.swift`: bindings and callbacks between the composer and screen.
- `GlassmorphicChatView+Voice.swift`: token-safe start, lock, cancel, send, and timeout transitions.
- `VoiceNotes.swift`: reuse live microphone level; add no second recorder.
- Localizations: hints and VoiceOver announcements in all supported app languages.

The visual pieces should be extracted into focused SwiftUI views rather than expanding `GlassmorphicInputBar.body` with the full interaction.

## Error handling

- Permission denied: return to `idle` and show the existing microphone-permission error.
- Permission response after release: ignore it using the interaction token.
- Recorder start failure: return to `idle`, clear timers/progress, and show the existing error surface.
- Interruption or view disappearance: cancel safely unless the recording is already finishing.
- Send/cancel actions are idempotent and cannot stop the recorder twice.

## Acceptance criteria

- A quick tap never creates a voice message.
- Holding starts recording after the threshold and shows the large microphone plus live aura.
- Releasing sends exactly one recording.
- Swiping upward locks; releasing afterward does not send.
- Locked mode can be explicitly cancelled or sent.
- Swiping left cancels without producing a message.
- The gesture does not block normal conversation scrolling.
- Permission and interruption races do not leave the composer stuck in recording UI.
- Reduce Motion and VoiceOver have complete alternative behavior.
- Existing real waveform persistence continues unchanged.

## Verification scope

The user will perform runtime testing. Implementation review will be limited to focused source inspection and diff checks; no build or automated test run will be performed unless requested later.
