const {onRequest, onDocumentDeleted, admin} = require('../bootstrap');
const {setProxyCors, verifyFirebaseAuth, parseJsonBody} = require('../helpers');
const {buildViewerContext, canViewerSeeStory} = require('../helpers/feed');
const {validId, audioId, savingReason, sourceObject} = require('../helpers/story-audio');
const db = () => admin.firestore();
const registry = id => db().doc(`originalStoryAudio/${id}`);
const saved = (uid, id) => db().doc(`users/${uid}/savedStoryAudio/${id}`);
function fail(status, reason) { const error = new Error(reason); error.status = status; throw error; }
function endpoint(handler) {
  return onRequest({timeoutSeconds: 60, memory: '256MiB', maxInstances: 2, concurrency: 20}, async (req, res) => {
    setProxyCors(res); res.set('Cache-Control', 'private, no-store');
    if (req.method === 'OPTIONS') return res.status(204).send('');
    if (req.method !== 'POST') return res.status(405).json({error: 'method_not_allowed'});
    const uid = await verifyFirebaseAuth(req, res); if (!uid) return;
    try { await handler(parseJsonBody(req), res, uid); }
    catch (error) { res.status(error.status || 503).json({error: error.status ? error.message : 'audio_unavailable'}); }
  });
}
async function registered(id, uid, viewerContext) {
  if (typeof id !== 'string' || !/^[a-f0-9]{64}$/.test(id)) fail(400, 'invalid_audio');
  const snap = await registry(id).get(); if (!snap.exists || snap.data().active !== true) fail(404, 'audio_unavailable');
  const data = snap.data();
  const author = await db().doc(`users/${data.ownerId}`).get();
  const ctx = viewerContext || await buildViewerContext(uid);
  if (!author.exists || author.data().isActive === false || author.data().isPrivate === true ||
      !(await canViewerSeeStory({authorId: data.ownerId, audience: 'everyone'}, uid, ctx, author.data()))) fail(403, 'audio_unavailable');
  const source = await db().doc(`users/${data.ownerId}/stories/${data.sourceStoryId}`).get();
  if (source.exists && (source.data().audience !== 'everyone' || source.data().interactionSettings?.allowOriginalAudioReuse !== true)) fail(403, 'creator');
  return data;
}
async function source(body, uid) {
  const {ownerId, storyId, stickerId} = body;
  if (![ownerId, storyId, stickerId].every(validId)) fail(400, 'invalid_audio');
  const [snapshot, author, context] = await Promise.all([
    db().doc(`users/${ownerId}/stories/${storyId}`).get(), db().doc(`users/${ownerId}`).get(), buildViewerContext(uid),
  ]);
  if (!snapshot.exists || !author.exists || author.data().isActive === false) fail(404, 'audio_unavailable');
  const story = {...snapshot.data(), authorId: ownerId};
  if (story.expirationDate?.toMillis && story.expirationDate.toMillis() <= Date.now()) fail(404, 'audio_unavailable');
  if (!(await canViewerSeeStory(story, uid, context, author.data()))) fail(403, 'audio_unavailable');
  const sticker = (story.stickers || []).find(s => s.stickerId === stickerId && s.type === 'audio');
  if (!sticker || !(sticker.audioDuration > 0 && sticker.audioDuration <= 60)) fail(404, 'audio_unavailable');
  const bucket = admin.storage().bucket();
  const object = sourceObject(sticker.audioURL, bucket.name, ownerId, storyId);
  if (!object) fail(404, 'audio_unavailable');
  let metadata = {id: audioId(ownerId, storyId, stickerId), ownerId, sourceStoryId: storyId,
    artist: String(author.data().username || story.username || ''), duration: sticker.audioDuration,
    artworkURL: author.data().profileImagePath || story.profileImagePath || null};
  let reason = savingReason(story, author.data(), sticker);
  if (sticker.originalAudioId) {
    try { metadata = await registered(sticker.originalAudioId, uid); }
    catch { reason ||= 'creator'; }
  }
  return {metadata, object, bucket, reason};
}
async function preview(bucket, object) {
  const [url] = await bucket.file(object).getSignedUrl({action: 'read', expires: Date.now() + 15 * 60 * 1000});
  return url;
}
function publicMetadata(data) {
  return {id: data.id, title: 'Original audio', artist: data.artist, duration: data.duration, artworkURL: data.artworkURL || null};
}
const getStoryOriginalAudio = endpoint(async (body, res, uid) => {
  const item = await source(body, uid);
  const bookmark = await saved(uid, item.metadata.id).get();
  res.json({creatorId: item.metadata.ownerId, track: {...publicMetadata(item.metadata), previewURL: await preview(item.bucket, item.object)},
    canSave: item.reason === null, reason: item.reason, saved: bookmark.exists});
});
const setStoryOriginalAudioSaved = endpoint(async (body, res, uid) => {
  if (typeof body.saved !== 'boolean') fail(400, 'invalid_audio');
  if (!body.saved && typeof body.audioId === 'string' && /^[a-f0-9]{64}$/.test(body.audioId)) {
    await saved(uid, body.audioId).delete(); return res.json({saved: false});
  }
  const item = await source(body, uid);
  if (item.reason) fail(403, item.reason);
  const id = item.metadata.id;
  if (body.saved) {
    const ref = registry(id); const existing = await ref.get();
    if (!existing.exists) {
      const destination = `users/${item.metadata.ownerId}/originalStoryAudio/${id}.m4a`;
      const file = item.bucket.file(item.object); const [metadata] = await file.getMetadata();
      if (!(Number(metadata.size) > 0 && Number(metadata.size) <= 12 * 1024 * 1024)) fail(400, 'invalid_audio');
      await file.copy(item.bucket.file(destination));
      await item.bucket.file(destination).setMetadata({metadata: {firebaseStorageDownloadTokens: null}});
      await db().runTransaction(async transaction => {
        const originRef = db().doc(`users/${item.metadata.ownerId}/stories/${item.metadata.sourceStoryId}`);
        const authorRef = db().doc(`users/${item.metadata.ownerId}`);
        const [current, author, record] = await Promise.all([transaction.get(originRef), transaction.get(authorRef), transaction.get(ref)]);
        if (record.exists) return;
        if (!current.exists || !author.exists || author.data().isActive === false || author.data().isPrivate === true ||
            current.data().audience !== 'everyone' || current.data().interactionSettings?.allowOriginalAudioReuse !== true ||
            current.data().expirationDate?.toMillis() <= Date.now()) fail(403, 'creator');
        transaction.create(ref, {...item.metadata, storagePath: destination, active: true, createdAt: admin.firestore.FieldValue.serverTimestamp()});
      });
    }
    await registered(id, uid);
    await saved(uid, id).set({audioId: id, savedAt: admin.firestore.FieldValue.serverTimestamp()});
  } else { await saved(uid, id).delete(); }
  res.json({saved: body.saved});
});
const getStoryOriginalAudioSaved = endpoint(async (body, res, uid) => {
  const count = 30;
  let query = db().collection(`users/${uid}/savedStoryAudio`).orderBy('savedAt', 'desc').orderBy(admin.firestore.FieldPath.documentId(), 'desc').limit(count + 1);
  if (body.cursor != null) {
    if (typeof body.cursor !== 'string' || !/^[a-f0-9]{64}$/.test(body.cursor)) fail(400, 'invalid_cursor');
    const cursor = await saved(uid, body.cursor).get(); if (!cursor.exists) fail(400, 'invalid_cursor'); query = query.startAfter(cursor);
  }
  const snapshot = await query.get(); const page = snapshot.docs.slice(0, count);
  const context = await buildViewerContext(uid);
  const tracks = (await Promise.all(page.map(async doc => {
    try { return publicMetadata(await registered(doc.id, uid, context)); } catch { return null; }
  }))).filter(Boolean);
  res.json({tracks, nextCursor: snapshot.docs.length > count ? page.at(-1).id : null});
});
const resolveStoryOriginalAudio = endpoint(async (body, res, uid) => {
  if (typeof body.audioId !== 'string' || !/^[a-f0-9]{64}$/.test(body.audioId)) fail(400, 'invalid_audio');
  if (!(await saved(uid, body.audioId).get()).exists) fail(403, 'audio_unavailable');
  const data = await registered(body.audioId, uid);
  res.json({...publicMetadata(data), previewURL: await preview(admin.storage().bucket(), data.storagePath)});
});
// Explicit deletion revokes reuse; normal story expiration keeps an explicitly public audio saved.
const revokeStoryOriginalAudio = onDocumentDeleted('users/{ownerId}/stories/{storyId}', async event => {
  const data = event.data?.data();
  if (!data || !data.expirationDate?.toMillis || data.expirationDate.toMillis() <= Date.now()) return;
  await Promise.all((data.stickers || []).filter(s => s.type === 'audio' && !s.originalAudioId && validId(s.stickerId)).map(async s => {
    const ref = registry(audioId(event.params.ownerId, event.params.storyId, s.stickerId));
    if ((await ref.get()).exists) await ref.update({active: false});
  }));
});
const purgeStoryOriginalAudio = onDocumentDeleted('users/{ownerId}', async event => {
  while (true) {
    const page = await db().collection('originalStoryAudio').where('ownerId', '==', event.params.ownerId).limit(100).get();
    if (page.empty) break;
    await Promise.all(page.docs.map(async doc => {
      const data = doc.data();
      if (data.storagePath?.startsWith(`users/${event.params.ownerId}/originalStoryAudio/`)) {
        await admin.storage().bucket().file(data.storagePath).delete({ignoreNotFound: true});
      }
      await doc.ref.delete();
    }));
  }
});
module.exports = {purgeStoryOriginalAudio, getStoryOriginalAudio, setStoryOriginalAudioSaved, getStoryOriginalAudioSaved, resolveStoryOriginalAudio, revokeStoryOriginalAudio};
