const { onDocumentCreated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { setGlobalOptions } = require('firebase-functions/v2');
setGlobalOptions({ region: 'europe-southwest1', memory: '256MiB', concurrency: 80, retry: true });
const admin = require('firebase-admin');
admin.initializeApp();

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
    let notificationTitle;
    let notificationBody;
    
    // ✅ VALIDAR que username existe y no sea undefined
    const username = reacterData.username || 'Alguien';
    const reactionCount = Math.max(1, newReactionCount); // ✅ Evitar números negativos
    
    if (reactionCount === 1) {
      // Primera reacción: mostrar usuario específico
      notificationTitle = `${username} reaccionó ${emoji} a tu momento`;
      notificationBody = 'Toca para ver tu momento';
    } else {
      // Múltiples reacciones: mostrar conteo
      notificationTitle = `${username} y ${reactionCount - 1} más reaccionaron a tu momento`;
      notificationBody = `${reactionCount} reacciones en total`;
    }
    
    const message = {
      token: fcmToken,
      notification: {
        title: notificationTitle,
        body: notificationBody,
        image: cleanImageUrl
      },
      data: {
        type: 'moment_reaction', // ✅ SIEMPRE el mismo tipo
        momentId: momentId,
        userId: reaction.userId,
        reactionType: reaction.reactionType,
        momentOwnerId: userId,
        targetType: 'moment',
        targetId: momentId,
        senderUsername: reacterData.username,
        senderProfileImage: reacterData.profileImagePath || '',
        reactionCount: String(newReactionCount)
      },
      apns: {
        payload: {
          aps: {
            badge: 1,
            sound: 'default',
            'mutable-content': 1,
            // ✅ CLAVE: Thread-ID para agrupación nativa iOS
            'thread-id': `moment_reactions_${momentId}`,
            // ✅ NUEVO: Summary args para agrupación inteligente
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
            'content-available': 1,
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
    
    const message = {
      token: fcmToken,
      notification: {
        title: `${commenterData.username} comentó tu momento`,
        body: `"${commentPreview}"`,
        image: cleanImageUrl
      },
      data: {
        type: 'moment_comment',
        momentId: momentId,
        commentId: commentId,
        userId: comment.authorId,
        momentOwnerId: userId,
        targetType: 'moment',
        targetId: momentId,
        senderUsername: commenterData.username,
        senderProfileImage: commenterData.profileImagePath || ''
      },
      apns: {
        payload: {
          aps: {
            badge: 1,
            sound: 'default',
            'mutable-content': 1,
            'thread-id': `moment_comments_${momentId}` // ✅ Agrupación para comentarios
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
      notificationTitle = `${followerData.username} comenzó a seguirte`;
      notificationBody = 'Toca para ver su perfil';
      notificationType = 'newFollower';
      
      // ✅ ENVIAR NOTIFICACIÓN NORMAL
      const message = {
        token: fcmToken,
        notification: {
          title: notificationTitle,
          body: notificationBody,
          image: cleanImageUrl
        },
        data: {
          type: 'new_follower',
          followerId: followerId,
          userId: userId,
          targetType: 'profile',
          targetId: followerId,
          senderUsername: followerData.username,
          senderProfileImage: followerData.profileImagePath || ''
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: 'default',
              'mutable-content': 1,
              'thread-id': `new_followers_${userId}` // ✅ Agrupación para seguidores
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
      console.warn('⚠️ Datos de sender incompletos para mensaje');
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
      if (!receiverDoc.exists) return null;
      const receiverData = receiverDoc.data();
      const receiverId = receiverDoc.id;
      
      if (!validateUserData(receiverData)) {
        console.warn('⚠️ Datos de receiver incompletos para mensaje');
        return null;
      }
      
      if (!receiverData.isActive || !receiverData.fcmToken) return null;
      
      // ✅ VERIFICAR SI LA CONVERSACIÓN ESTÁ SILENCIADA PARA ESTE USUARIO
      if (conversationData.isMuted === true) {
        console.log(`🔇 Conversación ${conversationId} silenciada para ${receiverId}, saltando notificación`);
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
      
      const notificationMessage = {
        token: receiverData.fcmToken,
        notification: {
          title: notificationTitle,
          body: notificationBody,
          image: cleanImageUrl
        },
        data: {
          type: 'new_message',
          conversationId: conversationId,
          messageId: messageId,
          senderId: message.senderId,
          targetType: 'conversation',
          targetId: conversationId,
          senderUsername: senderData.username,
          senderProfileImage: senderData.profileImagePath || ''
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: 'default',
              'mutable-content': 1,
              'thread-id': `conversation_${conversationId}` // ✅ Agrupación por conversación
            }
          }
        }
      };
      
      try {
        await admin.messaging().send(notificationMessage);
        console.log(`✅ Notificación de mensaje enviada: ${senderData.username} -> ${receiverData.username} (${message.type})`);
        console.log(`🔔 Conversación ${conversationId} NO silenciada, notificación enviada`);
      } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
          await removeInvalidToken(receiverId, receiverData.fcmToken);
        }
        throw error;
      }
    });
    
    await Promise.all(notifications);
    
  } catch (error) {
    console.error('❌ Error sending message notification:', error);
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
    
    const message = {
      token: fcmToken,
      notification: {
        title: `${reacterData.username} reaccionó a tu historia con ${emoji}`,
        body: 'Toca para ver quién vio tu historia',
        image: cleanImageUrl
      },
      data: {
        type: 'story_reaction',
        storyId: storyId,
        userId: reaction.userId,
        reaction: reaction.reaction,
        storyOwnerId: userId,
        targetType: 'notification',
        targetId: storyId,
        senderUsername: reacterData.username,
        senderProfileImage: reacterData.profileImagePath || ''
      },
      apns: {
        payload: {
          aps: {
            badge: 1,
            sound: 'default',
            'mutable-content': 1,
            'thread-id': `story_reactions_${storyId}` // ✅ Agrupación por historia
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
    
    const message = {
      token: fcmToken,
      notification: {
        title: `${requesterData.username} quiere seguirte`,
        body: 'Toca para aceptar o rechazar la solicitud',
        image: cleanImageUrl
      },
      data: {
        type: 'follow_request',
        requestId: requestId,
        senderId: request.senderId,
        userId: userId,
        targetType: 'follow_requests',
        targetId: requestId,
        senderUsername: requesterData.username,
        senderProfileImage: requesterData.profileImagePath || ''
      },
      apns: {
        payload: {
          aps: {
            badge: 1,
            sound: 'default',
            'mutable-content': 1,
            'thread-id': `follow_requests_${userId}` // ✅ Agrupación para solicitudes
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
    
    const message = {
      token: fcmToken,
      notification: {
        title: `${senderData.username} te mencionó en una ${contentType}`,
        body: 'Toca para ver el contenido',
        image: cleanImageUrl
      },
      data: {
        type: 'mention',
        senderId: notification.senderId,
        userId: userId,
        targetType: targetType,
        targetId: targetId,
        senderUsername: senderData.username,
        senderProfileImage: senderData.profileImagePath || ''
      },
      apns: {
        payload: {
          aps: {
            badge: 1,
            sound: 'default',
            'mutable-content': 1,
            'thread-id': `mentions_${userId}` // ✅ Agrupación para menciones
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
    
    // ✅ TÍTULO DINÁMICO basado en número de partes
    let notificationTitle, notificationBody;
    
    const username = continuerData.username || 'Alguien';
    const chainTitle = story.chainTitle || 'historia';
    
    if (totalParts === 2) {
      // Segunda parte: mostrar usuario específico
      notificationTitle = `${username} continuó tu cadena "${chainTitle}"`;
      notificationBody = 'Toca para ver la nueva parte';
    } else {
      // Múltiples partes: mostrar conteo
      notificationTitle = `${username} agregó la parte ${story.chainPosition} a "${chainTitle}"`;
      notificationBody = `${totalParts} partes en total`;
    }
    
    const message = {
      token: fcmToken,
      notification: {
        title: notificationTitle,
        body: notificationBody,
        image: cleanImageUrl
      },
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
        senderProfileImage: continuerData.profileImagePath || ''
      },
      apns: {
        payload: {
          aps: {
            badge: 1,
            sound: 'default',
            'mutable-content': 1,
            // ✅ CLAVE: Thread-ID para agrupación nativa iOS
            'thread-id': `story_chain_${story.chainId}`,
            // ✅ NUEVO: Summary args para agrupación inteligente
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