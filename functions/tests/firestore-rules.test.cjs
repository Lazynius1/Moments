// Tests de firestore.rules contra el emulador. Ejecutar con `npm run test:rules`
// (levanta el emulador de Firestore). Sin emulador se omiten.
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

const EMULATOR = process.env.FIRESTORE_EMULATOR_HOST;
const skip = EMULATOR ? false : 'FIRESTORE_EMULATOR_HOST no definido (usa npm run test:rules)';

const {
  initializeTestEnvironment, assertSucceeds, assertFails
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, collection, query, where, Timestamp
} = require('firebase/firestore');

let env;

const newUser = (uid, overrides = {}) => ({
  id: uid,
  email: `${uid}@example.com`,
  username: uid,
  interests: [],
  isPlusSubscriber: false,
  blockedUsers: [],
  isPrivate: false,
  showMutuals: true,
  showFollowing: true,
  showFollowers: true,
  bestFriends: [],
  isActive: true,
  showBadge: true,
  showPlusBadge: true,
  isVerified: false,
  ownedBadges: [],
  privacyPolicyAccepted: true,
  privacyPolicyAcceptedAt: Timestamp.now(),
  privacyPolicyVersion: '2026-09',
  birthDate: Timestamp.fromDate(new Date('1990-01-01')),
  countryCode: 'ES',
  ...overrides
});

const as = uid => env.authenticatedContext(uid).firestore();
const seed = fn => env.withSecurityRulesDisabled(ctx => fn(ctx.firestore()));

test.before(async () => {
  if (skip) return;
  const [host, port] = EMULATOR.split(':');
  env = await initializeTestEnvironment({
    projectId: 'demo-moments-rules',
    firestore: {
      host,
      port: Number(port),
      rules: fs.readFileSync(process.env.RULES_PATH || path.join(__dirname, '../../firestore.rules'), 'utf8')
    }
  });
});

test.beforeEach(async () => {
  if (skip) return;
  await env.clearFirestore();
  await seed(async db => {
    await setDoc(doc(db, 'users/alice'), newUser('alice'));
    await setDoc(doc(db, 'users/bob'), newUser('bob'));
    await setDoc(doc(db, 'users/carol'), newUser('carol'));
  });
});

test.after(async () => {
  if (env) await env.cleanup();
});

test('users: el alta normal de ambas apps sigue funcionando', { skip }, async () => {
  await assertSucceeds(setDoc(doc(as('dave'), 'users/dave'), newUser('dave')));
});

test('users: no se puede nacer con privilegios', { skip }, async () => {
  const db = as('dave');
  await assertFails(setDoc(doc(db, 'users/dave'), newUser('dave', { isPlusSubscriber: true })));
  await assertFails(setDoc(doc(db, 'users/dave'), newUser('dave', { isVerified: true })));
  await assertFails(setDoc(doc(db, 'users/dave'), newUser('dave', { role: 'admin' })));
  await assertFails(setDoc(doc(db, 'users/dave'), newUser('dave', { ownedBadges: [{ badgeId: 'plus' }] })));
  await assertFails(setDoc(doc(db, 'users/dave'), newUser('dave', { plusSubscription: { isActive: true } })));
  await assertFails(setDoc(doc(db, 'users/dave'), newUser('dave', { primaryBadgeId: 'plus' })));
});

test('users: no se pueden auto-asignar privilegios después', { skip }, async () => {
  const db = as('alice');
  await assertFails(updateDoc(doc(db, 'users/alice'), { role: 'admin' }));
  await assertFails(updateDoc(doc(db, 'users/alice'), { isVerified: true }));
  await assertFails(updateDoc(doc(db, 'users/alice'), { isPlusSubscriber: true }));
  await assertFails(updateDoc(doc(db, 'users/alice'), { ownedBadges: [{ badgeId: 'plus' }] }));
  // Edición normal de perfil y reescribir el mismo valor siguen permitidos.
  await assertSucceeds(updateDoc(doc(db, 'users/alice'), { bio: 'hola', isVerified: false }));
});

test('moderationSettings: un usuario normal no puede escribir', { skip }, async () => {
  await assertFails(setDoc(doc(as('alice'), 'moderationSettings/global'), { x: 1 }));
});

test('visits: el visitante solo lista las suyas, el dueño todas', { skip }, async () => {
  await seed(async db => {
    await setDoc(doc(db, 'users/alice/visits/v1'), { visitorId: 'bob', timestamp: Timestamp.now() });
    await setDoc(doc(db, 'users/alice/visits/v2'), { visitorId: 'carol', timestamp: Timestamp.now() });
  });
  const visits = db => collection(db, 'users/alice/visits');
  await assertSucceeds(getDocs(visits(as('alice'))));
  await assertFails(getDocs(visits(as('bob'))));
  // Deduplicación de registerVisit (iOS y Android).
  const recent = Timestamp.fromMillis(Date.now() - 5 * 60 * 1000);
  await assertSucceeds(getDocs(query(visits(as('bob')),
    where('visitorId', '==', 'bob'), where('timestamp', '>', recent))));
  await assertFails(getDocs(query(visits(as('bob')), where('visitorId', '==', 'carol'))));
  await assertSucceeds(setDoc(doc(as('bob'), 'users/alice/visits/v3'),
    { visitorId: 'bob', timestamp: Timestamp.now() }));
});

test('visitSummaries y userActivity: solo el dueño escribe', { skip }, async () => {
  await assertFails(setDoc(doc(as('bob'), 'users/alice/visitSummaries/today'), { visitCount: 1 }));
  await assertFails(setDoc(doc(as('bob'), 'users/alice/userActivity/a'), { x: 1 }));
  await assertSucceeds(setDoc(doc(as('alice'), 'users/alice/visitSummaries/today'), { visitCount: 1 }));
});

test('conversations: solo 1:1 entre mutuals y cifrada', { skip }, async () => {
  await seed(async db => {
    await setDoc(doc(db, 'users/alice/mutuals/bob'), { userId: 'bob' });
  });
  const db = as('alice');
  const base = { encryptionVersion: '3.0' };
  await assertFails(setDoc(doc(db, 'conversations/group'), {
    ...base, participants: ['alice', 'bob', 'carol'],
    wrappedKeys: { alice: 'k', bob: 'k', carol: 'k' }
  }));
  await assertFails(setDoc(doc(db, 'conversations/plain'), { participants: ['alice', 'bob'] }));
  await assertFails(setDoc(doc(db, 'conversations/stranger'), {
    ...base, participants: ['alice', 'carol'], wrappedKeys: { alice: 'k', carol: 'k' }
  }));
  await assertSucceeds(setDoc(doc(db, 'conversations/ok'), {
    ...base, participants: ['alice', 'bob'], wrappedKeys: { alice: 'k', bob: 'k' }
  }));
});

test('messages: ningún participante puede borrar físicamente', { skip }, async () => {
  await seed(async db => {
    await setDoc(doc(db, 'conversations/c1'), { participants: ['alice', 'bob'] });
    await setDoc(doc(db, 'conversations/c1/messages/m1'), { senderId: 'alice', timestamp: Timestamp.now() });
  });
  await assertFails(deleteDoc(doc(as('bob'), 'conversations/c1/messages/m1')));
  await assertFails(deleteDoc(doc(as('alice'), 'conversations/c1/messages/m1')));
});

test('usernames: get público para comprobar disponibilidad', { skip }, async () => {
  await seed(async db => {
    await setDoc(doc(db, 'usernames/alice'), { userId: 'alice', email: 'alice@example.com' });
  });
  await assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(), 'usernames/alice')));
});
