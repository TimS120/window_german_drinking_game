import test from 'node:test';
import assert from 'node:assert/strict';
globalThis.self = globalThis;
const {engine, transition, names} = await import('../src/worker.js');
const uid = 'host', guest = 'guest';
function room() {
  const result = engine({players: ['Anna', 'Ben']});
  return {state: result.state, social: {}, code: 'ABCDEFGHJK', public: {hostUid: uid, version: 0, started: false, seats: [{index: 0, name: 'Anna', ownerUid: uid}, {index: 1, name: 'Ben', ownerUid: guest}], devices: {[uid]: 'Kitchen', [guest]: 'Living room'}, state: result.publicState, deckSize: result.deckSize, controlId: 0}};
}
test('server uses shared rules and redacts every hidden card and the deck', () => {
  const r = room(); assert.equal(r.state.deck.length, 14); assert.deepEqual(r.public.state.deck, []);
  for (let row = 0; row < 5; row++) for (let col = 0; col < 6; col++) {
    if (!r.state.faceUp[row][col]) assert.equal(r.public.state.cardGrid[row][col], null);
  }
});
test('host controls and moves enforce membership, turn and version', () => {
  const r = room(); assert.throws(() => transition(r, guest, {type: 'start', version: 0}), /host/);
  assert.throws(() => transition(r, 'stranger', {type: 'chat', action: {text: 'Hi'}}), /Join/);
  const started = transition(r, uid, {type: 'start', version: 0});
  assert.throws(() => transition(started, guest, {type: 'action', version: 1, action: {type: 'endTurn'}}), /another player/);
  assert.throws(() => transition(started, uid, {type: 'action', version: 0, action: {type: 'endTurn'}}), /changed/);
  assert.throws(() => transition(started, uid, {type: 'action', version: 1, action: {type: 'endTurn'}}), /Finish/);
});
test('correct move, serialization and handover work with both players offline', () => {
  let r = transition(room(), uid, {type: 'start', version: 0});
  const hidden = r.state.cardGrid[2][4] >> 2, visible = r.state.cardGrid[2][5] >> 2;
  r = transition(r, uid, {type: 'action', version: 1, action: {type: 'guess', position: [2, 4], orientation: 'horizontal', guess: hidden > visible ? 'higher' : hidden < visible ? 'lower' : 'same'}});
  if (r.state.pendingSamePosition) r = transition(r, uid, {type: 'action', version: r.public.version, action: {type: 'confirmSame'}});
  r = JSON.parse(JSON.stringify(r)); // Simulate eviction/restart between requests.
  r = transition(r, uid, {type: 'action', version: r.public.version, action: {type: 'endTurn'}});
  assert.equal(r.public.state.currentPlayerIndex, 1);
  assert.equal(r.public.state.players[1], 'Ben');
});
test('reopen and restart preserve room ownership; empty devices can receive players', () => {
  let r = transition(room(), uid, {type: 'start', version: 0});
  r = transition(r, uid, {type: 'restart', version: 1}); assert.equal(r.public.controlNotice, 'restart');
  r = transition(r, uid, {type: 'lobby', version: 2}); assert.equal(r.public.started, false);
  r = transition(r, uid, {type: 'edit', version: 3, uid: guest, names: [], label: 'Sofa'});
  assert.equal(r.public.seats.length, 1); assert.equal(r.public.devices[guest], 'Sofa');
  r = transition(r, uid, {type: 'edit', version: 4, uid: guest, names: ['ben'], label: 'Sofa'});
  assert.equal(r.public.seats[1].ownerUid, guest); assert.equal(r.public.seats[1].name, 'Ben');
});
test('editing a device keeps its original position in the turn order', () => {
  const r = transition(room(), uid, {type: 'edit', version: 0, uid, names: ['Anna', 'Carla'], label: 'Kitchen'});
  assert.deepEqual(r.public.seats.map(s => s.name), ['Anna', 'Carla', 'Ben']);
});
test('names and chat inputs are bounded and normalized', () => {
  assert.deepEqual(names([' élise ', 'Ben']), ['Élise', 'Ben']);
  assert.throws(() => names(['anna', 'Anna']), /unique/);
  assert.throws(() => names(Array(13).fill('X')), /12/);
  assert.throws(() => transition(room(), guest, {type: 'chat', action: {text: 'a'.repeat(501)}}), /500/);
});

test('wrong guess must be redealt before further guesses or ending the turn, including after restoration', () => {
  let r = transition(room(), uid, {type: 'start', version: 0});
  const hidden = r.state.cardGrid[2][4] >> 2, visible = r.state.cardGrid[2][5] >> 2;
  r = transition(r, uid, {type: 'action', version: r.public.version, action: {type: 'guess', position: [2, 4], orientation: 'horizontal', guess: hidden > visible ? 'lower' : 'higher'}});
  assert.ok(r.state.pendingRemovals.length >= 2);
  assert.deepEqual(r.public.state.pendingRemovals, r.state.pendingRemovals);
  assert.equal(r.public.state.turnCanEnd, false);
  r = JSON.parse(JSON.stringify(r));
  assert.throws(() => transition(r, uid, {type: 'action', version: r.public.version, action: {type: 'guess', position: [2, 3], orientation: 'horizontal', guess: 'higher'}}));
  assert.throws(() => transition(r, uid, {type: 'action', version: r.public.version, action: {type: 'endTurn'}}), /Finish/);
  r = transition(r, uid, {type: 'action', version: r.public.version, action: {type: 'confirmRemovals'}});
  assert.equal(r.state.pendingRemovals.length, 0);
  assert.equal(r.state.faceUp[2][4], false);
  assert.equal(r.state.faceUp[2][5], true);
  assert.equal(r.state.currentPlayerIndex, 0);
  assert.equal(new Set([...r.state.deck, ...r.state.cardGrid.flat().filter(x => x !== null)]).size, 36);
});
