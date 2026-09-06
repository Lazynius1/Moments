const { onRequest, onDocumentWritten, admin } = require('../bootstrap');
const { setProxyCors, parseJsonBody, verifyFirebaseAuth } = require('../helpers');
const { syncMomentSearch, searchMomentsPage } = require('../helpers/moment-search');

const syncMomentSearchIndex = onDocumentWritten('users/{userId}/moments/{momentId}', event =>
  syncMomentSearch(admin.firestore(), `users/${event.params.userId}/moments/${event.params.momentId}`));

const searchMoments = onRequest({ timeoutSeconds: 60, memory: '512MiB', concurrency: 20 }, async (req, res) => {
  setProxyCors(res);
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  if (req.method !== 'POST') { res.status(405).json({ error: 'Method not allowed' }); return; }
  const uid = await verifyFirebaseAuth(req, res);
  if (!uid) return;
  try {
    const page = await searchMomentsPage(admin.firestore(), uid, parseJsonBody(req));
    res.status(200).json({ ...page, source: 'backend-search-v1' });
  } catch (error) {
    console.error('searchMoments failed', error);
    res.status(error.status || 500).json({ error: 'Search failed' });
  }
});

const getExplorePage = onRequest({ timeoutSeconds: 60, memory: '512MiB', concurrency: 20 }, async (req, res) => {
  setProxyCors(res);
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  if (req.method !== 'POST') { res.status(405).json({ error: 'Method not allowed' }); return; }
  const uid = await verifyFirebaseAuth(req, res);
  if (!uid) return;
  try {
    const body = parseJsonBody(req);
    const { buildViewerContext } = require('../helpers/feed');
    const { rankedPage } = require('../helpers/for-you-feed');
    const page = await rankedPage({ db: admin.firestore(), uid, body,
      viewerCtx: await buildViewerContext(uid), surface: 'explore',
      limit: Math.max(1, Math.min(30, Math.floor(Number(body.limit) || 24))) });
    res.status(200).json({ ...page, source: 'backend-explore-v1' });
  } catch (error) {
    console.error('getExplorePage failed', error);
    res.status(error.status || 500).json({ error: 'Explore failed' });
  }
});

module.exports = { searchMoments, syncMomentSearchIndex, getExplorePage };
