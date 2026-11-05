const b = require('../bootstrap');
const { onDocumentWritten, admin } = b;
const { changedPrivateFields, relationChanges } = require('../helpers/private-account');

/**
 * Fase 1 de la migración: lo que cualquier versión de la app escriba en la ficha pública
 * se copia al documento privado, que así está siempre al día. Al borrar la ficha se borra.
 */
// Salta con cada escritura de la ficha (también el «en línea»): fracción de CPU para no
// agotar la cuota regional de Cloud Run, que comparten todas las funciones.
const LIGHT_TRIGGER = { cpu: 'gcf_gen1', concurrency: 1, maxInstances: 3 };

const mirrorPrivateAccountFields = onDocumentWritten({ ...LIGHT_TRIGGER, document: 'users/{userId}' }, async (event) => {
  const privateRef = admin.firestore().doc(`users/${event.params.userId}/private/account`);
  const after = event.data && event.data.after && event.data.after.exists ? event.data.after.data() : null;
  if (!after) {
    await privateRef.delete().catch(() => {});
    await admin.firestore().doc(`users/${event.params.userId}/private/relations`).delete().catch(() => {});
    return;
  }
  const before = event.data.before && event.data.before.exists ? event.data.before.data() : {};
  const changes = changedPrivateFields(before, after);
  if (!Object.keys(changes).length) return;
  await privateRef.set(
    { ...changes, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );
});

/**
 * Mantiene el índice inverso: al bloquear o añadir a mejores amigos, el otro usuario
 * recibe en su `private/relations` quién le ha bloqueado (`blockedBy`) o de quién es
 * mejor amigo (`bestFriendOf`).
 */
const syncPrivateRelations = onDocumentWritten({ ...LIGHT_TRIGGER, document: 'users/{userId}/private/account' }, async (event) => {
  const ownerId = event.params.userId;
  const before = event.data && event.data.before && event.data.before.exists ? event.data.before.data() : null;
  const after = event.data && event.data.after && event.data.after.exists ? event.data.after.data() : null;
  const changes = relationChanges(before, after).filter(change => change.targetId !== ownerId);
  if (!changes.length) return;

  const db = admin.firestore();
  const { arrayUnion, arrayRemove } = admin.firestore.FieldValue;
  for (let i = 0; i < changes.length; i += 400) {
    const batch = db.batch();
    for (const { targetId, inverse, added } of changes.slice(i, i + 400)) {
      batch.set(
        db.doc(`users/${targetId}/private/relations`),
        { [inverse]: added ? arrayUnion(ownerId) : arrayRemove(ownerId) },
        { merge: true }
      );
    }
    await batch.commit();
  }
});

module.exports = {
  mirrorPrivateAccountFields,
  syncPrivateRelations
};
