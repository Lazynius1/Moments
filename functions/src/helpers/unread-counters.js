// Contadores de no leídos desnormalizados en el documento de la conversación/grupo.
//
// Esquema: `unreadCounts.{uid}` (entero >= 0) junto al ya existente `readStatus.{uid}`.
// Invariante: el contador solo es válido mientras `readStatus[uid] === false`; si
// readStatus es true (o no existe) el valor efectivo es 0 aunque el reset aún no
// se haya aplicado. Sin contador y con readStatus false => desconocido (dato antiguo).
const { admin } = require('../bootstrap');

const UNREAD_FALLBACK_LIMIT = 100;
const INVALID_FCM_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token'
]);

function isNonNegativeInteger(value) {
  return Number.isInteger(value) && value >= 0;
}

// Valor efectivo del contador; null si es una conversación antigua sin contador.
function effectiveUnreadCount(data, uid) {
  const readStatus = (data && data.readStatus) || {};
  if (readStatus[uid] !== false) return 0;
  const value = ((data && data.unreadCounts) || {})[uid];
  return isNonNegativeInteger(value) ? value : null;
}

// Nuevo valor tras un mensaje entrante. `legacyFallback` ya incluye el mensaje actual.
function nextUnreadCount(data, uid, legacyFallback) {
  const current = effectiveUnreadCount(data, uid);
  if (current === null) {
    return isNonNegativeInteger(legacyFallback) ? Math.max(1, legacyFallback) : 1;
  }
  return current + 1;
}

// Participantes que ya leyeron pero conservan un contador > 0 (pendiente de reset).
function staleUnreadCounterUids(data) {
  if (!data) return [];
  const readStatus = data.readStatus || {};
  const counts = data.unreadCounts || {};
  return Object.keys(counts).filter((uid) => readStatus[uid] !== false && counts[uid] !== 0);
}

function timestampMillis(value) {
  return value && typeof value.toMillis === 'function' ? value.toMillis() : null;
}

function isVisibleIncoming(message, uid) {
  if (!message || message.senderId === uid) return false;
  if (message.isDeleted === true) return false;
  const deletedFor = Array.isArray(message.deletedFor) ? message.deletedFor : [];
  return !deletedFor.includes(uid);
}

// Cuenta no leídos sobre una página de mensajes ordenada por timestamp desc.
// Con lastReadAt: entrantes visibles posteriores. Sin él: racha más reciente de
// entrantes no leídos (mismo criterio que el cálculo histórico). Mínimo 1.
function countUnreadFromMessages(messages, uid, { lastReadMillis = null } = {}) {
  if (lastReadMillis !== null) {
    const count = messages.filter((message) => {
      if (!isVisibleIncoming(message, uid)) return false;
      const millis = timestampMillis(message.timestamp);
      return millis === null || millis > lastReadMillis;
    }).length;
    return Math.max(1, count);
  }

  let count = 0;
  for (const message of messages) {
    if (!message || message.isDeleted === true) continue;
    const deletedFor = Array.isArray(message.deletedFor) ? message.deletedFor : [];
    if (deletedFor.includes(uid)) continue;
    if (message.senderId === uid) break;
    const readBy = Array.isArray(message.readBy) ? message.readBy : [];
    if (readBy.includes(uid) || message.isRead === true || message.status === 'read') break;
    count += 1;
  }
  return Math.max(1, count);
}

// Fallback acotado para conversaciones sin contador: como mucho `limit` lecturas.
async function countUnreadMessagesBounded(conversationRef, uid, conversationData, limit = UNREAD_FALLBACK_LIMIT) {
  const lastReadValue = ((conversationData && conversationData.lastReadAt) || {})[uid];
  const lastReadMillis = timestampMillis(lastReadValue);
  let query = conversationRef.collection('messages');
  if (lastReadMillis !== null) {
    query = query.where('timestamp', '>', lastReadValue);
  }
  const snap = await query.orderBy('timestamp', 'desc').limit(limit).get();
  return countUnreadFromMessages(snap.docs.map((doc) => doc.data() || {}), uid, { lastReadMillis });
}

// Pone a 0 los contadores de quien ya leyó. Transaccional: si entre medias llega un
// mensaje nuevo (readStatus vuelve a false) no se toca ese contador.
async function resetReadUnreadCounters(docRef) {
  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    if (!snap.exists) return [];
    const uids = staleUnreadCounterUids(snap.data());
    if (uids.length === 0) return [];
    const update = {};
    uids.forEach((uid) => { update[`unreadCounts.${uid}`] = 0; });
    tx.update(docRef, update);
    return uids;
  });
}

function isInvalidFcmTokenError(error) {
  return !!error && INVALID_FCM_TOKEN_CODES.has(error.code);
}

module.exports = {
  UNREAD_FALLBACK_LIMIT,
  effectiveUnreadCount,
  nextUnreadCount,
  staleUnreadCounterUids,
  countUnreadFromMessages,
  countUnreadMessagesBounded,
  resetReadUnreadCounters,
  isInvalidFcmTokenError
};
