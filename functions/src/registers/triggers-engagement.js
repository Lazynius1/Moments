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

const onMomentReactionAdded = onDocumentCreated('users/{userId}/moments/{momentId}/reactions/{reactionId}', async (event) => {
  const snap = event.data;
  const { userId, momentId, reactionId } = event.params;
  const reaction = snap.data();

  try {
    // No notificar si te reaccionas a ti mismo
    if (reaction.userId === userId) return null;

    // Obtener datos del usuario que reaccionó y del dueño del momento
    const [reacterDoc, momentOwnerDoc, momentDoc] = await Promise.all([
      admin.firestore().doc(`users/${reaction.userId}`).get(),
      admin.firestore().doc(`users/${userId}`).get(),
      admin.firestore().doc(`users/${userId}/moments/${momentId}`).get()
    ]);

    if (!reacterDoc.exists || !momentOwnerDoc.exists || !momentDoc.exists) {
      console.warn('⚠️ Documento no encontrado');
      return null;
    }

    const reacterData = reacterDoc.data();
    const momentOwnerData = momentOwnerDoc.data();
    const momentData = momentDoc.data();
    const momentPreviewUrl = pickMomentPreviewUrl(momentData);

    // Validar datos requeridos
    if (!validateUserData(reacterData) || !validateUserData(momentOwnerData)) {
      console.warn('⚠️ Datos de usuario incompletos');
      return null;
    }

    // Verificar que ambas cuentas estén activas
    if (!reacterData.isActive || !momentOwnerData.isActive) {
      return null;
    }

    // Obtener FCM token del dueño del momento
    const fcmToken = momentOwnerData.fcmToken || null;
    const shouldSendPush = Boolean(fcmToken) && !isDoNotDisturbActive(momentOwnerData);

    // ✅ MAPEAR REACTIONTYPE A EMOJIS - SOLO LAS NUEVAS REACCIONES
    const reactionEmojis = {
      'vibe': '✨',
      'fire': '🔥',
      'real': '💯',
      'mood': '😊',
      'glow': '🌟',
      'feel': '💙',
      'love': '❤️',
      'wow': '😮',
      'laugh': '😂',
      'cry': '😢',
      'respect': '🙏',
      'power': '💪',
      'genius': '🧠',
      'creative': '🎨',
      'chill': '😌',
      'hype': '🚀'
    };

    const emoji = reactionEmojis[reaction.reactionType] || '❤️';

    // Limpiar URL de imagen
    const cleanImageUrl = reacterData.profileImagePath
      ? reacterData.profileImagePath.replace(':443', '')
      : null;

    // ✅ Incrementar contador de reacciones con transacción idempotente
    const momentRef = admin.firestore().doc(`users/${userId}/moments/${momentId}`);
    const reactionRef = admin.firestore().doc(`users/${userId}/moments/${momentId}/reactions/${reactionId}`);
    const reactionTx = await admin.firestore().runTransaction(async (tx) => {
      const [momentSnap, reactionSnap] = await Promise.all([tx.get(momentRef), tx.get(reactionRef)]);
      const alreadyProcessed = reactionSnap.exists && reactionSnap.get('processed') === true;
      if (!momentSnap.exists) {
        throw new Error('Moment doc missing');
      }
      const currentCount = momentSnap.get('reactionCount') || 0;
      if (alreadyProcessed) {
        return { newReactionCount: currentCount, alreadyProcessed: true };
      }
      tx.update(momentRef, { reactionCount: admin.firestore.FieldValue.increment(1) });
      tx.update(reactionRef, { processed: true });
      return { newReactionCount: currentCount + 1, alreadyProcessed: false };
    });
    if (reactionTx.alreadyProcessed) return null;
    const newReactionCount = reactionTx.newReactionCount;

    const isSilencedByMuteSettings = shouldSilenceNotificationForUser(momentOwnerData, {
      senderId: reaction.userId,
      candidateTexts: [reaction.reactionType, momentData?.content]
    });
    if (isSilencedByMuteSettings) {
      return null;
    }

    // ✅ TÍTULO DINÁMICO basado en número de reacciones
    const username = reacterData.username || 'Alguien';

    const reactionNotificationId = `reaction_${momentId}`;
    const reactionNotificationRef = admin.firestore().doc(`users/${userId}/notifications/${reactionNotificationId}`);
    const legacyPendingSnap = await admin.firestore()
      .collection(`users/${userId}/notifications`)
      .where('type', '==', 'reaction')
      .where('momentId', '==', momentId)
      .where('isPending', '==', true)
      .get();
    const legacyPendingDocs = legacyPendingSnap.docs.filter(doc => doc.id !== reactionNotificationId);
    const totalReactionCount = Math.max(1, Number(newReactionCount || 1));
    const pendingReactionCount = totalReactionCount;

    // Determinar claves de localización
    let titleLocKey, titleLocArgs, bodyLocKey, bodyLocArgs;
    if (pendingReactionCount === 1) {
      titleLocKey = 'notification.momentReaction.single.title';
      titleLocArgs = [username, emoji];
      bodyLocKey = 'notification.momentReaction.single.body';
      bodyLocArgs = [];
    } else {
      titleLocKey = 'notification.momentReaction.multiple.title';
      titleLocArgs = [username, String(pendingReactionCount - 1)];
      bodyLocKey = 'notification.momentReaction.multiple.body';
      bodyLocArgs = [String(pendingReactionCount)];
    }

    // ✅ Obtener conteos actualizados para el Widget
    const counts = await getUnreadCounts(userId, {
      type: 'notification',
      notificationType: 'momentReaction',
      notificationId: reactionNotificationId
    });

    const message = {
      token: fcmToken,
      data: {
        type: 'moment_reaction',
        momentId: momentId,
        userId: reaction.userId,
        reactionType: reaction.reactionType,
        momentOwnerId: userId,
        targetType: 'moment',
        targetId: momentId,
        senderUsername: reacterData.username,
        senderProfileImage: reacterData.profileImagePath || '',
        mediaUrl: momentPreviewUrl || '',
        reactionCount: String(newReactionCount),
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags),
      },
      apns: {
        headers: {
          'apns-collapse-id': `reaction_${momentId}`
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
            'thread-id': `moment_reactions_${momentId}`,
            'summary-arg': reacterData.username,
            'summary-arg-count': pendingReactionCount
          }
        }
      }
    };

    if (shouldSendPush) {
      try {
        await admin.messaging().send(message);
        console.log(`✅ Notificación enviada: ${username} -> ${momentOwnerData.username} (${reaction.reactionType}) - Pending: ${pendingReactionCount}`);
      } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
          await removeInvalidToken(userId, fcmToken);
        }
        throw error;
      }
    }

    // ✅ Una notificación agregada por momento
    await reactionNotificationRef.set({
      type: 'reaction',
      senderId: reaction.userId,
      senderUsername: username,
      senderProfileImage: reacterData.profileImagePath || '',
      momentId: momentId,
      reactionType: reaction.reactionType,
      reactionCount: pendingReactionCount,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isPending: true
    }, { merge: true });

    // Limpieza de migración: eliminar documentos legacy para este momento.
    if (legacyPendingDocs.length > 0) {
      const batch = admin.firestore().batch();
      legacyPendingDocs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
    }

  } catch (error) {
    console.error('❌ Error sending reaction notification:', error);
  }
});

const onHiddenLayerDiscoveryCreated = onDocumentCreated(
  'users/{userId}/moments/{momentId}/hiddenLayers/{layerId}/discoveries/{viewerId}',
  async (event) => {
    const { userId, momentId, layerId, viewerId } = event.params;
    const discoveryData = event.data?.data() || {};
    const discoveredAt = discoveryData.discoveredAt || admin.firestore.FieldValue.serverTimestamp();

    const db = admin.firestore();
    const layerRef = db
      .collection('users')
      .doc(userId)
      .collection('moments')
      .doc(momentId)
      .collection('hiddenLayers')
      .doc(layerId);

    await layerRef.set({
      discoverCount: admin.firestore.FieldValue.increment(1),
      uniqueDiscovererCount: admin.firestore.FieldValue.increment(1),
      lastDiscoveredAt: discoveredAt
    }, { merge: true });

    const momentDiscovererRef = db
      .collection('users')
      .doc(userId)
      .collection('moments')
      .doc(momentId)
      .collection('hiddenLayerDiscoverers')
      .doc(viewerId);

    const momentDiscovererSnap = await momentDiscovererRef.get();
    if (!momentDiscovererSnap.exists) {
      await momentDiscovererRef.set({
        viewerId,
        username: discoveryData.username || null,
        profileImagePath: discoveryData.profileImagePath || null,
        lastDiscoveredAt: discoveredAt
      }, { merge: true });
    }
  }
);

// ✅ ACTUALIZAR BADGE SILENCIOSAMENTE
// ✅ #1 OPTIMIZADO: Una sola Cloud Function para todas las notificaciones creadas
// Antes habían 3 funciones disparándose en paralelo (updateBadge, onMentionNotification, onPhotoTagNotification)
// Ahora un solo onDocumentCreated que hace switch por tipo.
const onNotificationCreated = onDocumentCreated('users/{userId}/notifications/{notificationId}', async (event) => {
  const snap = event.data;
  const { userId, notificationId } = event.params;
  const notification = snap.data();

  try {
    const userDoc = await admin.firestore().doc(`users/${userId}`).get();
    if (!userDoc.exists) return null;
    const userData = userDoc.data();
    if (!validateUserData(userData)) return null;

    // Dispatch según tipo
    switch (notification.type) {
      case 'mention':
        await handleMentionPush(userId, notificationId, notification, userData);
        break;
      case 'photoTag':
        await handlePhotoTagPush(userId, notificationId, notification, userData);
        break;
      case 'comment':
        if (notification.mentionContext === 'reply') {
          await handleReplyPush(userId, notificationId, notification, userData);
        } else {
          await handleBadgeUpdate(userId, userData);
        }
        break;
      case 'mediaModeration':
        await handleModerationPush(userId, notificationId, notification, userData);
        break;
      default:
        // Badge update silencioso para todos los demás tipos
        await handleBadgeUpdate(userId, userData);
        break;
    }
  } catch (error) {
    console.error('❌ Error en onNotificationCreated:', error);
  }
});

// Helper: Actualizar badge (antes era exports.updateBadge entero)
async function handleBadgeUpdate(userId, userData) {
  if (!userData.fcmToken || isDoNotDisturbActive(userData)) return;

  const notifications = await admin.firestore()
    .collection(`users/${userId}/notifications`)
    .where('isPending', '==', true)
    .get();

  const badgeCount = notifications.size;
  const message = {
    token: userData.fcmToken,
    data: { silent: true },
    apns: {
      payload: {
        aps: {
          'mutable-content': 1,
          badge: badgeCount
        }
      }
    }
  };

  try {
    await admin.messaging().send(message);
    console.log(`✅ Badge actualizado para ${userId}: ${badgeCount}`);
  } catch (error) {
    if (error.code === 'messaging/registration-token-not-registered') {
      await removeInvalidToken(userId, userData.fcmToken);
    }
    throw error;
  }
}

// 🛡️ Helper: Push notification para moderación de contenido multimedia
async function handleModerationPush(userId, notificationId, notification, userData) {
  const fcmToken = userData.fcmToken || null;
  if (!fcmToken || isDoNotDisturbActive(userData)) return;

  const moderationType = notification.moderationType || 'full';
  const moderationScope = notification.moderationScope || 'post';
  const moderatedMediaCount = notification.moderatedMediaCount || 0;
  const momentId = notification.momentId || '';
  const storyId = notification.storyId || '';

  let titleLocKey, bodyLocKey, bodyLocArgs;

  if (moderationScope === 'storySticker') {
    titleLocKey = 'notification.moderation.storySticker.partial.title';
    if (moderatedMediaCount === 1) {
      bodyLocKey = 'notification.moderation.storySticker.partial.body.one';
      bodyLocArgs = [];
    } else {
      bodyLocKey = 'notification.moderation.storySticker.partial.body.other';
      bodyLocArgs = [String(moderatedMediaCount)];
    }
  } else if (moderationScope === 'postHiddenLayer') {
    titleLocKey = 'notification.moderation.postHiddenLayer.partial.title';
    if (moderatedMediaCount === 1) {
      bodyLocKey = 'notification.moderation.postHiddenLayer.partial.body.one';
      bodyLocArgs = [];
    } else {
      bodyLocKey = 'notification.moderation.postHiddenLayer.partial.body.other';
      bodyLocArgs = [String(moderatedMediaCount)];
    }
  } else {
    const scopePrefix = moderationScope === 'story' ? 'notification.moderation.story' : 'notification.moderation';
    if (moderationType === 'partial') {
      titleLocKey = `${scopePrefix}.partial.title`;
      bodyLocKey = `${scopePrefix}.partial.body`;
      bodyLocArgs = [String(moderatedMediaCount)];
    } else {
      titleLocKey = `${scopePrefix}.full.title`;
      bodyLocKey = `${scopePrefix}.full.body`;
      bodyLocArgs = [];
    }
  }

  // Obtener conteos para badge
  const counts = await getUnreadCounts(userId, {
    type: 'notification',
    notificationType: 'mediaModeration',
    notificationId: notificationId
  });

  const message = {
    token: fcmToken,
    data: {
      type: 'media_moderation',
      momentId: momentId,
      storyId: storyId,
      moderationType: moderationType,
      moderationScope: moderationScope,
      moderatedMediaCount: String(moderatedMediaCount),
      unreadMessages: String(counts.unreadMessages),
      unreadNotifications: String(counts.unreadNotifications),
    },
    apns: {
      headers: {
        'apns-collapse-id': `moderation_${storyId || momentId || notificationId}`
      },
      payload: {
        aps: {
          alert: {
            'title-loc-key': titleLocKey,
            'loc-key': bodyLocKey,
            'loc-args': bodyLocArgs
          },
          badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
          sound: 'default',
          'mutable-content': 1,
          'thread-id': `moderation_${storyId || momentId || notificationId}`
        }
      }
    }
  };

  try {
    await admin.messaging().send(message);
    console.log(`✅ Push de moderación enviada a ${userData.username} (${moderationType})`);
  } catch (error) {
    if (error.code === 'messaging/registration-token-not-registered') {
      await removeInvalidToken(userId, fcmToken);
    }
    console.error('❌ Error enviando push de moderación:', error);
  }
}

async function claimProcessingLock(docRef, options = {}) {
  const processedField = options.processedField || 'processed';
  const processingField = options.processingField || 'processingUntil';
  const lockMs = typeof options.lockMs === 'number' ? options.lockMs : 120000;

  const nowMs = Date.now();
  const lockUntil = admin.firestore.Timestamp.fromMillis(nowMs + lockMs);

  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    if (!snap.exists) return false;
    if (snap.get(processedField) === true) return false;

    const processingUntil = snap.get(processingField);
    if (processingUntil && typeof processingUntil.toMillis === 'function' && processingUntil.toMillis() > nowMs) {
      return false;
    }

    tx.update(docRef, { [processingField]: lockUntil });
    return true;
  });
}

async function markProcessingDone(docRef, options = {}) {
  const processedField = options.processedField || 'processed';
  const processingField = options.processingField || 'processingUntil';
  await docRef.set({
    [processedField]: true,
    processedAt: admin.firestore.FieldValue.serverTimestamp(),
    [processingField]: admin.firestore.FieldValue.delete()
  }, { merge: true });
}

async function releaseProcessingLock(docRef, options = {}) {
  const processingField = options.processingField || 'processingUntil';
  await docRef.set({
    [processingField]: admin.firestore.FieldValue.delete()
  }, { merge: true });
}

// Helper: Push de mención (antes era exports.onMentionNotification entero)
async function handleMentionPush(userId, notificationId, notification, userData) {
  const senderDoc = await admin.firestore().doc(`users/${notification.senderId}`).get();
  if (!senderDoc.exists) return;
  const senderData = senderDoc.data();
  if (!validateUserData(senderData) || !senderData.isActive || !userData.isActive) return;

  const mentionRef = admin.firestore().doc(`users/${userId}/notifications/${notificationId}`);
  const isSilenced = shouldSilenceNotificationForUser(userData, {
    senderId: notification.senderId,
    candidateTexts: [notification.text, notification.commentText, notification.content, notification.caption]
  });
  if (isSilenced) {
    await mentionRef.delete().catch(() => null);
    return;
  }

  const fcmToken = userData.fcmToken;
  const lockAcquired = await claimProcessingLock(mentionRef, {
    processedField: 'processed',
    processingField: 'processingUntil'
  });
  if (!lockAcquired) return;

  try {
    if (!fcmToken || isDoNotDisturbActive(userData)) {
      await markProcessingDone(mentionRef, {
        processedField: 'processed',
        processingField: 'processingUntil'
      });
      return;
    }

    const mentionContext = notification.mentionContext
      || (notification.storyId ? 'story' : (notification.commentId ? 'comment' : 'moment'));

    let contentType = 'contenido';
    let targetType = 'moment';
    let targetId = notification.momentId;
    if (mentionContext === 'story' && notification.storyId) {
      contentType = 'historia';
      targetType = 'story';
      targetId = notification.storyId;
    } else if (mentionContext === 'comment' && notification.momentId) {
      contentType = 'comentario';
      targetType = 'comment';
      targetId = notification.commentId || notification.momentId;
    } else if (notification.momentId) {
      contentType = 'momento';
      targetType = 'moment';
      targetId = notification.momentId;
    }

    const mentionTitleKey = mentionContext === 'story'
      ? 'notification.mention.story.title'
      : mentionContext === 'comment'
        ? (notification.targetAuthorUsername
          ? 'notification.mention.comment.withAuthor.title'
          : 'notification.mention.comment.title')
        : mentionContext === 'moment'
          ? 'notification.mention.moment.title'
          : 'notification.mention.title';
    const mentionTitleArgs = mentionTitleKey === 'notification.mention.title'
      ? [senderData.username, contentType]
      : mentionTitleKey === 'notification.mention.comment.withAuthor.title'
        ? [senderData.username, notification.targetAuthorUsername]
      : [senderData.username];

    const counts = await getUnreadCounts(userId, { type: 'notification', notificationType: 'mention' });

    const message = {
      token: fcmToken,
      data: {
        type: 'mention',
        senderId: notification.senderId,
        userId: userId,
        targetType: targetType,
        targetId: targetId,
        mentionContext: mentionContext,
        momentId: notification.momentId || '',
        storyId: notification.storyId || '',
        storyAuthorId: notification.storyAuthorId || notification.targetAuthorId || notification.senderId || '',
        targetAuthorId: notification.targetAuthorId || notification.storyAuthorId || notification.senderId || '',
        targetAuthorUsername: notification.targetAuthorUsername || '',
        commentId: notification.commentId || '',
        senderUsername: senderData.username,
        senderProfileImage: senderData.profileImagePath || '',
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags),
      },
      apns: {
        headers: { 'apns-collapse-id': `mention_${userId}` },
        payload: {
          aps: {
            alert: {
              'title-loc-key': mentionTitleKey,
              'title-loc-args': mentionTitleArgs,
              'loc-key': 'notification.mention.body',
              'loc-args': []
            },
            badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
            sound: 'default',
            'mutable-content': 1,
            'thread-id': `mentions_${userId}`
          }
        }
      }
    };

    await admin.messaging().send(message);
    await markProcessingDone(mentionRef, {
      processedField: 'processed',
      processingField: 'processingUntil'
    });
    console.log(`✅ Mención push: ${senderData.username} -> ${userData.username} en ${contentType}`);
  } catch (error) {
    await releaseProcessingLock(mentionRef, { processingField: 'processingUntil' }).catch(() => null);
    if (error.code === 'messaging/registration-token-not-registered') {
      await removeInvalidToken(userId, fcmToken);
    }
    throw error;
  }
}

async function handleReplyPush(userId, notificationId, notification, userData) {
  const senderDoc = await admin.firestore().doc(`users/${notification.senderId}`).get();
  if (!senderDoc.exists) return;
  const senderData = senderDoc.data();
  if (!validateUserData(senderData) || !senderData.isActive || !userData.isActive) return;

  const replyRef = admin.firestore().doc(`users/${userId}/notifications/${notificationId}`);
  const isSilenced = shouldSilenceNotificationForUser(userData, {
    senderId: notification.senderId,
    candidateTexts: [notification.reaction, notification.commentText, notification.text, notification.content]
  });
  if (isSilenced) {
    await replyRef.delete().catch(() => null);
    return;
  }

  // Respeta el toggle de comentarios: sin push, pero mantenemos la notificación in-app.
  if (!notificationTypeEnabled(userData, 'comment')) return;

  const fcmToken = userData.fcmToken;
  const lockAcquired = await claimProcessingLock(replyRef, {
    processedField: 'processed',
    processingField: 'processingUntil'
  });
  if (!lockAcquired) return;

  try {
    if (!fcmToken || isDoNotDisturbActive(userData)) {
      await markProcessingDone(replyRef, {
        processedField: 'processed',
        processingField: 'processingUntil'
      });
      return;
    }

    const counts = await getUnreadCounts(userId, { type: 'notification', notificationType: 'reply', notificationId });
    const replyPreview = notification.reaction || notification.commentText || '';

    const message = {
      token: fcmToken,
      data: {
        type: 'moment_comment',
        mentionContext: 'reply',
        senderId: notification.senderId,
        userId,
        momentId: notification.momentId || '',
        momentOwnerId: notification.targetAuthorId || '',
        targetAuthorId: notification.targetAuthorId || '',
        targetAuthorUsername: notification.targetAuthorUsername || '',
        commentId: notification.commentId || '',
        senderUsername: senderData.username,
        senderProfileImage: senderData.profileImagePath || '',
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags),
      },
      apns: {
        headers: { 'apns-collapse-id': `reply_${notification.commentId || notificationId}` },
        payload: {
          aps: {
            alert: replyPreview ? {
              'title-loc-key': 'notification.reply.title',
              'title-loc-args': [senderData.username],
              body: `"${String(replyPreview).substring(0, 80)}${String(replyPreview).length > 80 ? '...' : ''}"`
            } : {
              'title-loc-key': 'notification.reply.title',
              'title-loc-args': [senderData.username]
            },
            badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
            sound: 'default',
            'mutable-content': 1,
            'thread-id': `moment_replies_${notification.momentId || userId}`
          }
        }
      }
    };

    await admin.messaging().send(message);
    await markProcessingDone(replyRef, {
      processedField: 'processed',
      processingField: 'processingUntil'
    });
    console.log(`✅ Reply push: ${senderData.username} -> ${userData.username}`);
  } catch (error) {
    await releaseProcessingLock(replyRef, { processingField: 'processingUntil' }).catch(() => null);
    if (error.code === 'messaging/registration-token-not-registered') {
      await removeInvalidToken(userId, fcmToken);
    }
    throw error;
  }
}

// Helper: Push de photo tag (antes era exports.onPhotoTagNotification entero)
async function handlePhotoTagPush(userId, notificationId, notification, userData) {
  const senderDoc = await admin.firestore().doc(`users/${notification.senderId}`).get();
  if (!senderDoc.exists) return;
  const senderData = senderDoc.data();
  if (!validateUserData(senderData) || !senderData.isActive || !userData.isActive) return;

  const tagRef = admin.firestore().doc(`users/${userId}/notifications/${notificationId}`);
  const isSilenced = shouldSilenceNotificationForUser(userData, {
    senderId: notification.senderId,
    candidateTexts: [notification.text, notification.commentText, notification.content, notification.caption]
  });
  if (isSilenced) {
    await tagRef.delete().catch(() => null);
    return;
  }

  const fcmToken = userData.fcmToken;
  const lockAcquired = await claimProcessingLock(tagRef, {
    processedField: 'processed',
    processingField: 'processingUntil'
  });
  if (!lockAcquired) return;

  try {
    if (!fcmToken || isDoNotDisturbActive(userData)) {
      await markProcessingDone(tagRef, {
        processedField: 'processed',
        processingField: 'processingUntil'
      });
      return;
    }

    const counts = await getUnreadCounts(userId, { type: 'notification', notificationType: 'photoTag' });
    const momentTitle = typeof notification.reaction === 'string' ? notification.reaction.trim() : '';
    const titleLocKey = momentTitle
      ? 'notification.photoTag.withTitle.title'
      : 'notification.photoTag.title';
    const titleLocArgs = momentTitle
      ? [senderData.username, momentTitle]
      : [senderData.username];

    const message = {
      token: fcmToken,
      data: {
        type: 'photo_tag',
        senderId: notification.senderId,
        userId: userId,
        targetType: 'moment',
        targetId: notification.momentId || '',
        senderUsername: senderData.username,
        senderProfileImage: senderData.profileImagePath || '',
        momentTitle,
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags),
      },
      apns: {
        headers: { 'apns-collapse-id': `tag_${userId}` },
        payload: {
          aps: {
            alert: {
              'title-loc-key': titleLocKey,
              'title-loc-args': titleLocArgs,
              'loc-key': 'notification.photoTag.body',
              'loc-args': []
            },
            badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
            sound: 'default',
            'mutable-content': 1,
            'thread-id': `photo_tags_${userId}`
          }
        }
      }
    };

    await admin.messaging().send(message);
    await markProcessingDone(tagRef, {
      processedField: 'processed',
      processingField: 'processingUntil'
    });
    console.log(`✅ Photo tag push: ${senderData.username} -> ${userData.username}`);
  } catch (error) {
    await releaseProcessingLock(tagRef, { processingField: 'processingUntil' }).catch(() => null);
    if (error.code === 'messaging/registration-token-not-registered') {
      await removeInvalidToken(userId, fcmToken);
    }
    throw error;
  }
}

// ✅ #6 OPTIMIZADO: Limpieza con collectionGroup (escala sin depender del nº de usuarios)
const cleanOldNotifications = onSchedule(
  { schedule: '0 0 * * *', timeZone: 'Europe/Madrid', region: 'us-central1' },
  async () => {
    try {
      const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

      // Usar collectionGroup en vez de iterar user-by-user
      async function deleteBatch() {
        const snapshot = await admin.firestore()
          .collectionGroup('notifications')
          .where('timestamp', '<', thirtyDaysAgo)
          .where('isPending', '==', false)
          .limit(500)
          .get();

        if (snapshot.empty) return 0;

        const batch = admin.firestore().batch();
        snapshot.docs.forEach(doc => batch.delete(doc.ref));
        await batch.commit();

        console.log(`✅ Eliminadas ${snapshot.size} notificaciones antiguas`);
        return snapshot.size;
      }

      // Recursive batching hasta que no queden más
      let totalDeleted = 0;
      let batchSize;
      do {
        batchSize = await deleteBatch();
        totalDeleted += batchSize;
      } while (batchSize === 500);

      console.log(`✅ Limpieza total: ${totalDeleted} notificaciones antiguas eliminadas`);
    } catch (error) {
      console.error('❌ Error en limpieza de notificaciones:', error);
    }
  });

const sendDailyGentleReminders = onSchedule(
  { schedule: '0 18 * * *', timeZone: 'Europe/Madrid', region: 'us-central1' },
  async () => {
    const db = admin.firestore();
    const now = new Date();
    const batchSize = 200;
    let lastDoc = null;
    let scanned = 0;
    let sent = 0;
    let updated = 0;

    try {
      do {
        let query = db
          .collection('users')
          .where('isActive', '==', true)
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(batchSize);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const snapshot = await query.get();
        if (snapshot.empty) break;

        for (const doc of snapshot.docs) {
          scanned += 1;
          const userId = doc.id;
          const userData = doc.data() || {};
          const { state, updates } = buildGentleReminderState(userData, now);

          if (Object.keys(updates).length > 0) {
            await doc.ref.update(updates);
            updated += 1;
          }

          if (!userData.fcmToken) continue;
          if (!gentleRemindersEnabled(userData)) continue;
          if (isDoNotDisturbActive(userData)) continue;
          if (!state.lastAppOpenAt) continue;

          const variant = chooseGentleReminderVariant(state, now);
          if (!variant) continue;

          try {
            await sendGentleReminderPush(userId, userData, variant);

            const sentHistory = [...state.gentleReminderSentHistory, now]
              .filter((date) => date instanceof Date)
              .sort((a, b) => a.getTime() - b.getTime());

            await doc.ref.update({
              lastGentleReminderAt: now,
              lastGentleReminderVariant: variant,
              gentleReminderAwaitingResponse: true,
              gentleReminderSentHistory: normalizeReminderHistory(sentHistory, now),
              gentleReminderCooldownUntil: state.gentleReminderCooldownUntil || admin.firestore.FieldValue.delete()
            });

            sent += 1;
          } catch (error) {
            if (error.code === 'messaging/registration-token-not-registered') {
              await removeInvalidToken(userId, userData.fcmToken);
            } else {
              console.error(`❌ Error enviando gentle reminder a ${userId}:`, error);
            }
          }
        }

        lastDoc = snapshot.docs[snapshot.docs.length - 1];
        if (snapshot.size < batchSize) break;
      } while (lastDoc);

      console.log(`✅ Gentle reminders: revisados=${scanned}, enviados=${sent}, reconciliados=${updated}`);
    } catch (error) {
      console.error('❌ Error en gentle reminders:', error);
    }
  });


// 💬 COMENTARIOS EN MOMENTOS
const onMomentCommentAdded = onDocumentCreated('users/{userId}/moments/{momentId}/comments/{commentId}', async (event) => {
  const snap = event.data;
  const { userId, momentId, commentId } = event.params;
  const comment = snap.data();

  try {
    if (comment.authorId === userId) return null;

    const [commenterDoc, momentOwnerDoc, momentDoc] = await Promise.all([
      admin.firestore().doc(`users/${comment.authorId}`).get(),
      admin.firestore().doc(`users/${userId}`).get(),
      admin.firestore().doc(`users/${userId}/moments/${momentId}`).get()
    ]);

    if (!commenterDoc.exists || !momentOwnerDoc.exists) return null;

    const commenterData = commenterDoc.data();
    const momentOwnerData = momentOwnerDoc.data();
    const momentData = momentDoc.exists ? momentDoc.data() : null;
    const momentPreviewUrl = pickMomentPreviewUrl(momentData);

    if (!validateUserData(commenterData) || !validateUserData(momentOwnerData)) {
      console.warn('⚠️ Datos de usuario incompletos para comentario');
      return null;
    }

    if (!commenterData.isActive || !momentOwnerData.isActive) return null;

    const fcmToken = momentOwnerData.fcmToken || null;
    const shouldSendPush = Boolean(fcmToken) && !isDoNotDisturbActive(momentOwnerData) && notificationTypeEnabled(momentOwnerData, 'comment');

    const commentPreview = comment.text && comment.text.trim()
      ? comment.text.substring(0, 50) + (comment.text.length > 50 ? '...' : '')
      : 'Nuevo comentario';

    const cleanImageUrl = commenterData.profileImagePath
      ? commenterData.profileImagePath.replace(':443', '')
      : null;

    // ✅ Idempotencia por comentario
    const commentRef = admin.firestore().doc(`users/${userId}/moments/${momentId}/comments/${commentId}`);
    const processed = await admin.firestore().runTransaction(async (tx) => {
      const cSnap = await tx.get(commentRef);
      if (!cSnap.exists) return true; // nada que hacer
      if (cSnap.get('processed') === true) return true;
      tx.update(commentRef, { processed: true });
      return false; // no estaba procesado, ahora marcado
    });
    if (processed) return null;

    const isSilencedByMuteSettings = shouldSilenceNotificationForUser(momentOwnerData, {
      senderId: comment.authorId,
      candidateTexts: [comment.text, momentData?.content]
    });
    if (isSilencedByMuteSettings) {
      return null;
    }

    // ✅ Obtener conteos actualizados para el Widget
    const [counts, commentCount] = await Promise.all([
      getUnreadCounts(userId, { type: 'notification', notificationType: 'momentComment', notificationId: commentId }),
      getPendingCommentCount(userId, momentId)
    ]);

    // Determinar claves de localización
    let titleLocKey, titleLocArgs, bodyLocKey, bodyLocArgs;
    if (commentCount > 1) {
      titleLocKey = 'notification.comment.multiple.title';
      titleLocArgs = [commenterData.username, String(commentCount - 1)];
      bodyLocKey = 'notification.comment.multiple.body';
      bodyLocArgs = [String(commentCount)];
    } else {
      titleLocKey = 'notification.comment.single.title';
      titleLocArgs = [commenterData.username];
      bodyLocKey = null; // Usar el comentario como body
      bodyLocArgs = null;
    }

    const message = {
      token: fcmToken,
      data: {
        type: 'moment_comment',
        momentId: momentId,
        commentId: commentId,
        userId: comment.authorId,
        momentOwnerId: userId,
        targetType: 'moment',
        targetId: momentId,
        senderUsername: commenterData.username,
        senderProfileImage: commenterData.profileImagePath || '',
        mediaUrl: momentPreviewUrl || '',
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags),
      },
      apns: {
        headers: {
          'apns-collapse-id': `comment_${momentId}`
        },
        payload: {
          aps: {
            alert: bodyLocKey ? {
              'title-loc-key': titleLocKey,
              'title-loc-args': titleLocArgs,
              'loc-key': bodyLocKey,
              'loc-args': bodyLocArgs
            } : {
              'title-loc-key': titleLocKey,
              'title-loc-args': titleLocArgs,
              body: `"${commentPreview}"`
            },
            badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
            sound: 'default',
            'mutable-content': 1,
            'thread-id': `moment_comments_${momentId}`
          }
        }
      }
    };

    if (shouldSendPush) {
      try {
        await admin.messaging().send(message);
        console.log(`✅ Notificación de comentario enviada: ${commenterData.username} -> ${momentOwnerData.username}`);
      } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
          await removeInvalidToken(userId, fcmToken);
        }
        throw error;
      }
    }

    await admin.firestore().collection(`users/${userId}/notifications`).add({
      type: 'comment',
      senderId: comment.authorId,
      senderUsername: commenterData.username,
      senderProfileImage: commenterData.profileImagePath || '',
      momentId: momentId,
      commentId: commentId,
      commentText: commentPreview,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isPending: true
    });

  } catch (error) {
    console.error('❌ Error sending comment notification:', error);
  }
});

// 👥 NUEVOS SEGUIDORES

module.exports = {
  onMomentReactionAdded,
  onHiddenLayerDiscoveryCreated,
  onNotificationCreated,
  cleanOldNotifications,
  sendDailyGentleReminders,
  onMomentCommentAdded,
};
