function approvedModerationDecision(extra = {}) {
  return {
    action: 'approved',
    reason: 'Contenido apropiado',
    category: 'clean',
    visualScore: 0,
    audioScore: null,
    combinedScore: 0,
    provider: extra.provider || 'canonical',
    details: {},
    ...extra
  };
}

function warningModerationDecision(reason, category, extra = {}) {
  return {
    action: 'warning',
    reason,
    category,
    visualScore: 0,
    audioScore: null,
    combinedScore: 0,
    provider: extra.provider || 'canonical',
    details: {},
    ...extra
  };
}

function deletedModerationDecision(reason, category, extra = {}) {
  return {
    action: 'deleted',
    reason,
    category,
    visualScore: extra.visualScore ?? 1,
    audioScore: null,
    combinedScore: extra.combinedScore ?? extra.visualScore ?? 1,
    provider: extra.provider || 'canonical',
    details: {},
    ...extra
  };
}

function mergeModerationDecisions(decisions = []) {
  const validDecisions = decisions.filter(Boolean);
  if (validDecisions.length === 0) {
    return approvedModerationDecision();
  }

  const deleted = validDecisions.find((item) => item.action === 'deleted');
  if (deleted) return deleted;

  const warning = validDecisions.find((item) => item.action === 'warning');
  if (warning) return warning;

  return validDecisions[0];
}

module.exports = {
  approvedModerationDecision,
  warningModerationDecision,
  deletedModerationDecision,
  mergeModerationDecisions
};
