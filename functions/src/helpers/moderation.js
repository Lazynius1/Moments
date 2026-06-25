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

const { runFfmpeg } = require('./storage-data-export');

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

function escapeTelegramHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

async function sendTelegramModerationAlert(payload) {
  const botToken = TELEGRAM_BOT_TOKEN.value();
  const chatId = TELEGRAM_CHAT_ID.value();

  if (!botToken || !chatId) {
    console.warn('Telegram moderation alert skipped: missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID');
    return;
  }

  const heading = payload.contentVisible === false
    ? '⛔️ <b>Contenido ocultado automáticamente</b>'
    : '🚨 <b>Nueva revisión de moderación</b>';

  const scoreParts = [];
  if (typeof payload.visualScore === 'number') scoreParts.push(`visual ${payload.visualScore.toFixed(3)}`);
  if (typeof payload.audioScore === 'number') scoreParts.push(`audio ${payload.audioScore.toFixed(3)}`);
  if (typeof payload.combinedScore === 'number') scoreParts.push(`combined ${payload.combinedScore.toFixed(3)}`);

  const lines = [
    heading,
    `Usuario: <b>${escapeTelegramHtml(payload.username || 'desconocido')}</b>`,
    `UID: <code>${escapeTelegramHtml(payload.userId || '')}</code>`,
    `Tipo: <b>${escapeTelegramHtml(payload.contentType || 'unknown')}</b>`,
    `Scope: <b>${escapeTelegramHtml(payload.moderationScope || 'unknown')}</b>`,
    payload.reviewSource ? `Origen: <code>${escapeTelegramHtml(payload.reviewSource)}</code>` : null,
    `Categoría: <b>${escapeTelegramHtml(payload.category || 'general')}</b>`,
    `Motivo: ${escapeTelegramHtml(payload.reason || 'Sin motivo')}`,
    `Proveedor: <b>${escapeTelegramHtml(payload.provider || 'backend')}</b>`,
    `Fallback: <b>${payload.fallbackUsed ? 'sí' : 'no'}</b>`,
    payload.visibilitySummary ? `Estado: <b>${escapeTelegramHtml(payload.visibilitySummary)}</b>` : null,
    payload.audienceSummary ? `Audiencia: <code>${escapeTelegramHtml(payload.audienceSummary)}</code>` : null,
    scoreParts.length > 0 ? `Scores: <code>${escapeTelegramHtml(scoreParts.join(' · '))}</code>` : null,
    payload.topSignals ? `Señales: ${escapeTelegramHtml(payload.topSignals)}` : null,
    payload.mediaType ? `Media: <code>${escapeTelegramHtml(payload.mediaType)}</code>` : null,
    payload.contentId ? `Content ID: <code>${escapeTelegramHtml(payload.contentId)}</code>` : null,
    payload.createdAt ? `Hora: <code>${escapeTelegramHtml(payload.createdAt)}</code>` : null
  ].filter(Boolean);

  const text = lines.join('\n');
  const sendPayload = {
    chat_id: chatId,
    parse_mode: 'HTML',
    disable_web_page_preview: true,
    reply_markup: buildModerationTelegramReplyMarkup(payload)
  };

  const photoUrl = payload.photoUrl;
  const endpoint = photoUrl ? 'sendPhoto' : 'sendMessage';
  const body = photoUrl
    ? { ...sendPayload, photo: photoUrl, caption: text }
    : { ...sendPayload, text };

  const response = await fetch(`https://api.telegram.org/bot${botToken}/${endpoint}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });

  if (!response.ok) {
    const errorText = await response.text();
    if (photoUrl) {
      const fallbackResponse = await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ ...sendPayload, text })
      });
      if (fallbackResponse.ok) {
        return;
      }
      const fallbackError = await fallbackResponse.text();
      throw new Error(`Telegram sendPhoto failed (${response.status}): ${errorText}; sendMessage fallback failed: ${fallbackError}`);
    }
    throw new Error(`Telegram sendMessage failed (${response.status}): ${errorText}`);
  }
}

function buildInlineKeyboardButton(text, url) {
  if (!url) return null;
  return { text, url };
}

function buildModerationTelegramReplyMarkup(payload) {
  const panelUrl = `${ADMIN_PANEL_BASE_URL}/nexus/admin`;

  const rows = [
    [
      buildInlineKeyboardButton('Abrir panel', panelUrl),
      buildInlineKeyboardButton('Abrir media', payload.photoUrl || '')
    ].filter(Boolean)
  ].filter((row) => row.length > 0);

  if (rows.length === 0) {
    return undefined;
  }

  return { inline_keyboard: rows };
}

function summarizeTopSignals(details = {}) {
  const labels = Array.isArray(details.labels) ? details.labels : [];
  if (labels.length > 0) {
    return labels
      .slice(0, 3)
      .map((label) => `${label.Name || 'unknown'} ${Number(label.Confidence || 0).toFixed(1)}%`)
      .join(' · ');
  }

  const canonical = details.canonicalSignals || {};
  const canonicalEntries = [
    ['explicitSexualActivity', canonical.explicitSexualActivity],
    ['explicitSexualDisplay', canonical.explicitSexualDisplay],
    ['explicitFemaleIntimateExposure', canonical.explicitFemaleIntimateExposure],
    ['allowedMaleUnderwear', canonical.allowedMaleUnderwear],
    ['allowedFemaleSwimwear', canonical.allowedFemaleSwimwear],
    ['suggestive', canonical.suggestive],
    ['impliedNudity', canonical.impliedNudity]
  ].filter(([, value]) => typeof value === 'number' && value > 0);

  if (canonicalEntries.length > 0) {
    return canonicalEntries
      .slice(0, 4)
      .map(([key, value]) => `${key} ${Number(value).toFixed(3)}`)
      .join(' · ');
  }

  const nudity = details.nudity || {};
  const signalEntries = [
    ['sexual_display', nudity.sexual_display],
    ['sexual_activity', nudity.sexual_activity],
    ['erotica', nudity.erotica],
    ['sexting', nudity.sexting]
  ].filter(([, value]) => typeof value === 'number' && value > 0);

  if (signalEntries.length > 0) {
    return signalEntries
      .slice(0, 4)
      .map(([key, value]) => `${key} ${Number(value).toFixed(3)}`)
      .join(' · ');
  }

  return '';
}

async function buildModerationAlertPayload(queueId, data) {
  const userId = data.userId || '';
  let username = 'desconocido';
  let contentDocData = null;

  if (userId) {
    const userDoc = await admin.firestore().doc(`users/${userId}`).get();
    if (userDoc.exists) {
      username = userDoc.data()?.username || username;
    }
  }

  if (userId && data.contentId && data.contentType) {
    const collectionName = data.contentType === 'story' ? 'stories' : 'moments';
    const contentDoc = await admin.firestore().doc(`users/${userId}/${collectionName}/${data.contentId}`).get();
    if (contentDoc.exists) {
      contentDocData = contentDoc.data() || null;
    }
  }

  let photoUrl = '';
  if (typeof data.mediaURL === 'string' && /^https?:\/\//.test(data.mediaURL)) {
    photoUrl = data.mediaURL;
  } else if (contentDocData) {
    if (data.contentType === 'story') {
      photoUrl = contentDocData.originalMediaURL || contentDocData.imagePath || contentDocData.mediaItem?.url || '';
    } else {
      photoUrl = contentDocData.originalMediaURL || contentDocData.imagePath || contentDocData.imageUrl || contentDocData.mediaItems?.[0]?.url || '';
    }
  }

  const originalAudience = contentDocData?.originalAudience || '';
  const currentAudience = contentDocData?.audience || '';
  const audienceSummary = originalAudience && currentAudience && originalAudience !== currentAudience
    ? `${originalAudience} -> ${currentAudience}`
    : (currentAudience || originalAudience || '');

  const visibilitySummary = data.contentVisible === false
    ? 'oculto solo para el autor'
    : 'visible, pendiente de revisión';

  const details = data.details || {};

  return {
    userId,
    username,
    contentId: data.contentId || queueId,
    contentType: data.contentType || 'unknown',
    moderationScope: data.moderationScope || 'unknown',
    reason: data.reason || 'Sin motivo',
    category: data.category || 'general',
    provider: data.provider || 'backend',
    fallbackUsed: data.fallbackUsed === true,
    mediaType: data.mediaType || '',
    photoUrl,
    visibilitySummary,
    audienceSummary,
    reviewSource: data.reviewSource || '',
    visualScore: typeof data.visualScore === 'number' ? data.visualScore : null,
    audioScore: typeof data.audioScore === 'number' ? data.audioScore : null,
    combinedScore: typeof data.combinedScore === 'number' ? data.combinedScore : null,
    topSignals: summarizeTopSignals(details),
    contentVisible: data.contentVisible !== false,
    createdAt: new Date().toLocaleString('es-ES', { timeZone: 'Europe/Madrid' })
  };
}

async function buildModerationReviewRequestAlertPayload(requestId, data) {
  const userId = data.userId || '';
  let username = 'desconocido';
  let contentDocData = null;

  if (userId) {
    const userDoc = await admin.firestore().doc(`users/${userId}`).get();
    if (userDoc.exists) {
      username = userDoc.data()?.username || username;
    }
  }

  if (userId && data.contentId && data.contentType) {
    const collectionName = data.contentType === 'story' ? 'stories' : 'moments';
    const contentDoc = await admin.firestore().doc(`users/${userId}/${collectionName}/${data.contentId}`).get();
    if (contentDoc.exists) {
      contentDocData = contentDoc.data() || null;
    }
  }

  let photoUrl = '';
  if (contentDocData) {
    if (data.contentType === 'story') {
      photoUrl = contentDocData.originalMediaURL || contentDocData.imagePath || contentDocData.mediaItem?.url || '';
    } else {
      photoUrl = contentDocData.originalMediaURL || contentDocData.imagePath || contentDocData.imageUrl || contentDocData.mediaItems?.[0]?.url || '';
    }
  }

  const scope = data.moderationScope || (data.contentType ? 'content_review' : 'content_review');
  const title = '📩 <b>Nueva solicitud de revisión de contenido</b>';
  const contentSnapshot = data.contentSnapshot || {};
  const hiddenSummary = contentSnapshot.isModerationHidden === true ? 'sí' : 'no';
  const audienceSummary = contentSnapshot.originalAudience && contentSnapshot.audience
    ? `${contentSnapshot.originalAudience} -> ${contentSnapshot.audience}`
    : (contentSnapshot.audience || contentSnapshot.originalAudience || '');

  const lines = [
    title,
    `Usuario: <b>${escapeTelegramHtml(username)}</b>`,
    `UID: <code>${escapeTelegramHtml(userId)}</code>`,
    `Request ID: <code>${escapeTelegramHtml(requestId)}</code>`,
    data.ticketNumber ? `Ticket: <code>${escapeTelegramHtml(data.ticketNumber)}</code>` : null,
    data.contentType ? `Tipo: <b>${escapeTelegramHtml(data.contentType)}</b>` : null,
    `Scope: <b>${escapeTelegramHtml(scope)}</b>`,
    data.status ? `Estado: <b>${escapeTelegramHtml(data.status)}</b>` : null,
    data.priority ? `Prioridad: <b>${escapeTelegramHtml(data.priority)}</b>` : null,
    data.moderationCategory ? `Categoría: <b>${escapeTelegramHtml(data.moderationCategory)}</b>` : null,
    data.contactEmail ? `Email: <code>${escapeTelegramHtml(data.contactEmail)}</code>` : null,
    data.reviewMessage ? `Mensaje: ${escapeTelegramHtml(data.reviewMessage)}` : null,
    data.additionalInfo ? `Info extra: ${escapeTelegramHtml(data.additionalInfo)}` : null,
    data.contentId ? `Content ID: <code>${escapeTelegramHtml(data.contentId)}</code>` : null,
    audienceSummary ? `Audiencia: <b>${escapeTelegramHtml(audienceSummary)}</b>` : null,
    `Oculto ahora: <b>${escapeTelegramHtml(hiddenSummary)}</b>`
  ].filter(Boolean);

  return {
    photoUrl,
    text: lines.join('\n'),
    replyMarkup: {
      inline_keyboard: [
        [
          buildInlineKeyboardButton('Abrir panel', `${ADMIN_PANEL_BASE_URL}/nexus/admin`),
          buildInlineKeyboardButton('Abrir media', photoUrl || '')
        ].filter(Boolean)
      ].filter((row) => row.length > 0)
    }
  };
}

async function sendTelegramTextOrPhoto({ photoUrl, text, replyMarkup }) {
  const botToken = TELEGRAM_BOT_TOKEN.value();
  const chatId = TELEGRAM_CHAT_ID.value();

  if (!botToken || !chatId) {
    console.warn('Telegram alert skipped: missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID');
    return;
  }

  const sendPayload = {
    chat_id: chatId,
    parse_mode: 'HTML',
    disable_web_page_preview: true,
    reply_markup: replyMarkup
  };

  const endpoint = photoUrl ? 'sendPhoto' : 'sendMessage';
  const body = photoUrl
    ? { ...sendPayload, photo: photoUrl, caption: text }
    : { ...sendPayload, text };

  const response = await fetch(`https://api.telegram.org/bot${botToken}/${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });

  if (!response.ok) {
    const errorText = await response.text();
    if (photoUrl) {
      const fallbackResponse = await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...sendPayload, text })
      });
      if (fallbackResponse.ok) return;
      const fallbackError = await fallbackResponse.text();
      throw new Error(`Telegram sendPhoto failed (${response.status}): ${errorText}; sendMessage fallback failed: ${fallbackError}`);
    }
    throw new Error(`Telegram sendMessage failed (${response.status}): ${errorText}`);
  }
}

function approvedModerationDecision(extra = {}) {
  return {
    action: 'approved',
    reason: 'Contenido apropiado',
    category: 'clean',
    visualScore: 0,
    audioScore: null,
    combinedScore: 0,
    details: {},
    ...extra
  };
}

function warningModerationDecision(reason, category, extra = {}) {
  return {
    action: 'warning',
    reason,
    category,
    visualScore: 0,
    audioScore: null,
    combinedScore: 0,
    details: {},
    ...extra
  };
}

function deletedModerationDecision(reason, category, extra = {}) {
  return {
    action: 'deleted',
    reason,
    category,
    visualScore: 1,
    audioScore: null,
    combinedScore: 1,
    details: {},
    ...extra
  };
}

function mergeModerationDecisions(decisions = []) {
  const validDecisions = decisions.filter(Boolean);
  if (validDecisions.length === 0) {
    return approvedModerationDecision();
  }

  const deleted = validDecisions.find((item) => item.action === 'deleted');
  if (deleted) return deleted;

  const warning = validDecisions.find((item) => item.action === 'warning');
  if (warning) return warning;

  return validDecisions[0];
}

function createRekognitionClient() {
  return new RekognitionClient({
    region: AWS_REGION.value() || 'eu-west-1',
    credentials: {
      accessKeyId: AWS_ACCESS_KEY_ID.value(),
      secretAccessKey: AWS_SECRET_ACCESS_KEY.value()
    }
  });
}

function storageCustomMetadata(metadata = {}) {
  return metadata.metadata && typeof metadata.metadata === 'object' ? metadata.metadata : {};
}

function storageMetadataOwnerMatches(metadata, uid) {
  const ownerId = String(storageCustomMetadata(metadata).ownerId || '').trim();
  return Boolean(ownerId && uid && ownerId === String(uid).trim());
}

function expectedImageMetadataFromObjectName(objectName) {
  const parts = objectName.split('/');
  if (parts.length === 6 && parts[2] === 'moments' && parts[4] === 'media') {
    return { type: 'moment_image', contentKey: 'momentId', contentId: parts[3] };
  }
  if (parts.length === 6 && parts[2] === 'stories' && parts[4] === 'media') {
    return { type: 'story_image', contentKey: 'storyId', contentId: parts[3] };
  }
  if (parts.length === 7 && parts[2] === 'moments' && parts[4] === 'hidden_layers') {
    return { type: 'moment_hidden_layer_image', contentKey: 'momentId', contentId: parts[3], layerId: parts[5] };
  }
  return null;
}

async function downloadStorageObjectToBuffer({
  bucket,
  objectName,
  uid,
  maxBytes = IMAGE_DOWNLOAD_MAX_BYTES,
  expectedPrefix = 'image/',
  timeoutMs = IMAGE_DOWNLOAD_TIMEOUT_MS
}) {
  const file = bucket.file(objectName);
  const [metadata] = await file.getMetadata();

  if (!storageMetadataOwnerMatches(metadata, uid)) {
    throw new Error('Storage object owner metadata does not match this user');
  }

  const customMetadata = storageCustomMetadata(metadata);
  const expectedMetadata = expectedImageMetadataFromObjectName(objectName);
  if (!expectedMetadata || customMetadata.type !== expectedMetadata.type) {
    throw new Error('Storage object is not approved image media');
  }
  if (String(customMetadata[expectedMetadata.contentKey] || '').trim() !== expectedMetadata.contentId) {
    throw new Error('Storage object content metadata does not match its path');
  }
  if (expectedMetadata.layerId && String(customMetadata.layerId || '').trim() !== expectedMetadata.layerId) {
    throw new Error('Storage object layer metadata does not match its path');
  }

  const size = Number(metadata.size || 0);
  if (size > maxBytes) {
    throw new Error('Image download exceeds maximum allowed size');
  }

  const contentType = String(metadata.contentType || '').toLowerCase();
  if (!contentType || !contentType.startsWith(expectedPrefix)) {
    throw new Error('Storage object is not an image');
  }

  return new Promise((resolve, reject) => {
    let settled = false;
    let receivedBytes = 0;
    const chunks = [];
    const readStream = file.createReadStream();
    const timeout = setTimeout(() => {
      readStream.destroy(new Error('Image download timed out'));
    }, timeoutMs);

    const done = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (error) {
        reject(error);
      } else {
        resolve(Buffer.concat(chunks));
      }
    };

    readStream.on('data', (chunk) => {
      receivedBytes += chunk.length;
      if (receivedBytes > maxBytes) {
        readStream.destroy(new Error('Image download exceeds maximum allowed size'));
        return;
      }
      chunks.push(chunk);
    });
    readStream.on('error', done);
    readStream.on('end', () => done());
  });
}

async function callOpenAIModeration(input) {
  const upstream = await fetch('https://api.openai.com/v1/moderations', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${OPENAI_API_KEY.value()}`
    },
    body: JSON.stringify({ input })
  });

  const payloadText = await upstream.text();
  if (!upstream.ok) {
    throw new Error(`OpenAI moderation failed with status ${upstream.status}: ${payloadText.slice(0, 300)}`);
  }

  return JSON.parse(payloadText);
}

async function transcribeAudioBuffer(audioBuffer) {
  const speechURL = `https://speech.googleapis.com/v1/speech:recognize?key=${encodeURIComponent(GOOGLE_SPEECH_API_KEY.value())}`;
  const requestBody = {
    config: {
      encoding: 'LINEAR16',
      sampleRateHertz: 44100,
      languageCode: 'es-ES',
      enableAutomaticPunctuation: true,
      model: 'latest_short'
    },
    audio: {
      content: audioBuffer.toString('base64')
    }
  };

  const upstream = await fetch(speechURL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(requestBody)
  });

  const payloadText = await upstream.text();
  if (!upstream.ok) {
    throw new Error(`Speech-to-text failed with status ${upstream.status}: ${payloadText.slice(0, 300)}`);
  }

  const payload = JSON.parse(payloadText);
  const results = Array.isArray(payload.results) ? payload.results : [];
  const transcript = results
    .flatMap((result) => Array.isArray(result.alternatives) ? result.alternatives : [])
    .map((alt) => (typeof alt.transcript === 'string' ? alt.transcript.trim() : ''))
    .filter(Boolean)
    .join(' ')
    .trim();

  return transcript;
}

function evaluateTranscriptModerationPayload(payload) {
  const result = Array.isArray(payload.results) ? payload.results[0] : null;
  if (!result || result.flagged !== true) {
    return approvedModerationDecision({ provider: 'openai', audioScore: 0.1, combinedScore: 0.1 });
  }

  const categories = result.categories || {};
  const hasSevere =
    categories['sexual/minors'] ||
    categories['violence/graphic'] ||
    categories['harassment/threatening'] ||
    categories['hate/threatening'];

  if (hasSevere) {
    return deletedModerationDecision('Audio ofensivo o dañino detectado', 'audio_toxic', {
      provider: 'openai',
      audioScore: 1,
      combinedScore: 1,
      details: { categories }
    });
  }

  return warningModerationDecision('Audio potencialmente sensible detectado', 'audio_toxic', {
    provider: 'openai',
    audioScore: 0.6,
    combinedScore: 0.6,
    details: { categories }
  });
}

let cachedModerationPolicy = null;
let cachedModerationPolicyAt = 0;

async function loadModerationPolicy() {
  const now = Date.now();
  if (cachedModerationPolicy && now - cachedModerationPolicyAt < 60_000) {
    return cachedModerationPolicy;
  }

  const settingsDoc = await admin.firestore().collection('moderationSettings').doc('media').get();
  cachedModerationPolicy = policyFromFirestoreSettings(settingsDoc.exists ? settingsDoc.data() : null);
  cachedModerationPolicyAt = now;
  return cachedModerationPolicy;
}

async function callSightengineModeration(imageBuffer) {
  const formData = new FormData();
  formData.append('api_user', SIGHTENGINE_USER.value());
  formData.append('api_secret', SIGHTENGINE_SECRET.value());
  formData.append('models', 'nudity-2.1,face-attributes,scam,offensive');
  formData.append('media', new Blob([imageBuffer], { type: 'image/jpeg' }), 'frame.jpg');

  const upstream = await fetch('https://api.sightengine.com/1.0/check.json', {
    method: 'POST',
    body: formData
  });

  const payloadText = await upstream.text();
  if (!upstream.ok) {
    throw new Error(`Sightengine failed with status ${upstream.status}: ${payloadText.slice(0, 300)}`);
  }

  const payload = JSON.parse(payloadText);
  if (payload?.status === 'failure') {
    throw new Error(`Sightengine returned failure: ${payloadText.slice(0, 300)}`);
  }

  return payload;
}

async function callRekognitionModeration(imageBuffer) {
  const client = createRekognitionClient();
  const response = await client.send(new DetectModerationLabelsCommand({
    Image: { Bytes: imageBuffer },
    MinConfidence: 70
  }));
  return response;
}

const imageModerationService = createImageModerationService({
  callSightengineModeration,
  callRekognitionModeration,
  loadPolicy: loadModerationPolicy,
  forceProvider: process.env.MODERATION_FORCE_PROVIDER || null
});

async function moderateImageBufferWithFallback(imageBuffer) {
  return imageModerationService.moderateImageBufferWithFallback(imageBuffer);
}

async function extractModerationFramesFromVideo(localVideoPath) {
  const outputDir = path.join(os.tmpdir(), `moderation_frames_${Date.now()}_${crypto.randomUUID()}`);
  fs.mkdirSync(outputDir, { recursive: true });
  const outputPattern = path.join(outputDir, 'frame_%03d.jpg');

  await runFfmpeg([
    '-y',
    '-i', localVideoPath,
    '-vf', 'fps=1/5,scale=640:360:force_original_aspect_ratio=decrease',
    '-frames:v', '3',
    outputPattern
  ]);

  const frameFiles = fs.readdirSync(outputDir)
    .filter((fileName) => fileName.endsWith('.jpg'))
    .sort()
    .slice(0, 3)
    .map((fileName) => path.join(outputDir, fileName));

  const frames = frameFiles.map((filePath) => fs.readFileSync(filePath));
  return { frames, outputDir };
}

async function extractModerationAudioFromVideo(localVideoPath) {
  const outputPath = path.join(os.tmpdir(), `moderation_audio_${Date.now()}_${crypto.randomUUID()}.wav`);
  await runFfmpeg([
    '-y',
    '-i', localVideoPath,
    '-t', '10',
    '-vn',
    '-ac', '1',
    '-ar', '44100',
    '-acodec', 'pcm_s16le',
    outputPath
  ]);

  const audioBuffer = fs.readFileSync(outputPath);
  return { audioBuffer, outputPath };
}

async function moderateVideoFileWithFallback(localVideoPath) {
  let frameOutputDir = null;
  let audioOutputPath = null;

  try {
    const { frames, outputDir } = await extractModerationFramesFromVideo(localVideoPath);
    frameOutputDir = outputDir;

    const frameDecisions = [];
    for (const frame of frames) {
      frameDecisions.push(await moderateImageBufferWithFallback(frame));
    }

    const visualDecision = mergeModerationDecisions(frameDecisions);
    const visualScore = Math.max(...frameDecisions.map((item) => Number(item.visualScore || 0)), 0);

    let audioDecision = null;
    try {
      const extractedAudio = await extractModerationAudioFromVideo(localVideoPath);
      audioOutputPath = extractedAudio.outputPath;
      const transcript = await transcribeAudioBuffer(extractedAudio.audioBuffer);
      if (transcript) {
        const moderationPayload = await callOpenAIModeration(transcript);
        audioDecision = evaluateTranscriptModerationPayload(moderationPayload);
        audioDecision.details = {
          ...(audioDecision.details || {}),
          transcript
        };
      }
    } catch (audioError) {
      audioDecision = null;
    }

    const finalDecision = mergeModerationDecisions([visualDecision, audioDecision]);
    const audioScore = audioDecision ? Number(audioDecision.audioScore || audioDecision.combinedScore || 0) : null;
    const combinedScore = Math.max(visualScore, Number(audioScore || 0));

    return {
      ...finalDecision,
      visualScore,
      audioScore,
      combinedScore,
      details: {
        framesAnalyzed: frameDecisions.length,
        frameProviders: frameDecisions.map((item) => item.provider || item.details?.provider || 'unknown'),
        visualDecision,
        audioDecision
      }
    };
  } finally {
    if (frameOutputDir) {
      try { fs.rmSync(frameOutputDir, { recursive: true, force: true }); } catch (error) {}
    }
    if (audioOutputPath) {
      try { fs.unlinkSync(audioOutputPath); } catch (error) {}
    }
  }
}


module.exports = {
  runFfmpeg,
  setProxyCors,
  parseJsonBody,
  escapeTelegramHtml,
  sendTelegramModerationAlert,
  buildInlineKeyboardButton,
  buildModerationTelegramReplyMarkup,
  summarizeTopSignals,
  buildModerationAlertPayload,
  buildModerationReviewRequestAlertPayload,
  sendTelegramTextOrPhoto,
  approvedModerationDecision,
  warningModerationDecision,
  deletedModerationDecision,
  mergeModerationDecisions,
  createRekognitionClient,
  storageCustomMetadata,
  storageMetadataOwnerMatches,
  expectedImageMetadataFromObjectName,
  downloadStorageObjectToBuffer,
  callOpenAIModeration,
  transcribeAudioBuffer,
  evaluateTranscriptModerationPayload,
  loadModerationPolicy,
  callSightengineModeration,
  callRekognitionModeration,
  moderateImageBufferWithFallback,
  extractModerationFramesFromVideo,
  extractModerationAudioFromVideo,
  moderateVideoFileWithFallback,
};
