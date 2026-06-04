# Aligned Media Moderation Providers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sightengine remains primary and Rekognition fallback, but both map into one canonical signal model and one Instagram-aligned policy so the same photo gets the same decision regardless of provider.

**Architecture:** Add a small moderation module under `functions/moderation/`. Each provider adapter translates raw API output into `CanonicalModerationSignals`. A single `evaluateModerationPolicy(signals, settings)` returns `{ action, reason, category, visualScore, details }`. `moderateImageBufferWithFallback` calls Sightengine → adapter → policy; on failure, Rekognition → adapter → policy. Admin thresholds in Firestore `moderationSettings/media` become the single source of truth for both providers.

**Tech Stack:** Firebase Functions v2, Sightengine nudity-2.1, AWS Rekognition v7, Node 22 `node:test`, Firestore

---

## Design principles (Instagram-aligned)

| Decision | When | User-visible effect |
|----------|------|---------------------|
| `approved` | Allowed social context (male underwear, bare chest, bikini, gym/beach) without explicit sexual activity | Content stays public |
| `warning` | Suggestive but not explicit; queue for human review | Content stays public |
| `deleted` | Explicit sexual activity, explicit female nudity, minors, severe violence/hate | Content hidden |

**Never delete** for these alone:
- Male swimwear / underwear (Sightengine `male_underwear`, Rekognition `Male Swimwear or Underwear`)
- Bare male chest (Sightengine `male_chest`, Rekognition `Exposed Male Nipple`)
- Female bikini / one-piece swimwear
- Female lingerie in fashion context (warning only if very suggestive)
- Implied nudity / erotica **when** allowed context dominates and `sexual_activity` is low

**Female-specific (asymmetric vs male):**
- No `allowedFemaleChest` — female topless / exposed nipple → always `explicitFemaleIntimateExposure` → delete
- Bikini mirror selfie = same treatment as male boxer selfie (context override)
- Very revealing cleavage → warning, not delete
- Lingerie + suggestive pose → warning

**Always delete** (regardless of provider):
- `sexual_activity` above delete threshold
- Explicit female genitalia / nipple exposure above threshold
- Explicit sexual situations (not mere suggestive pose)

---

## Canonical signal model

```javascript
// functions/moderation/canonicalSignals.js
const EMPTY_SIGNALS = {
  explicitSexualActivity: 0,      // acts, intercourse, explicit situations
  explicitSexualDisplay: 0,     // exposed genitalia / explicit nudity (non-allowed)
  suggestive: 0,                // poses, focus, mild suggestive
  allowedMaleUnderwear: 0,      // context: boxer, swimwear male
  allowedMaleChest: 0,
  allowedFemaleSwimwear: 0,
  impliedNudity: 0,             // erotica, implied, partial (non-explicit)
  violence: 0,
  hate: 0,
  scam: 0,
  offensive: 0,
  provider: '',
  raw: null                     // original payload fragment for logs
};
```

Both adapters must populate this structure. Policy never reads provider-specific fields directly.

---

## Policy rules (single source of truth)

```javascript
// functions/moderation/policy.js — default thresholds (overridable from Firestore)
const DEFAULT_POLICY = {
  delete: {
    explicitSexualActivity: 0.95,
    explicitSexualDisplay: 0.95,
    violence: 0.85,
    hate: 0.90,
    scam: 0.98,
    offensive: 0.90
  },
  warning: {
    explicitSexualActivity: 0.90,
    explicitSexualDisplay: 0.90,
    suggestive: 0.92,
    impliedNudity: 0.90,
    violence: 0.75
  },
  contextOverride: {
    minAllowedContext: 0.55,      // male_underwear OR bikini OR male_chest
    maxExplicitActivityForOverride: 0.20,
    maxExplicitDisplayForOverride: 0.92  // suppress false genitalia on tight underwear
  }
};
```

**Policy algorithm (order matters):**

1. If `allowedMaleUnderwear` or `allowedMaleChest` or `allowedFemaleSwimwear` ≥ `minAllowedContext` **and** `explicitSexualActivity` < `maxExplicitActivityForOverride` **and** `explicitSexualDisplay` < `maxExplicitDisplayForOverride` → cap blocking scores; treat `impliedNudity` as suggestive only.
2. Evaluate delete thresholds on `explicitSexualActivity`, `explicitSexualDisplay`, `violence`, `hate`, `scam`, `offensive`.
3. Evaluate warning thresholds on remaining adult signals.
4. Return `approved`.

This makes the boxer-brief mirror selfie pass on both providers when underwear + chest dominate and there is no sexual activity.

---

## Provider adapters

### Sightengine adapter

**File:** `functions/moderation/adapters/sightengine.js`

Map nudity-2.1 fields:

| Canonical field | Sightengine source |
|-----------------|-------------------|
| `explicitSexualActivity` | `nudity.sexual_activity` |
| `explicitSexualDisplay` | `nudity.sexual_display` |
| `impliedNudity` | `max(nudity.erotica, nudity.sexting)` |
| `suggestive` | `max(nudity.very_suggestive, nudity.suggestive, suggestive_classes.suggestive_pose, suggestive_classes.suggestive_focus)` |
| `allowedMaleUnderwear` | `nudity.suggestive_classes.male_underwear`, `swimwear_male` |
| `allowedMaleChest` | `nudity.suggestive_classes.male_chest`, `male_chest_categories.*` |
| `allowedFemaleSwimwear` | `bikini`, `lingerie` (swimwear only if context sea/pool — optional phase 2) |
| `scam` | `scam.prob` |
| `offensive` | `offensive.prob` |

Do **not** fold `erotica` into `explicitSexualDisplay`; keep it in `impliedNudity`.

### Rekognition adapter

**File:** `functions/moderation/adapters/rekognition.js`

Support **v6.1 and v7** label names (lowercased match):

| Canonical field | Rekognition labels (name or parent) |
|-----------------|-------------------------------------|
| `allowedMaleUnderwear` | `male swimwear or underwear`, `swimwear or underwear` |
| `allowedMaleChest` | `barechested male`, `exposed male nipple` |
| `allowedFemaleSwimwear` | `female swimwear or underwear` |
| `explicitSexualActivity` | `sexual activity`, `explicit sexual activity`, `sexual situations` |
| `explicitSexualDisplay` | `graphic female nudity`, `exposed female genitalia`, `exposed female nipple`, `exposed buttocks or anus` — **exclude** when `allowedMaleUnderwear` ≥ 0.55 (false positive guard for `exposed male genitalia` on tight underwear) |
| `impliedNudity` | `implied nudity`, `partial nudity`, `obstructed intimate parts`, `non-explicit nudity` |
| `suggestive` | `suggestive`, `revealing clothes` |
| `violence` | `violence`, `graphic violence`, `weapon violence`, `physical violence` |
| `hate` | `hate symbols`, `nazi party`, `white supremacy`, `extremist` |

**Explicit male genitalia:** only count toward `explicitSexualDisplay` if `allowedMaleUnderwear` < 0.55 (not wearing underwear context).

---

## Firestore settings wiring

**Files:**
- Modify: `functions/moderation/policy.js`
- Modify: `functions/index.js` (`moderateMediaContent`)
- Already exists: `moments-admin-panel/pages/api/media-moderation-settings.js`

- [ ] Load `moderationSettings/media` once per request (or cache 60s in memory).
- [ ] Map admin panel fields to policy keys:

```javascript
// Firestore → policy mapping
deleteThresholds.adult      → delete.explicitSexualActivity + delete.explicitSexualDisplay
deleteThresholds.racy       → warning.suggestive + warning.impliedNudity (NOT delete)
deleteThresholds.violence   → delete.violence
deleteThresholds.spoofed    → delete.scam
warningThresholds.*         → warning.*
moderationMode              → multiplier: strict 0.85, balanced 1.0, permissive 1.1 on delete thresholds only
```

- [ ] Update admin panel copy: `racy` controls **warning/review**, not auto-delete (matches Instagram behavior).

---

## File structure

```
Moments/functions/
  moderation/
    canonicalSignals.js      # EMPTY_SIGNALS, merge helper
    policy.js                # loadPolicySettings, evaluateModerationPolicy
    adapters/
      sightengine.js         # sightenginePayloadToSignals
      rekognition.js         # rekognitionLabelsToSignals
    moderateImage.js           # moderateImageBufferWithFallback (orchestrator)
  test/
    moderation/
      policy.test.js
      sightengineAdapter.test.js
      rekognitionAdapter.test.js
  index.js                     # require orchestrator; remove inline evaluate* functions
```

---

### Task 1: Canonical model + policy engine

**Files:**
- Create: `functions/moderation/canonicalSignals.js`
- Create: `functions/moderation/policy.js`
- Create: `functions/test/moderation/policy.test.js`
- Modify: `functions/package.json` (add `"test": "node --test test/**/*.test.js"`)

- [ ] **Step 1: Write failing policy tests**

```javascript
// functions/test/moderation/policy.test.js
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { evaluateModerationPolicy } = require('../../moderation/policy');

test('approves male underwear mirror selfie pattern', () => {
  const decision = evaluateModerationPolicy({
    explicitSexualActivity: 0.02,
    explicitSexualDisplay: 0.88,
    suggestive: 0.70,
    allowedMaleUnderwear: 0.92,
    allowedMaleChest: 0.85,
    allowedFemaleSwimwear: 0,
    impliedNudity: 0.75,
    violence: 0, hate: 0, scam: 0, offensive: 0
  });
  assert.equal(decision.action, 'approved');
});

test('deletes explicit sexual activity', () => {
  const decision = evaluateModerationPolicy({
    explicitSexualActivity: 0.97,
    explicitSexualDisplay: 0.10,
    suggestive: 0, allowedMaleUnderwear: 0, allowedMaleChest: 0,
    allowedFemaleSwimwear: 0, impliedNudity: 0,
    violence: 0, hate: 0, scam: 0, offensive: 0
  });
  assert.equal(decision.action, 'deleted');
});
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `cd Moments/functions && npm test`
Expected: FAIL — module not found

- [ ] **Step 3: Implement `canonicalSignals.js` and `policy.js` with context override + DEFAULT_POLICY**

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add functions/moderation functions/test/moderation/policy.test.js functions/package.json
git commit -m "feat(moderation): add canonical policy engine for aligned provider decisions"
```

---

### Task 2: Sightengine adapter

**Files:**
- Create: `functions/moderation/adapters/sightengine.js`
- Create: `functions/test/moderation/sightengineAdapter.test.js`

- [ ] **Step 1: Write failing adapter test** using fixture JSON (male underwear high, sexual_activity low)

- [ ] **Step 2: Implement `sightenginePayloadToSignals(payload)`**

- [ ] **Step 3: Test passes; commit**

```bash
git commit -m "feat(moderation): map Sightengine nudity-2.1 to canonical signals"
```

---

### Task 3: Rekognition adapter (v6 + v7)

**Files:**
- Create: `functions/moderation/adapters/rekognition.js`
- Create: `functions/test/moderation/rekognitionAdapter.test.js`

- [ ] **Step 1: Write failing tests**

Fixtures:
- v7: `Male Swimwear or Underwear` 95%, `Exposed Male Genitalia` 91%, `Exposed Male Nipple` 88%
- v6: `Male Swimwear Or Underwear` 95%, `Graphic Male Nudity` 90%

Expected: `allowedMaleUnderwear` high, `explicitSexualDisplay` capped / zero after context guard.

- [ ] **Step 2: Implement `rekognitionLabelsToSignals(labels)`**

- [ ] **Step 3: Tests pass; commit**

```bash
git commit -m "feat(moderation): map Rekognition v7 labels to canonical signals"
```

---

### Task 4: Orchestrator + index.js integration

**Files:**
- Create: `functions/moderation/moderateImage.js`
- Modify: `functions/index.js` — replace `evaluateSightenginePayload`, `evaluateRekognitionLabels`, inline `moderateImageBufferWithFallback`

- [ ] **Step 1: Implement orchestrator**

```javascript
// functions/moderation/moderateImage.js
async function moderateImageBufferWithFallback(imageBuffer, { loadPolicy }) {
  let policy;
  try { policy = await loadPolicy(); } catch { policy = DEFAULT_POLICY; }

  try {
    const payload = await callSightengineModeration(imageBuffer);
    const signals = sightenginePayloadToSignals(payload);
    return evaluateModerationPolicy(signals, policy, { provider: 'sightengine', raw: payload });
  } catch (sightengineError) {
    try {
      const payload = await callRekognitionModeration(imageBuffer);
      const signals = rekognitionLabelsToSignals(payload.ModerationLabels || []);
      const decision = evaluateModerationPolicy(signals, policy, { provider: 'rekognition', raw: payload });
      decision.details = { ...decision.details, fallbackUsed: true, primaryProviderError: sightengineError.message };
      return decision;
    } catch (rekognitionError) {
      return warningModerationDecision('Revisión manual pendiente...', 'system_error', { ... });
    }
  }
}
```

- [ ] **Step 2: Wire `loadPolicy` to Firestore `moderationSettings/media`**

- [ ] **Step 3: Remove dead `evaluateSightenginePayload` / `evaluateRekognitionLabels` from index.js**

- [ ] **Step 4: Deploy to staging; verify logs show `canonicalSignals` summary in `details`**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(moderation): unify Sightengine and Rekognition through canonical policy"
```

---

### Task 5: Admin panel alignment

**Files:**
- Modify: `moments-admin-panel/src/app/admin/hidden/MediaModerationSensitivityPanel.tsx`
- Modify: `moments-admin-panel/pages/api/media-moderation-settings.js`

- [ ] Update default thresholds to match `DEFAULT_POLICY` (delete adult 0.95, racy → warning-only labels in UI)
- [ ] Add helper text: "Contenido sugerente (racy) → revisión manual, no ocultación automática"
- [ ] Add read-only section showing active policy version + last sync timestamp

- [ ] Commit admin panel copy/threshold alignment

---

### Task 6: Regression matrix (manual + logged)

**Files:**
- Create: `Moments/docs/moderation-regression-matrix.md`

Test cases (same expected `approved` on both providers when each is available):

| Case | Expected |
|------|----------|
| Male mirror selfie, boxer briefs, torso | `approved` |
| Shirtless male gym photo | `approved` |
| Female bikini beach | `approved` |
| Explicit sexual act (test image from provider docs) | `deleted` |
| Graphic violence | `deleted` |
| Suggestive pose, no nudity | `warning` or `approved` |

- [ ] Run each case twice (force Sightengine path, force Rekognition path via temporary env `MODERATION_FORCE_PROVIDER`)
- [ ] Log `provider`, `action`, top 3 canonical signals in `mediaModerationLogs`
- [ ] Document results in regression matrix

---

### Task 7: Optional — force provider flag for ops

**Files:**
- Modify: `functions/moderation/moderateImage.js`

- [ ] Add env `MODERATION_FORCE_PROVIDER=sightengine|rekognition` for debugging (default: normal fallback chain)
- [ ] Document in `Moments/docs/superpowers/plans/2026-06-04-backend-media-moderation-migration.md`

---

## iOS client

**No changes required.** `MediaModerationService` already consumes `{ action, reason, category, provider }` from `moderateMediaContent`. Remove stale client-side `combineFrameResults` thresholds in a follow-up cleanup PR (dead code).

---

## Rollout

1. Deploy backend with new module; monitor `fallbackUsed: true` rate (expect ~100% until Sightengine credits return).
2. Validate boxer-brief regression case passes on Rekognition.
3. When Sightengine credits return, confirm same cases pass without changing policy.
4. Tune `contextOverride.maxExplicitDisplayForOverride` in admin panel if false positives persist (start 0.92, adjust ±0.03).

---

## Success criteria

- Same canonical policy function for both providers
- Male underwear + torso photos: `approved` on Rekognition (current gap fixed)
- Explicit content: `deleted` on both providers
- Admin panel thresholds affect live moderation
- Unit tests cover policy + both adapters
- Logs include canonical signals for debugging
