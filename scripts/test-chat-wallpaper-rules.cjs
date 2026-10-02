// Validate private wallpaper access without publishing rules or touching user documents.
const fs = require('node:fs');
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || '/usr/local/lib/node_modules/firebase-tools/lib/';
const auth = require(path.join(cli, 'auth.js'));
const {requireAuth} = require(path.join(cli, 'requireAuth.js'));
const {Client} = require(path.join(cli, 'apiv2.js'));
const {rulesOrigin} = require(path.join(cli, 'api.js'));
(async () => {
  const project = process.env.WALLPAPER_TEST_PROJECT || 'glowsy-6a40e';
  await requireAuth({project, ...(auth.getGlobalDefaultAccount() || {})});
  const api = new Client({urlPrefix: rulesOrigin(), apiVersion: 'v1'});
  for (const file of ['firestore.rules', 'storage.rules']) {
    const resourcePath = file === 'firestore.rules'
      ? '/databases/(default)/documents/users/wallpaper-owner/chatWallpapers/test-chat'
      : '/b/glowsy-6a40e.firebasestorage.app/o/users/wallpaper-owner/chatWallpapers/test-chat/test.jpg';
    const cases = [];
    for (const method of ['get','delete']) {
      for (const uid of ['wallpaper-owner','other-participant',null]) {
        cases.push({expectation: uid === 'wallpaper-owner' ? 'ALLOW' : 'DENY',
          request: {path:resourcePath,method,auth: uid ? {uid,token:{}} : null}});
      }
    }
    const result = await api.post(`/projects/${project}:test`, {
      source: {files:[{name:file,content:fs.readFileSync(path.join(__dirname,'..',file),'utf8')}]},
      testSuite: {testCases:cases},
    }, {skipLog:{body:true}});
    const errors = (result.body.issues || []).filter(i=>i.severity==='ERROR');
    const states = (result.body.testResults || []).map(t=>t.state);
    console.log(file, JSON.stringify({errors,states}));
    if (errors.length || states.length !== cases.length || states.some(s=>s!=='SUCCESS')) process.exitCode=1;
  }
})().catch(error=>{console.error(error.message);process.exitCode=1;});
