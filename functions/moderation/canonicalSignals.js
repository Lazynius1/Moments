function createEmptySignals(extra = {}) {
  return {
    explicitSexualActivity: 0,
    explicitSexualDisplay: 0,
    explicitFemaleIntimateExposure: 0,
    suggestive: 0,
    allowedMaleUnderwear: 0,
    allowedMaleChest: 0,
    allowedFemaleSwimwear: 0,
    allowedFemaleLingerie: 0,
    femaleCleavageRevealing: 0,
    femaleCleavageVeryRevealing: 0,
    impliedNudity: 0,
    violence: 0,
    hate: 0,
    scam: 0,
    offensive: 0,
    outdoorLeisureContext: 0,
    indoorContext: 0,
    provider: '',
    raw: null,
    ...extra
  };
}

function maxSignal(signals) {
  return Math.max(
    signals.explicitSexualActivity,
    signals.explicitSexualDisplay,
    signals.explicitFemaleIntimateExposure,
    signals.suggestive,
    signals.impliedNudity,
    signals.violence,
    signals.hate,
    signals.scam,
    signals.offensive
  );
}

function strongestAllowedContext(signals) {
  return Math.max(
    signals.allowedMaleUnderwear,
    signals.allowedMaleChest,
    signals.allowedFemaleSwimwear,
    signals.allowedFemaleLingerie
  );
}

module.exports = {
  createEmptySignals,
  maxSignal,
  strongestAllowedContext
};
