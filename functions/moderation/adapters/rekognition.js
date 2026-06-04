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

  for (const label of labels) {
    const text = labelText(label);
    const confidence = readConfidence(label);
    const name = String(label?.Name || '').toLowerCase();

    if (includesAny(text, ['male swimwear or underwear', 'swimwear or underwear']) && includesAny(name, ['male'])) {
      signals.allowedMaleUnderwear = Math.max(signals.allowedMaleUnderwear, confidence);
      continue;
    }

    if (includesAny(text, ['barechested male', 'exposed male nipple'])) {
      signals.allowedMaleChest = Math.max(signals.allowedMaleChest, confidence);
      continue;
    }

    if (includesAny(text, ['female swimwear or underwear', 'swimwear or underwear']) && includesAny(name, ['female'])) {
      signals.allowedFemaleSwimwear = Math.max(signals.allowedFemaleSwimwear, confidence);
      signals.allowedFemaleLingerie = Math.max(signals.allowedFemaleLingerie, confidence * 0.85);
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
      signals.impliedNudity = Math.max(signals.impliedNudity, confidence);
      continue;
    }

    if (includesAny(text, ['suggestive', 'revealing clothes'])) {
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

  return signals;
}

module.exports = {
  rekognitionLabelsToSignals
};
