const b = require('../bootstrap');
const h = require('../helpers');

const {
  HttpsError,
  onCall,
  admin
} = b;

const {
  storageObjectNameFromTrustedValue
} = h;

const VIEW_ONCE_MEDIA_FIELDS = [
  'mediaUrl',
  'thumbnailUrl',
  'mediaObjectPath',
  'thumbnailObjectPath',
  'mediaEncryption',
  'thumbnailEncryption',
  'textOverlayLive',
  'textOverlays',
  'stickers',
  'drawingData'
];

function requireString(value, fieldName) {
  if (typeof value !== 'string' || !value.trim()) {
    throw new HttpsError('invalid-argument', `${fieldName} is required`);
  }
  return value.trim();
}

function viewOnceMediaResources(messageData) {
  return [
    messageData.mediaObjectPath,
    messageData.thumbnailObjectPath,
    messageData.mediaUrl,
    messageData.thumbnailUrl
  ].filter((value) => typeof value === 'string' && value.trim());
}

function isViewOnceType(type) {
  return type === 'viewOnceImage' || type === 'viewOnceVideo';
}

function isParticipant(conversationData, uid) {
  const participants = Array.isArray(conversationData.participants)
    ? conversationData.participants
    : [];
  return participants.includes(uid);
}

function hasUser(list, uid) {
  return Array.isArray(list) && list.includes(uid);
}

function deletionUpdate() {
  return VIEW_ONCE_MEDIA_FIELDS.reduce((update, field) => {
    update[field] = admin.firestore.FieldValue.delete();
    return update;
  }, {});
}

function storageObjectAllowedForMessage(objectName, messageData) {
  if (typeof objectName !== 'string' || !objectName.trim()) return false;

  const senderId = typeof messageData.senderId === 'string' ? messageData.senderId.trim() : '';
  const conversationId = typeof messageData.conversationId === 'string' ? messageData.conversationId.trim() : '';
  const messageId = typeof messageData.id === 'string' ? messageData.id.trim() : '';

  if (!senderId || !conversationId || !messageId) return false;

  return objectName.startsWith(`users/${senderId}/chat/${conversationId}/${messageId}/`);
}

async function deleteViewOnceStorageResources(resources, messageData) {
  if (!resources.length) {
    return { deleted: [], skipped: [] };
  }

  const bucket = admin.storage().bucket();
  const deleted = [];
  const skipped = [];

  for (const resource of resources) {
    const objectName = storageObjectNameFromTrustedValue(resource, bucket.name);
    if (!objectName) {
      skipped.push({ resource, reason: 'invalid_storage_reference' });
      continue;
    }

    if (!storageObjectAllowedForMessage(objectName, messageData)) {
      skipped.push({ resource, objectName, reason: 'path_mismatch' });
      continue;
    }

    try {
      await bucket.file(objectName).delete({ ignoreNotFound: true });
      deleted.push(objectName);
    } catch (error) {
      skipped.push({ resource, objectName, reason: error.message || 'delete_failed' });
    }
  }

  return { deleted, skipped };
}

exports.consumeViewOnceMessage = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }

  const conversationId = requireString(request.data && request.data.conversationId, 'conversationId');
  const messageId = requireString(request.data && request.data.messageId, 'messageId');
  const reason = requireString(request.data && request.data.reason, 'reason');

  if (!['viewOnce', 'replay', 'abandonReplay'].includes(reason)) {
    throw new HttpsError('invalid-argument', 'Invalid consumption reason');
  }

  const firestore = admin.firestore();
  const conversationRef = firestore.collection('conversations').doc(conversationId);
  const messageRef = conversationRef.collection('messages').doc(messageId);

  let mediaResources = [];
  let messageDataForStorage = null;

  const result = await firestore.runTransaction(async (transaction) => {
    const [conversationSnapshot, messageSnapshot] = await Promise.all([
      transaction.get(conversationRef),
      transaction.get(messageRef)
    ]);

    if (!conversationSnapshot.exists) {
      throw new HttpsError('not-found', 'Conversation not found');
    }

    const conversationData = conversationSnapshot.data() || {};
    if (!isParticipant(conversationData, uid)) {
      throw new HttpsError('permission-denied', 'Not a conversation participant');
    }

    if (!messageSnapshot.exists) {
      throw new HttpsError('not-found', 'Message not found');
    }

    const messageData = messageSnapshot.data() || {};
    if (!messageData.isViewOnce || !isViewOnceType(messageData.type)) {
      throw new HttpsError('failed-precondition', 'Message is not view-once media');
    }

    if (messageData.senderId === uid) {
      throw new HttpsError('permission-denied', 'Sender cannot consume own view-once media');
    }

    const allowReplay = messageData.allowReplay === true;
    if (reason === 'viewOnce' && allowReplay) {
      throw new HttpsError('failed-precondition', 'Allow-replay media must not use viewOnce consumption');
    }

    if ((reason === 'replay' || reason === 'abandonReplay') && !allowReplay) {
      throw new HttpsError('failed-precondition', 'Message does not allow replay');
    }

    const viewed = hasUser(messageData.viewedBy, uid) || messageData.isViewed === true;
    if ((reason === 'replay' || reason === 'abandonReplay') && !viewed) {
      throw new HttpsError('failed-precondition', 'Replay is only valid after first view');
    }

    mediaResources = viewOnceMediaResources(messageData);
    messageDataForStorage = {
      id: messageData.id || messageSnapshot.id,
      senderId: messageData.senderId,
      conversationId: messageData.conversationId || conversationId
    };

    const update = {
      ...deletionUpdate(),
      isViewed: true,
      status: 'read',
      viewedBy: admin.firestore.FieldValue.arrayUnion(uid)
    };

    if (reason === 'replay') {
      update.replayedBy = admin.firestore.FieldValue.arrayUnion(uid);
    }

    transaction.update(messageRef, update);

    return {
      hadMedia: mediaResources.length > 0,
      reason
    };
  });

  const storageResult = await deleteViewOnceStorageResources(mediaResources, messageDataForStorage || {});

  return {
    ok: true,
    ...result,
    deletedCount: storageResult.deleted.length,
    skippedCount: storageResult.skipped.length
  };
});
