const b = require('../bootstrap');
const h = require('../helpers');

const {
  admin,
  crypto,
  onDocumentCreated,
  onRequest,
  onSchedule
} = b;
const {
  buildViewerContext,
  canViewerSeeMoment,
  canViewerSeeStory,
  findExistingDirectConversation,
  isActiveUserData,
  isDoNotDisturbActive,
  parseJsonBody,
  purgeSocialNotifications,
  removeInvalidToken,
  setProxyCors,
  usersAreBlocked,
  verifyFirebaseAuth
} = h;

const REQUEST_SCHEMA_VERSION = 2;
const REQUEST_MESSAGE_LIMIT = 5;
const DAILY_NEW_RECIPIENT_LIMIT = 10;
const NORMAL_BURST_LIMIT = 5;
const NEW_ACCOUNT_BURST_LIMIT = 3;
const ALLOWED_MESSAGE_TYPES = new Set([
  'text',
  'ephemeral',
  'sharedMoment',
  'sharedStory',
  'viewOnceImage',
  'viewOnceVideo'
]);
const ALLOWED_CONTEXT_KINDS = new Set([
  'general',
  'storyMessage',
  'storyEphemeral',
  'shareStory',
  'shareMoment',
  'forwardText'
]);

function requestThreadId(firstUserId, secondUserId) {
  const pair = [firstUserId, secondUserId].sort().join(':');
  return `dmr_${crypto.createHash('sha256').update(pair).digest('hex').slice(0, 40)}`;
}

function stringValue(value, maxLength = 4096) {
  if (typeof value !== 'string') return '';
  return value.trim().slice(0, maxLength);
}

function booleanValue(value, fallback = false) {
  return typeof value === 'boolean' ? value : fallback;
}

function timestampMillis(value) {
  return value && typeof value.toMillis === 'function' ? value.toMillis() : 0;
}

function isNewAccount(userData, nowMillis) {
  const createdAt = userData.createdAt || userData.accountCreatedAt || userData.joinedAt;
  return timestampMillis(createdAt) > nowMillis - 7 * 24 * 60 * 60 * 1000;
}

function hasServerSafetySignal(userData) {
  return userData.messageRequestSafetyHold === true ||
    userData.safetyRestricted === true ||
    userData.accountSafetyStatus === 'restricted' ||
    userData.accountSafetyStatus === 'suspended';
}

function requestRef(db, threadId) {
  return db.collection('messageRequests').doc(threadId);
}

function outboxRef(db, senderId, threadId) {
  return db.doc(`users/${senderId}/messageRequestOutbox/${threadId}`);
}

function operationRef(db, actorId, operationId) {
  return db.doc(`users/${actorId}/messageRequestOperations/${operationId}`);
}

function metricWrite(db, event, fields = {}) {
  return db.collection('messageRequestMetrics').add({
    event,
    schemaVersion: REQUEST_SCHEMA_VERSION,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    ...fields
  }).catch((error) => {
    console.warn(`messageRequestMetrics/${event} failed`, error);
  });
}

function errorResponse(res, status, errorCode, message) {
  res.status(status).json({ error: message, errorCode });
}

function withAuthenticatedPost(handler) {
  return onRequest({ timeoutSeconds: 60, memory: '256MiB' }, async (req, res) => {
    setProxyCors(res);
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST') {
      errorResponse(res, 405, 'METHOD_NOT_ALLOWED', 'Method not allowed');
      return;
    }

    const actorId = await verifyFirebaseAuth(req, res);
    if (!actorId) return;

    try {
      await handler({ actorId, body: parseJsonBody(req), req, res });
    } catch (error) {
      console.error(`${handler.name || 'messageRequestV2'} failed`, error);
      const status = Number.isInteger(error.httpStatus) ? error.httpStatus : 500;
      const code = stringValue(error.errorCode || error.message, 80) || 'REQUEST_V2_FAILED';
      errorResponse(res, status, code, status === 500 ? 'Message request operation failed' : code);
    }
  });
}

async function loadRelationship(db, actorId, recipientId) {
  const [actorSnap, recipientSnap, actorFollows, recipientFollows, actorMutual, recipientMutual] = await Promise.all([
    db.doc(`users/${actorId}`).get(),
    db.doc(`users/${recipientId}`).get(),
    db.doc(`users/${actorId}/following/${recipientId}`).get(),
    db.doc(`users/${recipientId}/following/${actorId}`).get(),
    db.doc(`users/${actorId}/mutuals/${recipientId}`).get(),
    db.doc(`users/${recipientId}/mutuals/${actorId}`).get()
  ]);

  return {
    actorSnap,
    recipientSnap,
    actorData: actorSnap.data() || {},
    recipientData: recipientSnap.data() || {},
    actorFollowsRecipient: actorFollows.exists,
    recipientFollowsActor: recipientFollows.exists,
    mutual: (actorFollows.exists && recipientFollows.exists) || actorMutual.exists || recipientMutual.exists
  };
}

function storyInteractionAllowed(recipientData, actorId, interactionKind, relationship) {
  if (!interactionKind.startsWith('story')) return true;

  const settings = recipientData.contentVisibilitySettings || {};
  if (interactionKind === 'storyMessage' && settings.allowStoryMessages === false) {
    return false;
  }
  if (interactionKind === 'storyEphemeral' && settings.allowStoryEphemeralPhotos === false) {
    return false;
  }

  const audience = settings.storyAudience || 'everyone';
  if (audience === 'onlyMe') return false;
  if (audience === 'mutuals' && !relationship.mutual) return false;
  if (audience === 'custom' || audience === 'customList') {
    return Array.isArray(settings.storyCustomUsers) && settings.storyCustomUsers.includes(actorId);
  }
  if (Array.isArray(settings.hiddenFromUsers) && settings.hiddenFromUsers.includes(actorId)) return false;
  return true;
}

async function interactionContentAllowed(db, actorId, recipientId, interactionKind, context, relationship) {
  if (!['storyMessage', 'storyEphemeral', 'shareStory', 'shareMoment'].includes(interactionKind)) {
    return true;
  }

  if (['storyMessage', 'storyEphemeral'].includes(interactionKind)) {
    const storyId = stringValue(context.storyId, 160);
    const ownerId = stringValue(context.storyOwnerId, 160);
    if (!storyId || ownerId !== recipientId) return false;
    const storySnap = await db.doc(`users/${ownerId}/stories/${storyId}`).get();
    if (!storySnap.exists) return false;
    const story = { ...storySnap.data(), id: storyId, authorId: ownerId };
    const viewerContext = await buildViewerContext(actorId);
    return canViewerSeeStory(story, actorId, viewerContext, relationship.recipientData);
  }

  const contentId = stringValue(context.sharedContentId, 160);
  const ownerId = stringValue(context.sharedContentOwnerId || context.storyOwnerId, 160);
  if (!contentId || !ownerId) return false;
  const authorSnap = ownerId === actorId
    ? relationship.actorSnap
    : ownerId === recipientId ? relationship.recipientSnap : await db.doc(`users/${ownerId}`).get();
  if (!authorSnap.exists || !isActiveUserData(authorSnap.data() || {})) return false;
  const [actorContext, recipientContext] = await Promise.all([
    buildViewerContext(actorId),
    buildViewerContext(recipientId)
  ]);

  if (interactionKind === 'shareStory') {
    const storySnap = await db.doc(`users/${ownerId}/stories/${contentId}`).get();
    if (!storySnap.exists) return false;
    const story = { ...storySnap.data(), id: contentId, authorId: ownerId };
    return (await canViewerSeeStory(story, actorId, actorContext, authorSnap.data() || {})) &&
      (await canViewerSeeStory(story, recipientId, recipientContext, authorSnap.data() || {}));
  }

  const momentSnap = await db.doc(`users/${ownerId}/moments/${contentId}`).get();
  if (!momentSnap.exists) return false;
  const moment = { ...momentSnap.data(), id: contentId, authorId: ownerId };
  return (await canViewerSeeMoment(moment, actorId, actorContext, authorSnap.data() || {})) &&
    (await canViewerSeeMoment(moment, recipientId, recipientContext, authorSnap.data() || {}));
}

function receiverAllowsRequest(recipientData, actorId, relationship) {
  const policy = recipientData.messageRequestPolicy || 'everyone';
  if (policy === 'nobody') return false;
  if (policy === 'following') return relationship.recipientFollowsActor;
  return true;
}

function sanitizeInteractionContext(kind, rawContext) {
  if (!ALLOWED_CONTEXT_KINDS.has(kind) || !rawContext || typeof rawContext !== 'object') return null;
  const declaredKind = stringValue(rawContext.kind || kind, 40);
  if (declaredKind !== kind) return null;
  const context = { kind };
  if (['storyMessage', 'storyEphemeral'].includes(kind)) {
    context.storyId = stringValue(rawContext.storyId, 160);
    context.storyOwnerId = stringValue(rawContext.storyOwnerId, 160);
    if (!context.storyId || !context.storyOwnerId) return null;
  }
  if (kind === 'shareStory' || kind === 'shareMoment') {
    context.sharedContentId = stringValue(rawContext.sharedContentId, 160);
    context.sharedContentOwnerId = stringValue(rawContext.sharedContentOwnerId || rawContext.storyOwnerId, 160);
    if (!context.sharedContentId || !context.sharedContentOwnerId) return null;
  }
  return context;
}

function sanitizeEncryptedMedia(rawMedia, threadId, messageId) {
  if (!rawMedia || typeof rawMedia !== 'object') return null;
  const kind = stringValue(rawMedia.kind, 20);
  const contentType = stringValue(rawMedia.contentType, 80);
  const fileExtension = stringValue(rawMedia.fileExtension, 12);
  const plaintextSize = Number(rawMedia.plaintextSize);
  const storagePath = stringValue(rawMedia.storagePath, 1024);
  if (!['image', 'video'].includes(kind) ||
      storagePath !== `directThreads/${threadId}/${messageId}/media.enc` ||
      stringValue(rawMedia.version, 20) !== '1.0' ||
      stringValue(rawMedia.algorithm, 80) !== 'AES.GCM+HKDF-SHA256' ||
      stringValue(rawMedia.purpose, 20) !== 'primary' ||
      stringValue(rawMedia.mediaId, 160) !== messageId ||
      !Number.isSafeInteger(plaintextSize) || plaintextSize <= 0 || plaintextSize > 85 * 1024 * 1024 ||
      (kind === 'image' && (contentType !== 'image/jpeg' || fileExtension !== 'jpg')) ||
      (kind === 'video' && (contentType !== 'video/mp4' || fileExtension !== 'mp4'))) {
    return null;
  }
  return {
    version: '1.0',
    algorithm: 'AES.GCM+HKDF-SHA256',
    purpose: 'primary',
    mediaId: messageId,
    contentType,
    fileExtension,
    plaintextSize,
    storagePath,
    kind
  };
}

const routeDirectMessageV2 = withAuthenticatedPost(async function routeDirectMessageV2Handler({ actorId, body, res }) {
  const recipientId = stringValue(body.recipientId, 160);
  const interactionKind = stringValue(body.interactionKind || 'general', 40);
  const interactionContext = sanitizeInteractionContext(
    interactionKind,
    body.context && typeof body.context === 'object' ? body.context : { kind: interactionKind }
  );
  const shouldReserve = body.reserve !== false;
  if (!recipientId || recipientId === actorId || !interactionContext) {
    errorResponse(res, 400, 'INVALID_ROUTE', 'Invalid recipient or entry point');
    return;
  }

  const db = admin.firestore();
  const threadId = requestThreadId(actorId, recipientId);
  const relationship = await loadRelationship(db, actorId, recipientId);
  if (!relationship.actorSnap.exists || !relationship.recipientSnap.exists ||
      !isActiveUserData(relationship.actorData) || !isActiveUserData(relationship.recipientData)) {
    errorResponse(res, 409, 'INACTIVE_USER', 'One of the accounts is unavailable');
    return;
  }
  if (usersAreBlocked(relationship.actorData, actorId, relationship.recipientData, recipientId)) {
    errorResponse(res, 403, 'DENIED', 'Messaging is unavailable');
    return;
  }
  if (!storyInteractionAllowed(relationship.recipientData, actorId, interactionKind, relationship) ||
      !(await interactionContentAllowed(db, actorId, recipientId, interactionKind, interactionContext, relationship))) {
    errorResponse(res, 403, 'DENIED', 'This interaction is unavailable');
    return;
  }

  const existingConversation = await findExistingDirectConversation(actorId, recipientId);
  if (existingConversation) {
    res.status(200).json({ result: 'conversation', conversationId: existingConversation.id });
    return;
  }

  const existingRequestSnap = await requestRef(db, threadId).get();
  if (existingRequestSnap.exists) {
    const data = existingRequestSnap.data() || {};
    if (data.state === 'accepted' || data.status === 'accepted') {
      res.status(200).json({ result: 'conversation', conversationId: data.conversationId || threadId });
      return;
    }
    if (data.state === 'pending' || data.status === 'pending') {
      if (data.receiverId === actorId) {
        res.status(200).json({ result: 'incomingRequest', threadId, messageCount: data.messageCount || 0 });
      } else if (data.initiatorId === actorId || data.senderId === actorId) {
        if (!receiverAllowsRequest(relationship.recipientData, actorId, relationship)) {
          errorResponse(res, 403, 'DENIED', 'This person is not receiving requests from you');
          return;
        }
        res.status(200).json({
          result: 'outgoingRequest',
          threadId,
          messageCount: data.messageCount || 0,
          limit: REQUEST_MESSAGE_LIMIT,
          cryptoConfigured: data.cryptoContext?.configured === true
        });
      } else {
        errorResponse(res, 403, 'DENIED', 'Messaging is unavailable');
      }
      return;
    }
  }

  if (relationship.mutual) {
    res.status(200).json({ result: 'conversationDraft', threadId });
    return;
  }

  if (!receiverAllowsRequest(relationship.recipientData, actorId, relationship)) {
    errorResponse(res, 403, 'DENIED', 'This person is not receiving requests from you');
    return;
  }

  const now = admin.firestore.Timestamp.now();
  const nowMillis = now.toMillis();
  const cooldownSnap = await db.doc(`messageRequestCooldowns/${threadId}`).get();
  if (cooldownSnap.exists && timestampMillis(cooldownSnap.get('until')) > nowMillis) {
    errorResponse(res, 429, 'COOLDOWN', 'Please wait before sending another request');
    return;
  }

  const rateCollection = db.collection(`messageRequestRateLimits/${actorId}/events`);
  const signalsCollection = db.collection(`messageRequestSafety/${actorId}/signals`);
  const [dailyEvents, burstEvents, safetySignals, recipientPreferences] = await Promise.all([
    rateCollection.where('createdAt', '>=', admin.firestore.Timestamp.fromMillis(nowMillis - 24 * 60 * 60 * 1000)).get(),
    rateCollection.where('createdAt', '>=', admin.firestore.Timestamp.fromMillis(nowMillis - 10 * 60 * 1000)).get(),
    signalsCollection.where('createdAt', '>=', admin.firestore.Timestamp.fromMillis(nowMillis - 30 * 24 * 60 * 60 * 1000)).get(),
    db.doc(`users/${recipientId}/messageRequestPreferences/settings`).get()
  ]);
  const recentRecipientIds = new Set(dailyEvents.docs.map((doc) => doc.get('receiverId')).filter(Boolean));
  if (!recentRecipientIds.has(recipientId) && recentRecipientIds.size >= DAILY_NEW_RECIPIENT_LIMIT) {
    await metricWrite(db, 'limitReached', { senderId: actorId, kind: 'rolling24h' });
    errorResponse(res, 429, 'DAILY_LIMIT', 'Daily request limit reached');
    return;
  }

  const distinctNegativeActors = new Set(safetySignals.docs.map((doc) => doc.get('actorId')).filter(Boolean));
  const burstLimit = isNewAccount(relationship.actorData, nowMillis) ? NEW_ACCOUNT_BURST_LIMIT : NORMAL_BURST_LIMIT;
  const automaticFilterEnabled = recipientPreferences.get('automaticFilterEnabled') !== false;
  const safetyHidden = hasServerSafetySignal(relationship.actorData) ||
    (automaticFilterEnabled && (
      distinctNegativeActors.size >= 3 ||
      burstEvents.size + 1 >= burstLimit
    ));
  if (!shouldReserve) {
    res.status(200).json({
      result: 'outgoingRequest',
      threadId,
      messageCount: 0,
      limit: REQUEST_MESSAGE_LIMIT,
      cryptoConfigured: false,
      reserved: false
    });
    return;
  }
  const eventRef = rateCollection.doc();
  const rootRef = requestRef(db, threadId);
  const senderOutboxRef = outboxRef(db, actorId, threadId);

  let creation;
  try {
    creation = await db.runTransaction(async (tx) => {
      const current = await tx.get(rootRef);
      if (current.exists && ['pending', 'accepted'].includes(current.get('state') || current.get('status'))) {
        return { created: false, serverHidden: current.get('serverHidden') === true };
      }
      const [staleMessages, transactionalDailyEvents, transactionalBurstEvents] = await Promise.all([
        current.exists ? tx.get(rootRef.collection('messages').limit(REQUEST_MESSAGE_LIMIT * 2)) : Promise.resolve(null),
        tx.get(rateCollection.where('createdAt', '>=', admin.firestore.Timestamp.fromMillis(nowMillis - 24 * 60 * 60 * 1000))),
        tx.get(rateCollection.where('createdAt', '>=', admin.firestore.Timestamp.fromMillis(nowMillis - 10 * 60 * 1000)))
      ]);
      const transactionalRecipients = new Set(
        transactionalDailyEvents.docs.map((doc) => doc.get('receiverId')).filter(Boolean)
      );
      if (!transactionalRecipients.has(recipientId) && transactionalRecipients.size >= DAILY_NEW_RECIPIENT_LIMIT) {
        throw new Error('DAILY_LIMIT');
      }
      const serverHidden = safetyHidden ||
        (automaticFilterEnabled && transactionalBurstEvents.size + 1 >= burstLimit);
      const folder = serverHidden ? 'hidden' : 'normal';

      const participants = [actorId, recipientId].sort();
      staleMessages?.docs.forEach((doc) => tx.delete(doc.ref));
      tx.set(rootRef, {
      participants,
      initiatorId: actorId,
      senderId: actorId,
      senderUsername: relationship.actorData.username || '',
      senderProfileImagePath: relationship.actorData.profileImagePath || '',
      receiverId: recipientId,
      createdBy: actorId,
      state: 'pending',
      status: 'pending',
      folder,
      serverHidden,
      manualFolder: null,
      schemaVersion: REQUEST_SCHEMA_VERSION,
      generation: (current.data() || {}).generation ? Number(current.get('generation')) + 1 : 1,
      messageCount: 0,
      createdAt: now,
      lastActivityAt: now,
      timestamp: now,
      reservationExpiresAt: admin.firestore.Timestamp.fromMillis(nowMillis + 15 * 60 * 1000),
      rateEventPath: eventRef.path,
      interactionKind,
      cryptoContext: { version: '3.0', configured: false }
      });
      tx.set(senderOutboxRef, {
      threadId,
      receiverId: recipientId,
      receiverUsername: relationship.recipientData.username || '',
      receiverProfileImagePath: relationship.recipientData.profileImagePath || '',
      status: 'pending',
      messageCount: 0,
      limit: REQUEST_MESSAGE_LIMIT,
      createdAt: now,
      lastActivityAt: now,
      reservationExpiresAt: admin.firestore.Timestamp.fromMillis(nowMillis + 15 * 60 * 1000),
      schemaVersion: REQUEST_SCHEMA_VERSION
      });
      tx.set(eventRef, { receiverId: recipientId, threadId, createdAt: now });
      return { created: true, serverHidden };
    });
  } catch (error) {
    if (error.message === 'DAILY_LIMIT') {
      await metricWrite(db, 'limitReached', { senderId: actorId, kind: 'rolling24h' });
      errorResponse(res, 429, 'DAILY_LIMIT', 'Daily request limit reached');
      return;
    }
    throw error;
  }

  if (creation.created) {
    await metricWrite(db, 'created', {
      senderId: actorId,
      receiverId: recipientId,
      serverHidden: creation.serverHidden
    });
  }
  res.status(200).json({
    result: 'outgoingRequest',
    threadId,
    messageCount: 0,
    limit: REQUEST_MESSAGE_LIMIT,
    cryptoConfigured: false
  });
});

function validWrappedKey(value, participantId, actorId) {
  return value && typeof value === 'object' &&
    stringValue(value.wrappedKey, 16384).length >= 40 &&
    stringValue(value.senderPublicKey, 1024).length >= 40 &&
    stringValue(value.recipientKeyId, 256).length > 0 &&
    stringValue(value.wrappedBy, 160) === actorId &&
    participantId.length > 0;
}

const activateDirectConversationV2 = withAuthenticatedPost(async function activateDirectConversationV2Handler({ actorId, body, res }) {
  const recipientId = stringValue(body.recipientId, 160);
  const threadId = stringValue(body.threadId, 80);
  const wrappedKeys = body.wrappedKeys;
  if (!recipientId || recipientId === actorId || requestThreadId(actorId, recipientId) !== threadId ||
      !wrappedKeys || typeof wrappedKeys !== 'object') {
    errorResponse(res, 400, 'INVALID_CRYPTO_CONTEXT', 'Invalid direct conversation context');
    return;
  }

  const db = admin.firestore();
  const relationship = await loadRelationship(db, actorId, recipientId);
  if (!relationship.actorSnap.exists || !relationship.recipientSnap.exists ||
      !isActiveUserData(relationship.actorData) || !isActiveUserData(relationship.recipientData)) {
    errorResponse(res, 409, 'INACTIVE_USER', 'One of the accounts is unavailable');
    return;
  }
  if (!relationship.mutual || usersAreBlocked(relationship.actorData, actorId, relationship.recipientData, recipientId)) {
    errorResponse(res, 403, 'DENIED', 'Messaging is unavailable');
    return;
  }

  const existing = await findExistingDirectConversation(actorId, recipientId);
  if (existing) {
    res.status(200).json({
      success: true,
      conversationId: existing.id,
      usedExistingContext: true
    });
    return;
  }

  const participants = [actorId, recipientId].sort();
  if (participants.some((id) => !validWrappedKey(wrappedKeys[id], id, actorId))) {
    errorResponse(res, 400, 'INVALID_CRYPTO_CONTEXT', 'Invalid direct conversation context');
    return;
  }

  const ref = db.collection('conversations').doc(threadId);
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) {
      const data = snap.data() || {};
      const storedParticipants = Array.isArray(data.participants) ? [...data.participants].sort() : [];
      if (JSON.stringify(storedParticipants) !== JSON.stringify(participants)) {
        throw Object.assign(new Error('DENIED'), { httpStatus: 403, errorCode: 'DENIED' });
      }
      if (data.wrappedKeys && data.cryptoContext?.configured === true) {
        return { conversationId: threadId, usedExistingContext: true };
      }
    }

    tx.set(ref, {
      participants,
      participantData: {
        [actorId]: {
          userId: actorId,
          username: relationship.actorData.username || '',
          profileImagePath: relationship.actorData.profileImagePath || '',
          lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        },
        [recipientId]: {
          userId: recipientId,
          username: relationship.recipientData.username || '',
          profileImagePath: relationship.recipientData.profileImagePath || '',
          lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        }
      },
      schemaVersion: 2,
      directThreadId: threadId,
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      acceptedBy: 'mutualRelationship',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      readStatus: { [actorId]: true, [recipientId]: true },
      wrappedKeys,
      conversationKeyVersion: 1,
      encryptionVersion: '3.0',
      cryptoContext: { version: '3.0', configured: true, wrappedBy: actorId }
    }, { merge: true });
    return { conversationId: threadId, usedExistingContext: false };
  });

  res.status(200).json({ success: true, ...result });
});

const configureMessageRequestV2 = withAuthenticatedPost(async function configureMessageRequestV2Handler({ actorId, body, res }) {
  const threadId = stringValue(body.threadId, 80);
  const wrappedKeys = body.wrappedKeys;
  if (!threadId || !wrappedKeys || typeof wrappedKeys !== 'object') {
    errorResponse(res, 400, 'INVALID_CRYPTO_CONTEXT', 'Missing encryption context');
    return;
  }

  const db = admin.firestore();
  const ref = requestRef(db, threadId);
  const configuration = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new Error('REQUEST_NOT_FOUND');
    const data = snap.data() || {};
    const participants = Array.isArray(data.participants) ? data.participants : [];
    if (data.initiatorId !== actorId || data.state !== 'pending') throw new Error('REQUEST_FORBIDDEN');
    if (data.cryptoContext?.configured === true && data.wrappedKeys) {
      const existingSenderKey = data.wrappedKeys[actorId];
      tx.set(outboxRef(db, actorId, threadId), {
        wrappedKey: existingSenderKey,
        conversationKeyVersion: data.conversationKeyVersion || 1,
        encryptionVersion: data.encryptionVersion || '3.0'
      }, { merge: true });
      return { usedExistingContext: true };
    }
    if (participants.length !== 2 || participants.some((id) => !validWrappedKey(wrappedKeys[id], id, actorId))) {
      throw new Error('INVALID_CRYPTO_CONTEXT');
    }
    tx.update(ref, {
      wrappedKeys,
      conversationKeyVersion: 1,
      encryptionVersion: '3.0',
      cryptoContext: { version: '3.0', configured: true, wrappedBy: actorId },
      cryptoConfiguredAt: admin.firestore.FieldValue.serverTimestamp()
    });
    tx.set(outboxRef(db, actorId, threadId), {
      wrappedKey: wrappedKeys[actorId],
      conversationKeyVersion: 1,
      encryptionVersion: '3.0'
    }, { merge: true });
    return { usedExistingContext: false };
  }).catch((error) => {
    if (error.message === 'REQUEST_NOT_FOUND') throw Object.assign(error, { httpStatus: 404 });
    if (error.message === 'REQUEST_FORBIDDEN') throw Object.assign(error, { httpStatus: 403 });
    throw error;
  });
  res.status(200).json({ success: true, threadId, ...configuration });
});

function validateMessagePayload(message, threadId) {
  if (!message || typeof message !== 'object') return null;
  const id = stringValue(message.id, 160);
  const content = typeof message.ciphertext === 'string' ? message.ciphertext : message.content;
  const type = stringValue(message.type, 40);
  const rawContext = message.context && typeof message.context === 'object' ? message.context : {};
  const contextKind = stringValue(rawContext.kind || 'general', 40);
  const context = sanitizeInteractionContext(contextKind, rawContext);
  if (!id || typeof content !== 'string' || !content || content.length > 65536 ||
      !ALLOWED_MESSAGE_TYPES.has(type) || !context) return null;

  const hasMedia = message.media && typeof message.media === 'object';
  const media = hasMedia ? sanitizeEncryptedMedia(message.media, threadId, id) : null;
  if (hasMedia && !media) return null;
  if (['ephemeral', 'viewOnceImage', 'viewOnceVideo'].includes(type) && !media) return null;
  if (media && !['ephemeral', 'viewOnceImage', 'viewOnceVideo'].includes(type)) return null;
  if (type === 'sharedMoment' && contextKind !== 'shareMoment') return null;
  if (type === 'sharedStory' && contextKind !== 'shareStory') return null;
  if (contextKind === 'shareMoment' && type !== 'sharedMoment') return null;
  if (contextKind === 'shareStory' && type !== 'sharedStory') return null;
  if (contextKind === 'storyEphemeral' && !['ephemeral', 'viewOnceImage', 'viewOnceVideo'].includes(type)) return null;
  if (['storyMessage', 'storyEphemeral'].includes(contextKind) &&
      (!stringValue(context.storyId, 160) || !stringValue(context.storyOwnerId, 160))) return null;
  if (['shareMoment', 'shareStory'].includes(contextKind) && !stringValue(context.sharedContentId, 160)) return null;

  return {
    id,
    content,
    type,
    contextKind,
    context,
    media,
    clientNonce: stringValue(message.clientNonce || id, 160),
    expirationDateMillis: Number.isFinite(message.expirationDateMillis) ? message.expirationDateMillis : null,
    isViewOnce: type === 'viewOnceImage' || type === 'viewOnceVideo',
    allowReplay: booleanValue(message.allowReplay, type === 'ephemeral')
  };
}

function acceptedMessageContextFields(source) {
  const context = source.context && typeof source.context === 'object' ? source.context : {};
  const kind = stringValue(source.contextKind || context.kind || 'general', 40);
  if (kind === 'storyMessage' || kind === 'storyEphemeral') {
    return {
      storyReplyData: {
        storyId: stringValue(context.storyId, 160),
        storyAuthorId: stringValue(context.storyOwnerId, 160)
      }
    };
  }
  if (kind === 'shareMoment') {
    return {
      sharedMomentData: {
        momentId: stringValue(context.sharedContentId, 160),
        momentAuthorId: stringValue(context.sharedContentOwnerId, 160)
      }
    };
  }
  if (kind === 'shareStory') {
    return {
      sharedStoryData: {
        storyId: stringValue(context.sharedContentId, 160),
        storyAuthorId: stringValue(context.sharedContentOwnerId, 160)
      }
    };
  }
  return {};
}

const appendMessageRequestV2 = withAuthenticatedPost(async function appendMessageRequestV2Handler({ actorId, body, res }) {
  const threadId = stringValue(body.threadId, 80);
  const payload = validateMessagePayload(body.message, threadId);
  if (!threadId || !payload) {
    errorResponse(res, 400, 'INVALID_MESSAGE', 'Unsupported or invalid request message');
    return;
  }

  const db = admin.firestore();
  const rootRef = requestRef(db, threadId);
  const messageRef = rootRef.collection('messages').doc(payload.id);
  const initialRoot = await rootRef.get();
  if (!initialRoot.exists) {
    errorResponse(res, 404, 'REQUEST_NOT_FOUND', 'REQUEST_NOT_FOUND');
    return;
  }
  const initialData = initialRoot.data() || {};
  const recipientId = stringValue(initialData.receiverId, 160);
  if (initialData.initiatorId !== actorId || initialData.state !== 'pending' || !recipientId) {
    errorResponse(res, 403, 'REQUEST_FORBIDDEN', 'REQUEST_FORBIDDEN');
    return;
  }
  const relationship = await loadRelationship(db, actorId, recipientId);
  if (!relationship.actorSnap.exists || !relationship.recipientSnap.exists ||
      !isActiveUserData(relationship.actorData) || !isActiveUserData(relationship.recipientData) ||
      usersAreBlocked(relationship.actorData, actorId, relationship.recipientData, recipientId) ||
      !receiverAllowsRequest(relationship.recipientData, actorId, relationship) ||
      !storyInteractionAllowed(relationship.recipientData, actorId, payload.contextKind, relationship) ||
      !(await interactionContentAllowed(db, actorId, recipientId, payload.contextKind, payload.context, relationship))) {
    errorResponse(res, 403, 'DENIED', 'Messaging is unavailable');
    return;
  }
  let result;
  try {
    result = await db.runTransaction(async (tx) => {
      const [rootSnap, existingMessage] = await Promise.all([tx.get(rootRef), tx.get(messageRef)]);
      if (!rootSnap.exists) throw new Error('REQUEST_NOT_FOUND');
      const data = rootSnap.data() || {};
      if (data.initiatorId !== actorId || data.state !== 'pending') throw new Error('REQUEST_FORBIDDEN');
      if (!data.cryptoContext || data.cryptoContext.configured !== true || !data.wrappedKeys) {
        throw new Error('CRYPTO_NOT_CONFIGURED');
      }
      if (existingMessage.exists) {
        return { messageId: payload.id, messageCount: Number(data.messageCount || 0), idempotent: true };
      }
      const messageCount = Number(data.messageCount || 0);
      if (messageCount >= REQUEST_MESSAGE_LIMIT) throw new Error('MESSAGE_LIMIT');

      const sequence = messageCount + 1;
      const now = admin.firestore.Timestamp.now();
      const expirationDate = payload.expirationDateMillis && payload.expirationDateMillis > now.toMillis()
        ? admin.firestore.Timestamp.fromMillis(payload.expirationDateMillis)
        : null;
      if (payload.type === 'ephemeral' &&
          (!expirationDate || expirationDate.toMillis() > now.toMillis() + 24 * 60 * 60 * 1000 + 5 * 60 * 1000)) {
        throw new Error('INVALID_EPHEMERAL');
      }
      tx.create(messageRef, {
        id: payload.id,
        threadId,
        conversationId: threadId,
        senderId: actorId,
        content: payload.content,
        type: payload.type,
        sequence,
        timestamp: now,
        status: 'sent',
        encryptionVersion: '3.0',
        clientNonce: payload.clientNonce,
        context: payload.context,
        contextKind: payload.contextKind,
        ...(payload.media ? { encryptedMedia: payload.media, mediaUrl: payload.media.storagePath } : {}),
        ...(expirationDate ? { expirationDate } : {}),
        ...(payload.isViewOnce ? { isViewOnce: true } : {}),
        ...(payload.allowReplay ? { allowReplay: true } : {})
      });
      tx.update(rootRef, {
        messageCount: sequence,
        lastActivityAt: now,
        timestamp: now,
        folder: data.folder === 'old' && data.manualFolder !== 'hidden' ? 'normal' : data.folder,
        lastMessageType: payload.type,
        ...(expirationDate &&
          (!data.nextMediaExpirationAt || timestampMillis(data.nextMediaExpirationAt) > expirationDate.toMillis())
          ? { nextMediaExpirationAt: expirationDate }
          : {}),
        reservationExpiresAt: admin.firestore.FieldValue.delete()
      });
      tx.set(outboxRef(db, actorId, threadId), {
        messageCount: sequence,
        lastActivityAt: now,
        status: 'pending',
        reservationExpiresAt: admin.firestore.FieldValue.delete()
      }, { merge: true });

      return { messageId: payload.id, messageCount: sequence, idempotent: false };
    });
  } catch (error) {
    const mapping = {
      REQUEST_NOT_FOUND: [404, 'REQUEST_NOT_FOUND'],
      REQUEST_FORBIDDEN: [403, 'REQUEST_FORBIDDEN'],
      CRYPTO_NOT_CONFIGURED: [409, 'CRYPTO_NOT_CONFIGURED'],
      MESSAGE_LIMIT: [429, 'MESSAGE_LIMIT'],
      INVALID_EPHEMERAL: [400, 'INVALID_EPHEMERAL']
    };
    const mapped = mapping[error.message];
    if (mapped) {
      errorResponse(res, mapped[0], mapped[1], error.message);
      return;
    }
    throw error;
  }

  if (!result.idempotent) await metricWrite(db, 'messageAppended', { senderId: actorId, messageType: payload.type });
  res.status(200).json({ success: true, threadId, ...result, limit: REQUEST_MESSAGE_LIMIT });
});

async function acceptedRequestResult(db, data, threadId) {
  return {
    success: true,
    conversationId: data.conversationId || threadId,
    messageIds: Array.isArray(data.acceptedMessageIds) ? data.acceptedMessageIds : [],
    messageId: Array.isArray(data.acceptedMessageIds) ? data.acceptedMessageIds[0] || null : null
  };
}

const acceptMessageRequestV2 = withAuthenticatedPost(async function acceptMessageRequestV2Handler({ actorId, body, res }) {
  const threadId = stringValue(body.threadId || body.requestId, 80);
  if (!threadId) {
    errorResponse(res, 400, 'REQUEST_NOT_FOUND', 'Missing request id');
    return;
  }
  const db = admin.firestore();
  const rootRef = requestRef(db, threadId);
  let accepted;
  try {
    accepted = await db.runTransaction(async (tx) => {
      const rootSnap = await tx.get(rootRef);
      if (!rootSnap.exists) throw new Error('REQUEST_NOT_FOUND');
      const data = rootSnap.data() || {};
      if (data.receiverId !== actorId) throw new Error('REQUEST_FORBIDDEN');
      if (data.state === 'accepted' || data.status === 'accepted') return acceptedRequestResult(db, data, threadId);
      if (data.state !== 'pending' && data.status !== 'pending') throw new Error('REQUEST_NOT_PENDING');
      const messagesSnap = await tx.get(rootRef.collection('messages').orderBy('sequence', 'asc').limit(REQUEST_MESSAGE_LIMIT));
      const participants = Array.isArray(data.participants) ? data.participants : [];
      if (participants.length !== 2 || !data.wrappedKeys || messagesSnap.empty) throw new Error('REQUEST_UNTRUSTED');

      const userSnaps = await Promise.all(participants.map((id) => tx.get(db.doc(`users/${id}`))));
      if (userSnaps.some((snap) => !snap.exists || !isActiveUserData(snap.data() || {}))) throw new Error('INACTIVE_USER');
      if (usersAreBlocked(userSnaps[0].data() || {}, participants[0], userSnaps[1].data() || {}, participants[1])) {
        throw new Error('BLOCKED_RELATIONSHIP');
      }

      const conversationRef = db.collection('conversations').doc(threadId);
      const messageIds = messagesSnap.docs.map((doc) => doc.id);
      const receiptSnaps = await Promise.all(messageIds.map((id) =>
        tx.get(db.doc(`users/${actorId}/pendingEphemeralReceipts/${threadId}_${id}`))
      ));
      const senderId = data.initiatorId || data.senderId;
      const participantData = {};
      userSnaps.forEach((snap) => {
        const user = snap.data() || {};
        participantData[snap.id] = {
          userId: snap.id,
          username: user.username || '',
          profileImagePath: user.profileImagePath || '',
          lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        };
      });
      const lastMessage = messagesSnap.docs[messagesSnap.docs.length - 1].data();
      tx.set(conversationRef, {
        participants,
        participantData,
        directThreadId: threadId,
        sourceRequestId: threadId,
        schemaVersion: REQUEST_SCHEMA_VERSION,
        wrappedKeys: data.wrappedKeys,
        conversationKeyVersion: data.conversationKeyVersion || 1,
        encryptionVersion: data.encryptionVersion || '3.0',
        acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
        acceptedBy: actorId,
        lastMessage: '',
        lastMessageType: lastMessage.type || 'text',
        timestamp: lastMessage.timestamp || admin.firestore.FieldValue.serverTimestamp(),
        readStatus: { [senderId]: true, [actorId]: true }
      }, { merge: true });

      messagesSnap.docs.forEach((doc, index) => {
        const source = doc.data();
        const encryptedMedia = source.encryptedMedia && typeof source.encryptedMedia === 'object'
          ? source.encryptedMedia
          : null;
        const receipt = receiptSnaps[index];
        const viewed = receipt.exists;
        tx.set(conversationRef.collection('messages').doc(doc.id), {
          ...source,
          ...acceptedMessageContextFields(source),
          conversationId: threadId,
          sourceRequestId: threadId,
          processed: true,
          isRead: true,
          isViewed: viewed,
          ...(encryptedMedia ? {
            mediaObjectPath: encryptedMedia.storagePath,
            mediaEncryption: encryptedMedia
          } : {}),
          ...(viewed ? { viewedAt: receipt.get('viewedAt') } : {})
        }, { merge: true });
      });
      tx.update(rootRef, {
        state: 'accepted',
        status: 'accepted',
        acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
        acceptedBy: actorId,
        conversationId: threadId,
        acceptedMessageIds: messageIds
      });
      tx.set(outboxRef(db, senderId, threadId), {
        status: 'accepted',
        conversationId: threadId,
        acceptedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
      receiptSnaps.forEach((snap) => {
        if (snap.exists) tx.set(snap.ref, { syncedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
      });
      return { success: true, conversationId: threadId, messageIds, messageId: messageIds[0] || null };
    });
  } catch (error) {
    const statusByCode = {
      REQUEST_NOT_FOUND: 404,
      REQUEST_FORBIDDEN: 403,
      REQUEST_NOT_PENDING: 409,
      REQUEST_UNTRUSTED: 403,
      INACTIVE_USER: 409,
      BLOCKED_RELATIONSHIP: 403
    };
    if (statusByCode[error.message]) {
      errorResponse(res, statusByCode[error.message], error.message, error.message);
      return;
    }
    throw error;
  }
  await metricWrite(db, 'accepted', { receiverId: actorId, messageCount: accepted.messageIds.length });
  res.status(200).json(accepted);
});

async function cleanDirectThreadMedia(threadId) {
  try {
    await admin.storage().bucket().deleteFiles({ prefix: `directThreads/${threadId}/`, force: true });
  } catch (error) {
    console.warn(`Failed to clean directThreads/${threadId}`, error);
  }
}

const manageMessageRequestV2 = withAuthenticatedPost(async function manageMessageRequestV2Handler({ actorId, body, res }) {
  const threadId = stringValue(body.threadId || body.requestId, 80);
  const action = stringValue(body.action, 32);
  const allowedActions = new Set(['reject', 'cancel', 'moveToRequests', 'moveToHidden', 'report', 'block']);
  if (!threadId || !allowedActions.has(action)) {
    errorResponse(res, 400, 'INVALID_ACTION', 'Invalid request action');
    return;
  }

  const db = admin.firestore();
  const rootRef = requestRef(db, threadId);
  let cleanupMedia = false;
  let blockedUserId = null;
  let metric = action;
  let operationResult;
  try {
    operationResult = await db.runTransaction(async (tx) => {
      const snap = await tx.get(rootRef);
      if (!snap.exists) throw new Error('REQUEST_NOT_FOUND');
      const data = snap.data() || {};
      const operationId = `${threadId}_${action}_g${Number(data.generation || 1)}`;
      const receiptRef = operationRef(db, actorId, operationId);
      const priorReceipt = await tx.get(receiptRef);
      if (priorReceipt.exists) return { idempotent: true };
      const isReceiver = data.receiverId === actorId;
      const isSender = (data.initiatorId || data.senderId) === actorId;
      if ((action === 'cancel' && !isSender) || (action !== 'cancel' && !isReceiver)) {
        throw new Error('REQUEST_FORBIDDEN');
      }

      const now = admin.firestore.Timestamp.now();
      const senderId = data.initiatorId || data.senderId;
      if (action === 'moveToRequests' || action === 'moveToHidden') {
        if (data.state !== 'pending') throw new Error('REQUEST_NOT_PENDING');
        if (action === 'moveToRequests') {
          const senderSnap = await tx.get(db.doc(`users/${senderId}`));
          if (hasServerSafetySignal(senderSnap.data() || {})) throw new Error('SAFETY_RESTRICTED');
        }
        const folder = action === 'moveToRequests' ? 'normal' : 'hidden';
        tx.update(rootRef, { folder, manualFolder: folder, folderUpdatedAt: now });
      } else {
        const nextState = action === 'cancel' ? 'cancelled' : action === 'block' ? 'blocked' : 'rejected';
        tx.update(rootRef, { state: nextState, status: nextState, resolvedAt: now, resolvedBy: actorId });
        tx.set(outboxRef(db, senderId, threadId), { status: nextState, resolvedAt: now }, { merge: true });
        const cooldownHours = action === 'cancel' ? 24 : 30 * 24;
        tx.set(db.doc(`messageRequestCooldowns/${threadId}`), {
          senderId,
          receiverId: data.receiverId,
          reason: action,
          until: admin.firestore.Timestamp.fromMillis(now.toMillis() + cooldownHours * 60 * 60 * 1000),
          createdAt: now
        });
        cleanupMedia = true;

        if (action === 'reject' || action === 'report' || action === 'block') {
          tx.set(db.doc(`messageRequestSafety/${senderId}/signals/${actorId}`), {
            actorId,
            type: action,
            threadId,
            createdAt: now
          }, { merge: true });
        }
        if (action === 'block') {
          blockedUserId = senderId;
          tx.update(db.doc(`users/${actorId}`), {
            blockedUsers: admin.firestore.FieldValue.arrayUnion(senderId)
          });
          tx.delete(db.doc(`users/${actorId}/following/${senderId}`));
          tx.delete(db.doc(`users/${actorId}/followers/${senderId}`));
          tx.delete(db.doc(`users/${actorId}/mutuals/${senderId}`));
          tx.delete(db.doc(`users/${senderId}/following/${actorId}`));
          tx.delete(db.doc(`users/${senderId}/followers/${actorId}`));
          tx.delete(db.doc(`users/${senderId}/mutuals/${actorId}`));
          tx.delete(db.doc(`users/${actorId}/visits/${senderId}`));
          tx.delete(db.doc(`users/${senderId}/visits/${actorId}`));
        }
      }
      tx.set(receiptRef, { threadId, action, createdAt: now });
      return { idempotent: false };
    });
  } catch (error) {
    if (error.message === 'REQUEST_NOT_FOUND') {
      errorResponse(res, 404, error.message, error.message);
      return;
    }
    if (error.message === 'REQUEST_FORBIDDEN') {
      errorResponse(res, 403, error.message, error.message);
      return;
    }
    if (error.message === 'REQUEST_NOT_PENDING') {
      errorResponse(res, 409, error.message, error.message);
      return;
    }
    if (error.message === 'SAFETY_RESTRICTED') {
      errorResponse(res, 403, error.message, error.message);
      return;
    }
    throw error;
  }

  if (operationResult.idempotent) {
    res.status(200).json({ success: true, idempotent: true, action });
    return;
  }

  if (cleanupMedia) await cleanDirectThreadMedia(threadId);
  if (blockedUserId) {
    await Promise.all([
      purgeSocialNotifications(actorId, { type: 'newFollower', senderId: blockedUserId }),
      purgeSocialNotifications(actorId, { type: 'mutualConnection', senderId: blockedUserId }),
      purgeSocialNotifications(actorId, { type: 'followRequest', senderId: blockedUserId }),
      purgeSocialNotifications(blockedUserId, { type: 'newFollower', senderId: actorId }),
      purgeSocialNotifications(blockedUserId, { type: 'mutualConnection', senderId: actorId }),
      purgeSocialNotifications(blockedUserId, { type: 'followRequest', senderId: actorId })
    ]);
  }
  await metricWrite(db, metric, { actorId });
  res.status(200).json({ success: true, idempotent: false, action });
});

const consumePendingEphemeralV2 = withAuthenticatedPost(async function consumePendingEphemeralV2Handler({ actorId, body, res }) {
  const threadId = stringValue(body.threadId, 80);
  const messageId = stringValue(body.messageId, 160);
  if (!threadId || !messageId) {
    errorResponse(res, 400, 'INVALID_EPHEMERAL', 'Missing ephemeral reference');
    return;
  }
  const db = admin.firestore();
  const rootRef = requestRef(db, threadId);
  const messageRef = rootRef.collection('messages').doc(messageId);
  const receiptRef = db.doc(`users/${actorId}/pendingEphemeralReceipts/${threadId}_${messageId}`);
  try {
    const consumption = await db.runTransaction(async (tx) => {
      const [rootSnap, messageSnap, receiptSnap] = await Promise.all([
        tx.get(rootRef),
        tx.get(messageRef),
        tx.get(receiptRef)
      ]);
      if (!rootSnap.exists || !messageSnap.exists || rootSnap.get('receiverId') !== actorId) {
        throw new Error('REQUEST_NOT_FOUND');
      }
      const message = messageSnap.data() || {};
      if (!['ephemeral', 'viewOnceImage', 'viewOnceVideo'].includes(message.type)) {
        throw new Error('INVALID_EPHEMERAL');
      }
      if (message.expirationDate && timestampMillis(message.expirationDate) <= Date.now()) {
        throw new Error('EPHEMERAL_EXPIRED');
      }
      const previousViews = receiptSnap.exists ? Number(receiptSnap.get('viewCount') || 1) : 0;
      const maxViews = message.isViewOnce ? (message.allowReplay === true ? 2 : 1) : Number.MAX_SAFE_INTEGER;
      if (previousViews >= maxViews) throw new Error('EPHEMERAL_CONSUMED');
      const viewedAt = admin.firestore.Timestamp.now();
      tx.set(receiptRef, {
        threadId,
        messageId,
        firstViewedAt: receiptSnap.exists ? receiptSnap.get('firstViewedAt') || receiptSnap.get('viewedAt') : viewedAt,
        viewedAt,
        viewCount: previousViews + 1,
        schemaVersion: REQUEST_SCHEMA_VERSION
      }, { merge: true });
      return { viewCount: previousViews + 1, replayRemaining: previousViews + 1 < maxViews };
    });
    res.status(200).json({ success: true, ...consumption });
  } catch (error) {
    const mapping = {
      REQUEST_NOT_FOUND: [404, 'REQUEST_NOT_FOUND'],
      INVALID_EPHEMERAL: [400, 'INVALID_EPHEMERAL'],
      EPHEMERAL_EXPIRED: [410, 'EPHEMERAL_EXPIRED'],
      EPHEMERAL_CONSUMED: [410, 'EPHEMERAL_CONSUMED']
    };
    const mapped = mapping[error.message];
    if (mapped) {
      errorResponse(res, mapped[0], mapped[1], mapped[1]);
      return;
    }
    throw error;
  }
});

const onMessageRequestV2MessageCreated = onDocumentCreated('messageRequests/{threadId}/messages/{messageId}', async (event) => {
  const message = event.data.data() || {};
  const { threadId } = event.params;
  const db = admin.firestore();
  const rootRef = requestRef(db, threadId);
  const shouldNotify = await db.runTransaction(async (tx) => {
    const snap = await tx.get(rootRef);
    if (!snap.exists) return null;
    const data = snap.data() || {};
    if (data.schemaVersion !== REQUEST_SCHEMA_VERSION || data.folder !== 'normal' || data.notificationSentAt) return null;
    if (Number(message.sequence || 0) !== 1) return null;
    tx.update(rootRef, { notificationSentAt: admin.firestore.FieldValue.serverTimestamp() });
    return { receiverId: data.receiverId, senderId: data.initiatorId || data.senderId };
  });
  if (!shouldNotify) return null;

  const receiverSnap = await db.doc(`users/${shouldNotify.receiverId}`).get();
  const receiver = receiverSnap.data() || {};
  if (!receiver.fcmToken || isDoNotDisturbActive(receiver)) return null;
  const notification = {
    token: receiver.fcmToken,
    data: {
      type: 'message_request_v2',
      threadId,
      senderId: shouldNotify.senderId,
      sensitiveContent: 'false'
    },
    apns: {
      headers: { 'apns-collapse-id': `mr_${threadId.slice(-48)}` },
      payload: {
        aps: {
          alert: {
            title: 'Moments',
            'loc-key': 'notification.messageRequest.generic',
            'loc-args': []
          },
          sound: 'default',
          'mutable-content': 0,
          'thread-id': `message_request_${threadId}`
        }
      }
    },
    android: {
      priority: 'high',
      // Data-only: Android descifra y aplica palabras personalizadas antes de decidir
      // si debe mostrar el único aviso genérico. Nunca se incluye contenido sensible.
      collapseKey: `message_request_${threadId.slice(-48)}`
    }
  };
  try {
    await admin.messaging().send(notification);
  } catch (error) {
    if (error.code === 'messaging/registration-token-not-registered') {
      await removeInvalidToken(shouldNotify.receiverId, receiver.fcmToken);
    } else {
      throw error;
    }
  }
  return null;
});

const archiveOldMessageRequestsV2 = onSchedule({
  schedule: 'every 6 hours',
  timeZone: 'Europe/Madrid',
  region: 'us-central1',
  timeoutSeconds: 540,
  memory: '512MiB',
  concurrency: 1
}, async () => {
  const db = admin.firestore();
  const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - 30 * 24 * 60 * 60 * 1000);
  let archived = 0;
  while (archived < 2000) {
    const snapshot = await db.collection('messageRequests')
      .where('schemaVersion', '==', REQUEST_SCHEMA_VERSION)
      .where('state', '==', 'pending')
      .where('folder', '==', 'normal')
      .where('lastActivityAt', '<=', cutoff)
      .limit(400)
      .get();
    if (snapshot.empty) break;
    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.update(doc.ref, {
      folder: 'old',
      archivedAt: admin.firestore.FieldValue.serverTimestamp()
    }));
    await batch.commit();
    archived += snapshot.size;
    if (snapshot.size < 400) break;
  }
  if (archived > 0) await metricWrite(db, 'archived', { count: archived });
});

const cleanupEmptyMessageRequestReservationsV2 = onSchedule({
  schedule: 'every 15 minutes',
  timeZone: 'Europe/Madrid',
  region: 'us-central1',
  timeoutSeconds: 540,
  memory: '256MiB',
  concurrency: 1
}, async () => {
  const db = admin.firestore();
  const now = admin.firestore.Timestamp.now();
  const snapshot = await db.collection('messageRequests')
    .where('reservationExpiresAt', '<=', now)
    .limit(400)
    .get();
  let cleaned = 0;
  for (const candidate of snapshot.docs) {
    const didClean = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(candidate.ref);
      if (!fresh.exists) return false;
      const data = fresh.data() || {};
      if (data.schemaVersion !== REQUEST_SCHEMA_VERSION || data.state !== 'pending' ||
          Number(data.messageCount || 0) !== 0 || timestampMillis(data.reservationExpiresAt) > Date.now()) {
        return false;
      }
      const senderId = stringValue(data.initiatorId || data.senderId, 160);
      if (senderId) tx.delete(outboxRef(db, senderId, candidate.id));
      const rateEventPath = stringValue(data.rateEventPath, 1024);
      if (rateEventPath.startsWith('messageRequestRateLimits/')) tx.delete(db.doc(rateEventPath));
      tx.delete(fresh.ref);
      return true;
    });
    if (didClean) cleaned += 1;
  }
  if (cleaned > 0) await metricWrite(db, 'emptyReservationsCleaned', { count: cleaned });
});

const cleanupExpiredMessageRequestMediaV2 = onSchedule({
  schedule: 'every 30 minutes',
  timeZone: 'Europe/Madrid',
  region: 'us-central1',
  timeoutSeconds: 540,
  memory: '512MiB',
  concurrency: 1
}, async () => {
  const db = admin.firestore();
  const now = admin.firestore.Timestamp.now();
  const roots = await db.collection('messageRequests')
    .where('nextMediaExpirationAt', '<=', now)
    .limit(200)
    .get();
  let cleaned = 0;

  for (const root of roots.docs) {
    const rootData = root.data() || {};
    if (rootData.schemaVersion !== REQUEST_SCHEMA_VERSION) continue;
    const messages = await root.ref.collection('messages').get();
    const expired = messages.docs.filter((message) => {
      const data = message.data() || {};
      return timestampMillis(data.expirationDate) > 0 && timestampMillis(data.expirationDate) <= now.toMillis();
    });
    const successfullyDeleted = [];

    for (const message of expired) {
      const media = message.get('encryptedMedia');
      const storagePath = media && typeof media === 'object' ? stringValue(media.storagePath, 1024) : '';
      if (storagePath && storagePath.startsWith(`directThreads/${root.id}/`)) {
        try {
          await admin.storage().bucket().file(storagePath).delete({ ignoreNotFound: true });
        } catch (error) {
          console.warn(`Failed to clean expired request media ${storagePath}`, error);
          continue;
        }
      }
      successfullyDeleted.push(message);
    }

    const deletedIds = new Set(successfullyDeleted.map((message) => message.id));
    const remainingExpirations = messages.docs
      .filter((message) => !deletedIds.has(message.id))
      .map((message) => timestampMillis(message.get('expirationDate')))
      .filter((millis) => millis > now.toMillis())
      .sort((left, right) => left - right);
    const batch = db.batch();
    successfullyDeleted.forEach((message) => batch.update(message.ref, {
      expiredAt: admin.firestore.FieldValue.serverTimestamp(),
      encryptedMedia: admin.firestore.FieldValue.delete(),
      mediaUrl: admin.firestore.FieldValue.delete()
    }));
    batch.update(root.ref, remainingExpirations.length > 0
      ? { nextMediaExpirationAt: admin.firestore.Timestamp.fromMillis(remainingExpirations[0]) }
      : { nextMediaExpirationAt: admin.firestore.FieldValue.delete() });
    await batch.commit();
    cleaned += successfullyDeleted.length;
  }

  if (cleaned > 0) await metricWrite(db, 'expiredMediaCleaned', { count: cleaned });
});

module.exports = {
  routeDirectMessageV2,
  activateDirectConversationV2,
  configureMessageRequestV2,
  appendMessageRequestV2,
  acceptMessageRequestV2,
  manageMessageRequestV2,
  consumePendingEphemeralV2,
  onMessageRequestV2MessageCreated,
  archiveOldMessageRequestsV2,
  cleanupEmptyMessageRequestReservationsV2,
  cleanupExpiredMessageRequestMediaV2
};
