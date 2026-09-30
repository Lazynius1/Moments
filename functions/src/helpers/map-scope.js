// Social map candidates contain the viewer and followed accounts. Mutuals are
// already a subset of following; audience authorization remains in http-feed.
function mapSocialAuthorIds(uid, viewerCtx) {
  const blocked = viewerCtx.blockedUsers || new Set();
  return [...new Set([uid, ...(viewerCtx.following || [])])]
    .filter(id => typeof id === 'string' && id.length > 0 && !blocked.has(id));
}

module.exports = { mapSocialAuthorIds };
