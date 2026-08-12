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

## Task 1: Unit tests for social-normal allow + explicit delete

- [ ] Add `functions/moderation/__tests__/policy.moments.test.js`
- [ ] Cover: minishort outdoor approve; male chest approve; bikini beach approve; sexual_activity delete; rename exports
- [ ] Add `npm test` script using `node --test`

## Task 2: Adapters + canonical signals

- [ ] Update `canonicalSignals.js` with `allowedCasualBottoms`
- [ ] Update `sightengine.js` mapping
- [ ] Update `rekognition.js` mapping

## Task 3: Policy Moments override + categories

- [ ] Rename Instagram → Moments
- [ ] Dampen suggestive in allowed social contexts
- [ ] Use `racy` for remaining suggestive warnings
- [ ] Export rename; keep backward-compat alias if needed (prefer clean rename)

## Task 4: Verify + ship

- [ ] `npm test` in functions
- [ ] Commit, push, PR
