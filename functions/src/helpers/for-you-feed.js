'use strict';

const crypto = require('crypto');
const { orderPool, sanitizeSignals } = require('./for-you-ranking');
const keyFor = (authorId, momentId) => `${authorId}/${momentId}`;
const hiddenId = key => crypto.createHash('sha256').update(key).digest('hex');
const validId = value => typeof value === 'string' && /^[^/]{1,128}$/.test(value);
const error = (message, status) => Object.assign(new Error(message), { status });

async function getDocuments(db, refs) {
  const docs = [];
  for (let i = 0; i < refs.length; i += 100) docs.push(...await db.getAll(...refs.slice(i, i + 100)));
  return docs;
}

async function visibleEntries(db, uid, viewerCtx, docs, surface = 'feed') {
  const h = require('./feed');
  const candidates = docs.filter(doc => {
    if (!doc.exists) return false;
    const data = doc.data();
    return (surface !== 'explore' || (data.isModerationHidden !== true && (Array.isArray(data.mediaItems) && data.mediaItems.length
      ? data.mediaItems.some(item => item.url && !item.isHiddenByModeration) : data.imagePath || data.videoUrl)))
      && h.isMomentPathAuthorConsistent(doc, data) && !data.isArchived
      && !h.isExcludedForYouAuthor(data.authorId, uid, viewerCtx)
      && !viewerCtx.mutedUsers.has(data.authorId)
      && !(h.tsToMillis(data.scheduledDate) > Date.now());
  });
  if (!candidates.length) return [];
  const [authors, hidden] = await Promise.all([
    h.batchLoadAuthorDocs([...new Set(candidates.map(doc => doc.data().authorId))]),
    getDocuments(db, candidates.map(doc => db.doc(`users/${uid}/recommendationHidden/${hiddenId(keyFor(doc.data().authorId, doc.id))}`)))
  ]);
  const checks = await Promise.all(candidates.map(async (doc, index) => {
    const data = doc.data();
    const authorData = authors.get(data.authorId);
    // Firestore's collection-group rules require access to the profile before
    // checking its audience. Following authors are excluded from discovery,
    // so a private profile must never enter this surface, even via a custom list.
    if (!authorData || authorData.isPrivate === true || hidden[index].exists
        || (Array.isArray(authorData.blockedUsers) && authorData.blockedUsers.includes(uid))) return null;
    if (!await h.canViewerSeeMoment({ ...data, id: doc.id }, uid, viewerCtx, authorData)) return null;
    return { doc, data, authorData, key: keyFor(data.authorId, doc.id), timestamp: h.tsToMillis(data.timestamp) || 0 };
  }));
  return checks.filter(Boolean);
}

async function recordFeedback(db, uid, body, viewerCtx) {
  const { authorId, momentId, intent } = body;
  if (!validId(authorId) || !validId(momentId) || !['hide', 'undo'].includes(intent) || authorId === uid) {
    throw error('Invalid feedback', 400);
  }
  const ref = db.doc(`users/${uid}/recommendationHidden/${hiddenId(keyFor(authorId, momentId))}`);
  if (intent === 'undo') {
    // Undo remains available after deletion or an audience change; it grants no access.
    await ref.delete();
    return;
  }
  const h = require('./feed');
  const [moment, author] = await Promise.all([
    db.doc(`users/${authorId}/moments/${momentId}`).get(), db.doc(`users/${authorId}`).get()
  ]);
  if (!moment.exists || !author.exists || viewerCtx.following.has(authorId)
      || viewerCtx.mutedUsers.has(authorId) || viewerCtx.blockedUsers.has(authorId)
      || author.data().isPrivate === true
      || (Array.isArray(author.data().blockedUsers) && author.data().blockedUsers.includes(uid))
      || !h.isMomentPathAuthorConsistent(moment, moment.data())
      || moment.data().isArchived || h.tsToMillis(moment.data().scheduledDate) > Date.now()
      || !await h.canViewerSeeMoment({ ...moment.data(), id: momentId }, uid, viewerCtx, author.data())) {
    throw error('Content unavailable', 404);
  }
  // Idempotent: repeated requests cannot repeatedly strengthen the topic penalty.
  await db.runTransaction(async transaction => {
    const existing = await transaction.get(ref);
    if (!existing.exists) transaction.set(ref, { authorId, momentId,
      interests: Array.isArray(author.data().interests) ? author.data().interests.slice(0, 30) : [], timestamp: Date.now() });
  });
}

async function rankedPage({ db, uid, viewerCtx, body, limit, surface = 'feed', attempt = 0 }) {
  const h = require('./feed');
  const admin = require('../bootstrap').admin;
  const sessions = db.collection(`users/${uid}/${surface === 'explore' ? 'exploreRecommendationSessions' : 'recommendationSessions'}`);
  const match = /^fy2_([a-f0-9]{32})_(\d{1,5})(?:_\d+)?$/.exec(body.cursor?.momentId || '');
  let session, ref, offset = 0;
  if (match) {
    ref = sessions.doc(match[1]);
    const doc = await ref.get();
    if (!doc.exists) return { moments: [], nextCursor: null, totalCandidates: 0 };
    session = doc.data();
    offset = Number(match[2]);
    if (offset > session.keys.length) throw error('Invalid cursor', 400);
  } else {
    const now = Date.now();
    const [interestIds, secondDegreeIds, followerIds, negatives, oldSessions] = await Promise.all([
      h.fetchForYouInterestUserIds(db, uid, viewerCtx, 40),
      h.fetchForYouSecondDegreeUserIds(db, uid, viewerCtx, 30),
      h.fetchForYouFollowerPublicUserIds(db, uid, viewerCtx, 20),
      db.collection(`users/${uid}/recommendationHidden`).orderBy('timestamp', 'desc').limit(100).get(),
      sessions.orderBy('createdAt', 'desc').get()
    ]);
    const signals = sanitizeSignals(body, now);
    const authors = [...new Set([...interestIds, ...secondDegreeIds, ...followerIds,
      ...Object.keys(signals.affinity)])].filter(id => !h.isExcludedForYouAuthor(id, uid, viewerCtx)).slice(0, 120);
    const streams = [{ authors: [], cursor: null, done: false }];
    for (let i = 0; i < authors.length; i += 10) streams.push({ authors: authors.slice(i, i + 10), cursor: null, done: false });
    session = { createdAt: now, revision: 0, keys: [], streams, ...signals,
      interests: viewerCtx.viewerInterests, secondDegree: [...secondDegreeIds], followers: [...viewerCtx.followers],
      negatives: negatives.docs.map(doc => doc.data()) };
    ref = sessions.doc(crypto.randomBytes(16).toString('hex'));
    // Keep at most three recent browsing sessions per account; no unbounded session history.
    await Promise.all(oldSessions.docs.slice(2).map(doc => doc.ref.delete()));
  }
  const expectedRevision = session.revision || 0;

  async function extendPool() {
    const candidateDocs = [];
    await Promise.all(session.streams.filter(stream => !stream.done).map(async stream => {
      let query = db.collectionGroup('moments');
      query = stream.authors.length ? query.where('authorId', 'in', stream.authors) : query.where('audience', '==', 'everyone');
      query = query.orderBy('timestamp', 'desc').orderBy(admin.firestore.FieldPath.documentId(), 'desc');
      if (stream.cursor) query = query.startAfter(admin.firestore.Timestamp.fromMillis(stream.cursor.timestamp), db.doc(stream.cursor.path));
      else query = query.where('timestamp', '<=', admin.firestore.Timestamp.fromMillis(session.createdAt));
      const snap = await query.limit(60).get();
      candidateDocs.push(...snap.docs);
      stream.done = snap.size < 60;
      const last = snap.docs[snap.docs.length - 1];
      if (last) stream.cursor = { timestamp: h.tsToMillis(last.data().timestamp), path: last.ref.path };
    }));
    const previous = new Set(session.keys);
    const unique = [...new Map(candidateDocs.map(doc => [doc.ref.path, doc])).values()]
      .filter(doc => !previous.has(keyFor(doc.data().authorId, doc.id)));
    const entries = await visibleEntries(db, uid, viewerCtx, unique, surface);
    const ordered = orderPool(entries, { ...session, now: session.createdAt,
      followers: new Set(session.followers), secondDegree: new Set(session.secondDegree) },
    session.keys.at(-1)?.split('/')[0], session.keys.length);
    session.keys.push(...ordered.map(entry => entry.key).slice(0, 4000 - session.keys.length));
  }

  // Only the order is cached. Re-read content and permissions on every page.
  const result = [];
  let scans = 0;
  while (result.length < limit && scans++ < 8) {
    if (offset >= session.keys.length) {
      if (session.keys.length >= 4000 || session.streams.every(stream => stream.done)) break;
      await extendPool();
      if (offset >= session.keys.length) continue;
    }
    const keys = session.keys.slice(offset, offset + limit - result.length);
    const docs = await db.getAll(...keys.map(key => {
      const [authorId, momentId] = key.split('/');
      return db.doc(`users/${authorId}/moments/${momentId}`);
    }));
    const entries = await visibleEntries(db, uid, viewerCtx, docs, surface);
    const visible = new Map(entries.map(entry => [entry.key, entry]));
    for (const key of keys) {
      const entry = visible.get(key);
      if (entry) result.push(h.serializeMoment(entry.doc.id, entry.data));
    }
    offset += keys.length;
  }
  // A late retry must never overwrite a newer pool or change another page's order.
  const saved = await db.runTransaction(async transaction => {
    const latest = await transaction.get(ref);
    if ((latest.exists ? latest.data().revision || 0 : 0) !== expectedRevision) return false;
    transaction.set(ref, { ...session, revision: expectedRevision + 1 });
    return true;
  });
  if (!saved) {
    if (attempt >= 2) throw error('Please retry the page', 409);
    return rankedPage({ db, uid, viewerCtx, body, limit, surface, attempt: attempt + 1 });
  }
  const hasMore = offset < session.keys.length || (session.keys.length < 4000 && session.streams.some(stream => !stream.done));
  return { moments: result, nextCursor: hasMore ? { timestamp: session.createdAt,
    momentId: `fy2_${ref.id}_${offset}_${expectedRevision + 1}` } : null, totalCandidates: session.keys.length };
}

module.exports = { rankedPage, recordFeedback, visibleEntries };
