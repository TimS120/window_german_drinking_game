import './engine.generated.js';
export class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
const fail = (message, status = 400) => { throw new ApiError(status, message); };
const json = (data, status = 200) => Response.json(data, {status});
export const hash = async value => [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))].map(x => x.toString(16).padStart(2, '0')).join('');
export function engine(request) {
  const result = JSON.parse(globalThis.windowEngine(JSON.stringify(request)));
  if (result.error) fail(result.error.replace(/^Bad state: /, ''));
  return result;
}
export function names(input) {
  if (!Array.isArray(input) || input.length > 12) fail('Enter between 1 and 12 players.');
  const result = input.map(x => {
    if (typeof x !== 'string') fail('Invalid player name.');
    const name = x.trim();
    if (!name || name.length > 40 || /[\u0000-\u001f]/u.test(name)) fail('Names must have 1–40 characters.');
    const first = [...name][0];
    return first.toUpperCase() + name.slice(first.length);
  });
  if (new Set(result.map(x => x.toLowerCase())).size !== result.length) fail('Player names must be unique.');
  return result;
}
function member(room, uid) {
  if (!room) fail('Game not found.', 404);
  if (room.deleted) fail('This lobby was deleted.', 410);
  if (!Object.hasOwn(room.public.devices, uid)) fail('Join this game first.', 403);
}
function host(room, uid) { member(room, uid); if (room.public.hostUid !== uid) fail('Only the host can do that.', 403); }
function version(room, n) { if (n !== room.public.version) fail('The game changed. Refresh and try again.', 409); }
export function updateGame(room, result) {
  room.state = result.state;
  Object.assign(room.public, {state: result.publicState, deckSize: result.deckSize, ended: result.ended});
}
export function transition(original, uid, body) {
  const room = structuredClone(original);
  member(room, uid);
  const p = room.public, type = body.type;
  const gameChange = ['start', 'restart', 'lobby', 'edit', 'action'].includes(type);
  if (gameChange) version(room, body.version);
  if (['start', 'restart', 'lobby', 'edit'].includes(type)) host(room, uid);
  if (['start', 'restart', 'lobby'].includes(type)) {
    if (type === 'start' && p.started) fail('The game has already started.', 409);
    if (type !== 'start' && !p.started) fail('The game is still in the lobby.', 409);
    if (!p.seats.length) fail('Keep at least one player.');
    updateGame(room, engine({players: p.seats.map(x => x.name)}));
    p.started = type !== 'lobby';
    if (type !== 'start') { p.controlId++; p.controlNotice = type; }
  } else if (type === 'edit') {
    if (p.started) fail('Return to the lobby before editing players.');
    if (!Object.hasOwn(p.devices, body.uid)) fail('Unknown device.');
    const replacement = names(body.names);
    const all = [];
    let inserted = false;
    const insert = () => {for (const name of replacement) all.push({name, ownerUid: body.uid}); inserted = true;};
    for (const seat of p.seats) {
      if (seat.ownerUid === body.uid) {if (!inserted) insert();}
      else all.push(seat);
    }
    if (!inserted) insert();
    names(all.map(s => s.name));
    if (!all.length) fail('Keep at least one player.');
    p.seats = all.map((s, index) => ({...s, index}));
    const label = typeof body.label === 'string' ? body.label.trim() : '';
    if (!label || label.length > 60) fail('Device labels must have 1–60 characters.');
    p.devices[body.uid] = label;
    updateGame(room, engine({players: p.seats.map(s => s.name)}));
  } else if (type === 'action') {
    if (!p.started) fail('The game has not started.');
    if (p.seats[p.state.currentPlayerIndex]?.ownerUid !== uid) fail('It is another player’s turn.', 403);
    updateGame(room, engine({state: room.state, action: body.action}));
  } else if (type === 'chat') {
    const text = body.action?.text;
    if (typeof text !== 'string' || !text.trim() || text.length > 500) fail('Messages must have 1–500 characters.');
    room.social.messages ??= {};
    room.social.messages[body.requestId] = {id: body.requestId, uid, sender: p.seats.filter(s => s.ownerUid === uid).map(s => s.name).join(', '), text: text.trim(), createdAt: Date.now()};
    const keys = Object.keys(room.social.messages);
    for (const key of keys.slice(0, Math.max(0, keys.length - 100))) delete room.social.messages[key];
  } else if (type === 'reaction') {
    const emoji = body.action?.emoji;
    if (typeof emoji !== 'string' || emoji.length > 10) fail('Invalid reaction.');
    room.social.reactions ??= {};
    room.social.reactions[uid] = {id: body.requestId, uid, emoji, createdAt: Date.now()};
  } else fail('Unknown operation.');
  if (gameChange) { p.version++; room.social.turnViews = {}; }
  room.updatedAt = Date.now();
  return room;
}

export function lobbySummary(room) {
  if (room.deleted) return {code: room.code, revision: room.revision, deleted: true};
  return {
    code: room.code, revision: room.revision ?? 0, version: room.public.version,
    players: room.public.seats.map(s => s.name), hostUid: room.public.hostUid,
    status: !room.public.started ? 'lobby' : room.public.ended ? 'finished' : 'playing',
    createdDate: room.createdAt ? new Date(room.createdAt).toISOString().slice(0, 10) : null,
    lastActiveDate: new Date(room.updatedAt).toISOString().slice(0, 10),
  };
}
export function deleteLobby(room, actor, body, admin = false) {
  if (!room) fail('Game not found.', 404);
  if (room.deleted) {
    if (!admin && actor !== room.hostUid) fail('Only the host can delete this lobby.', 403);
    return room;
  }
  if (!admin) host(room, actor);
  version(room, body.version);
  if (body.revision !== (room.revision ?? 0)) fail('The lobby changed. Refresh before deleting it.', 409);
  return {code: room.code, deleted: true, hostUid: room.public.hostUid,
    revision: (room.revision ?? 0) + 1, deletedAt: Date.now(), catalogDirty: true,
    cleanup: Object.keys(room.public.devices)};
}
async function catalog(env, summary) {
  const response = await env.CATALOG.get(env.CATALOG.idFromName('lobbies')).fetch('https://internal/', {
    method: 'POST', body: JSON.stringify({type: 'update', summary}),
  });
  if (!response.ok) throw new Error('Lobby index update failed.');
}
export class LobbyCatalog {
  constructor(ctx) {
    this.ctx = ctx;
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS lobbies (code TEXT PRIMARY KEY, revision INTEGER NOT NULL, deleted INTEGER NOT NULL, summary TEXT NOT NULL, last_active TEXT NOT NULL)');
    ctx.storage.sql.exec('CREATE INDEX IF NOT EXISTS lobby_activity ON lobbies(deleted, last_active, code)');
  }
  async fetch(request) {
    const body = await request.json();
    if (body.type === 'update') {
      const item = body.summary;
      this.ctx.storage.sql.exec(`INSERT INTO lobbies(code, revision, deleted, summary, last_active)
        VALUES(?,?,?,?,?) ON CONFLICT(code) DO UPDATE SET revision=excluded.revision,
        deleted=excluded.deleted, summary=excluded.summary, last_active=excluded.last_active
        WHERE excluded.revision >= lobbies.revision AND lobbies.deleted=0`,
        item.code, item.revision, item.deleted ? 1 : 0, item.deleted ? '{}' : JSON.stringify(item), item.lastActiveDate ?? '');
      return json({ok: true});
    }
    const offset = Number.isInteger(body.offset) && body.offset >= 0 ? body.offset : 0;
    const rows = this.ctx.storage.sql.exec('SELECT summary FROM lobbies WHERE deleted=0 ORDER BY last_active, code LIMIT 51 OFFSET ?', offset).toArray();
    return json({lobbies: rows.slice(0, 50).map(r => JSON.parse(r.summary)), nextOffset: rows.length > 50 ? offset + 50 : null});
  }
}
function equalHash(a, b) {
  if (!/^[a-f0-9]{64}$/.test(a ?? '') || !/^[a-f0-9]{64}$/.test(b ?? '')) return false;
  let diff = 0;
  for (let i = 0; i < 64; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
export async function requireAdmin(request, env) {
  const key = request.headers.get('Authorization')?.replace(/^Bearer /, '') ?? '';
  if (!/^[a-f0-9]{64}$/.test(key) || !equalHash(await hash(key), env.ADMIN_KEY_HASH)) fail('Invalid admin key.', 403);
}

// One SQL row per object keeps commits atomic and survives server hibernation.
class StoredObject {
  constructor(ctx) {
    this.ctx = ctx;
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS saved (id INTEGER PRIMARY KEY, value TEXT NOT NULL)');
  }
  read() { const rows = this.ctx.storage.sql.exec('SELECT value FROM saved WHERE id=1').toArray(); return rows.length ? JSON.parse(rows[0].value) : null; }
  write(data) { this.ctx.storage.sql.exec('INSERT INTO saved (id,value) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET value=excluded.value', JSON.stringify(data)); }
}
export class PlayerIndex extends StoredObject {
  async fetch(request) {
    const body = await request.json();
    const data = this.read() ?? {games: [], tokens: []};
    if (body.type === 'add') {
      if (!data.games.includes(body.code)) data.games.push(body.code);
    } else if (body.type === 'removeGame') {
      data.games = data.games.filter(code => code !== body.code);
    } else if (body.type === 'token') {
      if (typeof body.token !== 'string' || !body.token || body.token.length > 4096) fail('Invalid notification token.');
      data.tokens = [body.token, ...data.tokens.filter(x => x !== body.token)].slice(0, 8);
    } else if (body.type === 'removeToken') data.tokens = data.tokens.filter(x => x !== body.token);
    else if (body.type === 'removeTokens') data.tokens = data.tokens.filter(x => !body.tokens.includes(x));
    if (body.type !== 'get') this.write(data);
    return json(data);
  }
}
async function profile(env, uid, body) {
  const response = await env.PLAYERS.get(env.PLAYERS.idFromName(uid)).fetch('https://internal/', {method: 'POST', body: JSON.stringify(body)});
  if (!response.ok) throw new Error('Player index is temporarily unavailable.');
  return response.json();
}
export class GameRoom extends StoredObject {
  constructor(ctx, env) { super(ctx); this.env = env; }
  response(room) { return json({room: {...room.public, code: room.code, revision: room.revision ?? 0, notificationSupport: !!this.env.FCM_SERVICE_ACCOUNT, createdDate: lobbySummary(room).createdDate, lastActiveDate: lobbySummary(room).lastActiveDate}, social: room.social, notificationDelivery: room.delivery ?? null}); }
  async syncCatalog() {
    const room = this.read();
    if (!room) return;
    const summary = lobbySummary(room);
    await catalog(this.env, summary);
    const latest = this.read();
    if ((latest.revision ?? 0) === summary.revision) {latest.catalogDirty = false; this.write(latest);}
  }
  async registerGame(uid, code) {
    await profile(this.env, uid, {type: 'add', code});
    // A deletion can commit while the cross-object registration is in flight.
    if (this.read()?.deleted) {
      await profile(this.env, uid, {type: 'removeGame', code});
      fail('This lobby was deleted.', 410);
    }
  }
  async cleanupDeleted() {
    let room = this.read();
    await catalog(this.env, lobbySummary(room));
    await Promise.all((room.cleanup ?? []).map(uid => profile(this.env, uid, {type: 'removeGame', code: room.code})));
    room = this.read(); room.cleanup = []; room.catalogDirty = false; this.write(room);
    await this.ctx.storage.deleteAlarm();
  }
  async fetch(request) {
    try {
      const body = await request.json();
      const {actor: uid, code} = body;
      // All state reads, validation and SQL commits below are synchronous.
      let room = this.read();
      if (body.type === 'catalog') {
        if (!room) return json({indexed: false});
        await this.syncCatalog();
        return json({indexed: !room.deleted});
      }
      if (body.type === 'delete') {
        room = deleteLobby(room, uid, body, body.admin === true);
        this.write(room);
        await this.ctx.storage.setAlarm(Date.now() + 60000);
        try {await this.cleanupDeleted();} catch (_) { /* The alarm retries index cleanup. */ }
        return json({deleted: true});
      }
      if (room?.deleted) fail('This lobby was deleted.', 410);
      if (body.type === 'create') {
        if (room) {
          if (room.public.hostUid !== uid || room.creationId !== body.requestId) fail('Code collision.', 409);
          await this.registerGame(uid, code);
          return this.response(room);
        }
        const local = names(body.names);
        if (!local.length) fail('Enter at least one player.');
        room = {code, creationId: body.requestId, social: {}, createdAt: Date.now(), updatedAt: Date.now(), requests: [], public: {hostUid: uid, version: 0, started: false, seats: local.map((name, index) => ({index, name, ownerUid: uid})), devices: {[uid]: 'Device 1'}, controlId: 0, controlNotice: null}};
        updateGame(room, engine({players: local}));
      } else if (body.type === 'join') {
        if (!room) fail('Game not found.', 404);
        if (!Object.hasOwn(room.public.devices, uid)) {
          if (room.public.started) fail('This game has already started. Ask the host to reopen its lobby.', 409);
          const local = names(body.names);
          if (!local.length) fail('Enter at least one player.');
          const seats = [...room.public.seats, ...local.map(name => ({name, ownerUid: uid}))];
          names(seats.map(s => s.name));
          room.public.seats = seats.map((s, index) => ({...s, index}));
          room.public.devices[uid] = `Device ${Object.keys(room.public.devices).length + 1}`;
          if (Object.keys(room.public.devices).length > 12) fail('This game already has 12 devices.');
          updateGame(room, engine({players: seats.map(s => s.name)}));
          room.public.version++;
          room.updatedAt = Date.now();
        }
      } else if (body.type === 'get') {
        member(room, uid);
        // Legacy rooms are indexed without marking an automatic refresh as activity.
        if (room.catalogDirty !== false) {
          try {await this.syncCatalog();} catch (_) {await this.ctx.storage.setAlarm(Date.now() + 60000);}
        }
        return this.response(room);
      } else {
        member(room, uid);
        if (!/^[a-f0-9]{32,64}$/.test(body.requestId ?? '')) fail('A request ID is required.');
        if (room.requests.includes(body.requestId)) return this.response(room);
        const before = room.public;
        room = transition(room, uid, body);
        const after = room.public;
        if (after.started && !after.ended && (!before.started || before.state.currentPlayerIndex !== after.state.currentPlayerIndex || body.type === 'restart')) {
          const next = after.seats[after.state.currentPlayerIndex];
          room.notification = {uid: next.ownerUid, code, name: next.name, id: `${code}:${after.version}`, attempts: 0};
        } else if (!after.started || after.ended) room.notification = null;
        room.requests = [...room.requests, body.requestId].slice(-128);
      }
      room.revision = (room.revision ?? 0) + 1;
      room.catalogDirty = true;
      this.write(room);
      await this.ctx.storage.setAlarm(Date.now() + 1000);
      try {await this.syncCatalog();} catch (_) { /* The persisted dirty flag is retried by the alarm. */ }
      if (body.type === 'create' || body.type === 'join') await this.registerGame(uid, code);
      return this.response(room);
    } catch (error) { return json({error: error instanceof ApiError ? error.message : 'The request could not be processed.'}, error.status ?? 500); }
  }
  async alarm() {
    const roomAtStart = this.read();
    if (roomAtStart?.deleted) {
      try {await this.cleanupDeleted();} catch (_) {await this.ctx.storage.setAlarm(Date.now() + 60000);}
      return;
    }
    if (roomAtStart?.catalogDirty) {
      try {await this.syncCatalog();} catch (_) {await this.ctx.storage.setAlarm(Date.now() + 60000);}
    }
    const job = this.read()?.notification;
    if (!job || !this.env.FCM_SERVICE_ACCOUNT) return;
    try {
      const account = JSON.parse(this.env.FCM_SERVICE_ACCOUNT);
      const tokens = (await profile(this.env, job.uid, {type: 'get'})).tokens;
      const accessToken = tokens.length ? await fcmAccessToken(account) : null;
      const invalid = [];
      for (const token of tokens) {
        const response = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {method: 'POST', headers: {Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json'}, body: JSON.stringify({message: {fid: token, notification: {title: 'Window · Your turn', body: `It’s your turn, ${job.name}.`}, data: {gameCode: job.code}, android: {collapse_key: job.code, notification: {tag: job.code, channel_id: 'window_turns'}}, webpush: {fcm_options: {link: `${this.env.BROWSER_URL}/?async=${job.code}`}, notification: {tag: job.code}}}})});
        if ([404, 410].includes(response.status)) invalid.push(token);
        else if (!response.ok) {
          const error = (await response.json()).error ?? {};
          const reason = error.details?.find(d => d.errorCode)?.errorCode ?? '';
          throw new Error(`FCM ${response.status} ${error.status ?? ''} ${reason}`);
        }
      }
      if (invalid.length) await profile(this.env, job.uid, {type: 'removeTokens', tokens: invalid});
      const room = this.read();
      if (room.notification?.id === job.id) {
        room.notification = null;
        room.delivery = {status: 'accepted', targets: tokens.length, updatedAt: Date.now()};
        this.write(room);
      }
    } catch (error) {
      // Log status categories only, never registration IDs or credentials.
      console.warn('Turn notification retry:', error.message);
      const room = this.read();
      if (room.notification?.id !== job.id) return;
      job.attempts++;
      room.delivery = {status: error.message, attempts: job.attempts, updatedAt: Date.now()};
      room.notification = job.attempts < 6 ? job : null;
      this.write(room);
      if (room.notification) await this.ctx.storage.setAlarm(Date.now() + Math.min(3600000, 30000 * 2 ** job.attempts));
    }
  }
}
const encode64 = bytes => btoa(String.fromCharCode(...bytes)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
let cachedAccess;
async function fcmAccessToken(account) {
  if (cachedAccess?.expires > Date.now()) return cachedAccess.token;
  const now = Math.floor(Date.now() / 1000);
  const header = encode64(new TextEncoder().encode(JSON.stringify({alg: 'RS256', typ: 'JWT'})));
  const payload = encode64(new TextEncoder().encode(JSON.stringify({iss: account.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600})));
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(account.private_key.replace(/-----[^-]+-----|\s/g, '')), c => c.charCodeAt(0)), {name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256'}, false, ['sign']);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${payload}`));
  const response = await fetch('https://oauth2.googleapis.com/token', {method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: new URLSearchParams({grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${header}.${payload}.${encode64(new Uint8Array(signature))}`})});
  if (!response.ok) throw new Error('Notification authorization failed.');
  const data = await response.json();
  cachedAccess = {token: data.access_token, expires: Date.now() + 3300000};
  return cachedAccess.token;
}
export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin');
    const allowed = !origin || [env.BROWSER_URL, 'http://localhost:8080', 'http://127.0.0.1:8080'].includes(origin);
    const headers = {'Access-Control-Allow-Origin': allowed ? origin ?? '*' : 'null', 'Access-Control-Allow-Headers': 'Authorization,Content-Type', 'Access-Control-Allow-Methods': 'GET,POST,OPTIONS', 'Cache-Control': 'no-store', 'Vary': 'Origin'};
    const respond = response => {const out = new Response(response.body, response); for (const [k, v] of Object.entries(headers)) out.headers.set(k, v); return out;};
    if (request.method === 'OPTIONS') return new Response(null, {status: allowed ? 204 : 403, headers});
    try {
      if (!allowed) fail('Origin not allowed.', 403);
      const url = new URL(request.url);
      if (url.pathname === '/health') return respond(json({ok: true, notifications: !!env.FCM_SERVICE_ACCOUNT}));
      if (url.pathname.startsWith('/admin/')) {
        await requireAdmin(request, env);
        if (request.method === 'GET' && url.pathname === '/admin/lobbies') {
          const offset = Number(url.searchParams.get('offset') ?? 0);
          return respond(await env.CATALOG.get(env.CATALOG.idFromName('lobbies')).fetch('https://internal/', {method: 'POST', body: JSON.stringify({type: 'list', offset})}));
        }
        if (request.method !== 'POST') fail('Method not allowed.', 405);
        const text = await request.text();
        if (text.length > 16000) fail('Request too large.', 413);
        let body; try {body = JSON.parse(text);} catch (_) {fail('Invalid JSON.');}
        if (!body || typeof body !== 'object' || Array.isArray(body)) fail('Invalid request.');
        if (url.pathname === '/admin/import') {
          if (!Array.isArray(body.objectIds) || body.objectIds.length > 10 || body.objectIds.some(id => !/^[a-f0-9]{64}$/.test(id))) fail('Invalid import batch.');
          let indexed = 0;
          for (const id of body.objectIds) {
            const result = await env.GAMES.get(env.GAMES.idFromString(id)).fetch('https://internal/', {method: 'POST', body: JSON.stringify({type: 'catalog'})});
            if ((await result.json()).indexed) indexed++;
          }
          return respond(json({indexed}));
        }
        const match = /^\/admin\/lobbies\/([A-HJ-NP-Z2-9]{10})$/.exec(url.pathname);
        if (!match || body.type !== 'delete') fail('Endpoint not found.', 404);
        return respond(await env.GAMES.get(env.GAMES.idFromName(match[1])).fetch('https://internal/', {method: 'POST', body: JSON.stringify({type: 'delete', code: match[1], admin: true, version: body.version, revision: body.revision})}));
      }

      const secret = request.headers.get('Authorization')?.replace(/^Bearer /, '') ?? '';
      if (!/^[a-f0-9]{64}$/.test(secret)) fail('A valid recovery identity is required.', 401);
      const actor = await hash(secret);
      if (!['GET', 'POST'].includes(request.method)) fail('Method not allowed.', 405);
      if (Number(request.headers.get('Content-Length') ?? 0) > 16000) fail('Request too large.', 413);
      let body = {};
      if (request.method === 'POST') {
        const text = await request.text();
        if (text.length > 16000) fail('Request too large.', 413);
        try {body = JSON.parse(text);} catch (_) {fail('Invalid JSON.');}
        if (!body || typeof body !== 'object' || Array.isArray(body)) fail('Invalid request.');
      }
      if (url.pathname === '/me') {
        if (request.method === 'POST' && !['token', 'removeToken'].includes(body.type)) fail('Invalid profile operation.');
        const data = await profile(env, actor, request.method === 'GET' ? {type: 'get'} : body);
        return respond(json({uid: actor, games: data.games, notificationDevices: data.tokens.length}));
      }
      if (url.pathname === '/games' && request.method === 'POST') {
        const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        if (!/^[a-f0-9]{32}$/.test(body.requestId ?? '')) fail('A request ID is required.');
        const digest = await hash(`${actor}:${body.requestId}`);
        const code = Array.from({length: 10}, (_, i) => alphabet[parseInt(digest.slice(i * 2, i * 2 + 2), 16) % 32]).join('');
        return respond(await env.GAMES.get(env.GAMES.idFromName(code)).fetch('https://internal/', {method: 'POST', body: JSON.stringify({type: 'create', names: body.names, requestId: body.requestId, code, actor})}));
      }
      const match = /^\/games\/([A-HJ-NP-Z2-9]{10})$/.exec(url.pathname);
      if (!match) fail('Endpoint not found.', 404);
      const code = match[1];
      const type = request.method === 'GET' ? 'get' : body.type;
      if (!['get', 'join', 'start', 'restart', 'lobby', 'edit', 'action', 'chat', 'reaction', 'delete'].includes(type)) fail('Unknown operation.');
      return respond(await env.GAMES.get(env.GAMES.idFromName(code)).fetch('https://internal/', {method: 'POST', body: JSON.stringify({...body, type, actor, code, admin: false})}));
    } catch (error) { return respond(json({error: error instanceof ApiError ? error.message : 'Service temporarily unavailable.'}, error.status ?? 503)); }
  }
};
