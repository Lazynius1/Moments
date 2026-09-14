const admin = require('firebase-admin');

if (!admin.apps.length) admin.initializeApp();

const db = admin.firestore();

async function aggregateCount(query) {
  const snapshot = await query.count().get();
  return snapshot.data().count;
}

async function activeUserIds(ids) {
  const uniqueIds = [...new Set(ids.filter(Boolean))];
  const active = [];
  for (let offset = 0; offset < uniqueIds.length; offset += 100) {
    const refs = uniqueIds.slice(offset, offset + 100).map(id => db.doc(`users/${id}`));
    const docs = refs.length ? await db.getAll(...refs) : [];
    docs.forEach(doc => {
      if (doc.exists && doc.get('isActive') !== false) active.push(doc.id);
    });
  }
  return active;
}

async function activeEdgeCount(userRef, collectionName) {
  const snapshot = await userRef.collection(collectionName).select('userId').get();
  const ids = snapshot.docs.map(doc => String(doc.get('userId') || doc.id));
  return (await activeUserIds(ids)).length;
}

async function backfillUser(userDoc) {
  const userRef = userDoc.ref;
  const [followersCount, followingCount, mutualsCount, allMomentsCount, archivedMomentsCount, visits] = await Promise.all([
    activeEdgeCount(userRef, 'followers'),
    activeEdgeCount(userRef, 'following'),
    activeEdgeCount(userRef, 'mutuals'),
    aggregateCount(userRef.collection('moments')),
    aggregateCount(userRef.collection('moments').where('isArchived', '==', true)),
    userRef.collection('visits').select('visitorId').get(),
  ]);
  const momentsCount = Math.max(0, allMomentsCount - archivedMomentsCount);
  const visitorIds = await activeUserIds(visits.docs.map(doc => doc.get('visitorId')));
  const profileVisitorsCount = visitorIds.length;

  for (let offset = 0; offset < visitorIds.length; offset += 450) {
    const batch = db.batch();
    visitorIds.slice(offset, offset + 450).forEach(visitorId => {
      batch.set(userRef.collection('profileVisitors').doc(visitorId), { visitorId }, { merge: true });
    });
    await batch.commit();
  }

  await userRef.set({ followersCount, followingCount, momentsCount, mutualsCount, profileVisitorsCount }, { merge: true });
  console.log(`${userDoc.id}: ${momentsCount} posts, ${followersCount} followers, ${followingCount} following, ${mutualsCount} mutuals, ${profileVisitorsCount} visitors`);
}

async function main() {
  let cursor = null;
  let processed = 0;

  while (true) {
    let query = db.collection('users').orderBy(admin.firestore.FieldPath.documentId()).limit(100);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;

    for (const userDoc of page.docs) {
      await backfillUser(userDoc);
      processed += 1;
    }
    cursor = page.docs[page.docs.length - 1];
  }

  console.log(`Backfill complete: ${processed} users`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
