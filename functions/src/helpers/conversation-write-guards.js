// Guardas puras para el trigger onDocumentWritten de conversations/{id}: deciden,
// sin lecturas extra, si una escritura afecta a alguna de sus tareas.

// Todos los participantes han ocultado la conversación (deletedFor).
function participantsAllDeleted(data) {
  if (!data) return false;
  const participants = data.participants;
  const deletedFor = data.deletedFor;
  if (!Array.isArray(participants) || participants.length === 0) return false;
  if (!Array.isArray(deletedFor) || deletedFor.length === 0) return false;
  return participants.every((uid) => deletedFor.includes(uid));
}

// Limpieza total solo en la transición a "todos la borraron". Los reintentos del
// mismo evento conservan before/after, así que siguen entrando.
function shouldRunConversationCleanup(before, after) {
  return participantsAllDeleted(after) && !participantsAllDeleted(before);
}

// Mismo criterio que el antiguo onConversationVanishModeChanged.
function vanishModeTurnedOff(before, after) {
  return !!before && !!after && before.vanishModeActive === true && after.vanishModeActive === false;
}

module.exports = {
  participantsAllDeleted,
  shouldRunConversationCleanup,
  vanishModeTurnedOff
};
