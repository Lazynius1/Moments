const { maxSignal, strongestAllowedContext } = require('./canonicalSignals');
const {
  approvedModerationDecision,
  warningModerationDecision,
  deletedModerationDecision
} = require('./decisions');

const DEFAULT_POLICY = {
  delete: {
    explicitSexualActivity: 0.95,
    explicitSexualDisplay: 0.95,
    explicitFemaleIntimateExposure: 0.90,
    violence: 0.85,
    hate: 0.90,
    scam: 0.98,
    offensive: 0.90
  },
  warning: {
    explicitSexualActivity: 0.90,
    explicitSexualDisplay: 0.90,
    suggestive: 0.88,
    impliedNudity: 0.90,
    femaleCleavageVeryRevealing: 0.82,
    violence: 0.75
  },
  contextOverride: {
    minAllowedContext: 0.55,
    maxExplicitActivityForOverride: 0.20,
    maxExplicitDisplayForOverride: 0.93
  }
};

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function applyModeMultiplier(policy, mode) {
  const multipliers = {
    strict: 0.88,
    balanced: 1.0,
    permissive: 1.08
  };
  const multiplier = multipliers[mode] || 1.0;
  if (multiplier === 1.0) {
    return policy;
  }

  const scaled = structuredClone(policy);
  for (const bucket of ['delete', 'warning']) {
    for (const key of Object.keys(scaled[bucket])) {
      scaled[bucket][key] = clamp(scaled[bucket][key] * multiplier, 0.1, 0.995);
    }
  }
  return scaled;
}

function policyFromFirestoreSettings(settings) {
  let policy = structuredClone(DEFAULT_POLICY);
  if (!settings || typeof settings !== 'object') {
    return policy;
  }

  const deleteThresholds = settings.deleteThresholds || {};
  const warningThresholds = settings.warningThresholds || {};

  if (typeof deleteThresholds.adult === 'number') {
    policy.delete.explicitSexualActivity = deleteThresholds.adult;
    policy.delete.explicitSexualDisplay = deleteThresholds.adult;
    policy.delete.explicitFemaleIntimateExposure = clamp(deleteThresholds.adult - 0.03, 0.85, 0.99);
  }
  if (typeof deleteThresholds.violence === 'number') {
    policy.delete.violence = deleteThresholds.violence;
    policy.warning.violence = clamp(deleteThresholds.violence - 0.1, 0.5, 0.95);
  }
  if (typeof deleteThresholds.spoofed === 'number') {
    policy.delete.scam = deleteThresholds.spoofed;
  }
  if (typeof deleteThresholds.offensive === 'number') {
    policy.delete.offensive = deleteThresholds.offensive;
    policy.delete.hate = deleteThresholds.offensive;
  }
  if (typeof warningThresholds.adult === 'number') {
    policy.warning.explicitSexualActivity = warningThresholds.adult;
    policy.warning.explicitSexualDisplay = warningThresholds.adult;
  }
  if (typeof warningThresholds.racy === 'number') {
    policy.warning.suggestive = warningThresholds.racy;
    policy.warning.impliedNudity = warningThresholds.racy;
    policy.warning.femaleCleavageVeryRevealing = clamp(warningThresholds.racy - 0.05, 0.5, 0.95);
  }
  if (typeof warningThresholds.violence === 'number') {
    policy.warning.violence = warningThresholds.violence;
  }

  return applyModeMultiplier(policy, settings.moderationMode || 'balanced');
}

function applyInstagramContextOverride(signals, policy) {
  const adjusted = { ...signals };
  const allowedContext = strongestAllowedContext(signals);
  const override = policy.contextOverride;

  if (allowedContext < override.minAllowedContext) {
    return adjusted;
  }
  if (signals.explicitSexualActivity >= override.maxExplicitActivityForOverride) {
    return adjusted;
  }
  if (signals.explicitFemaleIntimateExposure >= policy.delete.explicitFemaleIntimateExposure) {
    return adjusted;
  }

  if (signals.allowedMaleUnderwear >= override.minAllowedContext
      && signals.explicitSexualDisplay < override.maxExplicitDisplayForOverride) {
    adjusted.explicitSexualDisplay = Math.min(adjusted.explicitSexualDisplay, 0.35);
    adjusted.impliedNudity = Math.min(adjusted.impliedNudity, policy.warning.impliedNudity - 0.01);
  }

  if (signals.allowedMaleChest >= override.minAllowedContext
      && signals.explicitSexualActivity < override.maxExplicitActivityForOverride) {
    adjusted.impliedNudity = Math.min(adjusted.impliedNudity, policy.warning.impliedNudity - 0.01);
  }

  if (signals.allowedFemaleSwimwear >= override.minAllowedContext
      && signals.explicitFemaleIntimateExposure < policy.warning.explicitSexualDisplay) {
    adjusted.explicitSexualDisplay = Math.min(adjusted.explicitSexualDisplay, 0.45);
    adjusted.impliedNudity = Math.min(adjusted.impliedNudity, policy.warning.impliedNudity - 0.01);
  }

  if (signals.allowedFemaleLingerie >= override.minAllowedContext
      && signals.explicitFemaleIntimateExposure < policy.warning.explicitSexualDisplay) {
    adjusted.explicitSexualDisplay = Math.min(adjusted.explicitSexualDisplay, 0.55);
    adjusted.impliedNudity = Math.min(adjusted.impliedNudity, policy.warning.impliedNudity);
  }

  return adjusted;
}

function evaluateModerationPolicy(signals, policyInput = DEFAULT_POLICY, meta = {}) {
  const policy = policyInput || DEFAULT_POLICY;
  const adjusted = applyInstagramContextOverride(signals, policy);
  const visualScore = maxSignal(adjusted);
  const provider = meta.provider || adjusted.provider || 'canonical';
  const details = {
    provider,
    canonicalSignals: adjusted,
    policyVersion: 'instagram-aligned-v1',
    ...(meta.details || {})
  };

  if (adjusted.explicitFemaleIntimateExposure >= policy.delete.explicitFemaleIntimateExposure) {
    return deletedModerationDecision(
      'Desnudez explícita detectada',
      'adult',
      { provider, visualScore, combinedScore: visualScore, details }
    );
  }

  if (adjusted.explicitSexualActivity >= policy.delete.explicitSexualActivity) {
    return deletedModerationDecision(
      'Contenido sexual explícito detectado',
      'adult',
      { provider, visualScore, combinedScore: visualScore, details }
    );
  }

  if (adjusted.explicitSexualDisplay >= policy.delete.explicitSexualDisplay) {
    return deletedModerationDecision(
      'Contenido sexual explícito detectado',
      'adult',
      { provider, visualScore, combinedScore: visualScore, details }
    );
  }

  if (adjusted.violence >= policy.delete.violence) {
    return deletedModerationDecision(
      'Contenido violento extremo detectado',
      'violence',
      { provider, visualScore, combinedScore: visualScore, details }
    );
  }

  if (adjusted.hate >= policy.delete.hate) {
    return deletedModerationDecision(
      'Contenido ofensivo detectado',
      'offensive',
      { provider, visualScore, combinedScore: visualScore, details }
    );
  }

  if (adjusted.scam >= policy.delete.scam) {
    return deletedModerationDecision(
      'Posible fraude o falsificación',
      'scam',
      { provider, visualScore, combinedScore: visualScore, details }
    );
  }

  if (adjusted.offensive >= policy.delete.offensive) {
    return deletedModerationDecision(
      'Contenido ofensivo detectado',
      'offensive',
      { provider, visualScore, combinedScore: visualScore, details }
    );
  }

  if (adjusted.explicitSexualActivity >= policy.warning.explicitSexualActivity) {
    return warningModerationDecision(
      'Contenido potencialmente adulto',
      'adult',
      { provider, visualScore, combinedScore: visualScore, details }
    );
  }

  if (adjusted.explicitSexualDisplay >= policy.warning.explicitSexualDisplay) {
    return warningModerationDecision(
      'Contenido sugerente detectado',
      'adult',
      { provider, visualScore, combinedScore: visualScore, details }
    );
  }

  if (adjusted.femaleCleavageVeryRevealing >= policy.warning.femaleCleavageVeryRevealing) {
    return warningModerationDecision(
      'Contenido sugerente detectado para revisión',
      'adult',
      { provider, visualScore, combinedScore: visualScore, details }
    );
  }

  if (adjusted.suggestive >= policy.warning.suggestive) {
    return warningModerationDecision(
      'Contenido sugerente detectado para revisión',
      'adult',
      { provider, visualScore, combinedScore: visualScore, details }
    );
  }

  if (adjusted.impliedNudity >= policy.warning.impliedNudity) {
    return warningModerationDecision(
      'Contenido sugerente detectado para revisión',
      'adult',
      { provider, visualScore, combinedScore: visualScore, details }
    );
  }

  if (adjusted.allowedFemaleSwimwear >= policy.contextOverride.minAllowedContext
      && adjusted.indoorContext >= 0.55
      && adjusted.suggestive >= 0.70) {
    return warningModerationDecision(
      'Contenido sugerente detectado para revisión',
      'adult',
      { provider, visualScore, combinedScore: visualScore, details }
    );
  }

  if (adjusted.violence >= policy.warning.violence) {
    return warningModerationDecision(
      'Contenido potencialmente violento',
      'violence',
      { provider, visualScore, combinedScore: visualScore, details }
    );
  }

  return approvedModerationDecision({
    provider,
    visualScore,
    combinedScore: visualScore,
    details
  });
}

module.exports = {
  DEFAULT_POLICY,
  policyFromFirestoreSettings,
  applyInstagramContextOverride,
  evaluateModerationPolicy
};
