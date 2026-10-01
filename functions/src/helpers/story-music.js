const API_ORIGIN = 'https://api.soundstripe.com';

function mediaURL(value) {
  if (typeof value !== 'string') return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' ? url.href : null;
  } catch { return null; }
}

function normalizeSong(song, included = []) {
  const attrs = song?.attributes || {};
  const artistId = song?.relationships?.artists?.data?.[0]?.id;
  const audioId = song?.relationships?.audio_files?.data?.[0]?.id;
  const artist = included.find(r => r.type === 'artists' && r.id === artistId)?.attributes || {};
  const audio = included.find(r => r.type === 'audio_files' && r.id === audioId)?.attributes || {};
  const duration = Number(audio.duration);
  const previewURL = mediaURL(audio.versions?.mp3);
  if (!song?.id || !attrs.title || !Number.isFinite(duration) || duration <= 0 || !previewURL) return null;
  // Do not expose WAV/stems, privileged keys, or the full upstream document.
  return {
    id: String(song.id), title: String(attrs.title), artist: String(artist.name || ''),
    duration, artworkURL: mediaURL(artist.image), previewURL,
    lyrics: typeof attrs.lyrics === 'string' ? attrs.lyrics : null
  };
}

function parseMusicPage(value) {
  if (value === null || value === undefined || value === '') return 1;
  if (typeof value !== 'string' || !/^\d{1,6}$/.test(value)) throw new Error('invalid_cursor');
  const page = Number(value);
  if (page < 1 || page > 100000) throw new Error('invalid_cursor');
  return page;
}

async function soundstripeRequest(path, key, fetchImpl = fetch) {
  const response = await fetchImpl(new URL(path, API_ORIGIN), {
    headers: { Authorization: `Token ${key}`, Accept: 'application/vnd.api+json' },
    signal: AbortSignal.timeout(15000), redirect: 'error'
  });
  if (!response.ok) {
    const error = new Error('music_unavailable');
    error.status = response.status === 404 ? 404 : 503;
    throw error;
  }
  return response.json();
}

module.exports = { normalizeSong, parseMusicPage, soundstripeRequest };
