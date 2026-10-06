const crypto = require('crypto');
function validId(value) { return typeof value === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(value); }
function audioId(ownerId, storyId, stickerId) {
  return crypto.createHash('sha256').update(`${ownerId}:${storyId}:${stickerId}`).digest('hex');
}
function savingReason(story, author, sticker) {
  if (story.audience !== 'everyone' || author.isPrivate === true) return 'audience';
  if (!sticker.originalAudioId && story.interactionSettings?.allowOriginalAudioReuse !== true) return 'creator';
  return null;
}
function sourceObject(url, bucket, ownerId, storyId) {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' || parsed.hostname !== 'firebasestorage.googleapis.com') return null;
    const parts = parsed.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
    if (!parts || decodeURIComponent(parts[1]) !== bucket) return null;
    const object = decodeURIComponent(parts[2]);
    const prefix = `users/${ownerId}/stories/${storyId}/audio/`;
    return object.startsWith(prefix) && /^[A-Za-z0-9_-]+\.m4a$/.test(object.slice(prefix.length)) ? object : null;
  } catch { return null; }
}
module.exports = {validId, audioId, savingReason, sourceObject};
