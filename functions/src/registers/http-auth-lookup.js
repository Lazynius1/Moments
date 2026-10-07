/**
 * Consultas de login sin sesión que antes se hacían leyendo `usernames` desde el cliente:
 * - resolveLoginEmail: username → email para iniciar sesión con nombre de usuario.
 * - checkEmailAvailable: ¿hay ya una cuenta con este email? (paso del correo en el alta).
 * Permiten cerrar `usernames` a `list` y dejar de guardar el email en ese índice público.
 *
 * Y la limpieza de visitas al bloquear: los clientes intentan borrar `visits/{otherUid}`,
 * pero las visitas se crean con ID aleatorio, así que se borran aquí por `visitorId`.
 */

const b = require('../bootstrap');

const { HttpsError, onCall, onDocumentWritten, admin, crypto } = b;

const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000;
const RATE_LIMIT_MAX_PER_WINDOW = 20;
// Debe servir como ID de documento de `usernames` (sin '/', ni '.'/'..', máx. 30 como en las reglas).
const USERNAME_PATTERN = /^[^/\s]{1,30}$/;
const EMAIL_MAX_LENGTH = 320;

function clientKey(request) {
  const raw = request.rawRequest || {};
  const forwarded = String((raw.headers && raw.headers['x-forwarded-for']) || '').split(',')[0].trim();
  const ip = forwarded || raw.ip || 'unknown';
  return crypto.createHash('sha256').update(ip).digest('hex');
}

/** Ventana fija por IP (hash). Lanza resource-exhausted al superar el cupo. */
async function enforceRateLimit(request, scope) {
  const db = admin.firestore();
  const ref = db.doc(`authLookupRateLimits/${scope}_${clientKey(request)}`);
  const now = Date.now();

  const allowed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const windowStart = snap.exists ? Number(snap.get('windowStart')) : 0;
    const count = snap.exists ? Number(snap.get('count')) : 0;
    const inWindow = Number.isFinite(windowStart) && now - windowStart < RATE_LIMIT_WINDOW_MS;

    if (inWindow && count >= RATE_LIMIT_MAX_PER_WINDOW) return false;

    tx.set(ref, {
      windowStart: inWindow ? windowStart : now,
      count: inWindow ? count + 1 : 1,
      expireAt: admin.firestore.Timestamp.fromMillis(now + RATE_LIMIT_WINDOW_MS * 2)
    });
    return true;
  });

  if (!allowed) {
    throw new HttpsError('resource-exhausted', 'Too many attempts, try again later');
  }
}

const resolveLoginEmail = onCall({ timeoutSeconds: 10 }, async (request) => {
  const username = String((request.data && request.data.username) || '').trim().toLowerCase();
  if (!USERNAME_PATTERN.test(username) || username === '.' || username === '..') {
    throw new HttpsError('invalid-argument', 'Invalid username');
  }

  await enforceRateLimit(request, 'resolveLoginEmail');

  const db = admin.firestore();
  const usernameDoc = await db.doc(`usernames/${username}`).get();
  if (!usernameDoc.exists) {
    throw new HttpsError('not-found', 'Username not found');
  }

  // El email del índice puede faltar (o dejar de guardarse); la fuente de verdad es Auth.
  const userId = String(usernameDoc.get('userId') || '').trim();
  let email = '';
  if (userId) {
    try {
      email = (await admin.auth().getUser(userId)).email || '';
    } catch (error) {
      if (error.code !== 'auth/user-not-found') throw error;
    }
  }
  if (!email) email = String(usernameDoc.get('email') || '').trim();
  if (!email) {
    throw new HttpsError('not-found', 'Username not found');
  }

  return { email };
});

const checkEmailAvailable = onCall({ timeoutSeconds: 10 }, async (request) => {
  const email = String((request.data && request.data.email) || '').trim();
  if (!email || email.length > EMAIL_MAX_LENGTH || !email.includes('@')) {
    throw new HttpsError('invalid-argument', 'Invalid email');
  }

  await enforceRateLimit(request, 'checkEmailAvailable');

  try {
    await admin.auth().getUserByEmail(email);
    return { available: false };
  } catch (error) {
    if (error.code === 'auth/user-not-found') return { available: true };
    if (error.code === 'auth/invalid-email') {
      throw new HttpsError('invalid-argument', 'Invalid email');
    }
    throw error;
  }
});

/** Borra, en ambos perfiles, las visitas entre `ownerId` y `otherId`. Idempotente. */
async function deleteVisitsBetween(db, ownerId, otherId) {
  const [inOwner, inOther] = await Promise.all([
    db.collection(`users/${ownerId}/visits`).where('visitorId', '==', otherId).get(),
    db.collection(`users/${otherId}/visits`).where('visitorId', '==', ownerId).get()
  ]);
  const refs = [...inOwner.docs, ...inOther.docs].map(doc => doc.ref);
  for (let i = 0; i < refs.length; i += 400) {
    const batch = db.batch();
    refs.slice(i, i + 400).forEach(ref => batch.delete(ref));
    await batch.commit();
  }
  return refs.length;
}

const purgeVisitsOnBlock = onDocumentWritten('users/{userId}', async (event) => {
  const before = event.data && event.data.before && event.data.before.exists ? event.data.before.data() : null;
  const after = event.data && event.data.after && event.data.after.exists ? event.data.after.data() : null;
  if (!after) return;

  const previous = new Set(Array.isArray(before && before.blockedUsers) ? before.blockedUsers : []);
  const added = (Array.isArray(after.blockedUsers) ? after.blockedUsers : [])
    .filter(id => typeof id === 'string' && id && !previous.has(id));
  if (!added.length) return;

  const db = admin.firestore();
  const ownerId = event.params.userId;
  for (const blockedId of added) {
    await deleteVisitsBetween(db, ownerId, blockedId);
  }
});

module.exports = {
  resolveLoginEmail,
  checkEmailAvailable,
  purgeVisitsOnBlock
};
