const b = require('../bootstrap');
const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
  onSchedule,
  onRequest,
  admin,
  RekognitionClient,
  DetectModerationLabelsCommand,
  JSZip,
  crypto,
  path,
  fs,
  os,
  spawn,
  ffmpegPath,
  createImageModerationService,
  policyFromFirestoreSettings,
  OPENAI_API_KEY,
  SIGHTENGINE_USER,
  SIGHTENGINE_SECRET,
  AWS_ACCESS_KEY_ID,
  AWS_SECRET_ACCESS_KEY,
  AWS_REGION,
  GOOGLE_SPEECH_API_KEY,
  GIPHY_API_KEY,
  TELEGRAM_BOT_TOKEN,
  TELEGRAM_CHAT_ID,
  VIDEO_DOWNLOAD_MAX_BYTES,
  VIDEO_DOWNLOAD_TIMEOUT_MS,
  IMAGE_DOWNLOAD_MAX_BYTES,
  IMAGE_DOWNLOAD_TIMEOUT_MS,
  PUBLISHABLE_IMAGE_EXTENSIONS,
  ADMIN_PANEL_BASE_URL,
  GENTLE_REMINDER_VARIANTS,
  GENTLE_REMINDER_LIMITS
} = b;

function validateUserData(userData, requiredFields = ['username', 'isActive']) {
  return requiredFields.every(field => userData[field] !== undefined && userData[field] !== null);
}

// ✅ FUNCIÓN auxiliar para manejar tokens inválidos
async function removeInvalidToken(userId, fcmToken) {
  try {
    await admin.firestore().collection('users').doc(userId).update({
      fcmToken: admin.firestore.FieldValue.delete(),
      fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    console.log(`✅ Token inválido eliminado para usuario: ${userId}`);
  } catch (error) {
    console.error(`❌ Error eliminando token inválido para ${userId}:`, error);
  }
}

function buildMessageRequestConversationPreview(messageType, messageText) {
  const trimmed = typeof messageText === 'string' ? messageText.trim() : '';
  if (messageType === 'text' && trimmed) {
    return trimmed;
  }

  switch (messageType) {
    case 'image':
    case 'viewOnceImage':
      return '📷';
    case 'video':
    case 'viewOnceVideo':
      return '🎥';
    case 'audio':
      return '🎵';
    case 'gif':
      return '🎞';
    case 'sticker':
      return '😊';
    case 'location':
      return '📍';
    case 'file':
      return '📎';
    case 'sharedMoment':
      return '📸';
    default:
      return trimmed || '💬';
  }
}

async function findExistingDirectConversation(userAId, userBId) {
  const snap = await admin.firestore()
    .collection('conversations')
    .where('participants', 'array-contains', userAId)
    .get();

  return snap.docs.find((doc) => {
    const participants = Array.isArray(doc.get('participants')) ? doc.get('participants') : [];
    return participants.length === 2 && participants.includes(userBId);
  }) || null;
}

function isActiveUserData(userData) {
  return !userData || userData.isActive !== false;
}

function usersAreBlocked(userAData, userAId, userBData, userBId) {
  const userABlocked = Array.isArray(userAData?.blockedUsers) ? userAData.blockedUsers : [];
  const userBBlocked = Array.isArray(userBData?.blockedUsers) ? userBData.blockedUsers : [];
  return userABlocked.includes(userBId) || userBBlocked.includes(userAId);
}

function parseTimeToMinutes(value) {
  if (typeof value !== 'string') return null;
  const parts = value.split(':');
  if (parts.length !== 2) return null;
  const hours = Number(parts[0]);
  const minutes = Number(parts[1]);
  if (!Number.isInteger(hours) || !Number.isInteger(minutes)) return null;
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;
  return hours * 60 + minutes;
}

function isDoNotDisturbActive(userData) {
  if (!userData) return false;
  const startMinutes = parseTimeToMinutes(userData.activeHoursStart);
  const endMinutes = parseTimeToMinutes(userData.activeHoursEnd);
  if (startMinutes === null || endMinutes === null) return false;

  const timezone = userData.notificationTimeZone || userData.timeZone || userData.timezone || null;
  const now = new Date();
  let currentMinutes = now.getHours() * 60 + now.getMinutes();

  if (timezone) {
    try {
      const parts = new Intl.DateTimeFormat('en-US', {
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
        timeZone: timezone
      }).formatToParts(now);

      const hourPart = parts.find(p => p.type === 'hour')?.value;
      const minutePart = parts.find(p => p.type === 'minute')?.value;
      const tzHour = Number(hourPart);
      const tzMinute = Number(minutePart);

      if (Number.isInteger(tzHour) && Number.isInteger(tzMinute)) {
        currentMinutes = tzHour * 60 + tzMinute;
      }
    } catch (error) {
      // Fallback to server-local time if timezone is invalid.
    }
  }

  if (startMinutes > endMinutes) {
    return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
  }
  return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
}

function asDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (value instanceof admin.firestore.Timestamp) return value.toDate();
  if (typeof value.toDate === 'function') {
    try {
      return value.toDate();
    } catch (error) {
      return null;
    }
  }
  return null;
}

function hoursSince(date, now) {
  if (!date) return Number.POSITIVE_INFINITY;
  return (now.getTime() - date.getTime()) / (1000 * 60 * 60);
}

function daysSince(date, now) {
  if (!date) return Number.POSITIVE_INFINITY;
  return (now.getTime() - date.getTime()) / (1000 * 60 * 60 * 24);
}

function startOfTodayInTimezone(date, timezone) {
  if (!timezone) {
    const local = new Date(date);
    local.setHours(0, 0, 0, 0);
    return local;
  }

  try {
    const parts = new Intl.DateTimeFormat('en-CA', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      timeZone: timezone
    }).formatToParts(date);

    const year = parts.find((p) => p.type === 'year')?.value;
    const month = parts.find((p) => p.type === 'month')?.value;
    const day = parts.find((p) => p.type === 'day')?.value;
    if (!year || !month || !day) return null;
    return new Date(`${year}-${month}-${day}T00:00:00Z`);
  } catch (error) {
    const local = new Date(date);
    local.setHours(0, 0, 0, 0);
    return local;
  }
}

function hasPostedToday(userData, now) {
  const lastMomentCreatedAt = asDate(userData.lastMomentCreatedAt);
  if (!lastMomentCreatedAt) return false;
  const timezone = userData.notificationTimeZone || userData.timeZone || userData.timezone || null;
  try {
    const formatter = new Intl.DateTimeFormat('en-CA', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      timeZone: timezone || 'UTC'
    });
    return formatter.format(lastMomentCreatedAt) === formatter.format(now);
  } catch (error) {
    const localNow = new Date(now);
    const localMoment = new Date(lastMomentCreatedAt);
    return (
      localNow.getFullYear() === localMoment.getFullYear() &&
      localNow.getMonth() === localMoment.getMonth() &&
      localNow.getDate() === localMoment.getDate()
    );
  }
}

function gentleRemindersEnabled(userData) {
  const prefs = userData && typeof userData.notificationPreferences === 'object' && userData.notificationPreferences !== null
    ? userData.notificationPreferences
    : {};
  return prefs.gentleReminders !== false;
}

// Respeta los toggles por tipo de Ajustes (like, newFollower, followRequest,
// mutualConnection, comment, storyReaction...). Por defecto ON si no hay preferencia.
function notificationTypeEnabled(userData, notificationType) {
  if (!notificationType) return true;
  const prefs = userData && typeof userData.notificationPreferences === 'object' && userData.notificationPreferences !== null
    ? userData.notificationPreferences
    : {};
  return prefs[notificationType] !== false;
}

function normalizeReminderHistory(history, now) {
  const cutoff = new Date(now.getTime() - (7 * 24 * 60 * 60 * 1000));
  return Array.isArray(history)
    ? history
      .map(asDate)
      .filter((date) => date && date >= cutoff)
      .sort((a, b) => a.getTime() - b.getTime())
    : [];
}

function buildGentleReminderState(userData, now) {
  const state = {
    lastGentleReminderAt: asDate(userData.lastGentleReminderAt),
    lastGentleReminderVariant: typeof userData.lastGentleReminderVariant === 'string' ? userData.lastGentleReminderVariant : null,
    lastAppOpenAt: asDate(userData.lastAppOpenAt),
    lastMomentCreatedAt: asDate(userData.lastMomentCreatedAt),
    notificationTimeZone: userData.notificationTimeZone || userData.timeZone || userData.timezone || null,
    gentleReminderIgnoreCount: Number.isFinite(userData.gentleReminderIgnoreCount) ? userData.gentleReminderIgnoreCount : 0,
    gentleReminderAwaitingResponse: userData.gentleReminderAwaitingResponse === true,
    gentleReminderCooldownUntil: asDate(userData.gentleReminderCooldownUntil),
    gentleReminderSentHistory: normalizeReminderHistory(userData.gentleReminderSentHistory, now)
  };

  const updates = {};
  const responseWindowMs = GENTLE_REMINDER_LIMITS.responseWindowHours * 60 * 60 * 1000;

  if (state.gentleReminderCooldownUntil && state.gentleReminderCooldownUntil <= now) {
    state.gentleReminderCooldownUntil = null;
    updates.gentleReminderCooldownUntil = admin.firestore.FieldValue.delete();
  }

  if (
    state.gentleReminderAwaitingResponse &&
    state.lastGentleReminderAt &&
    (now.getTime() - state.lastGentleReminderAt.getTime()) >= responseWindowMs
  ) {
    const engaged =
      state.lastAppOpenAt &&
      state.lastAppOpenAt > state.lastGentleReminderAt &&
      (state.lastAppOpenAt.getTime() - state.lastGentleReminderAt.getTime()) <= responseWindowMs;

    state.gentleReminderAwaitingResponse = false;
    updates.gentleReminderAwaitingResponse = false;

    if (engaged) {
      state.gentleReminderIgnoreCount = 0;
      updates.gentleReminderIgnoreCount = 0;
      if (state.gentleReminderCooldownUntil) {
        state.gentleReminderCooldownUntil = null;
        updates.gentleReminderCooldownUntil = admin.firestore.FieldValue.delete();
      }
    } else {
      const nextIgnoreCount = state.gentleReminderIgnoreCount + 1;
      if (nextIgnoreCount >= 3) {
        const cooldownUntil = new Date(now.getTime() + (GENTLE_REMINDER_LIMITS.cooldownDays * 24 * 60 * 60 * 1000));
        state.gentleReminderCooldownUntil = cooldownUntil;
        state.gentleReminderIgnoreCount = 0;
        updates.gentleReminderCooldownUntil = cooldownUntil;
        updates.gentleReminderIgnoreCount = 0;
      } else {
        state.gentleReminderIgnoreCount = nextIgnoreCount;
        updates.gentleReminderIgnoreCount = nextIgnoreCount;
      }
    }
  }

  if (Array.isArray(userData.gentleReminderSentHistory)) {
    const originalCount = userData.gentleReminderSentHistory.length;
    if (originalCount !== state.gentleReminderSentHistory.length) {
      updates.gentleReminderSentHistory = state.gentleReminderSentHistory;
    }
  }

  return { state, updates };
}

function chooseGentleReminderVariant(state, now) {
  if (hoursSince(state.lastAppOpenAt, now) < GENTLE_REMINDER_LIMITS.minHoursSinceOpen) {
    return null;
  }

  if (hasPostedToday({
    lastMomentCreatedAt: state.lastMomentCreatedAt,
    notificationTimeZone: state.notificationTimeZone
  }, now)) {
    return null;
  }

  if (state.lastGentleReminderAt && hoursSince(state.lastGentleReminderAt, now) < 24) {
    return null;
  }

  if (state.gentleReminderCooldownUntil && state.gentleReminderCooldownUntil > now) {
    return null;
  }

  if (state.gentleReminderSentHistory.length >= GENTLE_REMINDER_LIMITS.maxPerRollingWeek) {
    return null;
  }

  const eligibleGroups = [];
  const hoursWithoutOpen = hoursSince(state.lastAppOpenAt, now);
  const daysWithoutMoment = daysSince(state.lastMomentCreatedAt, now);

  if (daysWithoutMoment >= GENTLE_REMINDER_LIMITS.inactiveDaysSinceMoment) {
    eligibleGroups.push([
      GENTLE_REMINDER_VARIANTS.inactiveAnyMoment
    ]);
  }
  if (
    hoursWithoutOpen >= GENTLE_REMINDER_LIMITS.editorialHoursSinceOpen &&
    daysWithoutMoment >= GENTLE_REMINDER_LIMITS.editorialDaysSinceMoment
  ) {
    eligibleGroups.push([
      GENTLE_REMINDER_VARIANTS.editorialBeautiful,
      GENTLE_REMINDER_VARIANTS.editorialYours
    ]);
  }
  if (hoursWithoutOpen >= GENTLE_REMINDER_LIMITS.minHoursSinceOpen) {
    eligibleGroups.push([
      GENTLE_REMINDER_VARIANTS.neutralDay,
      GENTLE_REMINDER_VARIANTS.neutralAvailable
    ]);
  }

  if (eligibleGroups.length === 0) {
    return null;
  }

  for (const group of eligibleGroups) {
    const preferred = group.find((variant) => variant !== state.lastGentleReminderVariant);
    if (preferred) {
      return preferred;
    }
  }

  return null;
}

async function sendGentleReminderPush(userId, userData, variant) {
  const fcmToken = userData.fcmToken || null;
  if (!fcmToken) return;

  const message = {
    token: fcmToken,
    data: {
      type: 'gentle_reminder',
      targetType: 'creator',
      targetId: '',
      reminderVariant: variant
    },
    apns: {
      headers: {
        'apns-collapse-id': `gentle_reminder_${userId}`
      },
      payload: {
        aps: {
          alert: {
            'title-loc-key': 'notification.gentleReminder.title',
            'loc-key': `notification.gentleReminder.body.${variant}`,
            'loc-args': []
          },
          sound: 'default',
          'thread-id': 'gentle_reminders'
        }
      }
    }
  };

  await admin.messaging().send(message);
}

function normalizeMutedWords(words) {
  if (!Array.isArray(words)) return [];
  return words
    .map((word) => (typeof word === 'string' ? word.trim().toLowerCase() : ''))
    .filter((word) => word.length > 0);
}

function getMuteSettings(userData) {
  const raw = userData && typeof userData.muteSettings === 'object' && userData.muteSettings !== null
    ? userData.muteSettings
    : {};
  const mutedUsers = Array.isArray(raw.mutedUsers)
    ? raw.mutedUsers.filter((id) => typeof id === 'string' && id.trim().length > 0)
    : [];

  return {
    muteNotifications: raw.muteNotifications === true,
    hideFromSearch: raw.hideFromSearch === true,
    mutedUsers: new Set(mutedUsers),
    mutedWords: normalizeMutedWords(raw.mutedWords)
  };
}

function textContainsMutedWord(text, mutedWords) {
  if (!text || mutedWords.length === 0) return false;
  const normalizedText = String(text).toLowerCase();
  return mutedWords.some((word) => normalizedText.includes(word));
}

function shouldSilenceNotificationForUser(receiverData, options = {}) {
  const muteSettings = getMuteSettings(receiverData);
  const senderId = typeof options.senderId === 'string' ? options.senderId : '';
  // `muteNotifications` means "mute notifications from muted accounts", not "mute all notifications".
  if (muteSettings.muteNotifications && senderId && muteSettings.mutedUsers.has(senderId)) {
    return true;
  }

  const candidateTexts = Array.isArray(options.candidateTexts) ? options.candidateTexts : [];
  return candidateTexts.some((text) => textContainsMutedWord(text, muteSettings.mutedWords));
}

function pickMomentPreviewUrl(momentData) {
  if (!momentData || typeof momentData !== 'object') return null;

  if (Array.isArray(momentData.mediaItems)) {
    for (const item of momentData.mediaItems) {
      if (!item || typeof item !== 'object') continue;
      if (item.moderationState === 'hidden') continue;
      if (typeof item.thumbnailUrl === 'string' && item.thumbnailUrl.trim()) {
        return item.thumbnailUrl.trim();
      }
      if (typeof item.url === 'string' && item.url.trim()) {
        return item.url.trim();
      }
    }

    return null;
  }

  if (typeof momentData.thumbnailUrl === 'string' && momentData.thumbnailUrl.trim()) {
    return momentData.thumbnailUrl.trim();
  }
  if (typeof momentData.imageUrl === 'string' && momentData.imageUrl.trim()) {
    return momentData.imageUrl.trim();
  }

  if (typeof momentData.videoUrl === 'string' && momentData.videoUrl.trim()) {
    return momentData.videoUrl.trim();
  }

  return null;
}

// Mejor imagen de preview de una historia para el push / la lista.
// Foto: mediaItem.url (ya es imagen). Vídeo: mediaItem.thumbnailUrl (poster subido al publicar).
// Devuelve null si no hay imagen utilizable (vídeos legacy sin poster) para caer en el avatar,
// nunca en un placeholder genérico, y jamás en una URL de vídeo .mp4.
function pickStoryPreviewUrl(storyData) {
  if (!storyData || typeof storyData !== 'object') return null;

  const mediaItem = storyData.mediaItem || {};

  if (typeof mediaItem.thumbnailUrl === 'string' && mediaItem.thumbnailUrl.trim()) {
    return mediaItem.thumbnailUrl.trim();
  }
  if (mediaItem.type === 'image' && typeof mediaItem.url === 'string' && mediaItem.url.trim()) {
    return mediaItem.url.trim();
  }
  if (typeof storyData.backgroundFrameURL === 'string' && storyData.backgroundFrameURL.trim()) {
    return storyData.backgroundFrameURL.trim();
  }
  if (typeof storyData.backgroundBlurredFrameURL === 'string' && storyData.backgroundBlurredFrameURL.trim()) {
    return storyData.backgroundBlurredFrameURL.trim();
  }
  if (typeof storyData.imagePath === 'string' && storyData.imagePath.trim()) {
    return storyData.imagePath.trim();
  }

  return null;
}

// APNs exige collapse-id ≤ 64 bytes. IDs de Firestore/UUID pueden superarlo si se concatenan.
function apnsCollapseId(prefix, ...parts) {
  const candidate = `${prefix}_${parts.join('_')}`;
  if (Buffer.byteLength(candidate, 'utf8') <= 64) {
    return candidate;
  }
  const hash = crypto.createHash('sha256').update(parts.join('\0')).digest('hex').slice(0, 57);
  return `${prefix}_${hash}`;
}

// ✅ Contar mensajes no leídos EN UNA CONVERSACIÓN ESPECÍFICA
async function getUnreadMessagesInConversation(conversationId, userId) {
  try {
    const conversationSnap = await admin.firestore()
      .collection('conversations')
      .doc(conversationId)
      .get();

    const conversationData = conversationSnap.data() || {};
    const lastReadAt = conversationData.lastReadAt || {};
    const lastReadValue = lastReadAt[userId];
    const lastReadMillis = lastReadValue && typeof lastReadValue.toMillis === 'function'
      ? lastReadValue.toMillis()
      : null;

    const messagesSnap = await admin.firestore()
      .collection('conversations')
      .doc(conversationId)
      .collection('messages')
      .orderBy('timestamp', 'desc')
      .get();

    const visibleIncomingMessages = messagesSnap.docs.filter(doc => {
      const data = doc.data() || {};
      if (data.senderId === userId) return false;
      if (data.isDeleted === true) return false;

      const deletedFor = Array.isArray(data.deletedFor) ? data.deletedFor : [];
      if (deletedFor.includes(userId)) return false;

      return true;
    });

    if (lastReadMillis) {
      const unreadCount = visibleIncomingMessages.filter(doc => {
        const data = doc.data() || {};
        const timestampMillis = data.timestamp && typeof data.timestamp.toMillis === 'function'
          ? data.timestamp.toMillis()
          : null;

        return !timestampMillis || timestampMillis > lastReadMillis;
      }).length;

      return Math.max(1, unreadCount);
    }

    // Fallback para conversaciones antiguas sin lastReadAt:
    // contamos solo la racha mas reciente de mensajes entrantes no leidos.
    let unreadCount = 0;
    for (const doc of messagesSnap.docs) {
      const data = doc.data() || {};

      if (data.isDeleted === true) {
        continue;
      }

      const deletedFor = Array.isArray(data.deletedFor) ? data.deletedFor : [];
      if (deletedFor.includes(userId)) {
        continue;
      }

      if (data.senderId === userId) {
        break;
      }

      const readBy = Array.isArray(data.readBy) ? data.readBy : [];
      const isExplicitlyRead = readBy.includes(userId) || data.isRead === true || data.status === 'read';

      if (isExplicitlyRead) {
        break;
      }

      unreadCount += 1;
    }

    return Math.max(1, unreadCount);
  } catch (error) {
    return 1;
  }
}

// Mensajes propios con reacción ajena desde la última lectura del chat (plural estilo "2 mensajes").
async function getUnreadReactionSummary(conversationId, authorId, conversationData) {
  try {
    const lastReadAt = conversationData.lastReadAt || {};
    const lastReadValue = lastReadAt[authorId];
    const lastReadMillis = lastReadValue && typeof lastReadValue.toMillis === 'function'
      ? lastReadValue.toMillis()
      : null;

    const reactionsSnap = await admin.firestore()
      .collectionGroup('messageReactions')
      .where('conversationId', '==', conversationId)
      .get();

    if (reactionsSnap.empty) return { count: 1, emojis: [] };

    const reactionEntries = [];
    for (const doc of reactionsSnap.docs) {
      const data = doc.data() || {};
      const reactorId = typeof data.userId === 'string' ? data.userId : doc.id;
      if (reactorId === authorId) continue;

      const reactionMillis = data.timestamp && typeof data.timestamp.toMillis === 'function'
        ? data.timestamp.toMillis()
        : Date.now();

      if (lastReadMillis && reactionMillis <= lastReadMillis) {
        continue;
      }

      const emoji = typeof data.emoji === 'string' ? data.emoji.trim() : '';
      if (typeof data.messageId === 'string' && data.messageId) {
        reactionEntries.push({ messageId: data.messageId, emoji, reactionMillis });
      }
    }

    if (reactionEntries.length === 0) return { count: 1, emojis: [] };

    reactionEntries.sort((a, b) => b.reactionMillis - a.reactionMillis);

    const candidateMessageIds = new Set();
    const emojisOrdered = [];
    const seenEmojis = new Set();
    for (const entry of reactionEntries) {
      candidateMessageIds.add(entry.messageId);
      if (entry.emoji && !seenEmojis.has(entry.emoji)) {
        seenEmojis.add(entry.emoji);
        emojisOrdered.push(entry.emoji);
      }
    }

    const messageRefs = [...candidateMessageIds].map((messageId) =>
      admin.firestore().doc(`conversations/${conversationId}/messages/${messageId}`)
    );
    const messageDocs = await admin.firestore().getAll(...messageRefs);

    let count = 0;
    for (const msgDoc of messageDocs) {
      if (!msgDoc.exists) continue;
      const msg = msgDoc.data() || {};
      if (msg.senderId !== authorId || msg.isDeleted === true) continue;
      count += 1;
    }

    return { count: Math.max(1, count), emojis: emojisOrdered };
  } catch (error) {
    console.error('Error summarizing unread reacted own messages:', error);
    return { count: 1, emojis: [] };
  }
}

// ✅ IDs estables para notificaciones sociales (follow / mutual / request)
function socialNotificationDocId(type, peerId) {
  if (!peerId || typeof peerId !== 'string') return null;
  switch (type) {
    case 'newFollower':
      return `newFollower_${peerId}`;
    case 'mutualConnection':
      return `mutualConnection_${peerId}`;
    case 'followRequest':
      return `followRequest_${peerId}`;
    default:
      return null;
  }
}

async function upsertSocialNotification(recipientId, docId, payload) {
  const ref = admin.firestore().doc(`users/${recipientId}/notifications/${docId}`);
  await ref.set({
    ...payload,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    isPending: true
  }, { merge: true });
}

async function purgeSocialNotifications(recipientId, { type, senderId }) {
  if (!recipientId || !type || !senderId) return;

  const stableId = socialNotificationDocId(type, senderId);
  if (stableId) {
    const stableRef = admin.firestore().doc(`users/${recipientId}/notifications/${stableId}`);
    const stableSnap = await stableRef.get();
    if (stableSnap.exists) {
      await stableRef.delete();
    }
  }

  const legacySnap = await admin.firestore()
    .collection(`users/${recipientId}/notifications`)
    .where('type', '==', type)
    .where('senderId', '==', senderId)
    .get();

  if (legacySnap.empty) return;

  const batch = admin.firestore().batch();
  let ops = 0;
  for (const doc of legacySnap.docs) {
    if (stableId && doc.id === stableId) continue;
    batch.delete(doc.ref);
    ops += 1;
    if (ops >= 450) break;
  }
  if (ops > 0) {
    await batch.commit();
  }
}

async function upsertMutualDocuments(userId, otherUserId, timestamp = null) {
  const ts = timestamp || admin.firestore.FieldValue.serverTimestamp();
  const batch = admin.firestore().batch();
  batch.set(
    admin.firestore().doc(`users/${userId}/mutuals/${otherUserId}`),
    { userId: otherUserId, timestamp: ts },
    { merge: true }
  );
  batch.set(
    admin.firestore().doc(`users/${otherUserId}/mutuals/${userId}`),
    { userId, timestamp: ts },
    { merge: true }
  );
  await batch.commit();
}

async function deleteMutualDocuments(userId, otherUserId) {
  await Promise.all([
    admin.firestore().doc(`users/${userId}/mutuals/${otherUserId}`).delete().catch(() => null),
    admin.firestore().doc(`users/${otherUserId}/mutuals/${userId}`).delete().catch(() => null)
  ]);
}

// ✅ FUNCIÓN AUXILIAR: Enviar notificación de conexión mutua
async function sendMutualConnectionNotification(receiverData, senderData, receiverId, senderId, count = 1) {
  try {
    const isSilencedByMuteSettings = shouldSilenceNotificationForUser(receiverData, {
      senderId: senderId,
      candidateTexts: [senderData?.username]
    });
    if (isSilencedByMuteSettings) {
      return;
    }

    if (!receiverData.fcmToken || isDoNotDisturbActive(receiverData) || !notificationTypeEnabled(receiverData, 'mutualConnection')) {
      return;
    }

    // ✅ Usar loc-keys (iOS traduce según el idioma del dispositivo) en lugar de texto fijo en español.
    const message = {
      token: receiverData.fcmToken,
      data: {
        type: 'mutualConnection',
        senderId: senderId,
        userId: receiverId,
        targetType: 'profile',
        targetId: senderId,
        senderUsername: senderData.username,
        senderProfileImage: senderData.profileImagePath || ''
      },
      apns: {
        headers: {
          // Compartido por receptor: las mutuas seguidas colapsan en una sola notificación
          // que se actualiza con el agregado "X y N más" (igual que el push de seguidores).
          'apns-collapse-id': `mutual_${receiverId}`
        },
        payload: {
          aps: {
            alert: count > 1
              ? {
                  'title-loc-key': 'notification.mutualConnection.multiple.title',
                  'title-loc-args': [],
                  'loc-key': 'notification.mutualConnection.multiple.body',
                  'loc-args': [senderData.username, String(count - 1)]
                }
              : {
                  'title-loc-key': 'notification.mutualConnection.title',
                  'loc-key': 'notification.mutualConnection.body',
                  'loc-args': [senderData.username]
                },
            badge: 1,
            sound: 'default',
            'mutable-content': 1,
            'thread-id': `mutual_connections_${receiverId}` // ✅ Agrupación para conexiones mutuas
          }
        }
      }
    };

    await admin.messaging().send(message);
    console.log(`✅ Notificación de conexión mutua enviada: ${senderData.username} ↔ ${receiverData.username}`);

  } catch (error) {
    if (error.code === 'messaging/registration-token-not-registered') {
      await removeInvalidToken(receiverId, receiverData.fcmToken);
    } else {
      console.error('❌ Error enviando notificación de conexión mutua:', error);
    }
  }
}

async function reconcileMutualConnection(userId, followerId, userData, followerData) {
  await upsertMutualDocuments(userId, followerId);

  await Promise.all([
    purgeSocialNotifications(userId, { type: 'newFollower', senderId: followerId }),
    purgeSocialNotifications(followerId, { type: 'newFollower', senderId: userId })
  ]);

  const isSilencedForUser = shouldSilenceNotificationForUser(userData, {
    senderId: followerId,
    candidateTexts: [followerData.username]
  });
  if (!isSilencedForUser) {
    const mutualCountForUser = await getPendingMutualConnectionCount(userId, followerId);
    await sendMutualConnectionNotification(userData, followerData, userId, followerId, mutualCountForUser);
    await upsertSocialNotification(userId, socialNotificationDocId('mutualConnection', followerId), {
      type: 'mutualConnection',
      senderId: followerId,
      senderUsername: followerData.username,
      senderProfileImage: followerData.profileImagePath || ''
    });
  }

  const isSilencedForFollower = shouldSilenceNotificationForUser(followerData, {
    senderId: userId,
    candidateTexts: [userData.username]
  });
  if (!isSilencedForFollower) {
    const mutualCountForFollower = await getPendingMutualConnectionCount(followerId, userId);
    await sendMutualConnectionNotification(followerData, userData, followerId, userId, mutualCountForFollower);
    await upsertSocialNotification(followerId, socialNotificationDocId('mutualConnection', userId), {
      type: 'mutualConnection',
      senderId: userId,
      senderUsername: userData.username,
      senderProfileImage: userData.profileImagePath || ''
    });
  }
}

// ✅ Ventana de agregación: el conteo del push refleja actividad reciente,
// no un historial infinito. (isPending ya actúa como "watermark": al abrir el inbox se marca leído.)
const SOCIAL_AGGREGATION_WINDOW_DAYS = 7;

function isWithinAggregationWindow(timestamp) {
  if (!timestamp || typeof timestamp.toMillis !== 'function') return true; // sin timestamp fiable: no excluir
  const cutoff = Date.now() - SOCIAL_AGGREGATION_WINDOW_DAYS * 24 * 60 * 60 * 1000;
  return timestamp.toMillis() >= cutoff;
}

// ✅ Contar seguidores pendientes únicos y vivos (para agrupar push: "Username y X más te han seguido")
async function getPendingFollowerCount(userId, additionalSenderId = null) {
  try {
    const snap = await admin.firestore()
      .collection(`users/${userId}/notifications`)
      .where('type', '==', 'newFollower')
      .where('isPending', '==', true)
      .get();
    const senderIds = new Set();
    snap.docs.forEach((doc) => {
      const data = doc.data();
      const sid = data.senderId;
      if (typeof sid === 'string' && sid.length > 0 && isWithinAggregationWindow(data.timestamp)) {
        senderIds.add(sid);
      }
    });
    if (typeof additionalSenderId === 'string' && additionalSenderId.length > 0) {
      senderIds.add(additionalSenderId);
    }

    if (senderIds.size === 0) {
      return 1;
    }

    const senderIdList = Array.from(senderIds);
    const followerRefs = senderIdList.map((senderId) =>
      admin.firestore().doc(`users/${userId}/followers/${senderId}`)
    );
    const followerSnaps = await admin.firestore().getAll(...followerRefs);

    const activeSenderIds = new Set();
    const staleSenderIds = [];
    followerSnaps.forEach((docSnap, index) => {
      const senderId = senderIdList[index];
      if (docSnap.exists) {
        activeSenderIds.add(senderId);
      } else {
        staleSenderIds.push(senderId);
      }
    });

    if (staleSenderIds.length > 0) {
      await Promise.all(
        staleSenderIds.map((senderId) =>
          purgeSocialNotifications(userId, { type: 'newFollower', senderId })
        )
      );
    }

    return Math.max(1, activeSenderIds.size);
  } catch (error) {
    return 1;
  }
}

// ✅ Contar conexiones mutuas pendientes, únicas y vivas (mutua válida en AMBOS sentidos).
// Valida contra el grafo y purga zombies cuya relación ya se rompió. Sin colección extra.
async function getPendingMutualConnectionCount(userId, additionalSenderId = null) {
  try {
    const snap = await admin.firestore()
      .collection(`users/${userId}/notifications`)
      .where('type', '==', 'mutualConnection')
      .where('isPending', '==', true)
      .get();
    const senderIds = new Set();
    snap.docs.forEach((doc) => {
      const data = doc.data();
      const sid = data.senderId;
      if (typeof sid === 'string' && sid.length > 0 && isWithinAggregationWindow(data.timestamp)) {
        senderIds.add(sid);
      }
    });
    if (typeof additionalSenderId === 'string' && additionalSenderId.length > 0) {
      senderIds.add(additionalSenderId);
    }

    if (senderIds.size === 0) {
      return 1;
    }

    const senderIdList = Array.from(senderIds);
    // Mutua viva = me siguen Y les sigo
    const forwardRefs = senderIdList.map((sid) =>
      admin.firestore().doc(`users/${userId}/followers/${sid}`)
    );
    const reverseRefs = senderIdList.map((sid) =>
      admin.firestore().doc(`users/${sid}/followers/${userId}`)
    );
    const [forwardSnaps, reverseSnaps] = await Promise.all([
      admin.firestore().getAll(...forwardRefs),
      admin.firestore().getAll(...reverseRefs)
    ]);

    const activeSenderIds = new Set();
    const staleSenderIds = [];
    senderIdList.forEach((sid, index) => {
      const mutualAlive = forwardSnaps[index].exists && reverseSnaps[index].exists;
      if (mutualAlive) {
        activeSenderIds.add(sid);
      } else {
        staleSenderIds.push(sid);
      }
    });

    if (staleSenderIds.length > 0) {
      await Promise.all(
        staleSenderIds.map((sid) =>
          purgeSocialNotifications(userId, { type: 'mutualConnection', senderId: sid })
        )
      );
    }

    return Math.max(1, activeSenderIds.size);
  } catch (error) {
    return 1;
  }
}

// ✅ Contar comentarios pendientes en un momento específico
async function getPendingCommentCount(momentOwnerId, momentId) {
  try {
    const snap = await admin.firestore()
      .collection(`users/${momentOwnerId}/notifications`)
      .where('type', '==', 'comment')
      .where('momentId', '==', momentId)
      .where('isPending', '==', true)
      .get();
    return snap.size + 1;
  } catch (error) {
    return 1;
  }
}

// ✅ Contar reacciones pendientes en un momento específico (para título agrupado correcto)
async function getPendingMomentReactionCount(momentOwnerId, momentId) {
  try {
    const snap = await admin.firestore()
      .collection(`users/${momentOwnerId}/notifications`)
      .where('type', '==', 'reaction')
      .where('momentId', '==', momentId)
      .where('isPending', '==', true)
      .get();
    return snap.size + 1;
  } catch (error) {
    return 1;
  }
}

// ✅ Contar reacciones pendientes en una historia
async function getPendingStoryReactionCount(storyOwnerId, storyId) {
  try {
    const snap = await admin.firestore()
      .collection(`users/${storyOwnerId}/notifications`)
      .where('type', '==', 'storyReaction')
      .where('storyId', '==', storyId)
      .where('isPending', '==', true)
      .get();
    return snap.size + 1;
  } catch (error) {
    return 1;
  }
}

// ✅ Contar solicitudes de seguimiento pendientes
async function getPendingFollowRequestCount(userId) {
  try {
    const snap = await admin.firestore()
      .collection(`users/${userId}/receivedFollowRequests`)
      .where('status', '==', 'pending')
      .get();
    return snap.size; // No sumamos 1 porque ya está en la colección
  } catch (error) {
    return 1;
  }
}

// ✅ NUEVO: Función para obtener todos los conteos pendientes de un usuario
async function getUnreadCounts(userId, triggerContext = {}) {
  try {
    const [messagesSnap, notificationsSnap] = await Promise.all([
      admin.firestore().collection('conversations')
        .where('participants', 'array-contains', userId)
        .get(),
      admin.firestore().collection(`users/${userId}/notifications`)
        .where('isPending', '==', true)
        .get()
    ]);

    let unreadMessages = 0;
    let unreadInConversation = 0;
    let foundCurrentConversation = false;

    messagesSnap.forEach(doc => {
      const data = doc.data();
      const readStatus = data.readStatus || {};
      if (readStatus[userId] === false) {
        unreadMessages++;
        if (triggerContext.type === 'message' && doc.id === triggerContext.conversationId) {
          unreadInConversation++;
          foundCurrentConversation = true;
        }
      }
    });

    // ✅ SIEMPRE sumamos 1 si es un trigger de mensaje y no lo encontramos aún
    if (triggerContext.type === 'message' && !foundCurrentConversation) {
      unreadMessages++;
      unreadInConversation++;
    }

    let unreadNotifications = notificationsSnap.size;
    let foundCurrentNotification = false;

    // Verificar si la notificación actual ya está en el snap (poco probable por la velocidad de Firebase)
    if (triggerContext.notificationId) {
      foundCurrentNotification = notificationsSnap.docs.some(d => d.id === triggerContext.notificationId);
    }

    // ✅ SIEMPRE sumamos 1 si es un trigger de notificación y no la hemos contado
    if (triggerContext.type === 'notification' && !foundCurrentNotification) {
      unreadNotifications++;
    }

    // Conteos específicos de Echoes y Tags
    let unreadEchoes = notificationsSnap.docs.filter(d => d.data().type === 'echoSuggestion').length;
    if (triggerContext.notificationType === 'echoSuggestion' && !notificationsSnap.docs.some(d => d.data().type === 'echoSuggestion' && d.id === triggerContext.notificationId)) {
      unreadEchoes++;
    }

    let unreadTags = notificationsSnap.docs.filter(d => d.data().type === 'photoTag').length;
    if (triggerContext.notificationType === 'photoTag' && !notificationsSnap.docs.some(d => d.data().type === 'photoTag' && d.id === triggerContext.notificationId)) {
      unreadTags++;
    }

    return {
      unreadMessages,
      unreadNotifications,
      unreadInConversation,
      unreadEchoes,
      unreadTags
    };
  } catch (error) {
    console.error('❌ Error obteniendo conteos:', error);
    return {
      unreadMessages: 0,
      unreadNotifications: 0,
      unreadInConversation: 0,
      unreadEchoes: 0,
      unreadTags: 0
    };
  }
}

module.exports = {
  validateUserData,
  removeInvalidToken,
  buildMessageRequestConversationPreview,
  findExistingDirectConversation,
  isActiveUserData,
  usersAreBlocked,
  parseTimeToMinutes,
  isDoNotDisturbActive,
  asDate,
  hoursSince,
  daysSince,
  startOfTodayInTimezone,
  hasPostedToday,
  gentleRemindersEnabled,
  notificationTypeEnabled,
  normalizeReminderHistory,
  buildGentleReminderState,
  chooseGentleReminderVariant,
  sendGentleReminderPush,
  normalizeMutedWords,
  getMuteSettings,
  textContainsMutedWord,
  shouldSilenceNotificationForUser,
  pickMomentPreviewUrl,
  pickStoryPreviewUrl,
  apnsCollapseId,
  getUnreadMessagesInConversation,
  getUnreadReactionSummary,
  socialNotificationDocId,
  upsertSocialNotification,
  purgeSocialNotifications,
  upsertMutualDocuments,
  deleteMutualDocuments,
  reconcileMutualConnection,
  sendMutualConnectionNotification,
  isWithinAggregationWindow,
  getPendingFollowerCount,
  getPendingMutualConnectionCount,
  getPendingCommentCount,
  getPendingMomentReactionCount,
  getPendingStoryReactionCount,
  getPendingFollowRequestCount,
  getUnreadCounts,
};
