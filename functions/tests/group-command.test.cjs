const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const firestore = Object.assign(() => {}, {
  FieldValue: { serverTimestamp: () => 'SERVER_TIME', delete: () => 'DELETE_FIELD' },
});
const source = fs.readFileSync(path.join(__dirname, '../src/registers/http-groups.js'), 'utf8');
const sandbox = {
  module: { exports: {} }, Buffer, URL, console,
  require(name) {
    if (name === 'node:crypto') return require(name);
    if (name === '../bootstrap') return {
      onRequest: (_, fn) => fn, onCall: (_, fn) => fn, onDocumentCreated: (_, fn) => fn,
      HttpsError: Error, admin: { firestore },
    };
    if (name === '../helpers') return {};
    throw Error(`Unexpected import: ${name}`);
  },
};
vm.runInNewContext(source + '\nmodule.exports.applyGroupCommand = applyGroupCommand;', sandbox);
const command = sandbox.module.exports.applyGroupCommand;
const id = 'group-00000000-0000-0000-0000-000000000001';
function fixture({ alreadyMember = false } = {}) {
  const group = { isGroup: true, participants: ['admin', ...(alreadyMember ? ['joiner'] : [])],
    adminIds: ['admin'], ownerId: 'admin', groupRevision: 4, groupName: 'Before', groupDescription: 'Old',
    pendingJoinIds: ['joiner'], pendingJoinNames: { joiner: 'Person' }, participantData: {}, wrappedKeys: {}, readStatus: {} };
  const documents = {
    [`groupConversations/${id}`]: group, 'users/admin': { username: 'Admin' },
    'users/joiner': { username: 'Person', isActive: true },
    [`groupJoinRequests/${id}_joiner`]: { recipientId: 'joiner', wrappedKey: { key: 'wrapped' } },
  };
  const writes = [];
  const ref = path => ({ path, id: path.split('/').at(-1), collection: name => ({ doc: () => ref(`${path}/${name}/notice`) }) });
  const tx = {
    async get(ref) {
      // Firestore enforces all reads before the first write.
      if (writes.length) throw Error('Firestore transactions require all reads before writes');
      const data = documents[ref.path];
      return { exists: !!data, data: () => data, get: key => data?.[key] };
    },
    update: (ref, data) => writes.push({ kind: 'update', path: ref.path, data }),
    create: (ref, data) => writes.push({ kind: 'create', path: ref.path, data }),
    delete: ref => writes.push({ kind: 'delete', path: ref.path }),
  };
  return { db: { doc: ref, runTransaction: fn => fn(tx) }, writes };
}
const body = action => ({ action, conversationId: id, revision: 4, memberId: 'joiner' });
test('approves a new member with reads before writes', async () => {
  const { db, writes } = fixture();
  await command(db, 'admin', body('approveJoin'));
  const change = writes.find(w => w.data?.participants);
  assert.ok(change.data.participants.includes('joiner'));
  assert.ok(writes.some(w => w.kind === 'delete' && w.path.endsWith('_joiner')));
});
for (const [action, alreadyMember] of [['declineJoin', false], ['approveJoin', true]]) {
  test(`${action}, existing=${alreadyMember}, clears request without duplicate membership`, async () => {
    const { db, writes } = fixture({ alreadyMember });
    await command(db, 'admin', body(action));
    assert.ok(writes.some(w => w.kind === 'delete'));
    assert.ok(!writes.some(w => w.data?.participants));
  });
}
test('saves name and description in one revision and one write', async () => {
  const { db, writes } = fixture();
  await command(db, 'admin', { ...body('rename'), name: ' New ', description: ' About us ' });
  assert.equal(writes.length, 1);
  assert.equal(writes[0].data.groupName, 'New');
  assert.equal(writes[0].data.groupDescription, 'About us');
  assert.equal(writes[0].data.groupRevision, 5);
});
test('legacy rename preserves description; blank description clears it', async () => {
  for (const extra of [{}, { description: '  ' }]) {
    const { db, writes } = fixture();
    await command(db, 'admin', { ...body('rename'), name: 'New', ...extra });
    assert.equal(writes[0].data.groupDescription, 'description' in extra ? '' : undefined);
  }
});
test('invalid description or stale revision cannot partially rename', async () => {
  for (const extra of [{ description: 'x'.repeat(281) }, { description: 123 }, { revision: 3 }]) {
    const { db, writes } = fixture();
    await assert.rejects(command(db, 'admin', { ...body('rename'), name: 'New', ...extra }));
    assert.equal(writes.length, 0);
  }
});
