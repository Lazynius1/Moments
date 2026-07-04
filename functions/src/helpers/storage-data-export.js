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
  archiver,
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

function toSerializable(value) {
  if (value === null || value === undefined) return null;
  if (value instanceof admin.firestore.Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (value instanceof admin.firestore.GeoPoint) {
    return { latitude: value.latitude, longitude: value.longitude };
  }
  if (Array.isArray(value)) return value.map(toSerializable);
  if (typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = toSerializable(v);
    return out;
  }
  return value;
}

async function fetchUserSubcollection(userId, name) {
  const snap = await admin.firestore()
    .collection('users')
    .doc(userId)
    .collection(name)
    .get();
  return snap.docs.map((doc) => ({ documentId: doc.id, ...toSerializable(doc.data()) }));
}

async function fetchUserComments(userId) {
  const snap = await admin.firestore()
    .collectionGroup('comments')
    .where('authorId', '==', userId)
    .get();

  return snap.docs.map((doc) => {
    const momentRef = doc.ref.parent.parent;
    const momentAuthorRef = momentRef ? momentRef.parent.parent : null;
    return {
      documentId: doc.id,
      momentId: momentRef ? momentRef.id : null,
      momentAuthorId: momentAuthorRef ? momentAuthorRef.id : null,
      ...toSerializable(doc.data())
    };
  });
}

async function fetchUserReactions(userId) {
  const snap = await admin.firestore()
    .collectionGroup('reactions')
    .where('userId', '==', userId)
    .get();

  return snap.docs.map((doc) => {
    const contentRef = doc.ref.parent.parent;
    const authorRef = contentRef ? contentRef.parent.parent : null;
    const contentType = contentRef ? contentRef.parent.id : null;
    return {
      documentId: doc.id,
      contentType,
      contentId: contentRef ? contentRef.id : null,
      contentAuthorId: authorRef ? authorRef.id : null,
      ...toSerializable(doc.data())
    };
  });
}

function aesGcmOpenCombinedBase64(base64Combined, keyBuffer) {
  if (typeof base64Combined !== 'string' || !keyBuffer) return null;
  const combined = Buffer.from(base64Combined, 'base64');
  if (combined.length < 12 + 16 || keyBuffer.length !== 32) return null;
  const iv = combined.subarray(0, 12);
  const tag = combined.subarray(combined.length - 16);
  const ciphertext = combined.subarray(12, combined.length - 16);
  const decipher = crypto.createDecipheriv('aes-256-gcm', keyBuffer, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
}

function derivePinKey(pin, saltBase64, iterations, keyLength) {
  const salt = Buffer.from(saltBase64, 'base64');
  return crypto.pbkdf2Sync(Buffer.from(pin, 'utf8'), salt, iterations, keyLength, 'sha256');
}

const EXPORT_PIN_MAX_ATTEMPTS = 5;
const EXPORT_PIN_LOCKOUT_MS = 5 * 60 * 1000;

async function checkAndRegisterPinAttempt(userId, mode) {
  const stateRef = admin.firestore().collection('users').doc(userId).collection('chatRecovery').doc('exportPinState');
  const stateSnap = await stateRef.get();
  const state = stateSnap.data() || {};

  const lockedUntilMs = state.lockedUntil ? state.lockedUntil.toMillis() : 0;
  if (lockedUntilMs > Date.now()) {
    return { locked: true, remainingMs: lockedUntilMs - Date.now() };
  }

  if (mode === 'success') {
    await stateRef.set({ failedAttempts: 0, lockedUntil: admin.firestore.FieldValue.delete() }, { merge: true });
    return { locked: false };
  }

  if (mode === 'fail') {
    const failedAttempts = (state.failedAttempts || 0) + 1;
    if (failedAttempts >= EXPORT_PIN_MAX_ATTEMPTS) {
      await stateRef.set({
        failedAttempts: 0,
        lockedUntil: admin.firestore.Timestamp.fromMillis(Date.now() + EXPORT_PIN_LOCKOUT_MS)
      }, { merge: true });
    } else {
      await stateRef.set({ failedAttempts }, { merge: true });
    }
  }

  return { locked: false };
}

async function unwrapRecoveryBundle(userId, pin) {
  if (typeof pin !== 'string' || !/^\d{6}$/.test(pin.trim())) return null;
  const trimmedPin = pin.trim();

  const lockState = await checkAndRegisterPinAttempt(userId, 'check');
  if (lockState.locked) return null;

  const bundleSnap = await admin.firestore()
    .collection('users').doc(userId).collection('chatRecovery').doc('default').get();
  const bundle = bundleSnap.data();
  if (!bundle || !bundle.encryptedPrivateKey || !bundle.salt || !bundle.kdfParams) return null;

  const iterations = bundle.kdfParams.iterations || 200000;
  const keyLength = bundle.kdfParams.keyLength || 32;
  const pinKey = derivePinKey(trimmedPin, bundle.salt, iterations, keyLength);

  let chatPrivateKeyBuffer = null;
  try {
    chatPrivateKeyBuffer = aesGcmOpenCombinedBase64(bundle.encryptedPrivateKey, pinKey);
  } catch (error) {
    chatPrivateKeyBuffer = null;
  }
  if (!chatPrivateKeyBuffer || chatPrivateKeyBuffer.length !== 32) {
    await checkAndRegisterPinAttempt(userId, 'fail');
    return null;
  }

  await checkAndRegisterPinAttempt(userId, 'success');

  let novaUserKeyBuffer = null;
  if (bundle.encryptedUserKey) {
    try {
      novaUserKeyBuffer = aesGcmOpenCombinedBase64(bundle.encryptedUserKey, pinKey);
      if (novaUserKeyBuffer && novaUserKeyBuffer.length !== 32) novaUserKeyBuffer = null;
    } catch (error) {
      novaUserKeyBuffer = null;
    }
  }

  return { chatPrivateKeyBuffer, novaUserKeyBuffer };
}

const X25519_PKCS8_PREFIX = Buffer.from('302e020100300506032b656e04220420', 'hex');

function x25519SharedSecret(privateKeyRaw32, publicKeyRaw32) {
  const der = Buffer.concat([X25519_PKCS8_PREFIX, privateKeyRaw32]);
  const privateKey = crypto.createPrivateKey({ key: der, format: 'der', type: 'pkcs8' });
  const publicKey = crypto.createPublicKey({
    key: { kty: 'OKP', crv: 'X25519', x: publicKeyRaw32.toString('base64url') },
    format: 'jwk'
  });
  return crypto.diffieHellman({ privateKey, publicKey });
}

function unwrapConversationKeyForUser(wrappedKeyMap, chatPrivateKeyBuffer) {
  if (!wrappedKeyMap || !chatPrivateKeyBuffer) return null;
  try {
    const senderPublicKey = Buffer.from(wrappedKeyMap.senderPublicKey, 'base64');
    const sharedSecret = x25519SharedSecret(chatPrivateKeyBuffer, senderPublicKey);
    const wrappingKey = Buffer.from(
      crypto.hkdfSync('sha256', sharedSecret, Buffer.alloc(0), Buffer.from('moments.chat.wrap.v1', 'utf8'), 32)
    );
    const conversationKey = aesGcmOpenCombinedBase64(wrappedKeyMap.wrappedKey, wrappingKey);
    return conversationKey ? conversationKey.toString('base64') : null;
  } catch (error) {
    return null;
  }
}

async function fetchUserConversations(userId, chatPrivateKeyBuffer) {
  const conversationsSnap = await admin.firestore()
    .collection('conversations')
    .where('participants', 'array-contains', userId)
    .get();

  const conversations = [];
  for (const convoDoc of conversationsSnap.docs) {
    const conversationId = convoDoc.id;
    const conversationData = convoDoc.data() || {};
    const sharedKey = await fetchConversationSharedKey(conversationId, conversationData, userId, chatPrivateKeyBuffer);
    const messagesSnap = await admin.firestore()
      .collection('conversations')
      .doc(conversationId)
      .collection('messages')
      .orderBy('timestamp')
      .get();

    const messages = messagesSnap.docs.map((msgDoc) => {
      const rawMessage = msgDoc.data() || {};
      const serializedMessage = {
        messageId: msgDoc.id,
        ...toSerializable(rawMessage)
      };
      if (typeof rawMessage.content === 'string' && rawMessage.content.trim().length > 0) {
        const decrypted = decryptChatContent(rawMessage.content, sharedKey);
        serializedMessage.contentDecrypted = decrypted;
        if (rawMessage.type === 'location') {
          serializedMessage.locationDecrypted = decodeLocationPayload(decrypted);
        }
      }
      return serializedMessage;
    });

    const conversation = {
      conversationId,
      ...toSerializable(conversationData),
      messages
    };
    Object.defineProperty(conversation, '_conversationKey', {
      value: sharedKey,
      enumerable: false
    });
    conversations.push(conversation);
  }
  return conversations;
}

async function fetchConversationSharedKey(conversationId, conversationData, userId, chatPrivateKeyBuffer) {
  if (typeof conversationData.sharedEncryptionKey === 'string' && conversationData.sharedEncryptionKey.length > 0) {
    return conversationData.sharedEncryptionKey;
  }
  if (typeof conversationData.encryptionKey === 'string' && conversationData.encryptionKey.length > 0) {
    return conversationData.encryptionKey;
  }
  if (
    chatPrivateKeyBuffer
    && conversationData.wrappedKeys
    && typeof conversationData.wrappedKeys === 'object'
    && conversationData.wrappedKeys[userId]
  ) {
    const unwrapped = unwrapConversationKeyForUser(conversationData.wrappedKeys[userId], chatPrivateKeyBuffer);
    if (unwrapped) return unwrapped;
  }
  try {
    const sharedDoc = await admin.firestore()
      .collection('conversations')
      .doc(conversationId)
      .collection('encryption')
      .doc('shared_key')
      .get();
    const data = sharedDoc.data() || {};
    if (typeof data.encryptionKey === 'string' && data.encryptionKey.length > 0) {
      return data.encryptionKey;
    }
  } catch (error) {
    // Best-effort fallback only.
  }
  return null;
}

function decryptChatContent(encryptedContent, keyBase64) {
  if (!encryptedContent || !keyBase64) return null;
  try {
    const combined = Buffer.from(encryptedContent, 'base64');
    const key = Buffer.from(keyBase64, 'base64');
    if (combined.length < 12 + 16 || key.length !== 32) return null;
    const iv = combined.subarray(0, 12);
    const tag = combined.subarray(combined.length - 16);
    const ciphertext = combined.subarray(12, combined.length - 16);
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAuthTag(tag);
    const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
    return decrypted.toString('utf8');
  } catch (error) {
    return null;
  }
}

function decodeLocationPayload(decryptedContentJson) {
  if (typeof decryptedContentJson !== 'string' || !decryptedContentJson.trim()) return null;
  try {
    const parsed = JSON.parse(decryptedContentJson);
    if (typeof parsed.lat !== 'number' || typeof parsed.lng !== 'number') return null;
    return {
      latitude: parsed.lat,
      longitude: parsed.lng,
      name: typeof parsed.name === 'string' ? parsed.name : null,
      address: typeof parsed.address === 'string' ? parsed.address : null
    };
  } catch (error) {
    return null;
  }
}

function deriveChatMediaKey(conversationKeyBuffer, conversationId, messageId, purpose) {
  const salt = Buffer.from('moments.chat.media.salt.v1', 'utf8');
  const info = Buffer.from(`moments.chat.media.v1|${conversationId}|${messageId}|${purpose}`, 'utf8');
  return Buffer.from(crypto.hkdfSync('sha256', conversationKeyBuffer, salt, info, 32));
}

function chatMediaAuthenticatedData(conversationId, messageId, purpose, contentType) {
  return Buffer.from(`moments.chat.media.aad.v1|${conversationId}|${messageId}|${purpose}|${contentType}`, 'utf8');
}

function decryptChatMediaBuffer(encryptedBuffer, metadata, conversationKeyBase64, conversationId, messageId) {
  if (!encryptedBuffer || !metadata || !conversationKeyBase64) return null;
  try {
    const conversationKeyBuffer = Buffer.from(conversationKeyBase64, 'base64');
    if (conversationKeyBuffer.length !== 32) return null;

    const mediaKey = deriveChatMediaKey(conversationKeyBuffer, conversationId, messageId, metadata.purpose);
    const aad = chatMediaAuthenticatedData(conversationId, messageId, metadata.purpose, metadata.contentType);

    if (encryptedBuffer.length < 12 + 16) return null;
    const iv = encryptedBuffer.subarray(0, 12);
    const tag = encryptedBuffer.subarray(encryptedBuffer.length - 16);
    const ciphertext = encryptedBuffer.subarray(12, encryptedBuffer.length - 16);

    const decipher = crypto.createDecipheriv('aes-256-gcm', mediaKey, iv);
    decipher.setAuthTag(tag);
    decipher.setAAD(aad);
    return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  } catch (error) {
    return null;
  }
}

async function fetchNovaConversations(userId, novaUserKeyBuffer) {
  const [newSnap, titlesSnap, conversationsSnap] = await Promise.all([
    admin.firestore()
      .collection('users')
      .doc(userId)
      .collection('novaConversations')
      .orderBy('lastUpdated', 'desc')
      .get(),
    admin.firestore()
      .collection('geminiConversationTitles')
      .where('userId', '==', userId)
      .orderBy('lastUpdated', 'desc')
      .get(),
    admin.firestore()
      .collection('geminiConversations')
      .where('userId', '==', userId)
      .orderBy('lastUpdated', 'desc')
      .get()
  ]);

  const novaKeyBase64 = novaUserKeyBuffer ? novaUserKeyBuffer.toString('base64') : null;

  const decorateWithDecryptedTitle = (item) => {
    if (novaKeyBase64 && typeof item.title === 'string' && item.title.trim().length > 0) {
      item.titleDecrypted = decryptChatContent(item.title, novaKeyBase64);
    }
    return item;
  };

  const decorateConversation = (item) => {
    decorateWithDecryptedTitle(item);
    if (Array.isArray(item.messages)) {
      item.messages = item.messages.map((message) => {
        if (novaKeyBase64 && typeof message.text === 'string' && message.text.trim().length > 0) {
          message.textDecrypted = decryptChatContent(message.text, novaKeyBase64);
        }
        return message;
      });
    }
    return item;
  };

  const newConversations = newSnap.docs
    .map((doc) => ({ conversationId: doc.id, ...toSerializable(doc.data()) }))
    .map(decorateConversation);
  const newIds = new Set(newConversations.map((conversation) => conversation.conversationId));

  const legacyConversations = conversationsSnap.docs
    .map((doc) => ({ conversationId: doc.id, ...toSerializable(doc.data()) }))
    .filter((conversation) => !newIds.has(conversation.conversationId))
    .map(decorateConversation);

  const titles = titlesSnap.docs
    .map((doc) => ({ conversationId: doc.id, ...toSerializable(doc.data()) }))
    .map(decorateWithDecryptedTitle);

  return {
    titles,
    conversations: [...newConversations, ...legacyConversations]
  };
}

function sanitizeFileName(value) {
  return String(value || 'file').replace(/[\/\\?%*:|"<>]/g, '_');
}

function inferFileExtension(url, contentType = '') {
  const ct = String(contentType || '').toLowerCase();
  if (ct.includes('image/jpeg')) return 'jpg';
  if (ct.includes('image/png')) return 'png';
  if (ct.includes('image/webp')) return 'webp';
  if (ct.includes('image/gif')) return 'gif';
  if (ct.includes('video/mp4')) return 'mp4';
  if (ct.includes('video/quicktime')) return 'mov';
  if (ct.includes('audio/mp4') || ct.includes('audio/x-m4a') || ct.includes('audio/m4a')) return 'm4a';
  if (ct.includes('audio/aac')) return 'aac';
  if (ct.includes('audio/mpeg')) return 'mp3';
  try {
    const pathname = new URL(url).pathname;
    const ext = path.extname(pathname).replace('.', '').toLowerCase();
    if (ext && ext.length <= 5) return ext;
  } catch (error) {
    // Ignore and fallback.
  }
  return 'bin';
}

function runFfmpeg(args) {
  return new Promise((resolve, reject) => {
    if (!ffmpegPath) {
      reject(new Error('ffmpeg binary is not available'));
      return;
    }

    const process = spawn(ffmpegPath, args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let stderr = '';

    process.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    process.on('error', reject);
    process.on('close', (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`ffmpeg exited with code ${code}: ${stderr.slice(-1200)}`));
      }
    });
  });
}

function firebaseStorageDownloadUrl(bucketName, objectName, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(objectName)}?alt=media&token=${token}`;
}

function storageProjectIdFromBucketName(bucketName) {
  const value = String(bucketName || '').trim();
  if (!value) return '';
  if (value.endsWith('.firebasestorage.app')) {
    return value.slice(0, -'.firebasestorage.app'.length);
  }
  if (value.endsWith('.appspot.com')) {
    return value.slice(0, -'.appspot.com'.length);
  }
  return value;
}

function storageBucketsAreEquivalent(left, right) {
  const projectA = storageProjectIdFromBucketName(left);
  const projectB = storageProjectIdFromBucketName(right);
  return Boolean(projectA) && projectA === projectB;
}

function sanitizeStorageSegment(value) {
  return String(value || '')
    .trim()
    .split('')
    .map((ch) => (/[a-zA-Z0-9\-_]/.test(ch) ? ch : '_'))
    .join('');
}

function storageObjectNameFromFirebaseUrl(url, expectedBucketName) {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' || parsed.hostname !== 'firebasestorage.googleapis.com') return null;

    const match = parsed.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
    if (!match) return null;

    const bucketName = decodeURIComponent(match[1]);
    if (!storageBucketsAreEquivalent(bucketName, expectedBucketName)) return null;

    return decodeURIComponent(match[2]);
  } catch (error) {
    return null;
  }
}

function resolveStorageObjectNameFromClientMediaReference(mediaReference, bucket) {
  const bucketName = bucket?.name || '';
  if (!bucketName) return null;

  const fromUrl = storageObjectNameFromFirebaseUrl(mediaReference, bucketName);
  if (fromUrl) return fromUrl;

  return storageObjectNameFromTrustedValue(mediaReference, bucketName);
}

function userOwnedPublishableMediaObjectNameFromFirebaseUrl(
  url,
  userId,
  allowedExtensions,
  { contentType = '', contentId = '', mediaItemId = '', requireContentBinding = false } = {}
) {
  const bucket = admin.storage().bucket();
  const objectName = resolveStorageObjectNameFromClientMediaReference(url, bucket);
  if (!objectName || !userId) return null;

  const safeUid = sanitizeStorageSegment(userId);
  if (!safeUid) return null;

  const parts = objectName.split('/');
  if (parts.length !== 6 || parts[0] !== 'users' || sanitizeStorageSegment(parts[1]) !== safeUid || parts[4] !== 'media') {
    return null;
  }

  const collection = parts[2];
  if (!['moments', 'stories'].includes(collection)) return null;

  const fileName = parts[5];
  const extension = path.posix.extname(fileName).slice(1).toLowerCase();
  if (!extension || !allowedExtensions.has(extension)) return null;

  if (requireContentBinding) {
    const expectedCollection = contentType === 'moment' ? 'moments' : contentType === 'story' ? 'stories' : '';
    const expectedContentId = sanitizeStorageSegment(contentId);
    if (!expectedCollection || !expectedContentId) return null;
    if (collection !== expectedCollection || sanitizeStorageSegment(parts[3]) !== expectedContentId) return null;

    const expectedMediaItemId = sanitizeStorageSegment(mediaItemId);
    if (expectedMediaItemId) {
      const fileBase = path.posix.basename(fileName, path.posix.extname(fileName));
      if (sanitizeStorageSegment(fileBase) !== expectedMediaItemId) return null;
    }
  }

  return objectName;
}

function hiddenLayerIdFromMediaItemId(mediaItemId) {
  const value = String(mediaItemId || '').trim();
  const prefix = 'hiddenLayer_';
  if (!value.startsWith(prefix) || value.length <= prefix.length) return '';
  return value.slice(prefix.length);
}

function userOwnedHiddenLayerImageObjectNameFromFirebaseUrl(url, userId, { contentType = '', contentId = '', mediaItemId = '' } = {}) {
  const bucket = admin.storage().bucket();
  const objectName = resolveStorageObjectNameFromClientMediaReference(url, bucket);
  if (!objectName || !userId) return null;

  const safeUid = sanitizeStorageSegment(userId);
  const expectedMomentId = sanitizeStorageSegment(contentId);
  const expectedLayerId = sanitizeStorageSegment(hiddenLayerIdFromMediaItemId(mediaItemId));
  if (!safeUid || contentType !== 'moment' || !expectedMomentId || !expectedLayerId) return null;

  const parts = objectName.split('/');
  if (
    parts.length !== 7 ||
    parts[0] !== 'users' ||
    sanitizeStorageSegment(parts[1]) !== safeUid ||
    parts[2] !== 'moments' ||
    sanitizeStorageSegment(parts[3]) !== expectedMomentId ||
    parts[4] !== 'hidden_layers' ||
    sanitizeStorageSegment(parts[5]) !== expectedLayerId
  ) {
    return null;
  }

  const fileName = parts[6];
  const extension = path.posix.extname(fileName).slice(1).toLowerCase();
  if (path.posix.basename(fileName, path.posix.extname(fileName)) !== 'media') return null;
  if (!extension || !PUBLISHABLE_IMAGE_EXTENSIONS.has(extension)) return null;

  return objectName;
}

function userOwnedImageObjectNameFromFirebaseUrl(url, userId, expectedContent = {}) {
  return (
    userOwnedPublishableMediaObjectNameFromFirebaseUrl(url, userId, PUBLISHABLE_IMAGE_EXTENSIONS, {
      ...expectedContent,
      requireContentBinding: true
    }) || userOwnedHiddenLayerImageObjectNameFromFirebaseUrl(url, userId, expectedContent)
  );
}

function userOwnedVideoObjectNameFromFirebaseUrl(url, userId) {
  const objectName = userOwnedPublishableMediaObjectNameFromFirebaseUrl(url, userId, new Set(['mp4']));
  if (objectName) return objectName;

  const bucket = admin.storage().bucket();
  const legacyObjectName = resolveStorageObjectNameFromClientMediaReference(url, bucket);
  if (!legacyObjectName || !userId) return null;

  const safeUid = String(userId).trim();
  if (!safeUid) return null;

  // Legacy layout: videos/{uuid}_{uid}.mp4
  if (!legacyObjectName.startsWith('videos/')) return null;

  const expectedSuffix = `_${safeUid}.mp4`;
  if (path.posix.dirname(legacyObjectName) !== 'videos' || !path.posix.basename(legacyObjectName).endsWith(expectedSuffix)) {
    return null;
  }

  return legacyObjectName;
}

async function downloadStorageObjectToFile({ bucket, objectName, destinationPath, maxBytes = VIDEO_DOWNLOAD_MAX_BYTES }) {
  const file = bucket.file(objectName);
  const [metadata] = await file.getMetadata();
  const size = Number(metadata.size || 0);
  if (size > maxBytes) {
    throw new Error('Video download exceeds maximum allowed size');
  }

  const contentType = String(metadata.contentType || '').toLowerCase();
  if (contentType && !contentType.startsWith('video/')) {
    throw new Error('Storage object is not a video');
  }

  await new Promise((resolve, reject) => {
    let settled = false;
    let receivedBytes = 0;
    const readStream = file.createReadStream();
    const writeStream = fs.createWriteStream(destinationPath);
    const timeout = setTimeout(() => {
      readStream.destroy(new Error('Video download timed out'));
      writeStream.destroy();
    }, VIDEO_DOWNLOAD_TIMEOUT_MS);

    const done = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (error) {
        try {
          if (fs.existsSync(destinationPath)) fs.unlinkSync(destinationPath);
        } catch (cleanupError) {
          console.warn('Video download cleanup failed', destinationPath, cleanupError.message);
        }
        reject(error);
      } else {
        resolve();
      }
    };

    readStream.on('data', (chunk) => {
      receivedBytes += chunk.length;
      if (receivedBytes > maxBytes) {
        readStream.destroy(new Error('Video download exceeds maximum allowed size'));
        writeStream.destroy();
      }
    });
    readStream.on('error', done);
    writeStream.on('error', done);
    writeStream.on('finish', () => writeStream.close(() => done()));
    readStream.pipe(writeStream);
  });
}


async function deleteOriginalMomentVideoIfSafe({ originalUrl, processedUrl, userId }) {
  const bucket = admin.storage().bucket();
  const objectName = userOwnedVideoObjectNameFromFirebaseUrl(originalUrl, userId);
  const processedObjectName = storageObjectNameFromFirebaseUrl(processedUrl, bucket.name);

  if (!objectName || objectName === processedObjectName) return false;

  try {
    await bucket.file(objectName).delete({ ignoreNotFound: true });
    return true;
  } catch (error) {
    console.warn('Could not delete original moment video after processing', objectName, error.message);
    return false;
  }
}

async function deleteStorageUrlIfSafe({ url, userId }) {
  const bucket = admin.storage().bucket();
  const objectName = userOwnedVideoObjectNameFromFirebaseUrl(url, userId);

  if (!objectName) return false;

  await bucket.file(objectName).delete({ ignoreNotFound: true });
  return true;
}

async function uploadStorageFile({ bucket, localPath, objectName, contentType, extraMetadata = {} }) {
  const token = crypto.randomUUID();
  await bucket.upload(localPath, {
    destination: objectName,
    metadata: {
      contentType,
      metadata: {
        firebaseStorageDownloadTokens: token,
        ...extraMetadata
      }
    }
  });
  return firebaseStorageDownloadUrl(bucket.name, objectName, token);
}

async function transcodeMomentVideo({ userId, momentId, mediaItem }) {
  const bucket = admin.storage().bucket();
  const tempBase = path.join(os.tmpdir(), `moment_video_${momentId}_${mediaItem.id}_${Date.now()}`);
  const inputPath = `${tempBase}_input`;
  const sourceUrl = mediaItem.originalVideoUrl || mediaItem.url;
  const variantSpecs = [
    { key: 'low', max: 640, crf: '28' },
    { key: 'medium', max: 960, crf: '25' },
    { key: 'high', max: 1280, crf: '23' }
  ];
  const cleanupPaths = [inputPath];

  try {
    const sourceObjectName = userOwnedVideoObjectNameFromFirebaseUrl(sourceUrl, userId);
    if (!sourceObjectName) {
      throw new Error('Video source must be a Firebase Storage upload owned by this user');
    }
    await downloadStorageObjectToFile({ bucket, objectName: sourceObjectName, destinationPath: inputPath });

    const videoVariants = {};
    for (const spec of variantSpecs) {
      const outputPath = `${tempBase}_${spec.key}.mp4`;
      cleanupPaths.push(outputPath);
      await runFfmpeg([
        '-y',
        '-i', inputPath,
        '-vf', `scale=${spec.max}:${spec.max}:force_original_aspect_ratio=decrease,format=yuv420p`,
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-crf', spec.crf,
        '-c:a', 'aac',
        '-b:a', spec.key === 'low' ? '96k' : '128k',
        '-movflags', '+faststart',
        outputPath
      ]);

      const objectName = `processed_videos/moments/${userId}/${momentId}/${mediaItem.id}_${spec.key}.mp4`;
      videoVariants[spec.key] = await uploadStorageFile({
        bucket,
        localPath: outputPath,
        objectName,
        contentType: 'video/mp4',
        extraMetadata: {
          sourceMomentId: momentId,
          sourceMediaItemId: mediaItem.id,
          processedBy: 'processMomentVideos',
          variant: spec.key
        }
      });
    }

    const highPath = `${tempBase}_high.mp4`;
    const fileSize = fs.existsSync(highPath) ? fs.statSync(highPath).size : 0;
    return {
      url: videoVariants.high,
      fileSize,
      videoVariants
    };
  } finally {
    for (const filePath of cleanupPaths) {
      try {
        if (!fs.existsSync(filePath)) continue;
        if (fs.statSync(filePath).isDirectory()) {
          fs.rmSync(filePath, { recursive: true, force: true });
        } else {
          fs.unlinkSync(filePath);
        }
      } catch (error) {
        console.warn('Video temp cleanup failed', filePath, error.message);
      }
    }
  }
}

async function transcodeStoryVideo({ userId, uploadId, segmentId, temporaryUrl }) {
  const bucket = admin.storage().bucket();
  const tempBase = path.join(os.tmpdir(), `story_video_${uploadId}_${segmentId}_${Date.now()}`);
  const inputPath = `${tempBase}_input.mp4`;
  const outputPath = `${tempBase}_processed.mp4`;

  try {
    const sourceObjectName = userOwnedVideoObjectNameFromFirebaseUrl(temporaryUrl, userId);
    if (!sourceObjectName) {
      throw new Error('Story video source must be a Firebase Storage upload owned by this user');
    }
    await downloadStorageObjectToFile({ bucket, objectName: sourceObjectName, destinationPath: inputPath });

    await runFfmpeg([
      '-y',
      '-i', inputPath,
      '-vf', 'scale=1280:1280:force_original_aspect_ratio=decrease,format=yuv420p',
      '-c:v', 'libx264',
      '-preset', 'veryfast',
      '-crf', '24',
      '-c:a', 'aac',
      '-b:a', '128k',
      '-movflags', '+faststart',
      outputPath
    ]);

    const objectName = `processed_videos/stories/${userId}/${uploadId}/${segmentId}.mp4`;
    const token = crypto.randomUUID();

    await bucket.upload(outputPath, {
      destination: objectName,
      metadata: {
        contentType: 'video/mp4',
        metadata: {
          firebaseStorageDownloadTokens: token,
          sourceUploadId: uploadId,
          sourceSegmentId: segmentId,
          processedBy: 'processStoryVideos'
        }
      }
    });

    return {
      url: firebaseStorageDownloadUrl(bucket.name, objectName, token),
      fileSize: fs.statSync(outputPath).size
    };
  } finally {
    for (const filePath of [inputPath, outputPath]) {
      try {
        if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
      } catch (error) {
        console.warn('Story video temp cleanup failed', filePath, error.message);
      }
    }
  }
}

function addStorageUrl(targetSet, value) {
  if (typeof value !== 'string') return;
  const trimmed = value.trim();
  if (!trimmed) return;
  if (
    trimmed.startsWith('https://firebasestorage.googleapis.com/') ||
    trimmed.startsWith('images/') ||
    trimmed.startsWith('videos/') ||
    trimmed.startsWith('users/') ||
    trimmed.startsWith('processed_videos/') ||
    trimmed.startsWith('story_processing_uploads/') ||
    trimmed.startsWith('stories/') ||
    trimmed.startsWith('conversations/') ||
    trimmed.startsWith('background_frames/') ||
    trimmed.startsWith('story_frames/') ||
    trimmed.startsWith('story_audio/') ||
    trimmed.startsWith('hidden_layers/') ||
    trimmed.startsWith('exports/')
  ) {
    targetSet.add(trimmed);
  }
}

function storageObjectNameFromTrustedValue(value, bucketName) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  const fromUrl = storageObjectNameFromFirebaseUrl(trimmed, bucketName);
  if (fromUrl) return fromUrl;

  if (!trimmed || trimmed.includes('://') || trimmed.startsWith('/') || trimmed.includes('..')) return null;
  return trimmed;
}

function storageObjectBelongsToUser(objectName, uid) {
  if (typeof objectName !== 'string' || typeof uid !== 'string' || !uid.trim()) return false;

  const safeUid = uid.trim();
  const userScopedPrefixes = [
    `users/${safeUid}/profile/`,
    `users/${safeUid}/moments/`,
    `users/${safeUid}/stories/`,
    `users/${safeUid}/chat/`,
    `users/${safeUid}/exports/`,
    `processed_videos/moments/${safeUid}/`,
    `processed_videos/stories/${safeUid}/`,
    `story_processing_uploads/${safeUid}/`,
    `stories/${safeUid}/`,
    `background_frames/${safeUid}/`,
    `story_frames/${safeUid}/`,
    `story_audio/${safeUid}/`,
    `hidden_layers/${safeUid}/`
  ];

  if (userScopedPrefixes.some((prefix) => objectName.startsWith(prefix))) {
    return true;
  }

  // Legacy moment/profile uploads were stored as images/<uuid>_<uid>.* and videos/<uuid>_<uid>.*.
  if (objectName.startsWith('images/') || objectName.startsWith('videos/')) {
    const fileName = path.basename(objectName);
    const suffixStart = fileName.lastIndexOf(`_${safeUid}.`);
    return suffixStart > 0 && suffixStart + safeUid.length + 2 < fileName.length;
  }

  return false;
}

function addOwnedBackgroundFrameStorageUrl(targetSet, value, uid) {
  if (typeof value !== 'string') return;
  const trimmed = value.trim();
  if (!trimmed) return;

  const bucket = admin.storage().bucket();
  const objectName = storageObjectNameFromTrustedValue(trimmed, bucket.name);
  if (objectName && objectName.startsWith('background_frames/') && storageObjectBelongsToUser(objectName, uid)) {
    targetSet.add(trimmed);
  }
}

function addMediaItemStorageUrls(targetSet, item, uid, momentId) {
  if (!item || typeof item !== 'object') return;

  addStorageUrl(targetSet, item.url);
  addStorageUrl(targetSet, item.thumbnailUrl);
  addStorageUrl(targetSet, item.originalVideoUrl);

  const variants = item.videoVariants;
  if (variants && typeof variants === 'object') {
    addStorageUrl(targetSet, variants.low);
    addStorageUrl(targetSet, variants.medium);
    addStorageUrl(targetSet, variants.high);
  }

  if (item.type === 'video' && typeof item.id === 'string' && item.id.trim() && uid && momentId) {
    const safeUid = uid.trim();
    const safeMomentId = momentId.trim();
    const mediaId = item.id.trim();
    const base = `processed_videos/moments/${safeUid}/${safeMomentId}/${mediaId}`;
    addStorageUrl(targetSet, `${base}.mp4`);
    addStorageUrl(targetSet, `${base}_low.mp4`);
    addStorageUrl(targetSet, `${base}_medium.mp4`);
    addStorageUrl(targetSet, `${base}_high.mp4`);
  }
}

function collectDeletedContentStorageUrls(data = {}, uid, momentId = null) {
  const urls = new Set();
  const resolvedMomentId = momentId || (typeof data.id === 'string' ? data.id : null);

  // Legacy/top-level media fields. Do not include profileImagePath; it belongs to the user profile.
  addStorageUrl(urls, data.imagePath);
  addStorageUrl(urls, data.videoUrl);
  addStorageUrl(urls, data.thumbnailUrl);
  addStorageUrl(urls, data.mediaUrl);
  addStorageUrl(urls, data.mediaURL);
  addOwnedBackgroundFrameStorageUrl(urls, data.backgroundFrameURL, uid);
  addOwnedBackgroundFrameStorageUrl(urls, data.backgroundBlurredFrameURL, uid);

  const mediaItems = Array.isArray(data.mediaItems) ? data.mediaItems : [];
  for (const item of mediaItems) {
    addMediaItemStorageUrls(urls, item, uid, resolvedMomentId);
  }

  const mediaItem = data.mediaItem && typeof data.mediaItem === 'object' ? data.mediaItem : null;
  if (mediaItem) {
    addMediaItemStorageUrls(urls, mediaItem, uid, resolvedMomentId);
  }

  const hiddenLayers = Array.isArray(data.hiddenLayers) ? data.hiddenLayers : [];
  for (const layer of hiddenLayers) {
    if (!layer || typeof layer !== 'object') continue;
    addStorageUrl(urls, layer.mediaURL);
    addStorageUrl(urls, layer.thumbnailURL);
    addStorageUrl(urls, layer.audioURL);
  }

  const stickers = Array.isArray(data.stickers) ? data.stickers : [];
  for (const sticker of stickers) {
    if (!sticker || typeof sticker !== 'object') continue;
    addStorageUrl(urls, sticker.mediaURL);
    addStorageUrl(urls, sticker.audioURL);
    const interactionData = sticker.interactionData && typeof sticker.interactionData === 'object'
      ? sticker.interactionData
      : null;
    if (interactionData) {
      addStorageUrl(urls, interactionData.audioURL);
      addStorageUrl(urls, interactionData.mediaURL);
    }
  }

  return [...urls];
}

async function permanentlyDeleteRecentlyDeletedDoc(doc) {
  if (!doc.exists) {
    return {
      id: doc.id,
      status: 'missing',
      deletedDocuments: 0,
      storageDeleted: 0,
      storageSkipped: 0
    };
  }

  const data = doc.data() || {};
  const type = typeof data.type === 'string' ? data.type : 'moment';
  const userRef = doc.ref.parent.parent;
  const uid = userRef?.id;
  const storageUrls = collectDeletedContentStorageUrls(data, uid, doc.id);

  await admin.firestore().recursiveDelete(doc.ref);

  if (uid) {
    if (type === 'story') {
      await admin.firestore().recursiveDelete(admin.firestore().doc(`users/${uid}/stories/${doc.id}`));
    } else {
      await admin.firestore().recursiveDelete(admin.firestore().doc(`users/${uid}/moments/${doc.id}`));
    }
  }

  const storageResult = await deleteStorageUrls(storageUrls, uid);
  return {
    id: doc.id,
    type,
    uid,
    status: 'deleted',
    deletedDocuments: 1,
    storageDeleted: storageResult.deleted.length,
    storageSkipped: storageResult.skipped.length
  };
}

async function deleteStorageUrls(urls, uid) {
  const bucket = admin.storage().bucket();
  const deleted = [];
  const skipped = [];

  for (const url of urls) {
    const objectName = storageObjectNameFromTrustedValue(url, bucket.name);

    if (!objectName) {
      skipped.push({ url, reason: 'invalid_storage_url' });
      continue;
    }

    if (!storageObjectBelongsToUser(objectName, uid)) {
      skipped.push({ url, objectName, reason: 'not_owned_by_user' });
      continue;
    }

    try {
      await bucket.file(objectName).delete({ ignoreNotFound: true });
      deleted.push(objectName);
    } catch (error) {
      skipped.push({ url, objectName, reason: error.message || 'delete_failed' });
    }
  }

  return { deleted, skipped };
}


function storageObjectNameFromExportMediaUrl(value, expectedBucketName) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed) return null;

  if (!trimmed.includes('://')) {
    return trimmed.replace(/^\/+/, '');
  }

  try {
    const parsed = new URL(trimmed);
    if (parsed.protocol === 'gs:') {
      if (parsed.hostname !== expectedBucketName) return null;
      return decodeURIComponent(parsed.pathname.replace(/^\/+/, ''));
    }

    if (parsed.protocol !== 'https:') return null;

    if (parsed.hostname === 'firebasestorage.googleapis.com') {
      return storageObjectNameFromFirebaseUrl(trimmed, expectedBucketName);
    }

    if (parsed.hostname === 'storage.googleapis.com') {
      const parts = parsed.pathname.split('/').filter(Boolean);
      if (parts.length < 2 || decodeURIComponent(parts[0]) !== expectedBucketName) return null;
      return decodeURIComponent(parts.slice(1).join('/'));
    }

    if (parsed.hostname === `${expectedBucketName}.storage.googleapis.com`) {
      return decodeURIComponent(parsed.pathname.replace(/^\/+/, ''));
    }
  } catch (error) {
    return null;
  }

  return null;
}

function storageObjectBelongsToConversation(objectName, conversationId) {
  if (typeof objectName !== 'string' || typeof conversationId !== 'string' || !conversationId.trim()) return false;
  return objectName.startsWith(`conversations/${conversationId.trim()}/`);
}

function storageObjectIsAllowedForExport(objectName, userId, authorizedConversationIds = []) {
  if (storageObjectBelongsToUser(objectName, userId)) return true;
  return authorizedConversationIds.some((conversationId) => storageObjectBelongsToConversation(objectName, conversationId));
}

async function collectMediaFileEntries(mediaUrls, userId, authorizedConversationIds = [], manager, destPrefix = 'media') {
  const uniqueUrls = Array.from(new Set((mediaUrls || []).filter((url) => typeof url === 'string' && url.trim().length > 0)));
  const bucket = admin.storage().bucket();
  const limits = EXPORT_MEDIA_LIMITS;
  let totalBytes = 0;
  const manifest = {
    requested: uniqueUrls.length,
    downloaded: [],
    skipped: []
  };

  for (let i = 0; i < uniqueUrls.length; i += 1) {
    const mediaUrl = uniqueUrls[i];
    const objectName = storageObjectNameFromExportMediaUrl(mediaUrl, bucket.name);
    if (!objectName) {
      manifest.skipped.push({ url: mediaUrl, reason: 'unsupported_media_origin' });
      continue;
    }
    if (!storageObjectIsAllowedForExport(objectName, userId, authorizedConversationIds)) {
      manifest.skipped.push({ url: mediaUrl, reason: 'not_authorized_for_export' });
      continue;
    }

    if (manifest.downloaded.length >= limits.maxFiles) {
      manifest.skipped.push({ url: mediaUrl, reason: 'max_files_reached' });
      continue;
    }
    if (totalBytes >= limits.maxTotalBytes) {
      manifest.skipped.push({ url: mediaUrl, reason: 'max_total_size_reached' });
      continue;
    }

    try {
      const file = bucket.file(objectName);
      const [metadata] = await file.getMetadata();
      const declaredBytes = Number(metadata.size || 0);
      if (Number.isFinite(declaredBytes) && declaredBytes > limits.maxSingleFileBytes) {
        manifest.skipped.push({ url: mediaUrl, reason: 'single_file_too_large' });
        continue;
      }
      const [buffer] = await file.download();
      if (buffer.length === 0) {
        manifest.skipped.push({ url: mediaUrl, reason: 'empty_file' });
        continue;
      }
      if (buffer.length > limits.maxSingleFileBytes) {
        manifest.skipped.push({ url: mediaUrl, reason: 'single_file_too_large' });
        continue;
      }
      if ((totalBytes + buffer.length) > limits.maxTotalBytes) {
        manifest.skipped.push({ url: mediaUrl, reason: 'max_total_size_reached' });
        continue;
      }

      const ext = inferFileExtension(objectName, metadata.contentType || '');
      const fileName = `${destPrefix}/media_${String(manifest.downloaded.length + 1).padStart(4, '0')}.${ext}`;
      await manager.addFile(fileName, buffer);
      totalBytes += buffer.length;
      manifest.downloaded.push({
        file: fileName,
        bytes: buffer.length,
        sourceUrl: mediaUrl
      });
    } catch (error) {
      manifest.skipped.push({
        url: mediaUrl,
        reason: String(error?.name || error?.message || 'download_error')
      });
    }
  }

  manifest.totalDownloadedBytes = totalBytes;
  return manifest;
}

function collectMediaUrlsByCategory(payload, userId) {
  const bucket = admin.storage().bucket();
  const categories = { moments: new Set(), stories: new Set(), profile: new Set() };
  const pushTo = (category, url) => {
    if (typeof url !== 'string' || !url.trim()) return;
    const trimmed = url.trim();
    const objectName = storageObjectNameFromExportMediaUrl(trimmed, bucket.name);
    if (objectName && storageObjectBelongsToUser(objectName, userId)) {
      categories[category].add(trimmed);
    }
  };

  for (const moment of payload.moments || []) {
    pushTo('moments', moment.imagePath);
    pushTo('moments', moment.imageUrl);
    pushTo('moments', moment.videoUrl);
    if (Array.isArray(moment.mediaItems)) {
      for (const item of moment.mediaItems) pushTo('moments', item?.url);
    }
  }

  for (const story of payload.stories || []) {
    const mediaItem = story.mediaItem || {};
    pushTo('stories', mediaItem.url);
    pushTo('stories', mediaItem.thumbnailUrl);
    pushTo('stories', story.backgroundFrameURL);
    pushTo('stories', story.backgroundBlurredFrameURL);
  }

  pushTo('profile', payload.profile?.profileImagePath);

  return {
    moments: Array.from(categories.moments),
    stories: Array.from(categories.stories),
    profile: Array.from(categories.profile)
  };
}

const PROFILE_INTERNAL_FIELDS = [
  'chatKey',
  'fcmToken',
  'fcmTokenUpdatedAt',
  'deviceInfo',
  'conversationStatus',
  'onlineStatus',
  'incognito'
];

function stripInternalFields(records, fields) {
  if (!Array.isArray(records)) return records;
  return records.map((record) => {
    const cleaned = { ...record };
    for (const field of fields) delete cleaned[field];
    return cleaned;
  });
}

function cleanProfileForExport(profile) {
  const cleaned = { ...(profile || {}) };
  for (const field of PROFILE_INTERNAL_FIELDS) {
    delete cleaned[field];
  }
  return cleaned;
}

async function fetchUsernamesForIds(userIds) {
  const uniqueIds = Array.from(new Set((userIds || []).filter((id) => typeof id === 'string' && id.trim().length > 0)));
  const usernames = new Map();
  await Promise.all(uniqueIds.map(async (id) => {
    try {
      const snap = await admin.firestore().collection('users').doc(id).get();
      const username = snap.exists ? snap.data().username : null;
      usernames.set(id, typeof username === 'string' && username.trim().length > 0 ? username : id);
    } catch (error) {
      usernames.set(id, id);
    }
  }));
  return usernames;
}

function usernamesForList(idList, usernameMap) {
  return (Array.isArray(idList) ? idList : []).map((id) => usernameMap.get(id) || id);
}

const MOMENT_INTERNAL_FIELDS = [
  'moderationReason', 'moderationCategory', 'canRestore', 'confidence', 'mediaType', 'moderationDetails',
  'originalAudience', 'reviewRequired', 'moderatedBy', 'moderatedAt', 'originalMediaURL', 'restoredBy',
  'isModerationHidden', 'restoredAt', 'restoreReason', 'moderatorNotes', 'reviewedAt', 'reviewComplete',
  'reviewedBy', 'hiddenLayerCount', 'hasHiddenLayers', 'gridPreviewOffsetX', 'gridPreviewOffsetY',
  'gridPreviewScale', 'gridPreviewBackground', 'gridPreviewFitMode', 'customListId', 'scheduledDate'
];

const STORY_INTERNAL_FIELDS = [
  'moderatedBy', 'combinedScore', 'isModerationHidden', 'moderationReason', 'moderationCategory',
  'visualScore', 'moderationDetails', 'moderatedAt', 'reviewRequired', 'videoProcessingUpdatedAt',
  'videoProcessingError', 'videoProcessingStatus', 'canRestore', 'confidence', 'mediaType',
  'originalAudience', 'originalMediaURL', 'restoredBy', 'restoredAt', 'restoreReason', 'moderatorNotes',
  'reviewedAt', 'reviewComplete', 'reviewedBy', 'drawingData', 'customListId', 'chainId', 'chainPosition',
  'chainTitle', 'continuationAudience', 'continuationCustomViewers', 'mapVisibility', 'stickers'
];

const NOTIFICATION_INTERNAL_FIELDS = [
  'processed', 'processedAt', 'echoId', 'notificationId', 'moderatedMediaCount', 'moderationCategory',
  'moderationScope', 'moderationType', 'totalMediaCount', 'moderatedMediaIndex', 'downloadPartsCount',
  'requestId', 'downloadURL', 'storyPreviewUrl'
];

async function buildDataExportPayload(userId, exportType, requestedFormat, pin) {
  const userSnap = await admin.firestore().collection('users').doc(userId).get();
  const profile = userSnap.exists ? cleanProfileForExport(toSerializable(userSnap.data())) : {};

  const payload = {
    exportInfo: {
      exportDate: new Date().toISOString(),
      version: '2.0',
      platform: 'server',
      requestedFormat,
      exportType
    },
    profile
  };

  const recoveredKeys = typeof pin === 'string' && pin.trim().length > 0
    ? await unwrapRecoveryBundle(userId, pin)
    : null;
  payload.exportInfo.conversationsIncluded = Boolean(recoveredKeys);

  if (exportType === 'conversationsOnly') {
    if (recoveredKeys) {
      payload.conversations = await fetchUserConversations(userId, recoveredKeys.chatPrivateKeyBuffer);
      payload.nova = await fetchNovaConversations(userId, recoveredKeys.novaUserKeyBuffer);
      Object.defineProperty(payload.nova, '_novaUserKeyBuffer', {
        value: recoveredKeys.novaUserKeyBuffer,
        enumerable: false
      });
    }
  } else if (exportType !== 'mediaOnly') {
    payload.moments = stripInternalFields(await fetchUserSubcollection(userId, 'moments'), MOMENT_INTERNAL_FIELDS);
    payload.stories = stripInternalFields(await fetchUserSubcollection(userId, 'stories'), STORY_INTERNAL_FIELDS);
    payload.following = await fetchUserSubcollection(userId, 'following');
    payload.followers = stripInternalFields(await fetchUserSubcollection(userId, 'followers'), ['processed']);
    payload.mutuals = await fetchUserSubcollection(userId, 'mutuals');
    payload.notifications = stripInternalFields(await fetchUserSubcollection(userId, 'notifications'), NOTIFICATION_INTERNAL_FIELDS);
    payload.savedMoments = await fetchUserSubcollection(userId, 'savedMoments');
    payload.visits = await fetchUserSubcollection(userId, 'visits');
    payload.visitSummaries = await fetchUserSubcollection(userId, 'visitSummaries');
    payload.comments = await fetchUserComments(userId);
    payload.reactions = stripInternalFields(await fetchUserReactions(userId), ['processed']);

    const idsNeedingUsernames = [
      ...payload.following.map((item) => item.userId),
      ...payload.followers.map((item) => item.userId),
      ...payload.mutuals.map((item) => item.userId),
      ...payload.reactions.map((item) => item.contentAuthorId),
      ...payload.comments.map((item) => item.momentAuthorId),
      ...(profile.bestFriends || []),
      ...(profile.blockedUsers || []),
      ...(profile.muteSettings?.mutedUsers || [])
    ];
    const usernameMap = await fetchUsernamesForIds(idsNeedingUsernames);
    payload.following = payload.following.map((item) => ({ username: usernameMap.get(item.userId) || item.userId, timestamp: item.timestamp }));
    payload.followers = payload.followers.map((item) => ({ username: usernameMap.get(item.userId) || item.userId, timestamp: item.timestamp }));
    payload.mutuals = payload.mutuals.map((item) => ({ username: usernameMap.get(item.userId) || item.userId, timestamp: item.timestamp }));
    payload.reactions = payload.reactions.map((item) => {
      const { contentAuthorId, userId: _reactorId, documentId: _reactionDocId, ...rest } = item;
      return { ...rest, contentAuthorUsername: usernameMap.get(contentAuthorId) || contentAuthorId };
    });
    payload.comments = payload.comments.map((item) => {
      const { momentAuthorId, ...rest } = item;
      return { ...rest, momentAuthorUsername: usernameMap.get(momentAuthorId) || momentAuthorId };
    });
    if (Array.isArray(profile.bestFriends)) payload.profile.bestFriends = usernamesForList(profile.bestFriends, usernameMap);
    if (Array.isArray(profile.blockedUsers)) payload.profile.blockedUsers = usernamesForList(profile.blockedUsers, usernameMap);
    if (profile.muteSettings && Array.isArray(profile.muteSettings.mutedUsers)) {
      payload.profile.muteSettings = { ...profile.muteSettings, mutedUsers: usernamesForList(profile.muteSettings.mutedUsers, usernameMap) };
    }

    if (recoveredKeys) {
      payload.conversations = await fetchUserConversations(userId, recoveredKeys.chatPrivateKeyBuffer);
      payload.nova = await fetchNovaConversations(userId, recoveredKeys.novaUserKeyBuffer);
      Object.defineProperty(payload.nova, '_novaUserKeyBuffer', {
        value: recoveredKeys.novaUserKeyBuffer,
        enumerable: false
      });
    }
  } else {
    payload.moments = await fetchUserSubcollection(userId, 'moments');
    payload.stories = await fetchUserSubcollection(userId, 'stories');
    if (recoveredKeys) {
      payload.conversations = await fetchUserConversations(userId, recoveredKeys.chatPrivateKeyBuffer);
      payload.nova = await fetchNovaConversations(userId, recoveredKeys.novaUserKeyBuffer);
      Object.defineProperty(payload.nova, '_novaUserKeyBuffer', {
        value: recoveredKeys.novaUserKeyBuffer,
        enumerable: false
      });
    }
  }

  if (exportType !== 'textOnly' && exportType !== 'conversationsOnly') {
    payload.mediaUrlsByCategory = collectMediaUrlsByCategory(payload, userId);
    Object.defineProperty(payload, '_mediaAuthorizedConversationIds', {
      value: (payload.conversations || [])
        .map((conversation) => conversation.conversationId)
        .filter((conversationId) => typeof conversationId === 'string' && conversationId.trim().length > 0),
      enumerable: false
    });
  }

  if (exportType === 'mediaOnly') {
    delete payload.moments;
    delete payload.stories;
  }

  return payload;
}

function escapeCsvCell(value) {
  if (value === null || value === undefined) return '';
  const str = typeof value === 'string' ? value : JSON.stringify(value);
  if (/[",\n\r]/.test(str)) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

function flattenRow(row) {
  const out = {};
  for (const [key, value] of Object.entries(row || {})) {
    if (value === null || value === undefined) {
      out[key] = '';
    } else if (typeof value === 'object') {
      out[key] = JSON.stringify(value);
    } else {
      out[key] = String(value);
    }
  }
  return out;
}

function rowsToCsv(rows) {
  if (!Array.isArray(rows) || rows.length === 0) return '';
  const flattened = rows.map(flattenRow);
  const headers = Array.from(new Set(flattened.flatMap((row) => Object.keys(row))));
  const headerLine = headers.map(escapeCsvCell).join(',');
  const lines = flattened.map((row) => headers.map((h) => escapeCsvCell(row[h] || '')).join(','));
  return [headerLine, ...lines].join('\n');
}

function buildCsvFiles(payload) {
  const csvFiles = [];
  const mappings = [
    ['moments', payload.moments],
    ['stories', payload.stories],
    ['notifications', payload.notifications],
    ['following', payload.following],
    ['followers', payload.followers],
    ['mutuals', payload.mutuals],
    ['saved_moments', payload.savedMoments],
    ['comments', payload.comments],
    ['reactions', payload.reactions]
  ];
  for (const [name, rows] of mappings) {
    if (!Array.isArray(rows) || rows.length === 0) continue;
    const csv = rowsToCsv(rows);
    if (!csv) continue;
    csvFiles.push({
      path: `csv/${name}.csv`,
      content: csv
    });
  }
  return csvFiles;
}

function buildReadmeContent(payload, requestedFormat, exportType) {
  const now = new Date().toISOString();
  const conversationsIncluded = Boolean(payload?.exportInfo?.conversationsIncluded);

  const lines = [
    '# Moments Data Export',
    '',
    `Generated at: ${now}`,
    `Format requested: ${requestedFormat}`,
    `Export type: ${exportType}`,
    ''
  ];

  if (exportType === 'conversationsOnly') {
    lines.push(
      'This export only includes your conversations and Nova/assistant chats.',
      'Your posts, stories, comments, connections and activity are NOT part of this export.',
      ''
    );
    if (conversationsIncluded) {
      lines.push(
        'Folders:',
        '- conversations/{contact}/transcript.txt (readable chat log) and messages.json (structured data)',
        '- conversations/{contact}/media/ (decrypted photos, videos, voice notes, files from that chat)',
        '- nova/{conversation}/transcript.txt and conversation.json (your Nova/assistant chats, decrypted)'
      );
    } else {
      lines.push(
        'NOTHING was included because no recovery PIN was provided (or the PIN entered was incorrect).',
        'Request a new export with this option and enter your recovery PIN to receive your conversations.'
      );
    }
    lines.push('');
    return lines.join('\n');
  }

  lines.push('Folders:');
  lines.push('- profile/profile.json (your account info)');
  if (exportType !== 'textOnly') lines.push('- profile/media/ (your profile picture)');
  lines.push('- connections/following.json, followers.json, mutuals.json');
  if (exportType !== 'mediaOnly') lines.push('- content/moments.json, stories.json, saved_moments.json');
  if (exportType !== 'textOnly') lines.push('- content/media/moments/, content/media/stories/ (your posted photos and videos)');
  if (exportType !== 'mediaOnly') {
    lines.push(
      '- comments_and_reactions/comments.json, reactions.json',
      '- activity/notifications.json, visits.json, visit_summaries.json'
    );
  }
  lines.push(
    '- csv/*.csv (if CSV format was requested)',
    '- meta.json (export metadata)'
  );

  if (conversationsIncluded) {
    if (exportType !== 'mediaOnly') lines.push('- conversations/{contact}/transcript.txt (readable chat log) and messages.json (structured data)');
    if (exportType !== 'textOnly') lines.push('- conversations/{contact}/media/ (decrypted photos, videos, voice notes, files from that chat)');
    if (exportType !== 'mediaOnly') lines.push('- nova/{conversation}/transcript.txt and conversation.json (your Nova/assistant chats, decrypted)');
  } else {
    lines.push(
      '',
      'NOT included: your conversations and Nova/assistant chats.',
      'These are end-to-end encrypted and were not included because no recovery PIN was provided',
      '(or the PIN entered was incorrect). Request a new export and enter your recovery PIN to',
      'include them in readable form.'
    );
  }

  lines.push('');
  return lines.join('\n');
}

function conversationDisplayName(conversation, userId, participantData) {
  const otherIds = (conversation.participants || []).filter((id) => id !== userId);
  if (otherIds.length === 0) return conversation.conversationId || 'conversation';
  const names = otherIds.map((id) => (participantData[id] || {}).username || id);
  return names.join('_');
}

function uniqueFolderName(baseName, usedNames) {
  const safeName = sanitizeFileName(baseName || 'conversation') || 'conversation';
  let candidate = safeName;
  let suffix = 2;
  while (usedNames.has(candidate)) {
    candidate = `${safeName}_${suffix}`;
    suffix += 1;
  }
  usedNames.add(candidate);
  return candidate;
}

function formatTimestampForTranscript(value) {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return date.toISOString().replace('T', ' ').slice(0, 16);
}

function cleanConversationMetadata(conversation, folderName) {
  const participantData = conversation.participantData || {};
  const participants = (conversation.participants || []).map((id) => (participantData[id] || {}).username || id);
  return {
    conversationId: conversation.conversationId,
    displayName: folderName,
    participants,
    isPinned: Boolean(conversation.isPinned),
    isMuted: Boolean(conversation.isMuted),
    vanishModeActive: Boolean(conversation.vanishModeActive),
    createdAt: conversation.encryptionKeyCreatedAt || null,
    lastActivityAt: conversation.timestamp || null
  };
}

function cleanMessageForExport(message, participantData) {
  const cleaned = {
    id: message.messageId || message.id,
    senderUsername: (participantData[message.senderId] || {}).username || message.senderId,
    timestamp: message.timestamp,
    type: message.type,
    isDeleted: Boolean(message.isDeleted)
  };
  if (typeof message.contentDecrypted === 'string') cleaned.text = message.contentDecrypted;
  if (message.locationDecrypted) cleaned.location = message.locationDecrypted;
  if (message.mediaFile) cleaned.mediaFile = message.mediaFile;
  if (message.thumbnailFile) cleaned.thumbnailFile = message.thumbnailFile;
  if (
    typeof message.content === 'string'
    && message.content.trim().length > 0
    && !cleaned.text
    && !cleaned.location
    && !cleaned.mediaFile
  ) {
    cleaned.undecryptable = true;
  }
  return cleaned;
}

function buildConversationTranscript(displayName, cleanedMessages) {
  const lines = [`Chat with ${displayName}`, ''];
  for (const message of cleanedMessages) {
    const when = formatTimestampForTranscript(message.timestamp);
    const who = message.senderUsername;
    let line;
    if (message.text) {
      line = message.text;
    } else if (message.location) {
      line = `[location] ${message.location.name || ''} ${message.location.address || ''}`.trim();
    } else if (message.mediaFile) {
      line = `[media] ${message.mediaFile}`;
    } else if (message.isDeleted) {
      line = '[deleted message]';
    } else if (message.undecryptable) {
      line = '[message could not be decrypted]';
    } else {
      line = `[${message.type || 'message'}]`;
    }
    lines.push(`[${when}] ${who}: ${line}`);
  }
  return lines.join('\n');
}

async function collectConversationEntries(conversations, limits, manager, userId, options = {}) {
  const includeMedia = options.includeMedia !== false;
  const includeText = options.includeText !== false;
  const bucket = admin.storage().bucket();
  let downloadedCount = 0;
  let totalBytes = 0;
  const manifest = { downloaded: [], skipped: [] };
  const usedFolderNames = new Set();

  for (const conversation of conversations || []) {
    const participantData = conversation.participantData || {};
    const folderName = uniqueFolderName(conversationDisplayName(conversation, userId, participantData), usedFolderNames);
    const conversationKey = conversation._conversationKey;

    for (const message of (includeMedia ? (conversation.messages || []) : [])) {
      const attachments = [
        { field: 'mediaFile', suffix: '', objectPath: message.mediaObjectPath, metadata: message.mediaEncryption },
        { field: 'thumbnailFile', suffix: '_thumb', objectPath: message.thumbnailObjectPath, metadata: message.thumbnailEncryption }
      ];

      for (const attachment of attachments) {
        if (!attachment.objectPath || !attachment.metadata) continue;

        if (!storageObjectBelongsToConversation(attachment.objectPath, conversation.conversationId)) {
          manifest.skipped.push({ objectPath: attachment.objectPath, reason: 'not_authorized_for_export' });
          continue;
        }
        if (!conversationKey) {
          manifest.skipped.push({ objectPath: attachment.objectPath, reason: 'missing_conversation_key' });
          continue;
        }
        if (downloadedCount >= limits.maxFiles) {
          manifest.skipped.push({ objectPath: attachment.objectPath, reason: 'max_files_reached' });
          continue;
        }
        if (totalBytes >= limits.maxTotalBytes) {
          manifest.skipped.push({ objectPath: attachment.objectPath, reason: 'max_total_size_reached' });
          continue;
        }

        try {
          const file = bucket.file(attachment.objectPath);
          const [encryptedBuffer] = await file.download();
          if (encryptedBuffer.length > limits.maxSingleFileBytes) {
            manifest.skipped.push({ objectPath: attachment.objectPath, reason: 'single_file_too_large' });
            continue;
          }

          const decrypted = decryptChatMediaBuffer(
            encryptedBuffer,
            attachment.metadata,
            conversationKey,
            conversation.conversationId,
            message.messageId
          );
          if (!decrypted) {
            manifest.skipped.push({ objectPath: attachment.objectPath, reason: 'decryption_failed' });
            continue;
          }
          if ((totalBytes + decrypted.length) > limits.maxTotalBytes) {
            manifest.skipped.push({ objectPath: attachment.objectPath, reason: 'max_total_size_reached' });
            continue;
          }

          const ext = attachment.metadata.fileExtension
            || inferFileExtension(attachment.objectPath, attachment.metadata.contentType || '');
          const relativeFile = `${sanitizeFileName(message.messageId)}${attachment.suffix}.${ext}`;
          const zipPath = `conversations/${folderName}/media/${relativeFile}`;
          await manager.addFile(zipPath, decrypted);
          message[attachment.field] = `media/${relativeFile}`;

          totalBytes += decrypted.length;
          downloadedCount += 1;
          manifest.downloaded.push({ file: zipPath, bytes: decrypted.length });
        } catch (error) {
          manifest.skipped.push({
            objectPath: attachment.objectPath,
            reason: String(error?.name || error?.message || 'download_error')
          });
        }
      }
    }

    if (includeText) {
      const cleanedMessages = (conversation.messages || []).map((message) => cleanMessageForExport(message, participantData));
      const cleanedConversation = cleanConversationMetadata(conversation, folderName);
      cleanedConversation.messages = cleanedMessages;

      await manager.addFile(`conversations/${folderName}/messages.json`, JSON.stringify(cleanedConversation, null, 2));
      await manager.addFile(`conversations/${folderName}/transcript.txt`, buildConversationTranscript(folderName, cleanedMessages));
    }
  }

  manifest.totalDownloadedBytes = totalBytes;
  return manifest;
}

function deriveNovaBlobKey(novaUserKeyBuffer, userId, purpose) {
  const salt = Buffer.from('moments.nova.blob.salt.v1', 'utf8');
  const info = Buffer.from(`moments.nova.blob.v1|${userId}|${purpose}`, 'utf8');
  return Buffer.from(crypto.hkdfSync('sha256', novaUserKeyBuffer, salt, info, 32));
}

function novaBlobAuthenticatedData(userId, purpose) {
  return Buffer.from(`moments.nova.blob.aad.v1|${userId}|${purpose}`, 'utf8');
}

function decryptNovaBlobBuffer(encryptedBuffer, novaUserKeyBuffer, userId, purpose) {
  if (!encryptedBuffer || !novaUserKeyBuffer) return null;
  try {
    const blobKey = deriveNovaBlobKey(novaUserKeyBuffer, userId, purpose);
    const aad = novaBlobAuthenticatedData(userId, purpose);

    if (encryptedBuffer.length < 12 + 16) return null;
    const iv = encryptedBuffer.subarray(0, 12);
    const tag = encryptedBuffer.subarray(encryptedBuffer.length - 16);
    const ciphertext = encryptedBuffer.subarray(12, encryptedBuffer.length - 16);

    const decipher = crypto.createDecipheriv('aes-256-gcm', blobKey, iv);
    decipher.setAuthTag(tag);
    decipher.setAAD(aad);
    return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  } catch (error) {
    return null;
  }
}

function novaImageObjectPath(storedPath) {
  const trimmed = String(storedPath || '').trim();
  if (!trimmed) return '';
  if (trimmed.startsWith('https://firebasestorage.googleapis.com')) {
    try {
      const url = new URL(trimmed);
      const marker = '/o/';
      const idx = url.pathname.indexOf(marker);
      if (idx === -1) return trimmed;
      return decodeURIComponent(url.pathname.slice(idx + marker.length));
    } catch (error) {
      return trimmed;
    }
  }
  if (trimmed.includes('://')) return trimmed;
  return trimmed;
}

function novaConversationDisplayName(conversation) {
  if (typeof conversation.titleDecrypted === 'string' && conversation.titleDecrypted.trim().length > 0) {
    return conversation.titleDecrypted.trim();
  }
  const createdAt = formatTimestampForTranscript(conversation.createdAt) || 'conversation';
  return `${createdAt}_${(conversation.conversationId || '').slice(0, 8)}`;
}

function cleanNovaMessage(message) {
  const cleaned = {
    id: message.id,
    role: message.isUser ? 'user' : 'nova'
  };
  if (typeof message.textDecrypted === 'string') cleaned.text = message.textDecrypted;
  if (message.imageFile) cleaned.imageFile = message.imageFile;
  if (
    typeof message.text === 'string'
    && message.text.trim().length > 0
    && !cleaned.text
    && !cleaned.imageFile
  ) {
    cleaned.undecryptable = true;
  }
  return cleaned;
}

function buildNovaTranscript(displayName, cleanedMessages) {
  const lines = [`Nova conversation: ${displayName}`, ''];
  for (const message of cleanedMessages) {
    const who = message.role === 'user' ? 'You' : 'Nova';
    let line;
    if (message.text) {
      line = message.text;
    } else if (message.imageFile) {
      line = `[image] ${message.imageFile}`;
    } else if (message.undecryptable) {
      line = '[message could not be decrypted]';
    } else {
      line = '[message]';
    }
    lines.push(`${who}: ${line}`);
  }
  return lines.join('\n');
}

async function collectNovaImageEntries(novaPayload, userId, limits, manager, options = {}) {
  const includeMedia = options.includeMedia !== false;
  const includeText = options.includeText !== false;
  const manifest = { downloaded: [], skipped: [] };
  if (!novaPayload) return manifest;

  const novaUserKeyBuffer = novaPayload._novaUserKeyBuffer;
  const bucket = admin.storage().bucket();
  let downloadedCount = 0;
  let totalBytes = 0;
  const usedFolderNames = new Set();

  for (const conversation of novaPayload.conversations || []) {
    const folderName = uniqueFolderName(novaConversationDisplayName(conversation), usedFolderNames);

    if (includeMedia && novaUserKeyBuffer) {
      for (const message of conversation.messages || []) {
        if (typeof message.imageData !== 'string' || !message.imageData.trim()) continue;

        const objectPath = novaImageObjectPath(message.imageData);
        if (!objectPath || objectPath.includes('://')) {
          manifest.skipped.push({ messageId: message.id, reason: 'unsupported_media_origin' });
          continue;
        }
        if (downloadedCount >= limits.maxFiles || totalBytes >= limits.maxTotalBytes) {
          manifest.skipped.push({ messageId: message.id, reason: 'max_files_reached' });
          continue;
        }

        try {
          const [encryptedBuffer] = await bucket.file(objectPath).download();
          if (encryptedBuffer.length > limits.maxSingleFileBytes) {
            manifest.skipped.push({ messageId: message.id, reason: 'single_file_too_large' });
            continue;
          }

          const purpose = `conversationImage|${conversation.conversationId}|${message.id}`;
          const decrypted = decryptNovaBlobBuffer(encryptedBuffer, novaUserKeyBuffer, userId, purpose);
          if (!decrypted) {
            manifest.skipped.push({ messageId: message.id, reason: 'decryption_failed' });
            continue;
          }

          const fileName = `${sanitizeFileName(message.id)}.jpg`;
          const zipPath = `nova/${folderName}/media/${fileName}`;
          await manager.addFile(zipPath, decrypted);
          message.imageFile = `media/${fileName}`;

          totalBytes += decrypted.length;
          downloadedCount += 1;
          manifest.downloaded.push({ file: zipPath, bytes: decrypted.length });
        } catch (error) {
          manifest.skipped.push({ messageId: message.id, reason: String(error?.name || error?.message || 'download_error') });
        }
      }
    }

    if (includeText) {
      const cleanedMessages = (conversation.messages || []).map(cleanNovaMessage);
      const cleanedConversation = {
        conversationId: conversation.conversationId,
        displayName: folderName,
        createdAt: conversation.createdAt || null,
        lastUpdated: conversation.lastUpdated || null,
        messages: cleanedMessages
      };

      await manager.addFile(`nova/${folderName}/conversation.json`, JSON.stringify(cleanedConversation, null, 2));
      await manager.addFile(`nova/${folderName}/transcript.txt`, buildNovaTranscript(folderName, cleanedMessages));
    }
  }

  manifest.totalDownloadedBytes = totalBytes;
  return manifest;
}

const EXPORT_MEDIA_LIMITS = {
  maxFiles: 20000,
  maxTotalBytes: 50 * 1024 * 1024 * 1024,
  maxSingleFileBytes: 250 * 1024 * 1024
};

const ZIP_PART_MAX_BYTES = 500 * 1024 * 1024;

function createZipPartManager(maxPartBytes) {
  const parts = [];
  let currentArchive = null;
  let currentStream = null;
  let currentDone = null;
  let currentPath = null;
  let currentSize = 0;
  let addedAny = false;

  function startPart() {
    currentPath = path.join(os.tmpdir(), `export_part_${parts.length + 1}_${Date.now()}_${Math.random().toString(36).slice(2)}.zip`);
    currentStream = fs.createWriteStream(currentPath);
    currentArchive = archiver('zip', { zlib: { level: 6 } });
    currentDone = new Promise((resolve, reject) => {
      currentStream.on('close', resolve);
      currentStream.on('error', reject);
      currentArchive.on('error', reject);
    });
    currentArchive.pipe(currentStream);
    currentSize = 0;
  }

  async function closePart() {
    await currentArchive.finalize();
    await currentDone;
    const bytes = fs.statSync(currentPath).size;
    parts.push({ path: currentPath, bytes });
  }

  startPart();

  async function addFile(zipPath, content) {
    const buffer = Buffer.isBuffer(content) ? content : Buffer.from(String(content));
    if (currentSize > 0 && currentSize + buffer.length > maxPartBytes) {
      await closePart();
      startPart();
    }
    currentArchive.append(buffer, { name: zipPath });
    currentSize += buffer.length;
    addedAny = true;
  }

  async function finalize() {
    if (!addedAny && parts.length === 0) {
      currentArchive.abort();
      currentStream.destroy();
      fs.unlink(currentPath, () => {});
      return [];
    }
    await closePart();
    return parts;
  }

  return { addFile, finalize };
}

async function buildExportZipParts(payload, requestedFormat, exportType, userId) {
  const manager = createZipPartManager(ZIP_PART_MAX_BYTES);

  const conversationOptions = {
    includeMedia: exportType !== 'textOnly',
    includeText: exportType !== 'mediaOnly'
  };
  const conversationMediaManifest = await collectConversationEntries(payload.conversations, EXPORT_MEDIA_LIMITS, manager, userId, conversationOptions);
  const novaMediaManifest = await collectNovaImageEntries(payload.nova, userId, EXPORT_MEDIA_LIMITS, manager, conversationOptions);

  const mediaByCategory = payload.mediaUrlsByCategory || { moments: [], stories: [], profile: [] };
  let momentsMediaManifest = null;
  let storiesMediaManifest = null;
  let profileMediaManifest = null;
  if (exportType !== 'textOnly' && exportType !== 'conversationsOnly') {
    momentsMediaManifest = await collectMediaFileEntries(mediaByCategory.moments, userId, [], manager, 'content/media/moments');
    storiesMediaManifest = await collectMediaFileEntries(mediaByCategory.stories, userId, [], manager, 'content/media/stories');
    profileMediaManifest = await collectMediaFileEntries(mediaByCategory.profile, userId, [], manager, 'profile/media');
  }

  const metaZip = new JSZip();
  metaZip.file('meta.json', JSON.stringify(payload.exportInfo || {}, null, 2));
  metaZip.file('README.txt', buildReadmeContent(payload, requestedFormat, exportType));

  metaZip.file('profile/profile.json', JSON.stringify(payload.profile || {}, null, 2));

  metaZip.file('connections/following.json', JSON.stringify(payload.following || [], null, 2));
  metaZip.file('connections/followers.json', JSON.stringify(payload.followers || [], null, 2));
  metaZip.file('connections/mutuals.json', JSON.stringify(payload.mutuals || [], null, 2));

  if (payload.moments) metaZip.file('content/moments.json', JSON.stringify(payload.moments, null, 2));
  if (payload.stories) metaZip.file('content/stories.json', JSON.stringify(payload.stories, null, 2));
  if (payload.savedMoments) metaZip.file('content/saved_moments.json', JSON.stringify(payload.savedMoments, null, 2));

  if (payload.comments) metaZip.file('comments_and_reactions/comments.json', JSON.stringify(payload.comments, null, 2));
  if (payload.reactions) metaZip.file('comments_and_reactions/reactions.json', JSON.stringify(payload.reactions, null, 2));

  if (payload.notifications) metaZip.file('activity/notifications.json', JSON.stringify(payload.notifications, null, 2));
  if (payload.visits) metaZip.file('activity/visits.json', JSON.stringify(payload.visits, null, 2));
  if (payload.visitSummaries) metaZip.file('activity/visit_summaries.json', JSON.stringify(payload.visitSummaries, null, 2));

  metaZip.file('conversations/media_manifest.json', JSON.stringify(conversationMediaManifest, null, 2));
  if (payload.nova) {
    metaZip.file('nova/media_manifest.json', JSON.stringify(novaMediaManifest, null, 2));
  }
  if (momentsMediaManifest) metaZip.file('content/media/moments_manifest.json', JSON.stringify(momentsMediaManifest, null, 2));
  if (storiesMediaManifest) metaZip.file('content/media/stories_manifest.json', JSON.stringify(storiesMediaManifest, null, 2));
  if (profileMediaManifest) metaZip.file('profile/media_manifest.json', JSON.stringify(profileMediaManifest, null, 2));

  if (String(requestedFormat || '').toLowerCase() === 'csv') {
    const csvFiles = buildCsvFiles(payload);
    for (const csvFile of csvFiles) {
      metaZip.file(csvFile.path, csvFile.content);
    }
  }

  const metaBuffer = await metaZip.generateAsync({
    type: 'nodebuffer',
    compression: 'DEFLATE',
    compressionOptions: { level: 6 }
  });
  const metaPath = path.join(os.tmpdir(), `export_meta_${Date.now()}_${Math.random().toString(36).slice(2)}.zip`);
  fs.writeFileSync(metaPath, metaBuffer);

  const mediaParts = await manager.finalize();
  return [{ path: metaPath, bytes: metaBuffer.length }, ...mediaParts];
}

module.exports = {
  toSerializable,
  fetchUserSubcollection,
  fetchUserComments,
  fetchUserConversations,
  fetchConversationSharedKey,
  decryptChatContent,
  decodeLocationPayload,
  decryptChatMediaBuffer,
  collectConversationEntries,
  fetchNovaConversations,
  sanitizeFileName,
  inferFileExtension,
  runFfmpeg,
  firebaseStorageDownloadUrl,
  storageProjectIdFromBucketName,
  storageBucketsAreEquivalent,
  sanitizeStorageSegment,
  storageObjectNameFromFirebaseUrl,
  resolveStorageObjectNameFromClientMediaReference,
  userOwnedPublishableMediaObjectNameFromFirebaseUrl,
  hiddenLayerIdFromMediaItemId,
  userOwnedHiddenLayerImageObjectNameFromFirebaseUrl,
  userOwnedImageObjectNameFromFirebaseUrl,
  userOwnedVideoObjectNameFromFirebaseUrl,
  downloadStorageObjectToFile,
  deleteOriginalMomentVideoIfSafe,
  deleteStorageUrlIfSafe,
  uploadStorageFile,
  transcodeMomentVideo,
  transcodeStoryVideo,
  addStorageUrl,
  storageObjectNameFromTrustedValue,
  storageObjectBelongsToUser,
  addOwnedBackgroundFrameStorageUrl,
  addMediaItemStorageUrls,
  collectDeletedContentStorageUrls,
  permanentlyDeleteRecentlyDeletedDoc,
  deleteStorageUrls,
  storageObjectNameFromExportMediaUrl,
  storageObjectBelongsToConversation,
  storageObjectIsAllowedForExport,
  collectMediaFileEntries,
  collectMediaUrlsByCategory,
  buildDataExportPayload,
  escapeCsvCell,
  flattenRow,
  rowsToCsv,
  buildCsvFiles,
  buildReadmeContent,
  buildExportZipParts,
};
