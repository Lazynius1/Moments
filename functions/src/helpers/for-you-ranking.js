'use strict';

const DAY = 86400000;
const clamp = (value, max = 1) => Math.max(0, Math.min(max, Number(value) || 0));
const topics = (values) => [...new Set((Array.isArray(values) ? values : [])
  .filter(v => typeof v === 'string').map(v => v.trim().toLowerCase()).filter(Boolean))];
const decay = (at, now, days) => Math.pow(0.5, Math.max(0, now - Number(at || 0)) / (days * DAY));

/** All signals share a 0…1 scale. Missing personal history redistributes its weight. */
function score(entry, context) {
  const { now, interests = [], affinity = {}, followers = new Set(), secondDegree = new Set(), negatives = [] } = context;
  const viewerTopics = topics(interests);
  const authorTopics = topics(entry.authorData?.interests);
  const interest = viewerTopics.length
    ? authorTopics.filter(t => viewerTopics.includes(t)).length / viewerTopics.length : 0;
  const affinityAvailable = Object.values(affinity).some(value => Number(value) > 0);
  const socialAvailable = followers.size > 0 || secondDegree.size > 0;
  const weights = { interest: viewerTopics.length ? 0.35 : 0, affinity: affinityAvailable ? 0.25 : 0,
    recency: 0.25, social: socialAvailable ? 0.15 : 0 };
  const unused = 1 - Object.values(weights).reduce((a, b) => a + b, 0);
  const coldBase = weights.interest + weights.recency;
  weights.interest += unused * weights.interest / coldBase;
  weights.recency += unused * 0.25 / coldBase;
  const authorId = entry.data.authorId;
  const social = followers.has(authorId) ? 1 : secondDegree.has(authorId) ? 0.7 : 0;
  const affinitySignal = Math.log1p(clamp(affinity[authorId], 100)) / Math.log1p(100);
  const recency = decay(entry.timestamp, now, 3);
  let penalty = 0;
  for (const negative of negatives) {
    const overlap = topics(negative.interests).some(t => authorTopics.includes(t));
    penalty += (negative.authorId === authorId ? 0.16 : overlap ? 0.05 : 0) * decay(negative.timestamp, now, 7);
  }
  return clamp(weights.interest * interest + weights.affinity * affinitySignal
    + weights.recency * recency + weights.social * social - Math.min(0.35, penalty));
}

/** Freeze the full pool order, not just each page. Seen posts remain available at the end. */
function orderPool(entries, context, previousAuthor = null, startingPosition = 0) {
  const seen = context.seen || {};
  const sorted = entries.map(entry => ({ ...entry, rank: score(entry, context),
    viewed: Number(seen[entry.key]) > context.now - 30 * DAY,
    discovery: !topics(entry.authorData?.interests).some(t => topics(context.interests).includes(t))
      && !(Number(context.affinity?.[entry.data.authorId]) > 0)
  })).sort((a, b) => a.rank === b.rank ? b.timestamp - a.timestamp || a.key.localeCompare(b.key) : b.rank - a.rank);
  const result = [];
  for (const viewed of [false, true]) {
    const pool = sorted.filter(entry => entry.viewed === viewed);
    while (pool.length) {
      const explore = (startingPosition + result.length + 1) % 5 === 0;
      let index = pool.findIndex(e => e.data.authorId !== previousAuthor && (!explore || e.discovery));
      if (index < 0) index = pool.findIndex(e => e.data.authorId !== previousAuthor);
      if (index < 0) index = 0; // A sparse feed still shows the remaining author.
      const [entry] = pool.splice(index, 1);
      result.push(entry);
      previousAuthor = entry.data.authorId;
    }
  }
  return result;
}

function sanitizeSignals(body, now) {
  const affinity = {};
  const seen = {};
  for (const [key, value] of Object.entries(body.affinityScores || {}).slice(0, 200)) {
    if (/^[^/]{1,128}$/.test(key) && Number.isFinite(value)) affinity[key] = clamp(value, 100);
  }
  for (const [key, value] of Object.entries(body.seenMoments || {}).slice(0, 500)) {
    if (/^[^/]{1,128}\/[^/]{1,128}$/.test(key) && Number.isFinite(value)
        && value > now - 30 * DAY && value <= now + 60000) seen[key] = Math.min(now, value);
  }
  return { affinity, seen };
}

module.exports = { score, orderPool, sanitizeSignals, topics, DAY };
