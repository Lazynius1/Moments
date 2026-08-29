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
  ANDROID_FCM_CHANNELS,
  withAndroidShade,
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

const onFollowerAdded = onDocumentCreated('users/{userId}/followers/{followerId}', async (event) => {
  const snap = event.data;
  const { userId, followerId } = event.params;

  try {
    if (followerId === userId) return null;

    const [followerDoc, userDoc] = await Promise.all([
      admin.firestore().doc(`users/${followerId}`).get(),
      admin.firestore().doc(`users/${userId}`).get()
    ]);

    if (!followerDoc.exists || !userDoc.exists) return null;

    const followerData = followerDoc.data();
    const userData = userDoc.data();

    if (!validateUserData(followerData) || !validateUserData(userData)) {
      console.warn('⚠️ Datos de usuario incompletos para seguidor');
      return null;
    }

    if (!followerData.isActive || !userData.isActive) return null;

    // ✅ Idempotencia por follow
    const followRef = admin.firestore().doc(`users/${userId}/followers/${followerId}`);
    const already = await admin.firestore().runTransaction(async (tx) => {
      const fSnap = await tx.get(followRef);
      if (!fSnap.exists) return true;
      if (fSnap.get('processed') === true) return true;
      tx.update(followRef, { processed: true });
      return false;
    });
    if (already) return null;

    const followData = snap.data() || {};
    const wasAcceptedRequest =
      followData.source === 'followRequestAccepted' ||
      typeof followData.acceptedFollowRequestId === 'string';

    if (wasAcceptedRequest) {
      await sendRequestAcceptedNotification({
        requesterId: followerId,
        accepterId: userId,
        requesterData: followerData,
        accepterData: userData,
        requestId: followData.acceptedFollowRequestId || ''
      });
    }

    const isSilencedForUser = shouldSilenceNotificationForUser(userData, {
      senderId: followerId,
      candidateTexts: [followerData.username]
    });

    const fcmToken = userData.fcmToken || null;
    const shouldSendPush = Boolean(fcmToken) && !isDoNotDisturbActive(userData) && notificationTypeEnabled(userData, 'newFollower');

    // ✅ NUEVO: Verificar si se crea una conexión mutua
    const isMutualConnection = await checkMutualConnection(userId, followerId);

    if (isMutualConnection) {
      await reconcileMutualConnection(userId, followerId, userData, followerData);
      return null;
    }

    if (isSilencedForUser) {
      return null;
    }

    // Obtener conteos
    const [counts, followerCount] = await Promise.all([
      getUnreadCounts(userId, { type: 'notification', notificationType: 'newFollower' }),
      getPendingFollowerCount(userId, followerId)
    ]);

    // Determinar claves de localización
    let titleLocKey, titleLocArgs, bodyLocKey, bodyLocArgs;
    if (followerCount > 1) {
      titleLocKey = 'notification.follower.multiple.title';
      titleLocArgs = [followerData.username, String(followerCount - 1)];
      bodyLocKey = 'notification.follower.multiple.body';
      bodyLocArgs = [String(followerCount)];
    } else {
      titleLocKey = wasAcceptedRequest
        ? 'notification.follower.acceptedRequest.single.title'
        : 'notification.follower.single.title';
      titleLocArgs = [followerData.username];
      bodyLocKey = wasAcceptedRequest
        ? 'notification.follower.acceptedRequest.single.body'
        : 'notification.follower.single.body';
      bodyLocArgs = [];
    }

    // ✅ ENVIAR NOTIFICACIÓN NORMAL
    const message = {
      token: fcmToken,
      data: {
        type: 'new_follower',
        followerId: followerId,
        userId: userId,
        targetType: 'profile',
        targetId: followerId,
        senderUsername: followerData.username,
        senderProfileImage: followerData.profileImagePath || '',
        reactionCount: String(followerCount),
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags),
      },
      apns: {
        headers: {
          'apns-collapse-id': `followers_${userId}`
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
            'thread-id': `new_followers_${userId}`
          }
        }
      }
    };

    if (shouldSendPush) {
      try {
        await admin.messaging().send(withAndroidShade(message, {
          collapseKey: `followers_${userId}`,
          threadId: `new_followers_${userId}`,
          channel: ANDROID_FCM_CHANNELS.social,
        }));
        console.log(`✅ Notificación de seguidor enviada: ${followerData.username} -> ${userData.username}`);
      } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
          await removeInvalidToken(userId, fcmToken);
        }
        throw error;
      }
    }

    await upsertSocialNotification(userId, socialNotificationDocId('newFollower', followerId), {
      type: 'newFollower',
      senderId: followerId,
      senderUsername: followerData.username,
      senderProfileImage: followerData.profileImagePath || ''
    });

  } catch (error) {
    console.error('❌ Error sending follower notification:', error);
  }
});

// 👥 UNFOLLOW: limpiar notificaciones de follow/mutual al borrar edge followers/{id}
const onFollowerRemoved = onDocumentDeleted('users/{userId}/followers/{followerId}', async (event) => {
  const { userId, followerId } = event.params;

  try {
    await Promise.all([
      admin.firestore().doc(`users/${followerId}/following/${userId}`).delete().catch(() => null),
      deleteMutualDocuments(userId, followerId),
      purgeSocialNotifications(userId, { type: 'newFollower', senderId: followerId }),
      purgeSocialNotifications(userId, { type: 'mutualConnection', senderId: followerId }),
      purgeSocialNotifications(followerId, { type: 'mutualConnection', senderId: userId })
    ]);
    console.log(`🧹 Follow relationship reconciled after follower removal: ${followerId} -> ${userId}`);
  } catch (error) {
    console.error('❌ Error purging follow notifications on unfollow:', error);
  }

  return null;
});

// 👥 UNFOLLOW: limpiar edge followers y mutuals al borrar following/{id}
const onFollowingRemoved = onDocumentDeleted('users/{userId}/following/{followingId}', async (event) => {
  const { userId, followingId } = event.params;

  try {
    await Promise.all([
      admin.firestore().doc(`users/${followingId}/followers/${userId}`).delete().catch(() => null),
      deleteMutualDocuments(userId, followingId),
      purgeSocialNotifications(followingId, { type: 'newFollower', senderId: userId }),
      purgeSocialNotifications(userId, { type: 'mutualConnection', senderId: followingId }),
      purgeSocialNotifications(followingId, { type: 'mutualConnection', senderId: userId })
    ]);
    console.log(`🧹 Follow relationship reconciled after following removal: ${userId} -> ${followingId}`);
  } catch (error) {
    console.error('❌ Error purging follow notifications on following removal:', error);
  }

  return null;
});

async function sendRequestAcceptedNotification({ requesterId, accepterId, requesterData, accepterData, requestId }) {
  const isSilencedForRequester = shouldSilenceNotificationForUser(requesterData, {
    senderId: accepterId,
    candidateTexts: [accepterData.username]
  });
  if (isSilencedForRequester) {
    return;
  }

  const notificationId = `requestAccepted_${accepterId}`;
  const notificationRef = admin.firestore().doc(`users/${requesterId}/notifications/${notificationId}`);
  const notificationPayload = {
    type: 'requestAccepted',
    senderId: accepterId,
    senderUsername: accepterData.username,
    senderProfileImage: accepterData.profileImagePath || '',
    requestId: requestId || null,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    isPending: true
  };

  const fcmToken = requesterData.fcmToken || null;
  const shouldSendPush = Boolean(fcmToken) && !isDoNotDisturbActive(requesterData);

  if (shouldSendPush) {
    const counts = await getUnreadCounts(requesterId, {
      type: 'notification',
      notificationType: 'requestAccepted',
      notificationId
    });

    const message = {
      token: fcmToken,
      data: {
        type: 'requestAccepted',
        requestId: requestId || '',
        senderId: accepterId,
        userId: requesterId,
        targetType: 'profile',
        targetId: accepterId,
        senderUsername: accepterData.username,
        senderProfileImage: accepterData.profileImagePath || '',
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags)
      },
      apns: {
        headers: {
          'apns-collapse-id': `ra_${requesterId}_${accepterId}`
        },
        payload: {
          aps: {
            alert: {
              'title-loc-key': 'notification.requestAccepted.title',
              'title-loc-args': [accepterData.username],
              'loc-key': 'notification.requestAccepted.body',
              'loc-args': []
            },
            badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
            sound: 'default',
            'mutable-content': 1,
            'thread-id': `request_accepted_${requesterId}`
          }
        }
      }
    };

    try {
      await admin.messaging().send(withAndroidShade(message, {
        collapseKey: `ra_${requesterId}_${accepterId}`,
        threadId: `request_accepted_${requesterId}`,
        channel: ANDROID_FCM_CHANNELS.social,
      }));
      console.log(`✅ Solicitud aceptada enviada: ${accepterData.username} -> ${requesterData.username}`);
    } catch (error) {
      if (error.code === 'messaging/registration-token-not-registered') {
        await removeInvalidToken(requesterId, fcmToken);
      }
      console.error('❌ Error sending request accepted push:', error);
    }
  }

  await notificationRef.set(notificationPayload, { merge: true });
}

// ✅ FUNCIÓN AUXILIAR: Verificar conexión mutua
async function checkMutualConnection(user1Id, user2Id) {
  try {
    const [user1Followers, user2Followers] = await Promise.all([
      admin.firestore().collection(`users/${user1Id}/followers`).doc(user2Id).get(),
      admin.firestore().collection(`users/${user2Id}/followers`).doc(user1Id).get()
    ]);

    return user1Followers.exists && user2Followers.exists;
  } catch (error) {
    console.error('❌ Error verificando conexión mutua:', error);
    return false;
  }
}


module.exports = {
  onFollowerAdded,
  onFollowerRemoved,
  onFollowingRemoved,
};
