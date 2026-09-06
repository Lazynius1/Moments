# Explore: global search and recommendations

Implemented on iOS and Android. No app builds or tests were run, as requested.

## Search

The existing Explore input now searches the backend, with All, People, Hashtags and Places filters. A leading # or @ selects that search type. Requests are debounced; cancellation and generation checks prevent older responses replacing a newer query. Results have loading, retry and load-more states, with all new UI strings in the 16 supported languages.

`searchMoments` is authenticated. It searches the server-owned `momentSearch` collection, ordered newest first with a document-ID tie breaker and a cursor scoped to the account, query and mode. Each page returns at most 24 posts to the apps. A request scans at most 300 candidate entries; if visibility filtering exhausts that budget, the next cursor remains available, even on an empty page. Counts in the UI describe loaded results, not a global count.

Hashtags match complete normalized tags. Places and mixed searches match word prefixes, ignoring case and diacritics. Mixed search includes caption, location and stored username; user-profile search retains the existing username search. This is an indexed word search, not fuzzy or semantic search. Prefixes cover the first 40 characters of each word; index creation bounds very large input to 20,000 characters per text and 6,000 unique terms. Hashtags are indexed separately (up to 200, with at most 120 characters each).

The source moment and author are loaded again before any result is returned. Search retains Explore's exclusion of the viewer's own posts; it can include followed authors and private profiles the viewer follows, but only when the post audience also permits access. Archive, scheduling, moderation-hidden posts, inactive authors, blocked/muted accounts, hidden-from settings and all supported audiences are respected. Permission or content changes cannot be bypassed with a stale index entry or cursor.

`syncMomentSearchIndex` updates the index when a source post is created, changed or deleted. It reads current source state transactionally, so delayed events cannot resurrect deleted data. A content fingerprint avoids index rewrites when only engagement counts change. The index contains searchable terms and source references, never serves as the source of post bodies and is inaccessible directly under the existing rules. No rules deployment is required.

The migration in `functions/scripts/backfill-moment-search.js` indexes existing posts without modifying them. It is idempotent and can be rerun. `--index-only` creates only the composite index used by this feature; `--index-status` reads its readiness.

## Recommendations

`getExplorePage` reuses the normalized For You ranking: interests, affinity, recency, social proximity, discovery slots, author diversity, seen-post preference and negative feedback. Explore limits its candidates to posts with visible media suitable for the grid. It discovers public accounts the viewer does not follow and applies the post's audience. Following feed behavior is unchanged.

Explore has independent cursor sessions (`users/{uid}/exploreRecommendationSessions`), so browsing Explore cannot evict an active For You session. Content and permissions are reloaded on each page. The apps load recommendations independently of suggested people and provide pagination and retry. Opening a result records a view for future recommendations, unless incognito is active; the local view history is bounded and shared with For You.

## Deployment scope

Only these new functions are required:
- `searchMoments`
- `syncMomentSearchIndex`
- `getExplorePage`

One composite index is added: `momentSearch`: terms ARRAY_CONTAINS, timestamp DESC, document ID DESC. No other function or rules change is needed for this feature. The shared ranking helper has a default-preserving optional surface argument; only the new Explore endpoint selects the Explore behavior.

Deployment completed on 2026-09-06 to `glowsy-6a40e` (europe-southwest1): all three new functions created successfully. The backfill processed 112 existing source documents. The composite index reports READY. App compilation and runtime validation remain with the user.
