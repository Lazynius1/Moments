const { onDocumentCreated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onRequest } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const { defineSecret } = require('firebase-functions/params');
setGlobalOptions({ region: 'europe-southwest1', memory: '256MiB', concurrency: 80, retry: true });
const admin = require('firebase-admin');
admin.initializeApp();

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const SIGHTENGINE_USER = defineSecret('SIGHTENGINE_USER');
const SIGHTENGINE_SECRET = defineSecret('SIGHTENGINE_SECRET');
const GOOGLE_SPEECH_API_KEY = defineSecret('GOOGLE_SPEECH_API_KEY');
const GIPHY_API_KEY = defineSecret('GIPHY_API_KEY');

function setProxyCors(res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.set('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
}

function parseJsonBody(req) {
  if (!req.body) return {};
  if (typeof req.body === 'object') return req.body;
  try {
    return JSON.parse(req.body);
  } catch (error) {
    return {};
  }
}

async function verifyFirebaseAuth(req, res) {
  const authHeader = req.get('authorization') || '';
  if (!authHeader.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Unauthorized' });
    return null;
  }

  const idToken = authHeader.slice(7).trim();
  if (!idToken) {
    res.status(401).json({ error: 'Unauthorized' });
    return null;
  }

  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    return decoded.uid;
  } catch (error) {
    res.status(401).json({ error: 'Unauthorized' });
    return null;
  }
}

exports.proxyOpenAIModeration = onRequest(
  {
    timeoutSeconds: 30,
    secrets: [OPENAI_API_KEY]
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

    const uid = await verifyFirebaseAuth(req, res);
    if (!uid) return;

    const body = parseJsonBody(req);
    const input = typeof body.input === 'string' ? body.input : '';
    if (!input.trim()) {
      res.status(400).json({ error: 'Missing input' });
      return;
    }

    try {
      const upstream = await fetch('https://api.openai.com/v1/moderations', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${OPENAI_API_KEY.value()}`
        },
        body: JSON.stringify({ input })
      });

      const payload = await upstream.text();
      res.status(upstream.status).set('Content-Type', 'application/json').send(payload);
    } catch (error) {
      console.error('proxyOpenAIModeration error:', error);
      res.status(500).json({ error: 'Moderation proxy failed' });
    }
  }
);

exports.proxySightengineFrame = onRequest(
  {
    timeoutSeconds: 30,
    secrets: [SIGHTENGINE_USER, SIGHTENGINE_SECRET]
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

    const uid = await verifyFirebaseAuth(req, res);
    if (!uid) return;

    const body = parseJsonBody(req);
    const frameBase64 = typeof body.frameBase64 === 'string' ? body.frameBase64 : '';
    if (!frameBase64) {
      res.status(400).json({ error: 'Missing frameBase64' });
      return;
    }

    try {
      const imageBuffer = Buffer.from(frameBase64, 'base64');
      const formData = new FormData();
      formData.append('api_user', SIGHTENGINE_USER.value());
      formData.append('api_secret', SIGHTENGINE_SECRET.value());
      formData.append('models', 'nudity-2.1,face-attributes,scam,offensive');
      formData.append('media', new Blob([imageBuffer], { type: 'image/jpeg' }), 'frame.jpg');

      const upstream = await fetch('https://api.sightengine.com/1.0/check.json', {
        method: 'POST',
        body: formData
      });

      const payload = await upstream.text();
      res.status(upstream.status).set('Content-Type', 'application/json').send(payload);
    } catch (error) {
      console.error('proxySightengineFrame error:', error);
      res.status(500).json({ error: 'Sightengine proxy failed' });
    }
  }
);

exports.proxySpeechToText = onRequest(
  {
    timeoutSeconds: 30,
    secrets: [GOOGLE_SPEECH_API_KEY]
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

    const uid = await verifyFirebaseAuth(req, res);
    if (!uid) return;

    const body = parseJsonBody(req);
    const audioBase64 = typeof body.audioBase64 === 'string' ? body.audioBase64 : '';
    if (!audioBase64) {
      res.status(400).json({ error: 'Missing audioBase64' });
      return;
    }

    const requestBody = {
      config: {
        encoding: 'LINEAR16',
        sampleRateHertz: 44100,
        languageCode: 'es-ES',
        enableAutomaticPunctuation: true,
        model: 'latest_short'
      },
      audio: {
        content: audioBase64
      }
    };

    try {
      const speechURL = `https://speech.googleapis.com/v1/speech:recognize?key=${encodeURIComponent(GOOGLE_SPEECH_API_KEY.value())}`;
      const upstream = await fetch(speechURL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(requestBody)
      });

      const payload = await upstream.text();
      res.status(upstream.status).set('Content-Type', 'application/json').send(payload);
    } catch (error) {
      console.error('proxySpeechToText error:', error);
      res.status(500).json({ error: 'Speech proxy failed' });
    }
  }
);

exports.proxyGiphyStickers = onRequest(
  {
    timeoutSeconds: 30,
    secrets: [GIPHY_API_KEY]
  },
  async (req, res) => {
    setProxyCors(res);
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST' && req.method !== 'GET') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const uid = await verifyFirebaseAuth(req, res);
    if (!uid) return;

    const body = parseJsonBody(req);
    const modeSource = req.method === 'GET' ? req.query : body;
    const mode = modeSource.mode === 'search' ? 'search' : 'trending';
    const rating = typeof modeSource.rating === 'string' ? modeSource.rating : 'pg';
    const rawLimit = Number(modeSource.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 50)) : 24;
    const query = typeof modeSource.query === 'string' ? modeSource.query.trim() : '';

    if (mode === 'search' && !query) {
      res.status(400).json({ error: 'Missing query for search mode' });
      return;
    }

    const params = new URLSearchParams({
      api_key: GIPHY_API_KEY.value(),
      limit: String(limit),
      rating
    });
    if (mode === 'search') {
      params.set('q', query);
    }

    const endpoint = mode === 'search'
      ? 'https://api.giphy.com/v1/stickers/search'
      : 'https://api.giphy.com/v1/stickers/trending';

    try {
      const upstream = await fetch(`${endpoint}?${params.toString()}`, { method: 'GET' });
      const payload = await upstream.text();
      res.status(upstream.status).set('Content-Type', 'application/json').send(payload);
    } catch (error) {
      console.error('proxyGiphyStickers error:', error);
      res.status(500).json({ error: 'Giphy proxy failed' });
    }
  }
);

// ✅ FUNCIÓN auxiliar para validar datos de usuario
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

// ✅ Contar mensajes no leídos EN UNA CONVERSACIÓN ESPECÍFICA
async function getUnreadMessagesInConversation(conversationId, userId) {
  try {
    const messagesSnap = await admin.firestore()
      .collection('conversations')
      .doc(conversationId)
      .collection('messages')
      .where('status', 'in', ['sent', 'delivered'])
      .get();
    const unreadCount = messagesSnap.docs.filter(doc => doc.data().senderId !== userId).length;
    return unreadCount + 1; // +1 por el mensaje actual
  } catch (error) {
    return 1;
  }
}

// ✅ Contar seguidores pendientes (para agrupar: "Username y X más te han seguido")
async function getPendingFollowerCount(userId) {
  try {
    const snap = await admin.firestore()
      .collection(`users/${userId}/notifications`)
      .where('type', '==', 'newFollower')
      .where('isPending', '==', true)
      .get();
    return snap.size + 1; // +1 por el actual
  } catch (error) {
    return 1;
  }
}

// ✅ Contar comentarios pendientes en un momento específico
async function getPendingCommentCount(momentOwnerId, momentId) {
  try {
    const snap = await admin.firestore()
      .collection(`users/${momentOwnerId}/notifications`)
      .where('type', '==', 'momentComment')
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

// 🔥 REACCIONES EN MOMENTOS - VERSIÓN SIMPLIFICADA CON AGRUPACIÓN NATIVA
exports.onMomentReactionAdded = onDocumentCreated('users/{userId}/moments/{momentId}/reactions/{reactionId}', async (event) => {
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
    const fcmToken = momentOwnerData.fcmToken;
    if (!fcmToken) return null;

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
    const newReactionCount = await admin.firestore().runTransaction(async (tx) => {
      const [momentSnap, reactionSnap] = await Promise.all([tx.get(momentRef), tx.get(reactionRef)]);
      const alreadyProcessed = reactionSnap.exists && reactionSnap.get('processed') === true;
      if (!momentSnap.exists) {
        throw new Error('Moment doc missing');
      }
      const currentCount = momentSnap.get('reactionCount') || 0;
      if (alreadyProcessed) {
        return currentCount;
      }
      tx.update(momentRef, { reactionCount: admin.firestore.FieldValue.increment(1) });
      tx.update(reactionRef, { processed: true });
      return currentCount + 1;
    });

    // ✅ TÍTULO DINÁMICO basado en número de reacciones
    const username = reacterData.username || 'Alguien';
    const reactionCount = Math.max(1, newReactionCount);

    // Determinar claves de localización
    let titleLocKey, titleLocArgs, bodyLocKey, bodyLocArgs;
    if (reactionCount === 1) {
      titleLocKey = 'notification.momentReaction.single.title';
      titleLocArgs = [username, emoji];
      bodyLocKey = 'notification.momentReaction.single.body';
      bodyLocArgs = [];
    } else {
      titleLocKey = 'notification.momentReaction.multiple.title';
      titleLocArgs = [username, String(reactionCount - 1)];
      bodyLocKey = 'notification.momentReaction.multiple.body';
      bodyLocArgs = [String(reactionCount)];
    }

    // ✅ Obtener conteos actualizados para el Widget
    const counts = await getUnreadCounts(userId, { type: 'notification', notificationType: 'momentReaction', notificationId: reactionId });

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
            'summary-arg-count': newReactionCount
          }
        }
      }
    };

    try {
      await admin.messaging().send(message);
      console.log(`✅ Notificación enviada: ${username} -> ${momentOwnerData.username} (${reaction.reactionType}) - Total: ${reactionCount}`);
    } catch (error) {
      if (error.code === 'messaging/registration-token-not-registered') {
        await removeInvalidToken(userId, fcmToken);
      }
      throw error;
    }

    // Crear notificación en Firestore
    await admin.firestore().collection(`users/${userId}/notifications`).add({
      type: 'reaction', // ✅ CORREGIDO: Para reacciones en momentos
      senderId: reaction.userId,
      senderUsername: username, // ✅ Usar username validado
      senderProfileImage: reacterData.profileImagePath || '',
      momentId: momentId,
      reactionType: reaction.reactionType,
      reactionCount: reactionCount, // ✅ Usar reactionCount validado
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isPending: true
    });

  } catch (error) {
    console.error('❌ Error sending reaction notification:', error);
  }
});

// ✅ ACTUALIZAR BADGE SILENCIOSAMENTE
exports.updateBadge = onDocumentCreated('users/{userId}/notifications/{notificationId}', async (event) => {
  const { userId } = event.params;

  try {
    const userDoc = await admin.firestore().doc(`users/${userId}`).get();
    if (!userDoc.exists) return null;

    const userData = userDoc.data();
    if (!validateUserData(userData) || !userData.fcmToken) return null;

    const notifications = await admin.firestore()
      .collection(`users/${userId}/notifications`)
      .where('isPending', '==', true)
      .get();

    const badgeCount = notifications.size;

    const message = {
      token: userData.fcmToken,
      data: {
        silent: 'true'
      },
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
  } catch (error) {
    console.error('❌ Error actualizando badge:', error);
  }
});

// ✅ LIMPIEZA PROGRAMADA
exports.cleanOldNotifications = onSchedule(
  { schedule: '0 0 * * *', timeZone: 'Europe/Madrid', region: 'us-central1' },
  async () => {
    try {
      const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

      const usersSnapshot = await admin.firestore().collection('users').get();

      const deletePromises = usersSnapshot.docs.map(async (userDoc) => {
        const notificationsRef = userDoc.ref.collection('notifications');
        const oldNotifications = await notificationsRef
          .where('timestamp', '<', thirtyDaysAgo)
          .where('isPending', '==', false)
          .get();

        const batch = admin.firestore().batch();
        oldNotifications.forEach(doc => batch.delete(doc.ref));

        if (oldNotifications.size > 0) {
          await batch.commit();
          console.log(`✅ Eliminadas ${oldNotifications.size} notificaciones antiguas para usuario ${userDoc.id}`);
        }
      });

      await Promise.all(deletePromises);
      console.log('✅ Limpieza de notificaciones completada');
    } catch (error) {
      console.error('❌ Error en limpieza de notificaciones:', error);
    }
  });


// 💬 COMENTARIOS EN MOMENTOS
exports.onMomentCommentAdded = onDocumentCreated('users/{userId}/moments/{momentId}/comments/{commentId}', async (event) => {
  const snap = event.data;
  const { userId, momentId, commentId } = event.params;
  const comment = snap.data();

  try {
    if (comment.authorId === userId) return null;

    const [commenterDoc, momentOwnerDoc] = await Promise.all([
      admin.firestore().doc(`users/${comment.authorId}`).get(),
      admin.firestore().doc(`users/${userId}`).get()
    ]);

    if (!commenterDoc.exists || !momentOwnerDoc.exists) return null;

    const commenterData = commenterDoc.data();
    const momentOwnerData = momentOwnerDoc.data();

    if (!validateUserData(commenterData) || !validateUserData(momentOwnerData)) {
      console.warn('⚠️ Datos de usuario incompletos para comentario');
      return null;
    }

    if (!commenterData.isActive || !momentOwnerData.isActive) return null;

    const fcmToken = momentOwnerData.fcmToken;
    if (!fcmToken) return null;

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

    try {
      await admin.messaging().send(message);
      console.log(`✅ Notificación de comentario enviada: ${commenterData.username} -> ${momentOwnerData.username}`);
    } catch (error) {
      if (error.code === 'messaging/registration-token-not-registered') {
        await removeInvalidToken(userId, fcmToken);
      }
      throw error;
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
exports.onFollowerAdded = onDocumentCreated('users/{userId}/followers/{followerId}', async (event) => {
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

    const fcmToken = userData.fcmToken;
    if (!fcmToken) return null;

    const cleanImageUrl = followerData.profileImagePath
      ? followerData.profileImagePath.replace(':443', '')
      : null;

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

    // ✅ NUEVO: Verificar si se crea una conexión mutua
    const isMutualConnection = await checkMutualConnection(userId, followerId);

    let notificationTitle, notificationBody, notificationType;

    if (isMutualConnection) {
      // ✅ CONEXIÓN MUTUA
      notificationTitle = `Ahora tienes una conexión mutua con ${followerData.username}`;
      notificationBody = '¡Ambos se siguen mutuamente!';
      notificationType = 'mutualConnection';

      // ✅ ENVIAR NOTIFICACIÓN AL USUARIO ORIGINAL
      await sendMutualConnectionNotification(userData, followerData, userId, followerId);

      // ✅ ENVIAR NOTIFICACIÓN AL SEGUIDOR TAMBIÉN
      if (followerData.fcmToken) {
        await sendMutualConnectionNotification(followerData, userData, followerId, userId);

        // ✅ GUARDAR NOTIFICACIÓN EN FIRESTORE PARA EL SEGUIDOR TAMBIÉN
        await admin.firestore().collection(`users/${followerId}/notifications`).add({
          type: 'mutualConnection',
          senderId: userId,
          senderUsername: userData.username,
          senderProfileImage: userData.profileImagePath || '',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          isPending: true
        });
      }

    } else {
      // ✅ SEGUIDOR NORMAL
      notificationType = 'newFollower';

      // Obtener conteos
      const [counts, followerCount] = await Promise.all([
        getUnreadCounts(userId, { type: 'notification', notificationType: 'newFollower' }),
        getPendingFollowerCount(userId)
      ]);

      // Determinar claves de localización
      let titleLocKey, titleLocArgs, bodyLocKey, bodyLocArgs;
      if (followerCount > 1) {
        titleLocKey = 'notification.follower.multiple.title';
        titleLocArgs = [followerData.username, String(followerCount - 1)];
        bodyLocKey = 'notification.follower.multiple.body';
        bodyLocArgs = [String(followerCount)];
      } else {
        titleLocKey = 'notification.follower.single.title';
        titleLocArgs = [followerData.username];
        bodyLocKey = 'notification.follower.single.body';
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

      try {
        await admin.messaging().send(message);
        console.log(`✅ Notificación de seguidor enviada: ${followerData.username} -> ${userData.username}`);
      } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
          await removeInvalidToken(userId, fcmToken);
        }
        throw error;
      }
    }

    // ✅ GUARDAR NOTIFICACIÓN EN FIRESTORE
    await admin.firestore().collection(`users/${userId}/notifications`).add({
      type: notificationType,
      senderId: followerId,
      senderUsername: followerData.username,
      senderProfileImage: followerData.profileImagePath || '',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isPending: true
    });

  } catch (error) {
    console.error('❌ Error sending follower notification:', error);
  }
});

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

// ✅ FUNCIÓN AUXILIAR: Enviar notificación de conexión mutua
async function sendMutualConnectionNotification(receiverData, senderData, receiverId, senderId) {
  try {
    const message = {
      token: receiverData.fcmToken,
      notification: {
        title: `Ahora tienes una conexión mutua con ${senderData.username}`,
        body: '¡Ambos se siguen mutuamente!',
        image: senderData.profileImagePath ? senderData.profileImagePath.replace(':443', '') : null
      },
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
        payload: {
          aps: {
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

// 💬 MENSAJES DIRECTOS
exports.onMessageAdded = onDocumentCreated('conversations/{conversationId}/messages/{messageId}', async (event) => {
  const snap = event.data;
  const { conversationId, messageId } = event.params;
  const message = snap.data();

  try {
    const conversationDoc = await admin.firestore().doc(`conversations/${conversationId}`).get();
    if (!conversationDoc.exists) return null;

    const conversationData = conversationDoc.data();
    const participants = conversationData.participants;
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

      if (!receiverData.fcmToken) {
        return null;
      }

      // ✅ VERIFICAR SI LA CONVERSACIÓN ESTÁ SILENCIADA PARA ESTE USUARIO
      if (conversationData.isMuted === true) {
        return null;
      }

      let notificationTitle = senderData.username || 'Nuevo mensaje';
      let notificationBody = '';

      switch (message.type) {
        case 'text':
          notificationBody = 'Te envió un mensaje';
          break;
        case 'image':
          notificationBody = 'Te envió una foto 📷';
          break;
        case 'video':
          notificationBody = 'Te envió un video 🎥';
          break;
        case 'audio':
          notificationBody = 'Te envió un audio 🎵';
          break;
        case 'viewOnceImage':
          notificationBody = 'Te envió una foto que se ve una vez 📷✨';
          break;
        case 'viewOnceVideo':
          notificationBody = 'Te envió un video que se ve una vez 🎥✨';
          break;
        case 'location':
          notificationBody = 'Te envió su ubicación 📍';
          break;
        case 'file':
          notificationBody = 'Te envió un archivo 📎';
          break;
        case 'gif':
          notificationBody = 'Te envió un GIF 🎭';
          break;
        default:
          notificationBody = 'Te envió un mensaje';
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

      const notificationMessage = {
        token: receiverData.fcmToken,
        data: {
          type: 'new_message',
          conversationId: conversationId,
          messageId: messageId,
          senderId: message.senderId,
          targetType: 'conversation',
          targetId: conversationId,
          senderUsername: senderData.username,
          senderProfileImage: senderData.profileImagePath || '',
          unreadMessages: String(counts.unreadMessages),
          unreadNotifications: String(counts.unreadNotifications),
          unreadEchoes: String(counts.unreadEchoes),
          unreadTags: String(counts.unreadTags)
        },
        apns: {
          headers: {
            'apns-collapse-id': `msg_${conversationId}`
          },
          payload: {
            aps: {
              alert: {
                title: senderData.username || 'Moments',
                'loc-key': bodyLocKey,
                'loc-args': bodyLocArgs
              },
              badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
              sound: 'default',
              'mutable-content': 1,
              'thread-id': `conversation_${conversationId}`
            }
          }
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

// 📖 REACCIONES EN HISTORIAS
exports.onStoryReactionAdded = onDocumentCreated('users/{userId}/stories/{storyId}/reactions/{reactionId}', async (event) => {
  const snap = event.data;
  const { userId, storyId, reactionId } = event.params;
  const reaction = snap.data();

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

    const fcmToken = storyOwnerData.fcmToken;
    if (!fcmToken) return null;

    const emoji = reaction.reaction || '❤️';

    const cleanImageUrl = reacterData.profileImagePath
      ? reacterData.profileImagePath.replace(':443', '')
      : null;

    // ✅ Obtener conteos actualizados para el Widget
    const [counts, reactionCount] = await Promise.all([
      getUnreadCounts(userId, { type: 'notification', notificationType: 'storyReaction', notificationId: reactionId }),
      getPendingStoryReactionCount(userId, storyId)
    ]);

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

    try {
      await admin.messaging().send(message);
      console.log(`✅ Notificación de reacción a historia enviada: ${reacterData.username} -> ${storyOwnerData.username} (${emoji})`);
    } catch (error) {
      if (error.code === 'messaging/registration-token-not-registered') {
        await removeInvalidToken(userId, fcmToken);
      }
      throw error;
    }

    await admin.firestore().collection(`users/${userId}/notifications`).add({
      type: 'storyReaction',
      senderId: reaction.userId,
      senderUsername: reacterData.username,
      senderProfileImage: reacterData.profileImagePath || '',
      storyId: storyId,
      reaction: reaction.reaction,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isPending: true,
      notificationId: `story_reaction_${storyId}_${reaction.userId}_${Date.now()}`
    });

  } catch (error) {
    console.error('❌ Error sending story reaction notification:', error);
  }
});

// 🔔 SOLICITUDES DE SEGUIMIENTO
exports.onFollowRequestReceived = onDocumentCreated('users/{userId}/receivedFollowRequests/{requestId}', async (event) => {
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

    const fcmToken = userData.fcmToken;
    if (!fcmToken) return null;

    const cleanImageUrl = requesterData.profileImagePath
      ? requesterData.profileImagePath.replace(':443', '')
      : null;

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

    try {
      await admin.messaging().send(message);
      console.log(`✅ Notificación de solicitud enviada: ${requesterData.username} -> ${userData.username}`);
    } catch (error) {
      if (error.code === 'messaging/registration-token-not-registered') {
        await removeInvalidToken(userId, fcmToken);
      }
      throw error;
    }

    await admin.firestore().collection(`users/${userId}/notifications`).add({
      type: 'followRequest',
      senderId: request.senderId,
      senderUsername: requesterData.username,
      senderProfileImage: requesterData.profileImagePath || '',
      requestId: requestId,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isPending: true
    });

  } catch (error) {
    console.error('❌ Error sending follow request notification:', error);
  }
});

// 🔔 MENCIONES EN CUALQUIER CONTENIDO (HISTORIAS, MOMENTOS, COMENTARIOS)
exports.onMentionNotification = onDocumentCreated('users/{userId}/notifications/{notificationId}', async (event) => {
  const snap = event.data;
  const { userId, notificationId } = event.params;
  const notification = snap.data();

  // Solo procesar notificaciones de menciones
  if (notification.type !== 'mention') return null;

  try {
    const [senderDoc, userDoc] = await Promise.all([
      admin.firestore().doc(`users/${notification.senderId}`).get(),
      admin.firestore().doc(`users/${userId}`).get()
    ]);

    if (!senderDoc.exists || !userDoc.exists) return null;

    const senderData = senderDoc.data();
    const userData = userDoc.data();

    if (!validateUserData(senderData) || !validateUserData(userData)) {
      console.warn('⚠️ Datos de usuario incompletos para mención');
      return null;
    }

    if (!senderData.isActive || !userData.isActive) return null;

    const fcmToken = userData.fcmToken;
    if (!fcmToken) return null;

    const cleanImageUrl = senderData.profileImagePath
      ? senderData.profileImagePath.replace(':443', '')
      : null;

    // ✅ Idempotencia por notificación de mención
    const mentionRef = admin.firestore().doc(`users/${userId}/notifications/${notificationId}`);
    const done = await admin.firestore().runTransaction(async (tx) => {
      const mSnap = await tx.get(mentionRef);
      if (!mSnap.exists) return true;
      if (mSnap.get('processed') === true) return true;
      tx.update(mentionRef, { processed: true });
      return false;
    });
    if (done) return null;

    // ✅ DETERMINAR TIPO DE CONTENIDO Y NAVEGACIÓN
    let contentType = 'contenido';
    let targetType = 'moment';
    let targetId = notification.momentId;

    if (notification.storyId) {
      contentType = 'historia';
      targetType = 'story';
      targetId = notification.storyId;
    } else if (notification.momentId) {
      contentType = 'momento';
      targetType = 'moment';
      targetId = notification.momentId;
    }

    // ✅ Obtener conteos actualizados para el Widget (CON CONTEXTO PARA EVITAR RACE CONDITION)
    const counts = await getUnreadCounts(userId, { type: 'notification', notificationType: 'mention' });

    // Determinar claves de localización
    let titleLocKey = 'notification.mention.title';
    let titleLocArgs = [senderData.username, contentType]; // contentType ya es 'momento', 'historia', etc.
    // Mapear contentType a claves de localización si es necesario, pero ya los definimos en strings base
    // "notification.mention.contentType.moment" = "momento";
    // Podríamos hacer lookup inverso pero por simplicidad usaremos el string directo que coincide con la localizacion
    // Mejor estrategia: enviar la clave del tipo de contenido como argumento
    let contentTypeKey = 'notification.mention.contentType.default';
    if (targetType === 'moment') contentTypeKey = 'notification.mention.contentType.moment';
    if (targetType === 'story') contentTypeKey = 'notification.mention.contentType.story';

    // FCM no soporta anidar loc keys en argumentos fácilmente, así que usaremos el valor traducido en el cliente si fuera posible,
    // pero aquí APNs pide strings.
    // Simplificación: Usar "momento"/"historia" hardcoded en español como fallback o intentar pasar la key.
    // APNs soporta loc-args que son strings. 
    // Vamos a usar una clave genérica y el nombre del usuario.

    const message = {
      token: fcmToken,
      data: {
        type: 'mention',
        senderId: notification.senderId,
        userId: userId,
        targetType: targetType,
        targetId: targetId,
        senderUsername: senderData.username,
        senderProfileImage: senderData.profileImagePath || '',
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags),
      },
      apns: {
        headers: {
          'apns-collapse-id': `mention_${userId}`
        },
        payload: {
          aps: {
            alert: {
              'title-loc-key': 'notification.mention.title',
              'title-loc-args': [senderData.username, contentType], // contentType debe ser localizado en el cliente o enviado como string
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

    try {
      await admin.messaging().send(message);
      console.log(`✅ Notificación de mención enviada: ${senderData.username} -> ${userData.username} en ${contentType}`);
    } catch (error) {
      if (error.code === 'messaging/registration-token-not-registered') {
        await removeInvalidToken(userId, fcmToken);
      }
      throw error;
    }

  } catch (error) {
    console.error('❌ Error sending mention notification:', error);
  }
});

// 🏷️ ETIQUETAS EN FOTOS
exports.onPhotoTagNotification = onDocumentCreated('users/{userId}/notifications/{notificationId}', async (event) => {
  const snap = event.data;
  const { userId, notificationId } = event.params;
  const notification = snap.data();

  // Solo procesar notificaciones de etiquetas en fotos
  if (notification.type !== 'photoTag') return null;

  try {
    const [senderDoc, userDoc] = await Promise.all([
      admin.firestore().doc(`users/${notification.senderId}`).get(),
      admin.firestore().doc(`users/${userId}`).get()
    ]);

    if (!senderDoc.exists || !userDoc.exists) return null;

    const senderData = senderDoc.data();
    const userData = userDoc.data();

    if (!validateUserData(senderData) || !validateUserData(userData)) {
      console.warn('⚠️ Datos de usuario incompletos para etiqueta en foto');
      return null;
    }

    if (!senderData.isActive || !userData.isActive) return null;

    const fcmToken = userData.fcmToken;
    if (!fcmToken) return null;

    const cleanImageUrl = senderData.profileImagePath
      ? senderData.profileImagePath.replace(':443', '')
      : null;

    // ✅ Idempotencia por notificación de etiqueta
    const tagRef = admin.firestore().doc(`users/${userId}/notifications/${notificationId}`);
    const done = await admin.firestore().runTransaction(async (tx) => {
      const tSnap = await tx.get(tagRef);
      if (!tSnap.exists) return true;
      if (tSnap.get('processed') === true) return true;
      tx.update(tagRef, { processed: true });
      return false;
    });
    if (done) return null;

    // ✅ Obtener conteos actualizados para el Widget (CON CONTEXTO PARA EVITAR RACE CONDITION)
    const counts = await getUnreadCounts(userId, { type: 'notification', notificationType: 'photoTag' });

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
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags),
      },
      apns: {
        headers: {
          'apns-collapse-id': `tag_${userId}`
        },
        payload: {
          aps: {
            alert: {
              'title-loc-key': 'notification.photoTag.title',
              'title-loc-args': [senderData.username],
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

    try {
      await admin.messaging().send(message);
      console.log(`✅ Notificación de etiqueta enviada: ${senderData.username} -> ${userData.username}`);
    } catch (error) {
      if (error.code === 'messaging/registration-token-not-registered') {
        await removeInvalidToken(userId, fcmToken);
      }
      throw error;
    }

  } catch (error) {
    console.error('❌ Error sending photo tag notification:', error);
  }
});

// 🔔 ELIMINAR REACCIONES DE MOMENTOS
exports.onMomentReactionRemoved = onDocumentDeleted('users/{userId}/moments/{momentId}/reactions/{reactionId}', async (event) => {
  const snap = event.data;
  const { userId, momentId, reactionId } = event.params;
  const reaction = snap.data();

  try {
    // ✅ Decrementar el contador de reacciones
    const momentRef = admin.firestore().doc(`users/${userId}/moments/${momentId}`);
    await momentRef.update({ reactionCount: admin.firestore.FieldValue.increment(-1) });

    // ✅ ELIMINAR TODAS LAS NOTIFICACIONES EXISTENTES de este momento
    const notificationsSnapshot = await admin.firestore()
      .collection(`users/${userId}/notifications`)
      .where('type', '==', 'reaction') // ✅ CORREGIDO: Buscar notificaciones de tipo 'reaction'
      .where('momentId', '==', momentId)
      .get();

    // Eliminar todas las notificaciones de reacción para este momento
    const deletePromises = notificationsSnapshot.docs.map(doc => doc.ref.delete());
    await Promise.all(deletePromises);

    console.log(`🗑️ Eliminadas ${notificationsSnapshot.size} notificaciones de reacción para momento ${momentId}`);

    // ✅ SI QUEDAN REACCIONES, CREAR NUEVA NOTIFICACIÓN AGRUPADA
    const remainingReactionsSnapshot = await admin.firestore()
      .collection(`users/${userId}/moments/${momentId}/reactions`)
      .get();

    if (remainingReactionsSnapshot.size > 0) {
      // Obtener datos de la primera reacción restante
      const firstReaction = remainingReactionsSnapshot.docs[0].data();
      const reacterDoc = await admin.firestore().doc(`users/${firstReaction.userId}`).get();

      if (reacterDoc.exists) {
        const reacterData = reacterDoc.data();

        // Crear nueva notificación agrupada
        await admin.firestore().collection(`users/${userId}/notifications`).add({
          type: 'reaction', // ✅ CORREGIDO: Para reacciones en momentos
          senderId: firstReaction.userId,
          senderUsername: reacterData.username,
          senderProfileImage: reacterData.profileImagePath || '',
          momentId: momentId,
          reactionCount: remainingReactionsSnapshot.size,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          isPending: true
        });

        console.log(`✅ Nueva notificación agrupada creada para ${remainingReactionsSnapshot.size} reacciones restantes`);
      }
    }

  } catch (error) {
    console.error('❌ Error handling moment reaction removal:', error);
  }
});

// 🔗 STORY CHAINS: Crear entrada de cadena cuando se publica la primera parte
exports.onStoryChainCreated = onDocumentCreated('users/{userId}/stories/{storyId}', async (event) => {
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
exports.onStoryChainContinued = onDocumentCreated('users/{userId}/stories/{storyId}', async (event) => {
  const snap = event.data;
  const { userId, storyId } = event.params;
  const story = snap.data();

  try {
    // Solo procesar si es parte de una cadena y no es la primera parte
    if (!story.chainId || !story.chainPosition || story.chainPosition <= 1) {
      return null;
    }

    // No notificar si el usuario se continúa a sí mismo
    if (story.authorId === userId) {
      return null;
    }

    // Obtener datos del usuario que continuó la cadena y del creador original
    const [continuerDoc, chainCreatorDoc] = await Promise.all([
      admin.firestore().doc(`users/${story.authorId}`).get(),
      admin.firestore().doc(`users/${userId}`).get()
    ]);

    if (!continuerDoc.exists || !chainCreatorDoc.exists) {
      console.warn('⚠️ Documento no encontrado para Story Chain');
      return null;
    }

    const continuerData = continuerDoc.data();
    const chainCreatorData = chainCreatorDoc.data();

    // Validar datos requeridos
    if (!validateUserData(continuerData) || !validateUserData(chainCreatorData)) {
      console.warn('⚠️ Datos de usuario incompletos para Story Chain');
      return null;
    }

    // Verificar que ambas cuentas estén activas
    if (!continuerData.isActive || !chainCreatorData.isActive) {
      return null;
    }

    // Obtener FCM token del creador de la cadena
    const fcmToken = chainCreatorData.fcmToken;
    if (!fcmToken) return null;

    // Limpiar URL de imagen
    const cleanImageUrl = continuerData.profileImagePath
      ? continuerData.profileImagePath.replace(':443', '')
      : null;

    // ✅ Idempotencia por story chain
    const storyRef = admin.firestore().doc(`users/${userId}/stories/${storyId}`);
    const alreadyProcessed = await admin.firestore().runTransaction(async (tx) => {
      const storySnap = await tx.get(storyRef);
      if (!storySnap.exists) return true;
      if (storySnap.get('chainNotificationProcessed') === true) return true;
      tx.update(storyRef, { chainNotificationProcessed: true });
      return false;
    });
    if (alreadyProcessed) return null;

    // Obtener todas las historias de la cadena para contar partes
    const chainStoriesSnapshot = await admin.firestore()
      .collectionGroup('stories')
      .where('chainId', '==', story.chainId)
      .orderBy('chainPosition')
      .get();

    const totalParts = chainStoriesSnapshot.size;

    // Determinar claves de localización
    let titleLocKey, titleLocArgs, bodyLocKey, bodyLocArgs;

    const username = continuerData.username || 'Alguien';
    const chainTitle = story.chainTitle || 'historia';

    if (totalParts === 2) {
      // Segunda parte: mostrar notificación simple de "continuó"
      // Usamos el formato genérico: Usuario añadió la parte 2 a "Título"
      titleLocKey = 'notification.storyChain.single.title';
      titleLocArgs = [username, String(story.chainPosition), chainTitle];
      bodyLocKey = 'notification.storyChain.single.body';
      bodyLocArgs = [];
    } else {
      // Múltiples partes
      titleLocKey = 'notification.storyChain.multiple.title';
      titleLocArgs = [username, String(story.chainPosition), chainTitle];
      bodyLocKey = 'notification.storyChain.multiple.body';
      bodyLocArgs = [String(totalParts)];
    }

    // ✅ Obtener conteos actualizados para el Widget
    const counts = await getUnreadCounts(userId, { type: 'notification', notificationType: 'storyChainContinued' });

    const message = {
      token: fcmToken,
      data: {
        type: 'story_chain_continued',
        chainId: story.chainId,
        storyId: storyId,
        chainTitle: story.chainTitle || '',
        chainPosition: story.chainPosition.toString(),
        totalParts: totalParts.toString(),
        continuerId: story.authorId,
        chainCreatorId: userId,
        targetType: 'story_chain',
        targetId: story.chainId,
        senderUsername: continuerData.username,
        senderProfileImage: continuerData.profileImagePath || '',
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

    try {
      await admin.messaging().send(message);
      console.log(`✅ Notificación de Story Chain enviada: ${username} -> ${chainCreatorData.username} (${story.chainTitle}) - Parte ${story.chainPosition}/${totalParts}`);
    } catch (error) {
      if (error.code === 'messaging/registration-token-not-registered') {
        await removeInvalidToken(userId, fcmToken);
      }
      throw error;
    }

    // Crear notificación en Firestore
    await admin.firestore().collection(`users/${userId}/notifications`).add({
      type: 'storyChainContinued',
      senderId: story.authorId,
      senderUsername: continuerData.username,
      senderProfileImage: continuerData.profileImagePath || '',
      chainId: story.chainId,
      chainTitle: story.chainTitle || '',
      storyId: storyId,
      chainPosition: story.chainPosition,
      totalParts: totalParts,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isPending: true
    });

    // ✅ ACTUALIZAR METADATOS DE LA CADENA
    try {
      const chainRef = admin.firestore().doc(`storyChains/${story.chainId}`);
      await chainRef.set({
        id: story.chainId,
        title: story.chainTitle || '',
        createdBy: userId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        partCount: totalParts,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        lastPartBy: story.authorId,
        lastPartUsername: continuerData.username
      }, { merge: true });

      console.log(`✅ Metadatos de cadena actualizados: ${story.chainId} - ${totalParts} partes`);
    } catch (chainError) {
      console.warn('⚠️ Error actualizando metadatos de cadena:', chainError);
      // No fallar la notificación por esto
    }

  } catch (error) {
    console.error('❌ Error sending story chain notification:', error);
  }
});

// 🌊 ECHOES: Notificación cuando se detecta un posible Echo (Nova Spark)
exports.onEchoCreated = onDocumentCreated('echoes/{echoId}', async (event) => {
  const snap = event.data;
  const { echoId } = event.params;
  const echo = snap.data();

  if (!echo) return null;

  try {
    const participants = echo.participants || [];
    const hostId = echo.hostId;
    const recipients = participants.filter(p => p.userId !== hostId);

    if (recipients.length === 0) return null;

    console.log(`🌊 Procesando nuevo Echo: ${echoId} con ${recipients.length} participantes`);

    // Obtener datos del host para personalizar la notificación
    const hostDoc = await admin.firestore().doc(`users/${hostId}`).get();
    const hostData = hostDoc.exists ? hostDoc.data() : { username: 'Alguien' };

    const notificationPromises = recipients.map(async (participant) => {
      const recipientId = participant.userId;

      // 1. Obtener token del destinatario
      const userDoc = await admin.firestore().doc(`users/${recipientId}`).get();
      if (!userDoc.exists) return null;

      const userData = userDoc.data();
      if (!validateUserData(userData) || !userData.fcmToken) return null;

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
              alert: {
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

      try {
        await admin.messaging().send(message);
      } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
          await removeInvalidToken(recipientId, userData.fcmToken);
        }
        console.error(`❌ Error enviando FCM de Echo a ${recipientId}:`, error);
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
exports.optOutBestFriends = onRequest(
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
