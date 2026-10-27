// Creates and deletes only fresh disposable rooms. Optional admin test uses a
// private key file outside the repository; never place the key in arguments.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const base = process.env.ASYNC_TEST_URL ?? 'http://127.0.0.1:8790';
const random = () => crypto.randomUUID().replaceAll('-', '');
const host = random() + random(), guest = random() + random();
async function call(key, path, body, status = 200) {
  const response = await fetch(base + path, {method: body ? 'POST' : 'GET', headers: {Authorization: 'Bearer ' + key, 'Content-Type': 'application/json'}, body: body ? JSON.stringify(body) : undefined});
  const data = await response.json(); assert.equal(response.status, status, JSON.stringify(data)); return data;
}
const pathFor = r => '/games/' + r.code;
const removal = r => ({type: 'delete', version: r.version, revision: r.revision});
const made = [];
try {
  let room = (await call(host, '/games', {names:['Management integration test'], requestId: random()})).room; made.push(room);
  room = (await call(guest, pathFor(room), {type:'join',names:['Guest test']})).room;
  await call(guest,pathFor(room),{...removal(room),admin:true},403);
  await call(host,pathFor(room),{type:'chat',requestId:random(),action:{text:'Activity test'}});
  await call(host,pathFor(room),removal(room),409);
  room = (await call(host,pathFor(room))).room;
  await call(host,pathFor(room),removal(room));
  await call(guest,pathFor(room),null,410);
  assert.ok(!(await call(host,'/me')).games.includes(room.code));
  assert.ok(!(await call(guest,'/me')).games.includes(room.code));
  await call(host,pathFor(room),removal(room));
  if(process.env.ASYNC_ADMIN_KEY_FILE) {
    const admin = readFileSync(process.env.ASYNC_ADMIN_KEY_FILE,'utf8').trim();
    room = (await call(host,'/games',{names:['Admin integration test'],requestId:random()})).room; made.push(room);
    const list = (await call(admin,'/admin/lobbies')).lobbies;
    const summary = list.find(x=>x.code === room.code); assert.ok(summary);
    assert.match(summary.lastActiveDate,/^\d{4}-\d{2}-\d{2}$/); assert.equal(summary.state,undefined);
    await call(admin,'/admin/lobbies/' + room.code,removal(summary));
    await call(host,pathFor(room),null,410);
    assert.ok(!(await call(admin,'/admin/lobbies')).lobbies.some(x=>x.code === room.code));
  }
  console.log('PASS: deployed host/guest permissions, stale deletion, idempotent deletion, saved-reference cleanup and optional admin management.');
} finally {
  for(const created of made) {
    const response = await fetch(base + pathFor(created),{headers:{Authorization:'Bearer '+host}});
    if(response.status === 410) continue;
    if(response.ok) await call(host,pathFor(created),removal((await response.json()).room));
  }
}
