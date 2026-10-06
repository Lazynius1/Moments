const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const helper = require('../src/helpers/story-audio');
const body = {ownerId: 'owner', storyId: 'story', stickerId: 'clip'};
const id = helper.audioId('owner', 'story', 'clip');
const bucketName = 'test.firebasestorage.app';
const object = 'users/owner/stories/story/audio/clip.m4a';
const url = `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(object)}?alt=media&token=private`;
function fixture({audience = 'everyone', allow = true, privateAccount = false, visible = true, uid = 'viewer', expired = false} = {}) {
  const writes = [], copies = [], signed = [], metadata = [];
  const docs = new Map([
    ['users/owner', {username: 'creator', isPrivate: privateAccount, isActive: true}],
    ['users/owner/stories/story', {audience, interactionSettings: {allowOriginalAudioReuse: allow}, expirationDate: {toMillis: () => expired ? 0 : Date.now() + 60000}, stickers: [{type: 'audio', stickerId: 'clip', audioURL: url, audioDuration: 60}]}],
  ]);
  const ref = path => ({id: path.split('/').at(-1),
    async get() { return {exists: docs.has(path), data: () => docs.get(path)}; },
    async create(data) { docs.set(path, data); writes.push([path, data]); },
    async set(data) { docs.set(path, data); writes.push([path, data]); },
    async update(data) { docs.set(path, {...docs.get(path), ...data}); },
    async delete() { docs.delete(path); },
  });
  const firestore = () => ({doc: ref, runTransaction: async fn => fn({get: reference => reference.get(), create: (reference, data) => reference.create(data)})}); firestore.FieldValue = {serverTimestamp: () => 'server-time'};
  const bucket = {name: bucketName, file: path => ({
    name: path, async getMetadata() { return [{size: '5000'}]; },
    async copy(target) { copies.push([path, target.name]); },
    async setMetadata(value) { metadata.push(value); },
    async getSignedUrl() { signed.push(path); return ['https://storage.googleapis.com/test/audio?temporary=1']; },
  })};
  const bootstrap = {onRequest: (_opts, fn) => fn, onDocumentDeleted: (_path, fn) => fn, admin: {firestore, storage: () => ({bucket: () => bucket})}};
  const context = {module: {exports: {}}, Date, require: name => {
    if (name === '../bootstrap') return bootstrap;
    if (name === '../helpers') return {setProxyCors() {}, verifyFirebaseAuth: async () => uid, parseJsonBody: req => req.body};
    if (name === '../helpers/feed') return {buildViewerContext: async () => ({}), canViewerSeeStory: async () => visible};
    return helper;
  }};
  vm.runInNewContext(fs.readFileSync(require.resolve('../src/registers/http-story-audio'), 'utf8'), context);
  async function call(name, input = body) {
    const res = {code: 200, set() {}, status(n) { this.code = n; return this; }, json(value) { this.value = value; return this; }};
    await context.module.exports[name]({method: 'POST', body: input}, res); return res;
  }
  return {call, docs, copies, writes, signed, metadata, exported: context.module.exports};
}
test('saving copies public authorized audio outside the expiring story and stores only references', async () => {
  const f = fixture(); const response = await f.call('setStoryOriginalAudioSaved', {...body, saved: true, uid: 'other'});
  assert.equal(response.code, 200); assert.equal(f.copies.length, 1);
  assert.equal(f.copies[0][1], `users/owner/originalStoryAudio/${id}.m4a`);
  assert.equal(f.docs.get(`users/viewer/savedStoryAudio/${id}`).audioId, id);
  assert.equal(f.docs.has(`users/other/savedStoryAudio/${id}`), false);
  assert.equal(f.docs.get(`originalStoryAudio/${id}`).previewURL, undefined);
  assert.equal(f.metadata[0].metadata.firebaseStorageDownloadTokens, null);
  f.docs.delete('users/owner/stories/story');
  assert.equal((await f.call('resolveStoryOriginalAudio', {audioId: id})).code, 200);
});
test('private audiences, private accounts, creator opt-out, expired stories and unauthorized viewers cannot be saved', async () => {
  for (const options of [{audience: 'bestFriends'}, {privateAccount: true}, {allow: false}, {expired: true}, {visible: false}]) {
    const f = fixture(options); const response = await f.call('setStoryOriginalAudioSaved', {...body, saved: true});
    assert.ok(response.code >= 400); assert.equal(f.copies.length, 0); assert.equal(f.writes.length, 0);
  }
});
test('an authorized viewer can preview private audio and gets an explicit reason for disabled saving', async () => {
  for (const [options, reason] of [[{audience: 'bestFriends'}, 'audience'], [{allow: false}, 'creator']]) {
    const f = fixture(options); const response = await f.call('getStoryOriginalAudio');
    assert.equal(response.code, 200); assert.equal(response.value.canSave, false); assert.equal(response.value.reason, reason);
  }
  const hidden = fixture({visible: false}); assert.equal((await hidden.call('getStoryOriginalAudio')).code, 403); assert.equal(hidden.signed.length, 0);
});
test('the audio sheet links to the original creator when another user reuses the audio', async () => {
  const f = fixture();
  const originalId = 'a'.repeat(64);
  f.docs.get('users/owner/stories/story').stickers[0].originalAudioId = originalId;
  f.docs.set('users/originalCreator', {username: 'firstCreator', isPrivate: false, isActive: true});
  f.docs.set(`originalStoryAudio/${originalId}`, {id: originalId, ownerId: 'originalCreator',
    sourceStoryId: 'originalStory', artist: 'firstCreator', duration: 60, active: true});
  const response = await f.call('getStoryOriginalAudio');
  assert.equal(response.code, 200);
  assert.equal(response.value.creatorId, 'originalCreator');
  assert.equal(response.value.track.artist, 'firstCreator');
  assert.equal(response.value.track.id, originalId);
});
test('saved resolution requires the current user bookmark and follows creator revocation', async () => {
  const f = fixture(); assert.equal((await f.call('resolveStoryOriginalAudio', {audioId: id})).code, 403);
  await f.call('setStoryOriginalAudioSaved', {...body, saved: true});
  f.docs.get('users/owner/stories/story').interactionSettings.allowOriginalAudioReuse = false;
  assert.equal((await f.call('resolveStoryOriginalAudio', {audioId: id})).code, 403);
  assert.equal((await f.call('setStoryOriginalAudioSaved', {audioId: id, saved: false})).code, 200);
  assert.equal(f.docs.has(`users/viewer/savedStoryAudio/${id}`), false);
});
test('explicit story deletion revokes reuse but natural expiration preserves it', async () => {
  for (const expired of [false, true]) {
    const f = fixture(); await f.call('setStoryOriginalAudioSaved', {...body, saved: true});
    const story = f.docs.get('users/owner/stories/story'); story.expirationDate = {toMillis: () => expired ? 0 : Date.now() + 60000};
    await f.exported.revokeStoryOriginalAudio({data: {data: () => story}, params: body});
    assert.equal(f.docs.get(`originalStoryAudio/${id}`).active, expired);
  }
});
test('invalid identifiers and unauthenticated callers never read audio', async () => {
  const invalid = fixture(); assert.equal((await invalid.call('getStoryOriginalAudio', {...body, ownerId: '../other'})).code, 400);
  const anonymous = fixture({uid: null}); await anonymous.call('getStoryOriginalAudio'); assert.equal(anonymous.signed.length, 0);
});
test('storage sources must belong to the exact bucket, owner, story and audio directory', () => {
  assert.equal(helper.sourceObject(url, bucketName, 'owner', 'story'), object);
  for (const invalid of [url.replace('https:', 'http:'), url.replace(bucketName, 'other.appspot.com'), url.replace('firebasestorage.googleapis.com', 'evil.test')]) {
    assert.equal(helper.sourceObject(invalid, bucketName, 'owner', 'story'), null);
  }
  assert.equal(helper.sourceObject(url, bucketName, 'other', 'story'), null);
  assert.equal(helper.sourceObject(url, bucketName, 'owner', 'other'), null);
});
