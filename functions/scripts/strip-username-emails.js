// Borra el campo `email` de todos los documentos de `usernames` (índice público).
// Uso: node scripts/strip-username-emails.js [--dry-run]   (credenciales: gcloud ADC)
const admin = require('firebase-admin');

admin.initializeApp({ projectId: 'glowsy-6a40e' });
const db = admin.firestore();
const dryRun = process.argv.includes('--dry-run');

(async () => {
  let scanned = 0;
  let cleaned = 0;
  let last = null;
  for (;;) {
    let q = db.collection('usernames').orderBy(admin.firestore.FieldPath.documentId()).limit(400);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    if (page.empty) break;
    const batch = db.batch();
    let pending = 0;
    for (const d of page.docs) {
      scanned++;
      if (d.get('email') !== undefined) {
        cleaned++;
        pending++;
        if (!dryRun) batch.update(d.ref, { email: admin.firestore.FieldValue.delete() });
      }
    }
    if (pending && !dryRun) await batch.commit();
    last = page.docs[page.docs.length - 1];
  }
  console.log(`${dryRun ? '[prueba] ' : ''}revisados ${scanned}, con email ${cleaned}`);
})().catch(err => { console.error(err.message); process.exit(1); });
