const test = require('node:test');
const assert = require('node:assert/strict');
// Test-only key: production uses the function's bound Secret Manager value.
process.env.MAP_CURSOR_KEY = '11'.repeat(32);
const { mapQueryKey, decodeMapCursor, encodeMapCursor, fetchMapMomentCandidatePage,
  fetchMapStoryCandidatePage } = require('../src/helpers/map-pagination');

const timestamp = value => ({ toMillis: () => value, valueOf: () => value });
const admin = { firestore: { FieldPath: { documentId: () => '__name__' },
  Timestamp: { fromMillis: timestamp, now: () => timestamp(0) } } };
function fixture(records) {
  const value = (doc, field) => field === '__name__' ? doc.ref.path
    : field.split('.').reduce((data, key) => data?.[key], doc.data());
  return { doc: path => ({ path }), collectionGroup: kind => {
    let results = records.filter(doc => doc.ref.path.split('/')[2] === kind);
    let ordering = [], after = null, cap = Infinity;
    const query = {
      where(field, operator, expected) {
        results = results.filter(doc => {
          const actual = value(doc, field);
          return operator === 'in' ? expected.includes(actual)
            : operator === '==' ? actual === expected
            : operator === '>=' ? actual >= expected
            : operator === '<=' ? actual <= expected
            : operator === '>' ? actual > expected : false;
        });
        return query;
      },
      orderBy(field, direction) { ordering.push([field, direction]); return query; },
      startAfter(...values) { after = values.map(item => item?.path ?? item); return query; },
      limit(limit) { cap = limit; return query; },
      async get() {
        const compare = (left, right) => {
          for (let i = 0; i < ordering.length; i++) {
            const direction = ordering[i][1] === 'desc' ? -1 : 1;
            const difference = left[i] < right[i] ? -1 : left[i] > right[i] ? 1 : 0;
            if (difference) return direction * difference;
          }
          return 0;
        };
        const values = doc => ordering.map(([field]) => value(doc, field));
        return { docs: results.sort((a, b) => compare(values(a), values(b)))
          .filter(doc => !after || compare(values(doc), after) > 0).slice(0, cap) };
      },
    };
    return query;
  } };
}
function document(id, author, kind = 'moments', latitude = 40) {
  const data = { authorId: author, timestamp: timestamp(100), expirationDate: timestamp(1000),
    location: 'Place', locationCoordinate: { latitude, longitude: -3 } };
  return { id, ref: { path: `users/${author}/${kind}/${id}` }, data: () => data };
}
const filters = { latitudeMin: 39, latitudeMax: 41, longitudeMin: -4, longitudeMax: -2 };

test('a map cursor cannot be reused for another viewer, viewport, scope or content kind', () => {
  const key = mapQueryKey('viewer', 'region', filters, 'following', 'moments');
  const token = encodeMapCursor(key, 40, 'users/friend/moments/post');
  assert.equal(decodeMapCursor(token, key).value, 40);
  assert.ok(!Buffer.from(token, 'base64url').toString().includes('users/friend'));
  const altered = Buffer.from(token, 'base64url'); altered[30] ^= 1;
  assert.throws(() => decodeMapCursor(altered.toString('base64url'), key), /Invalid map cursor/);
  for (const other of [mapQueryKey('other', 'region', filters, 'following', 'moments'),
    mapQueryKey('viewer', 'region', { ...filters, latitudeMin: 38 }, 'following', 'moments'),
    mapQueryKey('viewer', 'region', filters, 'all', 'moments'),
    mapQueryKey('viewer', 'region', filters, 'following', 'stories')]) {
    assert.throws(() => decodeMapCursor(token, other), /Invalid map cursor/);
  }
  assert.throws(() => decodeMapCursor('bad json', key), /Invalid map cursor/);
});

for (const mode of ['region', 'location']) {
  test(`${mode} pages traverse multiple author batches and coordinate/timestamp ties without omissions`, async () => {
    const authors = Array.from({ length: 23 }, (_, i) => `author-${i}`);
    const records = authors.flatMap(author => Array.from({ length: 4 }, (_, i) => document(`post-${i}`, author)));
    const db = fixture([...records, document('outside', authors[0], 'moments', 80), document('stranger', 'stranger')]);
    const queryFilters = mode === 'location' ? { locationName: 'Place' } : filters;
    const key = mapQueryKey('viewer', mode, queryFilters, 'following', 'moments');
    let token = null;
    const paths = [];
    do {
      const page = await fetchMapMomentCandidatePage(db, admin, authors, mode, queryFilters, 7,
        decodeMapCursor(token, key), key);
      paths.push(...page.docs.map(doc => doc.ref.path));
      token = page.nextCursor;
    } while (token);
    const expected = mode === 'location' ? 93 : 92;
    assert.equal(paths.length, expected);
    assert.equal(new Set(paths).size, expected);
    assert.ok(paths.every(path => !path.includes('/stranger/')));
  });
}

test('story pagination is not truncated by the old 500-candidate cap', async () => {
  const records = Array.from({ length: 515 }, (_, i) => document(`story-${String(i).padStart(4, '0')}`, 'friend', 'stories'));
  const db = fixture(records);
  const key = mapQueryKey('viewer', 'region', filters, 'following', 'stories');
  const paths = [];
  let token = null;
  do {
    const page = await fetchMapStoryCandidatePage(db, admin, ['friend'], 60, decodeMapCursor(token, key), key);
    paths.push(...page.docs.map(doc => doc.ref.path));
    token = page.nextCursor;
  } while (token);
  assert.equal(paths.length, 515);
  assert.equal(new Set(paths).size, 515);
});

test('raw pages keep advancing even when all candidates are outside longitude bounds or denied', async () => {
  const records = Array.from({ length: 3 }, (_, i) => document(`hidden-${i}`, 'friend'));
  const db = fixture(records);
  const first = await fetchMapMomentCandidatePage(db, admin, ['friend'], 'region', filters, 2, null, 'query');
  assert.ok(first.nextCursor);
  const second = await fetchMapMomentCandidatePage(db, admin, ['friend'], 'region', filters, 2,
    decodeMapCursor(first.nextCursor, 'query'), 'query');
  assert.equal(second.docs.length, 1);
  assert.equal(second.nextCursor, null);
});

test('all scope includes posts and stories from authors outside the following graph', async () => {
  const db = fixture([document('public-post', 'not-followed'), document('public-story', 'not-followed', 'stories')]);
  const moments = await fetchMapMomentCandidatePage(db, admin, null, 'region', filters, 60, null, 'all-moments');
  const stories = await fetchMapStoryCandidatePage(db, admin, null, 60, null, 'all-stories');
  assert.deepEqual(moments.docs.map(doc => doc.id), ['public-post']);
  assert.deepEqual(stories.docs.map(doc => doc.id), ['public-story']);
});
