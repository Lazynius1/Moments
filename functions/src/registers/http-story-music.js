const { onRequest, defineSecret, admin } = require('../bootstrap');
const { setProxyCors, verifyFirebaseAuth, parseJsonBody } = require('../helpers');
const { normalizeSong, parseMusicPage, soundstripeRequest } = require('../helpers/story-music');

const SOUNDSTRIPE_API_KEY = defineSecret('SOUNDSTRIPE_API_KEY');
const options = { secrets: [SOUNDSTRIPE_API_KEY], timeoutSeconds: 25, memory: '256MiB', maxInstances: 2, concurrency: 20 };

function endpoint(handler) {
  return onRequest(options, async (req, res) => {
    setProxyCors(res);
    res.set('Cache-Control', 'private, no-store');
    if (req.method === 'OPTIONS') return res.status(204).send('');
    if (req.method !== 'POST') return res.status(405).json({ error: 'method_not_allowed' });
    const uid = await verifyFirebaseAuth(req, res);
    if (!uid) return;
    try { await handler(parseJsonBody(req), res, uid); }
    catch (error) {
      const invalid = error.message === 'invalid_cursor';
      res.status(invalid ? 400 : (error.status || 503)).json({ error: invalid ? 'invalid_cursor' : 'music_unavailable' });
    }
  });
}

const getStoryMusicCatalog = endpoint(async (body, res) => {
  const query = typeof body.query === 'string' ? body.query.trim() : '';
  if (query.length > 200) return res.status(400).json({ error: 'invalid_query' });
  const page = parseMusicPage(body.cursor);
  const params = new URLSearchParams({ 'page[size]': '30', 'page[number]': String(page) });
  if (query) params.set('filter[q]', query);
  const data = await soundstripeRequest(`/v1/songs?${params}`, SOUNDSTRIPE_API_KEY.value());
  const tracks = (Array.isArray(data.data) ? data.data : []).map(song => normalizeSong(song, data.included)).filter(Boolean);
  // Never follow a client/upstream URL. Only the validated page number is reused.
  res.json({ tracks, nextCursor: data.links?.next && page < 100000 ? String(page + 1) : null });
});

const getStoryMusicTrack = endpoint(async (body, res) => {
  if (typeof body.trackId !== 'string' || !/^\d{1,20}$/.test(body.trackId)) return res.status(400).json({ error: 'invalid_track' });
  const data = await soundstripeRequest(`/v1/songs/${body.trackId}`, SOUNDSTRIPE_API_KEY.value());
  const track = normalizeSong(data.data, data.included);
  if (!track) return res.status(404).json({ error: 'music_unavailable' });
  res.json(track);
});

const getStoryMusicDiscover = endpoint(async (body, res) => {
  const page = parseMusicPage(body.cursor);
  const params = new URLSearchParams({ 'page[size]': '30', 'page[number]': String(page) });
  if (body.playlistId != null) {
    if (typeof body.playlistId !== 'string' || !/^\d{1,20}$/.test(body.playlistId)) return res.status(400).json({ error: 'invalid_playlist' });
    params.set('include', 'songs,songs.artists,songs.audio_files');
    const data = await soundstripeRequest(`/v1/playlists/${body.playlistId}?${params}`, SOUNDSTRIPE_API_KEY.value());
    const ids = data.data?.relationships?.songs?.data || [];
    const songs = ids.map(ref => (data.included || []).find(item => item.type === 'songs' && item.id === ref.id)).filter(Boolean);
    res.json({ tracks: songs.map(song => normalizeSong(song, data.included)).filter(Boolean), nextCursor: (data.links?.next || songs.length === 30) && page < 100000 ? String(page + 1) : null });
  } else {
    const data = await soundstripeRequest(`/v1/playlists?${params}`, SOUNDSTRIPE_API_KEY.value());
    res.json({ playlists: (data.data || []).map(item => ({ id: String(item.id), title: String(item.attributes?.name || item.attributes?.title || ''), artworkURL: item.attributes?.image || null })).filter(item => item.title), nextCursor: data.links?.next && page < 100000 ? String(page + 1) : null });
  }
});

const getStoryMusicSaved = endpoint(async (body, res, uid) => {
  // Only explicit bookmarks. No searches, previews, or listening history are stored.
  const snapshot = await admin.firestore().collection('users').doc(uid).collection('savedMusic').orderBy('savedAt', 'desc').get();
  res.json({ tracks: snapshot.docs.map(doc => doc.data().track) });
});

const setStoryMusicSaved = endpoint(async (body, res, uid) => {
  if (typeof body.trackId !== 'string' || !/^\d{1,20}$/.test(body.trackId) || typeof body.saved !== 'boolean') return res.status(400).json({ error: 'invalid_track' });
  const ref = admin.firestore().collection('users').doc(uid).collection('savedMusic').doc(body.trackId);
  if (!body.saved) {
    await ref.delete();
  } else {
    const data = await soundstripeRequest(`/v1/songs/${body.trackId}`, SOUNDSTRIPE_API_KEY.value());
    const track = normalizeSong(data.data, data.included);
    if (!track) return res.status(404).json({ error: 'music_unavailable' });
    // Signed audio URLs and lyrics are not needed for a bookmark.
    const { previewURL, lyrics, ...metadata } = track;
    await ref.set({ track: metadata, savedAt: admin.firestore.FieldValue.serverTimestamp() });
  }
  res.json({ saved: body.saved });
});

module.exports = { getStoryMusicCatalog, getStoryMusicTrack, getStoryMusicDiscover, getStoryMusicSaved, setStoryMusicSaved };
