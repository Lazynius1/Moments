/* Operational migration. Only writes the server-owned momentSearch index.
 * Usage: node scripts/backfill-moment-search.js PROJECT [--firebase-cli /absolute/path/to/firebase-tools/lib] [--index-only]
 * ADC is the default; the CLI option reuses the signed-in deployer's credential
 * in memory and never logs or writes tokens.
 */
const admin = require('firebase-admin');
const path = require('path');
const projectId = process.argv[2];
if (!projectId || !/^[a-z][a-z0-9-]+$/.test(projectId)) throw new Error('Provide a project ID');
const cliOption = process.argv.indexOf('--firebase-cli');
let credential = admin.credential.applicationDefault();
let migrationDb;
if (cliOption >= 0) {
  const auth = require(path.join(process.argv[cliOption + 1], 'auth'));
  const account = auth.getProjectDefaultAccount(path.resolve(__dirname, '../..'));
  if (!account) throw new Error('Sign in to Firebase CLI first');
  const api = require(path.join(process.argv[cliOption + 1], 'api'));
  const { Firestore } = require('@google-cloud/firestore');
  migrationDb = new Firestore({ projectId, credentials: { type: 'authorized_user',
    client_id: api.clientId(), client_secret: api.clientSecret(), refresh_token: account.tokens.refresh_token } });
  credential = { getAccessToken: async () => {
    const token = await auth.getAccessToken(account.tokens.refresh_token, ['https://www.googleapis.com/auth/cloud-platform']);
    return { access_token: token.access_token, expires_in: Math.max(60, Math.floor(((token.expires_at || Date.now() + 3600000) - Date.now()) / 1000)) };
  } };
}
admin.initializeApp({ projectId, credential });
const { syncMomentSearch } = require('../src/helpers/moment-search');

async function createIndex() {
  const { access_token } = await credential.getAccessToken();
  const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/collectionGroups/momentSearch/indexes`;
  const response = await fetch(base, { method: 'POST', headers: { Authorization: `Bearer ${access_token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ queryScope: 'COLLECTION', fields: [{ fieldPath: 'terms', arrayConfig: 'CONTAINS' }, { fieldPath: 'timestamp', order: 'DESCENDING' }, { fieldPath: '__name__', order: 'DESCENDING' }] }) });
  if (response.status === 409) { console.log('Search composite index already exists.'); return; }
  if (!response.ok) throw new Error(`Index creation failed: HTTP ${response.status}`);
  const result = await response.json();
  console.log(`Search index creation requested: ${result.name}`);
}

async function main() {
  if (process.argv.includes('--index-status')) {
    const { access_token } = await credential.getAccessToken();
    const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/collectionGroups/momentSearch/indexes`, { headers: { Authorization: `Bearer ${access_token}` } });
    if (!response.ok) throw new Error(`Index status failed: HTTP ${response.status}`);
    const result = await response.json();
    console.log(JSON.stringify((result.indexes || []).filter(index => index.name.includes('/collectionGroups/momentSearch/')).map(index => ({ name: index.name, state: index.state, fields: index.fields }))));
    return;
  }
  if (process.argv.includes('--index-only')) { await createIndex(); return; }
  const db = migrationDb || admin.firestore();
  let last = null, count = 0;
  do {
    let query = db.collectionGroup('moments').orderBy(admin.firestore.FieldPath.documentId()).limit(200);
    if (last) query = query.startAfter(last);
    const page = await query.get();
    if (page.empty) break;
    for (let i = 0; i < page.docs.length; i += 10) {
      await Promise.all(page.docs.slice(i, i + 10).map(doc => syncMomentSearch(db, doc.ref.path)));
    }
    count += page.size;
    last = page.docs[page.size - 1];
    console.log(`Indexed source documents: ${count}`);
  } while (true);
  console.log(`Backfill complete: ${count} source documents processed.`);
}
main().then(() => process.exit(0)).catch(error => { console.error(error.message); process.exit(1); });
