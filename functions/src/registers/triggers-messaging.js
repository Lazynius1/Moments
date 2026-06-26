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

const acceptMessageRequest = onRequest(
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

    const receiverId = await verifyFirebaseAuth(req, res);
    if (!receiverId) return;

    const body = parseJsonBody(req);
    const requestId = typeof body.requestId === 'string' ? body.requestId.trim() : '';
    if (!requestId) {
      res.status(400).json({ error: 'Missing requestId' });
      return;
    }

    const db = admin.firestore();
    const requestRef = db.collection('messageRequests').doc(requestId);

    try {
      const requestData = await db.runTransaction(async (tx) => {
        const requestSnap = await tx.get(requestRef);
        if (!requestSnap.exists) {
          throw new Error('REQUEST_NOT_FOUND');
        }

        const data = requestSnap.data() || {};
        if (data.receiverId !== receiverId) {
          throw new Error('REQUEST_FORBIDDEN');
        }

        if (!data.senderId || data.createdBy !== data.senderId) {
          throw new Error('REQUEST_UNTRUSTED');
        }

        if (data.status !== 'pending' && data.status !== 'accepted') {
          throw new Error('REQUEST_NOT_PENDING');
        }

        if (data.status === 'pending') {
          tx.update(requestRef, {
            status: 'accepted',
            acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
            acceptedBy: receiverId
          });
        }

        return {
          id: requestSnap.id,
          senderId: data.senderId || '',
          receiverId: data.receiverId || '',
          createdBy: data.createdBy || '',
          message: data.message || '',
          messageType: data.messageType || 'text',
          mediaUrl: data.mediaUrl || null,
          thumbnailUrl: data.thumbnailUrl || null
        };
      });

      if (!requestData.senderId || !requestData.receiverId || requestData.createdBy !== requestData.senderId) {
        res.status(400).json({ error: 'Invalid message request', errorCode: 'REQUEST_UNTRUSTED' });
        return;
      }

      const participants = [requestData.senderId, requestData.receiverId].sort();
      const [senderDoc, receiverDoc, existingConversation] = await Promise.all([
        db.doc(`users/${requestData.senderId}`).get(),
        db.doc(`users/${requestData.receiverId}`).get(),
        findExistingDirectConversation(requestData.senderId, requestData.receiverId)
      ]);

      if (!senderDoc.exists || !receiverDoc.exists) {
        res.status(404).json({ error: 'User not found', errorCode: 'USER_NOT_FOUND' });
        return;
      }

      const senderData = senderDoc.data() || {};
      const receiverData = receiverDoc.data() || {};

      if (!isActiveUserData(senderData) || !isActiveUserData(receiverData)) {
        res.status(409).json({ error: 'One of the users is inactive', errorCode: 'INACTIVE_USER' });
        return;
      }

      if (usersAreBlocked(senderData, requestData.senderId, receiverData, requestData.receiverId)) {
        res.status(403).json({ error: 'Blocked relationship', errorCode: 'BLOCKED_RELATIONSHIP' });
        return;
      }

      const participantData = {
        [requestData.senderId]: {
          userId: requestData.senderId,
          username: senderData.username || '',
          profileImagePath: senderData.profileImagePath || '',
          lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        },
        [requestData.receiverId]: {
          userId: requestData.receiverId,
          username: receiverData.username || '',
          profileImagePath: receiverData.profileImagePath || '',
          lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        }
      };

      const conversationRef = existingConversation
        ? existingConversation.ref
        : db.collection('conversations').doc();
      const conversationId = conversationRef.id;
      const messageId = `request_${requestId}`;
      const messageRef = conversationRef.collection('messages').doc(messageId);
      const preview = buildMessageRequestConversationPreview(requestData.messageType, requestData.message);

      const batch = db.batch();
      const baseConversationData = {
        participants,
        participantData,
        lastMessage: preview,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        readStatus: {
          [requestData.senderId]: true,
          [requestData.receiverId]: true
        }
      };

      if (existingConversation) {
        batch.set(conversationRef, {
          ...baseConversationData,
          deletedFor: admin.firestore.FieldValue.arrayRemove(requestData.senderId, requestData.receiverId)
        }, { merge: true });
      } else {
        batch.set(conversationRef, baseConversationData, { merge: true });
      }

      batch.set(messageRef, {
        id: messageId,
        conversationId,
        senderId: requestData.senderId,
        content: requestData.message || '',
        type: requestData.messageType,
        status: 'sent',
        isRead: true,
        isDeleted: false,
        isViewed: false,
        processed: true,
        sourceRequestId: requestId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        ...(requestData.mediaUrl ? { mediaUrl: requestData.mediaUrl } : {}),
        ...(requestData.thumbnailUrl ? { thumbnailUrl: requestData.thumbnailUrl } : {})
      }, { merge: true });

      batch.delete(requestRef);
      await batch.commit();

      res.status(200).json({
        success: true,
        conversationId,
        messageId
      });
    } catch (error) {
      if (error.message === 'REQUEST_NOT_FOUND') {
        res.status(404).json({ error: 'Message request not found', errorCode: 'REQUEST_NOT_FOUND' });
        return;
      }
      if (error.message === 'REQUEST_FORBIDDEN') {
        res.status(403).json({ error: 'Forbidden', errorCode: 'REQUEST_FORBIDDEN' });
        return;
      }
      if (error.message === 'REQUEST_NOT_PENDING') {
        res.status(409).json({ error: 'Message request is no longer pending', errorCode: 'REQUEST_NOT_PENDING' });
        return;
      }
      if (error.message === 'REQUEST_UNTRUSTED') {
        res.status(403).json({ error: 'Untrusted message request', errorCode: 'REQUEST_UNTRUSTED' });
        return;
      }

      console.error('acceptMessageRequest error:', error);
      res.status(500).json({ error: 'Failed to accept message request', errorCode: 'REQUEST_ACCEPT_FAILED' });
    }
  }
);

// 💬 MENSAJES DIRECTOS
const onMessageAdded = onDocumentCreated('conversations/{conversationId}/messages/{messageId}', async (event) => {
  const snap = event.data;
  const { conversationId, messageId } = event.params;
  const message = snap.data();

  try {
    const conversationDoc = await admin.firestore().doc(`conversations/${conversationId}`).get();
    if (!conversationDoc.exists) return null;

    const conversationData = conversationDoc.data();
    const participants = Array.isArray(conversationData.participants) ? conversationData.participants : [];
    if (!participants.includes(message.senderId)) {
      console.warn(`⚠️ Ignorando mensaje ${messageId}: senderId no pertenece a ${conversationId}`);
      return null;
    }
    const receivers = participants.filter(p => p !== message.senderId);

    const senderDoc = await admin.firestore().doc(`users/${message.senderId}`).get();
    if (!senderDoc.exists) return null;

    const senderData = senderDoc.data();

    if (!validateUserData(senderData)) {
      return null;
    }

    if (!senderData.isActive) return null;

    // ✅ Idempotencia por mensaje
    const messageRef = admin.firestore().doc(`conversations/${conversationId}/messages/${messageId}`);
    const handled = await admin.firestore().runTransaction(async (tx) => {
      const mSnap = await tx.get(messageRef);
      if (!mSnap.exists) return true;
      if (mSnap.get('processed') === true) return true;
      tx.update(messageRef, { processed: true });
      return false;
    });
    if (handled) return null;

    // ✅ Batch fetch de receptores para reducir lecturas
    const receiverRefs = receivers.map((receiverId) => admin.firestore().doc(`users/${receiverId}`));
    const receiverDocs = await admin.firestore().getAll(...receiverRefs);

    const notifications = receiverDocs.map(async (receiverDoc) => {
      if (!receiverDoc.exists) {
        return null;
      }
      const receiverData = receiverDoc.data();
      const receiverId = receiverDoc.id;

      if (!validateUserData(receiverData)) {
        return null;
      }

      if (!receiverData.isActive) {
        return null;
      }

      const isSilencedByMuteSettings = shouldSilenceNotificationForUser(receiverData, {
        senderId: message.senderId,
        candidateTexts: [message.text, message.caption, message.type]
      });
      if (isSilencedByMuteSettings) {
        return null;
      }

      if (!receiverData.fcmToken || isDoNotDisturbActive(receiverData)) {
        return null;
      }

      // ✅ VERIFICAR SI LA CONVERSACIÓN ESTÁ SILENCIADA PARA ESTE USUARIO
      const mutedByUserIds = Array.isArray(conversationData.mutedByUserIds)
        ? conversationData.mutedByUserIds
        : [];
      const isMutedForReceiver =
        mutedByUserIds.includes(receiverId) ||
        (conversationData.isMuted === true && conversationData.mutedBy === receiverId);

      if (isMutedForReceiver) {
        return null;
      }

      const archivedByUserIds = Array.isArray(conversationData.archivedByUserIds)
        ? conversationData.archivedByUserIds
        : [];
      if (archivedByUserIds.includes(receiverId)) {
        return null;
      }

      const cleanImageUrl = senderData.profileImagePath
        ? senderData.profileImagePath.replace(':443', '')
        : null;

      // ✅ Obtener conteos actualizados para el receptor
      const [counts, unreadInConvo] = await Promise.all([
        getUnreadCounts(receiverId, { type: 'message', conversationId: conversationId }),
        getUnreadMessagesInConversation(conversationId, receiverId)
      ]);

      // Determinar clave de localización según el tipo de mensaje
      let bodyLocKey = 'notification.message.single.default';
      switch (message.type) {
        case 'text': bodyLocKey = 'notification.message.single.text'; break;
        case 'image': bodyLocKey = 'notification.message.single.photo'; break;
        case 'video': bodyLocKey = 'notification.message.single.video'; break;
        case 'audio': bodyLocKey = 'notification.message.single.audio'; break;
        case 'viewOnceImage':
        case 'viewOnceVideo': bodyLocKey = 'notification.message.single.viewOnce'; break;
        case 'moment': bodyLocKey = 'notification.message.single.moment'; break;
        default: bodyLocKey = 'notification.message.single.default';
      }

      // Si hay múltiples mensajes, usar clave plural
      let bodyLocArgs = [];
      if (unreadInConvo > 1) {
        bodyLocKey = 'notification.message.multiple';
        bodyLocArgs = [String(unreadInConvo)];
      }

      // 🔐 Vista previa E2E: el contenido sigue cifrado (el servidor no lo lee).
      // El Notification Service Extension lo descifra en el dispositivo y reemplaza
      // el cuerpo genérico (loc-key) por el texto real.
      //
      // Estrategia robusta frente al límite real de APNs (4 KB), no por longitud "a ojo":
      //  - Construimos el payload SIN encryptedContent y medimos su tamaño real serializado.
      //  - Solo embebemos el ciphertext (fast-path) si el payload total queda bajo un
      //    margen seguro. Si no cabe, lo omitimos y el NSE resuelve el texto haciendo
      //    fetch del mensaje (conversationId + messageId) y descifrando en el dispositivo.
      // view-once nunca expone media en la notificación (privacidad, igual que WhatsApp).
      const isViewOnceMessage = message.type === 'viewOnceImage'
        || message.type === 'viewOnceVideo'
        || message.type === 'ephemeral';

      // gif/sticker viajan como URL pública de Giphy (sin cifrar): el NSE la descarga
      // directamente para el adjunto. image/video usan la miniatura cifrada (hasEncryptedThumbnail).
      const publicMediaUrl = (!isViewOnceMessage && (message.type === 'gif' || message.type === 'sticker')
        && typeof message.mediaUrl === 'string')
        ? message.mediaUrl
        : '';

      const baseData = {
        type: 'new_message',
        conversationId: conversationId,
        messageId: messageId,
        senderId: message.senderId,
        targetType: 'conversation',
        targetId: conversationId,
        senderUsername: senderData.username,
        senderProfileImage: senderData.profileImagePath || '',
        messageType: message.type || 'text',
        hasEncryptedThumbnail: (!isViewOnceMessage && message.thumbnailObjectPath && message.thumbnailEncryption) ? '1' : '0',
        mediaUrl: publicMediaUrl,
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags)
      };

      const apnsPayload = {
        aps: {
          alert: {
            title: senderData.username || 'Moments',
            'loc-key': bodyLocKey,
            'loc-args': bodyLocArgs
          },
          badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
          sound: 'default',
          'mutable-content': 1,
          category: 'MESSAGE_CATEGORY',
          'thread-id': `conversation_${conversationId}`
        }
      };

      // Límite duro de APNs: 4096 bytes. Reservamos margen para overhead de FCM y claves.
      const APNS_PAYLOAD_SAFE_LIMIT = 3500;
      let encryptedContent = '';
      if (message.type === 'text' && typeof message.content === 'string' && message.content.length > 0) {
        const candidateData = { ...baseData, encryptedContent: message.content };
        const estimatedBytes =
          Buffer.byteLength(JSON.stringify(candidateData), 'utf8') +
          Buffer.byteLength(JSON.stringify(apnsPayload), 'utf8');
        if (estimatedBytes <= APNS_PAYLOAD_SAFE_LIMIT) {
          encryptedContent = message.content;
        }
      }

      const notificationMessage = {
        token: receiverData.fcmToken,
        data: { ...baseData, encryptedContent },
        apns: {
          headers: {
            'apns-collapse-id': `msg_${conversationId}`
          },
          payload: apnsPayload
        }
      };

      try {
        await admin.messaging().send(notificationMessage);
      } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
          await removeInvalidToken(receiverId, receiverData.fcmToken);
        }
        return null;
      }
    });

    await Promise.all(notifications);

  } catch (error) {
    console.error('Error sending message notification:', error);
  }
});

// 💬 REACCIONES EN MENSAJES DE CHAT — push al autor del mensaje reaccionado (anti-spam:
// solo onCreate, no self-reaction, respeta mute/DND, collapse por mensaje).
const onMessageReactionAdded = onDocumentCreated(
  'conversations/{conversationId}/messages/{messageId}/messageReactions/{reactorUserId}',
  async (event) => {
    const snap = event.data;
    const { conversationId, messageId, reactorUserId } = event.params;
    const reaction = snap.data();

    try {
      const emoji = typeof reaction.emoji === 'string' ? reaction.emoji.trim() : '';
      if (!emoji) return null;

      const reactorId = typeof reaction.userId === 'string' ? reaction.userId : reactorUserId;
      if (!reactorId) return null;

      const messageRef = admin.firestore().doc(`conversations/${conversationId}/messages/${messageId}`);
      const reactionRef = messageRef.collection('messageReactions').doc(reactorUserId);

      const [messageDoc, conversationDoc] = await Promise.all([
        messageRef.get(),
        admin.firestore().doc(`conversations/${conversationId}`).get()
      ]);

      if (!messageDoc.exists || !conversationDoc.exists) return null;

      const message = messageDoc.data();
      const conversationData = conversationDoc.data();
      const messageAuthorId = message.senderId;

      if (!messageAuthorId || messageAuthorId === reactorId) {
        return null;
      }

      const participants = Array.isArray(conversationData.participants) ? conversationData.participants : [];
      if (!participants.includes(reactorId) || !participants.includes(messageAuthorId)) {
        return null;
      }

      const handled = await admin.firestore().runTransaction(async (tx) => {
        const reactionSnap = await tx.get(reactionRef);
        if (!reactionSnap.exists) return true;
        if (reactionSnap.get('processed') === true) return true;
        return false;
      });
      if (handled) return null;

      const [reacterDoc, authorDoc] = await Promise.all([
        admin.firestore().doc(`users/${reactorId}`).get(),
        admin.firestore().doc(`users/${messageAuthorId}`).get()
      ]);

      if (!reacterDoc.exists || !authorDoc.exists) return null;

      const reacterData = reacterDoc.data();
      const authorData = authorDoc.data();

      if (!validateUserData(reacterData) || !validateUserData(authorData)) return null;
      if (!reacterData.isActive || !authorData.isActive) return null;

      const isSilencedByMuteSettings = shouldSilenceNotificationForUser(authorData, {
        senderId: reactorId,
        candidateTexts: [emoji, message.type]
      });
      if (isSilencedByMuteSettings) return null;

      if (!authorData.fcmToken || isDoNotDisturbActive(authorData)) return null;

      const mutedByUserIds = Array.isArray(conversationData.mutedByUserIds)
        ? conversationData.mutedByUserIds
        : [];
      const isMutedForAuthor =
        mutedByUserIds.includes(messageAuthorId) ||
        (conversationData.isMuted === true && conversationData.mutedBy === messageAuthorId);
      if (isMutedForAuthor) return null;

      if (!notificationTypeEnabled(authorData, 'messageReaction')) return null;

      const [counts, reactionSummary] = await Promise.all([
        getUnreadCounts(messageAuthorId, {
          type: 'message_reaction',
          conversationId
        }),
        getUnreadReactionSummary(conversationId, messageAuthorId, conversationData)
      ]);

      const unreadReactedCount = reactionSummary.count;
      const isPlural = unreadReactedCount > 1;
      const emojiList = reactionSummary.emojis.length > 0
        ? reactionSummary.emojis.join(', ')
        : emoji;

      let bodyLocKey = isPlural
        ? 'notification.chatReaction.multiple'
        : 'notification.chatReaction.single';
      const bodyLocArgs = isPlural ? [emojiList] : [emoji];

      const baseData = {
        type: 'message_reaction',
        conversationId,
        messageId,
        targetMessageId: messageId,
        senderId: reactorId,
        targetType: 'conversation',
        targetId: conversationId,
        senderUsername: reacterData.username || '',
        senderProfileImage: reacterData.profileImagePath || '',
        reactionEmoji: emoji,
        messageType: message.type || 'text',
        isReactionPlural: isPlural ? '1' : '0',
        reactionEmojis: emojiList,
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags)
      };

      const isTextReaction = !isPlural && message.type === 'text';

      const apnsPayload = {
        aps: {
          alert: {
            title: reacterData.username || 'Moments',
            'loc-key': bodyLocKey,
            'loc-args': bodyLocArgs
          },
          badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
          sound: 'default',
          'mutable-content': isTextReaction ? 1 : 0,
          'thread-id': `conversation_${conversationId}`
        }
      };

      if (isTextReaction && typeof message.content === 'string' && message.content.length > 0) {
        const APNS_PAYLOAD_SAFE_LIMIT = 3500;
        const candidateData = { ...baseData, encryptedContent: message.content };
        const estimatedBytes =
          Buffer.byteLength(JSON.stringify(candidateData), 'utf8') +
          Buffer.byteLength(JSON.stringify(apnsPayload), 'utf8');
        if (estimatedBytes <= APNS_PAYLOAD_SAFE_LIMIT) {
          baseData.encryptedContent = message.content;
        }
      }

      const notificationMessage = {
        token: authorData.fcmToken,
        data: baseData,
        apns: {
          headers: {
            'apns-collapse-id': apnsCollapseId('rx', conversationId)
          },
          payload: apnsPayload
        }
      };

      try {
        await admin.messaging().send(notificationMessage);
        await reactionRef.update({
          processed: true,
          processedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      } catch (error) {
        console.error('Error sending chat reaction push:', error);
        if (error.code === 'messaging/registration-token-not-registered') {
          await removeInvalidToken(messageAuthorId, authorData.fcmToken);
        }
        return null;
      }
    } catch (error) {
      console.error('Error sending chat reaction notification:', error);
    }

    return null;
  }
);

// 📳 ZUMBIDOS EN CHAT — push al otro participante (respeta mute del chat y buzzPreferences).
const onBuzzEventCreated = onDocumentCreated(
  'conversations/{conversationId}/buzzEvents/{buzzId}',
  async (event) => {
    const snap = event.data;
    const { conversationId, buzzId } = event.params;
    const buzz = snap.data();

    try {
      if (!buzz || buzz.type !== 'buzz') return null;

      const senderId = typeof buzz.senderId === 'string' ? buzz.senderId : '';
      if (!senderId) return null;

      const buzzRef = admin.firestore().doc(`conversations/${conversationId}/buzzEvents/${buzzId}`);
      const handled = await admin.firestore().runTransaction(async (tx) => {
        const buzzSnap = await tx.get(buzzRef);
        if (!buzzSnap.exists) return true;
        if (buzzSnap.get('processed') === true) return true;
        return false;
      });
      if (handled) return null;

      const conversationDoc = await admin.firestore().doc(`conversations/${conversationId}`).get();
      if (!conversationDoc.exists) return null;

      const conversationData = conversationDoc.data();
      const participants = Array.isArray(conversationData.participants) ? conversationData.participants : [];
      if (!participants.includes(senderId)) return null;

      const receivers = participants.filter((participantId) => participantId !== senderId);
      if (receivers.length === 0) return null;

      const senderDoc = await admin.firestore().doc(`users/${senderId}`).get();
      if (!senderDoc.exists) return null;

      const senderData = senderDoc.data();
      if (!validateUserData(senderData) || !senderData.isActive) return null;

      const receiverRefs = receivers.map((receiverId) => admin.firestore().doc(`users/${receiverId}`));
      const receiverDocs = await admin.firestore().getAll(...receiverRefs);

      const buzzPreferences = conversationData.buzzPreferences && typeof conversationData.buzzPreferences === 'object'
        ? conversationData.buzzPreferences
        : {};
      const mutedByUserIds = Array.isArray(conversationData.mutedByUserIds)
        ? conversationData.mutedByUserIds
        : [];

      await Promise.all(receiverDocs.map(async (receiverDoc) => {
        if (!receiverDoc.exists) return null;

        const receiverId = receiverDoc.id;
        const receiverData = receiverDoc.data();

        if (!validateUserData(receiverData) || !receiverData.isActive) return null;

        if (buzzPreferences[receiverId] === false) return null;

        const isMutedForReceiver =
          mutedByUserIds.includes(receiverId) ||
          (conversationData.isMuted === true && conversationData.mutedBy === receiverId);
        if (isMutedForReceiver) return null;

        const archivedByUserIds = Array.isArray(conversationData.archivedByUserIds)
          ? conversationData.archivedByUserIds
          : [];
        if (archivedByUserIds.includes(receiverId)) return null;

        const isSilencedByMuteSettings = shouldSilenceNotificationForUser(receiverData, {
          senderId,
          candidateTexts: ['buzz', 'zumbido']
        });
        if (isSilencedByMuteSettings) return null;

        if (!receiverData.fcmToken || isDoNotDisturbActive(receiverData)) return null;
        if (!notificationTypeEnabled(receiverData, 'chatBuzz')) return null;

        const counts = await getUnreadCounts(receiverId, {
          type: 'chat_buzz',
          conversationId
        });

        const baseData = {
          type: 'chat_buzz',
          conversationId,
          buzzEventId: buzzId,
          senderId,
          targetType: 'conversation',
          targetId: conversationId,
          senderUsername: senderData.username || '',
          senderProfileImage: senderData.profileImagePath || '',
          unreadMessages: String(counts.unreadMessages),
          unreadNotifications: String(counts.unreadNotifications),
          unreadEchoes: String(counts.unreadEchoes),
          unreadTags: String(counts.unreadTags)
        };

        const apnsPayload = {
          aps: {
            alert: {
              title: senderData.username || 'Moments',
              'loc-key': 'notification.chatBuzz.single',
              'loc-args': []
            },
            badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
            sound: 'default',
            'mutable-content': 0,
            'thread-id': `conversation_${conversationId}`
          }
        };

        const notificationMessage = {
          token: receiverData.fcmToken,
          data: baseData,
          apns: {
            headers: {
              'apns-collapse-id': apnsCollapseId('bz', conversationId)
            },
            payload: apnsPayload
          }
        };

        try {
          await admin.messaging().send(notificationMessage);
        } catch (error) {
          if (error.code === 'messaging/registration-token-not-registered') {
            await removeInvalidToken(receiverId, receiverData.fcmToken);
          }
        }

        return null;
      }));

      await buzzRef.update({
        processed: true,
        processedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } catch (error) {
      console.error('Error sending chat buzz notification:', error);
    }

    return null;
  }
);

// 📖 REACCIONES EN HISTORIAS (1 doc por reactor; update solo notifica si cambia el emoji)
const onStoryReactionAdded = onDocumentWritten('users/{userId}/stories/{storyId}/reactions/{reactionId}', async (event) => {
  const beforeSnap = event.data.before;
  const afterSnap = event.data.after;
  const { userId, storyId, reactionId } = event.params;

  if (!afterSnap.exists) return null;

  const reaction = afterSnap.data();
  const previousReaction = beforeSnap.exists ? beforeSnap.data() : null;

  // Mismo emoji en un update (p. ej. re-tap): no spamear push ni reescribir in-app.
  if (previousReaction && previousReaction.reaction === reaction.reaction) {
    return null;
  }

  try {
    if (reaction.userId === userId) return null;

    const [reacterDoc, storyOwnerDoc] = await Promise.all([
      admin.firestore().doc(`users/${reaction.userId}`).get(),
      admin.firestore().doc(`users/${userId}`).get()
    ]);

    if (!reacterDoc.exists || !storyOwnerDoc.exists) return null;

    const reacterData = reacterDoc.data();
    const storyOwnerData = storyOwnerDoc.data();

    if (!validateUserData(reacterData) || !validateUserData(storyOwnerData)) {
      console.warn('⚠️ Datos de usuario incompletos para reacción de historia');
      return null;
    }

    if (!reacterData.isActive || !storyOwnerData.isActive) return null;

    const fcmToken = storyOwnerData.fcmToken || null;
    const shouldSendPush = Boolean(fcmToken) && !isDoNotDisturbActive(storyOwnerData) && notificationTypeEnabled(storyOwnerData, 'storyReaction');

    const emoji = reaction.reaction || '❤️';

    const cleanImageUrl = reacterData.profileImagePath
      ? reacterData.profileImagePath.replace(':443', '')
      : null;

    const isSilencedByMuteSettings = shouldSilenceNotificationForUser(storyOwnerData, {
      senderId: reaction.userId,
      candidateTexts: [reaction.reaction]
    });
    if (isSilencedByMuteSettings) {
      return null;
    }

    // ✅ Obtener conteos actualizados para el Widget + preview de la historia
    const [counts, reactionCount, storySnap] = await Promise.all([
      getUnreadCounts(userId, { type: 'notification', notificationType: 'storyReaction', notificationId: reactionId }),
      getPendingStoryReactionCount(userId, storyId),
      admin.firestore().doc(`users/${userId}/stories/${storyId}`).get()
    ]);

    const storyPreviewUrl = storySnap.exists ? pickStoryPreviewUrl(storySnap.data()) : null;

    // Determinar claves de localización
    let titleLocKey, titleLocArgs, bodyLocKey, bodyLocArgs;
    if (reactionCount > 1) {
      titleLocKey = 'notification.storyReaction.multiple.title';
      titleLocArgs = [reacterData.username, String(reactionCount - 1)];
      bodyLocKey = 'notification.storyReaction.multiple.body';
      bodyLocArgs = [String(reactionCount)];
    } else {
      titleLocKey = 'notification.storyReaction.single.title';
      titleLocArgs = [reacterData.username, emoji];
      bodyLocKey = 'notification.storyReaction.single.body';
      bodyLocArgs = [];
    }

    const message = {
      token: fcmToken,
      data: {
        type: 'story_reaction',
        storyId: storyId,
        userId: reaction.userId,
        reaction: reaction.reaction,
        storyOwnerId: userId,
        targetType: 'notification',
        targetId: storyId,
        senderUsername: reacterData.username,
        senderProfileImage: reacterData.profileImagePath || '',
        mediaUrl: storyPreviewUrl || '',
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags),
      },
      apns: {
        headers: {
          'apns-collapse-id': `story_reaction_${storyId}`
        },
        payload: {
          aps: {
            alert: {
              'title-loc-key': titleLocKey,
              'title-loc-args': titleLocArgs,
              'loc-key': bodyLocKey,
              'loc-args': bodyLocArgs
            },
            badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
            sound: 'default',
            'mutable-content': 1,
            'thread-id': `story_reactions_${storyId}`
          }
        }
      }
    };

    if (shouldSendPush) {
      try {
        await admin.messaging().send(message);
        console.log(`✅ Notificación de reacción a historia enviada: ${reacterData.username} -> ${storyOwnerData.username} (${emoji})`);
      } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
          await removeInvalidToken(userId, fcmToken);
        }
        throw error;
      }
    }

    // ID estable: una notificación por reactor y por historia.
    // Evita que la colección crezca sin límite si alguien reacciona/quita varias veces.
    const storyReactionNotificationId = `storyReaction_${storyId}_${reaction.userId}`;
    await admin.firestore()
      .doc(`users/${userId}/notifications/${storyReactionNotificationId}`)
      .set({
        type: 'storyReaction',
        senderId: reaction.userId,
        senderUsername: reacterData.username,
        senderProfileImage: reacterData.profileImagePath || '',
        storyId: storyId,
        storyAuthorId: userId,
        storyPreviewUrl: storyPreviewUrl || null,
        reaction: reaction.reaction,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isPending: true
      }, { merge: true });

  } catch (error) {
    console.error('❌ Error sending story reaction notification:', error);
  }
});

// 🔔 SOLICITUDES DE SEGUIMIENTO
const onFollowRequestReceived = onDocumentCreated('users/{userId}/receivedFollowRequests/{requestId}', async (event) => {
  const snap = event.data;
  const { userId, requestId } = event.params;
  const request = snap.data();

  try {
    const [requesterDoc, userDoc] = await Promise.all([
      admin.firestore().doc(`users/${request.senderId}`).get(),
      admin.firestore().doc(`users/${userId}`).get()
    ]);

    if (!requesterDoc.exists || !userDoc.exists) return null;

    const requesterData = requesterDoc.data();
    const userData = userDoc.data();

    if (!validateUserData(requesterData) || !validateUserData(userData)) {
      console.warn('⚠️ Datos de usuario incompletos para solicitud');
      return null;
    }

    if (!requesterData.isActive || !userData.isActive) return null;

    const fcmToken = userData.fcmToken || null;
    const shouldSendPush = Boolean(fcmToken) && !isDoNotDisturbActive(userData) && notificationTypeEnabled(userData, 'followRequest');

    const cleanImageUrl = requesterData.profileImagePath
      ? requesterData.profileImagePath.replace(':443', '')
      : null;

    const isSilencedByMuteSettings = shouldSilenceNotificationForUser(userData, {
      senderId: request.senderId,
      candidateTexts: [requesterData.username]
    });
    if (isSilencedByMuteSettings) {
      return null;
    }

    // ✅ Obtener conteos actualizados para el Widget
    const [counts, requestCount] = await Promise.all([
      getUnreadCounts(userId, { type: 'notification', notificationType: 'followRequest' }),
      getPendingFollowRequestCount(userId)
    ]);

    // Determinar claves de localización
    let titleLocKey, titleLocArgs, bodyLocKey, bodyLocArgs;
    if (requestCount > 1) {
      titleLocKey = 'notification.followRequest.multiple.title';
      titleLocArgs = [requesterData.username, String(requestCount - 1)];
      bodyLocKey = 'notification.followRequest.multiple.body';
      bodyLocArgs = [String(requestCount)];
    } else {
      titleLocKey = 'notification.followRequest.single.title';
      titleLocArgs = [requesterData.username];
      bodyLocKey = 'notification.followRequest.single.body';
      bodyLocArgs = [];
    }

    const message = {
      token: fcmToken,
      data: {
        type: 'follow_request',
        requestId: requestId,
        senderId: request.senderId,
        userId: userId,
        targetType: 'follow_requests',
        targetId: requestId,
        senderUsername: requesterData.username,
        senderProfileImage: requesterData.profileImagePath || '',
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags),
      },
      apns: {
        headers: {
          'apns-collapse-id': `follow_request_${userId}`
        },
        payload: {
          aps: {
            alert: {
              'title-loc-key': titleLocKey,
              'title-loc-args': titleLocArgs,
              'loc-key': bodyLocKey,
              'loc-args': bodyLocArgs
            },
            badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
            sound: 'default',
            'mutable-content': 1,
            'thread-id': `follow_requests_${userId}`
          }
        }
      }
    };

    if (shouldSendPush) {
      try {
        await admin.messaging().send(message);
        console.log(`✅ Notificación de solicitud enviada: ${requesterData.username} -> ${userData.username}`);
      } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
          await removeInvalidToken(userId, fcmToken);
        }
        throw error;
      }
    }

    await upsertSocialNotification(userId, socialNotificationDocId('followRequest', request.senderId), {
      type: 'followRequest',
      senderId: request.senderId,
      senderUsername: requesterData.username,
      senderProfileImage: requesterData.profileImagePath || '',
      requestId: requestId
    });

  } catch (error) {
    console.error('❌ Error sending follow request notification:', error);
  }
});

// 📩 SOLICITUD CANCELADA / RECHAZADA: limpiar notificación followRequest
const onFollowRequestRemoved = onDocumentDeleted('users/{userId}/receivedFollowRequests/{requestId}', async (event) => {
  const snap = event.data;
  const { userId } = event.params;
  const request = snap?.data() || {};
  const senderId = typeof request.senderId === 'string' ? request.senderId : '';

  if (!senderId) {
    return null;
  }

  try {
    await purgeSocialNotifications(userId, { type: 'followRequest', senderId });
    console.log(`🧹 Follow request notification purged: ${senderId} -> ${userId}`);
  } catch (error) {
    console.error('❌ Error purging follow request notification:', error);
  }

  return null;
});

// 🔔 MENCIONES EN CUALQUIER CONTENIDO (HISTORIAS, MOMENTOS, COMENTARIOS)
// 🏷️ MENTIONS + PHOTO TAGS
// ✅ ELIMINADAS: exports.onMentionNotification y exports.onPhotoTagNotification
// Ahora están integradas en exports.onNotificationCreated (arriba) como
// handleMentionPush() y handlePhotoTagPush() respectivamente.
// Esto reduce invocaciones de Cloud Functions de 3x a 1x por notificación.

// 🧹 LIMPIEZA DE NOTIFICACIONES HUÉRFANAS
// Cuando se borra un momento / historia / comentario, las notificaciones asociadas
// (reacción, comentario, like, mención, etiqueta, reacción a historia) quedan huérfanas
// en los destinatarios. Usamos collectionGroup (igualdad simple → índice automático)
// para purgarlas allá donde estén.
async function purgeNotificationsByField(field, value) {
  if (!field || !value) return 0;
  let totalDeleted = 0;
  // Iterar en lotes hasta vaciar.
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snapshot = await admin.firestore()
      .collectionGroup('notifications')
      .where(field, '==', value)
      .limit(400)
      .get();

    if (snapshot.empty) break;

    const batch = admin.firestore().batch();
    snapshot.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    totalDeleted += snapshot.size;

    if (snapshot.size < 400) break;
  }
  if (totalDeleted > 0) {
    console.log(`🧹 Purga de notificaciones por ${field}=${value}: ${totalDeleted} eliminadas`);
  }
  return totalDeleted;
}

function echoHasMinimumMomentParticipants(echo) {
  const participantCount = new Set((echo?.moments || []).map((moment) => moment.authorId).filter(Boolean)).size;
  return participantCount >= 2;
}

async function reconcileEchoAfterMomentDeletion({ momentId, authorId }) {
  if (!momentId || !authorId) return 0;

  const matchingEchoes = await admin.firestore()
    .collection('echoes')
    .where('participantIds', 'array-contains', authorId)
    .get();

  let updatedCount = 0;

  for (const echoDoc of matchingEchoes.docs) {
    const echo = echoDoc.data() || {};
    const previousMoments = Array.isArray(echo.moments) ? echo.moments : [];
    const remainingMoments = previousMoments.filter((momentRef) => {
      if (!momentRef || typeof momentRef !== 'object') return false;
      return !(momentRef.momentId === momentId && momentRef.authorId === authorId);
    });

    if (remainingMoments.length === previousMoments.length) {
      continue;
    }

    const remainingAuthorIds = new Set(
      remainingMoments
        .map((momentRef) => momentRef?.authorId)
        .filter(Boolean)
    );

    const previousParticipants = Array.isArray(echo.participants) ? echo.participants : [];
    const remainingParticipants = previousParticipants.filter((participant) => remainingAuthorIds.has(participant?.userId));
    const acceptedParticipantCount = remainingParticipants.filter((participant) => participant?.status === 'accepted').length;
    const expiresAtMs = echo.expiresAt?.toDate ? echo.expiresAt.toDate().getTime() : 0;
    const isWithinWindow = expiresAtMs > Date.now();

    if (remainingParticipants.length === 0) {
      await echoDoc.ref.delete();
      updatedCount += 1;
      continue;
    }

    if (isWithinWindow && !echoHasMinimumMomentParticipants({ moments: remainingMoments })) {
      await echoDoc.ref.delete();
      updatedCount += 1;
      continue;
    }

    const nextPayload = {
      moments: remainingMoments,
      participants: remainingParticipants,
      participantIds: remainingParticipants.map((participant) => participant.userId)
    };

    if (echo.status === 'active' && acceptedParticipantCount < 2) {
      nextPayload.status = 'expired';
    }

    await echoDoc.ref.update(nextPayload);
    updatedCount += 1;
  }

  if (updatedCount > 0) {
    console.log(`🪞 Echoes reconciliados tras borrar moment ${momentId}: ${updatedCount}`);
  }

  return updatedCount;
}


module.exports = {
  acceptMessageRequest,
  onMessageAdded,
  onMessageReactionAdded,
  onBuzzEventCreated,
  onStoryReactionAdded,
  onFollowRequestReceived,
  onFollowRequestRemoved,
};
