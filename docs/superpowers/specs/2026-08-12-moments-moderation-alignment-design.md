# Moments media moderation alignment (social-normal)

## Goal

Align Moments media moderation with typical Instagram/Facebook norms: allow social leisure clothing and male chest; warn only on clearly sexualized/near-nude content; hide only explicit nudity/sex. Rename Instagram-branded policy identifiers to Moments.

## Decision matrix

| Action | Content |
|--------|---------|
| **approved** | Bikini/swimwear, casual shorts/skirts, male bare chest, outdoor leisure without genitals/female nipples or sexual activity |
| **warning** (`racy`) | Near-nudity, sexual pose/focus, very revealing cleavage without allowed swimwear context, indoor lingerie edge cases |
| **deleted** (`adult` / other) | Genitals, female intimate exposure, sexual activity/display above delete thresholds, violence/hate/scam/offensive |

## Technical approach

1. **Sightengine adapter**: stop folding `minishort` / `miniskirt` / `other` / `mildly_suggestive` into risk `suggestive`; map casual bottoms to `allowedCasualBottoms`.
2. **Rekognition adapter**: map swimwear/bare chest to allow signals; do not treat `revealing clothes` alone as warning-grade `suggestive` when an allow context is present (or map clothing-only revealing to a non-warning path via shared override).
3. **Shared policy**: rename `applyInstagramContextOverride` → `applyMomentsContextOverride`, `instagram-aligned-v1` → `moments-aligned-v1`. In allowed social contexts, dampen `suggestive` / `impliedNudity` below warning when explicit risk is low. Remaining suggestive warnings use category `racy`, not `adult`.

## Non-goals

- Changing comment moderation OpenAI thresholds
- Changing Telegram/queue UX
- Matching X/Twitter permissiveness
