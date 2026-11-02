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
  doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, collection, query, where, orderBy, limitToLast, Timestamp,
  arrayUnion, deleteField, serverTimestamp, writeBatch
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

// ─── Chat: contadores, eliminar para todos y estado de entrega ───────────────

const seedChat = (message = {}, conversation = {}) => seed(async db => {
  await setDoc(doc(db, 'conversations/c1'), {
    participants: ['alice', 'bob'], encryptionVersion: '3.0',
    readStatus: { alice: true, bob: false }, unreadCounts: { alice: 0, bob: 3 }, ...conversation
  });
  await setDoc(doc(db, 'conversations/c1/messages/m1'), {
    id: 'm1', conversationId: 'c1', senderId: 'alice', type: 'image', status: 'sent',
    isRead: false, isDeleted: false, isViewed: false, timestamp: Timestamp.now(),
    content: 'cifrado', mediaUrl: 'https://x', thumbnailUrl: 'https://t',
    mediaObjectPath: 'users/alice/chat/c1/m1/a.enc', thumbnailObjectPath: 'users/alice/chat/c1/m1/thumbnails/t.jpg',
    mediaEncryption: { v: 1 }, thumbnailEncryption: { v: 1 },
    textOverlayLive: true, textOverlays: [{ t: 1 }], stickers: [{ s: 1 }], ...message
  });
});
const m1 = uid => doc(as(uid), 'conversations/c1/messages/m1');

test('conversations: unreadCounts solo lo escribe el servidor', { skip }, async () => {
  await seedChat();
  const db = as('bob');
  await assertFails(updateDoc(doc(db, 'conversations/c1'), { 'unreadCounts.bob': 0 }));
  await assertFails(updateDoc(doc(db, 'conversations/c1'), { 'unreadCounts.alice': 9 }));
  // Marcar leído como hoy (iOS/Android) sigue funcionando con el campo presente.
  await assertSucceeds(updateDoc(doc(db, 'conversations/c1'), {
    'readStatus.bob': true, 'lastReadAt.bob': serverTimestamp()
  }));
  // Y "marcar como no leído".
  await assertSucceeds(updateDoc(doc(db, 'conversations/c1'), { 'readStatus.bob': false }));
  // Ni siquiera al crear la conversación.
  await seed(async sdb => setDoc(doc(sdb, 'users/alice/mutuals/carol'), { userId: 'carol' }));
  await assertFails(setDoc(doc(as('alice'), 'conversations/c2'), {
    encryptionVersion: '3.0', participants: ['alice', 'carol'], wrappedKeys: { alice: 'k', carol: 'k' },
    unreadCounts: { carol: 0 }
  }));
});

const deleteForEveryone = (extra = {}) => ({
  isDeleted: true, deletedAt: serverTimestamp(),
  content: deleteField(), mediaUrl: deleteField(), thumbnailUrl: deleteField(),
  mediaObjectPath: deleteField(), thumbnailObjectPath: deleteField(),
  mediaEncryption: deleteField(), thumbnailEncryption: deleteField(),
  textOverlayLive: deleteField(), textOverlays: deleteField(), stickers: deleteField(), drawingData: deleteField(),
  ...extra
});

test('messages: eliminar para todos borra también capas de edición (iOS/Android)', { skip }, async () => {
  await seedChat();
  await assertFails(updateDoc(m1('bob'), deleteForEveryone()));
  await assertFails(updateDoc(m1('alice'), deleteForEveryone({ senderId: 'bob' })));
  await assertSucceeds(updateDoc(m1('alice'), deleteForEveryone()));
});

test('messages: eliminar para todos ligero (avisos vanish) sigue permitido', { skip }, async () => {
  await seedChat({ type: 'chatNotice' });
  await assertSucceeds(updateDoc(m1('alice'), {
    isDeleted: true, deletedAt: serverTimestamp(), content: deleteField(), mediaUrl: deleteField()
  }));
});

test('messages: el estado solo avanza sent < delivered < read', { skip }, async () => {
  await seedChat();
  await assertFails(updateDoc(m1('bob'), { status: 'failed' }));
  await assertFails(updateDoc(m1('bob'), { status: 'sending' }));
  await assertFails(updateDoc(m1('bob'), { status: 'pending' }));
  await assertSucceeds(updateDoc(m1('bob'), { status: 'delivered' }));
  await assertSucceeds(updateDoc(m1('bob'), {
    readBy: arrayUnion('bob'), isRead: true, status: 'read', 'readAtBy.bob': serverTimestamp()
  }));
  // Retrocesos: delivered tardío, rama view-once y 'sent' del receptor.
  await assertFails(updateDoc(m1('bob'), { status: 'delivered' }));
  await assertFails(updateDoc(m1('bob'), { isViewed: true, status: 'delivered' }));
  await assertFails(updateDoc(m1('bob'), { status: 'sent' }));
  await assertFails(updateDoc(m1('alice'), { status: 'failed' }));
  // Recibos desactivados: solo readBy, sin tocar status.
  await assertSucceeds(updateDoc(m1('bob'), { readBy: arrayUnion('carol') }));
});

test('messages: compat del sent redundante del remitente tras crear', { skip }, async () => {
  await seedChat({ status: 'delivered' });
  // Android publicado no captura este error: se tolera solo {status:'sent'} del remitente.
  await assertFails(updateDoc(m1('alice'), { status: 'sent', isViewed: true }));
  await assertSucceeds(updateDoc(m1('alice'), { status: 'sent' }));
});

test('messages: estados legacy fuera de rango pueden avanzar', { skip }, async () => {
  await seedChat({ status: 'failed' });
  await assertSucceeds(updateDoc(m1('bob'), { status: 'delivered' }));
});

test('messages: batch de leído (mensajes + conversación) pasa con unreadCounts presente', { skip }, async () => {
  await seedChat({ status: 'delivered' });
  const db = as('bob');
  const batch = writeBatch(db);
  batch.update(doc(db, 'conversations/c1/messages/m1'), {
    readBy: arrayUnion('bob'), isRead: true, status: 'read', 'readAtBy.bob': serverTimestamp()
  });
  batch.update(doc(db, 'conversations/c1'), {
    'readStatus.bob': true, 'lastReadAt.bob': serverTimestamp(), 'lastMessageSeenAt.bob': serverTimestamp()
  });
  await assertSucceeds(batch.commit());
});

test('groups: el historial previo a memberJoinedAt sigue legible (sin cambio, ver informe)', { skip }, async () => {
  const gid = 'group-00000000-0000-0000-0000-000000000001';
  const joinedAt = Timestamp.fromMillis(Date.now());
  await seed(async db => {
    await setDoc(doc(db, `groupConversations/${gid}`), {
      participants: ['alice', 'bob'], memberJoinedAt: { bob: joinedAt }, readStatus: { alice: true, bob: true }
    });
    await setDoc(doc(db, `groupConversations/${gid}/groupMessages/old`), {
      senderId: 'alice', type: 'text', timestamp: Timestamp.fromMillis(joinedAt.toMillis() - 60000)
    });
  });
  const messages = collection(as('bob'), `groupConversations/${gid}/groupMessages`);
  // Consultas sin corte por joinedAt (galería, stats, get puntual) que usan los clientes publicados.
  await assertSucceeds(getDoc(doc(messages, 'old')));
  await assertSucceeds(getDocs(query(messages, orderBy('timestamp'), limitToLast(50))));
  await assertFails(getDocs(collection(as('carol'), `groupConversations/${gid}/groupMessages`)));
});

// ─── Seguridad (noviembre 2026) ──────────────────────────────────────────────

test('usernames: se puede consultar un nombre pero no listar ni buscar por email', { skip }, async () => {
  await seed(async db => { await setDoc(doc(db, 'usernames/alice'), { userId: 'alice' }); });
  const anon = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(anon, 'usernames/alice')));
  await assertFails(getDocs(collection(anon, 'usernames')));
  await assertFails(getDocs(query(collection(as('bob'), 'usernames'), where('email', '==', 'alice@example.com'))));
});

test('suspensión: no se levanta mientras dura, sí cuando ha caducado', { skip }, async () => {
  const future = Timestamp.fromMillis(Date.now() + 86400000);
  const past = Timestamp.fromMillis(Date.now() - 86400000);
  await seed(async db => {
    await updateDoc(doc(db, 'users/alice'), { isSuspended: true, suspendedUntil: future, suspensionReason: 'spam' });
    await updateDoc(doc(db, 'users/bob'), { isSuspended: true, suspendedUntil: past, suspensionReason: 'spam' });
    await updateDoc(doc(db, 'users/carol'), { isSuspended: true, suspensionReason: 'spam' });
  });
  const lift = { isSuspended: false, suspendedUntil: deleteField(), suspensionReason: deleteField() };
  await assertFails(updateDoc(doc(as('alice'), 'users/alice'), lift));
  await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { isSuspended: false }));
  await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { suspendedUntil: past }));
  await assertFails(updateDoc(doc(as('carol'), 'users/carol'), lift));
  await assertSucceeds(updateDoc(doc(as('bob'), 'users/bob'), lift));
  // Nadie puede suspenderse ni tocar el campo sin estar suspendido.
  await assertFails(updateDoc(doc(as('carol'), 'users/carol'), { suspensionReason: 'x' }));
});

test('notificaciones: nada de avisos de sistema en el buzón de otro', { skip }, async () => {
  const n = id => doc(as('bob'), `users/alice/notifications/${id}`);
  await assertSucceeds(setDoc(n('r1'), { senderId: 'bob', type: 'reaction', timestamp: Timestamp.now() }));
  await assertFails(setDoc(n('m1'), { senderId: 'bob', type: 'mediaModeration', timestamp: Timestamp.now() }));
  await assertFails(setDoc(n('a1'), { type: 'appeal_approved', timestamp: Timestamp.now() }));
  await assertFails(setDoc(n('f1'), { senderId: 'carol', type: 'reaction', timestamp: Timestamp.now() }));
  // A uno mismo (moderación de la propia subida) sigue permitido.
  await assertSucceeds(setDoc(doc(as('alice'), 'users/alice/notifications/self'),
    { type: 'mediaModeration', timestamp: Timestamp.now() }));
});

test('historias: otro solo puede poner la caducidad oficial de su cadena', { skip }, async () => {
  const created = Timestamp.fromMillis(Date.now() - 3600000);
  const official = Timestamp.fromMillis(created.toMillis() + 48 * 3600000);
  await seed(async db => {
    await setDoc(doc(db, 'storyChains/ch1'), { id: 'ch1', title: 't', createdBy: 'alice', createdAt: created, partCount: 2 });
    await setDoc(doc(db, 'users/alice/stories/s1'), { authorId: 'alice', mediaItem: { url: 'u' }, chainId: 'ch1',
      expirationDate: Timestamp.fromMillis(Date.now() + 3600000) });
    await setDoc(doc(db, 'users/alice/stories/s2'), { authorId: 'alice', mediaItem: { url: 'u' },
      expirationDate: Timestamp.fromMillis(Date.now() + 3600000) });
  });
  await assertSucceeds(updateDoc(doc(as('bob'), 'users/alice/stories/s1'), { expirationDate: official }));
  await assertFails(updateDoc(doc(as('bob'), 'users/alice/stories/s1'), { expirationDate: Timestamp.now() }));
  await assertFails(updateDoc(doc(as('bob'), 'users/alice/stories/s2'), { expirationDate: official }));
  await assertSucceeds(updateDoc(doc(as('alice'), 'users/alice/stories/s2'), { expirationDate: Timestamp.now() }));
});

test('listas de audiencia: el dueño y los miembros, nadie más', { skip }, async () => {
  await seed(async db => {
    await setDoc(doc(db, 'users/alice/customAudienceLists/l1'), { name: 'amigos', members: ['bob'], createdAt: Timestamp.now() });
  });
  await assertSucceeds(getDoc(doc(as('alice'), 'users/alice/customAudienceLists/l1')));
  await assertSucceeds(getDocs(collection(as('alice'), 'users/alice/customAudienceLists')));
  await assertSucceeds(getDoc(doc(as('bob'), 'users/alice/customAudienceLists/l1')));
  await assertFails(getDoc(doc(as('carol'), 'users/alice/customAudienceLists/l1')));
  await assertFails(getDocs(collection(as('bob'), 'users/alice/customAudienceLists')));
});

test('historias: reacciones y respuestas a stickers solo del autor y de cada uno', { skip }, async () => {
  await seed(async db => {
    await setDoc(doc(db, 'users/alice/stories/s1'), { authorId: 'alice', mediaItem: { url: 'u' }, audience: 'everyone',
      expirationDate: Timestamp.fromMillis(Date.now() + 3600000) });
    await setDoc(doc(db, 'users/alice/stories/s1/reactions/bob'), { userId: 'bob', reaction: '🔥', timestamp: Timestamp.now() });
    await setDoc(doc(db, 'users/alice/stories/s1/stickerInteractions/q1_bob'), { userId: 'bob', selectedIndex: 1 });
  });
  await assertSucceeds(getDocs(collection(as('alice'), 'users/alice/stories/s1/reactions')));
  await assertSucceeds(getDoc(doc(as('bob'), 'users/alice/stories/s1/reactions/bob')));
  await assertFails(getDocs(collection(as('carol'), 'users/alice/stories/s1/reactions')));
  const si = (uid, id) => doc(as(uid), `users/alice/stories/s1/stickerInteractions/${id}`);
  await assertSucceeds(getDoc(si('bob', 'q1_bob')));
  await assertFails(getDoc(si('carol', 'q1_bob')));
  await assertFails(setDoc(si('carol', 'q1_bob'), { userId: 'carol', selectedIndex: 0 }));
  await assertFails(deleteDoc(si('carol', 'q1_bob')));
  await assertSucceeds(setDoc(si('carol', 'q1_carol'),
    { userId: 'carol', stickerId: 'q1', type: 'quiz', selectedIndex: 0, isCorrect: false, timestamp: serverTimestamp() }));
  await assertSucceeds(getDocs(collection(as('alice'), 'users/alice/stories/s1/stickerInteractions')));
});

test('datos privados: solo el dueño los lee y solo escribe token, bloqueados y mejores amigos', { skip }, async () => {
  await seed(db => setDoc(doc(db, 'users/priv1/private/account'), {
    email: 'priv1@example.com', birthDate: Timestamp.fromDate(new Date('1990-01-01')), countryCode: 'ES',
    blockedUsers: [], bestFriends: []
  }));
  const own = doc(as('priv1'), 'users/priv1/private/account');
  await assertSucceeds(getDoc(own));
  await assertFails(getDoc(doc(as('other'), 'users/priv1/private/account')));
  await assertFails(getDocs(collection(as('other'), 'users/priv1/private')));
  await assertSucceeds(updateDoc(own, { blockedUsers: arrayUnion('x'), bestFriends: arrayUnion('y'), fcmToken: 't', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(own, { birthDate: Timestamp.fromDate(new Date('2015-01-01')) }));
  await assertFails(updateDoc(own, { countryCode: 'US' }));
  await assertFails(updateDoc(own, { email: 'otro@example.com' }));
  await assertFails(updateDoc(own, { blockedUsers: 'x' }));
  await assertFails(deleteDoc(own));
  await assertFails(setDoc(doc(as('other'), 'users/priv1/private/account'), { blockedUsers: [] }, { merge: true }));
  await assertSucceeds(setDoc(doc(as('priv2'), 'users/priv2/private/account'), { bestFriends: ['a'] }, { merge: true }));
  await assertFails(setDoc(doc(as('priv3'), 'users/priv3/private/otro'), { bestFriends: [] }));
  await assertFails(setDoc(doc(as('priv4'), 'users/priv4/private/account'), { email: 'x@example.com' }));
  // El índice inverso solo lo escribe el servidor; el dueño lo lee y nadie más.
  await seed(db => setDoc(doc(db, 'users/priv1/private/relations'), { blockedBy: ['z'], bestFriendOf: [] }));
  await assertSucceeds(getDoc(doc(as('priv1'), 'users/priv1/private/relations')));
  await assertFails(getDoc(doc(as('z'), 'users/priv1/private/relations')));
  await assertFails(setDoc(doc(as('priv1'), 'users/priv1/private/relations'), { blockedBy: [] }));
});
