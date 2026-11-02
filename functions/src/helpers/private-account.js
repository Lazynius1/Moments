/**
 * Datos de la cuenta que no deben estar en la ficha pública `users/{uid}` (cualquiera con
 * sesión puede leerla). Su sitio es `users/{uid}/private/account`, que solo lee su dueño.
 */
const PRIVATE_ACCOUNT_FIELDS = ['email', 'birthDate', 'countryCode', 'fcmToken', 'blockedUsers', 'bestFriends'];

function sameValue(a, b) {
  if (a === b) return true;
  if (a == null || b == null) return false;
  if (Array.isArray(a) || Array.isArray(b)) {
    return Array.isArray(a) && Array.isArray(b)
      && a.length === b.length
      && a.every((value, index) => sameValue(value, b[index]));
  }
  if (typeof a.isEqual === 'function') {
    try {
      return a.isEqual(b);
    } catch (_) {
      return false;
    }
  }
  return false;
}

/** Campos privados que cambian entre `before` y `after` de la ficha pública. */
function changedPrivateFields(before, after) {
  const changes = {};
  for (const field of PRIVATE_ACCOUNT_FIELDS) {
    if (!Object.prototype.hasOwnProperty.call(after, field)) continue;
    if (sameValue(before[field], after[field])) continue;
    changes[field] = after[field];
  }
  return changes;
}

/**
 * Índice inverso para que cada usuario sepa, sin leer fichas ajenas, quién le ha
 * bloqueado y de quién es mejor amigo: `users/{uid}/private/relations`.
 */
const RELATION_FIELDS = { blockedUsers: 'blockedBy', bestFriends: 'bestFriendOf' };

function idSet(value) {
  return new Set((Array.isArray(value) ? value : []).filter(id => typeof id === 'string' && id));
}

/** Altas y bajas de cada lista entre dos versiones del documento privado. */
function relationChanges(before, after) {
  const changes = [];
  for (const [field, inverse] of Object.entries(RELATION_FIELDS)) {
    const previous = idSet(before && before[field]);
    const next = idSet(after && after[field]);
    for (const id of next) if (!previous.has(id)) changes.push({ targetId: id, inverse, added: true });
    for (const id of previous) if (!next.has(id)) changes.push({ targetId: id, inverse, added: false });
  }
  return changes;
}

module.exports = {
  PRIVATE_ACCOUNT_FIELDS,
  RELATION_FIELDS,
  changedPrivateFields,
  relationChanges
};
