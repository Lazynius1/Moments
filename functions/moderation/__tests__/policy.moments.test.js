const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const { sightenginePayloadToSignals } = require('../adapters/sightengine');
const { rekognitionLabelsToSignals } = require('../adapters/rekognition');
const {
  DEFAULT_POLICY,
  evaluateModerationPolicy,
  applyMomentsContextOverride
} = require('../policy');

describe('Moments social-normal media moderation', () => {
  it('approves outdoor casual shorts (Sightengine minishort)', () => {
    const signals = sightenginePayloadToSignals({
      nudity: {
        sexual_activity: 0,
        sexual_display: 0,
        very_suggestive: 0.05,
        suggestive: 0.1,
        mildly_suggestive: 0.4,
        suggestive_classes: {
          minishort: 0.99,
          miniskirt: 0,
          other: 0.2,
          suggestive_pose: 0.05,
          suggestive_focus: 0.05
        },
        context: {
          outdoor_other: 0.8,
          sea_lake_pool: 0,
          indoor_other: 0.05
        }
      }
    });

    assert.ok(signals.allowedCasualBottoms >= 0.99);
    assert.ok(signals.suggestive < 0.88, `suggestive should not be clothing-driven, got ${signals.suggestive}`);

    const decision = evaluateModerationPolicy(signals, DEFAULT_POLICY, { provider: 'sightengine' });
    assert.equal(decision.action, 'approved');
    assert.equal(decision.details.policyVersion, 'moments-aligned-v1');
  });

  it('approves male bare chest selfie (Sightengine + Moments override)', () => {
    const signals = sightenginePayloadToSignals({
      nudity: {
        sexual_activity: 0,
        sexual_display: 0.1,
        erotica: 0.55,
        suggestive: 0.92,
        very_suggestive: 0.2,
        mildly_suggestive: 0.3,
        suggestive_classes: {
          male_chest: 0.97,
          male_chest_categories: { revealing: 0.9 },
          suggestive_pose: 0.2
        },
        context: { indoor_other: 0.7, outdoor_other: 0.1 }
      }
    });

    assert.ok(signals.allowedMaleChest >= 0.9);
    const decision = evaluateModerationPolicy(signals, DEFAULT_POLICY, { provider: 'sightengine' });
    assert.equal(decision.action, 'approved');
  });

  it('approves bikini on the beach (Sightengine)', () => {
    const signals = sightenginePayloadToSignals({
      nudity: {
        sexual_activity: 0,
        sexual_display: 0.35,
        suggestive: 0.95,
        very_suggestive: 0.4,
        mildly_suggestive: 0.5,
        suggestive_classes: {
          bikini: 0.96,
          swimwear_one_piece: 0,
          lingerie: 0,
          cleavage_categories: { revealing: 0.4, very_revealing: 0.2 },
          suggestive_pose: 0.15
        },
        context: {
          sea_lake_pool: 0.9,
          outdoor_other: 0.2,
          indoor_other: 0.05
        }
      }
    });

    assert.ok(signals.allowedFemaleSwimwear >= 0.9);
    const decision = evaluateModerationPolicy(signals, DEFAULT_POLICY, { provider: 'sightengine' });
    assert.equal(decision.action, 'approved');
  });

  it('approves Rekognition barechested male + revealing clothes without explicit labels', () => {
    const signals = rekognitionLabelsToSignals([
      { Name: 'Barechested Male', ParentName: 'Non-Explicit Nudity', Confidence: 98 },
      { Name: 'Revealing Clothes', ParentName: 'Suggestive', Confidence: 97 }
    ]);

    assert.ok(signals.allowedMaleChest >= 0.9);
    const decision = evaluateModerationPolicy(signals, DEFAULT_POLICY, { provider: 'rekognition' });
    assert.equal(decision.action, 'approved');
  });

  it('approves Rekognition female swimwear beach-like labels', () => {
    const signals = rekognitionLabelsToSignals([
      { Name: 'Female Swimwear Or Underwear', ParentName: 'Non-Explicit Nudity', Confidence: 96 },
      { Name: 'Revealing Clothes', ParentName: 'Suggestive', Confidence: 94 }
    ]);

    assert.ok(signals.allowedFemaleSwimwear >= 0.9);
    const decision = evaluateModerationPolicy(signals, DEFAULT_POLICY, { provider: 'rekognition' });
    assert.equal(decision.action, 'approved');
  });

  it('still deletes explicit sexual activity', () => {
    const signals = sightenginePayloadToSignals({
      nudity: {
        sexual_activity: 0.97,
        sexual_display: 0.2,
        suggestive: 0.1,
        suggestive_classes: {},
        context: {}
      }
    });

    const decision = evaluateModerationPolicy(signals, DEFAULT_POLICY, { provider: 'sightengine' });
    assert.equal(decision.action, 'deleted');
    assert.equal(decision.category, 'adult');
  });

  it('labels remaining suggestive warnings as racy, not adult', () => {
    const signals = sightenginePayloadToSignals({
      nudity: {
        sexual_activity: 0,
        sexual_display: 0.1,
        suggestive: 0.2,
        very_suggestive: 0.93,
        suggestive_classes: {
          suggestive_pose: 0.91,
          suggestive_focus: 0.9,
          lingerie: 0.2,
          bikini: 0
        },
        context: { indoor_other: 0.8, outdoor_other: 0.05 }
      }
    });

    const decision = evaluateModerationPolicy(signals, DEFAULT_POLICY, { provider: 'sightengine' });
    assert.equal(decision.action, 'warning');
    assert.equal(decision.category, 'racy');
  });

  it('exports Moments context override (not Instagram naming)', () => {
    assert.equal(typeof applyMomentsContextOverride, 'function');
    const adjusted = applyMomentsContextOverride(
      {
        suggestive: 0.95,
        allowedFemaleSwimwear: 0.9,
        explicitSexualActivity: 0,
        explicitSexualDisplay: 0.2,
        explicitFemaleIntimateExposure: 0,
        impliedNudity: 0.4,
        allowedMaleUnderwear: 0,
        allowedMaleChest: 0,
        allowedFemaleLingerie: 0,
        allowedCasualBottoms: 0,
        outdoorLeisureContext: 0.9,
        indoorContext: 0.05,
        femaleCleavageVeryRevealing: 0,
        violence: 0,
        hate: 0,
        scam: 0,
        offensive: 0,
        provider: 'test'
      },
      DEFAULT_POLICY
    );
    assert.ok(adjusted.suggestive < DEFAULT_POLICY.warning.suggestive);
  });
});
