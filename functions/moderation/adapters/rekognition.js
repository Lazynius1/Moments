const { createEmptySignals } = require('../canonicalSignals');

function readConfidence(label) {
  return Number(label?.Confidence || 0) / 100;
}

function labelText(label) {
  const name = String(label?.Name || '').toLowerCase();
  const parent = String(label?.ParentName || '').toLowerCase();
  return `${name} ${parent}`.trim();
}

function includesAny(text, needles) {
  return needles.some((needle) => text.includes(needle));
}

function rekognitionLabelsToSignals(labels = []) {
  const signals = createEmptySignals({ provider: 'rekognition', raw: labels });
  let revealingClothes = 0;

  for (const label of labels) {
    const text = labelText(label);
    const confidence = readConfidence(label);
    const name = String(label?.Name || '').toLowerCase();

    // Check female before male: the substring "male" also appears inside "female".
    if (name.includes('female swimwear') || (text.includes('female swimwear or underwear'))) {
      signals.allowedFemaleSwimwear = Math.max(signals.allowedFemaleSwimwear, confidence);
      signals.allowedFemaleLingerie = Math.max(signals.allowedFemaleLingerie, confidence * 0.85);
      continue;
    }

    if (name.includes('male swimwear') || (text.includes('male swimwear or underwear'))) {
      signals.allowedMaleUnderwear = Math.max(signals.allowedMaleUnderwear, confidence);
      continue;
    }

    if (includesAny(text, ['barechested male', 'exposed male nipple'])) {
      signals.allowedMaleChest = Math.max(signals.allowedMaleChest, confidence);
      continue;
    }

    if (includesAny(text, ['exposed female nipple', 'exposed female genitalia', 'graphic female nudity'])) {
      signals.explicitFemaleIntimateExposure = Math.max(signals.explicitFemaleIntimateExposure, confidence);
      signals.explicitSexualDisplay = Math.max(signals.explicitSexualDisplay, confidence);
      continue;
    }

    if (includesAny(text, ['exposed male genitalia', 'graphic male nudity'])) {
      if (signals.allowedMaleUnderwear < 0.55) {
        signals.explicitSexualDisplay = Math.max(signals.explicitSexualDisplay, confidence);
      }
      continue;
    }

    if (includesAny(text, ['sexual activity', 'explicit sexual activity', 'sexual situations'])) {
      signals.explicitSexualActivity = Math.max(signals.explicitSexualActivity, confidence);
      continue;
    }

    if (includesAny(text, ['explicit nudity', 'explicit'])) {
      if (includesAny(text, ['exposed buttocks or anus'])) {
        signals.explicitSexualDisplay = Math.max(signals.explicitSexualDisplay, confidence);
      }
      continue;
    }

    if (includesAny(text, ['implied nudity', 'partial nudity', 'obstructed intimate parts', 'non-explicit nudity'])) {
      // Non-explicit / bare chest parents often include this parent name; only keep as risk
      // when we do not already have a Moments-allowed body/clothing context.
      signals.impliedNudity = Math.max(signals.impliedNudity, confidence);
      continue;
    }

    if (includesAny(text, ['revealing clothes'])) {
      revealingClothes = Math.max(revealingClothes, confidence);
      continue;
    }

    if (includesAny(text, ['suggestive'])) {
      signals.suggestive = Math.max(signals.suggestive, confidence);
      continue;
    }

    if (includesAny(text, ['graphic violence', 'physical violence', 'weapon violence', 'violence', 'self-harm', 'explosions and blasts'])) {
      signals.violence = Math.max(signals.violence, confidence);
      continue;
    }

    if (includesAny(text, ['hate symbols', 'nazi party', 'white supremacy', 'extremist'])) {
      signals.hate = Math.max(signals.hate, confidence);
      continue;
    }
  }

  const hasAllowedSocialContext = Math.max(
    signals.allowedMaleUnderwear,
    signals.allowedMaleChest,
    signals.allowedFemaleSwimwear,
    signals.allowedFemaleLingerie,
    signals.allowedCasualBottoms
  ) >= 0.55;

  if (revealingClothes > 0) {
    if (hasAllowedSocialContext) {
      // Fashion/leisure clothing near an allow context is not warning-grade suggestive.
      signals.allowedCasualBottoms = Math.max(signals.allowedCasualBottoms, revealingClothes);
    } else {
      signals.suggestive = Math.max(signals.suggestive, revealingClothes);
    }
  }

  // Bare chest / swimwear often arrive under Non-Explicit Nudity parent; do not keep
  // clothing-context implied nudity as a risk when allow context is strong.
  if (hasAllowedSocialContext) {
    signals.impliedNudity = Math.min(signals.impliedNudity, 0.45);
  }

  return signals;
}

module.exports = {
  rekognitionLabelsToSignals
};
