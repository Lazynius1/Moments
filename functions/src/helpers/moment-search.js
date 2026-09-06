const crypto = require('crypto');
const { admin } = require('../bootstrap');
const { buildViewerContext, canViewerSeeMoment, serializeMoment, tsToMillis } = require('./feed');

const COLLECTION = 'momentSearch';
const VERSION = 1;
const normalize = value => String(value || '').normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase().trim();
const words = value => [...new Set(normalize(value).match(/[\p{L}\p{N}_]+/gu) || [])];
const indexId = path => crypto.createHash('sha256').update(path).digest('hex');

function searchTerms(data) {
  const terms = new Set();
  const tags = normalize(data.content).match(/#[\p{L}\p{N}_]+/gu) || [];
  for (const tag of tags.slice(0, 200)) { if (Array.from(tag).length <= 121) terms.add(`h:${tag.slice(1)}`); }
  // Prefixes keep typing responsive without scanning the moments collection.
  for (const [kind, text] of [['l', data.location], ['t', `${data.content || ''} ${data.location || ''} ${data.username || ''}`]]) {
    for (const word of words(String(text || '').slice(0, 20000))) {
      const characters = Array.from(word);
      for (let length = 1; length <= Math.min(characters.length, 40); length++) {
        if (terms.size >= 6000) return [...terms];
        terms.add(`${kind}:${characters.slice(0, length).join('')}`);
      }
    }
  }
  return [...terms];
}

// Read the current source inside the transaction: retries and out-of-order
// trigger delivery must never restore a deleted post or an old index entry.
async function syncMomentSearch(db, path) {
  if (!/^users\/[^/]+\/moments\/[^/]+$/.test(path)) return;
  const sourceRef = db.doc(path);
  const targetRef = db.collection(COLLECTION).doc(indexId(path));
  await db.runTransaction(async transaction => {
    const [source, existing] = await Promise.all([transaction.get(sourceRef), transaction.get(targetRef)]);
    const data = source.exists ? source.data() : null;
    if (!data || data.authorId !== path.split('/')[1] || data.isArchived === true) {
      transaction.delete(targetRef);
      return;
    }
    const timestamp = tsToMillis(data.timestamp);
    const fingerprint = indexId(JSON.stringify([VERSION, data.content || '', data.location || '', data.username || '', timestamp]));
    if (existing.exists && existing.data().fingerprint === fingerprint) return;
    const terms = searchTerms(data);
    if (!timestamp || !terms.length) {
      transaction.delete(targetRef);
      return;
    }
    transaction.set(targetRef, { path, timestamp, terms, fingerprint, version: VERSION });
  });
}

function parseSearch(body, uid) {
  const mode = ['hashtag', 'location', 'mixed'].includes(body.mode) ? body.mode : 'mixed';
  const raw = typeof body.query === 'string' ? body.query.trim() : '';
  if (!raw || Array.from(raw).length > 120) throw Object.assign(new Error('Invalid query'), { status: 400 });
  const query = normalize(raw.replace(/^#/, ''));
  const queryWords = words(query);
  const keys = mode === 'hashtag'
    ? (/^[\p{L}\p{N}_]+$/u.test(query) ? [`h:${query}`] : [])
    : queryWords.map(word => `${mode === 'location' ? 'l' : 't'}:${Array.from(word).slice(0, 40).join('')}`);
  const scope = indexId(`${uid}\n${mode}\n${query}`);
  return { mode, query, queryWords, keys, scope };
}

function matches(data, search) {
  if (search.mode === 'hashtag') return (normalize(data.content).match(/#[\p{L}\p{N}_]+/gu) || []).includes(`#${search.query}`);
  const text = search.mode === 'location' ? data.location : `${data.content || ''} ${data.location || ''} ${data.username || ''}`;
  const candidates = words(text);
  return search.queryWords.every(word => candidates.some(candidate => candidate.startsWith(word)));
}

async function searchMomentsPage(db, uid, body) {
  const search = parseSearch(body, uid);
  if (!search.keys.length) return { moments: [], nextCursor: null };
  const limit = Math.max(1, Math.min(30, Math.floor(Number(body.limit) || 24)));
  const viewer = await buildViewerContext(uid);
  const authorCache = new Map();
  let cursor = null;
  if (body.cursor) {
    try {
      if (typeof body.cursor !== 'string' || body.cursor.length > 1024) throw new Error();
      cursor = JSON.parse(Buffer.from(body.cursor, 'base64url').toString());
      if (cursor.scope !== search.scope || !Number.isFinite(cursor.timestamp) || !/^[a-f0-9]{64}$/.test(cursor.id)) throw new Error();
    } catch { throw Object.assign(new Error('Invalid cursor'), { status: 400 }); }
  }
  const term = [...search.keys].sort((a, b) => b.length - a.length)[0];
  const moments = [];
  let exhausted = false;
  for (let round = 0; round < 5 && moments.length < limit && !exhausted; round++) {
    let query = db.collection(COLLECTION).where('terms', 'array-contains', term)
      .orderBy('timestamp', 'desc').orderBy(admin.firestore.FieldPath.documentId(), 'desc').limit(60);
    if (cursor) query = query.startAfter(cursor.timestamp, cursor.id);
    const snapshot = await query.get();
    if (snapshot.empty) { exhausted = true; break; }
    const sources = await db.getAll(...snapshot.docs.map(doc => db.doc(doc.data().path)));
    const authorIds = [...new Set(sources.filter(doc => doc.exists).map(doc => doc.data().authorId))]
      .filter(id => typeof id === 'string' && id.length > 0 && !id.includes('/') && !authorCache.has(id));
    if (authorIds.length) {
      const authors = await db.getAll(...authorIds.map(id => db.doc(`users/${id}`)));
      authors.forEach(doc => authorCache.set(doc.id, doc));
    }
    for (let i = 0; i < snapshot.docs.length; i++) {
      const entry = snapshot.docs[i];
      cursor = { scope: search.scope, timestamp: entry.data().timestamp, id: entry.id };
      const source = sources[i];
      const data = source.exists ? source.data() : null;
      if (data && source.ref.path === `users/${data.authorId}/moments/${source.id}` &&
          data.authorId !== uid && data.isArchived !== true && data.isModerationHidden !== true && !viewer.mutedUsers.has(data.authorId) &&
          tsToMillis(data.timestamp) <= Date.now() && !(tsToMillis(data.scheduledDate) > Date.now()) && matches(data, search)) {
        if (!authorCache.has(data.authorId)) authorCache.set(data.authorId, await db.doc(`users/${data.authorId}`).get());
        const author = authorCache.get(data.authorId);
        // Profile privacy and post audience are both required, including lists.
        if (author.exists && (author.data().isPrivate !== true || viewer.following.has(data.authorId)) &&
            await canViewerSeeMoment({ ...data, id: source.id }, uid, viewer, author.data())) {
          moments.push(serializeMoment(source.id, data));
        }
      }
      if (moments.length === limit) {
        exhausted = i === snapshot.docs.length - 1 && snapshot.size < 60;
        break;
      }
    }
    if (moments.length < limit && snapshot.size < 60) exhausted = true;
  }
  return { moments, nextCursor: exhausted || !cursor ? null : Buffer.from(JSON.stringify(cursor)).toString('base64url') };
}

module.exports = { syncMomentSearch, searchMomentsPage, searchTerms, COLLECTION, VERSION };
