import assert from 'node:assert/strict';
const base = process.env.ASYNC_TEST_URL ?? 'http://127.0.0.1:8790';
const identity = () => [...crypto.getRandomValues(new Uint8Array(32))].map(x=>x.toString(16).padStart(2,'0')).join('');
const host=identity(), guest=identity(), stranger=identity();
const requestId=()=>identity().slice(0,32);
async function call(secret,path,body,status=200) {
 const response=await fetch(base+path,{method:body?'POST':'GET',headers:{Authorization:`Bearer ${secret}`,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
 const data=await response.json(); assert.equal(response.status,status,JSON.stringify(data)); return data;
}
const creation={names:['anna'],requestId:requestId()};
let r=await call(host,'/games',creation);
const code=r.room.code, path='/games/'+code;
assert.equal(code.length,10); assert.equal(r.room.seats[0].name,'Anna');
assert.equal((await call(host,'/games',creation)).room.code,code);
assert.deepEqual((await call(host,'/me')).games,[code]);
await call(stranger,path,null,403);
r=await call(guest,path,{type:'join',names:['ben']});
assert.equal(r.room.seats[1].name,'Ben');
assert.ok((await call(guest,'/me')).games.includes(code));
await call(guest,path,{type:'start',version:r.room.version,requestId:requestId()},403);
const start={type:'start',version:r.room.version,requestId:requestId()};
r=await call(host,path,start); const startedVersion=r.room.version;
assert.deepEqual(r.room.state.deck,[]);
assert.equal((await call(host,path,start)).room.version,startedVersion);
await call(stranger,path,{type:'join',names:['Eve']},409);
await call(guest,path,{type:'action',version:r.room.version,requestId:requestId(),action:{type:'endTurn'}},403);
let previous;
// No host process participates: only the independent Worker receives moves.
for(let i=0;i<80 && r.room.state.currentPlayerIndex===0;i++) {
 const s=r.room.state;
 let action;
 if(s.pendingSamePosition) action={type:'confirmSame'};
 else if(s.pendingRemovals.length) action={type:'confirmRemovals'};
 else if(s.turnCanEnd) action={type:'endTurn'};
 else {
  // The initial hidden card left of the handle always has a visible neighbour.
  action={type:'guess',position:[2,4],orientation:'horizontal',guess:'higher'};
 }
 const body={type:'action',version:r.room.version,requestId:requestId(),action};
 previous=r.room.version;
 r=await call(host,path,body);
 const replay=await call(host,path,body); assert.equal(replay.room.version,r.room.version);
}
assert.equal(r.room.state.currentPlayerIndex,1,'A turn must reach the guest');
await call(host,path,{type:'action',version:previous,requestId:requestId(),action:{type:'endTurn'}},409);
const recovered=await call(guest,path); assert.equal(recovered.room.state.currentPlayerIndex,1);
const v=recovered.room.version;
const [one,two]=await Promise.all([
 fetch(base+path,{method:'POST',headers:{Authorization:`Bearer ${host}`,'Content-Type':'application/json'},body:JSON.stringify({type:'restart',version:v,requestId:requestId()})}),
 fetch(base+path,{method:'POST',headers:{Authorization:`Bearer ${host}`,'Content-Type':'application/json'},body:JSON.stringify({type:'lobby',version:v,requestId:requestId()})}),
]);
assert.deepEqual([one.status,two.status].sort(),[200,409]);
r=await call(host,path);
if(r.room.started) r=await call(host,path,{type:'lobby',version:r.room.version,requestId:requestId()});
assert.equal(r.room.code,code); assert.equal(r.room.seats.length,2);
await call(guest,path,{type:'chat',requestId:requestId(),action:{text:'Back tomorrow'}});
assert.equal(Object.values((await call(host,path)).social.messages)[0].text,'Back tomorrow');
// Recovered identity on another client can see and resume the same room.
assert.ok((await call(guest,'/me')).games.includes(code));
console.log('PASS: create/join, retry safety, member privacy, host controls, wrong/stale turns, host-independent handover, concurrent updates, recovery and chat.');
