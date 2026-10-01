const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const { parseMusicPage, normalizeSong } = require('../src/helpers/story-music');

function fixture(uid = 'viewer') {
  const writes = [], requests = [];
  const song = { type: 'songs', id: '42', attributes: { title: 'Song', lyrics: 'Lyrics' }, relationships: { artists: { data: [{ id: '2' }] }, audio_files: { data: [{ id: '3' }] } } };
  const included = [song, { type: 'artists', id: '2', attributes: { name: 'Artist' } }, { type: 'audio_files', id: '3', attributes: { duration: 180, versions: { mp3: 'https://example.org/audio?expires=1' } } }];
  const ref = {
    collection(name) { writes.push(['collection', name]); return this; },
    doc(id) { writes.push(['doc', id]); return this; },
    orderBy() { return this; },
    async get() { return { docs: [{ data: () => ({ track: { id: '42', title: 'Song' } }) }] }; },
    async set(value) { writes.push(['set', value]); }, async delete() { writes.push(['delete']); }
  };
  const firestore = () => ref; firestore.FieldValue = { serverTimestamp: () => 'timestamp' };
  const bootstrap = { onRequest: (_options, handler) => handler, defineSecret: () => ({ value: () => 'secret' }), admin: { firestore } };
  const helpers = { setProxyCors() {}, verifyFirebaseAuth: async () => uid, parseJsonBody: req => req.body };
  const music = { parseMusicPage, normalizeSong, soundstripeRequest: async path => {
    requests.push(path);
    if (path.includes('/playlists/')) return { data: { relationships: { songs: { data: [{ id: '42' }] } } }, included };
    if (path.includes('/playlists?')) return { data: [{ id: '8', attributes: { name: 'Discover' } }], links: { next: 'ignored' } };
    return { data: song, included };
  }};
  const context = { module: { exports: {} }, URLSearchParams, require: name => name === '../bootstrap' ? bootstrap : name === '../helpers' ? helpers : music };
  vm.runInNewContext(fs.readFileSync(require.resolve('../src/registers/http-story-music'), 'utf8'), context);
  async function call(name, body = {}) {
    const res = { code: 200, set() {}, status(code) { this.code = code; return this; }, json(value) { this.value = value; return this; } };
    await context.module.exports[name]({ method: 'POST', body }, res);
    return res;
  }
  return { writes, requests, call };
}

test('bookmarks use the authenticated user and persist no signed URL or lyrics', async () => {
  const f = fixture(); const res = await f.call('setStoryMusicSaved', { trackId: '42', saved: true, uid: 'other' });
  assert.equal(res.code, 200);
  assert.deepEqual(f.writes.slice(0, 4), [['collection', 'users'], ['doc', 'viewer'], ['collection', 'savedMusic'], ['doc', '42']]);
  const saved = f.writes.find(([type]) => type === 'set')[1];
  assert.equal(saved.track.id, '42'); assert.equal(saved.track.previewURL, undefined); assert.equal(saved.track.lyrics, undefined);
});
test('removing a bookmark does not contact the vendor', async () => {
  const f = fixture(); await f.call('setStoryMusicSaved', { trackId: '42', saved: false });
  assert.equal(f.requests.length, 0); assert.ok(f.writes.some(([type]) => type === 'delete'));
});
test('unauthenticated requests cannot read or mutate favorites', async () => {
  const f = fixture(null); await f.call('setStoryMusicSaved', { trackId: '42', saved: true }); await f.call('getStoryMusicSaved');
  assert.equal(f.writes.length, 0); assert.equal(f.requests.length, 0);
});
test('invalid track and playlist identifiers never reach Firestore or the vendor', async () => {
  const f = fixture();
  assert.equal((await f.call('setStoryMusicSaved', { trackId: '../other', saved: true })).code, 400);
  assert.equal((await f.call('getStoryMusicDiscover', { playlistId: 'https://other' })).code, 400);
  assert.equal(f.requests.length, 0); assert.equal(f.writes.length, 0);
});
test('discovery requests the selected playlist page and follows relationship IDs', async () => {
  const f = fixture(); const res = await f.call('getStoryMusicDiscover', { playlistId: '8', cursor: '2' });
  assert.equal(res.value.tracks[0].id, '42');
  assert.ok(f.requests[0].includes('page%5Bnumber%5D=2')); assert.ok(f.requests[0].startsWith('/v1/playlists/8?'));
});
