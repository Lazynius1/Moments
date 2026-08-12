const { createEmptySignals } = require('../canonicalSignals');

function readProb(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function maxProb(values) {
  return values.reduce((max, value) => Math.max(max, readProb(value)), 0);
}

function sightenginePayloadToSignals(payload) {
  const nudity = payload?.nudity || {};
  const scam = payload?.scam || {};
  const offensive = payload?.offensive || {};
  const classes = nudity.suggestive_classes || {};
  const cleavageCategories = classes.cleavage_categories || {};
  const maleChestCategories = classes.male_chest_categories || {};
  const context = nudity.context || {};

  const maleUnderwear = maxProb([classes.male_underwear, classes.swimwear_male]);
  const maleChest = maxProb([
    classes.male_chest,
    maleChestCategories.revealing,
    maleChestCategories.very_revealing,
    maleChestCategories.slightly_revealing
  ]);
  const femaleSwimwear = maxProb([classes.bikini, classes.swimwear_one_piece]);
  const femaleLingerie = readProb(classes.lingerie);
  const casualBottoms = maxProb([classes.miniskirt, classes.minishort]);

  const hasFemaleFashionContext = femaleSwimwear >= 0.55 || femaleLingerie >= 0.55;
  const explicitFemaleIntimateExposure = hasFemaleFashionContext
    ? Math.max(
      readProb(classes.visibly_undressed),
      readProb(cleavageCategories.very_revealing) >= 0.92 ? readProb(nudity.sexual_display) : 0
    )
    : Math.max(readProb(nudity.sexual_display), readProb(classes.visibly_undressed));

  // Clothing / mild fashion cues are NOT risk signals. Risk suggestive = sexualized pose/focus
  // or clear suggestive/very_suggestive scores from the provider.
  return createEmptySignals({
    explicitSexualActivity: readProb(nudity.sexual_activity),
    explicitSexualDisplay: readProb(nudity.sexual_display),
    explicitFemaleIntimateExposure,
    suggestive: maxProb([
      nudity.very_suggestive,
      nudity.suggestive,
      classes.suggestive_pose,
      classes.suggestive_focus
    ]),
    allowedMaleUnderwear: maleUnderwear,
    allowedMaleChest: maleChest,
    allowedFemaleSwimwear: femaleSwimwear,
    allowedFemaleLingerie: femaleLingerie,
    allowedCasualBottoms: casualBottoms,
    femaleCleavageRevealing: readProb(cleavageCategories.revealing),
    femaleCleavageVeryRevealing: readProb(cleavageCategories.very_revealing),
    impliedNudity: maxProb([nudity.erotica, nudity.sexting, nudity.sextoy, classes.sextoy]),
    scam: readProb(scam.prob),
    offensive: readProb(offensive.prob),
    outdoorLeisureContext: maxProb([context.sea_lake_pool, context.outdoor_other]),
    indoorContext: readProb(context.indoor_other),
    provider: 'sightengine',
    raw: {
      nudity,
      scam,
      offensive
    }
  });
}

module.exports = {
  sightenginePayloadToSignals
};
