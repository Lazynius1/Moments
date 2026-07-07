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

const getFeedPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const feedType = body.feedType === 'forYou' ? 'forYou' : 'following';
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 40)) : 20;
    const cursor = body.cursor || null; // { timestamp, momentId, authorId?, globalStream*? }
    const globalStreamCursor = cursor && cursor.globalStreamTimestamp && cursor.globalStreamMomentId && cursor.globalStreamAuthorId
      ? {
        timestamp: cursor.globalStreamTimestamp,
        momentId: cursor.globalStreamMomentId,
        authorId: cursor.globalStreamAuthorId
      }
      : (body.globalStreamCursor || null);

    const db = admin.firestore();

    try {
      // ── 1. Build viewer context ──
      const viewerCtx = await buildViewerContext(uid);

      if (feedType === 'forYou') {
        const forYouResult = await processForYouFeedPage({
          db,
          uid,
          viewerCtx,
          cursor,
          globalStreamCursor,
          limit
        });

        res.status(200).json({
          moments: forYouResult.moments,
          nextCursor: forYouResult.nextCursor,
          source: 'backend',
          totalCandidates: forYouResult.totalCandidates
        });
        return;
      }

      // ── 2. Following: candidate user IDs ──
      let candidateUserIds = [...viewerCtx.following];
      if (!candidateUserIds.includes(uid)) {
        candidateUserIds.push(uid);
      }

      if (candidateUserIds.length === 0) {
        res.status(200).json({ moments: [], nextCursor: null, source: 'backend', totalCandidates: 0 });
        return;
      }

      // ── 3. Fetch candidate moments (batched by 10 using collectionGroup) ──
      const fetchLimit = 80;
      const perAuthorLimit = 50;

      const userBatches = [];
      for (let i = 0; i < candidateUserIds.length; i += 10) {
        userBatches.push(candidateUserIds.slice(i, i + 10));
      }

      const allCandidateDocs = [];
      const batchFetchCounts = new Array(userBatches.length).fill(0);
      await Promise.all(userBatches.map(async (batch, batchIndex) => {
        let query = db.collectionGroup('moments')
          .where('authorId', 'in', batch)
          .orderBy('timestamp', 'desc');

        // Apply cursor: use startAt (inclusive) so we don't skip same-timestamp items.
        // The momentId-based slice below handles exact dedup.
        if (cursor && cursor.timestamp) {
          const cursorDate = new Date(cursor.timestamp);
          query = query.startAt(admin.firestore.Timestamp.fromDate(cursorDate));
        }

        query = query.limit(fetchLimit);
        const snap = await query.get();
        batchFetchCounts[batchIndex] = snap.size;
        snap.docs.forEach(doc => allCandidateDocs.push(doc));
      }));

      // Deduplicate by full ref path (prevents cross-author ID collisions)
      const seen = new Set();
      const uniqueDocs = [];
      for (const doc of allCandidateDocs) {
        const refPath = doc.ref.path;
        if (!seen.has(refPath)) {
          seen.add(refPath);
          uniqueDocs.push(doc);
        }
      }

      uniqueDocs.sort((a, b) => {
        const tsA = a.data().timestamp;
        const tsB = b.data().timestamp;
        const millisA = tsToMillis(tsA) || 0;
        const millisB = tsToMillis(tsB) || 0;
        if (millisB !== millisA) return millisB - millisA;
        return b.id.localeCompare(a.id); // stable tiebreaker
      });

      // Apply cursor momentId filter for composite cursor stability
      // Use ref.path for matching to avoid cross-author collisions
      let startIdx = 0;
      if (cursor && cursor.momentId && cursor.authorId) {
        const cursorPath = `users/${cursor.authorId}/moments/${cursor.momentId}`;
        for (let i = 0; i < uniqueDocs.length; i++) {
          if (uniqueDocs[i].ref.path === cursorPath) {
            startIdx = i + 1;
            break;
          }
        }
      } else if (cursor && cursor.momentId) {
        // Fallback for old cursors without authorId
        for (let i = 0; i < uniqueDocs.length; i++) {
          if (uniqueDocs[i].id === cursor.momentId) {
            startIdx = i + 1;
            break;
          }
        }
      }

      const candidatesAfterCursor = uniqueDocs.slice(startIdx);
      const totalCandidates = candidatesAfterCursor.length;

      // Filter out scheduled moments (only author can see scheduled)
      const now = Date.now();
      const nonScheduledCandidates = candidatesAfterCursor.filter(doc => {
        const data = doc.data();
        if (!isMomentPathAuthorConsistent(doc, data)) return false;
        if (data.isArchived === true) return false;
        if (data.authorId === uid) return true; // author always sees own
        const schedMs = tsToMillis(data.scheduledDate);
        if (schedMs && schedMs > now) return false;
        return true;
      });

      // ── 4. Batch-load author docs for privacy checks ──
      const authorIds = [...new Set(nonScheduledCandidates.map(d => d.data().authorId))];
      const authorMap = await batchLoadAuthorDocs(authorIds);

      // ── 5. Apply privacy filter ──
      // Process in parallel but collect results in order
      const privacyResults = await Promise.all(
        nonScheduledCandidates.map(async (doc) => {
          const data = doc.data();
          if (!isMomentPathAuthorConsistent(doc, data)) return { doc, data, canView: false };
          const authorData = authorMap.get(data.authorId);
          // Fail-closed: if author doc is missing, deny access
          if (!authorData) return { doc, data, canView: false };
          const momentForCheck = {
            id: doc.id,
            authorId: data.authorId,
            audience: data.audience,
            taggedUsers: data.taggedUsers,
            customListId: data.customListId,
            isArchived: data.isArchived === true
          };
          const canView = await canViewerSeeMoment(momentForCheck, uid, viewerCtx, authorData);
          return { doc, data, canView };
        })
      );

      const visibleDocs = privacyResults.filter(r => r.canView);

      // ── 6. Per-author limit to avoid one user dominating feed ──
      const perAuthorCount = {};
      const perAuthorMax = 50;
      const finalDocs = [];
      for (const { doc, data } of visibleDocs) {
        const count = perAuthorCount[data.authorId] || 0;
        if (count >= perAuthorMax) continue;
        perAuthorCount[data.authorId] = count + 1;
        finalDocs.push({ doc, data });
        if (finalDocs.length >= limit) break;
      }

      // ── 7. Build response ──
      const moments = finalDocs.map(({ doc, data }) => serializeMoment(doc.id, data));

      let nextCursor = null;
      // Provide cursor if there are still more visible moments beyond what we returned,
      // OR if we hit fetchLimit (meaning there could be more in Firestore we haven't seen)
      const hasMoreInFirestore = batchFetchCounts.some(count => count >= fetchLimit);
      const moreVisibleThanReturned = visibleDocs.length > finalDocs.length;

      if (finalDocs.length > 0 && (moreVisibleThanReturned || hasMoreInFirestore)) {
        const lastDoc = finalDocs[finalDocs.length - 1];
        nextCursor = {
          timestamp: tsToMillis(lastDoc.data.timestamp),
          momentId: lastDoc.doc.id,
          authorId: lastDoc.data.authorId
        };
      } else if (finalDocs.length === 0 && nonScheduledCandidates.length > 0 && hasMoreInFirestore) {
        // All candidates filtered by privacy, but more may exist in Firestore.
        // Emit advance cursor from last candidate so client doesn't stop paginating.
        const lastCandidate = nonScheduledCandidates[nonScheduledCandidates.length - 1];
        const lastCandidateData = lastCandidate.data();
        nextCursor = {
          timestamp: tsToMillis(lastCandidateData.timestamp),
          momentId: lastCandidate.id,
          authorId: lastCandidateData.authorId
        };
      }

      // Safety guard: avoid returning the same cursor repeatedly (infinite pagination loops).
      if (cursor && nextCursor && isSameFeedCursor(cursor, nextCursor)) {
        console.warn(`⚠️ getFeedPage: no-op cursor detected for uid=${uid}, feed=${feedType}`);
        nextCursor = null;
      }

      console.log(`✅ getFeedPage: uid=${uid}, type=${feedType}, candidates=${totalCandidates}, visible=${visibleDocs.length}, returned=${moments.length}`);

      res.status(200).json({
        moments,
        nextCursor,
        source: 'backend',
        totalCandidates
      });

    } catch (error) {
      console.error('❌ getFeedPage error:', error);
      res.status(500).json({ error: 'Feed fetch failed', details: error.message });
    }
  }
);

function storyAudienceSupportsSeenShortcut(audience) {
  const normalized = typeof audience === 'string' && audience.trim()
    ? audience.trim()
    : 'everyone';
  return normalized === 'everyone' || normalized === 'mutuals';
}

async function fetchStoryLastSeenMap(viewerId, authorIds) {
  const db = admin.firestore();
  const uniqueIds = [...new Set(authorIds.filter((id) => typeof id === 'string' && id))];
  const result = new Map();

  for (let i = 0; i < uniqueIds.length; i += 100) {
    const chunk = uniqueIds.slice(i, i + 100);
    const refs = chunk.map((authorId) => db.doc(`users/${viewerId}/storySeen/${authorId}`));
    const docs = await db.getAll(...refs);
    docs.forEach((doc) => {
      if (!doc.exists) return;
      const millis = tsToMillis(doc.data().lastSeenAt);
      if (millis) result.set(doc.id, millis);
    });
  }

  return result;
}

async function fetchStoryViewerDocs(viewerId, stories) {
  const db = admin.firestore();
  const result = new Set();
  const refs = stories
    .filter((story) => story && story.id && story.authorId)
    .map((story) => db.doc(`users/${story.authorId}/stories/${story.id}/viewers/${viewerId}`));

  for (let i = 0; i < refs.length; i += 100) {
    const docs = await db.getAll(...refs.slice(i, i + 100));
    docs.forEach((doc) => {
      if (!doc.exists) return;
      const parts = doc.ref.path.split('/');
      if (parts.length >= 6) {
        result.add(`${parts[1]}|${parts[3]}`);
      }
    });
  }

  return result;
}

function serializeStoryTraySegment(story, viewed) {
  return {
    storyId: story.id || '',
    viewed: viewed === true,
    audience: story.audience || null,
    timestamp: tsToMillis(story.timestamp)
  };
}

function firestoreValueToJSON(value) {
  if (value == null) return null;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (Buffer.isBuffer(value)) return value.toString('base64');
  if (value instanceof Uint8Array) return Buffer.from(value).toString('base64');
  if (value instanceof admin.firestore.GeoPoint) {
    return { latitude: value.latitude, longitude: value.longitude };
  }
  if (Array.isArray(value)) return value.map(firestoreValueToJSON);
  if (typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      out[k] = firestoreValueToJSON(v);
    }
    return out;
  }
  return value;
}

// Passes through all Firestore story fields (including live text overlay metadata:
// textOverlayLive, textPositionNormX/Y, textColorHex, textMotion, textVisualEffect, etc.)
function serializeStoryDocument(doc) {
  const data = doc.data() || {};
  return {
    id: doc.id,
    ...firestoreValueToJSON(data)
  };
}

async function preloadCustomStoryAllowanceMap(customStories, viewerId, db) {
  const allowance = new Map();
  if (!customStories.length) return allowance;

  const refs = [];
  const refByPath = new Map();
  const refRequests = new Map();
  const stateByKey = new Map();
  const addRefRequest = (ref, request) => {
    if (!refByPath.has(ref.path)) {
      refs.push(ref);
      refByPath.set(ref.path, ref);
    }
    if (!refRequests.has(ref.path)) {
      refRequests.set(ref.path, []);
    }
    refRequests.get(ref.path).push(request);
  };

  for (const story of customStories) {
    if (!story.id || !story.authorId) continue;
    const key = `${story.authorId}|${story.id}`;
    if (!stateByKey.has(key)) {
      stateByKey.set(key, { primaryExists: false, primaryAllowed: false, legacyAllowed: false });
    }

    addRefRequest(db.doc(`users/${story.authorId}/customAudiences/story_${story.id}`), {
      key,
      scope: 'primary'
    });
    addRefRequest(db.doc(`users/${story.authorId}/customAudiences/default_story`), {
      key,
      scope: 'legacy'
    });
  }

  for (let i = 0; i < refs.length; i += 100) {
    const docs = await db.getAll(...refs.slice(i, i + 100));
    docs.forEach((doc) => {
      const requests = refRequests.get(doc.ref.path) || [];
      if (!requests.length || !doc.exists) return;

      const allowedUsers = doc.data().allowedUsers || [];
      const includesViewer = allowedUsers.includes(viewerId);
      requests.forEach(({ key, scope }) => {
        const state = stateByKey.get(key);
        if (!state) return;
        if (scope === 'primary') {
          state.primaryExists = true;
          state.primaryAllowed = includesViewer;
        } else {
          state.legacyAllowed = includesViewer;
        }
      });
    });
  }

  stateByKey.forEach((state, key) => {
    // Match canViewerSeeStory: a story-specific audience overrides default_story.
    if (state.primaryExists) {
      allowance.set(key, state.primaryAllowed);
    } else if (state.legacyAllowed) {
      allowance.set(key, true);
    }
  });

  return allowance;
}

async function canViewerSeeStoryOptimized(story, viewerId, viewerCtx, authorData, customAllowanceMap) {
  if (!story || typeof story.authorId !== 'string' || !story.authorId) return false;
  if (story.authorId === viewerId) return true;

  if (viewerCtx.mutedUsers && viewerCtx.mutedUsers.has(story.authorId)) return false;
  if (authorData.isActive === false) return false;

  const authorBlocked = Array.isArray(authorData.blockedUsers) ? authorData.blockedUsers : [];
  if (viewerCtx.blockedUsers.has(story.authorId) || authorBlocked.includes(viewerId)) {
    return false;
  }

  const visSettings = authorData.contentVisibilitySettings || {};
  const hiddenFrom = Array.isArray(visSettings.hiddenFromUsers) ? visSettings.hiddenFromUsers : [];
  if (hiddenFrom.includes(viewerId)) return false;

  const audience = story.audience || 'everyone';
  switch (audience) {
    case 'everyone': {
      const isPrivate = authorData.isPrivate === true;
      if (!isPrivate) return true;
      return viewerCtx.following.has(story.authorId);
    }
    case 'mutuals':
      return viewerCtx.following.has(story.authorId) && viewerCtx.followers.has(story.authorId);
    case 'bestFriends': {
      const authorBestFriends = Array.isArray(authorData.bestFriends) ? authorData.bestFriends : [];
      return authorBestFriends.includes(viewerId);
    }
    case 'custom': {
      if (!story.id) return false;
      const key = `${story.authorId}|${story.id}`;
      if (customAllowanceMap && customAllowanceMap.has(key)) {
        return customAllowanceMap.get(key) === true;
      }
      return canViewerSeeStory(story, viewerId, viewerCtx, authorData);
    }
    case 'customList': {
      const listId = story.customListId;
      if (!listId) return false;
      try {
        const db = admin.firestore();
        const listDoc = await db.doc(`users/${story.authorId}/customAudienceLists/${listId}`).get();
        if (!listDoc.exists) return false;
        const members = listDoc.data().members || [];
        return members.includes(viewerId);
      } catch {
        return false;
      }
    }
    case 'onlyMe':
      return false;
    default:
      return false;
  }
}

async function fetchActiveStoryDocsForAuthors(db, authorIds, now) {
  const uniqueDocsByPath = new Map();
  const batches = [];
  for (let i = 0; i < authorIds.length; i += 10) {
    batches.push(authorIds.slice(i, i + 10));
  }

  await Promise.all(batches.map(async (batch) => {
    if (!batch.length) return;
    const snap = await db.collectionGroup('stories')
      .where('authorId', 'in', batch)
      .where('expirationDate', '>', now)
      .limit(500)
      .get();
    snap.docs.forEach((doc) => uniqueDocsByPath.set(doc.ref.path, doc));
  }));

  return [...uniqueDocsByPath.values()]
    .map((doc) => ({ doc, data: doc.data() || {} }))
    .filter(({ doc, data }) => isStoryPathAuthorConsistent(doc, data))
    .sort((a, b) => {
      const tsA = tsToMillis(a.data.timestamp) || 0;
      const tsB = tsToMillis(b.data.timestamp) || 0;
      if (tsA !== tsB) return tsA - tsB;
      return a.doc.id.localeCompare(b.doc.id);
    });
}

async function buildVisibleStoryRecords(uid, normalizedDocs, authorMap, viewerCtx) {
  const customCandidates = normalizedDocs.map(({ doc, data }) => ({
    id: doc.id,
    authorId: data.authorId,
    audience: data.audience
  })).filter((s) => s.audience === 'custom');

  const db = admin.firestore();
  const customAllowanceMap = await preloadCustomStoryAllowanceMap(customCandidates, uid, db);

  const visibilityResults = await Promise.all(
    normalizedDocs.map(async ({ doc, data }) => {
      const authorData = authorMap.get(data.authorId);
      if (!authorData) return null;

      const storyForCheck = {
        id: doc.id,
        authorId: data.authorId,
        audience: data.audience,
        customListId: data.customListId
      };
      const canView = await canViewerSeeStoryOptimized(
        storyForCheck,
        uid,
        viewerCtx,
        authorData,
        customAllowanceMap
      );
      if (!canView) return null;

      return {
        id: doc.id,
        authorId: data.authorId,
        audience: data.audience || null,
        customListId: data.customListId || null,
        timestamp: data.timestamp
      };
    })
  );

  return visibilityResults.filter(Boolean);
}

function buildStoryTrayItemsFromVisibleStories(visibleStories, uid, lastSeenMap, viewedStoryKeys) {
  const itemsByUser = new Map();
  for (const story of visibleStories) {
    const storyTs = tsToMillis(story.timestamp) || 0;
    let viewed = story.authorId === uid;
    if (!viewed) {
      const supportsShortcut = storyAudienceSupportsSeenShortcut(story.audience);
      const lastSeen = lastSeenMap.get(story.authorId) || 0;
      viewed = supportsShortcut && lastSeen >= storyTs;
      if (!viewed) {
        viewed = viewedStoryKeys.has(`${story.authorId}|${story.id}`);
      }
    }

    const item = itemsByUser.get(story.authorId) || {
      userId: story.authorId,
      storyCount: 0,
      hasUnseenStory: false,
      segments: [],
      latestStoryAt: null
    };
    item.storyCount += 1;
    item.hasUnseenStory = item.hasUnseenStory || !viewed;
    item.latestStoryAt = Math.max(item.latestStoryAt || 0, storyTs || 0) || null;
    item.segments.push(serializeStoryTraySegment(story, viewed));
    itemsByUser.set(story.authorId, item);
  }
  return itemsByUser;
}

function sortStoryTrayItems(items, uid, candidateOrder) {
  return [...items].sort((a, b) => {
    if (a.userId === uid) return -1;
    if (b.userId === uid) return 1;
    if (a.hasUnseenStory !== b.hasUnseenStory) return a.hasUnseenStory ? -1 : 1;
    const tsA = Number(a.latestStoryAt || 0);
    const tsB = Number(b.latestStoryAt || 0);
    if (tsA !== tsB) return tsB - tsA;
    return (candidateOrder.get(a.userId) ?? 999999) - (candidateOrder.get(b.userId) ?? 999999);
  });
}

async function buildStoryRingPagePayload(uid, offset, limit) {
  const db = admin.firestore();
  const viewerCtx = await buildViewerContext(uid);
  const allCandidates = [uid, ...[...viewerCtx.following].filter((id) => id !== uid && !viewerCtx.mutedUsers.has(id))];
  const totalCandidates = allCandidates.length;
  if (offset >= totalCandidates) {
    return {
      items: [],
      nextCursor: null,
      source: 'backend',
      totalCandidates
    };
  }
  const now = admin.firestore.Timestamp.now();
  const visibleItems = [];
  const scannedAuthorIds = [];
  let cursor = offset;
  const internalBatchSize = Math.max(limit, 12);

  while (cursor < totalCandidates && visibleItems.length < limit) {
    const pageAuthorIds = allCandidates.slice(cursor, cursor + internalBatchSize);
    if (!pageAuthorIds.length) break;
    scannedAuthorIds.push(...pageAuthorIds);

    const normalizedDocs = await fetchActiveStoryDocsForAuthors(db, pageAuthorIds, now);
    const authorIds = [...new Set(normalizedDocs.map(({ data }) => data.authorId))];
    const [authorMap, lastSeenMap] = await Promise.all([
      batchLoadAuthorDocs(authorIds),
      fetchStoryLastSeenMap(uid, authorIds)
    ]);

    const visibleStories = await buildVisibleStoryRecords(uid, normalizedDocs, authorMap, viewerCtx);
    const needsViewerDoc = visibleStories.filter((story) => {
      if (story.authorId === uid) return false;
      if (!storyAudienceSupportsSeenShortcut(story.audience)) return true;
      const lastSeen = lastSeenMap.get(story.authorId) || 0;
      const storyTs = tsToMillis(story.timestamp) || 0;
      return !lastSeen || storyTs > lastSeen;
    });
    const viewedStoryKeys = await fetchStoryViewerDocs(uid, needsViewerDoc);

    const itemsByUser = buildStoryTrayItemsFromVisibleStories(
      visibleStories,
      uid,
      lastSeenMap,
      viewedStoryKeys
    );
    const candidateOrder = new Map(pageAuthorIds.map((id, index) => [id, index]));
    const sortedChunkItems = sortStoryTrayItems([...itemsByUser.values()], uid, candidateOrder);
    for (const item of sortedChunkItems) {
      if (visibleItems.length >= limit) break;
      visibleItems.push(item);
    }

    cursor += internalBatchSize;
  }

  const nextCursor = cursor < totalCandidates ? { offset: cursor } : null;

  return {
    items: visibleItems,
    nextCursor,
    source: 'backend',
    totalCandidates
  };
}

/**
 * 📚 getStoryTray — Backend-first story ring/tray endpoint.
 *
 * Response: { items: [{ userId, storyCount, hasUnseenStory, segments, latestStoryAt }], source, totalCandidates }
 */
const getStoryTray = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 120)) : 80;

    try {
      const payload = await buildStoryRingPagePayload(uid, 0, limit);
      console.log(`✅ getStoryTray: uid=${uid}, candidates=${payload.totalCandidates}, visibleAuthors=${payload.items.length}`);
      res.status(200).json(payload);
    } catch (error) {
      console.error('❌ getStoryTray error:', error);
      res.status(500).json({ error: 'Story tray fetch failed', details: error.message });
    }
  }
);

/**
 * 📚 getStoryRingPage — Paginated story ring/tray.
 *
 * POST body: { limit?: number, cursor?: { offset: number } }
 */
const getStoryRingPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 40)) : 16;
    const offset = Number.isFinite(body?.cursor?.offset) ? Math.max(0, body.cursor.offset) : 0;

    try {
      const payload = await buildStoryRingPagePayload(uid, offset, limit);
      console.log(`✅ getStoryRingPage: uid=${uid}, offset=${offset}, limit=${limit}, items=${payload.items.length}`);
      res.status(200).json(payload);
    } catch (error) {
      console.error('❌ getStoryRingPage error:', error);
      res.status(500).json({ error: 'Story ring page fetch failed', details: error.message });
    }
  }
);

/**
 * 📖 getAuthorStoryBundle — Visible stories for one author (viewer-filtered).
 *
 * POST body: { authorId: string }
 */
const getAuthorStoryBundle = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 80
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
    const authorId = typeof body.authorId === 'string' ? body.authorId.trim() : '';
    if (!authorId) {
      res.status(400).json({ error: 'authorId is required' });
      return;
    }

    const db = admin.firestore();
    try {
      const viewerCtx = await buildViewerContext(uid);
      const now = admin.firestore.Timestamp.now();
      const snap = await db.collection('users').doc(authorId).collection('stories')
        .where('expirationDate', '>', now)
        .orderBy('timestamp', 'asc')
        .get();

      const normalizedDocs = snap.docs
        .map((doc) => ({ doc, data: doc.data() || {} }))
        .filter(({ doc, data }) => isStoryPathAuthorConsistent(doc, data));

      const authorMap = await batchLoadAuthorDocs([authorId]);
      const visibleStories = await buildVisibleStoryRecords(uid, normalizedDocs, authorMap, viewerCtx);
      const lastSeenMap = await fetchStoryLastSeenMap(uid, [authorId]);
      const needsViewerDoc = visibleStories.filter((story) => {
        if (story.authorId === uid) return false;
        if (!storyAudienceSupportsSeenShortcut(story.audience)) return true;
        const lastSeen = lastSeenMap.get(story.authorId) || 0;
        const storyTs = tsToMillis(story.timestamp) || 0;
        return !lastSeen || storyTs > lastSeen;
      });
      const viewedStoryKeys = await fetchStoryViewerDocs(uid, needsViewerDoc);

      const stories = [];
      const segments = [];
      for (const story of visibleStories) {
        const storyTs = tsToMillis(story.timestamp) || 0;
        let viewed = story.authorId === uid;
        if (!viewed) {
          const supportsShortcut = storyAudienceSupportsSeenShortcut(story.audience);
          const lastSeen = lastSeenMap.get(story.authorId) || 0;
          viewed = supportsShortcut && lastSeen >= storyTs;
          if (!viewed) {
            viewed = viewedStoryKeys.has(`${story.authorId}|${story.id}`);
          }
        }
        segments.push(serializeStoryTraySegment(story, viewed));

        const sourceDoc = normalizedDocs.find(({ doc }) => doc.id === story.id);
        if (sourceDoc) {
          stories.push(serializeStoryDocument(sourceDoc.doc));
        }
      }

      console.log(`✅ getAuthorStoryBundle: uid=${uid}, authorId=${authorId}, stories=${stories.length}`);
      res.status(200).json({
        authorId,
        stories,
        segments,
        source: 'backend'
      });
    } catch (error) {
      console.error('❌ getAuthorStoryBundle error:', error);
      res.status(500).json({ error: 'Author story reel fetch failed', details: error.message });
    }
  }
);

/**
 * Map visibility helpers — server-side only; never leak hidden / onlyMe content on map surfaces.
 */
function isMapContentVisible(data) {
  if (!data || typeof data !== 'object') return false;
  // Derived server-side from "has location + audience"; not a separate user opt-out.
  if (data.mapVisibility === 'hidden') return false;
  if (data.audience === 'onlyMe') return false;
  return true;
}

function shouldFuzzMapCoordinate(audience, authorData) {
  const normalizedAudience = audience || 'everyone';
  if (normalizedAudience === 'onlyMe') return true;
  if (authorData && authorData.isPrivate === true && normalizedAudience !== 'everyone') {
    return true;
  }
  return normalizedAudience !== 'everyone';
}

function hashStringToUnit(seed) {
  let hash = 2166136261;
  const input = String(seed || '');
  for (let i = 0; i < input.length; i += 1) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0) / 4294967295;
}

function fuzzMapCoordinate(coordinate, seed) {
  const lat = Number(coordinate && coordinate.latitude);
  const lon = Number(coordinate && coordinate.longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return coordinate;

  const angle = hashStringToUnit(`${seed}|angle`) * Math.PI * 2;
  const distanceMeters = 180 + (hashStringToUnit(`${seed}|distance`) * 220);
  const latOffset = (distanceMeters / 111320) * Math.sin(angle);
  const cosLat = Math.max(0.2, Math.cos((lat * Math.PI) / 180));
  const lonOffset = (distanceMeters / (111320 * cosLat)) * Math.cos(angle);

  return {
    latitude: Math.max(-90, Math.min(90, lat + latOffset)),
    longitude: Math.max(-180, Math.min(180, lon + lonOffset))
  };
}

function serializeMomentForMap(docId, data, authorData) {
  const serialized = serializeMoment(docId, data);
  const audience = data.audience || 'everyone';
  if (serialized.locationCoordinate && shouldFuzzMapCoordinate(audience, authorData)) {
    serialized.locationCoordinate = fuzzMapCoordinate(
      serialized.locationCoordinate,
      `${data.authorId || ''}|${docId}`
    );
    serialized.locationFuzzed = true;
  }
  return serialized;
}

function extractStoryMapLocation(data) {
  if (!data || typeof data !== 'object') return null;

  const denormalized = data.mapLocation || null;
  if (denormalized && typeof denormalized === 'object') {
    const lat = Number(denormalized.latitude);
    const lon = Number(denormalized.longitude);
    if (Number.isFinite(lat) && Number.isFinite(lon)) {
      const locationName = typeof denormalized.locationName === 'string'
        ? denormalized.locationName.trim()
        : '';
      return { latitude: lat, longitude: lon, locationName };
    }
  }

  const stickers = Array.isArray(data.stickers) ? data.stickers : [];
  for (const sticker of stickers) {
    if (!sticker || typeof sticker !== 'object') continue;
    if (sticker.type !== 'location') continue;
    const lat = Number(sticker.latitude);
    const lon = Number(sticker.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) continue;
    const locationName = typeof sticker.location === 'string' ? sticker.location.trim() : '';
    return { latitude: lat, longitude: lon, locationName };
  }

  return null;
}

function storyMatchesMapLocationName(mapLocation, locationName) {
  if (!mapLocation || !locationName) return false;
  const normalizedTarget = String(locationName).trim().toLowerCase();
  const normalizedSource = String(mapLocation.locationName || '').trim().toLowerCase();
  if (!normalizedTarget || !normalizedSource) return false;
  return normalizedSource === normalizedTarget
    || normalizedSource.includes(normalizedTarget)
    || normalizedTarget.includes(normalizedSource);
}

function storyMatchesMapRegion(mapLocation, latitudeMin, latitudeMax, longitudeMin, longitudeMax) {
  if (!mapLocation) return false;
  const lat = Number(mapLocation.latitude);
  const lon = Number(mapLocation.longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return false;
  return lat >= latitudeMin && lat <= latitudeMax && lon >= longitudeMin && lon <= longitudeMax;
}

function serializeMapStory(docId, data, mapLocation, authorData) {
  const audience = data.audience || 'everyone';
  let coordinate = {
    latitude: mapLocation.latitude,
    longitude: mapLocation.longitude
  };
  if (shouldFuzzMapCoordinate(audience, authorData)) {
    coordinate = fuzzMapCoordinate(coordinate, `${data.authorId || ''}|story|${docId}`);
  }

  return {
    id: docId,
    authorId: data.authorId || '',
    username: data.username || '',
    profileImagePath: data.profileImagePath || null,
    timestamp: tsToMillis(data.timestamp),
    expirationDate: tsToMillis(data.expirationDate),
    audience,
    locationName: mapLocation.locationName || null,
    locationCoordinate: coordinate,
    locationFuzzed: shouldFuzzMapCoordinate(audience, authorData),
    previewUrl: pickStoryPreviewUrl(data),
    contentType: 'story'
  };
}

async function fetchMapStoryCandidates(db, uid, viewerCtx, mode, filters, limit) {
  const candidateUserIds = await buildMapFallbackCandidateUserIds(uid, viewerCtx, db);
  const now = admin.firestore.Timestamp.now();
  const storyDocs = await fetchActiveStoryDocsForAuthors(db, candidateUserIds, now);

  return storyDocs.filter(({ data }) => {
    if (!isMapContentVisible(data)) return false;
    const mapLocation = extractStoryMapLocation(data);
    if (!mapLocation) return false;

    if (mode === 'location') {
      return storyMatchesMapLocationName(mapLocation, filters.locationName || '');
    }

    return storyMatchesMapRegion(
      mapLocation,
      filters.latitudeMin,
      filters.latitudeMax,
      filters.longitudeMin,
      filters.longitudeMax
    );
  }).slice(0, Math.max(limit * 4, 200));
}

/**
 * 🗺️ getMapMomentsPage — Returns moments visible to the viewer for map surfaces.
 *
 * POST body:
 * {
 *   mode: "region" | "location",
 *   centerLatitude?: number,
 *   centerLongitude?: number,
 *   latitudeDelta?: number,
 *   longitudeDelta?: number,
 *   locationName?: string,
 *   limit?: number
 * }
 *
 * Response:
 * {
 *   moments: [...],
 *   source: "backend",
 *   totalCandidates: number
 * }
 */
const getMapMomentsPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const mode = body.mode === 'location' ? 'location' : 'region';
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 120)) : 80;

    const db = admin.firestore();

    try {
      const viewerCtx = await buildViewerContext(uid);

      let query = db.collectionGroup('moments');
      let longitudeMin = -180;
      let longitudeMax = 180;
      let latitudeMin = -90;
      let latitudeMax = 90;
      let debugScope = 'region';

      if (mode === 'location') {
        const locationName = typeof body.locationName === 'string' ? body.locationName.trim() : '';
        if (!locationName) {
          res.status(400).json({ error: 'Missing locationName' });
          return;
        }
        debugScope = `location:${locationName}`;
        query = query.where('location', '==', locationName).limit(Math.max(limit * 4, 200));
      } else {
        const centerLatitude = Number(body.centerLatitude);
        const centerLongitude = Number(body.centerLongitude);
        const latitudeDelta = Number(body.latitudeDelta);
        const longitudeDelta = Number(body.longitudeDelta);

        const validRegion = Number.isFinite(centerLatitude)
          && Number.isFinite(centerLongitude)
          && Number.isFinite(latitudeDelta)
          && Number.isFinite(longitudeDelta)
          && latitudeDelta > 0
          && longitudeDelta > 0;

        if (!validRegion) {
          res.status(400).json({ error: 'Invalid region payload' });
          return;
        }

        latitudeMin = Math.max(-90, centerLatitude - (latitudeDelta / 2));
        latitudeMax = Math.min(90, centerLatitude + (latitudeDelta / 2));
        longitudeMin = Math.max(-180, centerLongitude - (longitudeDelta / 2));
        longitudeMax = Math.min(180, centerLongitude + (longitudeDelta / 2));

        query = query
          .where('locationCoordinate.latitude', '>=', latitudeMin)
          .where('locationCoordinate.latitude', '<=', latitudeMax)
          .orderBy('locationCoordinate.latitude')
          .limit(Math.max(limit * 4, 220));
      }

      let snapshot;
      let usedFallbackPath = false;
      try {
        snapshot = await query.get();
      } catch (queryError) {
        if (!isFirestoreFailedPrecondition(queryError)) {
          throw queryError;
        }

        usedFallbackPath = true;
        const fallbackCandidateUserIds = await buildMapFallbackCandidateUserIds(uid, viewerCtx, db);
        const fallbackDocs = await fetchMapCandidatesByAuthorBatches(
          db,
          fallbackCandidateUserIds,
          mode,
          {
            locationName: mode === 'location' ? (typeof body.locationName === 'string' ? body.locationName.trim() : '') : '',
            latitudeMin,
            latitudeMax,
            longitudeMin,
            longitudeMax
          }
        );
        snapshot = { docs: fallbackDocs };
      }

      const nowMs = Date.now();

      // Primary candidate window (non-archived + no future scheduled for non-authors + in longitude bounds for region mode)
      const candidateDocs = snapshot.docs.filter((doc) => {
        const data = doc.data() || {};

        if (!isMapContentVisible(data)) return false;

        if (data.isArchived === true) return false;

        if (data.authorId !== uid) {
          const scheduledMs = tsToMillis(data.scheduledDate);
          if (scheduledMs && scheduledMs > nowMs) return false;
        }

        if (mode !== 'location') {
          const coord = data.locationCoordinate || {};
          const lon = Number(coord.longitude);
          if (!Number.isFinite(lon)) return false;
          if (lon < longitudeMin || lon > longitudeMax) return false;
        }

        return true;
      });

      const authorIds = [...new Set(candidateDocs.map((d) => (d.data() || {}).authorId).filter(Boolean))];
      const authorMap = await batchLoadAuthorDocs(authorIds);

      const privacyResults = await Promise.all(
        candidateDocs.map(async (doc) => {
          const data = doc.data() || {};
          const authorData = authorMap.get(data.authorId);
          if (!authorData) return { doc, data, canView: false };

          const momentForCheck = {
            id: doc.id,
            authorId: data.authorId,
            audience: data.audience,
            taggedUsers: data.taggedUsers,
            customListId: data.customListId,
            isArchived: data.isArchived === true
          };

          const canView = await canViewerSeeMoment(momentForCheck, uid, viewerCtx, authorData);
          return { doc, data, canView };
        })
      );

      const visible = privacyResults
        .filter((entry) => entry.canView)
        .sort((a, b) => {
          const tsA = tsToMillis(a.data.timestamp) || 0;
          const tsB = tsToMillis(b.data.timestamp) || 0;
          if (tsB !== tsA) return tsB - tsA;
          return String(b.doc.id).localeCompare(String(a.doc.id));
        })
        .slice(0, limit);

      const moments = visible.map(({ doc, data }) => {
        const authorData = authorMap.get(data.authorId);
        return serializeMomentForMap(doc.id, data, authorData);
      });

      const pathTag = usedFallbackPath ? 'fallback_author_batches' : 'geo_query';
      console.log(`✅ getMapMomentsPage: uid=${uid}, scope=${debugScope}, path=${pathTag}, candidates=${candidateDocs.length}, visible=${visible.length}, returned=${moments.length}`);

      res.status(200).json({
        moments,
        source: 'backend',
        totalCandidates: candidateDocs.length
      });
    } catch (error) {
      console.error('❌ getMapMomentsPage error:', error);
      res.status(500).json({ error: 'Map moments fetch failed', details: error.message });
    }
  }
);

/**
 * 🗺️ getMapStoriesPage — Active stories with location stickers visible to the viewer.
 *
 * POST body mirrors getMapMomentsPage.
 * Response: { stories: [...], source: "backend", totalCandidates: number }
 */
const getMapStoriesPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const mode = body.mode === 'location' ? 'location' : 'region';
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 120)) : 80;
    const db = admin.firestore();

    try {
      const viewerCtx = await buildViewerContext(uid);

      let latitudeMin = -90;
      let latitudeMax = 90;
      let longitudeMin = -180;
      let longitudeMax = 180;
      let debugScope = 'region';

      if (mode === 'location') {
        const locationName = typeof body.locationName === 'string' ? body.locationName.trim() : '';
        if (!locationName) {
          res.status(400).json({ error: 'Missing locationName' });
          return;
        }
        debugScope = `location:${locationName}`;
      } else {
        const centerLatitude = Number(body.centerLatitude);
        const centerLongitude = Number(body.centerLongitude);
        const latitudeDelta = Number(body.latitudeDelta);
        const longitudeDelta = Number(body.longitudeDelta);

        const validRegion = Number.isFinite(centerLatitude)
          && Number.isFinite(centerLongitude)
          && Number.isFinite(latitudeDelta)
          && Number.isFinite(longitudeDelta)
          && latitudeDelta > 0
          && longitudeDelta > 0;

        if (!validRegion) {
          res.status(400).json({ error: 'Invalid region payload' });
          return;
        }

        latitudeMin = Math.max(-90, centerLatitude - (latitudeDelta / 2));
        latitudeMax = Math.min(90, centerLatitude + (latitudeDelta / 2));
        longitudeMin = Math.max(-180, centerLongitude - (longitudeDelta / 2));
        longitudeMax = Math.min(180, centerLongitude + (longitudeDelta / 2));
      }

      const filters = mode === 'location'
        ? { locationName: typeof body.locationName === 'string' ? body.locationName.trim() : '' }
        : { latitudeMin, latitudeMax, longitudeMin, longitudeMax };

      const candidateStories = await fetchMapStoryCandidates(
        db,
        uid,
        viewerCtx,
        mode,
        filters,
        limit
      );

      const authorIds = [...new Set(candidateStories.map(({ data }) => data.authorId).filter(Boolean))];
      const authorMap = await batchLoadAuthorDocs(authorIds);

      const customCandidates = candidateStories.map(({ doc, data }) => ({
        id: doc.id,
        authorId: data.authorId,
        audience: data.audience
      })).filter((story) => story.audience === 'custom');
      const customAllowanceMap = await preloadCustomStoryAllowanceMap(customCandidates, uid, db);

      const privacyResults = await Promise.all(
        candidateStories.map(async ({ doc, data }) => {
          const authorData = authorMap.get(data.authorId);
          if (!authorData) return null;

          const mapLocation = extractStoryMapLocation(data);
          if (!mapLocation) return null;

          const storyForCheck = {
            id: doc.id,
            authorId: data.authorId,
            audience: data.audience,
            customListId: data.customListId
          };

          const canView = await canViewerSeeStoryOptimized(
            storyForCheck,
            uid,
            viewerCtx,
            authorData,
            customAllowanceMap
          );
          if (!canView) return null;

          return { doc, data, mapLocation };
        })
      );

      const visible = privacyResults
        .filter(Boolean)
        .sort((a, b) => {
          const tsA = tsToMillis(a.data.timestamp) || 0;
          const tsB = tsToMillis(b.data.timestamp) || 0;
          if (tsB !== tsA) return tsB - tsA;
          return String(b.doc.id).localeCompare(String(a.doc.id));
        })
        .slice(0, limit);

      const stories = visible.map(({ doc, data, mapLocation }) => {
        const authorData = authorMap.get(data.authorId);
        return serializeMapStory(doc.id, data, mapLocation, authorData);
      });

      console.log(`✅ getMapStoriesPage: uid=${uid}, scope=${debugScope}, candidates=${candidateStories.length}, visible=${visible.length}, returned=${stories.length}`);

      res.status(200).json({
        stories,
        source: 'backend',
        totalCandidates: candidateStories.length
      });
    } catch (error) {
      console.error('❌ getMapStoriesPage error:', error);
      res.status(500).json({ error: 'Map stories fetch failed', details: error.message });
    }
  }
);

/**
 * 🎯 getReactedMomentsPage — Returns moments the viewer reacted to.
 *
 * POST body: { cursor?: { timestamp: number }, limit?: number }
 * Response:  { items: [{ moment, reactionType, reactedAt, authorId, momentId, canView }], nextCursor, source, totalCandidates }
 */
const getReactedMomentsPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 60)) : 30;
    const cursorTimestamp = Number(body?.cursor?.timestamp || 0);

    const db = admin.firestore();

    try {
      let query = db.collectionGroup('reactions')
        .where('userId', '==', uid)
        .orderBy('timestamp', 'desc');

      if (Number.isFinite(cursorTimestamp) && cursorTimestamp > 0) {
        query = query.startAfter(admin.firestore.Timestamp.fromMillis(cursorTimestamp));
      }

      // Scan a wider window so we can filter hidden/private content server-side and still fill one page.
      const scanLimit = Math.max(limit * 6, 120);
      const reactionsSnap = await query.limit(scanLimit).get();

      if (reactionsSnap.empty) {
        res.status(200).json({
          items: [],
          nextCursor: null,
          source: 'backend',
          totalCandidates: 0
        });
        return;
      }

      const viewerCtx = await buildViewerContext(uid);
      const seenMoments = new Set();
      const candidates = [];

      for (const doc of reactionsSnap.docs) {
        const pathParts = doc.ref.path.split('/');
        if (pathParts.length < 6 || pathParts[0] !== 'users' || pathParts[2] !== 'moments') {
          continue;
        }

        const authorId = pathParts[1];
        const momentId = pathParts[3];
        const dedupeKey = `${authorId}_${momentId}`;
        if (seenMoments.has(dedupeKey)) continue;
        seenMoments.add(dedupeKey);

        const data = doc.data() || {};
        candidates.push({
          authorId,
          momentId,
          reactionType: data.reactionType || data.reaction || '',
          reactedAt: data.timestamp || null
        });
      }

      if (candidates.length === 0) {
        const lastDoc = reactionsSnap.docs[reactionsSnap.docs.length - 1];
        const lastTimestamp = tsToMillis(lastDoc.data().timestamp);
        res.status(200).json({
          items: [],
          nextCursor: lastTimestamp ? { timestamp: lastTimestamp } : null,
          source: 'backend',
          totalCandidates: 0
        });
        return;
      }

      const authorIds = candidates.map(item => item.authorId);
      const authorMap = await batchLoadAuthorDocs(authorIds);

      // Batch load moment docs
      const momentRefs = candidates.map(item => db.doc(`users/${item.authorId}/moments/${item.momentId}`));
      const momentDocs = [];
      for (let i = 0; i < momentRefs.length; i += 100) {
        const chunk = momentRefs.slice(i, i + 100);
        if (chunk.length === 0) continue;
        const docs = await db.getAll(...chunk);
        docs.forEach(doc => momentDocs.push(doc));
      }

      const momentMap = new Map();
      for (const doc of momentDocs) {
        if (!doc.exists) continue;
        const parts = doc.ref.path.split('/');
        if (parts.length < 4) continue;
        const key = `${parts[1]}_${parts[3]}`;
        momentMap.set(key, doc);
      }

      const items = [];
      for (const candidate of candidates) {
        const key = `${candidate.authorId}_${candidate.momentId}`;
        const momentDoc = momentMap.get(key);
        if (!momentDoc || !momentDoc.exists) continue;

        const momentData = momentDoc.data() || {};
        if (momentData.isArchived === true) continue;
        const authorData = authorMap.get(candidate.authorId);
        if (!authorData) continue;

        const canView = await canViewerSeeMoment(
          {
            id: momentDoc.id,
            authorId: candidate.authorId,
            audience: momentData.audience,
            taggedUsers: momentData.taggedUsers,
            customListId: momentData.customListId,
            isArchived: momentData.isArchived === true
          },
          uid,
          viewerCtx,
          authorData
        );

        items.push({
          moment: canView
            ? serializeMoment(momentDoc.id, momentData)
            : serializeRestrictedMoment(momentDoc.id, momentData),
          reactionType: candidate.reactionType,
          reactedAt: tsToMillis(candidate.reactedAt),
          authorId: candidate.authorId,
          momentId: candidate.momentId,
          canView
        });

        if (items.length >= limit) break;
      }

      let nextCursor = null;
      const hasMoreScanned = reactionsSnap.size >= scanLimit;
      if (hasMoreScanned) {
        const lastDoc = reactionsSnap.docs[reactionsSnap.docs.length - 1];
        const lastTs = tsToMillis(lastDoc.data().timestamp);
        if (lastTs) {
          nextCursor = { timestamp: lastTs };
        }
      }

      console.log(`✅ getReactedMomentsPage: uid=${uid}, scanned=${reactionsSnap.size}, candidates=${candidates.length}, returned=${items.length}`);

      res.status(200).json({
        items,
        nextCursor,
        source: 'backend',
        totalCandidates: candidates.length
      });

    } catch (error) {
      console.error('❌ getReactedMomentsPage error:', error);
      res.status(500).json({ error: 'Reacted moments fetch failed', details: error.message });
    }
  }
);

/**
 * 😊 getStickerRepliesPage — Returns viewer sticker interactions:
 * - poll votes (with selected option text)
 * - question responses (with question + response text)
 *
 * POST body: { cursor?: { timestamp: number }, limit?: number }
 */
const getStickerRepliesPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 80)) : 40;
    const cursorTimestamp = Number(body?.cursor?.timestamp || 0);
    const db = admin.firestore();

    const parseStoryPath = (path) => {
      const parts = String(path || '').split('/');
      if (parts.length >= 6 && parts[0] === 'users' && parts[2] === 'stories') {
        return { authorId: parts[1], storyId: parts[3] };
      }
      return null;
    };

    try {
      const scanLimit = Math.max(limit * 6, 120);
      const viewerSnap = await db.collection('users').doc(uid).get();
      const viewerData = viewerSnap.exists ? (viewerSnap.data() || {}) : {};
      const actorUsername = typeof viewerData.username === 'string' ? viewerData.username : null;
      const actorProfileImagePath = typeof viewerData.profileImagePath === 'string' ? viewerData.profileImagePath : null;

      let pollQuery = db.collectionGroup('pollVotes')
        .where('userId', '==', uid)
        .orderBy('timestamp', 'desc');

      let questionQuery = db.collectionGroup('questionResponses')
        .where('userId', '==', uid)
        .orderBy('timestamp', 'desc');

      if (Number.isFinite(cursorTimestamp) && cursorTimestamp > 0) {
        const cursorTs = admin.firestore.Timestamp.fromMillis(cursorTimestamp);
        pollQuery = pollQuery.startAfter(cursorTs);
        questionQuery = questionQuery.startAfter(cursorTs);
      }

      const [pollSnap, questionSnap] = await Promise.all([
        pollQuery.limit(scanLimit).get(),
        questionQuery.limit(scanLimit).get()
      ]);

      const pollCandidates = [];
      const questionCandidates = [];
      const metadataKeys = new Set();

      for (const doc of pollSnap.docs) {
        const pathInfo = parseStoryPath(doc.ref.path);
        if (!pathInfo) continue;

        const data = doc.data() || {};
        const timestampMs = tsToMillis(data.timestamp);
        if (!timestampMs) continue;

        const option = Number.isInteger(data.option) ? data.option : null;
        pollCandidates.push({
          id: doc.id,
          kind: 'poll',
          authorId: pathInfo.authorId,
          storyId: pathInfo.storyId,
          timestampMs,
          option
        });
        metadataKeys.add(`poll:${pathInfo.authorId}:${pathInfo.storyId}`);
      }

      for (const doc of questionSnap.docs) {
        const pathInfo = parseStoryPath(doc.ref.path);
        if (!pathInfo) continue;
        if (doc.id === 'metadata') continue;

        const data = doc.data() || {};
        const timestampMs = tsToMillis(data.timestamp);
        if (!timestampMs) continue;

        questionCandidates.push({
          id: doc.id,
          kind: 'question',
          authorId: pathInfo.authorId,
          storyId: pathInfo.storyId,
          timestampMs,
          responseText: typeof data.response === 'string' ? data.response : ''
        });
        metadataKeys.add(`question:${pathInfo.authorId}:${pathInfo.storyId}`);
      }

      const merged = [...pollCandidates, ...questionCandidates].sort((a, b) => {
        if (a.timestampMs !== b.timestampMs) return b.timestampMs - a.timestampMs;
        return String(b.id).localeCompare(String(a.id));
      });

      if (merged.length === 0) {
        res.status(200).json({
          items: [],
          nextCursor: null,
          source: 'backend',
          totalCandidates: 0
        });
        return;
      }

      const metadataMap = new Map();
      const metadataRefs = [];
      const storyMap = new Map();
      for (const key of metadataKeys) {
        const [kind, authorId, storyId] = key.split(':');
        if (kind === 'poll') {
          metadataRefs.push({
            key,
            ref: db.doc(`users/${authorId}/stories/${storyId}/pollVotes/metadata`)
          });
        } else if (kind === 'question') {
          metadataRefs.push({
            key,
            ref: db.doc(`users/${authorId}/stories/${storyId}/questionResponses/metadata`)
          });
        }
      }

      for (let i = 0; i < metadataRefs.length; i += 100) {
        const chunk = metadataRefs.slice(i, i + 100);
        if (chunk.length === 0) continue;
        const docs = await db.getAll(...chunk.map(c => c.ref));
        for (let j = 0; j < docs.length; j += 1) {
          const source = chunk[j];
          const snap = docs[j];
          metadataMap.set(source.key, snap.exists ? (snap.data() || {}) : {});
        }
      }

      // Story-level fallback: some polls/questions keep their text inside story stickers.
      const uniqueStories = new Map(); // storyKey -> ref
      for (const candidate of merged) {
        const storyKey = `${candidate.authorId}:${candidate.storyId}`;
        if (!uniqueStories.has(storyKey)) {
          uniqueStories.set(storyKey, db.doc(`users/${candidate.authorId}/stories/${candidate.storyId}`));
        }
      }

      const storyEntries = [...uniqueStories.entries()];
      for (let i = 0; i < storyEntries.length; i += 100) {
        const chunk = storyEntries.slice(i, i + 100);
        if (chunk.length === 0) continue;
        const docs = await db.getAll(...chunk.map(([, ref]) => ref));
        for (let j = 0; j < docs.length; j += 1) {
          const [storyKey] = chunk[j];
          const snap = docs[j];
          storyMap.set(storyKey, snap.exists ? (snap.data() || {}) : {});
        }
      }

      const firstPollArrayFromStory = (storyData) => {
        if (!storyData || typeof storyData !== 'object') return [];
        const stickerContainers = [];
        if (Array.isArray(storyData.stickers)) stickerContainers.push(...storyData.stickers);
        if (Array.isArray(storyData.stickerData)) stickerContainers.push(...storyData.stickerData);

        for (const sticker of stickerContainers) {
          if (!sticker || typeof sticker !== 'object') continue;
          const interactionData = sticker.interactionData && typeof sticker.interactionData === 'object'
            ? sticker.interactionData
            : {};
          const directPollData = Array.isArray(sticker.pollData) ? sticker.pollData : null;
          const directPollOptions = Array.isArray(sticker.pollOptions) ? sticker.pollOptions : null;
          const interactionPollData = Array.isArray(interactionData.pollData) ? interactionData.pollData : null;
          const interactionPollOptions = Array.isArray(interactionData.pollOptions) ? interactionData.pollOptions : null;
          const anyPollArray = interactionPollData || interactionPollOptions || directPollData || directPollOptions;
          if (anyPollArray && anyPollArray.length > 0) return anyPollArray;
        }
        return [];
      };

      const firstQuestionTextFromStory = (storyData) => {
        if (!storyData || typeof storyData !== 'object') return null;
        const stickerContainers = [];
        if (Array.isArray(storyData.stickers)) stickerContainers.push(...storyData.stickers);
        if (Array.isArray(storyData.stickerData)) stickerContainers.push(...storyData.stickerData);

        for (const sticker of stickerContainers) {
          if (!sticker || typeof sticker !== 'object') continue;
          const interactionData = sticker.interactionData && typeof sticker.interactionData === 'object'
            ? sticker.interactionData
            : {};
          const directQuestionText = typeof sticker.questionText === 'string' ? sticker.questionText : null;
          const interactionQuestionText = typeof interactionData.questionText === 'string' ? interactionData.questionText : null;
          const value = interactionQuestionText || directQuestionText;
          if (value && value.trim()) return value;
        }
        return null;
      };

      const items = [];
      for (const candidate of merged) {
        const storyKey = `${candidate.authorId}:${candidate.storyId}`;
        const storyData = storyMap.get(storyKey) || {};
        const targetUsername = typeof storyData.username === 'string' ? storyData.username : null;

        if (candidate.kind === 'poll') {
          const key = `poll:${candidate.authorId}:${candidate.storyId}`;
          const metadata = metadataMap.get(key) || {};
          const pollData = Array.isArray(metadata.pollData) ? metadata.pollData : [];
          const storyPollData = firstPollArrayFromStory(storyData);

          let optionText = '';
          if (Number.isInteger(candidate.option) && candidate.option >= 0) {
            const metadataRaw = pollData[candidate.option + 1];
            const storyRaw = storyPollData[candidate.option + 1];
            const storyRawNoQuestion = storyPollData[candidate.option];
            if (typeof metadataRaw === 'string' && metadataRaw.trim()) optionText = metadataRaw;
            else if (typeof storyRaw === 'string' && storyRaw.trim()) optionText = storyRaw;
            else if (typeof storyRawNoQuestion === 'string' && storyRawNoQuestion.trim()) optionText = storyRawNoQuestion;
          }

          items.push({
            id: `${candidate.authorId}_${candidate.storyId}_${candidate.id}`,
            sourceId: candidate.id,
            kind: 'poll',
            authorId: candidate.authorId,
            storyId: candidate.storyId,
            targetUsername,
            actorId: uid,
            actorUsername,
            actorProfileImagePath,
            timestamp: candidate.timestampMs,
            pollOption: Number.isInteger(candidate.option) ? candidate.option : null,
            pollOptionText: optionText || null,
            questionText: null,
            responseText: null
          });
        } else {
          const key = `question:${candidate.authorId}:${candidate.storyId}`;
          const metadata = metadataMap.get(key) || {};
          const metadataQuestionText = typeof metadata.questionText === 'string' ? metadata.questionText : null;
          const storyQuestionText = firstQuestionTextFromStory(storyData);
          const questionText = metadataQuestionText || storyQuestionText;

          items.push({
            id: `${candidate.authorId}_${candidate.storyId}_${candidate.id}`,
            sourceId: candidate.id,
            kind: 'question',
            authorId: candidate.authorId,
            storyId: candidate.storyId,
            targetUsername,
            actorId: uid,
            actorUsername,
            actorProfileImagePath,
            timestamp: candidate.timestampMs,
            pollOption: null,
            pollOptionText: null,
            questionText,
            responseText: candidate.responseText || null
          });
        }

        if (items.length >= limit) break;
      }

      let nextCursor = null;
      const hasMoreScanned = pollSnap.size >= scanLimit || questionSnap.size >= scanLimit;
      if (hasMoreScanned) {
        const lastPollTs = pollSnap.size > 0 ? tsToMillis(pollSnap.docs[pollSnap.docs.length - 1].data().timestamp) : null;
        const lastQuestionTs = questionSnap.size > 0 ? tsToMillis(questionSnap.docs[questionSnap.docs.length - 1].data().timestamp) : null;
        const minTs = [lastPollTs, lastQuestionTs]
          .filter((v) => Number.isFinite(v) && v > 0)
          .reduce((acc, v) => Math.min(acc, v), Number.POSITIVE_INFINITY);
        if (Number.isFinite(minTs) && minTs > 0) {
          nextCursor = { timestamp: minTs };
        }
      }

      console.log(`✅ getStickerRepliesPage: uid=${uid}, poll=${pollCandidates.length}, question=${questionCandidates.length}, returned=${items.length}`);
      res.status(200).json({
        items,
        nextCursor,
        source: 'backend',
        totalCandidates: merged.length
      });
    } catch (error) {
      console.error('❌ getStickerRepliesPage error:', error);
      res.status(500).json({ error: 'Sticker replies fetch failed', details: error.message });
    }
  }
);

/**
 * 🏷️ getTaggedMomentsPage — Returns moments where viewer is tagged.
 *
 * POST body: { cursor?: { timestamp: number }, limit?: number }
 * Response:  {
 *   items: [{ moment, taggedAt, authorId, momentId, canView }],
 *   nextCursor,
 *   source,
 *   totalCandidates
 * }
 */
const getTaggedMomentsPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 60)) : 30;
    const cursorTimestamp = Number(body?.cursor?.timestamp || 0);
    const requestedTargetUserId = typeof body?.targetUserId === 'string' ? body.targetUserId.trim() : '';
    const targetUserId = requestedTargetUserId || uid;

    const db = admin.firestore();

    try {
      let query = db.collectionGroup('moments')
        .where('taggedUsers', 'array-contains', targetUserId)
        .orderBy('timestamp', 'desc');

      if (Number.isFinite(cursorTimestamp) && cursorTimestamp > 0) {
        query = query.startAfter(admin.firestore.Timestamp.fromMillis(cursorTimestamp));
      }

      const snap = await query.limit(limit).get();

      if (snap.empty) {
        res.status(200).json({
          items: [],
          nextCursor: null,
          source: 'backend',
          totalCandidates: 0
        });
        return;
      }

      const viewerCtx = await buildViewerContext(uid);
      const authorIds = Array.from(new Set(
        snap.docs
          .map((doc) => doc.ref.path.split('/'))
          .filter((parts) => parts.length >= 4 && parts[0] === 'users' && parts[2] === 'moments')
          .map((parts) => parts[1])
      ));
      const authorMap = await batchLoadAuthorDocs(authorIds);

      const items = [];
      for (const doc of snap.docs) {
        const pathParts = doc.ref.path.split('/');
        if (pathParts.length < 4 || pathParts[0] !== 'users' || pathParts[2] !== 'moments') {
          continue;
        }

        const authorId = pathParts[1];
        const momentId = pathParts[3];
        const momentData = doc.data() || {};
        if (momentData.isArchived === true) continue;
        const authorData = authorMap.get(authorId);
        if (!authorData) continue;
        const canView = await canViewerSeeMoment(
          { id: momentId, authorId, ...momentData },
          uid,
          viewerCtx,
          authorData
        );
        if (!canView) continue;

        items.push({
          moment: serializeMoment(doc.id, momentData),
          taggedAt: tsToMillis(momentData.timestamp),
          authorId,
          momentId,
          canView: true
        });
      }

      let nextCursor = null;
      if (snap.size >= limit) {
        const lastDoc = snap.docs[snap.docs.length - 1];
        const lastTs = tsToMillis(lastDoc.data().timestamp);
        if (lastTs) {
          nextCursor = { timestamp: lastTs };
        }
      }

      console.log(`✅ getTaggedMomentsPage: uid=${uid}, scanned=${snap.size}, returned=${items.length}`);

      res.status(200).json({
        items,
        nextCursor,
        source: 'backend',
        totalCandidates: items.length
      });
    } catch (error) {
      console.error('❌ getTaggedMomentsPage error:', error);
      res.status(500).json({ error: 'Tagged moments fetch failed', details: error.message });
    }
  }
);

/**
 * 👤 getProfileMomentsPage — Returns moments for a target profile with backend privacy filtering.
 *
 * POST body: { targetUserId?: string, cursor?: { timestamp: number, momentId?: string }, limit?: number, includeTotalCount?: boolean }
 * Response: { moments: [...], nextCursor: {...}|null, source: "backend", totalCandidates: N, totalVisibleCount?: N }
 *
 * includeTotalCount (solo sin cursor): escanea hasta PROFILE_TOTAL_COUNT_SCAN_CAP moments y devuelve
 * en totalVisibleCount cuántos puede ver el viewer en total (audiencia/archivados/privacidad aplicados).
 */
const PROFILE_TOTAL_COUNT_SCAN_CAP = 500;
const getProfileMomentsPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 60)) : 50;
    const cursorTimestamp = Number(body?.cursor?.timestamp || 0);
    const cursorMomentId = typeof body?.cursor?.momentId === 'string' ? body.cursor.momentId.trim() : '';
    const requestedTargetUserId = typeof body?.targetUserId === 'string' ? body.targetUserId.trim() : '';
    const targetUserId = requestedTargetUserId || uid;
    const includeTotalCount = body?.includeTotalCount === true && !(cursorTimestamp > 0);
    const scanLimit = includeTotalCount ? PROFILE_TOTAL_COUNT_SCAN_CAP : limit;
    const db = admin.firestore();

    try {
      const [viewerCtx, authorMap] = await Promise.all([
        buildViewerContext(uid),
        batchLoadAuthorDocs([targetUserId])
      ]);
      const authorData = authorMap.get(targetUserId);

      if (!authorData) {
        res.status(200).json({ moments: [], nextCursor: null, source: 'backend', totalCandidates: 0, totalVisibleCount: includeTotalCount ? 0 : undefined });
        return;
      }

      let query = db.collection(`users/${targetUserId}/moments`)
        .orderBy('timestamp', 'desc');

      if (Number.isFinite(cursorTimestamp) && cursorTimestamp > 0) {
        query = query.startAfter(admin.firestore.Timestamp.fromMillis(cursorTimestamp));
      }

      const snap = await query.limit(scanLimit).get();
      if (snap.empty) {
        res.status(200).json({ moments: [], nextCursor: null, source: 'backend', totalCandidates: 0, totalVisibleCount: includeTotalCount ? 0 : undefined });
        return;
      }

      const now = Date.now();
      const filteredByCursor = snap.docs.filter((doc) => !cursorMomentId || doc.id !== cursorMomentId);
      const candidates = filteredByCursor.filter((doc) => {
        const data = doc.data() || {};
        if (data.isArchived === true) return false;
        if (!isMomentPathAuthorConsistent(doc, data)) return false;
        if (data.authorId === uid) return true;
        const schedMs = tsToMillis(data.scheduledDate);
        return !(schedMs && schedMs > now);
      });

      const privacyResults = await Promise.all(
        candidates.map(async (doc) => {
          const data = doc.data() || {};
          const canView = await canViewerSeeMoment(
            {
              id: doc.id,
              authorId: data.authorId,
              audience: data.audience,
              taggedUsers: data.taggedUsers,
              customListId: data.customListId,
              isArchived: data.isArchived === true
            },
            uid,
            viewerCtx,
            authorData
          );
          return { doc, data, canView };
        })
      );

      const visibleDocs = privacyResults.filter((entry) => entry.canView);
      const moments = visibleDocs.slice(0, limit).map(({ doc, data }) => serializeMoment(doc.id, data));

      let nextCursor = null;
      if (!includeTotalCount && snap.size >= limit && snap.docs.length > 0) {
        const lastDoc = snap.docs[snap.docs.length - 1];
        nextCursor = {
          timestamp: tsToMillis(lastDoc.data().timestamp),
          momentId: lastDoc.id,
          authorId: targetUserId
        };
      }

      console.log(`✅ getProfileMomentsPage: viewer=${uid}, target=${targetUserId}, scanned=${snap.size}, returned=${moments.length}${includeTotalCount ? `, totalVisible=${visibleDocs.length}` : ''}`);
      res.status(200).json({
        moments,
        nextCursor,
        source: 'backend',
        totalCandidates: candidates.length,
        totalVisibleCount: includeTotalCount ? visibleDocs.length : undefined
      });
    } catch (error) {
      console.error('❌ getProfileMomentsPage error:', error);
      res.status(500).json({ error: 'Profile moments fetch failed', details: error.message });
    }
  }
);

/**
 * ✨ getVisibleHighlightsPage — Returns highlights already filtered for the authenticated viewer.
 *
 * POST body: { targetUserId?: string, limit?: number }
 * Response: { highlights: [...], source: "backend", totalCandidates: N }
 */
const getVisibleHighlightsPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 50)) : 30;
    const requestedTargetUserId = typeof body?.targetUserId === 'string' ? body.targetUserId.trim() : '';
    const targetUserId = requestedTargetUserId || uid;
    const db = admin.firestore();

    try {
      const [viewerCtx, authorMap, highlightsSnap] = await Promise.all([
        buildViewerContext(uid),
        batchLoadAuthorDocs([targetUserId]),
        db.collection(`users/${targetUserId}/highlights`)
          .orderBy('createdAt', 'desc')
          .limit(limit)
          .get()
      ]);

      const authorData = authorMap.get(targetUserId);
      if (!authorData || highlightsSnap.empty) {
        res.status(200).json({ highlights: [], source: 'backend', totalCandidates: 0 });
        return;
      }

      const highlights = highlightsSnap.docs.map((doc) => ({ id: doc.id, data: doc.data() || {} }));
      const uniqueStoryIds = [...new Set(
        highlights.flatMap(({ data }) => Array.isArray(data.storyIds) ? data.storyIds.filter((id) => typeof id === 'string' && id.trim()) : [])
      )];

      const storyRefs = uniqueStoryIds.map((storyId) => db.doc(`users/${targetUserId}/stories/${storyId}`));
      const storyDocs = [];
      for (let i = 0; i < storyRefs.length; i += 100) {
        const chunkDocs = await db.getAll(...storyRefs.slice(i, i + 100));
        storyDocs.push(...chunkDocs);
      }

      const storyMap = new Map();
      storyDocs.forEach((doc) => {
        if (!doc.exists) return;
        storyMap.set(doc.id, doc.data() || {});
      });

      const customStories = storyDocs
        .filter((doc) => doc.exists)
        .map((doc) => ({ id: doc.id, ...(doc.data() || {}) }))
        .filter((story) => story.audience === 'custom');
      const customAllowanceMap = await preloadCustomStoryAllowanceMap(customStories, uid, db);

      const resolvedHighlights = [];
      for (const highlight of highlights) {
        const orderedStoryIds = Array.isArray(highlight.data.storyIds) ? highlight.data.storyIds : [];
        const visibleStoryIds = [];
        const visibleStoryData = [];

        for (const storyId of orderedStoryIds) {
          const storyData = storyMap.get(storyId);
          if (!storyData) continue;

          const canView = await canViewerSeeStoryOptimized(
            {
              id: storyId,
              authorId: targetUserId,
              audience: storyData.audience,
              customListId: storyData.customListId
            },
            uid,
            viewerCtx,
            authorData,
            customAllowanceMap
          );

          if (!canView) continue;
          visibleStoryIds.push(storyId);
          visibleStoryData.push(storyData);
        }

        if (!visibleStoryIds.length) continue;

        const originalCover = typeof highlight.data.coverImageUrl === 'string' ? highlight.data.coverImageUrl : null;
        const resolvedCoverUrl = originalCover && visibleStoryData.some((story) => storyPrimaryMediaUrl(story) === originalCover)
          ? originalCover
          : storyPrimaryMediaUrl(visibleStoryData[0]);

        resolvedHighlights.push(
          serializeHighlightedStory(highlight.id, highlight.data, {
            authorId: targetUserId,
            storyIds: visibleStoryIds,
            storiesCount: visibleStoryIds.length,
            coverImageUrl: resolvedCoverUrl
          })
        );
      }

      console.log(`✅ getVisibleHighlightsPage: viewer=${uid}, target=${targetUserId}, scanned=${highlights.length}, returned=${resolvedHighlights.length}`);
      res.status(200).json({
        highlights: resolvedHighlights,
        source: 'backend',
        totalCandidates: highlights.length
      });
    } catch (error) {
      console.error('❌ getVisibleHighlightsPage error:', error);
      res.status(500).json({ error: 'Visible highlights fetch failed', details: error.message });
    }
  }
);

/**
 * 💬 getCommentedMomentsPage — Returns moments where viewer has commented.
 *
 * POST body: { cursor?: { timestamp: number }, limit?: number }
 * Response:  {
 *   items: [{ moment, comment: { id, content, timestamp, parentCommentId }, commentedAt, authorId, momentId, commentId, canView }],
 *   nextCursor,
 *   source,
 *   totalCandidates
 * }
 */
const getCommentedMomentsPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 60)) : 30;
    const cursorTimestamp = Number(body?.cursor?.timestamp || 0);

    const db = admin.firestore();

    try {
      let query = db.collectionGroup('comments')
        .where('authorId', '==', uid)
        .orderBy('timestamp', 'desc');

      if (Number.isFinite(cursorTimestamp) && cursorTimestamp > 0) {
        query = query.startAfter(admin.firestore.Timestamp.fromMillis(cursorTimestamp));
      }

      // Wider scan because we still need privacy filtering on related moments.
      const scanLimit = Math.max(limit * 6, 120);
      const commentsSnap = await query.limit(scanLimit).get();

      if (commentsSnap.empty) {
        res.status(200).json({
          items: [],
          nextCursor: null,
          source: 'backend',
          totalCandidates: 0
        });
        return;
      }

      const viewerCtx = await buildViewerContext(uid);
      const candidates = [];
      const momentTargets = new Map(); // momentPath -> { authorId, momentId }

      for (const doc of commentsSnap.docs) {
        const pathParts = doc.ref.path.split('/');
        if (pathParts.length < 6 || pathParts[0] !== 'users' || pathParts[2] !== 'moments' || pathParts[4] !== 'comments') {
          continue;
        }

        const authorId = pathParts[1];
        const momentId = pathParts[3];
        const commentId = pathParts[5];
        const data = doc.data() || {};

        const commentedAt = data.timestamp || null;
        const content = (typeof data.content === 'string' && data.content.trim())
          ? data.content
          : (typeof data.text === 'string' ? data.text : '');

        candidates.push({
          authorId,
          momentId,
          commentId,
          commentedAt,
          content,
          parentCommentId: typeof data.parentCommentId === 'string' ? data.parentCommentId : null
        });

        const momentPath = `users/${authorId}/moments/${momentId}`;
        if (!momentTargets.has(momentPath)) {
          momentTargets.set(momentPath, { authorId, momentId });
        }
      }

      if (candidates.length === 0) {
        const lastDoc = commentsSnap.docs[commentsSnap.docs.length - 1];
        const lastTimestamp = tsToMillis(lastDoc.data().timestamp);
        res.status(200).json({
          items: [],
          nextCursor: lastTimestamp ? { timestamp: lastTimestamp } : null,
          source: 'backend',
          totalCandidates: 0
        });
        return;
      }

      const uniqueMomentRefs = [];
      const authorIds = new Set();
      for (const target of momentTargets.values()) {
        const { authorId, momentId } = target;
        authorIds.add(authorId);
        uniqueMomentRefs.push(db.doc(`users/${authorId}/moments/${momentId}`));
      }

      const authorMap = await batchLoadAuthorDocs([...authorIds]);

      const momentDocs = [];
      for (let i = 0; i < uniqueMomentRefs.length; i += 100) {
        const chunk = uniqueMomentRefs.slice(i, i + 100);
        if (chunk.length === 0) continue;
        const docs = await db.getAll(...chunk);
        docs.forEach(doc => momentDocs.push(doc));
      }

      const momentMap = new Map();
      for (const doc of momentDocs) {
        if (!doc.exists) continue;
        const parts = doc.ref.path.split('/');
        if (parts.length < 4) continue;
        const key = `${parts[1]}_${parts[3]}`;
        momentMap.set(key, doc);
      }

      const items = [];
      for (const candidate of candidates) {
        const key = `${candidate.authorId}_${candidate.momentId}`;
        const momentDoc = momentMap.get(key);
        if (!momentDoc || !momentDoc.exists) continue;

        const momentData = momentDoc.data() || {};
        if (momentData.isArchived === true) continue;
        const authorData = authorMap.get(candidate.authorId);
        if (!authorData) continue;

        const canView = await canViewerSeeMoment(
          {
            id: momentDoc.id,
            authorId: candidate.authorId,
            audience: momentData.audience,
            taggedUsers: momentData.taggedUsers,
            customListId: momentData.customListId,
            isArchived: momentData.isArchived === true
          },
          uid,
          viewerCtx,
          authorData
        );

        items.push({
          moment: canView
            ? serializeMoment(momentDoc.id, momentData)
            : serializeRestrictedMoment(momentDoc.id, momentData),
          comment: {
            id: candidate.commentId,
            content: candidate.content,
            timestamp: tsToMillis(candidate.commentedAt),
            parentCommentId: candidate.parentCommentId
          },
          commentedAt: tsToMillis(candidate.commentedAt),
          authorId: candidate.authorId,
          momentId: candidate.momentId,
          commentId: candidate.commentId,
          canView
        });

        if (items.length >= limit) break;
      }

      let nextCursor = null;
      const hasMoreScanned = commentsSnap.size >= scanLimit;
      if (hasMoreScanned) {
        const lastDoc = commentsSnap.docs[commentsSnap.docs.length - 1];
        const lastTs = tsToMillis(lastDoc.data().timestamp);
        if (lastTs) {
          nextCursor = { timestamp: lastTs };
        }
      }

      console.log(`✅ getCommentedMomentsPage: uid=${uid}, scanned=${commentsSnap.size}, candidates=${candidates.length}, returned=${items.length}`);

      res.status(200).json({
        items,
        nextCursor,
        source: 'backend',
        totalCandidates: candidates.length
      });

    } catch (error) {
      console.error('❌ getCommentedMomentsPage error:', error);
      res.status(500).json({ error: 'Commented moments fetch failed', details: error.message });
    }
  }
);

/**
 * 🤝 getSharedReactedMomentsPage — Returns shared reacted moments between viewer and another user.
 *
 * POST body: {
 *   otherUserId: string,
 *   direction?: "viewer_on_other" | "other_on_viewer",
 *   cursor?: { timestamp: number },
 *   limit?: number
 * }
 */
const getSharedReactedMomentsPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 60)) : 30;
    const cursorTimestamp = Number(body?.cursor?.timestamp || 0);

    if (!otherUserId || otherUserId === uid) {
      res.status(400).json({ error: 'Invalid otherUserId' });
      return;
    }

    const reactingUserId = direction === 'viewer_on_other' ? uid : otherUserId;
    const targetAuthorId = direction === 'viewer_on_other' ? otherUserId : uid;
    const db = admin.firestore();

    try {
      let query = db.collectionGroup('reactions')
        .where('userId', '==', reactingUserId)
        .orderBy('timestamp', 'desc');

      if (Number.isFinite(cursorTimestamp) && cursorTimestamp > 0) {
        query = query.startAfter(admin.firestore.Timestamp.fromMillis(cursorTimestamp));
      }

      const scanLimit = Math.max(limit * 6, 120);
      const reactionsSnap = await query.limit(scanLimit).get();

      if (reactionsSnap.empty) {
        res.status(200).json({ items: [], nextCursor: null, source: 'backend', totalCandidates: 0 });
        return;
      }

      const viewerCtx = await buildViewerContext(uid);
      const candidates = [];
      const seenMoments = new Set();

      for (const doc of reactionsSnap.docs) {
        const pathParts = doc.ref.path.split('/');
        if (pathParts.length < 6 || pathParts[0] !== 'users' || pathParts[2] !== 'moments') {
          continue;
        }

        const authorId = pathParts[1];
        if (authorId !== targetAuthorId) continue;

        const momentId = pathParts[3];
        const dedupeKey = `${authorId}_${momentId}`;
        if (seenMoments.has(dedupeKey)) continue;
        seenMoments.add(dedupeKey);

        const data = doc.data() || {};
        candidates.push({
          authorId,
          momentId,
          reactionType: data.reactionType || data.reaction || '',
          reactedAt: data.timestamp || null
        });
      }

      const authorMap = await batchLoadAuthorDocs([targetAuthorId]);
      const authorData = authorMap.get(targetAuthorId);
      if (!authorData || candidates.length === 0) {
        const lastDoc = reactionsSnap.docs[reactionsSnap.docs.length - 1];
        const lastTs = lastDoc ? tsToMillis(lastDoc.data().timestamp) : null;
        const hasMoreScanned = reactionsSnap.size >= scanLimit;
        res.status(200).json({
          items: [],
          nextCursor: hasMoreScanned && lastTs ? { timestamp: lastTs } : null,
          source: 'backend',
          totalCandidates: candidates.length
        });
        return;
      }

      const momentRefs = candidates.map(item => db.doc(`users/${item.authorId}/moments/${item.momentId}`));
      const momentDocs = [];
      for (let i = 0; i < momentRefs.length; i += 100) {
        const chunk = momentRefs.slice(i, i + 100);
        if (chunk.length === 0) continue;
        const docs = await db.getAll(...chunk);
        docs.forEach(doc => momentDocs.push(doc));
      }

      const momentMap = new Map();
      for (const doc of momentDocs) {
        if (!doc.exists) continue;
        const parts = doc.ref.path.split('/');
        if (parts.length < 4) continue;
        momentMap.set(`${parts[1]}_${parts[3]}`, doc);
      }

      const items = [];
      for (const candidate of candidates) {
        const key = `${candidate.authorId}_${candidate.momentId}`;
        const momentDoc = momentMap.get(key);
        if (!momentDoc || !momentDoc.exists) continue;

        const momentData = momentDoc.data() || {};
        if (momentData.isArchived === true) continue;

        const canView = await canViewerSeeMoment(
          {
            id: momentDoc.id,
            authorId: candidate.authorId,
            audience: momentData.audience,
            taggedUsers: momentData.taggedUsers,
            customListId: momentData.customListId,
            isArchived: momentData.isArchived === true
          },
          uid,
          viewerCtx,
          authorData
        );

        items.push({
          moment: canView
            ? serializeMoment(momentDoc.id, momentData)
            : serializeRestrictedMoment(momentDoc.id, momentData),
          reactionType: candidate.reactionType,
          reactedAt: tsToMillis(candidate.reactedAt),
          authorId: candidate.authorId,
          momentId: candidate.momentId,
          canView
        });

        if (items.length >= limit) break;
      }

      const lastDoc = reactionsSnap.docs[reactionsSnap.docs.length - 1];
      const lastTs = lastDoc ? tsToMillis(lastDoc.data().timestamp) : null;
      const hasMoreScanned = reactionsSnap.size >= scanLimit;

      res.status(200).json({
        items,
        nextCursor: hasMoreScanned && lastTs ? { timestamp: lastTs } : null,
        source: 'backend',
        totalCandidates: candidates.length
      });
    } catch (error) {
      console.error('❌ getSharedReactedMomentsPage error:', error);
      res.status(500).json({ error: 'Shared reacted moments fetch failed', details: error.message });
    }
  }
);

/**
 * 💬 getSharedCommentedMomentsPage — Returns shared commented moments between viewer and another user.
 */
const getSharedCommentedMomentsPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 60)) : 30;
    const cursorTimestamp = Number(body?.cursor?.timestamp || 0);

    if (!otherUserId || otherUserId === uid) {
      res.status(400).json({ error: 'Invalid otherUserId' });
      return;
    }

    const expectedMomentAuthorId = direction === 'viewer_on_other' ? otherUserId : uid;
    const commentAuthorId = direction === 'viewer_on_other' ? uid : otherUserId;
    const db = admin.firestore();

    try {
      let query = db.collection('users').doc(expectedMomentAuthorId).collection('moments')
        .orderBy('timestamp', 'desc')
        .limit(limit);

      if (Number.isFinite(cursorTimestamp) && cursorTimestamp > 0) {
        query = query.startAfter(admin.firestore.Timestamp.fromMillis(cursorTimestamp));
      }

      const snapshot = await query.get();
      if (snapshot.empty) {
        res.status(200).json({ items: [], nextCursor: null, source: 'backend', totalCandidates: 0 });
        return;
      }

      const documents = snapshot.docs;
      const last = documents[documents.length - 1];
      const viewerCtx = await buildViewerContext(uid);
      const authorMap = await batchLoadAuthorDocs([expectedMomentAuthorId]);
      const authorData = authorMap.get(expectedMomentAuthorId);
      if (!authorData) {
        res.status(200).json({ items: [], nextCursor: null, source: 'backend', totalCandidates: 0 });
        return;
      }

      let loadedComments = [];
      for (const doc of documents) {
        const momentData = doc.data() || {};
        if (momentData.isArchived === true) continue;

        const canView = await canViewerSeeMoment(
          {
            id: doc.id,
            authorId: expectedMomentAuthorId,
            audience: momentData.audience,
            taggedUsers: momentData.taggedUsers,
            customListId: momentData.customListId,
            isArchived: momentData.isArchived === true
          },
          uid,
          viewerCtx,
          authorData
        );

        const commentsSnap = await db.collection('users').doc(expectedMomentAuthorId)
          .collection('moments').doc(doc.id)
          .collection('comments')
          .where('authorId', '==', commentAuthorId)
          .get();

        for (const commentDoc of commentsSnap.docs) {
          const commentData = commentDoc.data() || {};
          loadedComments.push({
            moment: canView
              ? serializeMoment(doc.id, momentData)
              : serializeRestrictedMoment(doc.id, momentData),
            comment: {
              id: commentDoc.id,
              content: commentData.content || '',
              timestamp: tsToMillis(commentData.timestamp),
              parentCommentId: commentData.parentCommentId || null
            },
            commentedAt: tsToMillis(commentData.timestamp),
            authorId: expectedMomentAuthorId,
            momentId: doc.id,
            commentId: commentDoc.id,
            canView
          });
        }
      }

      loadedComments.sort((a, b) => (b.commentedAt || 0) - (a.commentedAt || 0));

      const nextCursor = documents.length >= limit && last
        ? { timestamp: tsToMillis(last.data().timestamp) }
        : null;

      res.status(200).json({
        items: loadedComments,
        nextCursor,
        source: 'backend',
        totalCandidates: loadedComments.length
      });
    } catch (error) {
      console.error('❌ getSharedCommentedMomentsPage error:', error);
      res.status(500).json({ error: 'Shared commented moments fetch failed', details: error.message });
    }
  }
);

/**
 * 🏷️ getSharedTaggedMomentsPage — Returns shared tagged moments between viewer and another user.
 */
const getSharedTaggedMomentsPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 60)) : 30;
    const cursorTimestamp = Number(body?.cursor?.timestamp || 0);

    if (!otherUserId || otherUserId === uid) {
      res.status(400).json({ error: 'Invalid otherUserId' });
      return;
    }

    const taggedUserId = direction === 'viewer_on_other' ? otherUserId : uid;
    const expectedAuthorId = direction === 'viewer_on_other' ? uid : otherUserId;
    const db = admin.firestore();

    try {
      let query = db.collectionGroup('moments')
        .where('taggedUsers', 'array-contains', taggedUserId)
        .orderBy('timestamp', 'desc')
        .limit(limit);

      if (Number.isFinite(cursorTimestamp) && cursorTimestamp > 0) {
        query = query.startAfter(admin.firestore.Timestamp.fromMillis(cursorTimestamp));
      }

      const snapshot = await query.get();
      if (snapshot.empty) {
        res.status(200).json({ items: [], nextCursor: null, source: 'backend', totalCandidates: 0 });
        return;
      }

      const viewerCtx = await buildViewerContext(uid);
      const authorMap = await batchLoadAuthorDocs([expectedAuthorId]);
      const authorData = authorMap.get(expectedAuthorId);
      if (!authorData) {
        res.status(200).json({ items: [], nextCursor: null, source: 'backend', totalCandidates: 0 });
        return;
      }

      const items = [];
      for (const doc of snapshot.docs) {
        const momentData = doc.data() || {};
        if (momentData.isArchived === true) continue;
        if (momentData.authorId !== expectedAuthorId) continue;

        const canView = await canViewerSeeMoment(
          {
            id: doc.id,
            authorId: expectedAuthorId,
            audience: momentData.audience,
            taggedUsers: momentData.taggedUsers,
            customListId: momentData.customListId,
            isArchived: momentData.isArchived === true
          },
          uid,
          viewerCtx,
          authorData
        );

        items.push({
          moment: canView
            ? serializeMoment(doc.id, momentData)
            : serializeRestrictedMoment(doc.id, momentData),
          taggedAt: tsToMillis(momentData.timestamp),
          authorId: expectedAuthorId,
          momentId: doc.id,
          canView
        });
      }

      const lastDoc = snapshot.docs[snapshot.docs.length - 1];
      const lastTs = lastDoc ? tsToMillis(lastDoc.data().timestamp) : null;

      res.status(200).json({
        items,
        nextCursor: snapshot.docs.length >= limit && lastTs ? { timestamp: lastTs } : null,
        source: 'backend',
        totalCandidates: items.length
      });
    } catch (error) {
      console.error('❌ getSharedTaggedMomentsPage error:', error);
      res.status(500).json({ error: 'Shared tagged moments fetch failed', details: error.message });
    }
  }
);

/**
 * 👀 getProfileVisitsPage — Returns grouped profile visits for the authenticated user.
 *
 * POST body: { limit?: number }
 * Response: { groupedVisits: [...], uniqueVisitorCount: number, source: "backend" }
 * User docs are hydrated on the client via FirestoreService.fetchUsersAsync.
 */
const getProfileVisitsPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const visitFetchLimit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 2000)) : 1000;
    const db = admin.firestore();

    try {
      const snap = await db.collection(`users/${uid}/visits`)
        .orderBy('timestamp', 'desc')
        .limit(visitFetchLimit)
        .get();

      const visits = snap.docs
        .map((doc) => {
          const data = doc.data() || {};
          const visitorId = typeof data.visitorId === 'string' ? data.visitorId.trim() : '';
          const timestampDate = asDate(data.timestamp);
          if (!visitorId || !timestampDate) return null;
          return {
            id: doc.id,
            visitorId,
            timestamp: timestampDate.getTime()
          };
        })
        .filter(Boolean);

      const groupedMap = new Map();
      for (const visit of visits) {
        if (!groupedMap.has(visit.visitorId)) {
          groupedMap.set(visit.visitorId, []);
        }
        groupedMap.get(visit.visitorId).push(visit);
      }

      const visitorIds = [...groupedMap.keys()];

      const groupedVisits = visitorIds
        .map((visitorId) => {
          const userVisits = groupedMap.get(visitorId).sort((a, b) => b.timestamp - a.timestamp);

          return {
            visitorId,
            visitCount: userVisits.length,
            lastVisit: userVisits[0].timestamp,
            visits: userVisits.map((visit) => ({
              id: visit.id,
              timestamp: visit.timestamp
            }))
          };
        })
        .sort((a, b) => b.lastVisit - a.lastVisit);

      res.status(200).json({
        groupedVisits,
        uniqueVisitorCount: groupedVisits.length,
        source: 'backend'
      });
    } catch (error) {
      console.error('❌ getProfileVisitsPage error:', error);
      res.status(500).json({ error: 'Profile visits fetch failed', details: error.message });
    }
  }
);

/**
 * 🗑️ deleteMyCommentsBatch — Deletes the viewer's selected comments (and direct replies).
 *
 * POST body: { comments: [{ authorId, momentId, commentId }] }
 */

module.exports = {
  getFeedPage,
  getStoryTray,
  getStoryRingPage,
  getAuthorStoryBundle,
  getMapMomentsPage,
  getMapStoriesPage,
  getReactedMomentsPage,
  getStickerRepliesPage,
  getTaggedMomentsPage,
  getProfileMomentsPage,
  getProfileVisitsPage,
  getVisibleHighlightsPage,
  getCommentedMomentsPage,
  getSharedReactedMomentsPage,
  getSharedCommentedMomentsPage,
  getSharedTaggedMomentsPage,
};
