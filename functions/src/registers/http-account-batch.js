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
  addMediaFilesToZip,
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
  buildExportZipBuffer,
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
  collectMediaUrlsFromPayload,
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

const deleteMyCommentsBatch = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 20
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
    const rawItems = Array.isArray(body.comments) ? body.comments : [];
    const trimmed = rawItems.slice(0, 50);
    const db = admin.firestore();

    try {
      // Deduplicate and validate payload
      const uniqueMap = new Map();
      for (const item of trimmed) {
        const authorId = typeof item?.authorId === 'string' ? item.authorId.trim() : '';
        const momentId = typeof item?.momentId === 'string' ? item.momentId.trim() : '';
        const commentId = typeof item?.commentId === 'string' ? item.commentId.trim() : '';
        if (!authorId || !momentId || !commentId) continue;
        const key = `${authorId}_${momentId}_${commentId}`;
        if (!uniqueMap.has(key)) {
          uniqueMap.set(key, { authorId, momentId, commentId });
        }
      }

      const targets = [...uniqueMap.values()];
      if (targets.length === 0) {
        res.status(200).json({ deleted: 0, skipped: 0, cascadedReplies: 0 });
        return;
      }

      // Verify ownership of root comments before deleting.
      let skipped = 0;
      const ownedTargets = [];
      for (const target of targets) {
        const ref = db.doc(`users/${target.authorId}/moments/${target.momentId}/comments/${target.commentId}`);
        const snap = await ref.get();
        if (!snap.exists) {
          skipped += 1;
          continue;
        }
        const data = snap.data() || {};
        if (data.authorId !== uid) {
          skipped += 1;
          continue;
        }
        ownedTargets.push(target);
      }

      if (ownedTargets.length === 0) {
        res.status(200).json({ deleted: 0, skipped, cascadedReplies: 0 });
        return;
      }

      const refsToDelete = new Map(); // path -> DocumentReference
      const decrementByMomentPath = new Map(); // momentPath -> count
      let cascadedReplies = 0;

      for (const target of ownedTargets) {
        const commentPath = `users/${target.authorId}/moments/${target.momentId}/comments/${target.commentId}`;
        refsToDelete.set(commentPath, db.doc(commentPath));

        const momentPath = `users/${target.authorId}/moments/${target.momentId}`;
        decrementByMomentPath.set(momentPath, (decrementByMomentPath.get(momentPath) || 0) + 1);

        const repliesSnap = await db
          .collection(`users/${target.authorId}/moments/${target.momentId}/comments`)
          .where('parentCommentId', '==', target.commentId)
          .get();

        for (const replyDoc of repliesSnap.docs) {
          if (!refsToDelete.has(replyDoc.ref.path)) {
            refsToDelete.set(replyDoc.ref.path, replyDoc.ref);
            decrementByMomentPath.set(momentPath, (decrementByMomentPath.get(momentPath) || 0) + 1);
            cascadedReplies += 1;
          }
        }
      }

      // Commit in chunks to stay below Firestore batch limits.
      let batch = db.batch();
      let ops = 0;
      let commits = 0;

      const flushBatch = async () => {
        if (ops === 0) return;
        await batch.commit();
        commits += 1;
        batch = db.batch();
        ops = 0;
      };

      for (const ref of refsToDelete.values()) {
        if (ops >= 420) await flushBatch();
        batch.delete(ref);
        ops += 1;
      }

      for (const [momentPath, count] of decrementByMomentPath.entries()) {
        if (ops >= 420) await flushBatch();
        batch.update(db.doc(momentPath), {
          commentCount: admin.firestore.FieldValue.increment(-count)
        });
        ops += 1;
      }

      await flushBatch();

      const deleted = refsToDelete.size;
      console.log(`✅ deleteMyCommentsBatch: uid=${uid}, deleted=${deleted}, skipped=${skipped}, cascadedReplies=${cascadedReplies}, commits=${commits}`);
      res.status(200).json({ deleted, skipped, cascadedReplies });

    } catch (error) {
      console.error('❌ deleteMyCommentsBatch error:', error);
      res.status(500).json({ error: 'Delete comments batch failed', details: error.message });
    }
  }
);

/**
 * 🏷️ removeMyTagsBatch — Removes the viewer from tagged moments in batch.
 *
 * POST body: { moments: [{ authorId, momentId }] }
 */
const removeMyTagsBatch = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 20
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
    const rawMoments = Array.isArray(body.moments) ? body.moments : [];
    if (rawMoments.length === 0) {
      res.status(400).json({ error: 'No moments provided' });
      return;
    }

    const targets = rawMoments
      .map((item) => ({
        authorId: typeof item?.authorId === 'string' ? item.authorId.trim() : '',
        momentId: typeof item?.momentId === 'string' ? item.momentId.trim() : ''
      }))
      .filter((item) => item.authorId && item.momentId);

    if (targets.length === 0) {
      res.status(400).json({ error: 'Invalid moments payload' });
      return;
    }

    const db = admin.firestore();
    let updated = 0;
    let skipped = 0;

    try {
      for (let i = 0; i < targets.length; i += 100) {
        const chunk = targets.slice(i, i + 100);
        if (chunk.length === 0) continue;

        const refs = chunk.map((target) => db.doc(`users/${target.authorId}/moments/${target.momentId}`));
        const docs = await db.getAll(...refs);
        const batch = db.batch();

        for (let j = 0; j < docs.length; j += 1) {
          const doc = docs[j];
          if (!doc.exists) {
            skipped += 1;
            continue;
          }

          const data = doc.data() || {};
          const taggedUsers = Array.isArray(data.taggedUsers) ? data.taggedUsers : [];
          if (!taggedUsers.includes(uid)) {
            skipped += 1;
            continue;
          }

          const nextTaggedUsers = taggedUsers.filter((id) => id !== uid);

          // Best effort: also remove tag entries in mediaItems.tags where userId/taggedUserId == uid.
          const mediaItems = Array.isArray(data.mediaItems) ? data.mediaItems : [];
          const nextMediaItems = mediaItems.map((mediaItem) => {
            if (!mediaItem || typeof mediaItem !== 'object') return mediaItem;
            const mediaTags = Array.isArray(mediaItem.tags) ? mediaItem.tags : null;
            if (!mediaTags) return mediaItem;
            const filteredTags = mediaTags.filter((tag) => {
              if (!tag || typeof tag !== 'object') return true;
              const tagUserId = typeof tag.userId === 'string' ? tag.userId : '';
              const taggedUserId = typeof tag.taggedUserId === 'string' ? tag.taggedUserId : '';
              return tagUserId !== uid && taggedUserId !== uid;
            });
            return {
              ...mediaItem,
              tags: filteredTags
            };
          });

          batch.update(doc.ref, {
            taggedUsers: nextTaggedUsers,
            mediaItems: nextMediaItems
          });
          updated += 1;
        }

        await batch.commit();
      }

      console.log(`✅ removeMyTagsBatch: uid=${uid}, updated=${updated}, skipped=${skipped}`);
      res.status(200).json({ updated, skipped });
    } catch (error) {
      console.error('❌ removeMyTagsBatch error:', error);
      res.status(500).json({ error: 'Remove tags batch failed', details: error.message });
    }
  }
);

/**
 * ❤️ removeSharedReactionsBatch — Removes shared reactions in either direction.
 *
 * POST body: { otherUserId, direction, reactions: [{ authorId, momentId }] }
 */
const removeSharedReactionsBatch = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 20
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
    const otherUserId = typeof body.otherUserId === 'string' ? body.otherUserId.trim() : '';
    const direction = body.direction === 'other_on_viewer' ? 'other_on_viewer' : 'viewer_on_other';
    const rawReactions = Array.isArray(body.reactions) ? body.reactions : [];
    const trimmed = rawReactions.slice(0, 80);

    if (!otherUserId || otherUserId === uid) {
      res.status(400).json({ error: 'Invalid otherUserId' });
      return;
    }

    const expectedMomentAuthorId = direction === 'viewer_on_other' ? otherUserId : uid;
    const expectedReactorId = direction === 'viewer_on_other' ? uid : otherUserId;
    const db = admin.firestore();

    try {
      const unique = new Map();
      for (const item of trimmed) {
        const authorId = typeof item?.authorId === 'string' ? item.authorId.trim() : '';
        const momentId = typeof item?.momentId === 'string' ? item.momentId.trim() : '';
        if (!authorId || !momentId) continue;
        if (authorId !== expectedMomentAuthorId) continue;
        const key = `${authorId}_${momentId}`;
        if (!unique.has(key)) {
          unique.set(key, { authorId, momentId });
        }
      }

      const targets = [...unique.values()];
      if (targets.length === 0) {
        res.status(200).json({ deleted: 0, skipped: 0 });
        return;
      }

      const batch = db.batch();
      let deleted = 0;
      let skipped = 0;

      for (const target of targets) {
        const ref = db.doc(`users/${target.authorId}/moments/${target.momentId}/reactions/${expectedReactorId}`);
        const snap = await ref.get();
        if (!snap.exists) {
          skipped += 1;
          continue;
        }

        const data = snap.data() || {};
        const reactionUserId = typeof data.userId === 'string' ? data.userId : expectedReactorId;
        if (reactionUserId !== expectedReactorId) {
          skipped += 1;
          continue;
        }

        batch.delete(ref);
        deleted += 1;
      }

      if (deleted > 0) {
        await batch.commit();
      }

      console.log(`✅ removeSharedReactionsBatch: uid=${uid}, otherUserId=${otherUserId}, direction=${direction}, deleted=${deleted}, skipped=${skipped}`);
      res.status(200).json({ deleted, skipped });
    } catch (error) {
      console.error('❌ removeSharedReactionsBatch error:', error);
      res.status(500).json({ error: 'Remove shared reactions batch failed', details: error.message });
    }
  }
);

/**
 * 💬 deleteSharedCommentsBatch — Deletes shared comments in either direction.
 *
 * POST body: { otherUserId, direction, comments: [{ authorId, momentId, commentId }] }
 */
const deleteSharedCommentsBatch = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 20
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
    const otherUserId = typeof body.otherUserId === 'string' ? body.otherUserId.trim() : '';
    const direction = body.direction === 'other_on_viewer' ? 'other_on_viewer' : 'viewer_on_other';
    const rawComments = Array.isArray(body.comments) ? body.comments : [];
    const trimmed = rawComments.slice(0, 50);

    if (!otherUserId || otherUserId === uid) {
      res.status(400).json({ error: 'Invalid otherUserId' });
      return;
    }

    const expectedMomentAuthorId = direction === 'viewer_on_other' ? otherUserId : uid;
    const expectedCommentAuthorId = direction === 'viewer_on_other' ? uid : otherUserId;
    const db = admin.firestore();

    try {
      const unique = new Map();
      for (const item of trimmed) {
        const authorId = typeof item?.authorId === 'string' ? item.authorId.trim() : '';
        const momentId = typeof item?.momentId === 'string' ? item.momentId.trim() : '';
        const commentId = typeof item?.commentId === 'string' ? item.commentId.trim() : '';
        if (!authorId || !momentId || !commentId) continue;
        if (authorId !== expectedMomentAuthorId) continue;
        const key = `${authorId}_${momentId}_${commentId}`;
        if (!unique.has(key)) {
          unique.set(key, { authorId, momentId, commentId });
        }
      }

      const targets = [...unique.values()];
      if (targets.length === 0) {
        res.status(200).json({ deleted: 0, skipped: 0, cascadedReplies: 0 });
        return;
      }

      let skipped = 0;
      const allowedTargets = [];
      for (const target of targets) {
        const ref = db.doc(`users/${target.authorId}/moments/${target.momentId}/comments/${target.commentId}`);
        const snap = await ref.get();
        if (!snap.exists) {
          skipped += 1;
          continue;
        }

        const data = snap.data() || {};
        const commentAuthorId = typeof data.authorId === 'string' ? data.authorId : '';
        if (commentAuthorId !== expectedCommentAuthorId) {
          skipped += 1;
          continue;
        }

        allowedTargets.push(target);
      }

      if (allowedTargets.length === 0) {
        res.status(200).json({ deleted: 0, skipped, cascadedReplies: 0 });
        return;
      }

      const refsToDelete = new Map();
      const decrementByMomentPath = new Map();
      let cascadedReplies = 0;

      for (const target of allowedTargets) {
        const commentPath = `users/${target.authorId}/moments/${target.momentId}/comments/${target.commentId}`;
        refsToDelete.set(commentPath, db.doc(commentPath));

        const momentPath = `users/${target.authorId}/moments/${target.momentId}`;
        decrementByMomentPath.set(momentPath, (decrementByMomentPath.get(momentPath) || 0) + 1);

        const repliesSnap = await db
          .collection(`users/${target.authorId}/moments/${target.momentId}/comments`)
          .where('parentCommentId', '==', target.commentId)
          .get();

        for (const replyDoc of repliesSnap.docs) {
          if (!refsToDelete.has(replyDoc.ref.path)) {
            refsToDelete.set(replyDoc.ref.path, replyDoc.ref);
            decrementByMomentPath.set(momentPath, (decrementByMomentPath.get(momentPath) || 0) + 1);
            cascadedReplies += 1;
          }
        }
      }

      let batch = db.batch();
      let ops = 0;

      const flushBatch = async () => {
        if (ops === 0) return;
        await batch.commit();
        batch = db.batch();
        ops = 0;
      };

      for (const ref of refsToDelete.values()) {
        if (ops >= 420) await flushBatch();
        batch.delete(ref);
        ops += 1;
      }

      for (const [momentPath, count] of decrementByMomentPath.entries()) {
        if (ops >= 420) await flushBatch();
        batch.update(db.doc(momentPath), {
          commentCount: admin.firestore.FieldValue.increment(-count)
        });
        ops += 1;
      }

      await flushBatch();

      const deleted = refsToDelete.size;
      console.log(`✅ deleteSharedCommentsBatch: uid=${uid}, otherUserId=${otherUserId}, direction=${direction}, deleted=${deleted}, skipped=${skipped}, cascadedReplies=${cascadedReplies}`);
      res.status(200).json({ deleted, skipped, cascadedReplies });
    } catch (error) {
      console.error('❌ deleteSharedCommentsBatch error:', error);
      res.status(500).json({ error: 'Delete shared comments batch failed', details: error.message });
    }
  }
);

/**
 * 🏷️ removeSharedTagsBatch — Removes shared tags in either direction.
 *
 * POST body: { otherUserId, direction, moments: [{ authorId, momentId }] }
 */
const removeSharedTagsBatch = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 20
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
    const otherUserId = typeof body.otherUserId === 'string' ? body.otherUserId.trim() : '';
    const direction = body.direction === 'other_on_viewer' ? 'other_on_viewer' : 'viewer_on_other';
    const rawMoments = Array.isArray(body.moments) ? body.moments : [];

    if (!otherUserId || otherUserId === uid) {
      res.status(400).json({ error: 'Invalid otherUserId' });
      return;
    }

    const expectedAuthorId = direction === 'viewer_on_other' ? uid : otherUserId;
    const taggedUserIdToRemove = direction === 'viewer_on_other' ? otherUserId : uid;

    const targets = rawMoments
      .slice(0, 80)
      .map((item) => ({
        authorId: typeof item?.authorId === 'string' ? item.authorId.trim() : '',
        momentId: typeof item?.momentId === 'string' ? item.momentId.trim() : ''
      }))
      .filter((item) => item.authorId && item.momentId && item.authorId === expectedAuthorId);

    if (targets.length === 0) {
      res.status(200).json({ updated: 0, skipped: 0 });
      return;
    }

    const db = admin.firestore();
    let updated = 0;
    let skipped = 0;

    try {
      for (let i = 0; i < targets.length; i += 100) {
        const chunk = targets.slice(i, i + 100);
        const refs = chunk.map((target) => db.doc(`users/${target.authorId}/moments/${target.momentId}`));
        const docs = await db.getAll(...refs);
        const batch = db.batch();
        let chunkUpdated = 0;

        for (const doc of docs) {
          if (!doc.exists) {
            skipped += 1;
            continue;
          }

          const data = doc.data() || {};
          const taggedUsers = Array.isArray(data.taggedUsers) ? data.taggedUsers : [];
          if (!taggedUsers.includes(taggedUserIdToRemove)) {
            skipped += 1;
            continue;
          }

          const nextTaggedUsers = taggedUsers.filter((id) => id !== taggedUserIdToRemove);
          const mediaItems = Array.isArray(data.mediaItems) ? data.mediaItems : [];
          const nextMediaItems = mediaItems.map((mediaItem) => {
            if (!mediaItem || typeof mediaItem !== 'object') return mediaItem;
            const mediaTags = Array.isArray(mediaItem.tags) ? mediaItem.tags : null;
            if (!mediaTags) return mediaItem;

            const filteredTags = mediaTags.filter((tag) => {
              if (!tag || typeof tag !== 'object') return true;
              const tagUserId = typeof tag.userId === 'string' ? tag.userId : '';
              const taggedUserId = typeof tag.taggedUserId === 'string' ? tag.taggedUserId : '';
              return tagUserId !== taggedUserIdToRemove && taggedUserId !== taggedUserIdToRemove;
            });

            return {
              ...mediaItem,
              tags: filteredTags
            };
          });

          batch.update(doc.ref, {
            taggedUsers: nextTaggedUsers,
            mediaItems: nextMediaItems
          });
          updated += 1;
          chunkUpdated += 1;
        }

        if (chunkUpdated > 0) {
          await batch.commit();
        }
      }

      console.log(`✅ removeSharedTagsBatch: uid=${uid}, otherUserId=${otherUserId}, direction=${direction}, updated=${updated}, skipped=${skipped}`);
      res.status(200).json({ updated, skipped });
    } catch (error) {
      console.error('❌ removeSharedTagsBatch error:', error);
      res.status(500).json({ error: 'Remove shared tags batch failed', details: error.message });
    }
  }
);

/**
 * 🧹 removeMyStickerRepliesBatch — Deletes viewer's sticker replies (poll votes + question replies).
 *
 * POST body: { replies: [{ kind: "poll"|"question", authorId, storyId, sourceId? }] }
 */
const removeMyStickerRepliesBatch = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 20
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
    const rawReplies = Array.isArray(body.replies) ? body.replies : [];
    const trimmed = rawReplies.slice(0, 80);
    const db = admin.firestore();

    try {
      const unique = new Map();
      for (const item of trimmed) {
        const kind = typeof item?.kind === 'string' ? item.kind.trim().toLowerCase() : '';
        const authorId = typeof item?.authorId === 'string' ? item.authorId.trim() : '';
        const storyId = typeof item?.storyId === 'string' ? item.storyId.trim() : '';
        const sourceId = typeof item?.sourceId === 'string' ? item.sourceId.trim() : '';
        if (!kind || !authorId || !storyId) continue;
        if (kind !== 'poll' && kind !== 'question') continue;
        const key = `${kind}_${authorId}_${storyId}_${sourceId}`;
        if (!unique.has(key)) {
          unique.set(key, { kind, authorId, storyId, sourceId });
        }
      }

      const targets = [...unique.values()];
      if (targets.length === 0) {
        res.status(200).json({ deleted: 0, skipped: 0 });
        return;
      }

      const batch = db.batch();
      let deleted = 0;
      let skipped = 0;

      for (const target of targets) {
        if (target.kind === 'poll') {
          const ref = db.doc(`users/${target.authorId}/stories/${target.storyId}/pollVotes/${uid}`);
          const snap = await ref.get();
          if (!snap.exists) {
            skipped += 1;
            continue;
          }
          const data = snap.data() || {};
          if (data.userId !== uid) {
            skipped += 1;
            continue;
          }
          batch.delete(ref);
          deleted += 1;
          continue;
        }

        if (target.kind === 'question') {
          if (!target.sourceId) {
            skipped += 1;
            continue;
          }
          const ref = db.doc(`users/${target.authorId}/stories/${target.storyId}/questionResponses/${target.sourceId}`);
          const snap = await ref.get();
          if (!snap.exists) {
            skipped += 1;
            continue;
          }
          const data = snap.data() || {};
          if (data.userId !== uid) {
            skipped += 1;
            continue;
          }
          batch.delete(ref);
          deleted += 1;
        }
      }

      if (deleted > 0) {
        await batch.commit();
      }

      console.log(`✅ removeMyStickerRepliesBatch: uid=${uid}, deleted=${deleted}, skipped=${skipped}`);
      res.status(200).json({ deleted, skipped });
    } catch (error) {
      console.error('❌ removeMyStickerRepliesBatch error:', error);
      res.status(500).json({ error: 'Remove sticker replies batch failed', details: error.message });
    }
  }
);

// ============================================================================
// MARK: - WebAuthn / Passkeys (FIDO2) Endpoints
// ============================================================================

const rpName = 'Moments';
const rpID = 'momentsapp.app';
const expectedOrigin = [ `https://${rpID}`, rpID ]; // iOS uses rpID as origin or https://rpID

function isExpiredPasskeyChallenge(data) {
  if (!data?.expiresAt || typeof data.expiresAt.toMillis !== 'function') {
    return true;
  }
  return data.expiresAt.toMillis() <= Date.now();
}

const passkeyRegisterChallenge = onRequest({ timeoutSeconds: 30 }, async (req, res) => {
  setProxyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).send('');

  const uid = await verifyFirebaseAuth(req, res);
  if (!uid) return;

  try {
    const { generateRegistrationOptions } = require('@simplewebauthn/server');
    const userSnap = await admin.firestore().collection('users').doc(uid).get();
    const userData = userSnap.data() || {};
    const username = userData.username || uid;

    // Obtener passkeys existentes
    const passkeysSnap = await admin.firestore().collection('users').doc(uid).collection('passkeys').get();
    const existingPasskeys = passkeysSnap.docs.map(doc => {
      const data = doc.data();
      return {
        id: Buffer.from(data.id, 'base64url'),
        type: 'public-key',
      };
    });

    const options = await generateRegistrationOptions({
      rpName,
      rpID,
      userID: Buffer.from(uid),
      userName: username,
      excludeCredentials: existingPasskeys,
      authenticatorSelection: {
        residentKey: 'required',
        userVerification: 'required',
      },
    });

    // Guardar challenge en Firestore (expira en 5 mins)
    await admin.firestore().collection('passkeyChallenges').doc(uid).set({
      challenge: options.challenge,
      type: 'registration',
      expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 5 * 60 * 1000)),
    });

    res.status(200).json(options);
  } catch (error) {
    console.error('passkeyRegisterChallenge error:', error);
    res.status(500).json({ error: 'Failed to generate challenge' });
  }
});

const passkeyRegisterVerify = onRequest({ timeoutSeconds: 30 }, async (req, res) => {
  setProxyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).send('');

  const uid = await verifyFirebaseAuth(req, res);
  if (!uid) return;

  try {
    const { verifyRegistrationResponse } = require('@simplewebauthn/server');
    const body = parseJsonBody(req);

    const challengeRef = admin.firestore().collection('passkeyChallenges').doc(uid);
    const challengeDoc = await challengeRef.get();
    if (!challengeDoc.exists) {
      return res.status(400).json({ error: 'Challenge expired or not found' });
    }
    const challengeData = challengeDoc.data();
    if (isExpiredPasskeyChallenge(challengeData)) {
      await challengeRef.delete();
      return res.status(400).json({ error: 'Challenge expired or not found' });
    }
    const { challenge } = challengeData;

    // Eliminar challenge usado
    await challengeRef.delete();

    const verification = await verifyRegistrationResponse({
      response: body,
      expectedChallenge: challenge,
      expectedOrigin,
      expectedRPID: rpID,
      requireUserVerification: true,
    });

    if (verification.verified && verification.registrationInfo) {
      const { credential, credentialDeviceType, credentialBackedUp } = verification.registrationInfo;
      const { id, publicKey, counter } = credential;

      // Guardar Passkey en Firestore
      const passkeyIdStr = id; // Ya es un string base64url en v10+
      await admin.firestore().collection('users').doc(uid).collection('passkeys').doc(passkeyIdStr).set({
        id: passkeyIdStr,
        publicKey: Buffer.from(publicKey).toString('base64'),
        counter,
        deviceType: credentialDeviceType,
        backedUp: credentialBackedUp,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      res.status(200).json({ success: true });
    } else {
      res.status(400).json({ error: 'Verification failed' });
    }
  } catch (error) {
    console.error('passkeyRegisterVerify error:', error);
    res.status(500).json({ error: 'Failed to verify registration', details: error.message });
  }
});

const passkeyLoginChallenge = onRequest({ timeoutSeconds: 30 }, async (req, res) => {
  setProxyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).send('');

  // Login challenge es público, no requiere Firebase Auth previo
  try {
    const { generateAuthenticationOptions } = require('@simplewebauthn/server');

    const options = await generateAuthenticationOptions({
      rpID,
      userVerification: 'required',
    });

    // Guardar challenge con el propio ID del challenge (ya que no sabemos el uid aún)
    await admin.firestore().collection('passkeyChallenges').doc(options.challenge).set({
      challenge: options.challenge,
      type: 'login',
      expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 5 * 60 * 1000)),
    });

    res.status(200).json(options);
  } catch (error) {
    console.error('passkeyLoginChallenge error:', error);
    res.status(500).json({ error: 'Failed to generate authentication challenge' });
  }
});

const passkeyLoginVerify = onRequest({ timeoutSeconds: 30 }, async (req, res) => {
  setProxyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).send('');

  try {
    const { verifyAuthenticationResponse } = require('@simplewebauthn/server');
    const body = parseJsonBody(req);

    // El frontend debe enviar el challenge usado en el body para que podamos buscarlo
    const clientChallenge = body.clientExtensionResults?.challenge || body.originalChallenge;
    if (!clientChallenge) {
       return res.status(400).json({ error: 'Missing originalChallenge in request' });
    }

    const challengeRef = admin.firestore().collection('passkeyChallenges').doc(clientChallenge);
    const challengeDoc = await challengeRef.get();
    if (!challengeDoc.exists) {
      return res.status(400).json({ error: 'Challenge expired or not found' });
    }
    const challengeData = challengeDoc.data();
    if (isExpiredPasskeyChallenge(challengeData)) {
      await challengeRef.delete();
      return res.status(400).json({ error: 'Challenge expired or not found' });
    }
    const { challenge } = challengeData;
    await challengeRef.delete();

    const passkeyIdStr = body.id;
    let passkeyDoc;

    // Si tenemos el userHandle (uid base64url), podemos buscar directamente sin collectionGroup
    if (body.response.userHandle) {
      const uidFromHandle = Buffer.from(body.response.userHandle, 'base64url').toString('utf8');
      passkeyDoc = await admin.firestore().collection('users').doc(uidFromHandle).collection('passkeys').doc(passkeyIdStr).get();
    }

    if (!passkeyDoc || !passkeyDoc.exists) {
      // Fallback a Collection Group por si acaso (ahora tiene índice)
      const passkeysSnap = await admin.firestore().collectionGroup('passkeys').where('id', '==', passkeyIdStr).get();
      if (passkeysSnap.empty) {
        return res.status(404).json({ error: 'Passkey not found in our records' });
      }
      passkeyDoc = passkeysSnap.docs[0];
    }

    const passkeyData = passkeyDoc.data();

    // El path es users/{uid}/passkeys/{passkeyId}
    const uid = passkeyDoc.ref.parent.parent.id;

    const verification = await verifyAuthenticationResponse({
      response: body,
      expectedChallenge: challenge,
      expectedOrigin,
      expectedRPID: rpID,
      credential: {
        id: passkeyData.id,
        publicKey: new Uint8Array(Buffer.from(passkeyData.publicKey, 'base64')),
        counter: passkeyData.counter,
        transports: passkeyData.transports || [],
      },
      requireUserVerification: true,
    });

    if (verification.verified) {
      const { newCounter } = verification.authenticationInfo;
      // Actualizar counter
      await passkeyDoc.ref.update({ counter: newCounter });

      // Generar Custom Token de Firebase Auth
      const customToken = await admin.auth().createCustomToken(uid);

      res.status(200).json({ customToken });
    } else {
      res.status(400).json({ error: 'Verification failed' });
    }
  } catch (error) {
    console.error('passkeyLoginVerify error:', error);
    res.status(500).json({ error: 'Failed to verify login', details: error.message });
  }
});

// Cuentas Auth sin documento users/{uid} tras 30 días (registros abandonados).

module.exports = {
  deleteMyCommentsBatch,
  removeMyTagsBatch,
  removeSharedReactionsBatch,
  deleteSharedCommentsBatch,
  removeSharedTagsBatch,
  removeMyStickerRepliesBatch,
  passkeyRegisterChallenge,
  passkeyRegisterVerify,
  passkeyLoginChallenge,
  passkeyLoginVerify,
};
