const { test } = require('node:test');
const assert = require('node:assert/strict');
const { normalizeSong, parseMusicPage, soundstripeRequest } = require('../src/helpers/story-music');

test('music normalization follows primary relationship IDs rather than included ordering', () => {
  const song = { id: '9', attributes: { title: 'Song', lyrics: 'Words' }, relationships: { artists: { data: [{ id: '2' }] }, audio_files: { data: [{ id: '3' }] } } };
  const included = [
    { id: '7', type: 'audio_files', attributes: { duration: 12, versions: { mp3: 'https://cdn.soundstripe.com/wrong.mp3' } } },
    { id: '3', type: 'audio_files', attributes: { duration: 180, versions: { mp3: 'https://cdn.soundstripe.com/right.mp3', wav: 'https://cdn.soundstripe.com/full.wav' } } },
    { id: '2', type: 'artists', attributes: { name: 'Artist', image: 'https://cdn.soundstripe.com/image.jpg' } }
  ];
  const result = normalizeSong(song, included);
  assert.equal(result.previewURL, 'https://cdn.soundstripe.com/right.mp3');
  assert.equal(result.artist, 'Artist');
  assert.equal(result.duration, 180);
  assert.equal(result.lyrics, 'Words');
  assert.ok(!JSON.stringify(result).includes('full.wav'));
});

test('malformed and unplayable songs do not become selectable tracks', () => {
  assert.equal(normalizeSong({ id: '1', attributes: { title: 'Song' } }), null);
  assert.equal(normalizeSong(null), null);
});

test('page cursors cannot supply arbitrary upstream URLs', () => {
  assert.equal(parseMusicPage(null), 1);
  assert.equal(parseMusicPage('2'), 2);
  for (const value of ['0', '-1', 'Infinity', 'https://example.com', {}, '100001']) assert.throws(() => parseMusicPage(value));
});

test('upstream failures do not disclose vendor messages or secrets', async () => {
  await assert.rejects(soundstripeRequest('/v1/songs', 'test-key', async () => ({ ok: false, status: 403 })), error => error.message === 'music_unavailable' && error.status === 503);
});
