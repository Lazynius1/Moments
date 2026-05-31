const { onDocumentCreated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onRequest } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const { defineSecret } = require('firebase-functions/params');
const JSZip = require('jszip');
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { spawn } = require('child_process');
const ffmpegPath = require('ffmpeg-static');

const VIDEO_DOWNLOAD_MAX_BYTES = 250 * 1024 * 1024;
const VIDEO_DOWNLOAD_TIMEOUT_MS = 60 * 1000;
setGlobalOptions({ region: 'europe-southwest1', memory: '256MiB', concurrency: 80, retry: true });
const admin = require('firebase-admin');
admin.initializeApp();

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const SIGHTENGINE_USER = defineSecret('SIGHTENGINE_USER');
const SIGHTENGINE_SECRET = defineSecret('SIGHTENGINE_SECRET');
const GOOGLE_SPEECH_API_KEY = defineSecret('GOOGLE_SPEECH_API_KEY');
const GIPHY_API_KEY = defineSecret('GIPHY_API_KEY');

const GENTLE_REMINDER_VARIANTS = {
  neutralDay: 'neutral_day',
  neutralAvailable: 'neutral_available',
  editorialBeautiful: 'editorial_beautiful',
  editorialYours: 'editorial_yours',
  inactiveAnyMoment: 'inactive_anymoment'
};

const GENTLE_REMINDER_LIMITS = {
  minHoursSinceOpen: 18,
  editorialHoursSinceOpen: 24,
  editorialDaysSinceMoment: 2,
  inactiveDaysSinceMoment: 4,
  cooldownDays: 7,
  responseWindowHours: 24,
  maxPerRollingWeek: 3
};

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

function storageObjectNameFromFirebaseUrl(url, expectedBucketName) {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' || parsed.hostname !== 'firebasestorage.googleapis.com') return null;

    const match = parsed.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
    if (!match) return null;

    const bucketName = decodeURIComponent(match[1]);
    if (bucketName !== expectedBucketName) return null;

    return decodeURIComponent(match[2]);
  } catch (error) {
    return null;
  }
}

function userOwnedVideoObjectNameFromFirebaseUrl(url, userId) {
  const bucket = admin.storage().bucket();
  const objectName = storageObjectNameFromFirebaseUrl(url, bucket.name);
  if (!objectName || !userId) return null;

  const safeUid = String(userId).trim();
  if (!safeUid) return null;

  // New layout: users/{uid}/moments|stories/{contentId}/media/{mediaId}.mp4
  const newMediaMatch = objectName.match(
    new RegExp(`^users/${safeUid}/(moments|stories)/[^/]+/media/[^/]+\\.mp4$`)
  );
  if (newMediaMatch) {
    return objectName;
  }

  // Legacy layout: videos/{uuid}_{uid}.mp4
  if (!objectName.startsWith('videos/')) return null;

  const expectedSuffix = `_${safeUid}.mp4`;
  if (path.posix.dirname(objectName) !== 'videos' || !path.posix.basename(objectName).endsWith(expectedSuffix)) {
    return null;
  }

  return objectName;
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

exports.permanentlyDeleteRecentlyDeletedBatch = onRequest(
  {
    timeoutSeconds: 120,
    memory: '512MiB',
    concurrency: 10
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
    const rawIds = Array.isArray(body.ids) ? body.ids : [];
    const ids = [...new Set(rawIds
      .map((id) => (typeof id === 'string' ? id.trim() : ''))
      .filter(Boolean))]
      .slice(0, 50);

    if (ids.length === 0) {
      res.status(400).json({ error: 'No ids provided' });
      return;
    }

    const db = admin.firestore();
    const recentlyDeletedRefs = ids.map((id) => db.doc(`users/${uid}/recentlyDeleted/${id}`));

    try {
      const docs = await db.getAll(...recentlyDeletedRefs);
      let deletedDocuments = 0;
      let missing = 0;
      let storageDeleted = 0;
      let storageSkipped = 0;
      const details = [];

      for (const doc of docs) {
        const result = await permanentlyDeleteRecentlyDeletedDoc(doc);
        if (result.status === 'missing') {
          missing += 1;
          details.push({ id: result.id, status: 'missing' });
          continue;
        }

        deletedDocuments += result.deletedDocuments;
        storageDeleted += result.storageDeleted;
        storageSkipped += result.storageSkipped;
        details.push({
          id: result.id,
          type: result.type,
          status: 'deleted',
          storageDeleted: result.storageDeleted,
          storageSkipped: result.storageSkipped
        });
      }

      console.log(
        `✅ permanentlyDeleteRecentlyDeletedBatch: uid=${uid}, docs=${deletedDocuments}, missing=${missing}, storageDeleted=${storageDeleted}, storageSkipped=${storageSkipped}`
      );
      res.status(200).json({ deletedDocuments, missing, storageDeleted, storageSkipped, details });
    } catch (error) {
      console.error('❌ permanentlyDeleteRecentlyDeletedBatch error:', error);
      res.status(500).json({ error: 'Permanent delete failed', details: error.message });
    }
  }
);

exports.cleanExpiredRecentlyDeleted = onSchedule(
  {
    schedule: '15 3 * * *',
    timeZone: 'Europe/Madrid',
    region: 'us-central1',
    timeoutSeconds: 540,
    memory: '512MiB',
    concurrency: 1
  },
  async () => {
    const db = admin.firestore();
    const retentionDays = 30;
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000)
    );
    const batchLimit = 100;
    const maxBatches = 20;
    let batches = 0;
    let deletedDocuments = 0;
    let storageDeleted = 0;
    let storageSkipped = 0;
    let failed = 0;

    try {
      while (batches < maxBatches) {
        const snapshot = await db
          .collectionGroup('recentlyDeleted')
          .where('deletedAt', '<', cutoff)
          .limit(batchLimit)
          .get();

        if (snapshot.empty) break;

        batches += 1;
        for (const doc of snapshot.docs) {
          try {
            const result = await permanentlyDeleteRecentlyDeletedDoc(doc);
            deletedDocuments += result.deletedDocuments;
            storageDeleted += result.storageDeleted;
            storageSkipped += result.storageSkipped;
          } catch (error) {
            failed += 1;
            console.error(`❌ cleanExpiredRecentlyDeleted failed for ${doc.ref.path}:`, error);
          }
        }

        if (snapshot.size < batchLimit) break;
      }

      console.log(
        `✅ cleanExpiredRecentlyDeleted: deleted=${deletedDocuments}, storageDeleted=${storageDeleted}, storageSkipped=${storageSkipped}, failed=${failed}, batches=${batches}`
      );
    } catch (error) {
      console.error('❌ cleanExpiredRecentlyDeleted error:', error);
    }
  }
);

exports.processMomentVideos = onDocumentCreated(
  {
    document: 'users/{userId}/moments/{momentId}',
    memory: '2GiB',
    timeoutSeconds: 540,
    concurrency: 1,
    retry: false
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const { userId, momentId } = event.params;
    const momentRef = snap.ref;
    const data = snap.data() || {};
    const mediaItems = Array.isArray(data.mediaItems) ? data.mediaItems : [];
    const pendingIndexes = mediaItems
      .map((item, index) => ({ item, index }))
      .filter(({ item }) => item && item.type === 'video' && item.videoProcessingStatus === 'pending' && item.url);

    if (pendingIndexes.length === 0) return;

    let updatedItems = mediaItems.map((item, index) => {
      if (pendingIndexes.some((entry) => entry.index === index)) {
        return {
          ...item,
          originalVideoUrl: item.originalVideoUrl || item.url,
          videoProcessingStatus: 'processing'
        };
      }
      return item;
    });

    const processingLegacyFields = buildLegacyMomentMediaFields(updatedItems);
    await momentRef.update({
      mediaItems: updatedItems,
      ...processingLegacyFields,
      videoProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    for (const { item, index } of pendingIndexes) {
      try {
        const processed = await transcodeMomentVideo({ userId, momentId, mediaItem: item });
        const originalVideoUrl = item.originalVideoUrl || item.url;
        const originalDeleted = await deleteOriginalMomentVideoIfSafe({
          originalUrl: originalVideoUrl,
          processedUrl: processed.url,
          userId
        });

        updatedItems[index] = {
          ...updatedItems[index],
          url: processed.url,
          videoVariants: processed.videoVariants || null,
          originalVideoUrl: originalDeleted ? null : originalVideoUrl,
          videoFileSize: processed.fileSize,
          videoProcessingStatus: 'ready',
          originalVideoDeletedAt: originalDeleted ? admin.firestore.Timestamp.now() : null,
          videoProcessingError: null
        };
      } catch (error) {
        console.error(`processMomentVideos failed for ${userId}/${momentId}/${item.id}`, error);
        updatedItems[index] = {
          ...updatedItems[index],
          originalVideoUrl: item.originalVideoUrl || item.url,
          videoProcessingStatus: 'failed',
          videoProcessingError: error.message || 'Video processing failed'
        };
      }
    }

    const finalLegacyFields = buildLegacyMomentMediaFields(updatedItems);
    await momentRef.update({
      mediaItems: updatedItems,
      ...finalLegacyFields,
      videoProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
  }
);

exports.processStoryVideos = onDocumentCreated(
  {
    document: 'users/{userId}/stories/{storyId}',
    memory: '2GiB',
    timeoutSeconds: 540,
    concurrency: 1,
    retry: false
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const { userId, storyId } = event.params;
    const storyRef = snap.ref;
    const data = snap.data() || {};
    const mediaItem = data.mediaItem || {};

    if (
      mediaItem.type !== 'video' ||
      mediaItem.videoProcessingStatus !== 'pending' ||
      !mediaItem.url
    ) {
      return;
    }

    const originalVideoUrl = mediaItem.originalVideoUrl || mediaItem.url;

    await storyRef.update({
      'mediaItem.originalVideoUrl': originalVideoUrl,
      'mediaItem.videoProcessingStatus': 'processing',
      videoProcessingStatus: 'processing',
      videoProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    try {
      const processed = await transcodeStoryVideo({
        userId,
        uploadId: storyId,
        segmentId: mediaItem.id || 'single',
        temporaryUrl: originalVideoUrl
      });

      const originalDeleted = await deleteStorageUrlIfSafe({
        url: originalVideoUrl,
        userId
      });

      await storyRef.update({
        'mediaItem.url': processed.url,
        'mediaItem.originalVideoUrl': originalDeleted ? null : originalVideoUrl,
        'mediaItem.videoFileSize': processed.fileSize,
        'mediaItem.videoProcessingStatus': 'ready',
        'mediaItem.originalVideoDeletedAt': originalDeleted ? admin.firestore.Timestamp.now() : null,
        'mediaItem.videoProcessingError': null,
        videoUrl: processed.url,
        videoFileSize: processed.fileSize,
        videoProcessingStatus: 'ready',
        videoProcessingError: null,
        videoProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } catch (error) {
      console.error(`processStoryVideos failed for ${userId}/${storyId}`, error);
      await storyRef.update({
        'mediaItem.originalVideoUrl': originalVideoUrl,
        'mediaItem.videoProcessingStatus': 'failed',
        'mediaItem.videoProcessingError': error.message || 'Story video processing failed',
        videoProcessingStatus: 'failed',
        videoProcessingError: error.message || 'Story video processing failed',
        videoProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }
  }
);

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
    payload.connections = await fetchUserSubcollection(userId, 'connections');
    payload.admirers = await fetchUserSubcollection(userId, 'admirers');
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
    ['connections', payload.connections],
    ['admirers', payload.admirers],
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

const RECENT_AUTH_MAX_AGE_SECONDS = 5 * 60;

async function verifyFirebaseAuth(req, res, options = {}) {
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
    const decoded = await admin.auth().verifyIdToken(idToken, options.checkRevoked === true);

    if (options.requireRecentAuth === true) {
      const maxAgeSeconds = options.maxAuthAgeSeconds || RECENT_AUTH_MAX_AGE_SECONDS;
      const authTimeSeconds = Number(decoded.auth_time);
      const nowSeconds = Math.floor(Date.now() / 1000);

      if (!Number.isFinite(authTimeSeconds) || nowSeconds - authTimeSeconds > maxAgeSeconds) {
        res.status(401).json({ error: 'Recent authentication required' });
        return null;
      }
    }

    return decoded.uid;
  } catch (error) {
    res.status(401).json({ error: 'Unauthorized' });
    return null;
  }
}

const INCOGNITO_DAILY_BUDGET_SECONDS = 30 * 60;

function normalizeTimeZoneIdentifier(timeZoneIdentifier) {
  if (typeof timeZoneIdentifier !== 'string') return 'UTC';
  const trimmed = timeZoneIdentifier.trim();
  if (!trimmed) return 'UTC';

  try {
    Intl.DateTimeFormat('en-US', { timeZone: trimmed }).format(new Date());
    return trimmed;
  } catch (error) {
    return 'UTC';
  }
}

function timestampToDate(value) {
  if (!value) return null;
  if (value instanceof admin.firestore.Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value.toDate === 'function') return value.toDate();

  if (typeof value === 'string' || typeof value === 'number') {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  return null;
}

function getDateKeyForTimeZone(date, timeZoneIdentifier) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: timeZoneIdentifier,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  });

  const parts = formatter.formatToParts(date);
  const year = parts.find((part) => part.type === 'year')?.value || '1970';
  const month = parts.find((part) => part.type === 'month')?.value || '01';
  const day = parts.find((part) => part.type === 'day')?.value || '01';
  return `${year}-${month}-${day}`;
}

function buildDefaultIncognitoState(timeZoneIdentifier, now) {
  return {
    remainingSeconds: INCOGNITO_DAILY_BUDGET_SECONDS,
    isActive: false,
    lastResetDate: getDateKeyForTimeZone(now, timeZoneIdentifier),
    sessionStartedAt: null,
    sessionExpectedEndTime: null,
    timezoneIdentifier: timeZoneIdentifier,
    lastUpdatedAt: now,
    dailyBudgetSeconds: INCOGNITO_DAILY_BUDGET_SECONDS
  };
}

function resolveIncognitoState(rawIncognito, timeZoneIdentifier, now) {
  const defaultState = buildDefaultIncognitoState(timeZoneIdentifier, now);
  const source = rawIncognito && typeof rawIncognito === 'object' ? rawIncognito : {};

  const lastResetDate = typeof source.lastResetDate === 'string' ? source.lastResetDate : '';
  if (!lastResetDate || lastResetDate !== defaultState.lastResetDate) {
    return defaultState;
  }

  const rawRemaining = Number.isFinite(source.remainingSeconds)
    ? Math.max(0, Math.floor(source.remainingSeconds))
    : INCOGNITO_DAILY_BUDGET_SECONDS;
  const rawIsActive = source.isActive === true;
  const startedAt = timestampToDate(source.sessionStartedAt);
  const expectedEnd = timestampToDate(source.sessionExpectedEndTime);

  if (!rawIsActive) {
    return {
      ...defaultState,
      remainingSeconds: Math.min(rawRemaining, INCOGNITO_DAILY_BUDGET_SECONDS),
      isActive: false,
      sessionStartedAt: null,
      sessionExpectedEndTime: null
    };
  }

  if (!expectedEnd) {
    return {
      ...defaultState,
      remainingSeconds: Math.min(rawRemaining, INCOGNITO_DAILY_BUDGET_SECONDS),
      isActive: false,
      sessionStartedAt: null,
      sessionExpectedEndTime: null
    };
  }

  const remainingSeconds = Math.max(0, Math.floor((expectedEnd.getTime() - now.getTime()) / 1000));
  if (remainingSeconds <= 0) {
    return {
      ...defaultState,
      remainingSeconds: 0,
      isActive: false,
      sessionStartedAt: null,
      sessionExpectedEndTime: null
    };
  }

  return {
    ...defaultState,
    remainingSeconds,
    isActive: true,
    sessionStartedAt: startedAt || now,
    sessionExpectedEndTime: expectedEnd
  };
}

function persistableIncognitoState(state, nowOverride = null) {
  const lastUpdatedAt = nowOverride || state.lastUpdatedAt || new Date();

  return {
    remainingSeconds: state.remainingSeconds,
    isActive: state.isActive,
    lastResetDate: state.lastResetDate,
    sessionStartedAt: state.sessionStartedAt
      ? admin.firestore.Timestamp.fromDate(state.sessionStartedAt)
      : null,
    sessionExpectedEndTime: state.sessionExpectedEndTime
      ? admin.firestore.Timestamp.fromDate(state.sessionExpectedEndTime)
      : null,
    timezoneIdentifier: state.timezoneIdentifier,
    lastUpdatedAt: admin.firestore.Timestamp.fromDate(lastUpdatedAt)
  };
}

function incognitoStateNeedsPersistence(rawIncognito, resolvedState) {
  if (!rawIncognito || typeof rawIncognito !== 'object') return true;

  const rawExpectedEnd = timestampToDate(rawIncognito.sessionExpectedEndTime)?.getTime() || null;
  const rawStartedAt = timestampToDate(rawIncognito.sessionStartedAt)?.getTime() || null;
  const resolvedExpectedEnd = resolvedState.sessionExpectedEndTime?.getTime() || null;
  const resolvedStartedAt = resolvedState.sessionStartedAt?.getTime() || null;

  return (
    rawIncognito.remainingSeconds !== resolvedState.remainingSeconds ||
    rawIncognito.isActive !== resolvedState.isActive ||
    rawIncognito.lastResetDate !== resolvedState.lastResetDate ||
    rawIncognito.timezoneIdentifier !== resolvedState.timezoneIdentifier ||
    rawExpectedEnd !== resolvedExpectedEnd ||
    rawStartedAt !== resolvedStartedAt
  );
}

function serializeIncognitoStateForResponse(state) {
  return {
    remainingSeconds: state.remainingSeconds,
    isActive: state.isActive,
    lastResetDate: state.lastResetDate,
    sessionStartedAt: state.sessionStartedAt ? state.sessionStartedAt.toISOString() : null,
    sessionExpectedEndTime: state.sessionExpectedEndTime ? state.sessionExpectedEndTime.toISOString() : null,
    timezoneIdentifier: state.timezoneIdentifier,
    lastUpdatedAt: state.lastUpdatedAt ? state.lastUpdatedAt.toISOString() : null,
    dailyBudgetSeconds: state.dailyBudgetSeconds
  };
}

async function runIncognitoTransition({ userId, requestedAction, timeZoneIdentifier }) {
  const db = admin.firestore();
  const userRef = db.collection('users').doc(userId);
  const now = new Date();
  const normalizedTimeZone = normalizeTimeZoneIdentifier(timeZoneIdentifier);

  return db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) {
      return {
        statusCode: 404,
        body: { error: 'User not found' }
      };
    }

    const userData = userSnap.data() || {};
    const rawIncognito = userData.incognito || null;
    const effectiveTimeZone = normalizeTimeZoneIdentifier(
      normalizedTimeZone || rawIncognito?.timezoneIdentifier || 'UTC'
    );

    let nextState = resolveIncognitoState(rawIncognito, effectiveTimeZone, now);
    let statusCode = 200;
    let success = true;
    let reason = null;

    switch (requestedAction) {
      case 'get': {
        break;
      }
      case 'activate':
      case 'resume': {
        if (nextState.remainingSeconds <= 0) {
          success = false;
          reason = 'exhausted';
          statusCode = 409;
          break;
        }

        if (!nextState.isActive) {
          nextState = {
            ...nextState,
            isActive: true,
            sessionStartedAt: now,
            sessionExpectedEndTime: new Date(now.getTime() + (nextState.remainingSeconds * 1000)),
            lastUpdatedAt: now
          };
        }
        break;
      }
      case 'pause': {
        if (nextState.isActive) {
          nextState = {
            ...nextState,
            isActive: false,
            sessionStartedAt: null,
            sessionExpectedEndTime: null,
            lastUpdatedAt: now
          };
        }
        break;
      }
      default: {
        return {
          statusCode: 400,
          body: { error: 'Invalid action' }
        };
      }
    }

    if (incognitoStateNeedsPersistence(rawIncognito, nextState) || requestedAction !== 'get') {
      tx.set(userRef, { incognito: persistableIncognitoState(nextState, now) }, { merge: true });
    }

    return {
      statusCode,
      body: {
        success,
        reason,
        state: serializeIncognitoStateForResponse({
          ...nextState,
          lastUpdatedAt: now
        })
      }
    };
  });
}

function createIncognitoHandler(requestedAction) {
  return onRequest(
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

      const userId = await verifyFirebaseAuth(req, res);
      if (!userId) return;

      const body = parseJsonBody(req);
      const timeZoneIdentifier = typeof body.timezoneIdentifier === 'string'
        ? body.timezoneIdentifier
        : 'UTC';

      try {
        const result = await runIncognitoTransition({
          userId,
          requestedAction,
          timeZoneIdentifier
        });

        res.status(result.statusCode).json(result.body);
      } catch (error) {
        console.error(`${requestedAction}Incognito error:`, error);
        res.status(500).json({ error: 'Failed to update incognito state' });
      }
    }
  );
}

exports.getIncognitoState = createIncognitoHandler('get');
exports.activateIncognito = createIncognitoHandler('activate');
exports.pauseIncognito = createIncognitoHandler('pause');
exports.resumeIncognito = createIncognitoHandler('resume');

exports.onDataExportRequestCreated = onDocumentCreated({
  document: 'users/{userId}/dataExportRequests/{requestId}',
  timeoutSeconds: 540,
  memory: '1GiB'
}, async (event) => {
  const userId = event.params.userId;
  const requestId = event.params.requestId;
  const requestRef = admin.firestore().doc(`users/${userId}/dataExportRequests/${requestId}`);

  const requestData = event.data?.data() || {};
  const status = requestData.status || 'pending';
  if (status !== 'pending') return;

  const exportType = requestData.exportType || 'complete';
  const requestedFormat = requestData.format || 'json';

  try {
    await requestRef.update({
      status: 'processing',
      progress: 0.1,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    });

    const payload = await buildDataExportPayload(userId, exportType, requestedFormat);

    await requestRef.update({
      status: 'uploading',
      progress: 0.75,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    });

    const now = new Date();
    const stamp = now.toISOString().replace(/[:.]/g, '-');
    const objectName = `exports/${userId}/moments_export_${stamp}.zip`;
    const file = admin.storage().bucket().file(objectName);
    const body = await buildExportZipBuffer(payload, requestedFormat, exportType, userId);

    await file.save(body, {
      resumable: false,
      metadata: {
        contentType: 'application/zip',
        cacheControl: 'private, max-age=0, no-cache'
      }
    });

    const expiresAt = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
    const [downloadURL] = await file.getSignedUrl({
      action: 'read',
      expires: expiresAt
    });

    await requestRef.update({
      status: 'ready',
      progress: 1.0,
      downloadURL,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      expirationDate: admin.firestore.Timestamp.fromDate(expiresAt),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    });

    await admin.firestore()
      .collection('users')
      .doc(userId)
      .collection('notifications')
      .add({
        type: 'data_export_ready',
        // Sin texto fijo: el cliente muestra la cadena localizada
        // (notifications.message.dataExportReady) según el idioma del dispositivo.
        message: '',
        downloadURL,
        senderId: 'system',
        senderUsername: 'Moments',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isPending: true,
        isRead: false
      });

    console.log(`✅ data export ready: user=${userId} request=${requestId}`);
  } catch (error) {
    console.error(`❌ data export failed: user=${userId} request=${requestId}`, error);
    await requestRef.update({
      status: 'failed',
      progress: 0.0,
      errorMessage: error?.message || 'Export failed',
      lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    });
  }
});

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

async function reconcileMutualConnection(userId, followerId, userData, followerData) {
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
    const momentPreviewUrl = pickMomentPreviewUrl(momentData);

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
    const fcmToken = momentOwnerData.fcmToken || null;
    const shouldSendPush = Boolean(fcmToken) && !isDoNotDisturbActive(momentOwnerData);

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
    const reactionTx = await admin.firestore().runTransaction(async (tx) => {
      const [momentSnap, reactionSnap] = await Promise.all([tx.get(momentRef), tx.get(reactionRef)]);
      const alreadyProcessed = reactionSnap.exists && reactionSnap.get('processed') === true;
      if (!momentSnap.exists) {
        throw new Error('Moment doc missing');
      }
      const currentCount = momentSnap.get('reactionCount') || 0;
      if (alreadyProcessed) {
        return { newReactionCount: currentCount, alreadyProcessed: true };
      }
      tx.update(momentRef, { reactionCount: admin.firestore.FieldValue.increment(1) });
      tx.update(reactionRef, { processed: true });
      return { newReactionCount: currentCount + 1, alreadyProcessed: false };
    });
    if (reactionTx.alreadyProcessed) return null;
    const newReactionCount = reactionTx.newReactionCount;

    const isSilencedByMuteSettings = shouldSilenceNotificationForUser(momentOwnerData, {
      senderId: reaction.userId,
      candidateTexts: [reaction.reactionType, momentData?.content]
    });
    if (isSilencedByMuteSettings) {
      return null;
    }

    // ✅ TÍTULO DINÁMICO basado en número de reacciones
    const username = reacterData.username || 'Alguien';

    const reactionNotificationId = `reaction_${momentId}`;
    const reactionNotificationRef = admin.firestore().doc(`users/${userId}/notifications/${reactionNotificationId}`);
    const legacyPendingSnap = await admin.firestore()
      .collection(`users/${userId}/notifications`)
      .where('type', '==', 'reaction')
      .where('momentId', '==', momentId)
      .where('isPending', '==', true)
      .get();
    const legacyPendingDocs = legacyPendingSnap.docs.filter(doc => doc.id !== reactionNotificationId);
    const totalReactionCount = Math.max(1, Number(newReactionCount || 1));
    const pendingReactionCount = totalReactionCount;

    // Determinar claves de localización
    let titleLocKey, titleLocArgs, bodyLocKey, bodyLocArgs;
    if (pendingReactionCount === 1) {
      titleLocKey = 'notification.momentReaction.single.title';
      titleLocArgs = [username, emoji];
      bodyLocKey = 'notification.momentReaction.single.body';
      bodyLocArgs = [];
    } else {
      titleLocKey = 'notification.momentReaction.multiple.title';
      titleLocArgs = [username, String(pendingReactionCount - 1)];
      bodyLocKey = 'notification.momentReaction.multiple.body';
      bodyLocArgs = [String(pendingReactionCount)];
    }

    // ✅ Obtener conteos actualizados para el Widget
    const counts = await getUnreadCounts(userId, {
      type: 'notification',
      notificationType: 'momentReaction',
      notificationId: reactionNotificationId
    });

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
        mediaUrl: momentPreviewUrl || '',
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
            'summary-arg-count': pendingReactionCount
          }
        }
      }
    };

    if (shouldSendPush) {
      try {
        await admin.messaging().send(message);
        console.log(`✅ Notificación enviada: ${username} -> ${momentOwnerData.username} (${reaction.reactionType}) - Pending: ${pendingReactionCount}`);
      } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
          await removeInvalidToken(userId, fcmToken);
        }
        throw error;
      }
    }

    // ✅ Una notificación agregada por momento
    await reactionNotificationRef.set({
      type: 'reaction',
      senderId: reaction.userId,
      senderUsername: username,
      senderProfileImage: reacterData.profileImagePath || '',
      momentId: momentId,
      reactionType: reaction.reactionType,
      reactionCount: pendingReactionCount,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isPending: true
    }, { merge: true });

    // Limpieza de migración: eliminar documentos legacy para este momento.
    if (legacyPendingDocs.length > 0) {
      const batch = admin.firestore().batch();
      legacyPendingDocs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
    }

  } catch (error) {
    console.error('❌ Error sending reaction notification:', error);
  }
});

exports.onHiddenLayerDiscoveryCreated = onDocumentCreated(
  'users/{userId}/moments/{momentId}/hiddenLayers/{layerId}/discoveries/{viewerId}',
  async (event) => {
    const { userId, momentId, layerId, viewerId } = event.params;
    const discoveryData = event.data?.data() || {};
    const discoveredAt = discoveryData.discoveredAt || admin.firestore.FieldValue.serverTimestamp();

    const db = admin.firestore();
    const layerRef = db
      .collection('users')
      .doc(userId)
      .collection('moments')
      .doc(momentId)
      .collection('hiddenLayers')
      .doc(layerId);

    await layerRef.set({
      discoverCount: admin.firestore.FieldValue.increment(1),
      uniqueDiscovererCount: admin.firestore.FieldValue.increment(1),
      lastDiscoveredAt: discoveredAt
    }, { merge: true });

    const momentDiscovererRef = db
      .collection('users')
      .doc(userId)
      .collection('moments')
      .doc(momentId)
      .collection('hiddenLayerDiscoverers')
      .doc(viewerId);

    const momentDiscovererSnap = await momentDiscovererRef.get();
    if (!momentDiscovererSnap.exists) {
      await momentDiscovererRef.set({
        viewerId,
        username: discoveryData.username || null,
        profileImagePath: discoveryData.profileImagePath || null,
        lastDiscoveredAt: discoveredAt
      }, { merge: true });
    }
  }
);

// ✅ ACTUALIZAR BADGE SILENCIOSAMENTE
// ✅ #1 OPTIMIZADO: Una sola Cloud Function para todas las notificaciones creadas
// Antes habían 3 funciones disparándose en paralelo (updateBadge, onMentionNotification, onPhotoTagNotification)
// Ahora un solo onDocumentCreated que hace switch por tipo.
exports.onNotificationCreated = onDocumentCreated('users/{userId}/notifications/{notificationId}', async (event) => {
  const snap = event.data;
  const { userId, notificationId } = event.params;
  const notification = snap.data();

  try {
    const userDoc = await admin.firestore().doc(`users/${userId}`).get();
    if (!userDoc.exists) return null;
    const userData = userDoc.data();
    if (!validateUserData(userData)) return null;

    // Dispatch según tipo
    switch (notification.type) {
      case 'mention':
        await handleMentionPush(userId, notificationId, notification, userData);
        break;
      case 'photoTag':
        await handlePhotoTagPush(userId, notificationId, notification, userData);
        break;
      case 'comment':
        if (notification.mentionContext === 'reply') {
          await handleReplyPush(userId, notificationId, notification, userData);
        } else {
          await handleBadgeUpdate(userId, userData);
        }
        break;
      case 'mediaModeration':
        await handleModerationPush(userId, notificationId, notification, userData);
        break;
      default:
        // Badge update silencioso para todos los demás tipos
        await handleBadgeUpdate(userId, userData);
        break;
    }
  } catch (error) {
    console.error('❌ Error en onNotificationCreated:', error);
  }
});

// Helper: Actualizar badge (antes era exports.updateBadge entero)
async function handleBadgeUpdate(userId, userData) {
  if (!userData.fcmToken || isDoNotDisturbActive(userData)) return;

  const notifications = await admin.firestore()
    .collection(`users/${userId}/notifications`)
    .where('isPending', '==', true)
    .get();

  const badgeCount = notifications.size;
  const message = {
    token: userData.fcmToken,
    data: { silent: 'true' },
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
}

// 🛡️ Helper: Push notification para moderación de contenido multimedia
async function handleModerationPush(userId, notificationId, notification, userData) {
  const fcmToken = userData.fcmToken || null;
  if (!fcmToken || isDoNotDisturbActive(userData)) return;

  const moderationType = notification.moderationType || 'full';
  const moderationScope = notification.moderationScope || 'post';
  const moderatedMediaCount = notification.moderatedMediaCount || 0;
  const momentId = notification.momentId || '';
  const storyId = notification.storyId || '';

  let titleLocKey, bodyLocKey, bodyLocArgs;

  if (moderationScope === 'storySticker') {
    titleLocKey = 'notification.moderation.storySticker.partial.title';
    if (moderatedMediaCount === 1) {
      bodyLocKey = 'notification.moderation.storySticker.partial.body.one';
      bodyLocArgs = [];
    } else {
      bodyLocKey = 'notification.moderation.storySticker.partial.body.other';
      bodyLocArgs = [String(moderatedMediaCount)];
    }
  } else if (moderationScope === 'postHiddenLayer') {
    titleLocKey = 'notification.moderation.postHiddenLayer.partial.title';
    if (moderatedMediaCount === 1) {
      bodyLocKey = 'notification.moderation.postHiddenLayer.partial.body.one';
      bodyLocArgs = [];
    } else {
      bodyLocKey = 'notification.moderation.postHiddenLayer.partial.body.other';
      bodyLocArgs = [String(moderatedMediaCount)];
    }
  } else {
    const scopePrefix = moderationScope === 'story' ? 'notification.moderation.story' : 'notification.moderation';
    if (moderationType === 'partial') {
      titleLocKey = `${scopePrefix}.partial.title`;
      bodyLocKey = `${scopePrefix}.partial.body`;
      bodyLocArgs = [String(moderatedMediaCount)];
    } else {
      titleLocKey = `${scopePrefix}.full.title`;
      bodyLocKey = `${scopePrefix}.full.body`;
      bodyLocArgs = [];
    }
  }

  // Obtener conteos para badge
  const counts = await getUnreadCounts(userId, {
    type: 'notification',
    notificationType: 'mediaModeration',
    notificationId: notificationId
  });

  const message = {
    token: fcmToken,
    data: {
      type: 'media_moderation',
      momentId: momentId,
      storyId: storyId,
      moderationType: moderationType,
      moderationScope: moderationScope,
      moderatedMediaCount: String(moderatedMediaCount),
      unreadMessages: String(counts.unreadMessages),
      unreadNotifications: String(counts.unreadNotifications),
    },
    apns: {
      headers: {
        'apns-collapse-id': `moderation_${storyId || momentId || notificationId}`
      },
      payload: {
        aps: {
          alert: {
            'title-loc-key': titleLocKey,
            'loc-key': bodyLocKey,
            'loc-args': bodyLocArgs
          },
          badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
          sound: 'default',
          'mutable-content': 1,
          'thread-id': `moderation_${storyId || momentId || notificationId}`
        }
      }
    }
  };

  try {
    await admin.messaging().send(message);
    console.log(`✅ Push de moderación enviada a ${userData.username} (${moderationType})`);
  } catch (error) {
    if (error.code === 'messaging/registration-token-not-registered') {
      await removeInvalidToken(userId, fcmToken);
    }
    console.error('❌ Error enviando push de moderación:', error);
  }
}

async function claimProcessingLock(docRef, options = {}) {
  const processedField = options.processedField || 'processed';
  const processingField = options.processingField || 'processingUntil';
  const lockMs = typeof options.lockMs === 'number' ? options.lockMs : 120000;

  const nowMs = Date.now();
  const lockUntil = admin.firestore.Timestamp.fromMillis(nowMs + lockMs);

  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    if (!snap.exists) return false;
    if (snap.get(processedField) === true) return false;

    const processingUntil = snap.get(processingField);
    if (processingUntil && typeof processingUntil.toMillis === 'function' && processingUntil.toMillis() > nowMs) {
      return false;
    }

    tx.update(docRef, { [processingField]: lockUntil });
    return true;
  });
}

async function markProcessingDone(docRef, options = {}) {
  const processedField = options.processedField || 'processed';
  const processingField = options.processingField || 'processingUntil';
  await docRef.set({
    [processedField]: true,
    processedAt: admin.firestore.FieldValue.serverTimestamp(),
    [processingField]: admin.firestore.FieldValue.delete()
  }, { merge: true });
}

async function releaseProcessingLock(docRef, options = {}) {
  const processingField = options.processingField || 'processingUntil';
  await docRef.set({
    [processingField]: admin.firestore.FieldValue.delete()
  }, { merge: true });
}

// Helper: Push de mención (antes era exports.onMentionNotification entero)
async function handleMentionPush(userId, notificationId, notification, userData) {
  const senderDoc = await admin.firestore().doc(`users/${notification.senderId}`).get();
  if (!senderDoc.exists) return;
  const senderData = senderDoc.data();
  if (!validateUserData(senderData) || !senderData.isActive || !userData.isActive) return;

  const mentionRef = admin.firestore().doc(`users/${userId}/notifications/${notificationId}`);
  const isSilenced = shouldSilenceNotificationForUser(userData, {
    senderId: notification.senderId,
    candidateTexts: [notification.text, notification.commentText, notification.content, notification.caption]
  });
  if (isSilenced) {
    await mentionRef.delete().catch(() => null);
    return;
  }

  const fcmToken = userData.fcmToken;
  const lockAcquired = await claimProcessingLock(mentionRef, {
    processedField: 'processed',
    processingField: 'processingUntil'
  });
  if (!lockAcquired) return;

  try {
    if (!fcmToken || isDoNotDisturbActive(userData)) {
      await markProcessingDone(mentionRef, {
        processedField: 'processed',
        processingField: 'processingUntil'
      });
      return;
    }

    const mentionContext = notification.mentionContext
      || (notification.storyId ? 'story' : (notification.commentId ? 'comment' : 'moment'));

    let contentType = 'contenido';
    let targetType = 'moment';
    let targetId = notification.momentId;
    if (mentionContext === 'story' && notification.storyId) {
      contentType = 'historia';
      targetType = 'story';
      targetId = notification.storyId;
    } else if (mentionContext === 'comment' && notification.momentId) {
      contentType = 'comentario';
      targetType = 'comment';
      targetId = notification.commentId || notification.momentId;
    } else if (notification.momentId) {
      contentType = 'momento';
      targetType = 'moment';
      targetId = notification.momentId;
    }

    const mentionTitleKey = mentionContext === 'story'
      ? 'notification.mention.story.title'
      : mentionContext === 'comment'
        ? (notification.targetAuthorUsername
          ? 'notification.mention.comment.withAuthor.title'
          : 'notification.mention.comment.title')
        : mentionContext === 'moment'
          ? 'notification.mention.moment.title'
          : 'notification.mention.title';
    const mentionTitleArgs = mentionTitleKey === 'notification.mention.title'
      ? [senderData.username, contentType]
      : mentionTitleKey === 'notification.mention.comment.withAuthor.title'
        ? [senderData.username, notification.targetAuthorUsername]
      : [senderData.username];

    const counts = await getUnreadCounts(userId, { type: 'notification', notificationType: 'mention' });

    const message = {
      token: fcmToken,
      data: {
        type: 'mention',
        senderId: notification.senderId,
        userId: userId,
        targetType: targetType,
        targetId: targetId,
        mentionContext: mentionContext,
        momentId: notification.momentId || '',
        storyId: notification.storyId || '',
        storyAuthorId: notification.storyAuthorId || notification.targetAuthorId || notification.senderId || '',
        targetAuthorId: notification.targetAuthorId || notification.storyAuthorId || notification.senderId || '',
        targetAuthorUsername: notification.targetAuthorUsername || '',
        commentId: notification.commentId || '',
        senderUsername: senderData.username,
        senderProfileImage: senderData.profileImagePath || '',
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags),
      },
      apns: {
        headers: { 'apns-collapse-id': `mention_${userId}` },
        payload: {
          aps: {
            alert: {
              'title-loc-key': mentionTitleKey,
              'title-loc-args': mentionTitleArgs,
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

    await admin.messaging().send(message);
    await markProcessingDone(mentionRef, {
      processedField: 'processed',
      processingField: 'processingUntil'
    });
    console.log(`✅ Mención push: ${senderData.username} -> ${userData.username} en ${contentType}`);
  } catch (error) {
    await releaseProcessingLock(mentionRef, { processingField: 'processingUntil' }).catch(() => null);
    if (error.code === 'messaging/registration-token-not-registered') {
      await removeInvalidToken(userId, fcmToken);
    }
    throw error;
  }
}

async function handleReplyPush(userId, notificationId, notification, userData) {
  const senderDoc = await admin.firestore().doc(`users/${notification.senderId}`).get();
  if (!senderDoc.exists) return;
  const senderData = senderDoc.data();
  if (!validateUserData(senderData) || !senderData.isActive || !userData.isActive) return;

  const replyRef = admin.firestore().doc(`users/${userId}/notifications/${notificationId}`);
  const isSilenced = shouldSilenceNotificationForUser(userData, {
    senderId: notification.senderId,
    candidateTexts: [notification.reaction, notification.commentText, notification.text, notification.content]
  });
  if (isSilenced) {
    await replyRef.delete().catch(() => null);
    return;
  }

  // Respeta el toggle de comentarios: sin push, pero mantenemos la notificación in-app.
  if (!notificationTypeEnabled(userData, 'comment')) return;

  const fcmToken = userData.fcmToken;
  const lockAcquired = await claimProcessingLock(replyRef, {
    processedField: 'processed',
    processingField: 'processingUntil'
  });
  if (!lockAcquired) return;

  try {
    if (!fcmToken || isDoNotDisturbActive(userData)) {
      await markProcessingDone(replyRef, {
        processedField: 'processed',
        processingField: 'processingUntil'
      });
      return;
    }

    const counts = await getUnreadCounts(userId, { type: 'notification', notificationType: 'reply', notificationId });
    const replyPreview = notification.reaction || notification.commentText || '';

    const message = {
      token: fcmToken,
      data: {
        type: 'moment_comment',
        mentionContext: 'reply',
        senderId: notification.senderId,
        userId,
        momentId: notification.momentId || '',
        momentOwnerId: notification.targetAuthorId || '',
        targetAuthorId: notification.targetAuthorId || '',
        targetAuthorUsername: notification.targetAuthorUsername || '',
        commentId: notification.commentId || '',
        senderUsername: senderData.username,
        senderProfileImage: senderData.profileImagePath || '',
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags),
      },
      apns: {
        headers: { 'apns-collapse-id': `reply_${notification.commentId || notificationId}` },
        payload: {
          aps: {
            alert: replyPreview ? {
              'title-loc-key': 'notification.reply.title',
              'title-loc-args': [senderData.username],
              body: `"${String(replyPreview).substring(0, 80)}${String(replyPreview).length > 80 ? '...' : ''}"`
            } : {
              'title-loc-key': 'notification.reply.title',
              'title-loc-args': [senderData.username]
            },
            badge: Math.max(1, counts.unreadNotifications + counts.unreadMessages),
            sound: 'default',
            'mutable-content': 1,
            'thread-id': `moment_replies_${notification.momentId || userId}`
          }
        }
      }
    };

    await admin.messaging().send(message);
    await markProcessingDone(replyRef, {
      processedField: 'processed',
      processingField: 'processingUntil'
    });
    console.log(`✅ Reply push: ${senderData.username} -> ${userData.username}`);
  } catch (error) {
    await releaseProcessingLock(replyRef, { processingField: 'processingUntil' }).catch(() => null);
    if (error.code === 'messaging/registration-token-not-registered') {
      await removeInvalidToken(userId, fcmToken);
    }
    throw error;
  }
}

// Helper: Push de photo tag (antes era exports.onPhotoTagNotification entero)
async function handlePhotoTagPush(userId, notificationId, notification, userData) {
  const senderDoc = await admin.firestore().doc(`users/${notification.senderId}`).get();
  if (!senderDoc.exists) return;
  const senderData = senderDoc.data();
  if (!validateUserData(senderData) || !senderData.isActive || !userData.isActive) return;

  const tagRef = admin.firestore().doc(`users/${userId}/notifications/${notificationId}`);
  const isSilenced = shouldSilenceNotificationForUser(userData, {
    senderId: notification.senderId,
    candidateTexts: [notification.text, notification.commentText, notification.content, notification.caption]
  });
  if (isSilenced) {
    await tagRef.delete().catch(() => null);
    return;
  }

  const fcmToken = userData.fcmToken;
  const lockAcquired = await claimProcessingLock(tagRef, {
    processedField: 'processed',
    processingField: 'processingUntil'
  });
  if (!lockAcquired) return;

  try {
    if (!fcmToken || isDoNotDisturbActive(userData)) {
      await markProcessingDone(tagRef, {
        processedField: 'processed',
        processingField: 'processingUntil'
      });
      return;
    }

    const counts = await getUnreadCounts(userId, { type: 'notification', notificationType: 'photoTag' });
    const momentTitle = typeof notification.reaction === 'string' ? notification.reaction.trim() : '';
    const titleLocKey = momentTitle
      ? 'notification.photoTag.withTitle.title'
      : 'notification.photoTag.title';
    const titleLocArgs = momentTitle
      ? [senderData.username, momentTitle]
      : [senderData.username];

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
        momentTitle,
        unreadMessages: String(counts.unreadMessages),
        unreadNotifications: String(counts.unreadNotifications),
        unreadEchoes: String(counts.unreadEchoes),
        unreadTags: String(counts.unreadTags),
      },
      apns: {
        headers: { 'apns-collapse-id': `tag_${userId}` },
        payload: {
          aps: {
            alert: {
              'title-loc-key': titleLocKey,
              'title-loc-args': titleLocArgs,
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

    await admin.messaging().send(message);
    await markProcessingDone(tagRef, {
      processedField: 'processed',
      processingField: 'processingUntil'
    });
    console.log(`✅ Photo tag push: ${senderData.username} -> ${userData.username}`);
  } catch (error) {
    await releaseProcessingLock(tagRef, { processingField: 'processingUntil' }).catch(() => null);
    if (error.code === 'messaging/registration-token-not-registered') {
      await removeInvalidToken(userId, fcmToken);
    }
    throw error;
  }
}

// ✅ #6 OPTIMIZADO: Limpieza con collectionGroup (escala sin depender del nº de usuarios)
exports.cleanOldNotifications = onSchedule(
  { schedule: '0 0 * * *', timeZone: 'Europe/Madrid', region: 'us-central1' },
  async () => {
    try {
      const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

      // Usar collectionGroup en vez de iterar user-by-user
      async function deleteBatch() {
        const snapshot = await admin.firestore()
          .collectionGroup('notifications')
          .where('timestamp', '<', thirtyDaysAgo)
          .where('isPending', '==', false)
          .limit(500)
          .get();

        if (snapshot.empty) return 0;

        const batch = admin.firestore().batch();
        snapshot.docs.forEach(doc => batch.delete(doc.ref));
        await batch.commit();

        console.log(`✅ Eliminadas ${snapshot.size} notificaciones antiguas`);
        return snapshot.size;
      }

      // Recursive batching hasta que no queden más
      let totalDeleted = 0;
      let batchSize;
      do {
        batchSize = await deleteBatch();
        totalDeleted += batchSize;
      } while (batchSize === 500);

      console.log(`✅ Limpieza total: ${totalDeleted} notificaciones antiguas eliminadas`);
    } catch (error) {
      console.error('❌ Error en limpieza de notificaciones:', error);
    }
  });

exports.sendDailyGentleReminders = onSchedule(
  { schedule: '0 18 * * *', timeZone: 'Europe/Madrid', region: 'us-central1' },
  async () => {
    const db = admin.firestore();
    const now = new Date();
    const batchSize = 200;
    let lastDoc = null;
    let scanned = 0;
    let sent = 0;
    let updated = 0;

    try {
      do {
        let query = db
          .collection('users')
          .where('isActive', '==', true)
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(batchSize);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const snapshot = await query.get();
        if (snapshot.empty) break;

        for (const doc of snapshot.docs) {
          scanned += 1;
          const userId = doc.id;
          const userData = doc.data() || {};
          const { state, updates } = buildGentleReminderState(userData, now);

          if (Object.keys(updates).length > 0) {
            await doc.ref.update(updates);
            updated += 1;
          }

          if (!userData.fcmToken) continue;
          if (!gentleRemindersEnabled(userData)) continue;
          if (isDoNotDisturbActive(userData)) continue;
          if (!state.lastAppOpenAt) continue;

          const variant = chooseGentleReminderVariant(state, now);
          if (!variant) continue;

          try {
            await sendGentleReminderPush(userId, userData, variant);

            const sentHistory = [...state.gentleReminderSentHistory, now]
              .filter((date) => date instanceof Date)
              .sort((a, b) => a.getTime() - b.getTime());

            await doc.ref.update({
              lastGentleReminderAt: now,
              lastGentleReminderVariant: variant,
              gentleReminderAwaitingResponse: true,
              gentleReminderSentHistory: normalizeReminderHistory(sentHistory, now),
              gentleReminderCooldownUntil: state.gentleReminderCooldownUntil || admin.firestore.FieldValue.delete()
            });

            sent += 1;
          } catch (error) {
            if (error.code === 'messaging/registration-token-not-registered') {
              await removeInvalidToken(userId, userData.fcmToken);
            } else {
              console.error(`❌ Error enviando gentle reminder a ${userId}:`, error);
            }
          }
        }

        lastDoc = snapshot.docs[snapshot.docs.length - 1];
        if (snapshot.size < batchSize) break;
      } while (lastDoc);

      console.log(`✅ Gentle reminders: revisados=${scanned}, enviados=${sent}, reconciliados=${updated}`);
    } catch (error) {
      console.error('❌ Error en gentle reminders:', error);
    }
  });


// 💬 COMENTARIOS EN MOMENTOS
exports.onMomentCommentAdded = onDocumentCreated('users/{userId}/moments/{momentId}/comments/{commentId}', async (event) => {
  const snap = event.data;
  const { userId, momentId, commentId } = event.params;
  const comment = snap.data();

  try {
    if (comment.authorId === userId) return null;

    const [commenterDoc, momentOwnerDoc, momentDoc] = await Promise.all([
      admin.firestore().doc(`users/${comment.authorId}`).get(),
      admin.firestore().doc(`users/${userId}`).get(),
      admin.firestore().doc(`users/${userId}/moments/${momentId}`).get()
    ]);

    if (!commenterDoc.exists || !momentOwnerDoc.exists) return null;

    const commenterData = commenterDoc.data();
    const momentOwnerData = momentOwnerDoc.data();
    const momentData = momentDoc.exists ? momentDoc.data() : null;
    const momentPreviewUrl = pickMomentPreviewUrl(momentData);

    if (!validateUserData(commenterData) || !validateUserData(momentOwnerData)) {
      console.warn('⚠️ Datos de usuario incompletos para comentario');
      return null;
    }

    if (!commenterData.isActive || !momentOwnerData.isActive) return null;

    const fcmToken = momentOwnerData.fcmToken || null;
    const shouldSendPush = Boolean(fcmToken) && !isDoNotDisturbActive(momentOwnerData) && notificationTypeEnabled(momentOwnerData, 'comment');

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

    const isSilencedByMuteSettings = shouldSilenceNotificationForUser(momentOwnerData, {
      senderId: comment.authorId,
      candidateTexts: [comment.text, momentData?.content]
    });
    if (isSilencedByMuteSettings) {
      return null;
    }

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
        mediaUrl: momentPreviewUrl || '',
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

    if (shouldSendPush) {
      try {
        await admin.messaging().send(message);
        console.log(`✅ Notificación de comentario enviada: ${commenterData.username} -> ${momentOwnerData.username}`);
      } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
          await removeInvalidToken(userId, fcmToken);
        }
        throw error;
      }
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
        await admin.messaging().send(message);
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
exports.onFollowerRemoved = onDocumentDeleted('users/{userId}/followers/{followerId}', async (event) => {
  const { userId, followerId } = event.params;

  try {
    await Promise.all([
      purgeSocialNotifications(userId, { type: 'newFollower', senderId: followerId }),
      purgeSocialNotifications(userId, { type: 'mutualConnection', senderId: followerId }),
      purgeSocialNotifications(followerId, { type: 'mutualConnection', senderId: userId })
    ]);
    console.log(`🧹 Follow notifications purged after unfollow: ${followerId} -> ${userId}`);
  } catch (error) {
    console.error('❌ Error purging follow notifications on unfollow:', error);
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
      await admin.messaging().send(message);
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

      const isSilencedByMuteSettings = shouldSilenceNotificationForUser(receiverData, {
        senderId: message.senderId,
        candidateTexts: [message.text, message.caption, message.type]
      });
      if (isSilencedByMuteSettings) {
        return null;
      }

      if (!receiverData.fcmToken || isDoNotDisturbActive(receiverData)) {
        return null;
      }

      // ✅ VERIFICAR SI LA CONVERSACIÓN ESTÁ SILENCIADA PARA ESTE USUARIO
      const mutedByUserIds = Array.isArray(conversationData.mutedByUserIds)
        ? conversationData.mutedByUserIds
        : [];
      const isMutedForReceiver =
        mutedByUserIds.includes(receiverId) ||
        (conversationData.isMuted === true && conversationData.mutedBy === receiverId);

      if (isMutedForReceiver) {
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

    const fcmToken = storyOwnerData.fcmToken || null;
    const shouldSendPush = Boolean(fcmToken) && !isDoNotDisturbActive(storyOwnerData) && notificationTypeEnabled(storyOwnerData, 'storyReaction');

    const emoji = reaction.reaction || '❤️';

    const cleanImageUrl = reacterData.profileImagePath
      ? reacterData.profileImagePath.replace(':443', '')
      : null;

    const isSilencedByMuteSettings = shouldSilenceNotificationForUser(storyOwnerData, {
      senderId: reaction.userId,
      candidateTexts: [reaction.reaction]
    });
    if (isSilencedByMuteSettings) {
      return null;
    }

    // ✅ Obtener conteos actualizados para el Widget + preview de la historia
    const [counts, reactionCount, storySnap] = await Promise.all([
      getUnreadCounts(userId, { type: 'notification', notificationType: 'storyReaction', notificationId: reactionId }),
      getPendingStoryReactionCount(userId, storyId),
      admin.firestore().doc(`users/${userId}/stories/${storyId}`).get()
    ]);

    const storyPreviewUrl = storySnap.exists ? pickStoryPreviewUrl(storySnap.data()) : null;

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
        mediaUrl: storyPreviewUrl || '',
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

    if (shouldSendPush) {
      try {
        await admin.messaging().send(message);
        console.log(`✅ Notificación de reacción a historia enviada: ${reacterData.username} -> ${storyOwnerData.username} (${emoji})`);
      } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
          await removeInvalidToken(userId, fcmToken);
        }
        throw error;
      }
    }

    // ID estable: una notificación por reactor y por historia.
    // Evita que la colección crezca sin límite si alguien reacciona/quita varias veces.
    const storyReactionNotificationId = `storyReaction_${storyId}_${reaction.userId}`;
    await admin.firestore()
      .doc(`users/${userId}/notifications/${storyReactionNotificationId}`)
      .set({
        type: 'storyReaction',
        senderId: reaction.userId,
        senderUsername: reacterData.username,
        senderProfileImage: reacterData.profileImagePath || '',
        storyId: storyId,
        storyAuthorId: userId,
        storyPreviewUrl: storyPreviewUrl || null,
        reaction: reaction.reaction,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isPending: true
      }, { merge: true });

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

    const fcmToken = userData.fcmToken || null;
    const shouldSendPush = Boolean(fcmToken) && !isDoNotDisturbActive(userData) && notificationTypeEnabled(userData, 'followRequest');

    const cleanImageUrl = requesterData.profileImagePath
      ? requesterData.profileImagePath.replace(':443', '')
      : null;

    const isSilencedByMuteSettings = shouldSilenceNotificationForUser(userData, {
      senderId: request.senderId,
      candidateTexts: [requesterData.username]
    });
    if (isSilencedByMuteSettings) {
      return null;
    }

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

    if (shouldSendPush) {
      try {
        await admin.messaging().send(message);
        console.log(`✅ Notificación de solicitud enviada: ${requesterData.username} -> ${userData.username}`);
      } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
          await removeInvalidToken(userId, fcmToken);
        }
        throw error;
      }
    }

    await upsertSocialNotification(userId, socialNotificationDocId('followRequest', request.senderId), {
      type: 'followRequest',
      senderId: request.senderId,
      senderUsername: requesterData.username,
      senderProfileImage: requesterData.profileImagePath || '',
      requestId: requestId
    });

  } catch (error) {
    console.error('❌ Error sending follow request notification:', error);
  }
});

// 📩 SOLICITUD CANCELADA / RECHAZADA: limpiar notificación followRequest
exports.onFollowRequestRemoved = onDocumentDeleted('users/{userId}/receivedFollowRequests/{requestId}', async (event) => {
  const snap = event.data;
  const { userId } = event.params;
  const request = snap?.data() || {};
  const senderId = typeof request.senderId === 'string' ? request.senderId : '';

  if (!senderId) {
    return null;
  }

  try {
    await purgeSocialNotifications(userId, { type: 'followRequest', senderId });
    console.log(`🧹 Follow request notification purged: ${senderId} -> ${userId}`);
  } catch (error) {
    console.error('❌ Error purging follow request notification:', error);
  }

  return null;
});

// 🔔 MENCIONES EN CUALQUIER CONTENIDO (HISTORIAS, MOMENTOS, COMENTARIOS)
// 🏷️ MENTIONS + PHOTO TAGS
// ✅ ELIMINADAS: exports.onMentionNotification y exports.onPhotoTagNotification
// Ahora están integradas en exports.onNotificationCreated (arriba) como
// handleMentionPush() y handlePhotoTagPush() respectivamente.
// Esto reduce invocaciones de Cloud Functions de 3x a 1x por notificación.

// 🧹 LIMPIEZA DE NOTIFICACIONES HUÉRFANAS
// Cuando se borra un momento / historia / comentario, las notificaciones asociadas
// (reacción, comentario, like, mención, etiqueta, reacción a historia) quedan huérfanas
// en los destinatarios. Usamos collectionGroup (igualdad simple → índice automático)
// para purgarlas allá donde estén.
async function purgeNotificationsByField(field, value) {
  if (!field || !value) return 0;
  let totalDeleted = 0;
  // Iterar en lotes hasta vaciar.
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snapshot = await admin.firestore()
      .collectionGroup('notifications')
      .where(field, '==', value)
      .limit(400)
      .get();

    if (snapshot.empty) break;

    const batch = admin.firestore().batch();
    snapshot.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    totalDeleted += snapshot.size;

    if (snapshot.size < 400) break;
  }
  if (totalDeleted > 0) {
    console.log(`🧹 Purga de notificaciones por ${field}=${value}: ${totalDeleted} eliminadas`);
  }
  return totalDeleted;
}

function echoHasMinimumMomentParticipants(echo) {
  const participantCount = new Set((echo?.moments || []).map((moment) => moment.authorId).filter(Boolean)).size;
  return participantCount >= 2;
}

async function reconcileEchoAfterMomentDeletion({ momentId, authorId }) {
  if (!momentId || !authorId) return 0;

  const matchingEchoes = await admin.firestore()
    .collection('echoes')
    .where('participantIds', 'array-contains', authorId)
    .get();

  let updatedCount = 0;

  for (const echoDoc of matchingEchoes.docs) {
    const echo = echoDoc.data() || {};
    const previousMoments = Array.isArray(echo.moments) ? echo.moments : [];
    const remainingMoments = previousMoments.filter((momentRef) => {
      if (!momentRef || typeof momentRef !== 'object') return false;
      return !(momentRef.momentId === momentId && momentRef.authorId === authorId);
    });

    if (remainingMoments.length === previousMoments.length) {
      continue;
    }

    const remainingAuthorIds = new Set(
      remainingMoments
        .map((momentRef) => momentRef?.authorId)
        .filter(Boolean)
    );

    const previousParticipants = Array.isArray(echo.participants) ? echo.participants : [];
    const remainingParticipants = previousParticipants.filter((participant) => remainingAuthorIds.has(participant?.userId));
    const acceptedParticipantCount = remainingParticipants.filter((participant) => participant?.status === 'accepted').length;
    const expiresAtMs = echo.expiresAt?.toDate ? echo.expiresAt.toDate().getTime() : 0;
    const isWithinWindow = expiresAtMs > Date.now();

    if (remainingParticipants.length === 0) {
      await echoDoc.ref.delete();
      updatedCount += 1;
      continue;
    }

    if (isWithinWindow && !echoHasMinimumMomentParticipants({ moments: remainingMoments })) {
      await echoDoc.ref.delete();
      updatedCount += 1;
      continue;
    }

    const nextPayload = {
      moments: remainingMoments,
      participants: remainingParticipants,
      participantIds: remainingParticipants.map((participant) => participant.userId)
    };

    if (echo.status === 'active' && acceptedParticipantCount < 2) {
      nextPayload.status = 'expired';
    }

    await echoDoc.ref.update(nextPayload);
    updatedCount += 1;
  }

  if (updatedCount > 0) {
    console.log(`🪞 Echoes reconciliados tras borrar moment ${momentId}: ${updatedCount}`);
  }

  return updatedCount;
}

exports.onMomentDeleted = onDocumentDeleted('users/{userId}/moments/{momentId}', async (event) => {
  const { userId, momentId } = event.params;
  try {
    await purgeNotificationsByField('momentId', momentId);
    await reconcileEchoAfterMomentDeletion({ momentId, authorId: userId });
  } catch (error) {
    console.error('❌ Error purgando notificaciones del momento eliminado:', error);
  }
  return null;
});

exports.onStoryDeleted = onDocumentDeleted('users/{userId}/stories/{storyId}', async (event) => {
  const { storyId } = event.params;
  try {
    await purgeNotificationsByField('storyId', storyId);
  } catch (error) {
    console.error('❌ Error purgando notificaciones de la historia eliminada:', error);
  }
  return null;
});

exports.onCommentDeleted = onDocumentDeleted('users/{userId}/moments/{momentId}/comments/{commentId}', async (event) => {
  const { commentId } = event.params;
  try {
    await purgeNotificationsByField('commentId', commentId);
  } catch (error) {
    console.error('❌ Error purgando notificaciones del comentario eliminado:', error);
  }
  return null;
});

// 🔔 ELIMINAR REACCIONES DE MOMENTOS
exports.onMomentReactionRemoved = onDocumentDeleted('users/{userId}/moments/{momentId}/reactions/{reactionId}', async (event) => {
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
exports.onEchoCreated = onDocumentCreated('echoes/{echoId}', async (event) => {
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

// ✅ ACCOUNT DELETION: trusted backend cascade for permanent account deletion
exports.deleteMyAccount = onRequest(
  {
    timeoutSeconds: 540,
    memory: '1GiB'
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

    const uid = await verifyFirebaseAuth(req, res, {
      checkRevoked: true,
      requireRecentAuth: true
    });
    if (!uid) return;

    const db = admin.firestore();
    const fieldValue = admin.firestore.FieldValue;
    const stats = {
      conversationsMarked: 0,
      relationshipRefsDeleted: 0,
      relationshipArraysUpdated: 0,
      collectionDocsDeleted: 0,
      collectionDocsUpdated: 0,
      storagePrefixesRequested: 0
    };

    const commitBatches = async (operations) => {
      let batch = db.batch();
      let count = 0;

      for (const operation of operations) {
        operation(batch);
        count += 1;

        if (count >= 450) {
          await batch.commit();
          batch = db.batch();
          count = 0;
        }
      }

      if (count > 0) {
        await batch.commit();
      }
    };

    const deleteQueryDocs = async (query) => {
      let deleted = 0;
      while (true) {
        const snap = await query.limit(300).get();
        if (snap.empty) break;

        await commitBatches(snap.docs.map((doc) => (batch) => batch.delete(doc.ref)));
        deleted += snap.size;

        if (snap.size < 300) break;
      }
      stats.collectionDocsDeleted += deleted;
      return deleted;
    };

    const updateQueryDocs = async (query, updateData) => {
      let updated = 0;
      while (true) {
        const snap = await query.limit(300).get();
        if (snap.empty) break;

        await commitBatches(snap.docs.map((doc) => (batch) => batch.update(doc.ref, updateData)));
        updated += snap.size;

        if (snap.size < 300) break;
      }
      stats.collectionDocsUpdated += updated;
      return updated;
    };

    const runNamedCleanup = async (name, action) => {
      try {
        return await action();
      } catch (error) {
        console.error(`❌ deleteMyAccount cleanup failed [${name}] for uid=${uid}:`, error);
        throw error;
      }
    };

    const deleteStoragePrefix = async (prefix) => {
      try {
        await admin.storage().bucket().deleteFiles({ prefix, force: true });
        stats.storagePrefixesRequested += 1;
      } catch (error) {
        console.warn(`deleteMyAccount: storage cleanup skipped for ${prefix}`, error.message);
      }
    };

    try {
      const userRef = db.collection('users').doc(uid);
      const userSnap = await userRef.get();
      const userData = userSnap.exists ? (userSnap.data() || {}) : {};
      const username = typeof userData.username === 'string' ? userData.username.trim().toLowerCase() : '';

      if (userSnap.exists) {
        await userRef.set({
          isActive: false,
          isDeleted: true,
          accountDeletion: {
            status: 'processing',
            requestedAt: fieldValue.serverTimestamp(),
            source: 'settings'
          }
        }, { merge: true });
      }

      const usersSnap = await db.collection('users').get();
      const relationshipOps = [];

      for (const doc of usersSnap.docs) {
        if (doc.id === uid) continue;

        const data = doc.data() || {};
        const updateData = {};
        const muteSettings = data.muteSettings || {};

        if (Array.isArray(data.bestFriends) && data.bestFriends.includes(uid)) {
          updateData.bestFriends = fieldValue.arrayRemove(uid);
        }
        if (Array.isArray(data.blockedUsers) && data.blockedUsers.includes(uid)) {
          updateData.blockedUsers = fieldValue.arrayRemove(uid);
        }
        if (Array.isArray(muteSettings.mutedUsers) && muteSettings.mutedUsers.includes(uid)) {
          updateData['muteSettings.mutedUsers'] = fieldValue.arrayRemove(uid);
        }

        if (Object.keys(updateData).length > 0) {
          relationshipOps.push((batch) => batch.update(doc.ref, updateData));
          stats.relationshipArraysUpdated += 1;
        }

        relationshipOps.push((batch) => batch.delete(doc.ref.collection('followers').doc(uid)));
        relationshipOps.push((batch) => batch.delete(doc.ref.collection('following').doc(uid)));
        stats.relationshipRefsDeleted += 2;
      }

      await commitBatches(relationshipOps);

      await Promise.all([
        runNamedCleanup('customAudienceLists.members', () => updateQueryDocs(
          db.collectionGroup('customAudienceLists').where('members', 'array-contains', uid),
          { members: fieldValue.arrayRemove(uid), updatedAt: fieldValue.serverTimestamp() }
        )),
        runNamedCleanup('customAudiences.allowedUsers', () => updateQueryDocs(
          db.collectionGroup('customAudiences').where('allowedUsers', 'array-contains', uid),
          { allowedUsers: fieldValue.arrayRemove(uid), lastUpdated: fieldValue.serverTimestamp() }
        )),
        runNamedCleanup('sentFollowRequests.senderId', () => deleteQueryDocs(db.collectionGroup('sentFollowRequests').where('senderId', '==', uid))),
        runNamedCleanup('sentFollowRequests.recipientId', () => deleteQueryDocs(db.collectionGroup('sentFollowRequests').where('recipientId', '==', uid))),
        runNamedCleanup('receivedFollowRequests.senderId', () => deleteQueryDocs(db.collectionGroup('receivedFollowRequests').where('senderId', '==', uid))),
        runNamedCleanup('receivedFollowRequests.recipientId', () => deleteQueryDocs(db.collectionGroup('receivedFollowRequests').where('recipientId', '==', uid))),
        runNamedCleanup('notifications.senderId', () => deleteQueryDocs(db.collectionGroup('notifications').where('senderId', '==', uid))),
        runNamedCleanup('comments.authorId', () => deleteQueryDocs(db.collectionGroup('comments').where('authorId', '==', uid))),
        runNamedCleanup('reactions.userId', () => deleteQueryDocs(db.collectionGroup('reactions').where('userId', '==', uid))),
        runNamedCleanup('customaudience.userId', () => deleteQueryDocs(db.collection('customaudience').where('userId', '==', uid))),
        runNamedCleanup('dailystats.userId', () => deleteQueryDocs(db.collection('dailystats').where('userId', '==', uid))),
        runNamedCleanup('loginActivity.userId', () => deleteQueryDocs(db.collection('loginActivity').where('userId', '==', uid))),
        runNamedCleanup('novamemory.userId', () => deleteQueryDocs(db.collection('novamemory').where('userId', '==', uid))),
        runNamedCleanup('visitorsummaries.userId', () => deleteQueryDocs(db.collection('visitorsummaries').where('userId', '==', uid))),
        runNamedCleanup('visits.userId', () => deleteQueryDocs(db.collection('visits').where('userId', '==', uid)))
      ]);

      const conversationsSnap = await runNamedCleanup('conversations.participants', () => db.collection('conversations')
        .where('participants', 'array-contains', uid)
        .get());

      await commitBatches(conversationsSnap.docs.map((doc) => (batch) => batch.update(doc.ref, {
        unavailableParticipantIds: fieldValue.arrayUnion(uid),
        deletedParticipantIds: fieldValue.arrayUnion(uid),
        [`participantData.${uid}.isDeleted`]: true,
        [`participantData.${uid}.isActive`]: false,
        [`participantData.${uid}.profileImagePath`]: '',
        [`participantData.${uid}.deletedAt`]: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp()
      })));
      stats.conversationsMarked += conversationsSnap.size;

      await Promise.all([
        runNamedCleanup('typing.userId', () => deleteQueryDocs(db.collectionGroup('typing').where('userId', '==', uid))),
        deleteStoragePrefix(`users/${uid}/`),
        deleteStoragePrefix(`profile_images/${uid}/`),
        deleteStoragePrefix(`moments/${uid}/`),
        deleteStoragePrefix(`stories/${uid}/`),
        deleteStoragePrefix(`messages/${uid}/`)
      ]);

      if (username) {
        await db.collection('usernames').doc(username).delete();
      }

      if (typeof db.recursiveDelete === 'function') {
        await db.recursiveDelete(userRef);
      } else {
        await userRef.delete();
      }

      try {
        await admin.auth().deleteUser(uid);
      } catch (authError) {
        if (authError.code !== 'auth/user-not-found') {
          throw authError;
        }
      }

      console.log(`✅ deleteMyAccount completed for uid=${uid}`, stats);
      res.status(200).json({ success: true, stats });
    } catch (error) {
      console.error(`❌ deleteMyAccount failed for uid=${uid}:`, error);
      res.status(500).json({ error: 'Failed to delete account' });
    }
  }
);

// =====================================================
// 🚀 BACKEND-FIRST FEED — getFeedPage
// =====================================================

/**
 * Build the viewer's relationship context in parallel.
 * Returns { following, followers, mutuals, bestFriends, blockedUsers, isPrivate }
 */
async function buildViewerContext(uid) {
  const db = admin.firestore();
  const [followingSnap, followersSnap, viewerDoc] = await Promise.all([
    db.collection(`users/${uid}/following`).get(),
    db.collection(`users/${uid}/followers`).get(),
    db.doc(`users/${uid}`).get()
  ]);

  const following = new Set(followingSnap.docs.map(d => d.id));
  const followers = new Set(followersSnap.docs.map(d => d.id));
  const mutuals = new Set([...following].filter(id => followers.has(id)));

  const viewerData = viewerDoc.exists ? viewerDoc.data() : {};
  const bestFriends = new Set(Array.isArray(viewerData.bestFriends) ? viewerData.bestFriends : []);
  const blockedUsers = new Set(Array.isArray(viewerData.blockedUsers) ? viewerData.blockedUsers : []);

  return { following, followers, mutuals, bestFriends, blockedUsers };
}

/**
 * Batch-load author user documents for a set of author IDs.
 * Returns Map<authorId, authorData>.
 */
async function batchLoadAuthorDocs(authorIds) {
  const db = admin.firestore();
  const uniqueIds = [...new Set(authorIds)];
  const authorMap = new Map();

  // Firestore getAll supports up to 100 refs
  const chunks = [];
  for (let i = 0; i < uniqueIds.length; i += 100) {
    chunks.push(uniqueIds.slice(i, i + 100));
  }

  for (const chunk of chunks) {
    const refs = chunk.map(id => db.doc(`users/${id}`));
    const docs = await db.getAll(...refs);
    docs.forEach(doc => {
      if (doc.exists) {
        authorMap.set(doc.id, doc.data());
      }
    });
  }

  return authorMap;
}

/**
 * Server-side privacy check — mirrors canUserViewMomentEnhanced from PrivacyService.swift
 *
 * @param {object} moment - { id, authorId, audience, taggedUsers, mentionedUsers, customListId }
 * @param {string} viewerId
 * @param {object} viewerCtx - from buildViewerContext
 * @param {object} authorData - author user document data
 * @returns {Promise<boolean>}
 */
async function canViewerSeeMoment(moment, viewerId, viewerCtx, authorData) {
  const db = admin.firestore();

  // Archived moments are hidden outside the dedicated archived activity view.
  if (moment.isArchived === true) return false;

  // 1. Author always sees own content
  if (moment.authorId === viewerId) return true;

  // Match Firestore read rules: inactive/deactivated authors are hidden from
  // non-owners, even if the content is public or the viewer follows the author.
  if (authorData.isActive === false) return false;

  // 2. Mutual block check
  const authorBlocked = Array.isArray(authorData.blockedUsers) ? authorData.blockedUsers : [];
  if (viewerCtx.blockedUsers.has(moment.authorId) || authorBlocked.includes(viewerId)) {
    return false;
  }

  // 3. Hidden from author content
  const visSettings = authorData.contentVisibilitySettings || {};
  const hiddenFrom = Array.isArray(visSettings.hiddenFromUsers) ? visSettings.hiddenFromUsers : [];
  if (hiddenFrom.includes(viewerId)) return false;

  // 4. Audience check
  const audience = moment.audience || 'everyone';

  switch (audience) {
    case 'everyone': {
      // Public profile → visible. Private → viewer must follow author.
      const isPrivate = authorData.isPrivate === true;
      if (!isPrivate) return true;
      return viewerCtx.following.has(moment.authorId);
    }

    case 'connections': {
      // Mutual connection required
      return viewerCtx.following.has(moment.authorId) && viewerCtx.followers.has(moment.authorId);
    }

    case 'bestFriends': {
      // Viewer must be in author's bestFriends
      const authorBestFriends = Array.isArray(authorData.bestFriends) ? authorData.bestFriends : [];
      return authorBestFriends.includes(viewerId);
    }

    case 'custom': {
      // Check customAudiences subcollection
      if (!moment.id) return false;
      try {
        const audienceDoc = await db.doc(`users/${moment.authorId}/customAudiences/moment_${moment.id}`).get();
        if (!audienceDoc.exists) return false;
        const allowedUsers = audienceDoc.data().allowedUsers || [];
        return allowedUsers.includes(viewerId);
      } catch {
        return false;
      }
    }

    case 'customList': {
      // Check customAudienceLists subcollection
      const listId = moment.customListId;
      if (!listId) return false;
      try {
        const listDoc = await db.doc(`users/${moment.authorId}/customAudienceLists/${listId}`).get();
        if (!listDoc.exists) return false;
        const members = listDoc.data().members || [];
        return members.includes(viewerId);
      } catch {
        return false;
      }
    }

    case 'onlyMe':
      return false;

    default:
      return false;
  }
}

/**
 * Serialize a Firestore Timestamp to epoch millis (or null).
 */
function tsToMillis(ts) {
  if (!ts) return null;
  if (typeof ts.toMillis === 'function') return ts.toMillis();
  if (ts._seconds !== undefined) return ts._seconds * 1000 + Math.floor((ts._nanoseconds || 0) / 1e6);
  return null;
}

/**
 * Compare two feed cursors and detect no-op progression loops.
 */
function isSameFeedCursor(a, b) {
  if (!a || !b) return false;
  return Number(a.timestamp || 0) === Number(b.timestamp || 0)
    && String(a.momentId || '') === String(b.momentId || '')
    && String(a.authorId || '') === String(b.authorId || '');
}

/**
 * Validate the users/{authorId}/moments/{momentId} ownership invariant before
 * trusting Admin-read collectionGroup results. This mirrors the create-time
 * security rule that requires moment.authorId to match the owning user path.
 */
function isMomentPathAuthorConsistent(doc, data) {
  const authorId = data && data.authorId;
  if (typeof authorId !== 'string' || authorId.length === 0) return false;

  const refPath = doc && doc.ref && typeof doc.ref.path === 'string' ? doc.ref.path : '';
  const parts = refPath.split('/');
  return parts.length === 4
    && parts[0] === 'users'
    && parts[1] === authorId
    && parts[2] === 'moments'
    && parts[3] === doc.id;
}

/**
 * Serialize a Firestore moment doc into the JSON format the client expects.
 */
function serializeMediaItem(item) {
  if (!item || typeof item !== 'object') return null;

  return {
    id: item.id || null,
    type: item.type || null,
    url: item.url || null,
    aspectRatio: item.aspectRatio || null,
    thumbnailUrl: item.thumbnailUrl || null,
    videoDuration: item.videoDuration || null,
    videoFileSize: item.videoFileSize || null,
    videoResolution: item.videoResolution || null,
    videoProcessingStatus: item.videoProcessingStatus || null,
    originalVideoUrl: item.originalVideoUrl || null,
    videoVariants: item.videoVariants || null,
    tags: Array.isArray(item.tags) ? item.tags : null,
    moderationState: item.moderationState || null,
    moderationReason: item.moderationReason || null,
    moderationCategory: item.moderationCategory || null,
    moderationConfidence: item.moderationConfidence || null,
    moderatedAt: tsToMillis(item.moderatedAt)
  };
}

function hasVisibleMediaItem(item) {
  if (!item || typeof item !== 'object') return false;
  if (item.moderationState === 'hidden') return false;
  return typeof item.url === 'string' && item.url.trim().length > 0;
}

function buildLegacyMomentMediaFields(mediaItems) {
  if (!Array.isArray(mediaItems)) return {};

  const visibleMediaItems = mediaItems.filter((item) => hasVisibleMediaItem(item));
  const primaryVisibleMediaItem = visibleMediaItems[0] || null;
  if (!primaryVisibleMediaItem) {
    return {
      imageUrl: null,
      videoUrl: null,
      thumbnailUrl: null,
      videoDuration: null,
      videoFileSize: null,
      videoResolution: null
    };
  }

  const normalizedUrl = typeof primaryVisibleMediaItem.url === 'string'
    ? primaryVisibleMediaItem.url.trim()
    : null;
  const normalizedThumbnailUrl = typeof primaryVisibleMediaItem.thumbnailUrl === 'string'
    ? primaryVisibleMediaItem.thumbnailUrl.trim()
    : null;

  if (primaryVisibleMediaItem.type === 'video') {
    return {
      imageUrl: null,
      videoUrl: normalizedUrl || null,
      thumbnailUrl: normalizedThumbnailUrl || normalizedUrl || null,
      videoDuration: primaryVisibleMediaItem.videoDuration || null,
      videoFileSize: primaryVisibleMediaItem.videoFileSize || null,
      videoResolution: primaryVisibleMediaItem.videoResolution || null
    };
  }

  return {
    imageUrl: normalizedUrl || null,
    videoUrl: null,
    thumbnailUrl: null,
    videoDuration: null,
    videoFileSize: null,
    videoResolution: null
  };
}

function serializeMoment(docId, data) {
  const hasStructuredMediaItems = Array.isArray(data.mediaItems);
  const visibleMediaItems = hasStructuredMediaItems
    ? data.mediaItems.filter((item) => hasVisibleMediaItem(item))
    : null;
  const primaryVisibleMediaItem = Array.isArray(visibleMediaItems) ? visibleMediaItems[0] || null : null;
  const previewUrl = hasStructuredMediaItems
    ? pickMomentPreviewUrl({ ...data, mediaItems: visibleMediaItems })
    : null;
  const primaryVisibleMediaUrl = primaryVisibleMediaItem && typeof primaryVisibleMediaItem.url === 'string'
    ? primaryVisibleMediaItem.url.trim()
    : null;
  const primaryVisibleThumbnailUrl = primaryVisibleMediaItem && typeof primaryVisibleMediaItem.thumbnailUrl === 'string'
    ? primaryVisibleMediaItem.thumbnailUrl.trim()
    : null;

  return {
    id: docId,
    authorId: data.authorId || '',
    username: data.username || '',
    content: data.content || '',
    imageUrl: hasStructuredMediaItems
      ? (primaryVisibleMediaItem?.type === 'image' ? primaryVisibleMediaUrl : null)
      : data.imageUrl || null,
    videoUrl: hasStructuredMediaItems
      ? (primaryVisibleMediaItem?.type === 'video' ? primaryVisibleMediaUrl : null)
      : data.videoUrl || null,
    timestamp: tsToMillis(data.timestamp),
    reactions: data.reactions || {},
    commentCount: data.commentCount || 0,
    profileImagePath: data.profileImagePath || null,
    taggedUsers: data.taggedUsers || null,
    mentionedUsers: data.mentionedUsers || null,
    location: data.location || null,
    locationCoordinate: data.locationCoordinate || null,
    audience: data.audience || 'everyone',
    mediaItems: hasStructuredMediaItems
      ? visibleMediaItems.map((item) => serializeMediaItem(item)).filter(Boolean)
      : null,
    aspectRatio: data.aspectRatio || null,
    customListId: data.customListId || null,
    thumbnailUrl: hasStructuredMediaItems
      ? (primaryVisibleThumbnailUrl || previewUrl || null)
      : data.thumbnailUrl || null,
    videoDuration: data.videoDuration || null,
    videoFileSize: data.videoFileSize || null,
    videoResolution: data.videoResolution || null,
    disableComments: data.disableComments || false,
    hideLikeCounts: data.hideLikeCounts || false,
    allowSharing: data.allowSharing !== false,
    scheduledDate: tsToMillis(data.scheduledDate),
    trendingScore: data.trendingScore || null,
    engagementRate: data.engagementRate || null,
    hasHiddenLayers: data.hasHiddenLayers === true,
    hiddenLayerCount: Number.isInteger(data.hiddenLayerCount) ? data.hiddenLayerCount : 0
  };
}

/**
 * Serialize a restricted moment without exposing media/content.
 */
function serializeRestrictedMoment(docId, data) {
  return {
    id: docId,
    authorId: data.authorId || '',
    username: data.username || '',
    content: '',
    imageUrl: null,
    videoUrl: null,
    timestamp: tsToMillis(data.timestamp),
    reactions: {},
    commentCount: 0,
    profileImagePath: data.profileImagePath || null,
    taggedUsers: null,
    mentionedUsers: null,
    location: null,
    locationCoordinate: null,
    audience: data.audience || 'everyone',
    mediaItems: null,
    aspectRatio: data.aspectRatio || null,
    customListId: data.customListId || null,
    thumbnailUrl: null,
    videoDuration: null,
    videoFileSize: null,
    videoResolution: null,
    disableComments: true,
    hideLikeCounts: true,
    allowSharing: false,
    scheduledDate: tsToMillis(data.scheduledDate),
    trendingScore: null,
    engagementRate: null
  };
}

function isFirestoreFailedPrecondition(error) {
  if (!error) return false;
  const code = error.code;
  const codeStr = typeof code === 'string' ? code.toLowerCase() : String(code || '');
  return code === 9 || codeStr.includes('failed-precondition') || codeStr === '9';
}

async function buildMapFallbackCandidateUserIds(uid, viewerCtx, db) {
  const followingIds = [...viewerCtx.following];
  const extraIds = new Set(followingIds);
  extraIds.add(uid);

  const [suggestedSnap, popularSnap] = await Promise.all([
    db.collection('users')
      .where('isActive', '==', true)
      .limit(40)
      .get(),
    db.collection('users')
      .limit(30)
      .get()
  ]);

  suggestedSnap.docs.forEach((d) => {
    if (d.id !== uid && !viewerCtx.blockedUsers.has(d.id)) {
      extraIds.add(d.id);
    }
  });

  popularSnap.docs.forEach((d) => {
    if (d.id !== uid && !viewerCtx.blockedUsers.has(d.id)) {
      extraIds.add(d.id);
    }
  });

  return [...extraIds];
}

async function fetchMapCandidatesByAuthorBatches(db, candidateUserIds, mode, filters) {
  if (!Array.isArray(candidateUserIds) || candidateUserIds.length === 0) return [];

  const userBatches = [];
  for (let i = 0; i < candidateUserIds.length; i += 10) {
    userBatches.push(candidateUserIds.slice(i, i + 10));
  }

  const perBatchLimit = mode === 'location' ? 80 : 120;
  const allDocs = [];

  await Promise.all(userBatches.map(async (batch) => {
    const snap = await db.collectionGroup('moments')
      .where('authorId', 'in', batch)
      .orderBy('timestamp', 'desc')
      .limit(perBatchLimit)
      .get();
    snap.docs.forEach((doc) => allDocs.push(doc));
  }));

  const seen = new Set();
  const unique = [];
  for (const doc of allDocs) {
    const path = doc.ref.path;
    if (!seen.has(path)) {
      seen.add(path);
      unique.push(doc);
    }
  }

  if (mode === 'location') {
    const locationName = filters.locationName || '';
    return unique.filter((doc) => {
      const data = doc.data() || {};
      return String(data.location || '') === locationName;
    });
  }

  const latitudeMin = filters.latitudeMin;
  const latitudeMax = filters.latitudeMax;
  const longitudeMin = filters.longitudeMin;
  const longitudeMax = filters.longitudeMax;

  return unique.filter((doc) => {
    const data = doc.data() || {};
    const coord = data.locationCoordinate || {};
    const lat = Number(coord.latitude);
    const lon = Number(coord.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) return false;
    return lat >= latitudeMin && lat <= latitudeMax && lon >= longitudeMin && lon <= longitudeMax;
  });
}

/**
 * 🚀 getFeedPage — Backend-first feed endpoint.
 *
 * POST body: { feedType: "following"|"forYou", cursor?: { timestamp, momentId, authorId? }, limit?: number }
 * Response:  { moments: [...], nextCursor: {...}|null, source: "backend", totalCandidates: N }
 */
exports.getFeedPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const feedType = body.feedType === 'forYou' ? 'forYou' : 'following';
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 40)) : 20;
    const cursor = body.cursor || null; // { timestamp: number, momentId: string, authorId?: string }

    const db = admin.firestore();

    try {
      // ── 1. Build viewer context ──
      const viewerCtx = await buildViewerContext(uid);

      // ── 2. Determine candidate user IDs ──
      let candidateUserIds;

      if (feedType === 'following') {
        candidateUserIds = [...viewerCtx.following];
        // Include own moments
        if (!candidateUserIds.includes(uid)) {
          candidateUserIds.push(uid);
        }
      } else {
        // forYou: following + suggested + popular
        const followingIds = [...viewerCtx.following];
        const extraIds = new Set(followingIds);
        extraIds.add(uid);

        // Fetch some suggested/popular users
        const [suggestedSnap, popularSnap] = await Promise.all([
          db.collection('users')
            .where('isActive', '==', true)
            .limit(30)
            .get(),
          db.collection('users')
            .where('isActive', '==', true)
            .limit(20)
            .get()
        ]);

        suggestedSnap.docs.forEach(d => {
          if (d.id !== uid && !viewerCtx.blockedUsers.has(d.id)) {
            extraIds.add(d.id);
          }
        });
        popularSnap.docs.forEach(d => {
          if (d.id !== uid && !viewerCtx.blockedUsers.has(d.id)) {
            extraIds.add(d.id);
          }
        });

        candidateUserIds = [...extraIds];
      }

      if (candidateUserIds.length === 0) {
        res.status(200).json({ moments: [], nextCursor: null, source: 'backend', totalCandidates: 0 });
        return;
      }

      // ── 3. Fetch candidate moments (batched by 10 using collectionGroup) ──
      const fetchLimit = feedType === 'forYou' ? 200 : 80;
      const perAuthorLimit = feedType === 'forYou' ? 12 : 50;

      const userBatches = [];
      for (let i = 0; i < candidateUserIds.length; i += 10) {
        userBatches.push(candidateUserIds.slice(i, i + 10));
      }

      const allCandidateDocs = [];
      const batchFetchCounts = new Array(userBatches.length).fill(0);
      await Promise.all(userBatches.map(async (batch, batchIndex) => {
        let query = db.collectionGroup('moments')
          .where('authorId', 'in', batch)
          .orderBy('timestamp', 'desc');

        // Apply cursor: use startAt (inclusive) so we don't skip same-timestamp items.
        // The momentId-based slice below handles exact dedup.
        if (cursor && cursor.timestamp) {
          const cursorDate = new Date(cursor.timestamp);
          query = query.startAt(admin.firestore.Timestamp.fromDate(cursorDate));
        }

        query = query.limit(fetchLimit);
        const snap = await query.get();
        batchFetchCounts[batchIndex] = snap.size;
        snap.docs.forEach(doc => allCandidateDocs.push(doc));
      }));

      // Deduplicate by full ref path (prevents cross-author ID collisions)
      const seen = new Set();
      const uniqueDocs = [];
      for (const doc of allCandidateDocs) {
        const refPath = doc.ref.path;
        if (!seen.has(refPath)) {
          seen.add(refPath);
          uniqueDocs.push(doc);
        }
      }

      uniqueDocs.sort((a, b) => {
        const tsA = a.data().timestamp;
        const tsB = b.data().timestamp;
        const millisA = tsToMillis(tsA) || 0;
        const millisB = tsToMillis(tsB) || 0;
        if (millisB !== millisA) return millisB - millisA;
        return b.id.localeCompare(a.id); // stable tiebreaker
      });

      // Apply cursor momentId filter for composite cursor stability
      // Use ref.path for matching to avoid cross-author collisions
      let startIdx = 0;
      if (cursor && cursor.momentId && cursor.authorId) {
        const cursorPath = `users/${cursor.authorId}/moments/${cursor.momentId}`;
        for (let i = 0; i < uniqueDocs.length; i++) {
          if (uniqueDocs[i].ref.path === cursorPath) {
            startIdx = i + 1;
            break;
          }
        }
      } else if (cursor && cursor.momentId) {
        // Fallback for old cursors without authorId
        for (let i = 0; i < uniqueDocs.length; i++) {
          if (uniqueDocs[i].id === cursor.momentId) {
            startIdx = i + 1;
            break;
          }
        }
      }

      const candidatesAfterCursor = uniqueDocs.slice(startIdx);
      const totalCandidates = candidatesAfterCursor.length;

      // Filter out scheduled moments (only author can see scheduled)
      const now = Date.now();
      const nonScheduledCandidates = candidatesAfterCursor.filter(doc => {
        const data = doc.data();
        if (!isMomentPathAuthorConsistent(doc, data)) return false;
        if (data.isArchived === true) return false;
        if (data.authorId === uid) return true; // author always sees own
        const schedMs = tsToMillis(data.scheduledDate);
        if (schedMs && schedMs > now) return false;
        return true;
      });

      // ── 4. Batch-load author docs for privacy checks ──
      const authorIds = [...new Set(nonScheduledCandidates.map(d => d.data().authorId))];
      const authorMap = await batchLoadAuthorDocs(authorIds);

      // ── 5. Apply privacy filter ──
      // Process in parallel but collect results in order
      const privacyResults = await Promise.all(
        nonScheduledCandidates.map(async (doc) => {
          const data = doc.data();
          if (!isMomentPathAuthorConsistent(doc, data)) return { doc, data, canView: false };
          const authorData = authorMap.get(data.authorId);
          // Fail-closed: if author doc is missing, deny access
          if (!authorData) return { doc, data, canView: false };
          const momentForCheck = {
            id: doc.id,
            authorId: data.authorId,
            audience: data.audience,
            taggedUsers: data.taggedUsers,
            customListId: data.customListId,
            isArchived: data.isArchived === true
          };
          const canView = await canViewerSeeMoment(momentForCheck, uid, viewerCtx, authorData);
          return { doc, data, canView };
        })
      );

      const visibleDocs = privacyResults.filter(r => r.canView);

      // ── 6. Per-author limit to avoid one user dominating feed ──
      const perAuthorCount = {};
      const perAuthorMax = feedType === 'forYou' ? 5 : 50;
      const finalDocs = [];
      for (const { doc, data } of visibleDocs) {
        const count = perAuthorCount[data.authorId] || 0;
        if (count >= perAuthorMax) continue;
        perAuthorCount[data.authorId] = count + 1;
        finalDocs.push({ doc, data });
        if (finalDocs.length >= limit) break;
      }

      // ── 7. Build response ──
      const moments = finalDocs.map(({ doc, data }) => serializeMoment(doc.id, data));

      let nextCursor = null;
      // Provide cursor if there are still more visible moments beyond what we returned,
      // OR if we hit fetchLimit (meaning there could be more in Firestore we haven't seen)
      const hasMoreInFirestore = batchFetchCounts.some(count => count >= fetchLimit);
      const moreVisibleThanReturned = visibleDocs.length > finalDocs.length;

      if (finalDocs.length > 0 && (moreVisibleThanReturned || hasMoreInFirestore)) {
        const lastDoc = finalDocs[finalDocs.length - 1];
        nextCursor = {
          timestamp: tsToMillis(lastDoc.data.timestamp),
          momentId: lastDoc.doc.id,
          authorId: lastDoc.data.authorId
        };
      } else if (finalDocs.length === 0 && nonScheduledCandidates.length > 0 && hasMoreInFirestore) {
        // All candidates filtered by privacy, but more may exist in Firestore.
        // Emit advance cursor from last candidate so client doesn't stop paginating.
        const lastCandidate = nonScheduledCandidates[nonScheduledCandidates.length - 1];
        const lastCandidateData = lastCandidate.data();
        nextCursor = {
          timestamp: tsToMillis(lastCandidateData.timestamp),
          momentId: lastCandidate.id,
          authorId: lastCandidateData.authorId
        };
      }

      // Safety guard: avoid returning the same cursor repeatedly (infinite pagination loops).
      if (cursor && nextCursor && isSameFeedCursor(cursor, nextCursor)) {
        console.warn(`⚠️ getFeedPage: no-op cursor detected for uid=${uid}, feed=${feedType}`);
        nextCursor = null;
      }

      console.log(`✅ getFeedPage: uid=${uid}, type=${feedType}, candidates=${totalCandidates}, visible=${visibleDocs.length}, returned=${moments.length}`);

      res.status(200).json({
        moments,
        nextCursor,
        source: 'backend',
        totalCandidates
      });

    } catch (error) {
      console.error('❌ getFeedPage error:', error);
      res.status(500).json({ error: 'Feed fetch failed', details: error.message });
    }
  }
);

/**
 * 🗺️ getMapMomentsPage — Returns moments visible to the viewer for map surfaces.
 *
 * POST body:
 * {
 *   mode: "region" | "location",
 *   centerLatitude?: number,
 *   centerLongitude?: number,
 *   latitudeDelta?: number,
 *   longitudeDelta?: number,
 *   locationName?: string,
 *   limit?: number
 * }
 *
 * Response:
 * {
 *   moments: [...],
 *   source: "backend",
 *   totalCandidates: number
 * }
 */
exports.getMapMomentsPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const mode = body.mode === 'location' ? 'location' : 'region';
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 120)) : 80;

    const db = admin.firestore();

    try {
      const viewerCtx = await buildViewerContext(uid);

      let query = db.collectionGroup('moments');
      let longitudeMin = -180;
      let longitudeMax = 180;
      let latitudeMin = -90;
      let latitudeMax = 90;
      let debugScope = 'region';

      if (mode === 'location') {
        const locationName = typeof body.locationName === 'string' ? body.locationName.trim() : '';
        if (!locationName) {
          res.status(400).json({ error: 'Missing locationName' });
          return;
        }
        debugScope = `location:${locationName}`;
        query = query.where('location', '==', locationName).limit(Math.max(limit * 4, 200));
      } else {
        const centerLatitude = Number(body.centerLatitude);
        const centerLongitude = Number(body.centerLongitude);
        const latitudeDelta = Number(body.latitudeDelta);
        const longitudeDelta = Number(body.longitudeDelta);

        const validRegion = Number.isFinite(centerLatitude)
          && Number.isFinite(centerLongitude)
          && Number.isFinite(latitudeDelta)
          && Number.isFinite(longitudeDelta)
          && latitudeDelta > 0
          && longitudeDelta > 0;

        if (!validRegion) {
          res.status(400).json({ error: 'Invalid region payload' });
          return;
        }

        latitudeMin = Math.max(-90, centerLatitude - (latitudeDelta / 2));
        latitudeMax = Math.min(90, centerLatitude + (latitudeDelta / 2));
        longitudeMin = Math.max(-180, centerLongitude - (longitudeDelta / 2));
        longitudeMax = Math.min(180, centerLongitude + (longitudeDelta / 2));

        query = query
          .where('locationCoordinate.latitude', '>=', latitudeMin)
          .where('locationCoordinate.latitude', '<=', latitudeMax)
          .orderBy('locationCoordinate.latitude')
          .limit(Math.max(limit * 4, 220));
      }

      let snapshot;
      let usedFallbackPath = false;
      try {
        snapshot = await query.get();
      } catch (queryError) {
        if (!isFirestoreFailedPrecondition(queryError)) {
          throw queryError;
        }

        usedFallbackPath = true;
        const fallbackCandidateUserIds = await buildMapFallbackCandidateUserIds(uid, viewerCtx, db);
        const fallbackDocs = await fetchMapCandidatesByAuthorBatches(
          db,
          fallbackCandidateUserIds,
          mode,
          {
            locationName: mode === 'location' ? (typeof body.locationName === 'string' ? body.locationName.trim() : '') : '',
            latitudeMin,
            latitudeMax,
            longitudeMin,
            longitudeMax
          }
        );
        snapshot = { docs: fallbackDocs };
      }

      const nowMs = Date.now();

      // Primary candidate window (non-archived + no future scheduled for non-authors + in longitude bounds for region mode)
      const candidateDocs = snapshot.docs.filter((doc) => {
        const data = doc.data() || {};

        if (data.isArchived === true) return false;

        if (data.authorId !== uid) {
          const scheduledMs = tsToMillis(data.scheduledDate);
          if (scheduledMs && scheduledMs > nowMs) return false;
        }

        if (mode !== 'location') {
          const coord = data.locationCoordinate || {};
          const lon = Number(coord.longitude);
          if (!Number.isFinite(lon)) return false;
          if (lon < longitudeMin || lon > longitudeMax) return false;
        }

        return true;
      });

      const authorIds = [...new Set(candidateDocs.map((d) => (d.data() || {}).authorId).filter(Boolean))];
      const authorMap = await batchLoadAuthorDocs(authorIds);

      const privacyResults = await Promise.all(
        candidateDocs.map(async (doc) => {
          const data = doc.data() || {};
          const authorData = authorMap.get(data.authorId);
          if (!authorData) return { doc, data, canView: false };

          const momentForCheck = {
            id: doc.id,
            authorId: data.authorId,
            audience: data.audience,
            taggedUsers: data.taggedUsers,
            customListId: data.customListId,
            isArchived: data.isArchived === true
          };

          const canView = await canViewerSeeMoment(momentForCheck, uid, viewerCtx, authorData);
          return { doc, data, canView };
        })
      );

      const visible = privacyResults
        .filter((entry) => entry.canView)
        .sort((a, b) => {
          const tsA = tsToMillis(a.data.timestamp) || 0;
          const tsB = tsToMillis(b.data.timestamp) || 0;
          if (tsB !== tsA) return tsB - tsA;
          return String(b.doc.id).localeCompare(String(a.doc.id));
        })
        .slice(0, limit);

      const moments = visible.map(({ doc, data }) => serializeMoment(doc.id, data));

      const pathTag = usedFallbackPath ? 'fallback_author_batches' : 'geo_query';
      console.log(`✅ getMapMomentsPage: uid=${uid}, scope=${debugScope}, path=${pathTag}, candidates=${candidateDocs.length}, visible=${visible.length}, returned=${moments.length}`);

      res.status(200).json({
        moments,
        source: 'backend',
        totalCandidates: candidateDocs.length
      });
    } catch (error) {
      console.error('❌ getMapMomentsPage error:', error);
      res.status(500).json({ error: 'Map moments fetch failed', details: error.message });
    }
  }
);

/**
 * 🎯 getReactedMomentsPage — Returns moments the viewer reacted to.
 *
 * POST body: { cursor?: { timestamp: number }, limit?: number }
 * Response:  { items: [{ moment, reactionType, reactedAt, authorId, momentId, canView }], nextCursor, source, totalCandidates }
 */
exports.getReactedMomentsPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 60)) : 30;
    const cursorTimestamp = Number(body?.cursor?.timestamp || 0);
    const requestedTargetUserId = typeof body?.targetUserId === 'string' ? body.targetUserId.trim() : '';
    const targetUserId = requestedTargetUserId || uid;
    const requestedTargetUserId = typeof body?.targetUserId === 'string' ? body.targetUserId.trim() : '';
    const targetUserId = requestedTargetUserId || uid;

    const db = admin.firestore();

    try {
      let query = db.collectionGroup('reactions')
        .where('userId', '==', uid)
        .orderBy('timestamp', 'desc');

      if (Number.isFinite(cursorTimestamp) && cursorTimestamp > 0) {
        query = query.startAfter(admin.firestore.Timestamp.fromMillis(cursorTimestamp));
      }

      // Scan a wider window so we can filter hidden/private content server-side and still fill one page.
      const scanLimit = Math.max(limit * 6, 120);
      const reactionsSnap = await query.limit(scanLimit).get();

      if (reactionsSnap.empty) {
        res.status(200).json({
          items: [],
          nextCursor: null,
          source: 'backend',
          totalCandidates: 0
        });
        return;
      }

      const viewerCtx = await buildViewerContext(uid);
      const seenMoments = new Set();
      const candidates = [];

      for (const doc of reactionsSnap.docs) {
        const pathParts = doc.ref.path.split('/');
        if (pathParts.length < 6 || pathParts[0] !== 'users' || pathParts[2] !== 'moments') {
          continue;
        }

        const authorId = pathParts[1];
        const momentId = pathParts[3];
        const dedupeKey = `${authorId}_${momentId}`;
        if (seenMoments.has(dedupeKey)) continue;
        seenMoments.add(dedupeKey);

        const data = doc.data() || {};
        candidates.push({
          authorId,
          momentId,
          reactionType: data.reactionType || data.reaction || '',
          reactedAt: data.timestamp || null
        });
      }

      if (candidates.length === 0) {
        const lastDoc = reactionsSnap.docs[reactionsSnap.docs.length - 1];
        const lastTimestamp = tsToMillis(lastDoc.data().timestamp);
        res.status(200).json({
          items: [],
          nextCursor: lastTimestamp ? { timestamp: lastTimestamp } : null,
          source: 'backend',
          totalCandidates: 0
        });
        return;
      }

      const authorIds = candidates.map(item => item.authorId);
      const authorMap = await batchLoadAuthorDocs(authorIds);

      // Batch load moment docs
      const momentRefs = candidates.map(item => db.doc(`users/${item.authorId}/moments/${item.momentId}`));
      const momentDocs = [];
      for (let i = 0; i < momentRefs.length; i += 100) {
        const chunk = momentRefs.slice(i, i + 100);
        if (chunk.length === 0) continue;
        const docs = await db.getAll(...chunk);
        docs.forEach(doc => momentDocs.push(doc));
      }

      const momentMap = new Map();
      for (const doc of momentDocs) {
        if (!doc.exists) continue;
        const parts = doc.ref.path.split('/');
        if (parts.length < 4) continue;
        const key = `${parts[1]}_${parts[3]}`;
        momentMap.set(key, doc);
      }

      const items = [];
      for (const candidate of candidates) {
        const key = `${candidate.authorId}_${candidate.momentId}`;
        const momentDoc = momentMap.get(key);
        if (!momentDoc || !momentDoc.exists) continue;

        const momentData = momentDoc.data() || {};
        if (momentData.isArchived === true) continue;
        const authorData = authorMap.get(candidate.authorId);
        if (!authorData) continue;

        const canView = await canViewerSeeMoment(
          {
            id: momentDoc.id,
            authorId: candidate.authorId,
            audience: momentData.audience,
            taggedUsers: momentData.taggedUsers,
            customListId: momentData.customListId,
            isArchived: momentData.isArchived === true
          },
          uid,
          viewerCtx,
          authorData
        );

        items.push({
          moment: canView
            ? serializeMoment(momentDoc.id, momentData)
            : serializeRestrictedMoment(momentDoc.id, momentData),
          reactionType: candidate.reactionType,
          reactedAt: tsToMillis(candidate.reactedAt),
          authorId: candidate.authorId,
          momentId: candidate.momentId,
          canView
        });

        if (items.length >= limit) break;
      }

      let nextCursor = null;
      const hasMoreScanned = reactionsSnap.size >= scanLimit;
      if (hasMoreScanned) {
        const lastDoc = reactionsSnap.docs[reactionsSnap.docs.length - 1];
        const lastTs = tsToMillis(lastDoc.data().timestamp);
        if (lastTs) {
          nextCursor = { timestamp: lastTs };
        }
      }

      console.log(`✅ getReactedMomentsPage: uid=${uid}, scanned=${reactionsSnap.size}, candidates=${candidates.length}, returned=${items.length}`);

      res.status(200).json({
        items,
        nextCursor,
        source: 'backend',
        totalCandidates: candidates.length
      });

    } catch (error) {
      console.error('❌ getReactedMomentsPage error:', error);
      res.status(500).json({ error: 'Reacted moments fetch failed', details: error.message });
    }
  }
);

/**
 * 😊 getStickerRepliesPage — Returns viewer sticker interactions:
 * - poll votes (with selected option text)
 * - question responses (with question + response text)
 *
 * POST body: { cursor?: { timestamp: number }, limit?: number }
 */
exports.getStickerRepliesPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 80)) : 40;
    const cursorTimestamp = Number(body?.cursor?.timestamp || 0);
    const db = admin.firestore();

    const parseStoryPath = (path) => {
      const parts = String(path || '').split('/');
      if (parts.length >= 6 && parts[0] === 'users' && parts[2] === 'stories') {
        return { authorId: parts[1], storyId: parts[3] };
      }
      return null;
    };

    try {
      const scanLimit = Math.max(limit * 6, 120);
      const viewerSnap = await db.collection('users').doc(uid).get();
      const viewerData = viewerSnap.exists ? (viewerSnap.data() || {}) : {};
      const actorUsername = typeof viewerData.username === 'string' ? viewerData.username : null;
      const actorProfileImagePath = typeof viewerData.profileImagePath === 'string' ? viewerData.profileImagePath : null;

      let pollQuery = db.collectionGroup('pollVotes')
        .where('userId', '==', uid)
        .orderBy('timestamp', 'desc');

      let questionQuery = db.collectionGroup('questionResponses')
        .where('userId', '==', uid)
        .orderBy('timestamp', 'desc');

      if (Number.isFinite(cursorTimestamp) && cursorTimestamp > 0) {
        const cursorTs = admin.firestore.Timestamp.fromMillis(cursorTimestamp);
        pollQuery = pollQuery.startAfter(cursorTs);
        questionQuery = questionQuery.startAfter(cursorTs);
      }

      const [pollSnap, questionSnap] = await Promise.all([
        pollQuery.limit(scanLimit).get(),
        questionQuery.limit(scanLimit).get()
      ]);

      const pollCandidates = [];
      const questionCandidates = [];
      const metadataKeys = new Set();

      for (const doc of pollSnap.docs) {
        const pathInfo = parseStoryPath(doc.ref.path);
        if (!pathInfo) continue;

        const data = doc.data() || {};
        const timestampMs = tsToMillis(data.timestamp);
        if (!timestampMs) continue;

        const option = Number.isInteger(data.option) ? data.option : null;
        pollCandidates.push({
          id: doc.id,
          kind: 'poll',
          authorId: pathInfo.authorId,
          storyId: pathInfo.storyId,
          timestampMs,
          option
        });
        metadataKeys.add(`poll:${pathInfo.authorId}:${pathInfo.storyId}`);
      }

      for (const doc of questionSnap.docs) {
        const pathInfo = parseStoryPath(doc.ref.path);
        if (!pathInfo) continue;
        if (doc.id === 'metadata') continue;

        const data = doc.data() || {};
        const timestampMs = tsToMillis(data.timestamp);
        if (!timestampMs) continue;

        questionCandidates.push({
          id: doc.id,
          kind: 'question',
          authorId: pathInfo.authorId,
          storyId: pathInfo.storyId,
          timestampMs,
          responseText: typeof data.response === 'string' ? data.response : ''
        });
        metadataKeys.add(`question:${pathInfo.authorId}:${pathInfo.storyId}`);
      }

      const merged = [...pollCandidates, ...questionCandidates].sort((a, b) => {
        if (a.timestampMs !== b.timestampMs) return b.timestampMs - a.timestampMs;
        return String(b.id).localeCompare(String(a.id));
      });

      if (merged.length === 0) {
        res.status(200).json({
          items: [],
          nextCursor: null,
          source: 'backend',
          totalCandidates: 0
        });
        return;
      }

      const metadataMap = new Map();
      const metadataRefs = [];
      const storyMap = new Map();
      for (const key of metadataKeys) {
        const [kind, authorId, storyId] = key.split(':');
        if (kind === 'poll') {
          metadataRefs.push({
            key,
            ref: db.doc(`users/${authorId}/stories/${storyId}/pollVotes/metadata`)
          });
        } else if (kind === 'question') {
          metadataRefs.push({
            key,
            ref: db.doc(`users/${authorId}/stories/${storyId}/questionResponses/metadata`)
          });
        }
      }

      for (let i = 0; i < metadataRefs.length; i += 100) {
        const chunk = metadataRefs.slice(i, i + 100);
        if (chunk.length === 0) continue;
        const docs = await db.getAll(...chunk.map(c => c.ref));
        for (let j = 0; j < docs.length; j += 1) {
          const source = chunk[j];
          const snap = docs[j];
          metadataMap.set(source.key, snap.exists ? (snap.data() || {}) : {});
        }
      }

      // Story-level fallback: some polls/questions keep their text inside story stickers.
      const uniqueStories = new Map(); // storyKey -> ref
      for (const candidate of merged) {
        const storyKey = `${candidate.authorId}:${candidate.storyId}`;
        if (!uniqueStories.has(storyKey)) {
          uniqueStories.set(storyKey, db.doc(`users/${candidate.authorId}/stories/${candidate.storyId}`));
        }
      }

      const storyEntries = [...uniqueStories.entries()];
      for (let i = 0; i < storyEntries.length; i += 100) {
        const chunk = storyEntries.slice(i, i + 100);
        if (chunk.length === 0) continue;
        const docs = await db.getAll(...chunk.map(([, ref]) => ref));
        for (let j = 0; j < docs.length; j += 1) {
          const [storyKey] = chunk[j];
          const snap = docs[j];
          storyMap.set(storyKey, snap.exists ? (snap.data() || {}) : {});
        }
      }

      const firstPollArrayFromStory = (storyData) => {
        if (!storyData || typeof storyData !== 'object') return [];
        const stickerContainers = [];
        if (Array.isArray(storyData.stickers)) stickerContainers.push(...storyData.stickers);
        if (Array.isArray(storyData.stickerData)) stickerContainers.push(...storyData.stickerData);

        for (const sticker of stickerContainers) {
          if (!sticker || typeof sticker !== 'object') continue;
          const interactionData = sticker.interactionData && typeof sticker.interactionData === 'object'
            ? sticker.interactionData
            : {};
          const directPollData = Array.isArray(sticker.pollData) ? sticker.pollData : null;
          const directPollOptions = Array.isArray(sticker.pollOptions) ? sticker.pollOptions : null;
          const interactionPollData = Array.isArray(interactionData.pollData) ? interactionData.pollData : null;
          const interactionPollOptions = Array.isArray(interactionData.pollOptions) ? interactionData.pollOptions : null;
          const anyPollArray = interactionPollData || interactionPollOptions || directPollData || directPollOptions;
          if (anyPollArray && anyPollArray.length > 0) return anyPollArray;
        }
        return [];
      };

      const firstQuestionTextFromStory = (storyData) => {
        if (!storyData || typeof storyData !== 'object') return null;
        const stickerContainers = [];
        if (Array.isArray(storyData.stickers)) stickerContainers.push(...storyData.stickers);
        if (Array.isArray(storyData.stickerData)) stickerContainers.push(...storyData.stickerData);

        for (const sticker of stickerContainers) {
          if (!sticker || typeof sticker !== 'object') continue;
          const interactionData = sticker.interactionData && typeof sticker.interactionData === 'object'
            ? sticker.interactionData
            : {};
          const directQuestionText = typeof sticker.questionText === 'string' ? sticker.questionText : null;
          const interactionQuestionText = typeof interactionData.questionText === 'string' ? interactionData.questionText : null;
          const value = interactionQuestionText || directQuestionText;
          if (value && value.trim()) return value;
        }
        return null;
      };

      const items = [];
      for (const candidate of merged) {
        const storyKey = `${candidate.authorId}:${candidate.storyId}`;
        const storyData = storyMap.get(storyKey) || {};
        const targetUsername = typeof storyData.username === 'string' ? storyData.username : null;

        if (candidate.kind === 'poll') {
          const key = `poll:${candidate.authorId}:${candidate.storyId}`;
          const metadata = metadataMap.get(key) || {};
          const pollData = Array.isArray(metadata.pollData) ? metadata.pollData : [];
          const storyPollData = firstPollArrayFromStory(storyData);

          let optionText = '';
          if (Number.isInteger(candidate.option) && candidate.option >= 0) {
            const metadataRaw = pollData[candidate.option + 1];
            const storyRaw = storyPollData[candidate.option + 1];
            const storyRawNoQuestion = storyPollData[candidate.option];
            if (typeof metadataRaw === 'string' && metadataRaw.trim()) optionText = metadataRaw;
            else if (typeof storyRaw === 'string' && storyRaw.trim()) optionText = storyRaw;
            else if (typeof storyRawNoQuestion === 'string' && storyRawNoQuestion.trim()) optionText = storyRawNoQuestion;
          }

          items.push({
            id: `${candidate.authorId}_${candidate.storyId}_${candidate.id}`,
            sourceId: candidate.id,
            kind: 'poll',
            authorId: candidate.authorId,
            storyId: candidate.storyId,
            targetUsername,
            actorId: uid,
            actorUsername,
            actorProfileImagePath,
            timestamp: candidate.timestampMs,
            pollOption: Number.isInteger(candidate.option) ? candidate.option : null,
            pollOptionText: optionText || null,
            questionText: null,
            responseText: null
          });
        } else {
          const key = `question:${candidate.authorId}:${candidate.storyId}`;
          const metadata = metadataMap.get(key) || {};
          const metadataQuestionText = typeof metadata.questionText === 'string' ? metadata.questionText : null;
          const storyQuestionText = firstQuestionTextFromStory(storyData);
          const questionText = metadataQuestionText || storyQuestionText;

          items.push({
            id: `${candidate.authorId}_${candidate.storyId}_${candidate.id}`,
            sourceId: candidate.id,
            kind: 'question',
            authorId: candidate.authorId,
            storyId: candidate.storyId,
            targetUsername,
            actorId: uid,
            actorUsername,
            actorProfileImagePath,
            timestamp: candidate.timestampMs,
            pollOption: null,
            pollOptionText: null,
            questionText,
            responseText: candidate.responseText || null
          });
        }

        if (items.length >= limit) break;
      }

      let nextCursor = null;
      const hasMoreScanned = pollSnap.size >= scanLimit || questionSnap.size >= scanLimit;
      if (hasMoreScanned) {
        const lastPollTs = pollSnap.size > 0 ? tsToMillis(pollSnap.docs[pollSnap.docs.length - 1].data().timestamp) : null;
        const lastQuestionTs = questionSnap.size > 0 ? tsToMillis(questionSnap.docs[questionSnap.docs.length - 1].data().timestamp) : null;
        const minTs = [lastPollTs, lastQuestionTs]
          .filter((v) => Number.isFinite(v) && v > 0)
          .reduce((acc, v) => Math.min(acc, v), Number.POSITIVE_INFINITY);
        if (Number.isFinite(minTs) && minTs > 0) {
          nextCursor = { timestamp: minTs };
        }
      }

      console.log(`✅ getStickerRepliesPage: uid=${uid}, poll=${pollCandidates.length}, question=${questionCandidates.length}, returned=${items.length}`);
      res.status(200).json({
        items,
        nextCursor,
        source: 'backend',
        totalCandidates: merged.length
      });
    } catch (error) {
      console.error('❌ getStickerRepliesPage error:', error);
      res.status(500).json({ error: 'Sticker replies fetch failed', details: error.message });
    }
  }
);

/**
 * 🏷️ getTaggedMomentsPage — Returns moments where viewer is tagged.
 *
 * POST body: { cursor?: { timestamp: number }, limit?: number }
 * Response:  {
 *   items: [{ moment, taggedAt, authorId, momentId, canView }],
 *   nextCursor,
 *   source,
 *   totalCandidates
 * }
 */
exports.getTaggedMomentsPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 60)) : 30;
    const cursorTimestamp = Number(body?.cursor?.timestamp || 0);

    const db = admin.firestore();

    try {
      let query = db.collectionGroup('moments')
        .where('taggedUsers', 'array-contains', targetUserId)
        .orderBy('timestamp', 'desc');

      if (Number.isFinite(cursorTimestamp) && cursorTimestamp > 0) {
        query = query.startAfter(admin.firestore.Timestamp.fromMillis(cursorTimestamp));
      }

      const snap = await query.limit(limit).get();

      if (snap.empty) {
        res.status(200).json({
          items: [],
          nextCursor: null,
          source: 'backend',
          totalCandidates: 0
        });
        return;
      }

      const viewerCtx = await buildViewerContext(uid);
      const authorIds = Array.from(new Set(
        snap.docs
          .map((doc) => doc.ref.path.split('/'))
          .filter((parts) => parts.length >= 4 && parts[0] === 'users' && parts[2] === 'moments')
          .map((parts) => parts[1])
      ));
      const authorMap = await batchLoadAuthorDocs(authorIds);

      const items = [];
      for (const doc of snap.docs) {
        const pathParts = doc.ref.path.split('/');
        if (pathParts.length < 4 || pathParts[0] !== 'users' || pathParts[2] !== 'moments') {
          continue;
        }

        const authorId = pathParts[1];
        const momentId = pathParts[3];
        const momentData = doc.data() || {};
        if (momentData.isArchived === true) continue;
        const authorData = authorMap.get(authorId);
        if (!authorData) continue;
        const canView = await canViewerSeeMoment(
          { id: momentId, authorId, ...momentData },
          uid,
          viewerCtx,
          authorData
        );
        if (!canView) continue;

        items.push({
          moment: serializeMoment(doc.id, momentData),
          taggedAt: tsToMillis(momentData.timestamp),
          authorId,
          momentId,
          canView: true
        });
      }

      let nextCursor = null;
      if (snap.size >= limit) {
        const lastDoc = snap.docs[snap.docs.length - 1];
        const lastTs = tsToMillis(lastDoc.data().timestamp);
        if (lastTs) {
          nextCursor = { timestamp: lastTs };
        }
      }

      console.log(`✅ getTaggedMomentsPage: uid=${uid}, scanned=${snap.size}, returned=${items.length}`);

      res.status(200).json({
        items,
        nextCursor,
        source: 'backend',
        totalCandidates: items.length
      });
    } catch (error) {
      console.error('❌ getTaggedMomentsPage error:', error);
      res.status(500).json({ error: 'Tagged moments fetch failed', details: error.message });
    }
  }
);

/**
 * 💬 getCommentedMomentsPage — Returns moments where viewer has commented.
 *
 * POST body: { cursor?: { timestamp: number }, limit?: number }
 * Response:  {
 *   items: [{ moment, comment: { id, content, timestamp, parentCommentId }, commentedAt, authorId, momentId, commentId, canView }],
 *   nextCursor,
 *   source,
 *   totalCandidates
 * }
 */
exports.getCommentedMomentsPage = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 40
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
    const rawLimit = Number(body.limit);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 60)) : 30;
    const cursorTimestamp = Number(body?.cursor?.timestamp || 0);

    const db = admin.firestore();

    try {
      let query = db.collectionGroup('comments')
        .where('authorId', '==', uid)
        .orderBy('timestamp', 'desc');

      if (Number.isFinite(cursorTimestamp) && cursorTimestamp > 0) {
        query = query.startAfter(admin.firestore.Timestamp.fromMillis(cursorTimestamp));
      }

      // Wider scan because we still need privacy filtering on related moments.
      const scanLimit = Math.max(limit * 6, 120);
      const commentsSnap = await query.limit(scanLimit).get();

      if (commentsSnap.empty) {
        res.status(200).json({
          items: [],
          nextCursor: null,
          source: 'backend',
          totalCandidates: 0
        });
        return;
      }

      const viewerCtx = await buildViewerContext(uid);
      const candidates = [];
      const momentTargets = new Map(); // momentPath -> { authorId, momentId }

      for (const doc of commentsSnap.docs) {
        const pathParts = doc.ref.path.split('/');
        if (pathParts.length < 6 || pathParts[0] !== 'users' || pathParts[2] !== 'moments' || pathParts[4] !== 'comments') {
          continue;
        }

        const authorId = pathParts[1];
        const momentId = pathParts[3];
        const commentId = pathParts[5];
        const data = doc.data() || {};

        const commentedAt = data.timestamp || null;
        const content = (typeof data.content === 'string' && data.content.trim())
          ? data.content
          : (typeof data.text === 'string' ? data.text : '');

        candidates.push({
          authorId,
          momentId,
          commentId,
          commentedAt,
          content,
          parentCommentId: typeof data.parentCommentId === 'string' ? data.parentCommentId : null
        });

        const momentPath = `users/${authorId}/moments/${momentId}`;
        if (!momentTargets.has(momentPath)) {
          momentTargets.set(momentPath, { authorId, momentId });
        }
      }

      if (candidates.length === 0) {
        const lastDoc = commentsSnap.docs[commentsSnap.docs.length - 1];
        const lastTimestamp = tsToMillis(lastDoc.data().timestamp);
        res.status(200).json({
          items: [],
          nextCursor: lastTimestamp ? { timestamp: lastTimestamp } : null,
          source: 'backend',
          totalCandidates: 0
        });
        return;
      }

      const uniqueMomentRefs = [];
      const authorIds = new Set();
      for (const target of momentTargets.values()) {
        const { authorId, momentId } = target;
        authorIds.add(authorId);
        uniqueMomentRefs.push(db.doc(`users/${authorId}/moments/${momentId}`));
      }

      const authorMap = await batchLoadAuthorDocs([...authorIds]);

      const momentDocs = [];
      for (let i = 0; i < uniqueMomentRefs.length; i += 100) {
        const chunk = uniqueMomentRefs.slice(i, i + 100);
        if (chunk.length === 0) continue;
        const docs = await db.getAll(...chunk);
        docs.forEach(doc => momentDocs.push(doc));
      }

      const momentMap = new Map();
      for (const doc of momentDocs) {
        if (!doc.exists) continue;
        const parts = doc.ref.path.split('/');
        if (parts.length < 4) continue;
        const key = `${parts[1]}_${parts[3]}`;
        momentMap.set(key, doc);
      }

      const items = [];
      for (const candidate of candidates) {
        const key = `${candidate.authorId}_${candidate.momentId}`;
        const momentDoc = momentMap.get(key);
        if (!momentDoc || !momentDoc.exists) continue;

        const momentData = momentDoc.data() || {};
        if (momentData.isArchived === true) continue;
        const authorData = authorMap.get(candidate.authorId);
        if (!authorData) continue;

        const canView = await canViewerSeeMoment(
          {
            id: momentDoc.id,
            authorId: candidate.authorId,
            audience: momentData.audience,
            taggedUsers: momentData.taggedUsers,
            customListId: momentData.customListId,
            isArchived: momentData.isArchived === true
          },
          uid,
          viewerCtx,
          authorData
        );

        items.push({
          moment: canView
            ? serializeMoment(momentDoc.id, momentData)
            : serializeRestrictedMoment(momentDoc.id, momentData),
          comment: {
            id: candidate.commentId,
            content: candidate.content,
            timestamp: tsToMillis(candidate.commentedAt),
            parentCommentId: candidate.parentCommentId
          },
          commentedAt: tsToMillis(candidate.commentedAt),
          authorId: candidate.authorId,
          momentId: candidate.momentId,
          commentId: candidate.commentId,
          canView
        });

        if (items.length >= limit) break;
      }

      let nextCursor = null;
      const hasMoreScanned = commentsSnap.size >= scanLimit;
      if (hasMoreScanned) {
        const lastDoc = commentsSnap.docs[commentsSnap.docs.length - 1];
        const lastTs = tsToMillis(lastDoc.data().timestamp);
        if (lastTs) {
          nextCursor = { timestamp: lastTs };
        }
      }

      console.log(`✅ getCommentedMomentsPage: uid=${uid}, scanned=${commentsSnap.size}, candidates=${candidates.length}, returned=${items.length}`);

      res.status(200).json({
        items,
        nextCursor,
        source: 'backend',
        totalCandidates: candidates.length
      });

    } catch (error) {
      console.error('❌ getCommentedMomentsPage error:', error);
      res.status(500).json({ error: 'Commented moments fetch failed', details: error.message });
    }
  }
);

/**
 * 🗑️ deleteMyCommentsBatch — Deletes the viewer's selected comments (and direct replies).
 *
 * POST body: { comments: [{ authorId, momentId, commentId }] }
 */
exports.deleteMyCommentsBatch = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 20
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
    const rawItems = Array.isArray(body.comments) ? body.comments : [];
    const trimmed = rawItems.slice(0, 50);
    const db = admin.firestore();

    try {
      // Deduplicate and validate payload
      const uniqueMap = new Map();
      for (const item of trimmed) {
        const authorId = typeof item?.authorId === 'string' ? item.authorId.trim() : '';
        const momentId = typeof item?.momentId === 'string' ? item.momentId.trim() : '';
        const commentId = typeof item?.commentId === 'string' ? item.commentId.trim() : '';
        if (!authorId || !momentId || !commentId) continue;
        const key = `${authorId}_${momentId}_${commentId}`;
        if (!uniqueMap.has(key)) {
          uniqueMap.set(key, { authorId, momentId, commentId });
        }
      }

      const targets = [...uniqueMap.values()];
      if (targets.length === 0) {
        res.status(200).json({ deleted: 0, skipped: 0, cascadedReplies: 0 });
        return;
      }

      // Verify ownership of root comments before deleting.
      let skipped = 0;
      const ownedTargets = [];
      for (const target of targets) {
        const ref = db.doc(`users/${target.authorId}/moments/${target.momentId}/comments/${target.commentId}`);
        const snap = await ref.get();
        if (!snap.exists) {
          skipped += 1;
          continue;
        }
        const data = snap.data() || {};
        if (data.authorId !== uid) {
          skipped += 1;
          continue;
        }
        ownedTargets.push(target);
      }

      if (ownedTargets.length === 0) {
        res.status(200).json({ deleted: 0, skipped, cascadedReplies: 0 });
        return;
      }

      const refsToDelete = new Map(); // path -> DocumentReference
      const decrementByMomentPath = new Map(); // momentPath -> count
      let cascadedReplies = 0;

      for (const target of ownedTargets) {
        const commentPath = `users/${target.authorId}/moments/${target.momentId}/comments/${target.commentId}`;
        refsToDelete.set(commentPath, db.doc(commentPath));

        const momentPath = `users/${target.authorId}/moments/${target.momentId}`;
        decrementByMomentPath.set(momentPath, (decrementByMomentPath.get(momentPath) || 0) + 1);

        const repliesSnap = await db
          .collection(`users/${target.authorId}/moments/${target.momentId}/comments`)
          .where('parentCommentId', '==', target.commentId)
          .get();

        for (const replyDoc of repliesSnap.docs) {
          if (!refsToDelete.has(replyDoc.ref.path)) {
            refsToDelete.set(replyDoc.ref.path, replyDoc.ref);
            decrementByMomentPath.set(momentPath, (decrementByMomentPath.get(momentPath) || 0) + 1);
            cascadedReplies += 1;
          }
        }
      }

      // Commit in chunks to stay below Firestore batch limits.
      let batch = db.batch();
      let ops = 0;
      let commits = 0;

      const flushBatch = async () => {
        if (ops === 0) return;
        await batch.commit();
        commits += 1;
        batch = db.batch();
        ops = 0;
      };

      for (const ref of refsToDelete.values()) {
        if (ops >= 420) await flushBatch();
        batch.delete(ref);
        ops += 1;
      }

      for (const [momentPath, count] of decrementByMomentPath.entries()) {
        if (ops >= 420) await flushBatch();
        batch.update(db.doc(momentPath), {
          commentCount: admin.firestore.FieldValue.increment(-count)
        });
        ops += 1;
      }

      await flushBatch();

      const deleted = refsToDelete.size;
      console.log(`✅ deleteMyCommentsBatch: uid=${uid}, deleted=${deleted}, skipped=${skipped}, cascadedReplies=${cascadedReplies}, commits=${commits}`);
      res.status(200).json({ deleted, skipped, cascadedReplies });

    } catch (error) {
      console.error('❌ deleteMyCommentsBatch error:', error);
      res.status(500).json({ error: 'Delete comments batch failed', details: error.message });
    }
  }
);

/**
 * 🏷️ removeMyTagsBatch — Removes the viewer from tagged moments in batch.
 *
 * POST body: { moments: [{ authorId, momentId }] }
 */
exports.removeMyTagsBatch = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 20
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
    const rawMoments = Array.isArray(body.moments) ? body.moments : [];
    if (rawMoments.length === 0) {
      res.status(400).json({ error: 'No moments provided' });
      return;
    }

    const targets = rawMoments
      .map((item) => ({
        authorId: typeof item?.authorId === 'string' ? item.authorId.trim() : '',
        momentId: typeof item?.momentId === 'string' ? item.momentId.trim() : ''
      }))
      .filter((item) => item.authorId && item.momentId);

    if (targets.length === 0) {
      res.status(400).json({ error: 'Invalid moments payload' });
      return;
    }

    const db = admin.firestore();
    let updated = 0;
    let skipped = 0;

    try {
      for (let i = 0; i < targets.length; i += 100) {
        const chunk = targets.slice(i, i + 100);
        if (chunk.length === 0) continue;

        const refs = chunk.map((target) => db.doc(`users/${target.authorId}/moments/${target.momentId}`));
        const docs = await db.getAll(...refs);
        const batch = db.batch();

        for (let j = 0; j < docs.length; j += 1) {
          const doc = docs[j];
          if (!doc.exists) {
            skipped += 1;
            continue;
          }

          const data = doc.data() || {};
          const taggedUsers = Array.isArray(data.taggedUsers) ? data.taggedUsers : [];
          if (!taggedUsers.includes(uid)) {
            skipped += 1;
            continue;
          }

          const nextTaggedUsers = taggedUsers.filter((id) => id !== uid);

          // Best effort: also remove tag entries in mediaItems.tags where userId/taggedUserId == uid.
          const mediaItems = Array.isArray(data.mediaItems) ? data.mediaItems : [];
          const nextMediaItems = mediaItems.map((mediaItem) => {
            if (!mediaItem || typeof mediaItem !== 'object') return mediaItem;
            const mediaTags = Array.isArray(mediaItem.tags) ? mediaItem.tags : null;
            if (!mediaTags) return mediaItem;
            const filteredTags = mediaTags.filter((tag) => {
              if (!tag || typeof tag !== 'object') return true;
              const tagUserId = typeof tag.userId === 'string' ? tag.userId : '';
              const taggedUserId = typeof tag.taggedUserId === 'string' ? tag.taggedUserId : '';
              return tagUserId !== uid && taggedUserId !== uid;
            });
            return {
              ...mediaItem,
              tags: filteredTags
            };
          });

          batch.update(doc.ref, {
            taggedUsers: nextTaggedUsers,
            mediaItems: nextMediaItems
          });
          updated += 1;
        }

        await batch.commit();
      }

      console.log(`✅ removeMyTagsBatch: uid=${uid}, updated=${updated}, skipped=${skipped}`);
      res.status(200).json({ updated, skipped });
    } catch (error) {
      console.error('❌ removeMyTagsBatch error:', error);
      res.status(500).json({ error: 'Remove tags batch failed', details: error.message });
    }
  }
);

/**
 * 🧹 removeMyStickerRepliesBatch — Deletes viewer's sticker replies (poll votes + question replies).
 *
 * POST body: { replies: [{ kind: "poll"|"question", authorId, storyId, sourceId? }] }
 */
exports.removeMyStickerRepliesBatch = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    concurrency: 20
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
    const rawReplies = Array.isArray(body.replies) ? body.replies : [];
    const trimmed = rawReplies.slice(0, 80);
    const db = admin.firestore();

    try {
      const unique = new Map();
      for (const item of trimmed) {
        const kind = typeof item?.kind === 'string' ? item.kind.trim().toLowerCase() : '';
        const authorId = typeof item?.authorId === 'string' ? item.authorId.trim() : '';
        const storyId = typeof item?.storyId === 'string' ? item.storyId.trim() : '';
        const sourceId = typeof item?.sourceId === 'string' ? item.sourceId.trim() : '';
        if (!kind || !authorId || !storyId) continue;
        if (kind !== 'poll' && kind !== 'question') continue;
        const key = `${kind}_${authorId}_${storyId}_${sourceId}`;
        if (!unique.has(key)) {
          unique.set(key, { kind, authorId, storyId, sourceId });
        }
      }

      const targets = [...unique.values()];
      if (targets.length === 0) {
        res.status(200).json({ deleted: 0, skipped: 0 });
        return;
      }

      const batch = db.batch();
      let deleted = 0;
      let skipped = 0;

      for (const target of targets) {
        if (target.kind === 'poll') {
          const ref = db.doc(`users/${target.authorId}/stories/${target.storyId}/pollVotes/${uid}`);
          const snap = await ref.get();
          if (!snap.exists) {
            skipped += 1;
            continue;
          }
          const data = snap.data() || {};
          if (data.userId !== uid) {
            skipped += 1;
            continue;
          }
          batch.delete(ref);
          deleted += 1;
          continue;
        }

        if (target.kind === 'question') {
          if (!target.sourceId) {
            skipped += 1;
            continue;
          }
          const ref = db.doc(`users/${target.authorId}/stories/${target.storyId}/questionResponses/${target.sourceId}`);
          const snap = await ref.get();
          if (!snap.exists) {
            skipped += 1;
            continue;
          }
          const data = snap.data() || {};
          if (data.userId !== uid) {
            skipped += 1;
            continue;
          }
          batch.delete(ref);
          deleted += 1;
        }
      }

      if (deleted > 0) {
        await batch.commit();
      }

      console.log(`✅ removeMyStickerRepliesBatch: uid=${uid}, deleted=${deleted}, skipped=${skipped}`);
      res.status(200).json({ deleted, skipped });
    } catch (error) {
      console.error('❌ removeMyStickerRepliesBatch error:', error);
      res.status(500).json({ error: 'Remove sticker replies batch failed', details: error.message });
    }
  }
);

// ============================================================================
// MARK: - WebAuthn / Passkeys (FIDO2) Endpoints
// ============================================================================

const rpName = 'Moments';
const rpID = 'momentsapp.app';
const expectedOrigin = [ `https://${rpID}`, rpID ]; // iOS uses rpID as origin or https://rpID

function isExpiredPasskeyChallenge(data) {
  if (!data?.expiresAt || typeof data.expiresAt.toMillis !== 'function') {
    return true;
  }
  return data.expiresAt.toMillis() <= Date.now();
}

exports.passkeyRegisterChallenge = onRequest({ timeoutSeconds: 30 }, async (req, res) => {
  setProxyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).send('');

  const uid = await verifyFirebaseAuth(req, res);
  if (!uid) return;

  try {
    const { generateRegistrationOptions } = require('@simplewebauthn/server');
    const userSnap = await admin.firestore().collection('users').doc(uid).get();
    const userData = userSnap.data() || {};
    const username = userData.username || uid;

    // Obtener passkeys existentes
    const passkeysSnap = await admin.firestore().collection('users').doc(uid).collection('passkeys').get();
    const existingPasskeys = passkeysSnap.docs.map(doc => {
      const data = doc.data();
      return {
        id: Buffer.from(data.id, 'base64url'),
        type: 'public-key',
      };
    });

    const options = await generateRegistrationOptions({
      rpName,
      rpID,
      userID: Buffer.from(uid),
      userName: username,
      excludeCredentials: existingPasskeys,
      authenticatorSelection: {
        residentKey: 'required',
        userVerification: 'required',
      },
    });

    // Guardar challenge en Firestore (expira en 5 mins)
    await admin.firestore().collection('passkeyChallenges').doc(uid).set({
      challenge: options.challenge,
      type: 'registration',
      expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 5 * 60 * 1000)),
    });

    res.status(200).json(options);
  } catch (error) {
    console.error('passkeyRegisterChallenge error:', error);
    res.status(500).json({ error: 'Failed to generate challenge' });
  }
});

exports.passkeyRegisterVerify = onRequest({ timeoutSeconds: 30 }, async (req, res) => {
  setProxyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).send('');

  const uid = await verifyFirebaseAuth(req, res);
  if (!uid) return;

  try {
    const { verifyRegistrationResponse } = require('@simplewebauthn/server');
    const body = parseJsonBody(req);

    const challengeRef = admin.firestore().collection('passkeyChallenges').doc(uid);
    const challengeDoc = await challengeRef.get();
    if (!challengeDoc.exists) {
      return res.status(400).json({ error: 'Challenge expired or not found' });
    }
    const challengeData = challengeDoc.data();
    if (isExpiredPasskeyChallenge(challengeData)) {
      await challengeRef.delete();
      return res.status(400).json({ error: 'Challenge expired or not found' });
    }
    const { challenge } = challengeData;

    // Eliminar challenge usado
    await challengeRef.delete();

    const verification = await verifyRegistrationResponse({
      response: body,
      expectedChallenge: challenge,
      expectedOrigin,
      expectedRPID: rpID,
      requireUserVerification: true,
    });

    if (verification.verified && verification.registrationInfo) {
      const { credential, credentialDeviceType, credentialBackedUp } = verification.registrationInfo;
      const { id, publicKey, counter } = credential;

      // Guardar Passkey en Firestore
      const passkeyIdStr = id; // Ya es un string base64url en v10+
      await admin.firestore().collection('users').doc(uid).collection('passkeys').doc(passkeyIdStr).set({
        id: passkeyIdStr,
        publicKey: Buffer.from(publicKey).toString('base64'),
        counter,
        deviceType: credentialDeviceType,
        backedUp: credentialBackedUp,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      res.status(200).json({ success: true });
    } else {
      res.status(400).json({ error: 'Verification failed' });
    }
  } catch (error) {
    console.error('passkeyRegisterVerify error:', error);
    res.status(500).json({ error: 'Failed to verify registration', details: error.message });
  }
});

exports.passkeyLoginChallenge = onRequest({ timeoutSeconds: 30 }, async (req, res) => {
  setProxyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).send('');

  // Login challenge es público, no requiere Firebase Auth previo
  try {
    const { generateAuthenticationOptions } = require('@simplewebauthn/server');

    const options = await generateAuthenticationOptions({
      rpID,
      userVerification: 'required',
    });

    // Guardar challenge con el propio ID del challenge (ya que no sabemos el uid aún)
    await admin.firestore().collection('passkeyChallenges').doc(options.challenge).set({
      challenge: options.challenge,
      type: 'login',
      expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 5 * 60 * 1000)),
    });

    res.status(200).json(options);
  } catch (error) {
    console.error('passkeyLoginChallenge error:', error);
    res.status(500).json({ error: 'Failed to generate authentication challenge' });
  }
});

exports.passkeyLoginVerify = onRequest({ timeoutSeconds: 30 }, async (req, res) => {
  setProxyCors(res);
  if (req.method === 'OPTIONS') return res.status(204).send('');

  try {
    const { verifyAuthenticationResponse } = require('@simplewebauthn/server');
    const body = parseJsonBody(req);

    // El frontend debe enviar el challenge usado en el body para que podamos buscarlo
    const clientChallenge = body.clientExtensionResults?.challenge || body.originalChallenge;
    if (!clientChallenge) {
       return res.status(400).json({ error: 'Missing originalChallenge in request' });
    }

    const challengeRef = admin.firestore().collection('passkeyChallenges').doc(clientChallenge);
    const challengeDoc = await challengeRef.get();
    if (!challengeDoc.exists) {
      return res.status(400).json({ error: 'Challenge expired or not found' });
    }
    const challengeData = challengeDoc.data();
    if (isExpiredPasskeyChallenge(challengeData)) {
      await challengeRef.delete();
      return res.status(400).json({ error: 'Challenge expired or not found' });
    }
    const { challenge } = challengeData;
    await challengeRef.delete();

    const passkeyIdStr = body.id;
    let passkeyDoc;

    // Si tenemos el userHandle (uid base64url), podemos buscar directamente sin collectionGroup
    if (body.response.userHandle) {
      const uidFromHandle = Buffer.from(body.response.userHandle, 'base64url').toString('utf8');
      passkeyDoc = await admin.firestore().collection('users').doc(uidFromHandle).collection('passkeys').doc(passkeyIdStr).get();
    }

    if (!passkeyDoc || !passkeyDoc.exists) {
      // Fallback a Collection Group por si acaso (ahora tiene índice)
      const passkeysSnap = await admin.firestore().collectionGroup('passkeys').where('id', '==', passkeyIdStr).get();
      if (passkeysSnap.empty) {
        return res.status(404).json({ error: 'Passkey not found in our records' });
      }
      passkeyDoc = passkeysSnap.docs[0];
    }

    const passkeyData = passkeyDoc.data();

    // El path es users/{uid}/passkeys/{passkeyId}
    const uid = passkeyDoc.ref.parent.parent.id;

    const verification = await verifyAuthenticationResponse({
      response: body,
      expectedChallenge: challenge,
      expectedOrigin,
      expectedRPID: rpID,
      credential: {
        id: passkeyData.id,
        publicKey: new Uint8Array(Buffer.from(passkeyData.publicKey, 'base64')),
        counter: passkeyData.counter,
        transports: passkeyData.transports || [],
      },
      requireUserVerification: true,
    });

    if (verification.verified) {
      const { newCounter } = verification.authenticationInfo;
      // Actualizar counter
      await passkeyDoc.ref.update({ counter: newCounter });

      // Generar Custom Token de Firebase Auth
      const customToken = await admin.auth().createCustomToken(uid);

      res.status(200).json({ customToken });
    } else {
      res.status(400).json({ error: 'Verification failed' });
    }
  } catch (error) {
    console.error('passkeyLoginVerify error:', error);
    res.status(500).json({ error: 'Failed to verify login', details: error.message });
  }
});
