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

const { pickMomentPreviewUrl } = require('./notifications');

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
  const muteSettings = viewerData.muteSettings && typeof viewerData.muteSettings === 'object' ? viewerData.muteSettings : {};
  const mutedUsers = new Set(Array.isArray(muteSettings.mutedUsers) ? muteSettings.mutedUsers : []);
  const viewerInterests = Array.isArray(viewerData.interests)
    ? viewerData.interests.filter((interest) => typeof interest === 'string' && interest.trim().length > 0)
    : [];

  return { following, followers, mutuals, bestFriends, blockedUsers, mutedUsers, viewerInterests };
}

function isExcludedForYouAuthor(authorId, uid, viewerCtx) {
  if (!authorId || authorId === uid) return true;
  if (viewerCtx.following.has(authorId)) return true;
  if (viewerCtx.blockedUsers.has(authorId)) return true;
  return false;
}

async function fetchForYouInterestUserIds(db, uid, viewerCtx, cap = 40) {
  const interests = viewerCtx.viewerInterests || [];
  if (interests.length === 0) return new Set();

  const result = new Set();
  const batchSize = 30;
  for (let i = 0; i < interests.length && result.size < cap; i += batchSize) {
    const batch = interests.slice(i, i + batchSize);
    const snap = await db.collection('users')
      .where('interests', 'array-contains-any', batch)
      .limit(50)
      .get();
    snap.docs.forEach((doc) => {
      if (result.size >= cap) return;
      if (!isExcludedForYouAuthor(doc.id, uid, viewerCtx)) {
        result.add(doc.id);
      }
    });
  }
  return result;
}

async function fetchForYouSecondDegreeUserIds(db, uid, viewerCtx, cap = 30) {
  const followingSample = [...viewerCtx.following].slice(0, 15);
  if (followingSample.length === 0) return new Set();

  const result = new Set();
  await Promise.all(followingSample.map(async (followingId) => {
    if (result.size >= cap) return;
    const snap = await db.collection(`users/${followingId}/following`).limit(20).get();
    snap.docs.forEach((doc) => {
      if (result.size >= cap) return;
      if (!isExcludedForYouAuthor(doc.id, uid, viewerCtx)) {
        result.add(doc.id);
      }
    });
  }));
  return result;
}

async function fetchForYouFollowerPublicUserIds(db, uid, viewerCtx, cap = 20) {
  const candidates = [...viewerCtx.followers].filter(
    (id) => !viewerCtx.following.has(id) && !isExcludedForYouAuthor(id, uid, viewerCtx)
  );
  if (candidates.length === 0) return new Set();

  const authorMap = await batchLoadAuthorDocs(candidates.slice(0, cap * 2));
  const result = new Set();
  for (const id of candidates) {
    if (result.size >= cap) break;
    const authorData = authorMap.get(id);
    if (authorData && authorData.isPrivate !== true) {
      result.add(id);
    }
  }
  return result;
}

async function fetchForYouGlobalEveryoneDocs(db, globalStreamCursor, fetchLimit = 120) {
  let query = db.collectionGroup('moments')
    .where('audience', '==', 'everyone')
    .orderBy('timestamp', 'desc')
    .orderBy(admin.firestore.FieldPath.documentId(), 'desc');

  if (globalStreamCursor && globalStreamCursor.timestamp && globalStreamCursor.momentId && globalStreamCursor.authorId) {
    const streamRef = db.doc(`users/${globalStreamCursor.authorId}/moments/${globalStreamCursor.momentId}`);
    query = query.startAfter(
      admin.firestore.Timestamp.fromDate(new Date(globalStreamCursor.timestamp)),
      streamRef
    );
  }

  const snap = await query.limit(fetchLimit).get();
  return { docs: snap.docs, fetchCount: snap.size };
}

function forYouMomentPath(authorId, momentId) {
  return `users/${authorId}/moments/${momentId}`;
}

function filterVisibleEntriesAfterCursor(entries, cursor) {
  if (!cursor || !cursor.momentId || !cursor.authorId) {
    return entries;
  }

  const cursorPath = forYouMomentPath(cursor.authorId, cursor.momentId);
  const cursorIndex = entries.findIndex((entry) => entry.doc.ref.path === cursorPath);
  if (cursorIndex >= 0) {
    return entries.slice(cursorIndex + 1);
  }

  const cursorTs = Number(cursor.timestamp) || 0;
  return entries.filter((entry) => {
    const entryPath = entry.doc.ref.path;
    if (entryPath === cursorPath) return false;

    const entryTs = tsToMillis(entry.data.timestamp) || 0;
    if (entryTs !== cursorTs) {
      return entryTs < cursorTs;
    }

    return entry.doc.id.localeCompare(cursor.momentId) < 0;
  });
}

function oldestGlobalStreamCursor(globalDocs) {
  if (!Array.isArray(globalDocs) || globalDocs.length === 0) return null;
  const oldest = globalDocs[globalDocs.length - 1];
  const data = oldest.data();
  return {
    timestamp: tsToMillis(data.timestamp),
    momentId: oldest.id,
    authorId: data.authorId
  };
}

function countSharedInterests(viewerInterests, authorData) {
  const authorInterests = Array.isArray(authorData?.interests) ? authorData.interests : [];
  const viewerSet = new Set(viewerInterests || []);
  return authorInterests.filter((interest) => viewerSet.has(interest)).length;
}

function forYouTierWeight(sourceTier) {
  switch (sourceTier) {
    case 'A': return 30000;
    case 'B': return 20000;
    case 'C': return 10000;
    default: return 0;
  }
}

function deterministicForYouJitter(momentId, viewerId) {
  const key = `${momentId || ''}:${viewerId || ''}`;
  let hash = 0;
  for (let i = 0; i < key.length; i += 1) {
    hash = ((hash << 5) - hash) + key.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash % 2000);
}

function scoreForYouMoment({
  data,
  authorData,
  viewerInterests,
  sourceTier,
  followerIds,
  momentId,
  viewerId
}) {
  const timestampMillis = tsToMillis(data.timestamp) || 0;
  const shared = countSharedInterests(viewerInterests, authorData);
  const tierWeight = forYouTierWeight(sourceTier);
  const followerBoost = followerIds.has(data.authorId) ? 5000 : 0;
  const jitter = deterministicForYouJitter(momentId, viewerId);
  return timestampMillis + (shared * 5000) + tierWeight + followerBoost + jitter;
}

async function buildForYouDiscoveryContext(db, uid, viewerCtx, globalStreamCursor) {
  const [tierA, tierB, tierC, globalResult] = await Promise.all([
    fetchForYouInterestUserIds(db, uid, viewerCtx, 40),
    fetchForYouSecondDegreeUserIds(db, uid, viewerCtx, 30),
    fetchForYouFollowerPublicUserIds(db, uid, viewerCtx, 20),
    fetchForYouGlobalEveryoneDocs(db, globalStreamCursor, 120)
  ]);

  const authorTierMap = new Map();
  tierA.forEach((id) => authorTierMap.set(id, 'A'));
  tierB.forEach((id) => {
    if (!authorTierMap.has(id)) authorTierMap.set(id, 'B');
  });
  tierC.forEach((id) => {
    if (!authorTierMap.has(id)) authorTierMap.set(id, 'C');
  });

  globalResult.docs.forEach((doc) => {
    const authorId = doc.data()?.authorId;
    if (authorId && !authorTierMap.has(authorId)) {
      authorTierMap.set(authorId, 'D');
    }
  });

  return {
    candidateUserIds: [...authorTierMap.keys()],
    authorTierMap,
    globalDocs: globalResult.docs,
    globalFetchCount: globalResult.fetchCount,
    tierStats: {
      interests: tierA.size,
      secondDegree: tierB.size,
      followersPublic: tierC.size,
      globalEveryone: globalResult.docs.length
    }
  };
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

    case 'mutuals': {
      // Mutual followers required
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
 * Server-side story privacy check — mirrors canUserViewStoryEnhanced from PrivacyService.swift.
 *
 * @param {object} story - { id, authorId, audience, customListId }
 * @param {string} viewerId
 * @param {object} viewerCtx - from buildViewerContext
 * @param {object} authorData - author user document data
 * @returns {Promise<boolean>}
 */
async function canViewerSeeStory(story, viewerId, viewerCtx, authorData) {
  const db = admin.firestore();

  if (!story || typeof story.authorId !== 'string' || !story.authorId) return false;

  // Author always sees own stories, including onlyMe.
  if (story.authorId === viewerId) return true;

  if (viewerCtx.mutedUsers && viewerCtx.mutedUsers.has(story.authorId)) return false;
  if (authorData.isActive === false) return false;

  const authorBlocked = Array.isArray(authorData.blockedUsers) ? authorData.blockedUsers : [];
  if (viewerCtx.blockedUsers.has(story.authorId) || authorBlocked.includes(viewerId)) {
    return false;
  }

  const visSettings = authorData.contentVisibilitySettings || {};
  const hiddenFrom = Array.isArray(visSettings.hiddenFromUsers) ? visSettings.hiddenFromUsers : [];
  if (hiddenFrom.includes(viewerId)) return false;

  const audience = story.audience || 'everyone';
  switch (audience) {
    case 'everyone': {
      const isPrivate = authorData.isPrivate === true;
      if (!isPrivate) return true;
      return viewerCtx.following.has(story.authorId);
    }

    case 'mutuals':
      return viewerCtx.following.has(story.authorId) && viewerCtx.followers.has(story.authorId);

    case 'bestFriends': {
      const authorBestFriends = Array.isArray(authorData.bestFriends) ? authorData.bestFriends : [];
      return authorBestFriends.includes(viewerId);
    }

    case 'custom': {
      if (!story.id) return false;
      try {
        const primary = await db.doc(`users/${story.authorId}/customAudiences/story_${story.id}`).get();
        if (primary.exists) {
          const allowedUsers = primary.data().allowedUsers || [];
          return allowedUsers.includes(viewerId);
        }
        const legacy = await db.doc(`users/${story.authorId}/customAudiences/default_story`).get();
        if (!legacy.exists) return false;
        const legacyUsers = legacy.data().allowedUsers || [];
        return legacyUsers.includes(viewerId);
      } catch {
        return false;
      }
    }

    case 'customList': {
      const listId = story.customListId;
      if (!listId) return false;
      try {
        const listDoc = await db.doc(`users/${story.authorId}/customAudienceLists/${listId}`).get();
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

function isStoryPathAuthorConsistent(doc, data) {
  const authorId = data && data.authorId;
  if (typeof authorId !== 'string' || authorId.length === 0) return false;

  const refPath = doc && doc.ref && typeof doc.ref.path === 'string' ? doc.ref.path : '';
  const parts = refPath.split('/');
  return parts.length === 4
    && parts[0] === 'users'
    && parts[1] === authorId
    && parts[2] === 'stories'
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
    hasHiddenLayers: data.hasHiddenLayers === true,
    hiddenLayerCount: Number.isInteger(data.hiddenLayerCount) ? data.hiddenLayerCount : 0
  };
}

function serializeHighlightedStory(docId, data, overrides = {}) {
  return {
    id: docId,
    title: data.title || '',
    coverImageUrl: overrides.coverImageUrl ?? data.coverImageUrl ?? null,
    storiesCount: overrides.storiesCount ?? data.storiesCount ?? 0,
    createdAt: tsToMillis(data.createdAt),
    storyIds: Array.isArray(overrides.storyIds) ? overrides.storyIds : (Array.isArray(data.storyIds) ? data.storyIds : []),
    authorId: overrides.authorId || data.authorId || ''
  };
}

function storyPrimaryMediaUrl(data) {
  if (data?.mediaItem && typeof data.mediaItem.url === 'string' && data.mediaItem.url.trim()) {
    return data.mediaItem.url.trim();
  }
  if (typeof data?.imagePath === 'string' && data.imagePath.trim()) {
    return data.imagePath.trim();
  }
  if (typeof data?.videoUrl === 'string' && data.videoUrl.trim()) {
    return data.videoUrl.trim();
  }
  return null;
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
 * Build and paginate the Para Ti (forYou) feed — discovery outside the following graph.
 */
async function processForYouFeedPage({ db, uid, viewerCtx, cursor, globalStreamCursor, limit }) {
  const discovery = await buildForYouDiscoveryContext(db, uid, viewerCtx, globalStreamCursor);
  const { candidateUserIds, authorTierMap, globalDocs, globalFetchCount, tierStats } = discovery;

  const fetchLimit = 120;
  const allCandidateDocs = [];
  const batchFetchCounts = [globalFetchCount];

  globalDocs.forEach((doc) => {
    const authorId = doc.data()?.authorId;
    if (isExcludedForYouAuthor(authorId, uid, viewerCtx)) return;
    allCandidateDocs.push({ doc, sourceTier: authorTierMap.get(authorId) || 'D' });
  });

  if (candidateUserIds.length > 0) {
    const userBatches = [];
    for (let i = 0; i < candidateUserIds.length; i += 10) {
      userBatches.push(candidateUserIds.slice(i, i + 10));
    }

    await Promise.all(userBatches.map(async (batch) => {
      const query = db.collectionGroup('moments')
        .where('authorId', 'in', batch)
        .orderBy('timestamp', 'desc')
        .limit(fetchLimit);
      const snap = await query.get();
      batchFetchCounts.push(snap.size);
      snap.docs.forEach((doc) => {
        const authorId = doc.data()?.authorId;
        if (isExcludedForYouAuthor(authorId, uid, viewerCtx)) return;
        allCandidateDocs.push({
          doc,
          sourceTier: authorTierMap.get(authorId) || 'D'
        });
      });
    }));
  }

  const seen = new Set();
  const uniqueEntries = [];
  for (const entry of allCandidateDocs) {
    const refPath = entry.doc.ref.path;
    if (seen.has(refPath)) continue;
    seen.add(refPath);
    uniqueEntries.push(entry);
  }

  const now = Date.now();
  const nonScheduledEntries = uniqueEntries.filter(({ doc }) => {
    const data = doc.data();
    if (!isMomentPathAuthorConsistent(doc, data)) return false;
    if (data.isArchived === true) return false;
    if (isExcludedForYouAuthor(data.authorId, uid, viewerCtx)) return false;
    const schedMs = tsToMillis(data.scheduledDate);
    if (schedMs && schedMs > now) return false;
    return true;
  });

  const authorIds = [...new Set(nonScheduledEntries.map(({ doc }) => doc.data().authorId))];
  const authorMap = await batchLoadAuthorDocs(authorIds);

  const privacyResults = await Promise.all(
    nonScheduledEntries.map(async ({ doc, sourceTier }) => {
      const data = doc.data();
      if (!isMomentPathAuthorConsistent(doc, data)) {
        return { doc, data, sourceTier, canView: false };
      }
      if (viewerCtx.following.has(data.authorId)) {
        return { doc, data, sourceTier, canView: false };
      }
      const authorData = authorMap.get(data.authorId);
      if (!authorData) return { doc, data, sourceTier, canView: false };
      const momentForCheck = {
        id: doc.id,
        authorId: data.authorId,
        audience: data.audience,
        taggedUsers: data.taggedUsers,
        customListId: data.customListId,
        isArchived: data.isArchived === true
      };
      const canView = await canViewerSeeMoment(momentForCheck, uid, viewerCtx, authorData);
      return { doc, data, sourceTier, canView, authorData };
    })
  );

  const visibleEntries = privacyResults
    .filter((entry) => entry.canView)
    .map((entry) => {
      const score = scoreForYouMoment({
        data: entry.data,
        authorData: entry.authorData,
        viewerInterests: viewerCtx.viewerInterests,
        sourceTier: entry.sourceTier,
        followerIds: viewerCtx.followers,
        momentId: entry.doc.id,
        viewerId: uid
      });
      return { ...entry, score };
    });

  visibleEntries.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    const tsA = tsToMillis(a.data.timestamp) || 0;
    const tsB = tsToMillis(b.data.timestamp) || 0;
    if (tsB !== tsA) return tsB - tsA;
    return b.doc.id.localeCompare(a.doc.id);
  });

  const candidatesAfterCursor = filterVisibleEntriesAfterCursor(visibleEntries, cursor);
  const totalCandidates = candidatesAfterCursor.length;

  const perAuthorCount = {};
  const perAuthorMax = 3;
  const finalEntries = [];
  for (const entry of candidatesAfterCursor) {
    const authorId = entry.data.authorId;
    const count = perAuthorCount[authorId] || 0;
    if (count >= perAuthorMax) continue;
    perAuthorCount[authorId] = count + 1;
    finalEntries.push(entry);
    if (finalEntries.length >= limit) break;
  }

  const moments = finalEntries.map(({ doc, data }) => serializeMoment(doc.id, data));

  let nextCursor = null;
  const hasMoreInFirestore = batchFetchCounts.some((count) => count >= fetchLimit);
  const moreVisibleThanReturned = candidatesAfterCursor.length > finalEntries.length;

  if (finalEntries.length > 0 && (moreVisibleThanReturned || hasMoreInFirestore)) {
    const lastEntry = finalEntries[finalEntries.length - 1];
    const streamCursor = oldestGlobalStreamCursor(globalDocs);
    nextCursor = {
      timestamp: tsToMillis(lastEntry.data.timestamp),
      momentId: lastEntry.doc.id,
      authorId: lastEntry.data.authorId,
      globalStreamTimestamp: streamCursor?.timestamp ?? null,
      globalStreamMomentId: streamCursor?.momentId ?? null,
      globalStreamAuthorId: streamCursor?.authorId ?? null
    };
  } else if (finalEntries.length === 0 && nonScheduledEntries.length > 0 && hasMoreInFirestore) {
    const lastEntry = nonScheduledEntries[nonScheduledEntries.length - 1];
    const lastData = lastEntry.doc.data();
    const streamCursor = oldestGlobalStreamCursor(globalDocs);
    nextCursor = {
      timestamp: tsToMillis(lastData.timestamp),
      momentId: lastEntry.doc.id,
      authorId: lastData.authorId,
      globalStreamTimestamp: streamCursor?.timestamp ?? null,
      globalStreamMomentId: streamCursor?.momentId ?? null,
      globalStreamAuthorId: streamCursor?.authorId ?? null
    };
  }

  if (cursor && nextCursor && isSameFeedCursor(cursor, nextCursor)) {
    console.warn(`⚠️ getFeedPage forYou: no-op cursor detected for uid=${uid}`);
    nextCursor = null;
  }

  console.log(
    `✅ getFeedPage forYou: uid=${uid}, tiers=${JSON.stringify(tierStats)}, `
    + `candidates=${totalCandidates}, visible=${visibleEntries.length}, returned=${moments.length}`
  );

  return { moments, nextCursor, totalCandidates };
}

module.exports = {
  buildViewerContext,
  isExcludedForYouAuthor,
  fetchForYouInterestUserIds,
  fetchForYouSecondDegreeUserIds,
  fetchForYouFollowerPublicUserIds,
  fetchForYouGlobalEveryoneDocs,
  forYouMomentPath,
  filterVisibleEntriesAfterCursor,
  oldestGlobalStreamCursor,
  countSharedInterests,
  forYouTierWeight,
  deterministicForYouJitter,
  scoreForYouMoment,
  buildForYouDiscoveryContext,
  batchLoadAuthorDocs,
  canViewerSeeMoment,
  canViewerSeeStory,
  tsToMillis,
  isSameFeedCursor,
  isMomentPathAuthorConsistent,
  isStoryPathAuthorConsistent,
  serializeMediaItem,
  hasVisibleMediaItem,
  buildLegacyMomentMediaFields,
  serializeMoment,
  serializeHighlightedStory,
  storyPrimaryMediaUrl,
  serializeRestrictedMoment,
  isFirestoreFailedPrecondition,
  buildMapFallbackCandidateUserIds,
  fetchMapCandidatesByAuthorBatches,
  processForYouFeedPage,
};
