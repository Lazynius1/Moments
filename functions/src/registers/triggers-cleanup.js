const b = require('../bootstrap');
const h = require('../helpers');
const { claimProcessingLock, markProcessingDone, releaseProcessingLock } = require('./triggers-engagement');
const { purgeNotificationsByField, reconcileEchoAfterMomentDeletion } = require('./triggers-messaging');
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

const onMomentDeleted = onDocumentDeleted('users/{userId}/moments/{momentId}', async (event) => {
  const { userId, momentId } = event.params;
  try {
    await purgeNotificationsByField('momentId', momentId);
    await reconcileEchoAfterMomentDeletion({ momentId, authorId: userId });
  } catch (error) {
    console.error('❌ Error purgando notificaciones del momento eliminado:', error);
  }
  return null;
});

const onStoryDeleted = onDocumentDeleted('users/{userId}/stories/{storyId}', async (event) => {
  const { storyId } = event.params;
  try {
    await purgeNotificationsByField('storyId', storyId);
  } catch (error) {
    console.error('❌ Error purgando notificaciones de la historia eliminada:', error);
  }
  return null;
});

const onCommentDeleted = onDocumentDeleted('users/{userId}/moments/{momentId}/comments/{commentId}', async (event) => {
  const { commentId } = event.params;
  try {
    await purgeNotificationsByField('commentId', commentId);
  } catch (error) {
    console.error('❌ Error purgando notificaciones del comentario eliminado:', error);
  }
  return null;
});

// 🔔 ELIMINAR REACCIONES DE MOMENTOS
const onMomentReactionRemoved = onDocumentDeleted('users/{userId}/moments/{momentId}/reactions/{reactionId}', async (event) => {
  const snap = event.data;
  const { userId, momentId, reactionId } = event.params;
  const reaction = snap?.data() || {};

  try {
    // ✅ Decrementar el contador de reacciones
    const momentRef = admin.firestore().doc(`users/${userId}/moments/${momentId}`);
    await momentRef.update({ reactionCount: admin.firestore.FieldValue.increment(-1) });

    // ✅ Actualizar solo la notificación agregada del momento.
    const removedByUserId = typeof reaction.userId === 'string' ? reaction.userId : '';
    if (!removedByUserId) {
      return null;
    }

    const reactionNotificationId = `reaction_${momentId}`;
    const reactionNotificationRef = admin.firestore().doc(`users/${userId}/notifications/${reactionNotificationId}`);
    const reactionNotificationSnap = await reactionNotificationRef.get();
    if (!reactionNotificationSnap.exists) {
      return null;
    }

    const reactionNotificationData = reactionNotificationSnap.data() || {};
    if (reactionNotificationData.type !== 'reaction' || reactionNotificationData.isPending !== true) {
      return null;
    }

    // Limpieza de migración: eliminar documentos legacy para este momento.
    const legacyPendingSnap = await admin.firestore()
      .collection(`users/${userId}/notifications`)
      .where('type', '==', 'reaction')
      .where('momentId', '==', momentId)
      .where('isPending', '==', true)
      .get();
    const legacyPendingDocs = legacyPendingSnap.docs.filter(doc => doc.id !== reactionNotificationId);
    if (legacyPendingDocs.length > 0) {
      const cleanupBatch = admin.firestore().batch();
      legacyPendingDocs.forEach(doc => cleanupBatch.delete(doc.ref));
      await cleanupBatch.commit();
    }

    const currentPendingCount = Math.max(1, Number(reactionNotificationData.reactionCount || 1));

    const momentAfterUpdateSnap = await momentRef.get();
    const totalReactionCount = Math.max(0, Number(momentAfterUpdateSnap.get('reactionCount') || 0));

    if (totalReactionCount === 0) {
      await reactionNotificationRef.delete();
      console.log(`🗑️ Eliminada notificación agregada de reacción para momento ${momentId}`);
      return null;
    }

    const updatePayload = {
      reactionCount: totalReactionCount
    };

    // Si el actor visible era justo quien quitó la reacción, sustituimos por la reacción más reciente restante.
    if (reactionNotificationData.senderId === removedByUserId) {
      const remainingReactionsSnap = await admin.firestore()
        .collection(`users/${userId}/moments/${momentId}/reactions`)
        .orderBy('timestamp', 'desc')
        .limit(1)
        .get();

      if (remainingReactionsSnap.empty) {
        await reactionNotificationRef.delete();
        console.log(`🗑️ Eliminada notificación agregada: no quedan reacciones para ${momentId}`);
        return null;
      }

      const remainingReaction = remainingReactionsSnap.docs[0].data() || {};
      const replacementSenderId = remainingReaction.userId || reactionNotificationData.senderId;
      let replacementSenderUsername = reactionNotificationData.senderUsername || 'Alguien';
      let replacementSenderProfileImage = reactionNotificationData.senderProfileImage || '';

      if (replacementSenderId) {
        const replacementSenderDoc = await admin.firestore().doc(`users/${replacementSenderId}`).get();
        if (replacementSenderDoc.exists) {
          const replacementSenderData = replacementSenderDoc.data() || {};
          replacementSenderUsername = replacementSenderData.username || replacementSenderUsername;
          replacementSenderProfileImage = replacementSenderData.profileImagePath || replacementSenderProfileImage;
        }
      }

      updatePayload.senderId = replacementSenderId;
      updatePayload.senderUsername = replacementSenderUsername;
      updatePayload.senderProfileImage = replacementSenderProfileImage;
      updatePayload.reactionType = remainingReaction.reactionType || reactionNotificationData.reactionType || '';
      const replacementTimestamp = remainingReaction.timestamp || null;
      if (replacementTimestamp) {
        updatePayload.timestamp = replacementTimestamp;
      }
    }

    await reactionNotificationRef.set(updatePayload, { merge: true });
    console.log(`✅ Actualizada notificación agregada de reacción para ${momentId}: ${currentPendingCount} -> ${totalReactionCount}`);

  } catch (error) {
    console.error('❌ Error handling moment reaction removal:', error);
  }
});

// 🔗 STORY CHAINS: Crear entrada de cadena cuando se publica la primera parte
const onStoryChainCreated = onDocumentCreated('users/{userId}/stories/{storyId}', async (event) => {
  const snap = event.data;
  const { userId, storyId } = event.params;
  const story = snap.data();

  try {
    // Solo procesar si es la primera parte de una cadena
    if (!story.chainId || !story.chainPosition || story.chainPosition !== 1) {
      return null;
    }

    console.log(`🔗 Creando entrada de cadena: ${story.chainId} - ${story.chainTitle}`);

    // Crear entrada en la colección storyChains
    await admin.firestore().collection('storyChains').doc(story.chainId).set({
      id: story.chainId,
      title: story.chainTitle || '',
      createdBy: userId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      partCount: 1,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      lastPartBy: story.authorId,
      lastPartUsername: story.username,
      isExpired: false
    });

    console.log(`✅ Entrada de cadena creada: ${story.chainId}`);

  } catch (error) {
    console.error('❌ Error creando entrada de cadena:', error);
  }
});

// 🔗 STORY CHAINS: Notificación cuando alguien continúa una cadena
const onStoryChainContinued = onDocumentCreated('users/{userId}/stories/{storyId}', async (event) => {
  const snap = event.data;
  const { userId, storyId } = event.params;
  const story = snap.data();

  try {
    // Solo procesar si es parte de una cadena y no es la primera parte
    if (!story.chainId || !story.chainPosition || story.chainPosition <= 1) {
      return null;
    }

    // El doc recién creado vive en users/{userId}/stories/{storyId}.
    // userId aquí es quien publicó esta parte (continuador), no necesariamente el creador original.
    const continuerId = story.authorId || userId;
    const storyOwnerId = userId;
    if (continuerId !== storyOwnerId) {
      console.warn(`⚠️ Story chain inconsistente: authorId (${continuerId}) != ownerId (${storyOwnerId}) en story ${storyId}`);
    }

    // Resolver creador real de la cadena
    let chainCreatorId = null;
    const chainMetaDoc = await admin.firestore().doc(`storyChains/${story.chainId}`).get();
    if (chainMetaDoc.exists) {
      chainCreatorId = chainMetaDoc.data()?.createdBy || null;
    }

    // Fallback: buscar la primera parte de la cadena
    if (!chainCreatorId) {
      const firstPartSnapshot = await admin.firestore()
        .collectionGroup('stories')
        .where('chainId', '==', story.chainId)
        .where('chainPosition', '==', 1)
        .limit(1)
        .get();
      const firstPart = firstPartSnapshot.docs[0];
      if (firstPart) {
        chainCreatorId = firstPart.data()?.authorId || firstPart.ref.parent.parent?.id || null;
      }
    }

    if (!chainCreatorId) {
      console.warn(`⚠️ No se pudo resolver chainCreatorId para chainId=${story.chainId}`);
      return null;
    }

    // Obtener datos del continuador (remitente de la notificación)
    const continuerDoc = await admin.firestore().doc(`users/${continuerId}`).get();
    if (!continuerDoc.exists) {
      console.warn('⚠️ Continuador no encontrado para Story Chain');
      return null;
    }
    const continuerData = continuerDoc.data();
    if (!validateUserData(continuerData) || !continuerData.isActive) {
      return null;
    }

    // Lock idempotente sobre la parte recién creada
    const storyRef = admin.firestore().doc(`users/${storyOwnerId}/stories/${storyId}`);
    const lockAcquired = await claimProcessingLock(storyRef, {
      processedField: 'chainNotificationProcessed',
      processingField: 'chainNotificationProcessingUntil'
    });
    if (!lockAcquired) return null;

    // Obtener todas las partes de la cadena: para contar y para conocer a los participantes
    const chainStoriesSnapshot = await admin.firestore()
      .collectionGroup('stories')
      .where('chainId', '==', story.chainId)
      .orderBy('chainPosition')
      .get();

    const totalParts = chainStoriesSnapshot.size;
    const storyPreviewUrl = pickStoryPreviewUrl(story);

    // Destinatarios: creador original + todos los que han participado en la cadena,
    // excluyendo a quien acaba de continuarla.
    const recipientIds = new Set();
    if (chainCreatorId) recipientIds.add(chainCreatorId);
    chainStoriesSnapshot.docs.forEach(doc => {
      const ownerId = doc.ref.parent.parent?.id;
      const authorId = doc.data()?.authorId;
      if (ownerId) recipientIds.add(ownerId);
      if (authorId) recipientIds.add(authorId);
    });
    recipientIds.delete(continuerId);

    if (recipientIds.size === 0) {
      await markProcessingDone(storyRef, {
        processedField: 'chainNotificationProcessed',
        processingField: 'chainNotificationProcessingUntil'
      });
      return null;
    }

    const username = continuerData.username || 'Alguien';

    const notificationPromises = Array.from(recipientIds).map(async (recipientId) => {
      const recipientDoc = await admin.firestore().doc(`users/${recipientId}`).get();
      if (!recipientDoc.exists) return null;
      const recipientData = recipientDoc.data();
      if (!validateUserData(recipientData) || !recipientData.isActive) return null;

      const isSilenced = shouldSilenceNotificationForUser(recipientData, {
        senderId: continuerId,
        candidateTexts: [story.chainTitle]
      });
      if (isSilenced) return null;

      const isCreator = recipientId === chainCreatorId;
      const fcmToken = recipientData.fcmToken || null;
      const shouldSendPush = Boolean(fcmToken) && !isDoNotDisturbActive(recipientData);

      const titleLocKey = isCreator
        ? 'notification.storyChain.creator.title'
        : 'notification.storyChain.participant.title';
      const bodyLocKey = isCreator
        ? 'notification.storyChain.creator.body'
        : 'notification.storyChain.participant.body';
      const titleLocArgs = isCreator ? [username] : [story.chainTitle || ''];
      const bodyLocArgs = isCreator
        ? [story.chainTitle || '', String(totalParts)]
        : [username, String(totalParts)];

      const counts = await getUnreadCounts(recipientId, { type: 'notification', notificationType: 'storyChainContinued' });

      const message = {
        token: fcmToken,
        data: {
          type: 'story_chain_continued',
          chainId: story.chainId,
          storyId: storyId,
          chainTitle: story.chainTitle || '',
          chainPosition: story.chainPosition.toString(),
          totalParts: totalParts.toString(),
          continuerId: continuerId,
          chainCreatorId: chainCreatorId,
          targetType: 'story_chain',
          targetId: story.chainId,
          senderUsername: continuerData.username,
          senderProfileImage: continuerData.profileImagePath || '',
          mediaUrl: storyPreviewUrl || '',
          unreadMessages: String(counts.unreadMessages),
          unreadNotifications: String(counts.unreadNotifications),
          unreadEchoes: String(counts.unreadEchoes),
          unreadTags: String(counts.unreadTags),
        },
        apns: {
          headers: {
            'apns-collapse-id': `chain_${story.chainId}`
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
              'thread-id': `story_chain_${story.chainId}`,
              'summary-arg': continuerData.username,
              'summary-arg-count': totalParts
            }
          }
        }
      };

      if (shouldSendPush) {
        try {
          await admin.messaging().send(message);
        } catch (error) {
          if (error.code === 'messaging/registration-token-not-registered') {
            await removeInvalidToken(recipientId, fcmToken);
          }
          console.error(`❌ Error enviando FCM de Story Chain a ${recipientId}:`, error);
        }
      }

      await admin.firestore().collection(`users/${recipientId}/notifications`).add({
        type: 'storyChainContinued',
        senderId: continuerId,
        senderUsername: continuerData.username,
        senderProfileImage: continuerData.profileImagePath || '',
        chainId: story.chainId,
        chainTitle: story.chainTitle || '',
        storyId: storyId,
        storyAuthorId: storyOwnerId,
        storyPreviewUrl: storyPreviewUrl || null,
        chainPosition: story.chainPosition,
        totalParts: totalParts,
        chainRole: isCreator ? 'creator' : 'participant',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isPending: true
      });
      return null;
    });

    await Promise.all(notificationPromises);
    console.log(`✅ Notificaciones de Story Chain enviadas: ${username} -> ${recipientIds.size} destinatarios (${story.chainTitle}) - Parte ${story.chainPosition}/${totalParts}`);

    // ✅ ACTUALIZAR METADATOS DE LA CADENA
    try {
      const chainRef = admin.firestore().doc(`storyChains/${story.chainId}`);
      await chainRef.set({
        id: story.chainId,
        title: story.chainTitle || '',
        createdBy: chainCreatorId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        partCount: totalParts,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        lastPartBy: continuerId,
        lastPartUsername: continuerData.username
      }, { merge: true });

      console.log(`✅ Metadatos de cadena actualizados: ${story.chainId} - ${totalParts} partes`);
    } catch (chainError) {
      console.warn('⚠️ Error actualizando metadatos de cadena:', chainError);
      // No fallar la notificación por esto
    }

    await markProcessingDone(storyRef, {
      processedField: 'chainNotificationProcessed',
      processingField: 'chainNotificationProcessingUntil'
    });

  } catch (error) {
    const storyRef = admin.firestore().doc(`users/${userId}/stories/${storyId}`);
    await releaseProcessingLock(storyRef, { processingField: 'chainNotificationProcessingUntil' }).catch(() => null);
    console.error('❌ Error sending story chain notification:', error);
  }
});

// 🌊 ECHOES: Notificación cuando se detecta un posible Echo (Nova Spark)
const onEchoCreated = onDocumentCreated('echoes/{echoId}', async (event) => {
  const snap = event.data;
  const { echoId } = event.params;
  const echo = snap.data();

  if (!echo) return null;

  try {
    const participants = echo.participants || [];
    const hostId = echo.hostId;
    // Todos los participantes (incluido el host) empiezan en pending y deben aceptar,
    // así que todos reciben la notificación para poder aceptar el Echo.
    const recipients = participants;

    if (recipients.length === 0) return null;

    console.log(`🌊 Procesando nuevo Echo: ${echoId} con ${recipients.length} participantes`);

    // Obtener datos del host para personalizar la notificación
    const hostDoc = await admin.firestore().doc(`users/${hostId}`).get();
    const hostData = hostDoc.exists ? hostDoc.data() : { username: 'Alguien' };

    const notificationPromises = recipients.map(async (participant) => {
      const recipientId = participant.userId;
      const isHost = recipientId === hostId;

      // 1. Obtener token del destinatario
      const userDoc = await admin.firestore().doc(`users/${recipientId}`).get();
      if (!userDoc.exists) return null;

      const userData = userDoc.data();
      if (!validateUserData(userData)) return null;

      const isSilencedByMuteSettings = shouldSilenceNotificationForUser(userData, {
        senderId: hostId,
        candidateTexts: [echo.title, echo.topic, hostData.username]
      });
      if (isSilencedByMuteSettings) {
        return null;
      }

      const shouldSendPush = Boolean(userData.fcmToken) && !isDoNotDisturbActive(userData);

      // ✅ Obtener conteos actualizados para este receptor (CON CONTEXTO PARA EVITAR RACE CONDITION)
      const counts = await getUnreadCounts(recipientId, { type: 'notification', notificationType: 'echoSuggestion' });

      // 2. Enviar FCM (Nova Spark)
      const message = {
        token: userData.fcmToken,
        data: {
          type: 'echo_suggestion',
          echoId: echoId,
          hostId: hostId,
          targetType: 'echo',
          targetId: echoId,
          senderUsername: hostData.username,
          senderProfileImage: hostData.profileImagePath || '',
          unreadMessages: String(counts.unreadMessages),
          unreadNotifications: String(counts.unreadNotifications),
          unreadEchoes: String(counts.unreadEchoes),
          unreadTags: String(counts.unreadTags),
        },
        apns: {
          headers: {
            'apns-collapse-id': `echo_${recipientId}`
          },
          payload: {
            aps: {
              alert: isHost
              ? {
                  'title-loc-key': 'notification.echo.host.title',
                  'title-loc-args': [],
                  'loc-key': 'notification.echo.host.body',
                  'loc-args': []
                }
              : {
                  'title-loc-key': 'notification.echo.title',
                  'title-loc-args': [],
                  'loc-key': 'notification.echo.body',
                  'loc-args': [hostData.username]
                },
              badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
              sound: 'default',
              'mutable-content': 1,
              'thread-id': `echo_suggestions_${recipientId}`
            }
          }
        }
      };

      if (shouldSendPush) {
        try {
          await admin.messaging().send(message);
        } catch (error) {
          if (error.code === 'messaging/registration-token-not-registered') {
            await removeInvalidToken(recipientId, userData.fcmToken);
          }
          console.error(`❌ Error enviando FCM de Echo a ${recipientId}:`, error);
        }
      }

      // 3. Crear notificación en Firestore
      await admin.firestore().collection(`users/${recipientId}/notifications`).add({
        type: 'echoSuggestion',
        senderId: hostId,
        senderUsername: hostData.username,
        senderProfileImage: hostData.profileImagePath || '',
        echoId: echoId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isPending: true
      });
    });

    await Promise.all(notificationPromises);
    console.log(`✅ Notificaciones de Echo enviadas para ${echoId}`);

  } catch (error) {
    console.error('❌ Error handling echo creation:', error);
  }
});

// ✅ PRIVACY: Permite que un usuario se salga de la lista de mejores amigos de otro usuario

module.exports = {
  onMomentDeleted,
  onStoryDeleted,
  onCommentDeleted,
  onMomentReactionRemoved,
  onStoryChainCreated,
  onStoryChainContinued,
  onEchoCreated,
};
