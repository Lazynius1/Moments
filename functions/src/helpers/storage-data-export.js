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

async function fetchUserConversations(userId) {
  const conversationsSnap = await admin.firestore()
    .collection('conversations')
    .where('participants', 'array-contains', userId)
    .get();

  const conversations = [];
  for (const convoDoc of conversationsSnap.docs) {
    const conversationId = convoDoc.id;
    const conversationData = convoDoc.data() || {};
    const sharedKey = await fetchConversationSharedKey(conversationId, conversationData);
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
      }
      return serializedMessage;
    });

    conversations.push({
      conversationId,
      ...toSerializable(conversationData),
      messages
    });
  }
  return conversations;
}

async function fetchConversationSharedKey(conversationId, conversationData) {
  if (typeof conversationData.sharedEncryptionKey === 'string' && conversationData.sharedEncryptionKey.length > 0) {
    return conversationData.sharedEncryptionKey;
  }
  if (typeof conversationData.encryptionKey === 'string' && conversationData.encryptionKey.length > 0) {
    return conversationData.encryptionKey;
  }
  try {
    const sharedDoc = await admin.firestore()
      .collection('conversations')
      .doc(conversationId)
      .collection('encryption')
      .doc('shared')
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

async function fetchNovaConversations(userId) {
  const [titlesSnap, conversationsSnap] = await Promise.all([
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

  return {
    titles: titlesSnap.docs.map((doc) => ({ conversationId: doc.id, ...toSerializable(doc.data()) })),
    conversations: conversationsSnap.docs.map((doc) => ({ conversationId: doc.id, ...toSerializable(doc.data()) }))
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

async function addMediaFilesToZip(zip, mediaUrls, userId, authorizedConversationIds = []) {
  const uniqueUrls = Array.from(new Set((mediaUrls || []).filter((url) => typeof url === 'string' && url.trim().length > 0)));
  const bucket = admin.storage().bucket();
  const limits = {
    maxFiles: 120,
    maxTotalBytes: 200 * 1024 * 1024,
    maxSingleFileBytes: 30 * 1024 * 1024
  };
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
      const fileName = `media/media_${String(manifest.downloaded.length + 1).padStart(4, '0')}.${ext}`;
      zip.file(fileName, buffer);
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

function collectMediaUrlsFromPayload(payload, userId) {
  const urls = new Set();
  const bucket = admin.storage().bucket();
  const pushIfAllowed = (url, isAllowedObjectName) => {
    if (typeof url !== 'string' || !url.trim()) return;

    const trimmed = url.trim();
    const objectName = storageObjectNameFromExportMediaUrl(trimmed, bucket.name);
    if (objectName && isAllowedObjectName(objectName)) {
      urls.add(trimmed);
    }
  };
  const pushUserOwned = (url) => {
    pushIfAllowed(url, (objectName) => storageObjectBelongsToUser(objectName, userId));
  };
  const pushConversationOwned = (url, conversationId) => {
    pushIfAllowed(url, (objectName) => storageObjectBelongsToConversation(objectName, conversationId));
  };

  for (const moment of payload.moments || []) {
    pushUserOwned(moment.imagePath);
    pushUserOwned(moment.imageUrl);
    pushUserOwned(moment.videoUrl);
    if (Array.isArray(moment.mediaItems)) {
      for (const item of moment.mediaItems) pushUserOwned(item?.url);
    }
  }

  for (const story of payload.stories || []) {
    const mediaItem = story.mediaItem || {};
    pushUserOwned(mediaItem.url);
    pushUserOwned(mediaItem.thumbnailUrl);
    pushUserOwned(story.backgroundFrameURL);
    pushUserOwned(story.backgroundBlurredFrameURL);
  }

  for (const convo of payload.conversations || []) {
    const conversationId = convo.conversationId;
    for (const msg of convo.messages || []) {
      pushConversationOwned(msg.mediaUrl, conversationId);
      pushConversationOwned(msg.thumbnailUrl, conversationId);
    }
  }

  pushUserOwned(payload.profile?.profileImagePath);
  return Array.from(urls);
}

async function buildDataExportPayload(userId, exportType, requestedFormat) {
  const userSnap = await admin.firestore().collection('users').doc(userId).get();
  const profile = userSnap.exists ? toSerializable(userSnap.data()) : {};

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

  if (exportType !== 'mediaOnly') {
    payload.moments = await fetchUserSubcollection(userId, 'moments');
    payload.stories = await fetchUserSubcollection(userId, 'stories');
    payload.following = await fetchUserSubcollection(userId, 'following');
    payload.followers = await fetchUserSubcollection(userId, 'followers');
    payload.mutuals = await fetchUserSubcollection(userId, 'mutuals');
    payload.notifications = await fetchUserSubcollection(userId, 'notifications');
    payload.activityStats = await fetchUserSubcollection(userId, 'dailyStats');
    payload.loginActivity = await fetchUserSubcollection(userId, 'loginActivity');
    payload.savedMoments = await fetchUserSubcollection(userId, 'savedMoments');
    payload.visits = await fetchUserSubcollection(userId, 'visits');
    payload.visitSummaries = await fetchUserSubcollection(userId, 'visitSummaries');
    payload.conversations = await fetchUserConversations(userId);
    payload.nova = await fetchNovaConversations(userId);
  } else {
    // For media-only exports we still need source docs to discover media URLs.
    payload.moments = await fetchUserSubcollection(userId, 'moments');
    payload.stories = await fetchUserSubcollection(userId, 'stories');
    payload.conversations = await fetchUserConversations(userId);
  }

  if (exportType !== 'textOnly') {
    payload.mediaUrls = collectMediaUrlsFromPayload(payload, userId);
    Object.defineProperty(payload, '_mediaAuthorizedConversationIds', {
      value: (payload.conversations || [])
        .map((conversation) => conversation.conversationId)
        .filter((conversationId) => typeof conversationId === 'string' && conversationId.trim().length > 0),
      enumerable: false
    });
  }

  if (exportType === 'mediaOnly') {
    // Keep output lightweight and privacy-friendly.
    delete payload.moments;
    delete payload.stories;
    delete payload.conversations;
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
    ['saved_moments', payload.savedMoments]
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
  return [
    '# Moments Data Export',
    '',
    `Generated at: ${now}`,
    `Format requested: ${requestedFormat}`,
    `Export type: ${exportType}`,
    '',
    'Included:',
    '- export.json (full structured data)',
    '- meta.json (metadata)',
    '- conversations/*.json (direct messages with best-effort decrypted text)',
    '- nova/*.json (Nova conversations/titles; encrypted text when key is unavailable server-side)',
    '- media/* (downloaded media files when requested and reachable)',
    '- csv/*.csv (if CSV format was requested)',
    ''
  ].join('\n');
}

async function buildExportZipBuffer(payload, requestedFormat, exportType, userId) {
  const zip = new JSZip();
  zip.file('export.json', JSON.stringify(payload, null, 2));
  zip.file('meta.json', JSON.stringify(payload.exportInfo || {}, null, 2));
  zip.file('README.txt', buildReadmeContent(payload, requestedFormat, exportType));

  for (const conversation of payload.conversations || []) {
    const fileId = sanitizeFileName(conversation.conversationId || 'conversation');
    zip.file(`conversations/${fileId}.json`, JSON.stringify(conversation, null, 2));
  }

  if (payload.nova) {
    zip.file('nova/titles.json', JSON.stringify(payload.nova.titles || [], null, 2));
    zip.file('nova/conversations.json', JSON.stringify(payload.nova.conversations || [], null, 2));
  }

  if (String(requestedFormat || '').toLowerCase() === 'csv') {
    const csvFiles = buildCsvFiles(payload);
    for (const csvFile of csvFiles) {
      zip.file(csvFile.path, csvFile.content);
    }
  }

  if (exportType !== 'textOnly') {
    const authorizedConversationIds = Array.isArray(payload._mediaAuthorizedConversationIds)
      ? payload._mediaAuthorizedConversationIds
      : (payload.conversations || [])
        .map((conversation) => conversation.conversationId)
        .filter((conversationId) => typeof conversationId === 'string' && conversationId.trim().length > 0);
    const mediaManifest = await addMediaFilesToZip(zip, payload.mediaUrls || [], userId, authorizedConversationIds);
    zip.file('media/manifest.json', JSON.stringify(mediaManifest, null, 2));
  }

  return zip.generateAsync({
    type: 'nodebuffer',
    compression: 'DEFLATE',
    compressionOptions: { level: 6 }
  });
}

module.exports = {
  toSerializable,
  fetchUserSubcollection,
  fetchUserConversations,
  fetchConversationSharedKey,
  decryptChatContent,
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
  addMediaFilesToZip,
  collectMediaUrlsFromPayload,
  buildDataExportPayload,
  escapeCsvCell,
  flattenRow,
  rowsToCsv,
  buildCsvFiles,
  buildReadmeContent,
  buildExportZipBuffer,
};
