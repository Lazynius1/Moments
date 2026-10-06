// Local Firestore emulator only. Concurrent absence reads followed by conflicting
// creates exercise the existence precondition used by mobile client transactions.
const assert = require('node:assert/strict');
const project = 'demo-moments-echo';
const root = `http://127.0.0.1:9098/v1/projects/${project}/databases/(default)`;
const now = Math.floor(Date.now()/1000);
function token(uid) {
 return `${Buffer.from(JSON.stringify({alg:'none',typ:'JWT'})).toString('base64url')}.${Buffer.from(JSON.stringify({iss:`https://securetoken.google.com/${project}`,aud:project,sub:uid,user_id:uid,iat:now,exp:now+3600,auth_time:now,firebase:{sign_in_provider:'custom'}})).toString('base64url')}.`;
}
function value(v) {
 if(typeof v==='string') return {stringValue:v};
 if(typeof v==='boolean') return {booleanValue:v};
 if(Array.isArray(v)) return {arrayValue:{values:v.map(value)}};
 return {mapValue:{fields:Object.fromEntries(Object.entries(v).map(([k,x])=>[k,value(x)]))}};
}
async function request(path,uid,method='GET',body) {
 const r=await fetch(root+path,{method,headers:{'Content-Type':'application/json',...(uid?{Authorization:`Bearer ${uid==='owner'?'owner':token(uid)}`}:{})},...(body?{body:JSON.stringify(body)}:{})});
 const text=await r.text();return {status:r.status,data: text?JSON.parse(text):null};
}
async function seed(path,data) {
 const r=await request('/documents/'+path,'owner','PATCH',{fields:Object.fromEntries(Object.entries(data).map(([k,v])=>[k,value(v)]))});assert.equal(r.status,200,JSON.stringify(r.data));
}
(async()=>{
 await seed('users/a',{isActive:true});await seed('users/b',{isActive:true});await seed('users/outsider',{isActive:true});
 const id='echo_v1_'+require('node:crypto').randomBytes(32).toString('hex'),path='echoes/'+id;
 const [ra,rb]=await Promise.all([request('/documents/'+path,'a'),request('/documents/'+path,'b')]);
 assert.equal(ra.status,404);assert.equal(rb.status,404);
 const fields=Object.fromEntries(Object.entries({hostId:'a',participantIds:['a','b'],participants:[{userId:'a',status:'pending'},{userId:'b',status:'pending'}],status:'pending'}).map(([k,v])=>[k,value(v)]));
 const name=`projects/${project}/databases/(default)/documents/${path}`;
 const first=await request('/documents:commit','a','POST',{writes:[{update:{name,fields},currentDocument:{exists:false}}]});assert.equal(first.status,200,JSON.stringify(first.data));
 const second=await request('/documents:commit','b','POST',{writes:[{update:{name,fields:{...fields,hostId:value('b')}},currentDocument:{exists:false}}]});assert.notEqual(second.status,200,'Concurrent creation must not overwrite winner');
 await seed(path,{hostId:'a',participantIds:['a','b'],status:'active',participants:[{userId:'a',status:'accepted'},{userId:'b',status:'accepted'}]});
 const retry=await request('/documents/'+path,'b');assert.equal(retry.status,200);assert.equal(retry.data.fields.status.stringValue,'active');assert.equal(retry.data.fields.participants.arrayValue.values[0].mapValue.fields.status.stringValue,'accepted');
 const query = (scoped) => ({structuredQuery:{from:[{collectionId:'echoes'}],...(scoped?{where:{fieldFilter:{field:{fieldPath:'participantIds'},op:'ARRAY_CONTAINS',value:value('b')}}}:{})}});
 assert.equal((await request('/documents:runQuery','b','POST',query(true))).status,200);
 assert.equal((await request('/documents:runQuery','outsider','POST',query(false))).status,403);
 assert.equal((await request('/documents/'+path,'outsider')).status,403);
 assert.equal((await request('/documents/echoes/echo_v1_'+'b'.repeat(64),null)).status,403);
 assert.equal((await request('/documents/echoes/random-missing-id','a')).status,403);
 console.log('Passed: two concurrent creators, winner preserved, retry retains acceptance, outsider blocked, anonymous blocked, missing random ID blocked, participant query allowed, unscoped query blocked.');
})().catch(e=>{console.error(e);process.exitCode=1});
