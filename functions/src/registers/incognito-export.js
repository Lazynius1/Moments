const b = require('../bootstrap');
const h = require('../helpers');
const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
  onSchedule,
  onRequest,
  admin,
  fs,
  path,
  os,
  crypto,
  OPENAI_API_KEY,
  SIGHTENGINE_USER,
  SIGHTENGINE_SECRET,
  AWS_ACCESS_KEY_ID,
  AWS_SECRET_ACCESS_KEY,
  AWS_REGION,
  GOOGLE_SPEECH_API_KEY,
  GIPHY_API_KEY,
  TELEGRAM_BOT_TOKEN,
  TELEGRAM_CHAT_ID
} = b;
const {
  addMediaItemStorageUrls,
  addOwnedBackgroundFrameStorageUrl,
  addStorageUrl,
  apnsCollapseId,
  approvedModerationDecision,
  asDate,
  batchLoadAuthorDocs,
  buildCsvFiles,
  buildDataExportPayload,
  buildDefaultIncognitoState,
  buildExportZipParts,
  buildForYouDiscoveryContext,
  buildGentleReminderState,
  buildInlineKeyboardButton,
  buildLegacyMomentMediaFields,
  buildMapFallbackCandidateUserIds,
  buildMessageRequestConversationPreview,
  buildModerationAlertPayload,
  buildModerationReviewRequestAlertPayload,
  buildModerationTelegramReplyMarkup,
  buildReadmeContent,
  buildViewerContext,
  callOpenAIModeration,
  callRekognitionModeration,
  callSightengineModeration,
  canViewerSeeMoment,
  canViewerSeeStory,
  chooseGentleReminderVariant,
  collectDeletedContentStorageUrls,
  countSharedInterests,
  createIncognitoHandler,
  createRekognitionClient,
  daysSince,
  decryptChatContent,
  deleteMutualDocuments,
  deleteOriginalMomentVideoIfSafe,
  deleteStorageUrlIfSafe,
  deleteStorageUrls,
  deletedModerationDecision,
  deterministicForYouJitter,
  downloadStorageObjectToBuffer,
  downloadStorageObjectToFile,
  escapeCsvCell,
  escapeTelegramHtml,
  evaluateTranscriptModerationPayload,
  expectedImageMetadataFromObjectName,
  extractModerationAudioFromVideo,
  extractModerationFramesFromVideo,
  fetchConversationSharedKey,
  fetchForYouFollowerPublicUserIds,
  fetchForYouGlobalEveryoneDocs,
  fetchForYouInterestUserIds,
  fetchForYouSecondDegreeUserIds,
  fetchMapCandidatesByAuthorBatches,
  fetchNovaConversations,
  fetchUserConversations,
  fetchUserSubcollection,
  filterVisibleEntriesAfterCursor,
  findExistingDirectConversation,
  firebaseStorageDownloadUrl,
  flattenRow,
  forYouMomentPath,
  forYouTierWeight,
  gentleRemindersEnabled,
  getDateKeyForTimeZone,
  getMuteSettings,
  getPendingCommentCount,
  getPendingFollowRequestCount,
  getPendingFollowerCount,
  getPendingMomentReactionCount,
  getPendingMutualConnectionCount,
  getPendingStoryReactionCount,
  getUnreadCounts,
  getUnreadMessagesInConversation,
  getUnreadReactionSummary,
  hasPostedToday,
  hasVisibleMediaItem,
  hiddenLayerIdFromMediaItemId,
  hoursSince,
  incognitoStateNeedsPersistence,
  inferFileExtension,
  isActiveUserData,
  isDoNotDisturbActive,
  isExcludedForYouAuthor,
  isFirestoreFailedPrecondition,
  isMomentPathAuthorConsistent,
  isSameFeedCursor,
  isStoryPathAuthorConsistent,
  isWithinAggregationWindow,
  loadModerationPolicy,
  mergeModerationDecisions,
  moderateImageBufferWithFallback,
  moderateVideoFileWithFallback,
  normalizeMutedWords,
  normalizeReminderHistory,
  normalizeTimeZoneIdentifier,
  notificationTypeEnabled,
  oldestGlobalStreamCursor,
  parseJsonBody,
  parseTimeToMinutes,
  permanentlyDeleteRecentlyDeletedDoc,
  persistableIncognitoState,
  pickMomentPreviewUrl,
  pickStoryPreviewUrl,
  processForYouFeedPage,
  purgeSocialNotifications,
  reconcileMutualConnection,
  removeInvalidToken,
  resolveIncognitoState,
  resolveStorageObjectNameFromClientMediaReference,
  rowsToCsv,
  runFfmpeg,
  runIncognitoTransition,
  sanitizeFileName,
  sanitizeStorageSegment,
  scoreForYouMoment,
  sendGentleReminderPush,
  sendTelegramModerationAlert,
  sendTelegramTextOrPhoto,
  serializeHighlightedStory,
  serializeIncognitoStateForResponse,
  serializeMediaItem,
  serializeMoment,
  serializeRestrictedMoment,
  setProxyCors,
  shouldSilenceNotificationForUser,
  socialNotificationDocId,
  startOfTodayInTimezone,
  storageBucketsAreEquivalent,
  storageCustomMetadata,
  storageMetadataOwnerMatches,
  storageObjectBelongsToConversation,
  storageObjectBelongsToUser,
  storageObjectIsAllowedForExport,
  storageObjectNameFromExportMediaUrl,
  storageObjectNameFromFirebaseUrl,
  storageObjectNameFromTrustedValue,
  storageProjectIdFromBucketName,
  storyPrimaryMediaUrl,
  summarizeTopSignals,
  textContainsMutedWord,
  timestampToDate,
  toSerializable,
  transcodeMomentVideo,
  transcodeStoryVideo,
  transcribeAudioBuffer,
  tsToMillis,
  uploadStorageFile,
  upsertMutualDocuments,
  upsertSocialNotification,
  userOwnedHiddenLayerImageObjectNameFromFirebaseUrl,
  userOwnedImageObjectNameFromFirebaseUrl,
  userOwnedPublishableMediaObjectNameFromFirebaseUrl,
  userOwnedVideoObjectNameFromFirebaseUrl,
  usersAreBlocked,
  validateUserData,
  verifyFirebaseAuth,
  warningModerationDecision
} = h;

const getIncognitoState = createIncognitoHandler('get');
const activateIncognito = createIncognitoHandler('activate');
const pauseIncognito = createIncognitoHandler('pause');
const resumeIncognito = createIncognitoHandler('resume');

const onDataExportRequestCreated = onDocumentCreated({
  document: 'users/{userId}/dataExportRequests/{requestId}',
  timeoutSeconds: 3600,
  memory: '8GiB',
  maxInstances: 2
}, async (event) => {
  const userId = event.params.userId;
  const requestId = event.params.requestId;
  const requestRef = admin.firestore().doc(`users/${userId}/dataExportRequests/${requestId}`);

  const requestData = event.data?.data() || {};
  const status = requestData.status || 'pending';
  if (status !== 'pending') return;

  const exportType = requestData.exportType || 'complete';
  const requestedFormat = requestData.format || 'json';
  const pin = typeof requestData.pin === 'string' ? requestData.pin : null;

  try {
    await requestRef.update({
      status: 'processing',
      progress: 0.1,
      pin: admin.firestore.FieldValue.delete(),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    });

    const payload = await buildDataExportPayload(userId, exportType, requestedFormat, pin);

    await requestRef.update({
      status: 'uploading',
      progress: 0.75,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    });

    const now = new Date();
    const stamp = now.toISOString().replace(/[:.]/g, '-');
    const parts = await buildExportZipParts(payload, requestedFormat, exportType, userId);
    const expiresAt = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

    const downloadParts = [];
    const bucket = admin.storage().bucket();
    for (let i = 0; i < parts.length; i += 1) {
      const suffix = parts.length > 1 ? `_part${i + 1}of${parts.length}` : '';
      const objectName = `exports/${userId}/moments_export_${stamp}${suffix}.zip`;
      await bucket.upload(parts[i].path, {
        destination: objectName,
        metadata: {
          contentType: 'application/zip',
          cacheControl: 'private, max-age=0, no-cache'
        }
      });
      fs.unlink(parts[i].path, () => {});
      const [url] = await bucket.file(objectName).getSignedUrl({ action: 'read', expires: expiresAt });
      downloadParts.push({ index: i + 1, total: parts.length, bytes: parts[i].bytes, downloadURL: url });
    }

    await requestRef.update({
      status: 'ready',
      progress: 1.0,
      downloadURL: downloadParts[0].downloadURL,
      downloadParts,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      expirationDate: admin.firestore.Timestamp.fromDate(expiresAt),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    });

    await admin.firestore()
      .collection('users')
      .doc(userId)
      .collection('notifications')
      .add({
        type: 'data_export_ready',
        // Sin texto fijo: el cliente muestra la cadena localizada
        // (notifications.message.dataExportReady) según el idioma del dispositivo.
        message: '',
        downloadURL: downloadParts[0].downloadURL,
        downloadPartsCount: downloadParts.length,
        senderId: 'system',
        senderUsername: 'Moments',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isPending: true,
        isRead: false
      });

    console.log(`✅ data export ready: user=${userId} request=${requestId}`);
  } catch (error) {
    console.error(`❌ data export failed: user=${userId} request=${requestId}`, error);
    await requestRef.update({
      status: 'failed',
      progress: 0.0,
      errorMessage: error?.message || 'Export failed',
      lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    });
  }
});

const onModerationReviewQueueCreated = onDocumentCreated(
  {
    document: 'moderationReviewQueue/{queueId}',
    timeoutSeconds: 60,
    secrets: [TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID]
  },
  async (event) => {
    try {
      const data = event.data?.data() || {};
      const payload = await buildModerationAlertPayload(event.params.queueId, data);
      await sendTelegramModerationAlert(payload);

      console.log(`✅ Telegram moderation alert sent for queue item ${event.params.queueId}`);
    } catch (error) {
      console.error('❌ Error sending Telegram moderation alert:', error);
    }
  }
);

const onAppealCreatedTelegramAlert = onDocumentCreated(
  {
    document: 'moderationReviewRequests/{requestId}',
    timeoutSeconds: 60,
    secrets: [TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID]
  },
  async (event) => {
    try {
      const data = event.data?.data() || {};
      const payload = await buildModerationReviewRequestAlertPayload(event.params.requestId, data);
      await sendTelegramTextOrPhoto(payload);
      console.log(`✅ Telegram moderation review alert sent for request ${event.params.requestId}`);
    } catch (error) {
      console.error('❌ Error sending Telegram moderation review alert:', error);
    }
  }
);

const proxyOpenAIModeration = onRequest(
  {
    timeoutSeconds: 30,
    secrets: [OPENAI_API_KEY]
  },
  async (req, res) => {
    setProxyCors(res);
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const uid = await verifyFirebaseAuth(req, res);
    if (!uid) return;

    const body = parseJsonBody(req);
    const input = typeof body.input === 'string' ? body.input : '';
    if (!input.trim()) {
      res.status(400).json({ error: 'Missing input' });
      return;
    }

    try {
      const upstream = await fetch('https://api.openai.com/v1/moderations', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${OPENAI_API_KEY.value()}`
        },
        body: JSON.stringify({ input })
      });

      const payload = await upstream.text();
      res.status(upstream.status).set('Content-Type', 'application/json').send(payload);
    } catch (error) {
      console.error('proxyOpenAIModeration error:', error);
      res.status(500).json({ error: 'Moderation proxy failed' });
    }
  }
);

const proxySightengineFrame = onRequest(
  {
    timeoutSeconds: 30,
    secrets: [SIGHTENGINE_USER, SIGHTENGINE_SECRET]
  },
  async (req, res) => {
    setProxyCors(res);
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const uid = await verifyFirebaseAuth(req, res);
    if (!uid) return;

    const body = parseJsonBody(req);
    const frameBase64 = typeof body.frameBase64 === 'string' ? body.frameBase64 : '';
    if (!frameBase64) {
      res.status(400).json({ error: 'Missing frameBase64' });
      return;
    }

    try {
      const imageBuffer = Buffer.from(frameBase64, 'base64');
      const formData = new FormData();
      formData.append('api_user', SIGHTENGINE_USER.value());
      formData.append('api_secret', SIGHTENGINE_SECRET.value());
      formData.append('models', 'nudity-2.1,face-attributes,scam,offensive');
      formData.append('media', new Blob([imageBuffer], { type: 'image/jpeg' }), 'frame.jpg');

      const upstream = await fetch('https://api.sightengine.com/1.0/check.json', {
        method: 'POST',
        body: formData
      });

      const payload = await upstream.text();
      res.status(upstream.status).set('Content-Type', 'application/json').send(payload);
    } catch (error) {
      console.error('proxySightengineFrame error:', error);
      res.status(500).json({ error: 'Sightengine proxy failed' });
    }
  }
);

const moderateMediaContent = onRequest(
  {
    timeoutSeconds: 120,
    memory: '1GiB',
    secrets: [
      OPENAI_API_KEY,
      SIGHTENGINE_USER,
      SIGHTENGINE_SECRET,
      AWS_ACCESS_KEY_ID,
      AWS_SECRET_ACCESS_KEY,
      AWS_REGION,
      GOOGLE_SPEECH_API_KEY
    ]
  },
  async (req, res) => {
    setProxyCors(res);
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const uid = await verifyFirebaseAuth(req, res);
    if (!uid) return;

    const body = parseJsonBody(req);
    const mediaType = typeof body.mediaType === 'string' ? body.mediaType : '';
    const mediaURL = typeof body.mediaURL === 'string' ? body.mediaURL.trim() : '';
    const imageBase64 = typeof body.imageBase64 === 'string' ? body.imageBase64.trim() : '';
    const contentType = typeof body.contentType === 'string' ? body.contentType.trim() : '';
    const contentId = typeof body.contentId === 'string' ? body.contentId.trim() : '';
    const mediaItemId = typeof body.mediaItemId === 'string' ? body.mediaItemId.trim() : '';

    if (!['image', 'video', 'story_sticker'].includes(mediaType)) {
      res.status(400).json({ error: 'Unsupported mediaType' });
      return;
    }

    if ((mediaType === 'image' || mediaType === 'video') && !mediaURL) {
      res.status(400).json({ error: 'Missing mediaURL' });
      return;
    }

    if (mediaType === 'story_sticker' && !imageBase64) {
      res.status(400).json({ error: 'Missing imageBase64' });
      return;
    }

    let localVideoPath = null;
    try {
      let decision;

      if (mediaType === 'story_sticker') {
        const imageBuffer = Buffer.from(imageBase64, 'base64');
        decision = await moderateImageBufferWithFallback(imageBuffer);
      } else if (mediaType === 'image') {
        const bucket = admin.storage().bucket();
        const objectName = userOwnedImageObjectNameFromFirebaseUrl(mediaURL, uid, { contentType, contentId, mediaItemId });
        if (!objectName) {
          const resolvedPath = resolveStorageObjectNameFromClientMediaReference(mediaURL, bucket);
          console.warn('moderateMediaContent rejected image source', {
            uid,
            contentType,
            contentId,
            mediaItemId,
            bucket: bucket.name,
            resolvedPath,
            mediaURLPrefix: String(mediaURL || '').slice(0, 180)
          });
          throw new Error('Image source must match publishable Firebase Storage media for this content and user');
        }

        const imageBuffer = await downloadStorageObjectToBuffer({ bucket, objectName, uid });
        decision = await moderateImageBufferWithFallback(imageBuffer);
      } else {
        const bucket = admin.storage().bucket();
        const objectName = userOwnedVideoObjectNameFromFirebaseUrl(mediaURL, uid);
        if (!objectName) {
          throw new Error('Video source must be a Firebase Storage upload owned by this user');
        }

        localVideoPath = path.join(os.tmpdir(), `moderation_video_${Date.now()}_${crypto.randomUUID()}.mp4`);
        await downloadStorageObjectToFile({ bucket, objectName, destinationPath: localVideoPath });
        decision = await moderateVideoFileWithFallback(localVideoPath);
      }

      res.status(200).json({
        success: true,
        action: decision.action,
        reason: decision.reason,
        category: decision.category,
        provider: decision.provider || decision.details?.provider || 'unknown',
        fallbackUsed: decision.details?.fallbackUsed === true,
        visualScore: decision.visualScore ?? 0,
        audioScore: decision.audioScore ?? null,
        combinedScore: decision.combinedScore ?? 0,
        details: decision.details || {}
      });
    } catch (error) {
      console.error('moderateMediaContent error:', error);
      res.status(500).json({
        success: false,
        action: 'warning',
        reason: 'Revisión manual pendiente por error interno de moderación',
        category: 'system_error',
        provider: 'backend_error',
        fallbackUsed: false,
        visualScore: 0,
        audioScore: null,
        combinedScore: 0,
        details: {
          error: error.message || 'Unknown moderation error'
        }
      });
    } finally {
      if (localVideoPath) {
        try { if (fs.existsSync(localVideoPath)) fs.unlinkSync(localVideoPath); } catch (error) {}
      }
    }
  }
);

const proxySpeechToText = onRequest(
  {
    timeoutSeconds: 30,
    secrets: [GOOGLE_SPEECH_API_KEY]
  },
  async (req, res) => {
    setProxyCors(res);
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const uid = await verifyFirebaseAuth(req, res);
    if (!uid) return;

    const body = parseJsonBody(req);
    const audioBase64 = typeof body.audioBase64 === 'string' ? body.audioBase64 : '';
    if (!audioBase64) {
      res.status(400).json({ error: 'Missing audioBase64' });
      return;
    }

    const requestBody = {
      config: {
        encoding: 'LINEAR16',
        sampleRateHertz: 44100,
        languageCode: 'es-ES',
        enableAutomaticPunctuation: true,
        model: 'latest_short'
      },
      audio: {
        content: audioBase64
      }
    };

    try {
      const speechURL = `https://speech.googleapis.com/v1/speech:recognize?key=${encodeURIComponent(GOOGLE_SPEECH_API_KEY.value())}`;
      const upstream = await fetch(speechURL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(requestBody)
      });

      const payload = await upstream.text();
      res.status(upstream.status).set('Content-Type', 'application/json').send(payload);
    } catch (error) {
      console.error('proxySpeechToText error:', error);
      res.status(500).json({ error: 'Speech proxy failed' });
    }
  }
);

const proxyGiphyStickers = onRequest(
  {
    timeoutSeconds: 30,
    secrets: [GIPHY_API_KEY]
  },
  async (req, res) => {
    setProxyCors(res);
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST' && req.method !== 'GET') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const uid = await verifyFirebaseAuth(req, res);
    if (!uid) return;

    const body = parseJsonBody(req);
    const modeSource = req.method === 'GET' ? req.query : body;
    const mode = modeSource.mode === 'search' ? 'search' : 'trending';
    const rating = typeof modeSource.rating === 'string' ? modeSource.rating : 'pg';
    const rawLimit = Number(modeSource.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 50)) : 24;
    const rawOffset = Number(modeSource.offset);
    const offset = Number.isFinite(rawOffset) ? Math.max(0, Math.min(rawOffset, 4999)) : 0;
    const query = typeof modeSource.query === 'string' ? modeSource.query.trim() : '';

    if (mode === 'search' && !query) {
      res.status(400).json({ error: 'Missing query for search mode' });
      return;
    }

    const params = new URLSearchParams({
      api_key: GIPHY_API_KEY.value(),
      limit: String(limit),
      offset: String(offset),
      rating
    });
    if (mode === 'search') {
      params.set('q', query);
    }

    const endpoint = mode === 'search'
      ? 'https://api.giphy.com/v1/stickers/search'
      : 'https://api.giphy.com/v1/stickers/trending';

    try {
      const upstream = await fetch(`${endpoint}?${params.toString()}`, { method: 'GET' });
      const payload = await upstream.text();
      res.status(upstream.status).set('Content-Type', 'application/json').send(payload);
    } catch (error) {
      console.error('proxyGiphyStickers error:', error);
      res.status(500).json({ error: 'Giphy proxy failed' });
    }
  }
);

// ✅ Proxy GIF de Giphy (trending/search) para el chat — paralelo a proxyGiphyStickers
const proxyGiphyGifs = onRequest(
  {
    timeoutSeconds: 30,
    secrets: [GIPHY_API_KEY]
  },
  async (req, res) => {
    setProxyCors(res);
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST' && req.method !== 'GET') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const uid = await verifyFirebaseAuth(req, res);
    if (!uid) return;

    const body = parseJsonBody(req);
    const modeSource = req.method === 'GET' ? req.query : body;
    const mode = modeSource.mode === 'search' ? 'search' : 'trending';
    const rating = typeof modeSource.rating === 'string' ? modeSource.rating : 'pg';
    const rawLimit = Number(modeSource.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 50)) : 24;
    const rawOffset = Number(modeSource.offset);
    const offset = Number.isFinite(rawOffset) ? Math.max(0, Math.min(rawOffset, 4999)) : 0;
    const query = typeof modeSource.query === 'string' ? modeSource.query.trim() : '';

    if (mode === 'search' && !query) {
      res.status(400).json({ error: 'Missing query for search mode' });
      return;
    }

    const params = new URLSearchParams({
      api_key: GIPHY_API_KEY.value(),
      limit: String(limit),
      offset: String(offset),
      rating
    });
    if (mode === 'search') {
      params.set('q', query);
    }

    const endpoint = mode === 'search'
      ? 'https://api.giphy.com/v1/gifs/search'
      : 'https://api.giphy.com/v1/gifs/trending';

    try {
      const upstream = await fetch(`${endpoint}?${params.toString()}`, { method: 'GET' });
      const payload = await upstream.text();
      res.status(upstream.status).set('Content-Type', 'application/json').send(payload);
    } catch (error) {
      console.error('proxyGiphyGifs error:', error);
      res.status(500).json({ error: 'Giphy proxy failed' });
    }
  }
);

module.exports = {
  getIncognitoState,
  activateIncognito,
  pauseIncognito,
  resumeIncognito,
  onDataExportRequestCreated,
  onModerationReviewQueueCreated,
  onAppealCreatedTelegramAlert,
  proxyOpenAIModeration,
  proxySightengineFrame,
  moderateMediaContent,
  proxySpeechToText,
  proxyGiphyStickers,
  proxyGiphyGifs,
};
