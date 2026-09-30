const crypto = require('node:crypto');
const { defineSecret } = require('firebase-functions/params');
const MAP_CURSOR_KEY = defineSecret('MAP_CURSOR_KEY');

function mapQueryKey(uid, mode, filters, scope, kind) {
  return crypto.createHash('sha256').update(JSON.stringify([uid, mode, filters, scope, kind])).digest('hex');
}

function decodeMapCursor(token, key) {
  if (token == null) return null;
  if (typeof token !== 'string' || token.length > 2048) throw new Error('Invalid map cursor');
  let cursor;
  try {
    const bytes = Buffer.from(token, 'base64url');
    const decipher = crypto.createDecipheriv('aes-256-gcm', cursorEncryptionKey(), bytes.subarray(0, 12));
    decipher.setAAD(Buffer.from(key));
    decipher.setAuthTag(bytes.subarray(12, 28));
    cursor = JSON.parse(Buffer.concat([decipher.update(bytes.subarray(28)), decipher.final()]).toString());
  } catch { throw new Error('Invalid map cursor'); }
  if (cursor.v !== 1 || !Number.isFinite(cursor.value)
      || typeof cursor.path !== 'string' || !/^users\/[^/]+\/(moments|stories)\/[^/]+$/.test(cursor.path)) {
    throw new Error('Invalid map cursor');
  }
  return cursor;
}

function cursorEncryptionKey() {
  const secret = MAP_CURSOR_KEY.value();
  if (!/^[a-f0-9]{64}$/.test(secret || '')) throw new Error('Missing map cursor key');
  return Buffer.from(secret, 'hex');
}

function encodeMapCursor(key, value, path) {
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', cursorEncryptionKey(), nonce);
  cipher.setAAD(Buffer.from(key));
  const bytes = Buffer.concat([cipher.update(JSON.stringify({ v: 1, value, path })), cipher.final()]);
  return Buffer.concat([nonce, cipher.getAuthTag(), bytes]).toString('base64url');
}

// Page the raw candidates, not only authorized items: a page containing hidden
// items must still advance. Authorization stays in the endpoints before output.
async function fetchMapMomentCandidatePage(db, admin, authorIds, mode, filters, limit, cursor, key) {
  const batches = authorIds == null ? [null] : [];
  if (authorIds) for (let i = 0; i < authorIds.length; i += 10) batches.push(authorIds.slice(i, i + 10));
  const descending = mode === 'location';
  const field = descending ? 'timestamp' : 'locationCoordinate.latitude';
  const order = descending ? 'desc' : 'asc';
  const snapshots = await Promise.all(batches.map(async batch => {
    let query = db.collectionGroup('moments');
    if (batch) query = query.where('authorId', 'in', batch);
    query = descending ? query.where('location', '==', filters.locationName)
      : query.where(field, '>=', filters.latitudeMin).where(field, '<=', filters.latitudeMax);
    query = query.orderBy(field, order).orderBy(admin.firestore.FieldPath.documentId(), order);
    if (cursor) query = query.startAfter(
      descending ? admin.firestore.Timestamp.fromMillis(cursor.value) : cursor.value,
      db.doc(cursor.path)
    );
    return query.limit(limit + 1).get();
  }));
  const valueOf = doc => {
    const value = descending ? doc.data().timestamp : doc.data().locationCoordinate?.latitude;
    return descending ? (value?.toMillis?.() ?? Number(value)) : Number(value);
  };
  const unique = new Map();
  snapshots.forEach(snapshot => snapshot.docs.forEach(doc => unique.set(doc.ref.path, doc)));
  const ordered = [...unique.values()].sort((a, b) => {
    const difference = valueOf(a) - valueOf(b);
    const pathOrder = a.ref.path < b.ref.path ? -1 : a.ref.path > b.ref.path ? 1 : 0;
    return (descending ? -1 : 1) * (difference || pathOrder);
  });
  const docs = ordered.slice(0, limit);
  const last = docs.at(-1);
  return { docs, nextCursor: ordered.length > limit && last
    ? encodeMapCursor(key, valueOf(last), last.ref.path) : null };
}

async function fetchMapStoryCandidatePage(db, admin, authorIds, limit, cursor, key) {
  const batches = authorIds == null ? [null] : [];
  if (authorIds) for (let i = 0; i < authorIds.length; i += 10) batches.push(authorIds.slice(i, i + 10));
  const now = admin.firestore.Timestamp.now();
  const snapshots = await Promise.all(batches.map(async batch => {
    let query = db.collectionGroup('stories');
    if (batch) query = query.where('authorId', 'in', batch);
    query = query.where('expirationDate', '>', now).orderBy('expirationDate', 'asc')
      .orderBy(admin.firestore.FieldPath.documentId(), 'asc');
    if (cursor) query = query.startAfter(admin.firestore.Timestamp.fromMillis(cursor.value), db.doc(cursor.path));
    return query.limit(limit + 1).get();
  }));
  const unique = new Map();
  snapshots.forEach(snapshot => snapshot.docs.forEach(doc => unique.set(doc.ref.path, doc)));
  const ordered = [...unique.values()].sort((a, b) => a.data().expirationDate.toMillis() - b.data().expirationDate.toMillis()
    || (a.ref.path < b.ref.path ? -1 : a.ref.path > b.ref.path ? 1 : 0));
  const docs = ordered.slice(0, limit);
  const last = docs.at(-1);
  return { docs, nextCursor: ordered.length > limit && last
    ? encodeMapCursor(key, last.data().expirationDate.toMillis(), last.ref.path) : null };
}

module.exports = { mapQueryKey, decodeMapCursor, encodeMapCursor, fetchMapMomentCandidatePage, fetchMapStoryCandidatePage, MAP_CURSOR_KEY };
