import { readFileSync } from "node:fs";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import {
  ref,
  set,
  get,
  update,
  serverTimestamp,
  remove,
} from "firebase/database";
const env = await initializeTestEnvironment({
  projectId: "demo-window-social",
  database: {
    host: "127.0.0.1",
    port: 19000,
    rules: readFileSync(
      new URL("../../firebase-database.rules.json", import.meta.url),
      "utf8",
    ),
  },
});
let checks = 0;
async function succeeds(p) {
  await assertSucceeds(p);
  checks++;
}
async function fails(p) {
  await assertFails(p);
  checks++;
}
try {
  await env.withSecurityRulesDisabled(async (ctx) =>
    set(ref(ctx.database(), "rooms/ABC234"), {
      public: {
        hostUid: "host",
        members: { host: true, guest: true },
        version: 1,
        started: true,
      },
      private: { secret: "hidden cards" },
      social: {
        messages: { one: { sender: "Host", text: "Hi", createdAt: 1 } },
        turn: { uid: "host", version: 1, stage: "guess" },
      },
    }),
  );
  const host = env.authenticatedContext("host").database();
  const guest = env.authenticatedContext("guest").database();
  const outsider = env.authenticatedContext("outsider").database();
  const anon = env.unauthenticatedContext().database();
  await succeeds(get(ref(guest, "rooms/ABC234/social")));
  await fails(get(ref(outsider, "rooms/ABC234/social")));
  await fails(get(ref(anon, "rooms/ABC234/social")));
  await fails(get(ref(guest, "rooms/ABC234/private")));
  await fails(set(ref(guest, "rooms/ABC234/social/turn"), { stage: "guess" }));
  await succeeds(
    set(ref(host, "rooms/ABC234/social/messages/two"), { text: "Hi" }),
  );
  const request = (uid, type, action) => ({
    uid,
    type,
    action,
    expectedVersion: 1,
    createdAt: serverTimestamp(),
  });
  await succeeds(
    set(
      ref(guest, "rooms/ABC234/requests/chat"),
      request("guest", "chat", { text: "Hello 😂" }),
    ),
  );
  await succeeds(
    set(
      ref(guest, "rooms/ABC234/requests/reaction"),
      request("guest", "reaction", { emoji: "🎉" }),
    ),
  );
  await succeeds(
    set(
      ref(guest, "rooms/ABC234/requests/ui"),
      request("guest", "turnUi", { stage: "guess", row: 1, column: 2 }),
    ),
  );
  await fails(
    set(
      ref(outsider, "rooms/ABC234/requests/outsider"),
      request("outsider", "chat", { text: "Hi" }),
    ),
  );
  await fails(
    set(
      ref(guest, "rooms/ABC234/requests/spoof"),
      request("host", "chat", { text: "Hi" }),
    ),
  );
  await fails(
    set(
      ref(guest, "rooms/ABC234/requests/huge"),
      request("guest", "chat", { text: "x".repeat(501) }),
    ),
  );
  await fails(
    set(ref(guest, "rooms/ABC234/requests/bad-time"), {
      uid: "guest",
      type: "chat",
      createdAt: 0,
      action: { text: "Hi" },
    }),
  );
  await fails(remove(ref(guest, "rooms/ABC234/requests/chat")));
  await succeeds(remove(ref(host, "rooms/ABC234/requests/chat")));
  await succeeds(
    set(ref(outsider, "rooms/ABC234/requests/join"), {
      uid: "outsider",
      type: "joinLobby",
      createdAt: serverTimestamp(),
      seatNames: ["New"],
    }),
  );
  await succeeds(
    update(ref(host, "rooms/ABC234"), {
      public: {
        hostUid: "host",
        members: { host: true, guest: true },
        version: 2,
        started: true,
      },
      private: { secret: "still hidden" },
      "social/turn": null,
    }),
  );
  console.log(`PASS: ${checks} Firebase emulator security checks`);
  // Older hosts do not publish the membership map. Preserve their original
  // Direct presentation is writable only by the active authenticated seat.
  await env.withSecurityRulesDisabled((ctx) =>
    update(ref(ctx.database(), "rooms/ABC234/public"), {
      version: 3,
      started: true,
      state: { currentPlayerIndex: 1 },
      seats: [
        { name: "Host", ownerUid: "host" },
        { name: "Guest", ownerUid: "guest" },
      ],
      members: { host: true, guest: true, spectator: true },
    }),
  );
  const view = {
    uid: "guest",
    version: 3,
    playerIndex: 1,
    stage: "guess",
    row: 2,
    column: 4,
    orientation: "horizontal",
    eventId: "guest:1",
    createdAt: serverTimestamp(),
  };
  const viewPath = "rooms/ABC234/social/turnViews/guest";
  await succeeds(set(ref(guest, viewPath), view));
  await succeeds(get(ref(host, viewPath)));
  await fails(set(ref(guest, viewPath), { ...view, version: 2 }));
  await fails(set(ref(guest, viewPath), { ...view, uid: "host" }));
  await fails(set(ref(guest, viewPath), { ...view, playerIndex: 0 }));
  await fails(set(ref(guest, viewPath), { ...view, column: 99 }));
  await fails(set(ref(guest, viewPath), { ...view, extra: "unexpected" }));
  await fails(
    set(ref(guest, "rooms/ABC234/social/turnViews/host"), {
      ...view,
      uid: "host",
    }),
  );
  const spectator = env.authenticatedContext("spectator").database();
  await fails(
    set(ref(spectator, "rooms/ABC234/social/turnViews/spectator"), {
      ...view,
      uid: "spectator",
    }),
  );
  await fails(set(ref(guest, "rooms/ABC234/public/version"), 99));
  await env.withSecurityRulesDisabled((ctx) =>
    set(ref(ctx.database(), viewPath + "/createdAt"), 0),
  );
  await succeeds(
    update(ref(host, "rooms/ABC234/social"), {
      "messages/fresh": { text: "Chat still works" },
    }),
  );
  await succeeds(
    update(ref(host, "rooms/ABC234/public"), {
      version: 4,
      state: { currentPlayerIndex: 0 },
    }),
  );
  await fails(set(ref(guest, viewPath), { ...view, version: 4 }));

  // move-request permissions while keeping new chat restricted to members.
  await env.withSecurityRulesDisabled((ctx) =>
    set(ref(ctx.database(), "rooms/OLD234/public"), {
      hostUid: "host",
      version: 1,
      started: true,
    }),
  );
  await succeeds(
    set(
      ref(guest, "rooms/OLD234/requests/action"),
      request("guest", "action", { type: "endTurn" }),
    ),
  );
  await fails(
    set(
      ref(guest, "rooms/OLD234/requests/chat"),
      request("guest", "chat", { text: "Hi" }),
    ),
  );
  await succeeds(
    update(ref(host, "rooms/OLD234/public"), {
      members: { host: true, guest: true },
    }),
  );
  await succeeds(
    set(
      ref(guest, "rooms/OLD234/requests/chat"),
      request("guest", "chat", { text: "Hi" }),
    ),
  );
} finally {
  await env.cleanup();
}

// Preserve core gameplay when a client is updated before its database rules.
const legacy = await initializeTestEnvironment({
  projectId: "demo-window-social",
  database: {
    host: "127.0.0.1",
    port: 19000,
    rules: readFileSync(
      new URL("legacy-database.rules.json", import.meta.url),
      "utf8",
    ),
  },
});
try {
  await legacy.withSecurityRulesDisabled((ctx) =>
    set(ref(ctx.database(), "rooms/ABC234"), {
      public: { hostUid: "host", version: 1, started: false },
      private: { secret: "hidden cards" },
    }),
  );
  const host = legacy.authenticatedContext("host").database();
  const guest = legacy.authenticatedContext("guest").database();
  const board = {
    public: {
      hostUid: "host",
      version: 2,
      started: true,
      members: { host: true, guest: true },
    },
    private: { secret: "still hidden" },
  };
  // Reproduce the reported regression, then verify the corrected payload.
  await fails(
    update(ref(host, "rooms/ABC234"), { ...board, "social/turn": null }),
  );
  await succeeds(update(ref(host, "rooms/ABC234"), board));
  await succeeds(
    set(ref(guest, "rooms/ABC234/requests/move"), {
      uid: "guest",
      type: "action",
      expectedVersion: 2,
      createdAt: serverTimestamp(),
      action: { type: "endTurn" },
    }),
  );
  await fails(get(ref(guest, "rooms/ABC234/private")));
  console.log(
    `PASS: ${checks} total security and legacy-rule regression checks`,
  );
} finally {
  await legacy.cleanup();
}
