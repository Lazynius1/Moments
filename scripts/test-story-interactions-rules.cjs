// Run against the local Firestore emulator only; never writes production documents.
const assert = require('node:assert/strict');
const project = 'demo-moments-story-share';
const base = `http://127.0.0.1:9098/v1/projects/${project}/databases/(default)/documents`;
const now = Math.floor(Date.now() / 1000);
const token = `${Buffer.from(JSON.stringify({alg: 'none', typ: 'JWT'})).toString('base64url')}.${Buffer.from(JSON.stringify({iss: `https://securetoken.google.com/${project}`, aud: project, sub: 'viewer', user_id: 'viewer', iat: now, exp: now + 3600, auth_time: now, firebase: {sign_in_provider: 'custom'}})).toString('base64url')}.`;
function value(v) {
  if (typeof v === 'boolean') return {booleanValue: v};
  if (typeof v === 'string') return {stringValue: v};
  return {mapValue: {fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, value(x)]))}};
}
async function write(path, fields, auth = 'owner') {
  return fetch(`${base}/${path}`, {method: 'PATCH', headers: {'Content-Type': 'application/json', ...(auth ? {Authorization: `Bearer ${auth}`} : {})}, body: JSON.stringify({fields})});
}
async function seed(path, data) {
  const r = await write(path, Object.fromEntries(Object.entries(data).map(([k,v]) => [k,value(v)])));
  assert.equal(r.status, 200, await r.text());
}
(async () => {
  await seed('users/viewer', {isActive: true});
  const cases = [
    {global: true, override: false, allow: false},
    {global: false, override: true, allow: true},
    {global: false, override: undefined, allow: false},
    {global: true, override: undefined, allow: true},
    {global: true, override: true, allow: false, anonymous: true},
    {global: true, override: true, allow: false, audience: 'onlyMe'},
  ];
  for (const [i,c] of cases.entries()) {
    await seed('users/owner', {isActive: true, isPrivate: false, contentVisibilitySettings: {allowStoryReactions: c.global}});
    const story = {authorId: 'owner', audience: c.audience || 'everyone'};
    if (c.override !== undefined) story.interactionSettings = {allowStoryReactions: c.override};
    await seed(`users/owner/stories/story-${i}`, story);
    const fields = {userId: value('viewer'), reaction: value('❤️'), timestamp: {timestampValue: new Date().toISOString()}};
    const reactionPath = `users/owner/stories/story-${i}/reactions/viewer`;
    const r = await write(reactionPath, fields, c.anonymous ? null : token);
    assert.equal(r.status, c.allow ? 200 : 403, `case ${i}: ${await r.text()}`);
    if (c.allow) {
      const updated = await write(reactionPath, {...fields, reaction: value('👏')}, token);
      assert.equal(updated.status, 200, await updated.text());
    }
  }
  console.log('6 reaction permission cases passed, including legacy fallback, update, private audience and anonymous denial.');
})().catch(e => {console.error(e); process.exitCode = 1;});
