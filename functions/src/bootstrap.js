const { onDocumentCreated, onDocumentDeleted, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { HttpsError, onCall, onRequest } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const { defineSecret } = require('firebase-functions/params');
const { RekognitionClient, DetectModerationLabelsCommand } = require('@aws-sdk/client-rekognition');
const JSZip = require('jszip');
const archiver = require('archiver');
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { spawn } = require('child_process');
const ffmpegPath = require('ffmpeg-static');
const { createImageModerationService } = require('../moderation');
const { policyFromFirestoreSettings } = require('../moderation/policy');

const VIDEO_DOWNLOAD_MAX_BYTES = 250 * 1024 * 1024;
const VIDEO_DOWNLOAD_TIMEOUT_MS = 60 * 1000;
const IMAGE_DOWNLOAD_MAX_BYTES = 15 * 1024 * 1024;
const IMAGE_DOWNLOAD_TIMEOUT_MS = 30 * 1000;
const PUBLISHABLE_IMAGE_EXTENSIONS = new Set(['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif']);
setGlobalOptions({ region: 'europe-southwest1', memory: '256MiB', concurrency: 80, retry: true });
const admin = require('firebase-admin');
if (!admin.apps.length) {
  admin.initializeApp();
}

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const SIGHTENGINE_USER = defineSecret('SIGHTENGINE_USER');
const SIGHTENGINE_SECRET = defineSecret('SIGHTENGINE_SECRET');
const AWS_ACCESS_KEY_ID = defineSecret('AWS_ACCESS_KEY_ID');
const AWS_SECRET_ACCESS_KEY = defineSecret('AWS_SECRET_ACCESS_KEY');
const AWS_REGION = defineSecret('AWS_REGION');
const GOOGLE_SPEECH_API_KEY = defineSecret('GOOGLE_SPEECH_API_KEY');
const GIPHY_API_KEY = defineSecret('GIPHY_API_KEY');
const TELEGRAM_BOT_TOKEN = defineSecret('TELEGRAM_BOT_TOKEN');
const TELEGRAM_CHAT_ID = defineSecret('TELEGRAM_CHAT_ID');
const ADMIN_PANEL_BASE_URL = 'https://momentsapp.app';

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

module.exports = {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
  onSchedule,
  HttpsError,
  onCall,
  onRequest,
  setGlobalOptions,
  defineSecret,
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
