const test = require('node:test');
const assert = require('node:assert/strict');
const { mapSocialAuthorIds } = require('../src/helpers/map-scope');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadFunctions(file, dependencies) {
  const sandbox = { module: { exports: {} }, console, Buffer,
    require(name) { return dependencies[name]; } };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, file), 'utf8'), sandbox);
  return sandbox.module.exports;
}

const feedHelpers = loadFunctions('../src/helpers/feed.js', {
  '../bootstrap': { admin: { firestore: () => ({}) } }, './notifications': {},
});

function database(records) {
  return { collectionGroup() {
    let results = records;
    const query = {
      where(field, operator, value) {
        results = results.filter(doc => {
          const actual = field.split('.').reduce((data, key) => data?.[key], doc.data());
          if (operator === 'in') return value.includes(actual);
          if (operator === '==') return actual === value;
          if (operator === '>=') return actual >= value;
          if (operator === '<=') return actual <= value;
          throw Error(`Unexpected operator ${operator}`);
        });
        return query;
      },
      orderBy() { return query; },
      limit(limit) { results = results.slice(0, limit); return query; },
      async get() { return { docs: results }; },
    };
    return query;
  } };
}

function moment(id, authorId, latitude = 40, audience = 'everyone') {
  const data = { authorId, audience, location: 'Place', timestamp: 100,
    locationCoordinate: { latitude, longitude: -3 } };
  return { id, ref: { path: `users/${authorId}/moments/${id}` }, data: () => data };
}

test('social map includes own posts and following, without unrelated followers', () => {
  assert.deepEqual(mapSocialAuthorIds('viewer', {
    following: new Set(['friend', 'mutual', 'viewer']),
    followers: new Set(['mutual', 'stranger']),
    mutuals: new Set(['mutual']),
    blockedUsers: new Set(),
  }), ['viewer', 'friend', 'mutual']);
});

test('blocked and malformed accounts cannot become map candidates', () => {
  assert.deepEqual(mapSocialAuthorIds('viewer', {
    following: new Set(['blocked', '', null, 'friend']),
    blockedUsers: new Set(['blocked']),
  }), ['viewer', 'friend']);
});

test('a viewer without following only queries their own content', () => {
  assert.deepEqual(mapSocialAuthorIds('viewer', {}), ['viewer']);
});

test('viewport filtering precedes the candidate cap for followed authors', async () => {
  const outside = Array.from({ length: 500 }, (_, i) => moment(`outside-${i}`, 'friend', 80));
  const docs = await feedHelpers.fetchMapCandidatesByAuthorBatches(
    database([...outside, moment('inside', 'friend'), moment('stranger', 'stranger')]),
    ['viewer', 'friend'], 'region',
    { latitudeMin: 39, latitudeMax: 41, longitudeMin: -4, longitudeMax: -2 }, true,
  );
  assert.deepEqual(Array.from(docs, doc => doc.id), ['inside']);
});

test('following scope still applies audience authorization before the result limit', async () => {
  const records = [moment('denied', 'friend', 40, 'bestFriends'), moment('allowed', 'friend')];
  const db = database(records);
  const checked = [];
  const helpers = {
    setProxyCors() {}, verifyFirebaseAuth: async () => 'viewer', parseJsonBody: req => req.body,
    buildViewerContext: async () => ({ following: new Set(['friend']), blockedUsers: new Set() }),
    fetchMapCandidatesByAuthorBatches: feedHelpers.fetchMapCandidatesByAuthorBatches,
    batchLoadAuthorDocs: async () => new Map([['friend', {}]]),
    canViewerSeeMoment: async item => { checked.push(item.id); return item.id === 'allowed'; },
    tsToMillis: value => value, serializeMoment: (id, data) => ({ id, ...data }),
  };
  const endpoints = loadFunctions('../src/registers/http-feed.js', {
    '../bootstrap': { onRequest: (_, handler) => handler, admin: { firestore: () => db } },
    '../helpers': helpers, '../helpers/map-scope': { mapSocialAuthorIds },
    '../helpers/map-pagination': require('../src/helpers/map-pagination'),
  });
  let status, payload;
  const res = { status(code) { status = code; return res; }, json(body) { payload = body; } };
  await endpoints.getMapMomentsPage({ method: 'POST', body: { mode: 'region', scope: 'following',
    centerLatitude: 40, centerLongitude: -3, latitudeDelta: 2, longitudeDelta: 2, limit: 1 } }, res);
  assert.equal(status, 200);
  assert.deepEqual(checked, ['denied', 'allowed']);
  assert.deepEqual(Array.from(payload.moments, item => item.id), ['allowed']);
});

test('a paginated page with denied posts is empty but preserves the next cursor', async () => {
  const helpers = {
    setProxyCors() {}, verifyFirebaseAuth: async () => 'viewer', parseJsonBody: req => req.body,
    buildViewerContext: async () => ({ following: new Set(['friend']), blockedUsers: new Set() }),
    batchLoadAuthorDocs: async () => new Map([['friend', {}]]),
    canViewerSeeMoment: async () => false, tsToMillis: value => value,
  };
  const pagination = require('../src/helpers/map-pagination');
  const endpoints = loadFunctions('../src/registers/http-feed.js', {
    '../bootstrap': { onRequest: (_, handler) => handler, admin: { firestore: () => database([]) } },
    '../helpers': helpers, '../helpers/map-scope': { mapSocialAuthorIds },
    '../helpers/map-pagination': { ...pagination,
      fetchMapMomentCandidatePage: async () => ({ docs: [moment('denied', 'friend')], nextCursor: 'opaque-next' }) },
  });
  let status, payload;
  const res = { status(code) { status = code; return res; }, json(body) { payload = body; } };
  await endpoints.getMapMomentsPage({ method: 'POST', body: { mode: 'region', scope: 'following', paginate: true,
    centerLatitude: 40, centerLongitude: -3, latitudeDelta: 2, longitudeDelta: 2, limit: 1 } }, res);
  assert.equal(status, 200);
  assert.equal(payload.moments.length, 0);
  assert.equal(payload.nextCursor, 'opaque-next');
});

test('paginated stories still enforce their existing bestFriends audience', async () => {
  const denied = { doc: { id: 'denied', ref: { path: 'users/friend/stories/denied' } },
    data: { authorId: 'friend', audience: 'bestFriends', timestamp: 100,
      mapLocation: { latitude: 40, longitude: -3, locationName: 'Place' } } };
  const helpers = {
    setProxyCors() {}, verifyFirebaseAuth: async () => 'viewer', parseJsonBody: req => req.body,
    buildViewerContext: async () => ({ following: new Set(['friend']), followers: new Set(), blockedUsers: new Set() }),
    batchLoadAuthorDocs: async () => new Map([['friend', { bestFriends: ['someone-else'] }]]),
    isStoryPathAuthorConsistent: () => true, tsToMillis: value => value,
  };
  const endpoints = loadFunctions('../src/registers/http-feed.js', {
    '../bootstrap': { onRequest: (_, handler) => handler, admin: { firestore: () => database([]) } },
    '../helpers': helpers, '../helpers/map-scope': { mapSocialAuthorIds },
    '../helpers/map-pagination': { ...require('../src/helpers/map-pagination'),
      fetchMapStoryCandidatePage: async () => ({ docs: [{ ...denied.doc, data: () => denied.data }], nextCursor: 'opaque-next' }) },
  });
  let status, payload;
  const res = { status(code) { status = code; return res; }, json(body) { payload = body; } };
  await endpoints.getMapStoriesPage({ method: 'POST', body: { mode: 'region', scope: 'following', paginate: true,
    centerLatitude: 40, centerLongitude: -3, latitudeDelta: 2, longitudeDelta: 2, limit: 1 } }, res);
  assert.equal(status, 200);
  assert.equal(payload.stories.length, 0);
  assert.equal(payload.nextCursor, 'opaque-next');
});

// Regression: unfollowing a public author must not hide their public content
// in the all-authors map, while private-profile authorization remains intact.
test('unfollowing preserves public-post visibility but revokes private-profile visibility', async () => {
  const context = { following: new Set(), followers: new Set(), blockedUsers: new Set() };
  const item = { id: 'post', authorId: 'not-followed', audience: 'everyone' };
  assert.equal(await feedHelpers.canViewerSeeMoment(item, 'viewer', context, { isPrivate: false }), true);
  assert.equal(await feedHelpers.canViewerSeeMoment(item, 'viewer', context, { isPrivate: true }), false);
});
