/**
 * One-off migration: dedupe follow-related notifications per (type, senderId).
 *
 * Usage (from Moments/functions):
 *   node scripts/migrate-follow-notifications.js [userId]
 *
 * Without userId, scans all users (slow; use only in dev/staging).
 * Requires GOOGLE_APPLICATION_CREDENTIALS or Firebase emulator.
 */

const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const SOCIAL_TYPES = ['newFollower', 'mutualConnection', 'followRequest'];

function stableDocId(type, senderId) {
  switch (type) {
    case 'newFollower':
      return `newFollower_${senderId}`;
    case 'mutualConnection':
      return `mutualConnection_${senderId}`;
    case 'followRequest':
      return `followRequest_${senderId}`;
    default:
      return null;
  }
}

async function migrateUserNotifications(userId) {
  const col = db.collection(`users/${userId}/notifications`);
  const snap = await col.get();
  const byKey = new Map();

  for (const doc of snap.docs) {
    const data = doc.data();
    if (!SOCIAL_TYPES.includes(data.type)) continue;
    const senderId = data.senderId;
    if (!senderId) continue;

    const key = `${data.type}_${senderId}`;
    if (!byKey.has(key)) {
      byKey.set(key, []);
    }
    byKey.get(key).push({ id: doc.id, ref: doc.ref, data });
  }

  let deleted = 0;
  let merged = 0;

  for (const [, docs] of byKey) {
    if (docs.length <= 1) {
      const only = docs[0];
      const canonicalId = stableDocId(only.data.type, only.data.senderId);
      if (canonicalId && only.id !== canonicalId) {
        await col.doc(canonicalId).set(only.data, { merge: true });
        await only.ref.delete();
        merged += 1;
      }
      continue;
    }

    docs.sort((a, b) => {
      const ta = a.data.timestamp?.toMillis?.() ?? 0;
      const tb = b.data.timestamp?.toMillis?.() ?? 0;
      return tb - ta;
    });

    const winner = docs[0];
    const canonicalId = stableDocId(winner.data.type, winner.data.senderId);
    if (canonicalId) {
      await col.doc(canonicalId).set(winner.data, { merge: true });
    }

    for (let i = canonicalId && winner.id === canonicalId ? 1 : 0; i < docs.length; i++) {
      const doc = docs[i];
      if (canonicalId && doc.id === canonicalId) continue;
      await doc.ref.delete();
      deleted += 1;
    }
    if (canonicalId && winner.id !== canonicalId) {
      await winner.ref.delete();
      deleted += 1;
    }
    merged += 1;
  }

  return { deleted, merged };
}

async function main() {
  const targetUserId = process.argv[2];

  if (targetUserId) {
    const stats = await migrateUserNotifications(targetUserId);
    console.log(`User ${targetUserId}:`, stats);
    return;
  }

  console.warn('Scanning all users — prefer passing a single userId in production.');
  const usersSnap = await db.collection('users').select().get();
  let totalDeleted = 0;
  let totalMerged = 0;

  for (const userDoc of usersSnap.docs) {
    const stats = await migrateUserNotifications(userDoc.id);
    totalDeleted += stats.deleted;
    totalMerged += stats.merged;
  }

  console.log('Done.', { totalDeleted, totalMerged });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
