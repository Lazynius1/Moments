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

const cleanupIncompleteAuthAccounts = onSchedule(
  {
    schedule: '0 4 * * 0',
    timeZone: 'Europe/Madrid',
    region: 'us-central1',
    timeoutSeconds: 540,
    memory: '512MiB',
    concurrency: 1
  },
  async () => {
    const auth = admin.auth();
    const db = admin.firestore();
    const minAgeMs = 30 * 24 * 60 * 60 * 1000;
    const now = Date.now();
    let nextPageToken;
    let deleted = 0;
    let scanned = 0;

    try {
      do {
        const listResult = await auth.listUsers(1000, nextPageToken);
        for (const userRecord of listResult.users) {
          scanned += 1;
          const createdAt = new Date(userRecord.metadata.creationTime).getTime();
          if (now - createdAt < minAgeMs) {
            continue;
          }

          const userDoc = await db.collection('users').doc(userRecord.uid).get();
          if (userDoc.exists) {
            continue;
          }

          try {
            await auth.deleteUser(userRecord.uid);
            deleted += 1;
          } catch (deleteError) {
            console.error('cleanupIncompleteAuthAccounts delete failed', userRecord.uid, deleteError);
          }
        }
        nextPageToken = listResult.pageToken;
      } while (nextPageToken);

      console.log(`cleanupIncompleteAuthAccounts scanned=${scanned} deleted=${deleted}`);
    } catch (error) {
      console.error('cleanupIncompleteAuthAccounts failed', error);
      throw error;
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Conversation Cleanup
// Cuando ambos participantes han borrado la conversación, eliminar:
//   1. Todos los mensajes de Firestore (messages, buzzEvents, messageReactions)
//   2. Todos los archivos de Firebase Storage de esa conversación (media, audio,
//      thumbnails…) — tanto los referenciados en los mensajes como cualquier
//      archivo huérfano que esté en el directorio de Storage de cada participante.
//   3. El documento de la conversación.
// Esto replica el comportamiento de WhatsApp/Instagram.
// ─────────────────────────────────────────────────────────────────────────────
const cleanupDeletedConversation = onDocumentWritten(
  {
    document: 'conversations/{conversationId}',
    memory: '512MiB',
    timeoutSeconds: 540
  },
  async (event) => {
    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const conversationId = event.params.conversationId;

    // Solo actuar en documentos que siguen existiendo (no en borrados físicos)
    const after = event.data?.after;
    if (!after || !after.exists) return;

    const data = after.data();
    if (!data) return;

    const participants = data.participants;
    if (!Array.isArray(participants) || participants.length === 0) return;

    const deletedFor = data.deletedFor;
    if (!Array.isArray(deletedFor) || deletedFor.length === 0) return;

    // Comprobar que TODOS los participantes están en deletedFor
    const allDeleted = participants.every((uid) => deletedFor.includes(uid));
    if (!allDeleted) return;

    console.log(`[cleanupDeletedConversation] All participants deleted conversation ${conversationId}. Starting full cleanup.`);

    // ─── Helpers ─────────────────────────────────────────────────────────────

    // Borra un archivo de Storage por su objectPath; ignora "not found"
    const deleteStorageFile = async (objectPath) => {
      if (!objectPath || typeof objectPath !== 'string' || objectPath.trim() === '') return;
      const path = objectPath.trim();
      try {
        await bucket.file(path).delete();
      } catch (err) {
        // Ignorar 404 (archivo ya borrado o nunca subido)
        if (err.code !== 404 && err.message && !err.message.includes('No such object')) {
          console.warn(`[cleanupDeletedConversation] Could not delete Storage file ${path}:`, err.message);
        }
      }
    };

    // Borra todos los archivos bajo un "prefijo" de Storage (equivalente a carpeta)
    const deleteStorageDirectory = async (prefix) => {
      try {
        const [files] = await bucket.getFiles({ prefix });
        if (files.length === 0) return;
        await Promise.all(files.map((f) => f.delete().catch(() => {})));
        console.log(`[cleanupDeletedConversation] Deleted ${files.length} Storage files under ${prefix}`);
      } catch (err) {
        console.warn(`[cleanupDeletedConversation] Error listing Storage files under ${prefix}:`, err.message);
      }
    };

    // ─── 1. Recoger y borrar media de cada mensaje (y sus reacciones) ──────────
    const collRef = db
      .collection('conversations')
      .doc(conversationId)
      .collection('messages');

    const storagePathsToDelete = new Set();
    let hasMore = true;
    let totalMessages = 0;
    let totalReactions = 0;

    while (hasMore) {
      const snapshot = await collRef.limit(500).get();
      if (snapshot.empty) { hasMore = false; break; }

      // Obtener las reacciones de cada mensaje en este lote de 500 en paralelo
      const reactionsPromises = snapshot.docs.map(async (messageDoc) => {
        const reactionsSnap = await messageDoc.ref.collection('messageReactions').get();
        return { messageDoc, reactionsDocs: reactionsSnap.docs };
      });
      const results = await Promise.all(reactionsPromises);

      const batch = db.batch();
      for (const { messageDoc, reactionsDocs } of results) {
        const msgData = messageDoc.data();
        // Recoger paths de Storage referenciados directamente en el mensaje
        const mediaPath = msgData.mediaObjectPath;
        const thumbPath = msgData.thumbnailObjectPath;
        if (mediaPath) storagePathsToDelete.add(mediaPath);
        if (thumbPath) storagePathsToDelete.add(thumbPath);

        // Borrar cada documento de reacción
        for (const reactionDoc of reactionsDocs) {
          batch.delete(reactionDoc.ref);
          totalReactions++;
        }

        // Borrar el mensaje
        batch.delete(messageDoc.ref);
      }
      await batch.commit();
      totalMessages += snapshot.size;
      if (snapshot.size < 500) hasMore = false;
    }
    console.log(`[cleanupDeletedConversation] Deleted ${totalMessages} messages and ${totalReactions} reactions from Firestore.`);

    // ─── 2. Borrar sub-colecciones restantes (buzzEvents, typing) ────────────
    const deleteSubcollection = async (subcollectionName) => {
      const subRef = db
        .collection('conversations')
        .doc(conversationId)
        .collection(subcollectionName);
      let hasMoreSub = true;
      let total = 0;
      while (hasMoreSub) {
        const snap = await subRef.limit(500).get();
        if (snap.empty) { hasMoreSub = false; break; }
        const b = db.batch();
        snap.docs.forEach((d) => b.delete(d.ref));
        await b.commit();
        total += snap.size;
        if (snap.size < 500) hasMoreSub = false;
      }
      console.log(`[cleanupDeletedConversation] Deleted ${total} docs from ${subcollectionName}.`);
    };

    await deleteSubcollection('buzzEvents');
    await deleteSubcollection('typing');

    // ─── 3. Borrar archivos de Storage ───────────────────────────────────────
    // 3a. Archivos referenciados en los mensajes
    await Promise.all([...storagePathsToDelete].map(deleteStorageFile));
    console.log(`[cleanupDeletedConversation] Deleted ${storagePathsToDelete.size} referenced Storage files.`);

    // 3b. Barrer el directorio de Storage de cada participante para esta conv
    //     (captura archivos huérfanos: uploads a medias que no llegaron a guardarse en Firestore)
    //     Patrón: users/{uid}/chat/{conversationId}/
    await Promise.all(
      participants.map((uid) =>
        deleteStorageDirectory(`users/${uid}/chat/${conversationId}/`)
      )
    );

    // ─── 4. Borrar el documento de la conversación ───────────────────────────
    await db.collection('conversations').doc(conversationId).delete();
    console.log(`[cleanupDeletedConversation] Conversation ${conversationId} fully deleted (Firestore + Storage).`);
  }
);


module.exports = {
  cleanupIncompleteAuthAccounts,
  cleanupDeletedConversation,
};
