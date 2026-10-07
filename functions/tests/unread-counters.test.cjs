const test = require('node:test');
const assert = require('node:assert/strict');
const {
  effectiveUnreadCount, nextUnreadCount, staleUnreadCounterUids, countUnreadFromMessages, isInvalidFcmTokenError
} = require('../src/helpers/unread-counters');
const {
  participantsAllDeleted, shouldRunConversationCleanup, vanishModeTurnedOff
} = require('../src/helpers/conversation-write-guards');

const ts = millis => ({ toMillis: () => millis });

test('el contador solo vale mientras readStatus es false', () => {
  assert.equal(effectiveUnreadCount({ readStatus: { a: true }, unreadCounts: { a: 7 } }, 'a'), 0);
  assert.equal(effectiveUnreadCount({ unreadCounts: { a: 7 } }, 'a'), 0);
  assert.equal(effectiveUnreadCount({ readStatus: { a: false }, unreadCounts: { a: 7 } }, 'a'), 7);
  assert.equal(effectiveUnreadCount({ readStatus: { a: false } }, 'a'), null);
  assert.equal(effectiveUnreadCount({ readStatus: { a: false }, unreadCounts: { a: 'x' } }, 'a'), null);
});

test('incremento: tras leer reinicia a 1 y en datos antiguos usa el fallback', () => {
  assert.equal(nextUnreadCount({ readStatus: { a: false }, unreadCounts: { a: 2 } }, 'a'), 3);
  assert.equal(nextUnreadCount({ readStatus: { a: true }, unreadCounts: { a: 5 } }, 'a'), 1);
  assert.equal(nextUnreadCount({}, 'a'), 1);
  assert.equal(nextUnreadCount({ readStatus: { a: false } }, 'a', 4), 4);
  assert.equal(nextUnreadCount({ readStatus: { a: false } }, 'a', 0), 1);
  assert.equal(nextUnreadCount({ readStatus: { a: false } }, 'a'), 1);
});

test('reset pendiente solo para quien ya leyó con contador > 0', () => {
  const data = { readStatus: { a: true, b: false, c: true }, unreadCounts: { a: 3, b: 2, c: 0 } };
  assert.deepEqual(staleUnreadCounterUids(data), ['a']);
  assert.deepEqual(staleUnreadCounterUids({ readStatus: { a: true } }), []);
  assert.deepEqual(staleUnreadCounterUids(null), []);
});

test('fallback acotado con lastReadAt cuenta entrantes visibles', () => {
  const messages = [
    { senderId: 'b', timestamp: ts(300) },
    { senderId: 'b', timestamp: ts(250), isDeleted: true },
    { senderId: 'b', timestamp: ts(220), deletedFor: ['a'] },
    { senderId: 'a', timestamp: ts(210) },
    { senderId: 'b', timestamp: ts(200) }
  ];
  assert.equal(countUnreadFromMessages(messages, 'a', { lastReadMillis: 100 }), 2);
  assert.equal(countUnreadFromMessages([], 'a', { lastReadMillis: 100 }), 1);
});

test('fallback sin lastReadAt cuenta la racha reciente', () => {
  const messages = [
    { senderId: 'b' }, { senderId: 'b', isDeleted: true }, { senderId: 'b' },
    { senderId: 'b', status: 'read' }, { senderId: 'b' }
  ];
  assert.equal(countUnreadFromMessages(messages, 'a'), 2);
  assert.equal(countUnreadFromMessages([{ senderId: 'a' }, { senderId: 'b' }], 'a'), 1);
});

test('tokens FCM inválidos', () => {
  assert.ok(isInvalidFcmTokenError({ code: 'messaging/registration-token-not-registered' }));
  assert.ok(isInvalidFcmTokenError({ code: 'messaging/invalid-registration-token' }));
  assert.ok(!isInvalidFcmTokenError({ code: 'messaging/internal-error' }));
  assert.ok(!isInvalidFcmTokenError(undefined));
});

test('trigger de conversación: limpieza solo en la transición a todos borrados', () => {
  const live = { participants: ['a', 'b'], deletedFor: ['a'] };
  const gone = { participants: ['a', 'b'], deletedFor: ['a', 'b'] };
  assert.ok(!participantsAllDeleted(live));
  assert.ok(participantsAllDeleted(gone));
  assert.ok(!participantsAllDeleted({ participants: [], deletedFor: [] }));
  assert.ok(shouldRunConversationCleanup(live, gone));
  assert.ok(shouldRunConversationCleanup(null, gone));
  assert.ok(!shouldRunConversationCleanup(gone, { ...gone, lastMessage: 'x' }));
  assert.ok(!shouldRunConversationCleanup(live, { ...live, lastMessage: 'x' }));
});

test('trigger de conversación: purga vanish solo al desactivarlo', () => {
  assert.ok(vanishModeTurnedOff({ vanishModeActive: true }, { vanishModeActive: false }));
  assert.ok(!vanishModeTurnedOff({ vanishModeActive: true }, { vanishModeActive: true }));
  assert.ok(!vanishModeTurnedOff({ vanishModeActive: false }, { vanishModeActive: false }));
  assert.ok(!vanishModeTurnedOff(null, { vanishModeActive: false }));
  assert.ok(!vanishModeTurnedOff({ vanishModeActive: true }, { }));
});
