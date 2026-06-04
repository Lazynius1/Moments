# Backend Media Moderation Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move media moderation decisions to Firebase Functions and add Amazon Rekognition as a fallback when Sightengine fails.

**Architecture:** Firebase Functions becomes the source of truth for image, video, and sticker moderation decisions. The iOS app keeps its existing upload flow, but `MediaModerationService` becomes a thin client that sends media references to the backend and applies the returned action locally.

**Tech Stack:** Firebase Functions v2, ffmpeg-static, OpenAI Moderation, Google Speech-to-Text, Amazon Rekognition, Swift iOS client

---

### Task 1: Functions backend moderation endpoint

**Files:**
- Modify: `functions/index.js`
- Modify: `functions/package.json`

- [ ] Add AWS Rekognition dependency and secrets wiring.
- [ ] Add a new `moderateMediaContent` HTTPS function that handles:
  - images by URL
  - videos by Firebase Storage URL
  - sticker images by inline base64
- [ ] Implement `Sightengine -> Rekognition -> warning/pending` fallback behavior.
- [ ] Keep `OpenAI` moderation for transcribed video audio inside the backend.

### Task 2: iOS client migration

**Files:**
- Modify: `Moments/Moments/Moderation/MediaModerationService.swift`

- [ ] Add backend response decoding types.
- [ ] Route image moderation to the new backend function.
- [ ] Route video moderation to the new backend function.
- [ ] Route sticker moderation to the new backend function.
- [ ] Preserve existing hide/review flows by mapping backend decisions back into `MediaModerationAction`.

### Task 3: Verification

**Files:**
- Modify: `functions/index.js`
- Modify: `Moments/Moments/Moderation/MediaModerationService.swift`

- [ ] Run static validation for Functions.
- [ ] Run whitespace checks in both repos.
- [ ] Attempt build verification where the local environment allows it.
