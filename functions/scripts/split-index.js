#!/usr/bin/env node
/**
 * Splits monolithic index.js into modules under src/.
 * Run from functions/: node scripts/split-index.js
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const BACKUP = path.join(ROOT, 'index.legacy.js');
const SRC = fs.existsSync(BACKUP) ? BACKUP : path.join(ROOT, 'index.js');

const lines = fs.readFileSync(SRC, 'utf8').split('\n');

function slice(start, end) {
  return lines.slice(start - 1, end).join('\n');
}

function write(relPath, content) {
  const full = path.join(ROOT, relPath);
  fs.mkdirSync(path.dirname(full), { recursive: true });
  fs.writeFileSync(full, `${content.trimEnd()}\n`);
}

function collectFunctionNames(content) {
  const names = [];
  const re = /^(?:async )?function (\w+)/gm;
  let match;
  while ((match = re.exec(content)) !== null) {
    names.push(match[1]);
  }
  return names;
}

function wrapHelperChunk(content) {
  const names = collectFunctionNames(content);
  return `const b = require('../bootstrap');
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

${content}

module.exports = {
${names.map((name) => `  ${name},`).join('\n')}
};
`;
}

function wrapRegisterChunk(content) {
  const exportNames = [...content.matchAll(/^exports\.(\w+)/gm)].map((m) => m[1]);
  const body = content.replace(/^exports\./gm, 'const ');
  return `const b = require('../bootstrap');
const h = require('../helpers');
const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
  onSchedule,
  onRequest,
  admin,
  OPENAI_API_KEY,
  SIGHTENGINE_USER,
  SIGHTENGINE_SECRET,
  AWS_ACCESS_KEY_ID,
  AWS_SECRET_ACCESS_KEY,
  AWS_REGION,
  GOOGLE_SPEECH_API_KEY,
  GIPHY_API_KEY,
  TELEGRAM_BOT_TOKEN,
  TELEGRAM_CHAT_ID
} = b;
const {
${collectFunctionNames(require('fs').readFileSync(path.join(ROOT, 'src/helpers/index.js'), 'utf8') || '').map(() => '').join('')}
} = h;

${body}

module.exports = {
${exportNames.map((name) => `  ${name},`).join('\n')}
};
`;
}

if (!fs.existsSync(BACKUP)) {
  fs.copyFileSync(SRC, BACKUP);
  console.log('Backed up index.js -> index.legacy.js');
}

write('src/bootstrap.js', `${slice(1, 13)}
const { createImageModerationService } = require('../moderation');
const { policyFromFirestoreSettings } = require('../moderation/policy');

${slice(17, 22)}
const admin = require('firebase-admin');
if (!admin.apps.length) {
  admin.initializeApp();
}

${slice(26, 54)}

module.exports = {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
  onSchedule,
  onRequest,
  setGlobalOptions,
  defineSecret,
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
  admin,
  VIDEO_DOWNLOAD_MAX_BYTES,
  VIDEO_DOWNLOAD_TIMEOUT_MS,
  IMAGE_DOWNLOAD_MAX_BYTES,
  IMAGE_DOWNLOAD_TIMEOUT_MS,
  PUBLISHABLE_IMAGE_EXTENSIONS,
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
  ADMIN_PANEL_BASE_URL,
  GENTLE_REMINDER_VARIANTS,
  GENTLE_REMINDER_LIMITS
};
`);

function sliceRanges(ranges) {
  return ranges.map(([start, end]) => slice(start, end)).join('\n\n');
}

const helperChunks = [
  { file: 'src/helpers/moderation.js', ranges: [[56, 809]] },
  { file: 'src/helpers/storage-data-export.js', ranges: [[810, 1597], [1884, 2228]] },
  { file: 'src/helpers/auth.js', ranges: [[2230, 2555]] },
  { file: 'src/helpers/notifications.js', ranges: [[3084, 4108]] },
  { file: 'src/helpers/feed.js', ranges: [[7511, 8448]] }
];

const allHelperNames = [];

for (const chunk of helperChunks) {
  const content = sliceRanges(chunk.ranges);
  allHelperNames.push(...collectFunctionNames(content));
  write(chunk.file, wrapHelperChunk(content));
}

write('src/helpers/index.js', `const moderation = require('./moderation');
const storageDataExport = require('./storage-data-export');
const auth = require('./auth');
const notifications = require('./notifications');
const feed = require('./feed');

module.exports = {
  ...moderation,
  ...storageDataExport,
  ...auth,
  ...notifications,
  ...feed
};
`);

function wrapRegisterChunkFixed(content) {
  const exportNames = [...content.matchAll(/^exports\.(\w+)/gm)].map((m) => m[1]);
  const body = content.replace(/^exports\./gm, 'const ');
  const uniqueHelpers = [...new Set(allHelperNames)].sort();
  return `const b = require('../bootstrap');
const h = require('../helpers');
const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
  onSchedule,
  onRequest,
  admin,
  OPENAI_API_KEY,
  SIGHTENGINE_USER,
  SIGHTENGINE_SECRET,
  AWS_ACCESS_KEY_ID,
  AWS_SECRET_ACCESS_KEY,
  AWS_REGION,
  GOOGLE_SPEECH_API_KEY,
  GIPHY_API_KEY,
  TELEGRAM_BOT_TOKEN,
  TELEGRAM_CHAT_ID
} = b;
const {
  ${uniqueHelpers.join(',\n  ')}
} = h;

${body}

module.exports = {
${exportNames.map((name) => `  ${name},`).join('\n')}
};
`;
}

const registerChunks = [
  { file: 'src/registers/media.js', start: 1598, end: 1882 },
  { file: 'src/registers/incognito-export.js', start: 2557, end: 3081 },
  { file: 'src/registers/triggers-engagement.js', start: 4111, end: 5158 },
  { file: 'src/registers/triggers-social.js', start: 5159, end: 5518 },
  { file: 'src/registers/triggers-messaging.js', start: 5519, end: 6685 },
  { file: 'src/registers/triggers-cleanup.js', start: 6686, end: 7212 },
  { file: 'src/registers/http-account.js', start: 7213, end: 7510 },
  { file: 'src/registers/http-feed.js', start: 8456, end: 10845 },
  { file: 'src/registers/http-account-batch.js', start: 10846, end: 11428 },
  { file: 'src/registers/http-auth-cleanup.js', start: 11429, end: lines.length }
];

for (const chunk of registerChunks) {
  write(chunk.file, wrapRegisterChunkFixed(slice(chunk.start, chunk.end)));
}

write('index.js', `/**
 * Cloud Functions entrypoint — thin re-export layer.
 */

const registers = [
  require('./src/registers/media'),
  require('./src/registers/incognito-export'),
  require('./src/registers/triggers-engagement'),
  require('./src/registers/triggers-social'),
  require('./src/registers/triggers-messaging'),
  require('./src/registers/triggers-cleanup'),
  require('./src/registers/http-account'),
  require('./src/registers/http-feed'),
  require('./src/registers/http-account-batch'),
  require('./src/registers/http-auth-cleanup')
];

for (const register of registers) {
  Object.assign(exports, register);
}
`);

console.log(`Split complete: ${helperChunks.length} helper modules, ${registerChunks.length} register modules.`);
