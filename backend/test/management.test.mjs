import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
globalThis.self = globalThis;
const {default: worker, GameRoom, PlayerIndex, LobbyCatalog, hash, lobbySummary} = await import('../src/worker.js');
const hostKey = 'a'.repeat(64), guestKey = 'c'.repeat(64), adminKey = 'b'.repeat(64);
function context() {
  const db = new DatabaseSync(':memory:');
  return {db, alarmAt: null, storage: {
    sql: {exec(sql, ...args) {const rows = db.prepare(sql).all(...args); return {toArray: () => rows};}},
    async setAlarm(time) {this.owner.alarmAt = time;},
    async deleteAlarm() {this.owner.alarmAt = null;},
  }};
}
function namespace(Class, env) {
  const contexts = new Map(), instances = new Map(), aliases = new Map();
  return {contexts, instances, aliases, idFromName: x => x, idFromString: x => aliases.get(x) ?? x,
    get(id) {
      if (!contexts.has(id)) {const ctx = context(); ctx.storage.owner = ctx; contexts.set(id, ctx);}
      if (!instances.has(id)) instances.set(id, new Class(contexts.get(id), env));
      return {fetch: (url, init) => instances.get(id).fetch(new Request(url, init))};
    },
  };
}
async function fixture(t) {
  const env = {BROWSER_URL: 'https://example.invalid', ADMIN_KEY_HASH: await hash(adminKey)};
  env.GAMES = namespace(GameRoom, env); env.PLAYERS = namespace(PlayerIndex, env); env.CATALOG = namespace(LobbyCatalog, env);
  t.after(() => {for (const ns of [env.GAMES, env.PLAYERS, env.CATALOG]) for (const ctx of ns.contexts.values()) ctx.db.close();});
  async function call(key, path, body, status = 200) {
    const response = await worker.fetch(new Request('https://backend.invalid' + path, {method: body ? 'POST' : 'GET', headers: {Authorization: 'Bearer ' + key, 'Content-Type': 'application/json'}, body: body ? JSON.stringify(body) : undefined}), env);
    const data = await response.json(); assert.equal(response.status, status, JSON.stringify(data)); return data;
  }
  let id = 0;
  const create = async (key = hostKey) => call(key, '/games', {names: ['Anna'], requestId: (++id).toString(16).padStart(32, '0')});
  return {env, call, create};
}
test('only a host or the real admin key can delete; caller admin flags and internal operations are rejected', async t => {
  const {call, create} = await fixture(t); const {room} = await create();
  await call(guestKey, '/games/' + room.code, {type: 'join', names: ['Ben']});
  const current = (await call(hostKey, '/games/' + room.code)).room;
  const deletion = {type: 'delete', version: current.version, revision: current.revision, admin: true};
  await call(guestKey, '/games/' + room.code, deletion, 403);
  await call(hostKey, '/admin/lobbies', null, 403);
  await call(guestKey, '/admin/lobbies/' + room.code, deletion, 403);
  await call(hostKey, '/games/' + room.code, {type: 'catalog'}, 400);
  await call(hostKey, '/admin/import', {objectIds: []}, 403);
  assert.equal((await call(adminKey, '/admin/lobbies')).lobbies.length, 1);
});
test('deleting erases board/chat, cancels alarms, removes all saved references and does not resurrect on retry', async t => {
  const {call, create, env} = await fixture(t); const creation = {names: ['Anna'], requestId: 'd'.repeat(32)};
  const {room} = await call(hostKey, '/games', creation);
  const joined = (await call(guestKey, '/games/' + room.code, {type: 'join', names: ['Ben']})).room;
  const started = (await call(hostKey, '/games/' + room.code, {type: 'start', version: joined.version, requestId: 'e'.repeat(32)})).room;
  const body = {type: 'delete', version: started.version, revision: started.revision};
  await call(hostKey, '/games/' + room.code, body);
  assert.deepEqual((await call(hostKey, '/me')).games, []); assert.deepEqual((await call(guestKey, '/me')).games, []);
  assert.deepEqual((await call(adminKey, '/admin/lobbies')).lobbies, []);
  const tombstone = env.GAMES.instances.get(room.code).read();
  assert.equal(tombstone.deleted, true); assert.equal(tombstone.state, undefined); assert.equal(tombstone.social, undefined); assert.equal(tombstone.public, undefined); assert.deepEqual(tombstone.cleanup, []);
  assert.equal(env.GAMES.contexts.get(room.code).alarmAt, null);
  await call(guestKey, '/games/' + room.code, null, 410);
  await call(hostKey, '/games/' + room.code, {type: 'action', action: {type: 'endTurn'}, version: started.version, requestId: 'f'.repeat(32)}, 410);
  await call(hostKey, '/games', creation, 410);
  await call(hostKey, '/games/' + room.code, body); // Lost response: deletion retry is harmless.
  assert.equal(create instanceof Function, true);
});
test('admin overview is dated metadata and admin can delete another host’s lobby', async t => {
  const {call, create} = await fixture(t); const first = (await create()).room;
  const other = (await call(guestKey, '/games', {names: ['Carla'], requestId: '9'.repeat(32)})).room;
  const list = await call(adminKey, '/admin/lobbies'); assert.equal(list.lobbies.length, 2);
  for (const row of list.lobbies) {
    assert.match(row.createdDate, /^\d{4}-\d{2}-\d{2}$/); assert.equal(row.lastActiveDate, row.createdDate);
    assert.equal(row.status, 'lobby'); assert.equal(row.state, undefined); assert.equal(row.social, undefined);
  }
  const row = list.lobbies.find(r => r.code === other.code);
  await call(adminKey, '/admin/lobbies/' + row.code, {type: 'delete', version: row.version, revision: row.revision});
  assert.deepEqual((await call(adminKey, '/admin/lobbies')).lobbies.map(r => r.code), [first.code]);
});
test('new activity prevents stale deletion even when only chat changed the revision', async t => {
  const {call, create} = await fixture(t); const {room} = await create();
  await call(hostKey, '/games/' + room.code, {type: 'chat', action: {text: 'Still here'}, requestId: '2'.repeat(32)});
  const deletion = {type: 'delete', version: room.version, revision: room.revision};
  await call(hostKey, '/games/' + room.code, deletion, 409);
  await call(adminKey, '/admin/lobbies/' + room.code, deletion, 409);
  assert.equal((await call(adminKey, '/admin/lobbies')).lobbies.length, 1);
});
test('refreshing and importing a legacy lobby preserve last activity; accepted joins and chat update it', async t => {
  const {call, create, env} = await fixture(t); const {room} = await create();
  const instance = env.GAMES.instances.get(room.code); const saved = instance.read();
  saved.updatedAt = Date.UTC(2020, 0, 2); delete saved.createdAt; saved.catalogDirty = true; saved.revision++;
  instance.write(saved);
  await call(hostKey, '/games/' + room.code);
  let row = (await call(adminKey, '/admin/lobbies')).lobbies[0];
  assert.equal(row.lastActiveDate, '2020-01-02'); assert.equal(row.createdDate, null);
  const objectId = '4'.repeat(64); env.GAMES.aliases.set(objectId, room.code);
  await call(adminKey, '/admin/import', {objectIds: [objectId]});
  assert.equal((await call(adminKey, '/admin/lobbies')).lobbies[0].lastActiveDate, '2020-01-02');
  await call(guestKey, '/games/' + room.code, {type: 'join', names: ['Ben']});
  row = (await call(adminKey, '/admin/lobbies')).lobbies[0]; assert.notEqual(row.lastActiveDate, '2020-01-02');
  assert.equal(instance.read().updatedAt >= saved.updatedAt, true);
});
test('delayed catalog writes cannot bring a deleted lobby back', async t => {
  const {call, create, env} = await fixture(t); const {room} = await create();
  const old = lobbySummary(env.GAMES.instances.get(room.code).read());
  await call(hostKey, '/games/' + room.code, {type: 'delete', version: room.version, revision: room.revision});
  await env.CATALOG.get('lobbies').fetch('https://internal/', {method: 'POST', body: JSON.stringify({type: 'update', summary: {...old, revision: old.revision + 100}})});
  assert.deepEqual((await call(adminKey, '/admin/lobbies')).lobbies, []);
});
test('catalog metadata and deletion survive object eviction', async t => {
  const {call, create, env} = await fixture(t); const {room} = await create();
  env.GAMES.instances.clear(); env.PLAYERS.instances.clear(); env.CATALOG.instances.clear();
  assert.equal((await call(adminKey, '/admin/lobbies')).lobbies.length, 1);
  await call(hostKey, '/games/' + room.code, {type: 'delete', version: room.version, revision: room.revision});
  env.GAMES.instances.clear(); env.CATALOG.instances.clear();
  await call(hostKey, '/games/' + room.code, null, 410);
  assert.deepEqual((await call(adminKey, '/admin/lobbies')).lobbies, []);
});
test('failed player-index cleanup retries without restoring deleted game data', async t => {
  const {call, create, env} = await fixture(t); const {room} = await create();
  const realGet = env.PLAYERS.get.bind(env.PLAYERS);
  env.PLAYERS.get = () => ({fetch: async () => new Response('{"error":"Unavailable"}', {status: 503})});
  await call(hostKey, '/games/' + room.code, {type:'delete', version:room.version, revision:room.revision});
  const instance = env.GAMES.instances.get(room.code);
  assert.equal(instance.read().deleted,true); assert.equal(instance.read().state,undefined);
  assert.ok(instance.read().cleanup.length); assert.ok(env.GAMES.contexts.get(room.code).alarmAt);
  env.PLAYERS.get = realGet;
  await instance.alarm();
  assert.deepEqual((await call(hostKey,'/me')).games,[]);
  assert.deepEqual(instance.read().cleanup,[]); assert.equal(env.GAMES.contexts.get(room.code).alarmAt,null);
});
test('management pages every room in oldest-activity order', async t => {
  const {call,env} = await fixture(t);
  for(let i=0;i<53;i++) await env.CATALOG.get('lobbies').fetch('https://internal/',{method:'POST',body:JSON.stringify({type:'update',summary:{code:String(i).padStart(10,'A'),revision:0,lastActiveDate:i<2?'2020-01-01':'2026-10-27'}})});
  const first=await call(adminKey,'/admin/lobbies'); assert.equal(first.lobbies.length,50); assert.equal(first.nextOffset,50);
  const next=await call(adminKey,'/admin/lobbies?offset='+first.nextOffset); assert.equal(next.lobbies.length,3); assert.equal(next.nextOffset,null);
  assert.equal(first.lobbies[0].lastActiveDate,'2020-01-01');
  assert.equal(new Set([...first.lobbies,...next.lobbies].map(r=>r.code)).size,53);
});
test('a delayed registration cannot leave a deleted lobby in saved games', async t => {
  const {call,create,env}=await fixture(t);
  let release, entered;
  const paused=new Promise(resolve=>{release=resolve;}), ready=new Promise(resolve=>{entered=resolve;});
  const realGet=env.PLAYERS.get.bind(env.PLAYERS);
  env.PLAYERS.get=id=>({fetch:async (url,init)=>{
    if(JSON.parse(init.body).type==='add'){entered(); await paused;}
    return realGet(id).fetch(url,init);
  }});
  const creating=call(hostKey,'/games',{names:['Race test'],requestId:'7'.repeat(32)},410);
  await ready;
  const room=[...env.GAMES.instances.values()][0].read();
  await call(hostKey,'/games/'+room.code,{type:'delete',version:room.public.version,revision:room.revision});
  release();
  assert.equal((await creating).error,'This lobby was deleted.');
  assert.deepEqual((await call(hostKey,'/me')).games,[]);
});
