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

const RECENT_AUTH_MAX_AGE_SECONDS = 5 * 60;

const { setProxyCors, parseJsonBody } = require('./moderation');

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

module.exports = {
  setProxyCors,
  parseJsonBody,
  verifyFirebaseAuth,
  normalizeTimeZoneIdentifier,
  timestampToDate,
  getDateKeyForTimeZone,
  buildDefaultIncognitoState,
  resolveIncognitoState,
  persistableIncognitoState,
  incognitoStateNeedsPersistence,
  serializeIncognitoStateForResponse,
  runIncognitoTransition,
  createIncognitoHandler,
};
