const { onDocumentCreated, onDocumentWritten, onSchedule, admin } = require('../bootstrap');
const crypto = require('crypto');

const COUNTER_EVENT_TTL_MS = 7 * 24 * 60 * 60 * 1000;

function counterDelta(event, isCounted) {
  const before = event.data?.before;
  const after = event.data?.after;
  const wasCounted = Boolean(before?.exists && isCounted(before.data() || {}));
  const isNowCounted = Boolean(after?.exists && isCounted(after.data() || {}));
  return Number(isNowCounted) - Number(wasCounted);
}

async function applyCounterDeltaOnce({ eventId, userId, field, delta }) {
  if (!delta || !userId) return;

  const db = admin.firestore();
  const markerId = crypto.createHash('sha256').update(`${eventId}:${field}`).digest('hex');
  const markerRef = db.doc(`profileCounterEvents/${markerId}`);
  const userRef = db.doc(`users/${userId}`);

  await db.runTransaction(async (tx) => {
    const [marker, user] = await Promise.all([tx.get(markerRef), tx.get(userRef)]);
    if (marker.exists) return;

    if (user.exists) {
      const current = Number(user.get(field));
      const safeCurrent = Number.isFinite(current) ? current : 0;
      tx.update(userRef, { [field]: Math.max(0, safeCurrent + delta) });
    }
    tx.set(markerRef, {
      eventId,
      field,
      userId,
      appliedAt: admin.firestore.FieldValue.serverTimestamp(),
      expireAt: admin.firestore.Timestamp.fromMillis(Date.now() + COUNTER_EVENT_TTL_MS)
    });
  });
}

async function activeRelatedDelta(event, relatedUserId, isCounted = () => true) {
  const delta = counterDelta(event, isCounted);
  if (!delta || !relatedUserId) return 0;
  const related = await admin.firestore().doc(`users/${relatedUserId}`).get();
  return related.exists && related.get('isActive') !== false ? delta : 0;
}

const syncFollowerCount = onDocumentWritten(
  'users/{userId}/followers/{followerId}',
  async (event) => applyCounterDeltaOnce({
    eventId: event.id,
    userId: event.params.userId,
    field: 'followersCount',
    delta: await activeRelatedDelta(event, event.params.followerId)
  })
);

const syncFollowingCount = onDocumentWritten(
  'users/{userId}/following/{followingId}',
  async (event) => applyCounterDeltaOnce({
    eventId: event.id,
    userId: event.params.userId,
    field: 'followingCount',
    delta: await activeRelatedDelta(event, event.params.followingId)
  })
);

const syncMomentCount = onDocumentWritten(
  'users/{userId}/moments/{momentId}',
  async (event) => applyCounterDeltaOnce({
    eventId: event.id,
    userId: event.params.userId,
    field: 'momentsCount',
    delta: counterDelta(event, data => data.isArchived !== true)
  })
);

const syncMutualCount = onDocumentWritten(
  'users/{userId}/mutuals/{mutualId}',
  async (event) => applyCounterDeltaOnce({
    eventId: event.id,
    userId: event.params.userId,
    field: 'mutualsCount',
    delta: await activeRelatedDelta(event, event.params.mutualId)
  })
);

const syncProfileVisitorCount = onDocumentCreated(
  'users/{userId}/visits/{visitId}',
  async (event) => {
    const userId = event.params.userId;
    const visitorId = String(event.data?.data()?.visitorId || '').trim();
    if (!userId || !visitorId) return;

    const db = admin.firestore();
    const visitorUser = await db.doc(`users/${visitorId}`).get();
    if (!visitorUser.exists || visitorUser.get('isActive') === false) return;
    const markerId = crypto.createHash('sha256').update(`${event.id}:profileVisitorsCount`).digest('hex');
    const markerRef = db.doc(`profileCounterEvents/${markerId}`);
    const visitorRef = db.doc(`users/${userId}/profileVisitors/${visitorId}`);
    const userRef = db.doc(`users/${userId}`);

    await db.runTransaction(async (tx) => {
      const [marker, visitor, user] = await Promise.all([
        tx.get(markerRef),
        tx.get(visitorRef),
        tx.get(userRef)
      ]);
      if (marker.exists) return;

      if (!visitor.exists) {
        tx.set(visitorRef, {
          visitorId,
          firstVisitedAt: event.data.data().timestamp || admin.firestore.FieldValue.serverTimestamp()
        });
        if (user.exists) {
          const current = Number(user.get('profileVisitorsCount'));
          tx.update(userRef, { profileVisitorsCount: (Number.isFinite(current) ? current : 0) + 1 });
        }
      }
      tx.set(markerRef, {
        eventId: event.id,
        field: 'profileVisitorsCount',
        userId,
        appliedAt: admin.firestore.FieldValue.serverTimestamp(),
        expireAt: admin.firestore.Timestamp.fromMillis(Date.now() + COUNTER_EVENT_TTL_MS)
      });
    });
  }
);

const cleanupProfileCounterEvents = onSchedule({
  schedule: 'every 24 hours',
  region: 'europe-west1'
}, async () => {
  const db = admin.firestore();
  const expired = await db.collection('profileCounterEvents')
    .where('expireAt', '<=', admin.firestore.Timestamp.now())
    .limit(500)
    .get();
  if (expired.empty) return;
  const batch = db.batch();
  expired.docs.forEach(doc => batch.delete(doc.ref));
  await batch.commit();
});

module.exports = {
  syncFollowerCount,
  syncFollowingCount,
  syncMomentCount,
  syncMutualCount,
  syncProfileVisitorCount,
  cleanupProfileCounterEvents,
};
