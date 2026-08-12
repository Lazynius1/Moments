# Moments Moderation Alignment Implementation Plan

> **For agentic workers:** Implement task-by-task with TDD.

**Goal:** Make Moments media moderation allow normal social photos (bikini, shorts, male chest) while still deleting explicit adult content; rename IG policy identifiers to Moments.

**Architecture:** Canonical signals from Sightengine + Rekognition feed one shared Moments policy evaluator.

**Tech Stack:** Node.js `node:test`, Cloud Functions moderation modules.

## Global Constraints

- No Instagram naming in moderation policy API (`moments-aligned-v1`, `applyMomentsContextOverride`)
- Clothing-only signals must not produce `adult` warnings
- Explicit sexual/nudity delete path must remain strict

---

## Task 1: Adapters + canonical signals

- [x] Update `canonicalSignals.js` with `allowedCasualBottoms`
- [x] Update `sightengine.js` mapping
- [x] Update `rekognition.js` mapping

## Task 2: Policy Moments override + categories

- [x] Rename Instagram → Moments
- [x] Dampen suggestive in allowed social contexts
- [x] Use `racy` for remaining suggestive warnings

## Task 3: Ship

- [x] Commit, push, PR (sin suite de tests a petición del producto)
