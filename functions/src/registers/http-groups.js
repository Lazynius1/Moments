const crypto = require('node:crypto');
const { onRequest, onCall, HttpsError, onDocumentCreated, admin } = require('../bootstrap');
const { setProxyCors, parseJsonBody, verifyFirebaseAuth, isDoNotDisturbActive, shouldSilenceNotificationForUser, withAndroidShade, ANDROID_FCM_CHANNELS } = require('../helpers');
const validId = id => typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id);
const validBase64 = (value, byteCount) => {
  if (typeof value !== 'string' || value.length > 1024) return false;
  const decoded = Buffer.from(value, 'base64');
  return decoded.length === byteCount && decoded.toString('base64') === value;
};
const fail = (code, status = 400, extra) => { throw Object.assign(new Error(code), { status, code, extra }); };
const uniqueIds = ids => {
  if (!Array.isArray(ids) || ids.length > 50 || !ids.every(validId)) fail('invalidMembers');
  return [...new Set(ids)];
};
const allowsGroupInvite = (recipient, actorId, memberId, recipientFollowsActor, actorBlocked) => {
  if (!recipient || recipient.isActive === false) return false;
  if ((actorBlocked || []).includes(memberId)) return false;
  if ((recipient.blockedUsers || []).includes(actorId)) return false;
  const policy = recipient.groupInvitePolicy || 'everyone';
  if (policy === 'nobody') return false;
  if (policy === 'following') return recipientFollowsActor === true;
  return true;
};

// Server-authored timeline events; clients cannot forge these through sendGroupMessage.
function groupNotice(tx, ref, group, kind, memberId, name) {
  const messageRef = ref.collection('groupMessages').doc();
  const timestamp = admin.firestore.FieldValue.serverTimestamp();
  const content = JSON.stringify({ groupNotice: kind, name: name || '' });
  tx.create(messageRef, { id: messageRef.id, conversationId: ref.id, senderId: memberId,
    senderName: name || '', type: 'chatNotice', content, timestamp, status: 'sent',
    isRead: true, isDeleted: false, recipientIds: [], isViewOnce: false });
  tx.update(ref, { timestamp, lastMessageId: messageRef.id, lastMessage: content,
    lastMessageType: 'chatNotice', lastMessageSenderId: memberId,
    lastMessageReaction: admin.firestore.FieldValue.delete() });
}
const linkHash = token => crypto.createHash('sha256').update(token).digest('hex');
const validToken = token => typeof token === 'string' && /^[a-f0-9]{64}$/.test(token);
const validGroupImagePath = (id, path) => {
  if (typeof path !== 'string' || path.length < 40 || path.length > 2048) return false;
  try {
    const url = new URL(path);
    if (url.protocol !== 'https:') return false;
    const objectPath = `/groupConversations/${id}/avatar/`;
    return decodeURIComponent(url.pathname).includes(objectPath);
  } catch { return false; }
};

async function applyGroupCommand(db, uid, body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) fail('invalidAction');
  const action = body.action;
  if (!['create', 'add', 'rename', 'setPhoto', 'promote', 'demote', 'remove', 'leave', 'mute', 'read', 'acceptInvite', 'declineInvite', 'cancelInvite', 'getLink', 'setLink', 'revokeLink', 'previewLink', 'joinLink'].includes(action)) fail('invalidAction');
  const id = body.conversationId;
  if (!validId(id) || !/^group-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) fail('invalidGroup');
  const ref = db.doc(`groupConversations/${id}`);
  return db.runTransaction(async tx => {
    const snapshot = await tx.get(ref);
    const group = snapshot.exists ? snapshot.data() : null;
    const actor = await tx.get(db.doc(`users/${uid}`));
    if (!actor.exists || actor.data().isActive === false) fail('unavailable', 403);
    if (action === 'previewLink' || action === 'joinLink') {
      if (!validToken(body.token) || !group || !group.participants.length) fail('unavailable', 403);
      const link = (await tx.get(db.doc(`groupInviteLinks/${id}`))).data();
      if (!link || link.tokenHash !== linkHash(body.token) || link.keyVersion !== group.conversationKeyVersion) fail('unavailable', 403);
      if (action === 'previewLink') return { conversationId: id, name: group.groupName, image: group.groupImagePath || '',
        memberCount: group.participants.length, encryptedKey: link.encryptedKey, keyVersion: link.keyVersion };
      if (group.participants.includes(uid)) return { conversationId: id };
      if (group.participants.length + (group.pendingInviteIds || []).filter(x => x !== uid).length >= 50) fail('invalidMembers');
      const envelope = body.wrappedKey;
      if (!envelope || envelope.wrappedBy !== uid || !validBase64(envelope.senderPublicKey, 32) ||
          envelope.recipientKeyId !== actor.data().chatKey?.keyId || !validBase64(envelope.wrappedKey, 60)) fail('keyUnavailable', 409);
      const pendingNames = { ...(group.pendingInviteNames || {}) }; delete pendingNames[uid];
      const timestamp = admin.firestore.FieldValue.serverTimestamp();
      tx.update(ref, { participants: [...group.participants, uid],
        participantData: { ...group.participantData, [uid]: { userId: uid, username: actor.get('username') || '', profileImagePath: actor.get('profileImagePath') || '' } },
        wrappedKeys: { ...group.wrappedKeys, [uid]: { wrappedKey: envelope.wrappedKey, senderPublicKey: envelope.senderPublicKey,
          recipientKeyId: envelope.recipientKeyId, wrappedBy: uid, wrappedAt: timestamp } },
        pendingInviteIds: (group.pendingInviteIds || []).filter(x => x !== uid), pendingInviteNames: pendingNames,
        [`memberJoinedAt.${uid}`]: timestamp,
        readStatus: { ...group.readStatus, [uid]: true }, groupRevision: group.groupRevision + 1, updatedAt: timestamp });
      tx.delete(db.doc(`groupInvitations/${id}_${uid}`));
      groupNotice(tx, ref, group, 'joined', uid, actor.get('username'));
      return { conversationId: id };
    }
    if (action === 'acceptInvite' || action === 'declineInvite') {
      const invitationRef = db.doc(`groupInvitations/${id}_${uid}`);
      const invitationDoc = await tx.get(invitationRef);
      const invitation = invitationDoc.data();
      if (!invitation || invitation.recipientId !== uid || !group) fail('unavailable', 403);
      const pendingIds = (group.pendingInviteIds || []).filter(memberId => memberId !== uid);
      const pendingNames = { ...(group.pendingInviteNames || {}) }; delete pendingNames[uid];
      if (action === 'declineInvite') {
        tx.delete(invitationRef);
        tx.update(ref, { pendingInviteIds: pendingIds, pendingInviteNames: pendingNames });
        return { conversationId: id };
      }
      if (!group.adminIds.includes(invitation.inviterId) || invitation.keyVersion !== group.conversationKeyVersion ||
          invitation.wrappedKey?.recipientKeyId !== actor.data().chatKey?.keyId) fail('keyUnavailable', 409);
      if (!group.participants.includes(uid)) {
        if (group.participants.length >= 50) fail('invalidMembers');
        tx.update(ref, { participants: [...group.participants, uid], pendingInviteIds: pendingIds, pendingInviteNames: pendingNames,
          participantData: { ...group.participantData, [uid]: { userId: uid, username: actor.get('username') || '', profileImagePath: actor.get('profileImagePath') || '' } },
          wrappedKeys: { ...group.wrappedKeys, [uid]: invitation.wrappedKey },
          [`memberJoinedAt.${uid}`]: admin.firestore.FieldValue.serverTimestamp(),
          readStatus: { ...group.readStatus, [uid]: true }, groupRevision: group.groupRevision + 1,
          updatedAt: admin.firestore.FieldValue.serverTimestamp() });
      }
      if (!group.participants.includes(uid)) groupNotice(tx, ref, group, 'joined', uid, actor.get('username'));
      tx.delete(invitationRef);
      return { conversationId: id };
    }
    if (action === 'create') {
      if (group) {
        if (group.isGroup && group.createdBy === uid && group.participants.includes(uid)) return { conversationId: id };
        fail('conflict', 409);
      }
    } else {
      if (!group || group.isGroup !== true || !group.participants.includes(uid)) fail('unavailable', 403);
      if (!['leave', 'mute', 'read'].includes(action) && !group.adminIds.includes(uid)) fail('adminRequired', 403);
      if (!['mute', 'read', 'getLink'].includes(action) && body.revision !== group.groupRevision) fail('conflict', 409);
    }
    const timestamp = admin.firestore.FieldValue.serverTimestamp();
    if (action === 'create' || action === 'add') {
      const requested = uniqueIds(body.memberIds).filter(id => id !== uid && !(group?.participants || []).includes(id));
      if (!requested.length) fail('invalidMembers');
      const lookupIds = action === 'create' ? [uid, ...requested] : requested;
      const userDocs = await Promise.all(lookupIds.map(memberId => tx.get(db.doc(`users/${memberId}`))));
      const followSnaps = await Promise.all(requested.map(id => tx.get(db.doc(`users/${id}/following/${uid}`))));
      const users = new Map(userDocs.map(doc => [doc.id, doc.exists ? doc.data() : null]));
      const actorBlocked = actor.data().blockedUsers || [];
      const skipped = [];
      const additions = [];
      for (let i = 0; i < requested.length; i++) {
        const memberId = requested[i];
        if (!allowsGroupInvite(users.get(memberId), uid, memberId, followSnaps[i].exists, actorBlocked)) {
          skipped.push({ id: memberId, username: users.get(memberId)?.username || '' });
        } else additions.push(memberId);
      }
      const pendingIds = [...new Set([...(group?.pendingInviteIds || []), ...additions])];
      if ((action === 'create' && additions.length < 2) || !additions.length || (group?.participants.length || 1) + pendingIds.length > 50) {
        if (skipped.length) fail('inviteForbidden', 403, { skipped });
        fail('invalidMembers');
      }
      const recipients = action === 'create' ? [uid, ...additions] : additions;
      const wrapped = { ...(group?.wrappedKeys || {}) };
      for (const memberId of recipients) {
        const user = users.get(memberId), envelope = body.wrappedKeys?.[memberId];
        if (!user || user.isActive === false || !user.chatKey) fail('memberUnavailable', 409);
        // Both clients wrap with an ephemeral X25519 public key, not the actor's
        // persistent identity. Authentication comes from the verified request.
        if (!envelope || envelope.wrappedBy !== uid || !validBase64(envelope.senderPublicKey, 32) ||
            envelope.recipientKeyId !== user.chatKey.keyId || !validBase64(envelope.wrappedKey, 60)) fail('keyUnavailable', 409);
        wrapped[memberId] = { wrappedKey: envelope.wrappedKey, senderPublicKey: envelope.senderPublicKey,
          recipientKeyId: envelope.recipientKeyId, wrappedBy: uid, wrappedAt: timestamp };
      }
      const participantData = { ...(group?.participantData || {}) };
      for (const memberId of recipients) {
        const user = users.get(memberId);
        if (!user) fail('memberUnavailable', 409);
        participantData[memberId] = { userId: memberId, username: user.username || '', profileImagePath: user.profileImagePath || '' };
      }
      const pendingNames = { ...(group?.pendingInviteNames || {}), ...Object.fromEntries(additions.map(memberId => [memberId, participantData[memberId].username])) };
      if (action === 'create') {
        const name = typeof body.name === 'string' ? body.name.trim() : '';
        if (!name || Array.from(name).length > 60) fail('invalidName');
        tx.create(ref, { isGroup: true, groupName: name, createdBy: uid, ownerId: uid, adminIds: [uid],
          groupRevision: 1, participants: [uid], participantData: { [uid]: participantData[uid] }, pendingInviteIds: pendingIds, pendingInviteNames: pendingNames, wrappedKeys: { [uid]: wrapped[uid] }, encryptionVersion: '3.0', conversationKeyVersion: 1,
          timestamp, createdAt: timestamp, updatedAt: timestamp, readStatus: Object.fromEntries(recipients.map(id => [id, true])),
          lastMessage: '', lastMessageType: 'text', mutedByUserIds: [], archivedByUserIds: [] });
      } else {
        tx.update(ref, { pendingInviteIds: pendingIds, pendingInviteNames: pendingNames, groupRevision: group.groupRevision + 1, updatedAt: timestamp });
      }
      for (const memberId of additions) {
        tx.set(db.doc(`groupInvitations/${id}_${memberId}`), { groupId: id, groupName: group?.groupName || body.name.trim(),
          groupImagePath: group?.groupImagePath || '', recipientId: memberId, inviterId: uid, inviterName: actor.get('username') || '',
          keyVersion: group?.conversationKeyVersion || 1, wrappedKey: wrapped[memberId], createdAt: timestamp });
      }
      return { conversationId: id, skipped };
    }
    if (action === 'getLink') {
      const link = (await tx.get(db.doc(`groupInviteLinks/${id}`))).data();
      return link && link.keyVersion === group.conversationKeyVersion
        ? { token: link.token, secretBox: link.secretBox } : {};
    }
    if (action === 'setLink' || action === 'revokeLink') {
      const linkRef = db.doc(`groupInviteLinks/${id}`);
      if (action === 'setLink') {
        if (!validToken(body.token) || !validBase64(body.encryptedKey, 60) || !validBase64(body.secretBox, 60)) fail('invalidLink');
        tx.set(linkRef, { token: body.token, tokenHash: linkHash(body.token), encryptedKey: body.encryptedKey,
          secretBox: body.secretBox, keyVersion: group.conversationKeyVersion, createdBy: uid, createdAt: timestamp });
      } else tx.delete(linkRef);
      tx.update(ref, { groupRevision: group.groupRevision + 1, updatedAt: timestamp });
      return { conversationId: id };
    }
    if (action === 'cancelInvite') {
      if (!validId(body.memberId)) fail('invalidMember');
      const pendingNames = { ...(group.pendingInviteNames || {}) }; delete pendingNames[body.memberId];
      tx.delete(db.doc(`groupInvitations/${id}_${body.memberId}`));
      tx.update(ref, { pendingInviteIds: (group.pendingInviteIds || []).filter(memberId => memberId !== body.memberId),
        pendingInviteNames: pendingNames, groupRevision: group.groupRevision + 1, updatedAt: timestamp });
    } else if (action === 'mute') {
      if (typeof body.muted !== 'boolean') fail('invalidAction');
      const muted = (group.mutedByUserIds || []).filter(id => id !== uid);
      if (body.muted) muted.push(uid);
      tx.update(ref, { mutedByUserIds: muted });
    } else if (action === 'read') {
      // A late read acknowledgement must never mark a newer message as read.
      if (body.messageId === (group.lastMessageId || '')) {
        tx.update(ref, { readStatus: { ...group.readStatus, [uid]: true } });
      }
    } else if (action === 'rename') {
      const name = typeof body.name === 'string' ? body.name.trim() : '';
      if (!name || Array.from(name).length > 60) fail('invalidName');
      tx.update(ref, { groupName: name, groupRevision: group.groupRevision + 1, updatedAt: timestamp });
    } else if (action === 'setPhoto') {
      if (!validGroupImagePath(id, body.imagePath)) fail('invalidName');
      const imagePath = body.imagePath.trim();
      const inviteSnaps = await Promise.all((group.pendingInviteIds || []).map(memberId => tx.get(db.doc(`groupInvitations/${id}_${memberId}`))));
      tx.update(ref, { groupImagePath: imagePath, groupRevision: group.groupRevision + 1, updatedAt: timestamp });
      for (const snap of inviteSnaps) {
        if (snap.exists) tx.update(snap.ref, { groupImagePath: imagePath });
      }
    } else if (action === 'promote' || action === 'demote') {
      const target = body.memberId;
      if (!validId(target) || !group.participants.includes(target) || target === group.ownerId) fail('invalidMember');
      if (action === 'demote' && uid !== group.ownerId && target !== uid) fail('ownerRequired', 403);
      const admins = action === 'promote' ? [...new Set([...group.adminIds, target])] : group.adminIds.filter(id => id !== target);
      tx.update(ref, { adminIds: admins, groupRevision: group.groupRevision + 1, updatedAt: timestamp });
    } else if (action === 'remove' || action === 'leave') {
      const target = action === 'leave' ? uid : body.memberId;
      if (!validId(target) || !group.participants.includes(target)) fail('invalidMember');
      if (action === 'remove' && (target === group.ownerId || (group.adminIds.includes(target) && uid !== group.ownerId))) fail('ownerRequired', 403);
      const participants = group.participants.filter(id => id !== target);
      let admins = group.adminIds.filter(id => id !== target);
      if (!admins.length && participants.length) admins = [participants[0]];
      const wrapped = { ...group.wrappedKeys }, participantData = { ...group.participantData };
      delete wrapped[target];
      // Removal revokes the shared capability as well.
      tx.delete(db.doc(`groupInviteLinks/${id}`));
      tx.update(ref, { participants, adminIds: admins, ownerId: group.ownerId === target ? (admins[0] || null) : group.ownerId,
        wrappedKeys: wrapped, participantData, groupRevision: group.groupRevision + 1, updatedAt: timestamp });
      groupNotice(tx, ref, group, action === 'leave' ? 'left' : 'removed', target, participantData[target]?.username);
    } else { fail('invalidAction'); }
    return { conversationId: id };
  });
}

const manageGroup = onRequest({ timeoutSeconds: 60, memory: '256MiB', concurrency: 20 }, async (req, res) => {
  setProxyCors(res);
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  if (req.method === 'GET' && /^\/(join|g)\/group-[0-9a-f-]{36}\/[a-f0-9]{64}\/?$/i.test(req.path)) {
    const parts = req.path.split('/').filter(Boolean);
    const groupId = parts[parts.length - 2];
    const token = parts[parts.length - 1];
    res.set('Cache-Control', 'no-store');
    res.set('Referrer-Policy', 'no-referrer');
    res.redirect(302, `https://momentsapp.app/g/${groupId}/${token}`);
    return;
  }
  if (req.method !== 'POST') { res.status(405).json({ error: 'methodNotAllowed' }); return; }
  const uid = await verifyFirebaseAuth(req, res);
  if (!uid) return;
  try { res.status(200).json(await applyGroupCommand(admin.firestore(), uid, parseJsonBody(req))); }
  catch (error) {
    console.error('manageGroup failed', error.code || error.message);
    res.status(error.status || 500).json({ error: error.code || 'failed', ...(error.extra && typeof error.extra === 'object' ? error.extra : {}) });
  }
});


// Group messages never enter conversations/{id}/messages or its triggers.
const sendGroupMessage = onRequest({ timeoutSeconds: 60, memory: '256MiB', concurrency: 20 }, async (req, res) => {
  setProxyCors(res);
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  if (req.method !== 'POST') { res.status(405).json({ error: 'methodNotAllowed' }); return; }
  const uid = await verifyFirebaseAuth(req, res);
  if (!uid) return;
  try {
    const body = parseJsonBody(req);
    if (!body || !validId(body.groupId) || !validId(body.messageId)) fail('invalidGroup');
    const input = body.message;
    const supported = ['text', 'image', 'video', 'audio', 'gif', 'sticker', 'file', 'location', 'sharedMoment', 'sharedStory', 'sharedProfile', 'viewOnceImage', 'viewOnceVideo', 'ephemeral'];
    if (!input || typeof input !== 'object' || !supported.includes(input.type) || input.isVanishModeMessage === true) fail('invalidMessage');
    if (Buffer.byteLength(JSON.stringify(input), 'utf8') > 700000) fail('invalidMessage');
    const allowed = ['content', 'type', 'mediaObjectPath', 'thumbnailObjectPath', 'mediaUrl', 'thumbnailUrl', 'mediaEncryption', 'thumbnailEncryption',
      'duration', 'audioWaveform', 'fileName', 'fileSize', 'mediaWidth', 'mediaHeight', 'latitude', 'longitude', 'locationName', 'locationAddress', 'isLiveLocation',
      'liveLocationExpiresAt', 'liveLocationDuration', 'liveLocationStoppedAt', 'liveLocationSessionId', 'locationUpdatedAt', 'replyTo', 'expirationDate',
      'storyReplyData', 'sharedMomentData', 'sharedStoryData', 'sharedProfileData', 'mediaBatchId', 'textOverlayLive', 'textOverlays',
      'stickers', 'drawingData', 'allowReplay', 'isForwarded', 'forwardedFrom', 'giphyId'];
    const message = Object.fromEntries(allowed.filter(field => input[field] != null).map(field => [field, input[field]]));
    if (message.content != null && (typeof message.content !== 'string' || message.content.length > 100000)) fail('invalidMessage');
    if (message.replyTo != null && !validId(message.replyTo)) fail('invalidMessage');
    for (const field of ['mediaObjectPath', 'thumbnailObjectPath']) {
      if (message[field] != null && (typeof message[field] !== 'string' || !message[field].startsWith(`groupChat/${body.groupId}/${uid}/${body.messageId}/`))) fail('invalidMedia');
    }
    for (const field of ['liveLocationExpiresAt', 'liveLocationStoppedAt', 'locationUpdatedAt', 'expirationDate']) {
      if (message[field] != null) {
        if (typeof message[field] !== 'number' || !Number.isFinite(message[field])) fail('invalidMessage');
        message[field] = admin.firestore.Timestamp.fromMillis(message[field]);
      }
    }
    if (message.drawingData != null) {
      if (typeof message.drawingData !== 'string') fail('invalidMessage');
      message.drawingData = Buffer.from(message.drawingData, 'base64');
    }
    const db = admin.firestore(), ref = db.doc(`groupConversations/${body.groupId}`);
    const messageRef = ref.collection('groupMessages').doc(body.messageId);
    await db.runTransaction(async tx => {
      const [groupDoc, actor, existing] = await Promise.all([tx.get(ref), tx.get(db.doc(`users/${uid}`)), tx.get(messageRef)]);
      const group = groupDoc.data();
      if (!group || !group.participants.includes(uid) || !actor.exists || actor.get('isActive') === false) fail('unavailable', 403);
      if (existing.exists) {
        // Retry/late acknowledgement: never overwrite edits, receipts or consumption.
        if (existing.get('senderId') !== uid) fail('conflict', 409);
        return;
      }
      const timestamp = admin.firestore.FieldValue.serverTimestamp();
      tx.create(messageRef, { ...message, id: body.messageId, conversationId: body.groupId, senderId: uid,
        senderName: actor.get('username') || '', recipientIds: group.participants.filter(id => id !== uid),
        status: 'sent', isRead: false, isDeleted: false, isViewed: false, viewedBy: [], replayedBy: [], consumedBy: [],
        isViewOnce: ['viewOnceImage', 'viewOnceVideo'].includes(message.type), timestamp });
      tx.update(ref, { timestamp, lastMessageId: body.messageId, lastMessage: message.content || '', lastMessageType: message.type,
        lastMessageSenderId: uid, lastMessageSeenAt: {}, lastMessageReaction: admin.firestore.FieldValue.delete(),
        readStatus: Object.fromEntries(group.participants.map(id => [id, id === uid])) });
    });
    res.status(200).json({ messageId: body.messageId });
  } catch (error) {
    console.error('sendGroupMessage failed', error.code || error.message);
    res.status(error.status || 500).json({ error: error.code || 'failed' });
  }
});

const onGroupMessageAdded = onDocumentCreated({ document: 'groupConversations/{groupId}/groupMessages/{messageId}', retry: false }, async event => {
  const message = event.data?.data();
  if (!message || message.type === 'chatNotice') return;
  const { groupId, messageId } = event.params;
  const db = admin.firestore();
  const group = (await db.doc(`groupConversations/${groupId}`).get()).data();
  if (!group || !group.participants.includes(message.senderId)) return;
  const recipients = group.participants.filter(id => id !== message.senderId && !(group.mutedByUserIds || []).includes(id) && !(group.archivedByUserIds || []).includes(id));
  await Promise.all(recipients.map(async uid => {
    const user = (await db.doc(`users/${uid}`).get()).data();
    if (!user || user.isActive === false || !user.fcmToken ||
        isDoNotDisturbActive(user)) return;
    // Generic group notification: no ciphertext or direct-chat identifiers.
    const push = { token: user.fcmToken,
      data: { type: 'group_message', groupId, messageId, senderId: message.senderId,
        senderUsername: message.senderName, groupName: group.groupName, title: group.groupName },
      apns: { headers: { 'apns-collapse-id': `group-${groupId}`.slice(0, 64) }, payload: { aps: {
        alert: { title: group.groupName, 'loc-key': 'groups.notification', 'loc-args': [message.senderName] },
        sound: 'default', 'thread-id': `group-${groupId}`
      } } }
    };
    try { await admin.messaging().send(withAndroidShade(push, { collapseKey: `group-${groupId}`, threadId: `group-${groupId}`, channel: ANDROID_FCM_CHANNELS.messages })); }
    catch (error) { console.error('Group notification failed', error.code || 'unknown'); }
  }));
});
const consumeGroupViewOnceMessage = onCall(async request => {
  const uid = request.auth?.uid, { conversationId, messageId, reason } = request.data || {};
  if (!uid) throw new HttpsError('unauthenticated', 'Authentication required');
  if (!validId(conversationId) || !validId(messageId) || !['viewOnce', 'replay', 'abandonReplay'].includes(reason)) throw new HttpsError('invalid-argument', 'Invalid consumption');
  const db = admin.firestore(), groupRef = db.doc(`groupConversations/${conversationId}`), ref = groupRef.collection('groupMessages').doc(messageId);
  const resources = await db.runTransaction(async tx => {
    const [groupDoc, doc, user] = await Promise.all([tx.get(groupRef), tx.get(ref), tx.get(db.doc(`users/${uid}`))]);
    const group = groupDoc.data(), message = doc.data();
    if (!group || !group.participants.includes(uid) || !user.exists || user.get('isActive') === false) throw new HttpsError('permission-denied', 'Membership required');
    if (!message || !['viewOnceImage', 'viewOnceVideo'].includes(message.type) || !(message.recipientIds || []).includes(uid)) throw new HttpsError('permission-denied', 'Not a recipient');
    const allowReplay = message.allowReplay === true;
    if ((reason === 'viewOnce' && allowReplay) || (reason !== 'viewOnce' && !allowReplay)) throw new HttpsError('failed-precondition', 'Invalid consumption mode');
    if (reason !== 'viewOnce' && !(message.viewedBy || []).includes(uid)) throw new HttpsError('failed-precondition', 'First view required');
    const consumed = [...new Set([...(message.consumedBy || []), uid])];
    const remaining = (message.recipientIds || []).filter(id => group.participants.includes(id) && !consumed.includes(id));
    const update = { consumedBy: consumed, viewedBy: [...new Set([...(message.viewedBy || []), uid])], isViewed: true };
    if (reason === 'replay') update.replayedBy = [...new Set([...(message.replayedBy || []), uid])];
    const paths = [];
    if (!remaining.length) {
      for (const field of ['mediaObjectPath', 'thumbnailObjectPath', 'mediaEncryption', 'thumbnailEncryption', 'mediaUrl', 'thumbnailUrl', 'textOverlayLive', 'textOverlays', 'stickers', 'drawingData']) {
        if (['mediaObjectPath', 'thumbnailObjectPath'].includes(field) && typeof message[field] === 'string' && message[field].startsWith(`groupChat/${conversationId}/${message.senderId}/${messageId}/`)) paths.push(message[field]);
        update[field] = admin.firestore.FieldValue.delete();
      }
    }
    tx.update(ref, update);
    return paths;
  });
  await Promise.all(resources.map(path => admin.storage().bucket().file(path).delete({ ignoreNotFound: true })));
  return { ok: true };
});
const onGroupInvitationCreated = onDocumentCreated({ document: 'groupInvitations/{invitationId}', retry: false }, async event => {
  const invitation = event.data?.data();
  if (!invitation) return;
  const user = (await admin.firestore().doc(`users/${invitation.recipientId}`).get()).data();
  if (!user || user.isActive === false || !user.fcmToken || isDoNotDisturbActive(user)) return;
  const push = { token: user.fcmToken, data: { type: 'group_invitation', groupId: invitation.groupId, groupName: invitation.groupName },
    apns: { payload: { aps: { alert: { 'title-loc-key': 'groups.invitations', body: invitation.groupName }, sound: 'default' } } } };
  try { await admin.messaging().send(withAndroidShade(push, { collapseKey: `invite-${invitation.groupId}`, threadId: `invite-${invitation.groupId}`, channel: ANDROID_FCM_CHANNELS.messages })); }
  catch (error) { console.error('Group invitation notification failed', error.code || 'unknown'); }
});
module.exports = { manageGroup, sendGroupMessage, onGroupMessageAdded, consumeGroupViewOnceMessage, onGroupInvitationCreated };
