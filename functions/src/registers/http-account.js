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

const optOutBestFriends = onRequest(
  {
    timeoutSeconds: 30
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

    const requesterId = await verifyFirebaseAuth(req, res);
    if (!requesterId) return;

    const body = parseJsonBody(req);
    const ownerId = typeof body.ownerId === 'string' ? body.ownerId.trim() : '';

    if (!ownerId) {
      res.status(400).json({ error: 'Missing ownerId' });
      return;
    }

    if (ownerId === requesterId) {
      res.status(400).json({ error: 'Invalid ownerId' });
      return;
    }

    try {
      const ownerRef = admin.firestore().collection('users').doc(ownerId);

      await admin.firestore().runTransaction(async (tx) => {
        const ownerSnap = await tx.get(ownerRef);
        if (!ownerSnap.exists) {
          throw new Error('Owner not found');
        }

        const ownerData = ownerSnap.data() || {};
        const bestFriends = Array.isArray(ownerData.bestFriends) ? ownerData.bestFriends : [];

        if (bestFriends.includes(requesterId)) {
          tx.update(ownerRef, {
            bestFriends: admin.firestore.FieldValue.arrayRemove(requesterId),
            bestFriendsUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
          });
        }
      });

      res.status(200).json({ success: true });
    } catch (error) {
      console.error('optOutBestFriends error:', error);
      res.status(500).json({ error: 'Failed to opt out from best friends' });
    }
  }
);

// ✅ ACCOUNT DELETION: trusted backend cascade for permanent account deletion
const deleteMyAccount = onRequest(
  {
    timeoutSeconds: 540,
    memory: '1GiB'
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

    const uid = await verifyFirebaseAuth(req, res, {
      checkRevoked: true,
      requireRecentAuth: true
    });
    if (!uid) return;

    const db = admin.firestore();
    const fieldValue = admin.firestore.FieldValue;
    const stats = {
      conversationsMarked: 0,
      relationshipRefsDeleted: 0,
      relationshipArraysUpdated: 0,
      collectionDocsDeleted: 0,
      collectionDocsUpdated: 0,
      storagePrefixesRequested: 0
    };

    const commitBatches = async (operations) => {
      let batch = db.batch();
      let count = 0;

      for (const operation of operations) {
        operation(batch);
        count += 1;

        if (count >= 450) {
          await batch.commit();
          batch = db.batch();
          count = 0;
        }
      }

      if (count > 0) {
        await batch.commit();
      }
    };

    const deleteQueryDocs = async (query) => {
      let deleted = 0;
      while (true) {
        const snap = await query.limit(300).get();
        if (snap.empty) break;

        await commitBatches(snap.docs.map((doc) => (batch) => batch.delete(doc.ref)));
        deleted += snap.size;

        if (snap.size < 300) break;
      }
      stats.collectionDocsDeleted += deleted;
      return deleted;
    };

    const updateQueryDocs = async (query, updateData) => {
      let updated = 0;
      while (true) {
        const snap = await query.limit(300).get();
        if (snap.empty) break;

        await commitBatches(snap.docs.map((doc) => (batch) => batch.update(doc.ref, updateData)));
        updated += snap.size;

        if (snap.size < 300) break;
      }
      stats.collectionDocsUpdated += updated;
      return updated;
    };

    const runNamedCleanup = async (name, action) => {
      try {
        return await action();
      } catch (error) {
        console.error(`❌ deleteMyAccount cleanup failed [${name}] for uid=${uid}:`, error);
        throw error;
      }
    };

    const deleteStoragePrefix = async (prefix) => {
      try {
        await admin.storage().bucket().deleteFiles({ prefix, force: true });
        stats.storagePrefixesRequested += 1;
      } catch (error) {
        console.warn(`deleteMyAccount: storage cleanup skipped for ${prefix}`, error.message);
      }
    };

    try {
      const userRef = db.collection('users').doc(uid);
      const userSnap = await userRef.get();
      const userData = userSnap.exists ? (userSnap.data() || {}) : {};
      const rawUsername = userData.username;
      const normalizedUsername = typeof rawUsername === 'string' ? rawUsername.trim().toLowerCase() : '';

      if (userSnap.exists) {
        await userRef.set({
          isActive: false,
          isDeleted: true,
          accountDeletion: {
            status: 'processing',
            requestedAt: fieldValue.serverTimestamp(),
            source: 'settings'
          }
        }, { merge: true });
      }

      const usersSnap = await db.collection('users').get();
      const relationshipOps = [];

      for (const doc of usersSnap.docs) {
        if (doc.id === uid) continue;

        const data = doc.data() || {};
        const updateData = {};
        const muteSettings = data.muteSettings || {};

        if (Array.isArray(data.bestFriends) && data.bestFriends.includes(uid)) {
          updateData.bestFriends = fieldValue.arrayRemove(uid);
        }
        if (Array.isArray(data.blockedUsers) && data.blockedUsers.includes(uid)) {
          updateData.blockedUsers = fieldValue.arrayRemove(uid);
        }
        if (Array.isArray(muteSettings.mutedUsers) && muteSettings.mutedUsers.includes(uid)) {
          updateData['muteSettings.mutedUsers'] = fieldValue.arrayRemove(uid);
        }

        if (Object.keys(updateData).length > 0) {
          relationshipOps.push((batch) => batch.update(doc.ref, updateData));
          stats.relationshipArraysUpdated += 1;
        }

        relationshipOps.push((batch) => batch.delete(doc.ref.collection('followers').doc(uid)));
        relationshipOps.push((batch) => batch.delete(doc.ref.collection('following').doc(uid)));
        relationshipOps.push((batch) => batch.delete(doc.ref.collection('mutuals').doc(uid)));
        stats.relationshipRefsDeleted += 3;
      }

      await commitBatches(relationshipOps);

      await Promise.all([
        runNamedCleanup('customAudienceLists.members', () => updateQueryDocs(
          db.collectionGroup('customAudienceLists').where('members', 'array-contains', uid),
          { members: fieldValue.arrayRemove(uid), updatedAt: fieldValue.serverTimestamp() }
        )),
        runNamedCleanup('customAudiences.allowedUsers', () => updateQueryDocs(
          db.collectionGroup('customAudiences').where('allowedUsers', 'array-contains', uid),
          { allowedUsers: fieldValue.arrayRemove(uid), lastUpdated: fieldValue.serverTimestamp() }
        )),
        runNamedCleanup('sentFollowRequests.senderId', () => deleteQueryDocs(db.collectionGroup('sentFollowRequests').where('senderId', '==', uid))),
        runNamedCleanup('sentFollowRequests.recipientId', () => deleteQueryDocs(db.collectionGroup('sentFollowRequests').where('recipientId', '==', uid))),
        runNamedCleanup('receivedFollowRequests.senderId', () => deleteQueryDocs(db.collectionGroup('receivedFollowRequests').where('senderId', '==', uid))),
        runNamedCleanup('receivedFollowRequests.recipientId', () => deleteQueryDocs(db.collectionGroup('receivedFollowRequests').where('recipientId', '==', uid))),
        runNamedCleanup('notifications.senderId', () => deleteQueryDocs(db.collectionGroup('notifications').where('senderId', '==', uid))),
        runNamedCleanup('comments.authorId', () => deleteQueryDocs(db.collectionGroup('comments').where('authorId', '==', uid))),
        runNamedCleanup('reactions.userId', () => deleteQueryDocs(db.collectionGroup('reactions').where('userId', '==', uid))),
        runNamedCleanup('customaudience.userId', () => deleteQueryDocs(db.collection('customaudience').where('userId', '==', uid))),
        runNamedCleanup('dailystats.userId', () => deleteQueryDocs(db.collection('dailystats').where('userId', '==', uid))),
        runNamedCleanup('loginActivity.userId', () => deleteQueryDocs(db.collection('loginActivity').where('userId', '==', uid))),
        runNamedCleanup('novamemory.userId', () => deleteQueryDocs(db.collection('novamemory').where('userId', '==', uid))),
        runNamedCleanup('visitorsummaries.userId', () => deleteQueryDocs(db.collection('visitorsummaries').where('userId', '==', uid))),
        runNamedCleanup('visits.userId', () => deleteQueryDocs(db.collection('visits').where('userId', '==', uid))),
        runNamedCleanup('recommendationHidden', () => deleteQueryDocs(userRef.collection('recommendationHidden'))),
        runNamedCleanup('recommendationSessions', () => deleteQueryDocs(userRef.collection('recommendationSessions'))),
        runNamedCleanup('exploreRecommendationSessions', () => deleteQueryDocs(userRef.collection('exploreRecommendationSessions')))
      ]);

      const conversationsSnap = await runNamedCleanup('conversations.participants', () => db.collection('conversations')
        .where('participants', 'array-contains', uid)
        .get());

      await commitBatches(conversationsSnap.docs.map((doc) => (batch) => batch.update(doc.ref, {
        unavailableParticipantIds: fieldValue.arrayUnion(uid),
        deletedParticipantIds: fieldValue.arrayUnion(uid),
        [`participantData.${uid}.isDeleted`]: true,
        [`participantData.${uid}.isActive`]: false,
        [`participantData.${uid}.profileImagePath`]: '',
        [`participantData.${uid}.deletedAt`]: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp()
      })));
      stats.conversationsMarked += conversationsSnap.size;

      await Promise.all([
        runNamedCleanup('typing.userId', () => deleteQueryDocs(db.collectionGroup('typing').where('userId', '==', uid))),
        deleteStoragePrefix(`users/${uid}/`),
        deleteStoragePrefix(`profile_images/${uid}/`),
        deleteStoragePrefix(`moments/${uid}/`),
        deleteStoragePrefix(`stories/${uid}/`),
        deleteStoragePrefix(`messages/${uid}/`)
      ]);

      if (normalizedUsername) {
        const usernameRef = db.collection('usernames').doc(normalizedUsername);
        const usernameSnap = await usernameRef.get();
        const usernameOwnerId = usernameSnap.exists ? usernameSnap.get('userId') : null;

        if (usernameOwnerId === uid) {
          await usernameRef.delete();
        } else if (usernameSnap.exists) {
          console.warn(`deleteMyAccount: skipped username cleanup for ${normalizedUsername}; owner ${usernameOwnerId || 'unknown'} does not match uid=${uid}`);
        }
      }

      if (typeof db.recursiveDelete === 'function') {
        await db.recursiveDelete(userRef);
      } else {
        await userRef.delete();
      }

      try {
        await admin.auth().deleteUser(uid);
      } catch (authError) {
        if (authError.code !== 'auth/user-not-found') {
          throw authError;
        }
      }

      console.log(`✅ deleteMyAccount completed for uid=${uid}`, stats);
      res.status(200).json({ success: true, stats });
    } catch (error) {
      console.error(`❌ deleteMyAccount failed for uid=${uid}:`, error);
      res.status(500).json({ error: 'Failed to delete account' });
    }
  }
);


module.exports = {
  optOutBestFriends,
  deleteMyAccount,
};
