const b = require('../bootstrap');
const h = require('../helpers');
const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
  onSchedule,
  onRequest,
  admin,
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

const permanentlyDeleteRecentlyDeletedBatch = onRequest(
  {
    timeoutSeconds: 120,
    memory: '512MiB',
    concurrency: 10
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
    const rawIds = Array.isArray(body.ids) ? body.ids : [];
    const ids = [...new Set(rawIds
      .map((id) => (typeof id === 'string' ? id.trim() : ''))
      .filter(Boolean))]
      .slice(0, 50);

    if (ids.length === 0) {
      res.status(400).json({ error: 'No ids provided' });
      return;
    }

    const db = admin.firestore();
    const recentlyDeletedRefs = ids.map((id) => db.doc(`users/${uid}/recentlyDeleted/${id}`));

    try {
      const docs = await db.getAll(...recentlyDeletedRefs);
      let deletedDocuments = 0;
      let missing = 0;
      let storageDeleted = 0;
      let storageSkipped = 0;
      const details = [];

      for (const doc of docs) {
        const result = await permanentlyDeleteRecentlyDeletedDoc(doc);
        if (result.status === 'missing') {
          missing += 1;
          details.push({ id: result.id, status: 'missing' });
          continue;
        }

        deletedDocuments += result.deletedDocuments;
        storageDeleted += result.storageDeleted;
        storageSkipped += result.storageSkipped;
        details.push({
          id: result.id,
          type: result.type,
          status: 'deleted',
          storageDeleted: result.storageDeleted,
          storageSkipped: result.storageSkipped
        });
      }

      console.log(
        `✅ permanentlyDeleteRecentlyDeletedBatch: uid=${uid}, docs=${deletedDocuments}, missing=${missing}, storageDeleted=${storageDeleted}, storageSkipped=${storageSkipped}`
      );
      res.status(200).json({ deletedDocuments, missing, storageDeleted, storageSkipped, details });
    } catch (error) {
      console.error('❌ permanentlyDeleteRecentlyDeletedBatch error:', error);
      res.status(500).json({ error: 'Permanent delete failed', details: error.message });
    }
  }
);

const cleanExpiredRecentlyDeleted = onSchedule(
  {
    schedule: '15 3 * * *',
    timeZone: 'Europe/Madrid',
    region: 'us-central1',
    timeoutSeconds: 540,
    memory: '512MiB',
    concurrency: 1
  },
  async () => {
    const db = admin.firestore();
    const retentionDays = 30;
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000)
    );
    const batchLimit = 100;
    const maxBatches = 20;
    let batches = 0;
    let deletedDocuments = 0;
    let storageDeleted = 0;
    let storageSkipped = 0;
    let failed = 0;

    try {
      while (batches < maxBatches) {
        const snapshot = await db
          .collectionGroup('recentlyDeleted')
          .where('deletedAt', '<', cutoff)
          .limit(batchLimit)
          .get();

        if (snapshot.empty) break;

        batches += 1;
        for (const doc of snapshot.docs) {
          try {
            const result = await permanentlyDeleteRecentlyDeletedDoc(doc);
            deletedDocuments += result.deletedDocuments;
            storageDeleted += result.storageDeleted;
            storageSkipped += result.storageSkipped;
          } catch (error) {
            failed += 1;
            console.error(`❌ cleanExpiredRecentlyDeleted failed for ${doc.ref.path}:`, error);
          }
        }

        if (snapshot.size < batchLimit) break;
      }

      console.log(
        `✅ cleanExpiredRecentlyDeleted: deleted=${deletedDocuments}, storageDeleted=${storageDeleted}, storageSkipped=${storageSkipped}, failed=${failed}, batches=${batches}`
      );
    } catch (error) {
      console.error('❌ cleanExpiredRecentlyDeleted error:', error);
    }
  }
);

const processMomentVideos = onDocumentCreated(
  {
    document: 'users/{userId}/moments/{momentId}',
    memory: '2GiB',
    timeoutSeconds: 540,
    concurrency: 1,
    retry: false
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const { userId, momentId } = event.params;
    const momentRef = snap.ref;
    const data = snap.data() || {};
    const mediaItems = Array.isArray(data.mediaItems) ? data.mediaItems : [];
    const pendingIndexes = mediaItems
      .map((item, index) => ({ item, index }))
      .filter(({ item }) => item && item.type === 'video' && item.videoProcessingStatus === 'pending' && item.url);

    if (pendingIndexes.length === 0) return;

    let updatedItems = mediaItems.map((item, index) => {
      if (pendingIndexes.some((entry) => entry.index === index)) {
        return {
          ...item,
          originalVideoUrl: item.originalVideoUrl || item.url,
          videoProcessingStatus: 'processing'
        };
      }
      return item;
    });

    const processingLegacyFields = buildLegacyMomentMediaFields(updatedItems);
    await momentRef.update({
      mediaItems: updatedItems,
      ...processingLegacyFields,
      videoProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    for (const { item, index } of pendingIndexes) {
      try {
        const processed = await transcodeMomentVideo({ userId, momentId, mediaItem: item });
        const originalVideoUrl = item.originalVideoUrl || item.url;
        const originalDeleted = await deleteOriginalMomentVideoIfSafe({
          originalUrl: originalVideoUrl,
          processedUrl: processed.url,
          userId
        });

        updatedItems[index] = {
          ...updatedItems[index],
          url: processed.url,
          videoVariants: processed.videoVariants || null,
          hlsMasterUrl: processed.hlsMasterUrl || null,
          originalVideoUrl: originalDeleted ? null : originalVideoUrl,
          videoFileSize: processed.fileSize,
          videoProcessingStatus: 'ready',
          originalVideoDeletedAt: originalDeleted ? admin.firestore.Timestamp.now() : null,
          videoProcessingError: null
        };
      } catch (error) {
        console.error(`processMomentVideos failed for ${userId}/${momentId}/${item.id}`, error);
        updatedItems[index] = {
          ...updatedItems[index],
          originalVideoUrl: item.originalVideoUrl || item.url,
          videoProcessingStatus: 'failed',
          videoProcessingError: error.message || 'Video processing failed'
        };
      }
    }

    const finalLegacyFields = buildLegacyMomentMediaFields(updatedItems);
    await momentRef.update({
      mediaItems: updatedItems,
      ...finalLegacyFields,
      videoProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
  }
);

const processStoryVideos = onDocumentCreated(
  {
    document: 'users/{userId}/stories/{storyId}',
    memory: '2GiB',
    timeoutSeconds: 540,
    concurrency: 1,
    retry: false
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const { userId, storyId } = event.params;
    const storyRef = snap.ref;
    const data = snap.data() || {};
    const mediaItem = data.mediaItem || {};

    if (
      mediaItem.type !== 'video' ||
      mediaItem.videoProcessingStatus !== 'pending' ||
      !mediaItem.url
    ) {
      return;
    }

    const originalVideoUrl = mediaItem.originalVideoUrl || mediaItem.url;

    await storyRef.update({
      'mediaItem.originalVideoUrl': originalVideoUrl,
      'mediaItem.videoProcessingStatus': 'processing',
      videoProcessingStatus: 'processing',
      videoProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    try {
      const processed = await transcodeStoryVideo({
        userId,
        uploadId: storyId,
        segmentId: mediaItem.id || 'single',
        temporaryUrl: originalVideoUrl
      });

      const originalDeleted = await deleteStorageUrlIfSafe({
        url: originalVideoUrl,
        userId
      });

      await storyRef.update({
        'mediaItem.url': processed.url,
        'mediaItem.originalVideoUrl': originalDeleted ? null : originalVideoUrl,
        'mediaItem.videoFileSize': processed.fileSize,
        'mediaItem.videoProcessingStatus': 'ready',
        'mediaItem.originalVideoDeletedAt': originalDeleted ? admin.firestore.Timestamp.now() : null,
        'mediaItem.videoProcessingError': null,
        videoUrl: processed.url,
        videoFileSize: processed.fileSize,
        videoProcessingStatus: 'ready',
        videoProcessingError: null,
        videoProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } catch (error) {
      console.error(`processStoryVideos failed for ${userId}/${storyId}`, error);
      await storyRef.update({
        'mediaItem.originalVideoUrl': originalVideoUrl,
        'mediaItem.videoProcessingStatus': 'failed',
        'mediaItem.videoProcessingError': error.message || 'Story video processing failed',
        videoProcessingStatus: 'failed',
        videoProcessingError: error.message || 'Story video processing failed',
        videoProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }
  }
);

module.exports = {
  permanentlyDeleteRecentlyDeletedBatch,
  cleanExpiredRecentlyDeleted,
  processMomentVideos,
  processStoryVideos,
};
