// Copia los datos privados de cada ficha `users/{uid}` a `users/{uid}/private/account` y
// reconstruye el índice inverso `users/{uid}/private/relations` (quién le ha bloqueado y de
// quién es mejor amigo). No toca la ficha pública. Se puede repetir sin problema.
// Uso: node scripts/backfill-private-account.js [--dry-run]   (credenciales: gcloud ADC)
const admin = require('firebase-admin');
const { changedPrivateFields, RELATION_FIELDS } = require('../src/helpers/private-account');

admin.initializeApp({ projectId: 'glowsy-6a40e' });
const db = admin.firestore();
const dryRun = process.argv.includes('--dry-run');

(async () => {
  let scanned = 0;
  let copied = 0;
  let last = null;
  // inverso[targetId] = { blockedBy: Set, bestFriendOf: Set }
  const inverse = new Map();
  const userIds = new Set();

  for (;;) {
    let q = db.collection('users').orderBy(admin.firestore.FieldPath.documentId()).limit(200);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    if (page.empty) break;
    const privateRefs = page.docs.map(d => d.ref.collection('private').doc('account'));
    const privateDocs = await db.getAll(...privateRefs);
    const batch = db.batch();
    let pending = 0;
    page.docs.forEach((d, i) => {
      scanned++;
      userIds.add(d.id);
      const data = d.data();
      for (const [field, inverseField] of Object.entries(RELATION_FIELDS)) {
        for (const targetId of Array.isArray(data[field]) ? data[field] : []) {
          if (typeof targetId !== 'string' || !targetId || targetId === d.id) continue;
          if (!inverse.has(targetId)) inverse.set(targetId, { blockedBy: new Set(), bestFriendOf: new Set() });
          inverse.get(targetId)[inverseField].add(d.id);
        }
      }
      const current = privateDocs[i].exists ? privateDocs[i].data() : {};
      const changes = changedPrivateFields(current, data);
      if (!Object.keys(changes).length) return;
      copied++;
      pending++;
      if (!dryRun) {
        batch.set(
          privateRefs[i],
          { ...changes, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
          { merge: true }
        );
      }
    });
    if (pending && !dryRun) await batch.commit();
    last = page.docs[page.docs.length - 1];
  }

  let relations = 0;
  const targets = [...inverse.keys()].filter(id => userIds.has(id));
  for (let i = 0; i < targets.length; i += 400) {
    const batch = db.batch();
    for (const targetId of targets.slice(i, i + 400)) {
      const { blockedBy, bestFriendOf } = inverse.get(targetId);
      relations++;
      if (!dryRun) {
        batch.set(db.doc(`users/${targetId}/private/relations`), {
          blockedBy: [...blockedBy],
          bestFriendOf: [...bestFriendOf]
        });
      }
    }
    if (!dryRun) await batch.commit();
  }

  console.log(`${dryRun ? '[prueba] ' : ''}revisados ${scanned}, copiados ${copied}, índices ${relations}`);
})().catch(err => { console.error(err.message); process.exit(1); });
