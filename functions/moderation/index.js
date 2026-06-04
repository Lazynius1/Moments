const { sightenginePayloadToSignals } = require('./adapters/sightengine');
const { rekognitionLabelsToSignals } = require('./adapters/rekognition');
const { DEFAULT_POLICY, evaluateModerationPolicy } = require('./policy');
const { warningModerationDecision } = require('./decisions');

function createImageModerationService({
  callSightengineModeration,
  callRekognitionModeration,
  loadPolicy = async () => DEFAULT_POLICY,
  forceProvider = null
}) {
  async function moderateImageBufferWithFallback(imageBuffer) {
    let policy = DEFAULT_POLICY;
    try {
      policy = await loadPolicy();
    } catch (error) {
      console.warn('moderation policy load failed, using defaults:', error.message);
    }

    const providers = forceProvider === 'rekognition'
      ? ['rekognition']
      : forceProvider === 'sightengine'
        ? ['sightengine']
        : ['sightengine', 'rekognition'];

    let lastError = null;

    for (let index = 0; index < providers.length; index += 1) {
      const provider = providers[index];
      const fallbackUsed = provider === 'rekognition' && providers[0] === 'sightengine';

      try {
        if (provider === 'sightengine') {
          const payload = await callSightengineModeration(imageBuffer);
          const signals = sightenginePayloadToSignals(payload);
          return evaluateModerationPolicy(signals, policy, {
            provider: 'sightengine',
            details: { fallbackUsed: false }
          });
        }

        const payload = await callRekognitionModeration(imageBuffer);
        const signals = rekognitionLabelsToSignals(payload.ModerationLabels || []);
        const decision = evaluateModerationPolicy(signals, policy, {
          provider: 'rekognition',
          details: {
            fallbackUsed,
            moderationModelVersion: payload.ModerationModelVersion || null,
            ...(fallbackUsed && lastError ? { primaryProviderError: lastError.message } : {})
          }
        });
        return decision;
      } catch (error) {
        lastError = error;
        if (index === providers.length - 1) {
          break;
        }
      }
    }

    return warningModerationDecision(
      'Revisión manual pendiente por indisponibilidad temporal del sistema de moderación',
      'system_error',
      {
        provider: 'fallback_unavailable',
        visualScore: 0,
        combinedScore: 0,
        details: {
          fallbackUsed: true,
          primaryProviderError: lastError?.message || 'unknown'
        }
      }
    );
  }

  return {
    moderateImageBufferWithFallback
  };
}

module.exports = {
  createImageModerationService,
  sightenginePayloadToSignals,
  rekognitionLabelsToSignals,
  evaluateModerationPolicy,
  DEFAULT_POLICY
};
