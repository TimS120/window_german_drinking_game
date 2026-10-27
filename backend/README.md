# Asynchronous Window backend

This is a separate server-authoritative mode. Live Firebase rooms keep their
existing host-authoritative transport. No Firebase Cloud Functions, billing
account, paid Workers plan, or always-running host device is required.

## Deployment

Requirements: Flutter/Dart SDK, Node.js 22+, a **Cloudflare Workers Free** account,
and the existing Firebase **Spark** project. Never upgrade either plan to deploy
this mode. Free quota exhaustion is a service failure, not permission to upgrade.

```bash
cd backend
npm ci
cp wrangler.example.jsonc wrangler.jsonc
# Set BROWSER_URL in wrangler.jsonc to your Firebase Hosting URL.
npx wrangler login
npm test
npm run deploy
```

The deployment uses SQLite-backed Durable Objects, supported on Workers Free.
`predeploy` compiles `engine_bridge.dart` with Dart to JavaScript. This imports the
app's actual `game_engine.dart` and `game_state_codec.dart`; there is no separate
JavaScript implementation of the game rules. The server uses `Random.secure()`
for dealing and redealing. Generated engine JavaScript is ignored in Git.

Copy the root `firebase-options.example.json` to `firebase-options.json` and fill
in the Firebase public client fields. Use the returned HTTPS Worker URL as
`WINDOW_ASYNC_URL`. Both real config files (`firebase-options.json` and
`backend/wrangler.jsonc`) are ignored; commit only their example counterparts.
Local `.dev.vars`/`.env` files and their environment variants are ignored too;
`backend/.dev.vars.example` contains only a placeholder.
`backend/wrangler.jsonc` contains the public browser origin for CORS and invitation
links. No server credential belongs in the app or in a Dart define.

## Turn notifications

Firebase Cloud Messaging is a no-cost product on Spark and can be called by the
Worker. Configure a dedicated Google service account with the
`roles/firebasecloudmessaging.admin` role in this Firebase project. Store its JSON
credential only in the Worker secret store:

```bash
npx wrangler secret put FCM_SERVICE_ACCOUNT
```

Paste the JSON into the command's input; never pass it in command-line arguments,
commit it, or put it in the Flutter configuration. Revoke the key if the Worker
is retired. This service account does not need database access, billing access,
or Firebase Administrator permissions.

Android requires the existing package's Firebase app ID and API key in
`FIREBASE_ANDROID_APP_ID` and `FIREBASE_API_KEY`. For browser notifications, use
the Firebase console's Cloud Messaging / Web Push certificates public key as
`FIREBASE_VAPID_KEY`. **Only the public key goes into the app.**

Before Android/web builds, generate public client resources:

```bash
python3 tools/configure_async_notifications.py
```

`tools/browser.py build` also runs that step. It generates Android resource XML
so Firebase can receive notifications when Flutter is not running, and public
web configuration loaded by `firebase-messaging-sw.js`. No private credential is
included. Keep the service worker's SDK version aligned with `firebase_core_web`.

The app explicitly asks to enable notifications. Android and supported browsers
can receive them; Linux/Windows use the saved-games screen and refresh button.
FCM registration uses Firebase Installation IDs and refreshes enabled
registrations on app startup. Recovering an identity moves this device's
notification registration from its previous identity. Recovery codes are not
notification tokens and are never put in URLs.

## Persistence and consistency

- A random 256-bit recovery secret is saved on the device. Its SHA-256 digest is
  the server-side identity. Treat the recovery code as a password; possessing it
  restores access to all of that identity's saved games.
- A 10-character random-looking invitation code admits players only while the
  lobby is open. Only members can read a room; joining does not grant host rights.
- Hidden cards and the remaining deck stay in the room's private SQL record.
  Every client, including the host, receives a redacted public board.
- Each move/control operation carries an expected game version and an idempotency
  key. Synchronous validation and a single SQL commit prevent competing writes.
  Recent duplicate requests are ignored; older replays fail the version check.
  Creation retries deterministically address the same room.
- SQL records survive Durable Object eviction, Worker deployments and closed
  apps. There is no turn deadline and no automatic room expiry.
  Daily play therefore does not expire a lobby. Completed lobbies also remain
  stored. Each additional lobby adds persistent SQL data and an index entry;
  it does not keep a server continuously running. Hosts can explicitly delete
  their own lobbies; an administrator can manage all lobbies as described below.
- A separate player index lists saved games on restored devices.
- The current room refreshes every 30 seconds only while the app is in the
  foreground. Moves refresh immediately; returning from background also refreshes.
  Local dialogs/adviser selections do not generate server writes per tap.
- Notification handovers use a persisted outbox and Durable Object alarms with
  bounded retries. Notifications may arrive late or be duplicated after a retry;
  the saved game is authoritative. OS force-stop/disabled permissions can prevent
  notifications until the app is reopened.
- Chat retains the last 100 messages per game. The initial asynchronous mode
  supports up to 12 players/devices per room.

## Validation

```bash
npm test
npm run dev -- --port 8790
# In another terminal, from the project root:
node backend/test/http.integration.mjs
# Optional against a deployed backend (creates a disposable test game):
ASYNC_TEST_URL=https://your-worker.workers.dev node backend/test/http.integration.mjs
```

Integration coverage includes creation retries, joins, member-only reads,
hidden-card redaction, wrong-player/stale-version rejection, concurrent host
controls, a turn handover with no host process, recovery and chat. Management authorization, retry cleanup, persistence and pagination are covered
by `npm test`. An additional disposable-room check is available:

```bash
ASYNC_TEST_URL=https://your-worker.workers.dev node backend/test/management.integration.mjs
# To include admin listing/deletion, set ASYNC_ADMIN_KEY_FILE to your private key file.
```

Tests do not change billing configuration.

## Lobby management

The saved-games screen offers host-only deletion beside each owned lobby and
**Manage all lobbies** for an administrator. Both require confirmation. Deleting
removes the board, chat, pending notifications, saved-game references and the
management listing for everyone. A small deletion marker remains to prevent a
retried creation request from resurrecting the room. This is not automatic expiry.
A client viewing a deleted room learns about it on its next refresh or action.

The overview lists room codes, players, status, creation date and last activity
**date in UTC**, oldest activity first. Accepted joins, game/lobby changes, chat
and reactions update activity; reads, polls and management do not. Older lobbies
have an unknown creation date rather than an invented one. Deletion is rejected
if the room changed after the displayed snapshot; refresh and confirm again.

Set up an independent admin credential from the project root:

```bash
python3 tools/configure_async_admin.py --upload
```

This creates a random private key at
`~/.config/window-game/async-admin-key.txt` with mode 0600 and uploads only its
SHA-256 digest as Worker secret `ADMIN_KEY_HASH`. Keep the plaintext outside the
repository and builds; never put it in URLs, example configs or Dart defines.
Enter the key in the app's management screen. It stays in memory only until
locking or leaving the screen. It grants listing and deletion of all asynchronous
lobbies, not device access. Removing/changing the Worker secret revokes access.
No Cloudflare/Firebase account credential is distributed to the app.

For lobbies created before management was deployed, refresh the Wrangler login
and import their metadata once (no activity timestamps change and none are deleted):

```bash
cd backend
npx wrangler whoami
cd ..
python3 tools/index_async_lobbies.py --account-id YOUR_CLOUDFLARE_ACCOUNT_ID
```

The indexer reads the local Wrangler OAuth token (or `CLOUDFLARE_API_TOKEN`) only
for Cloudflare's namespace inventory; it sends the separate admin key to the game
backend. New lobbies index themselves, and pending index/cleanup failures retry
through Durable Object alarms. The v2 migration adds a catalog without replacing
the existing game or player storage.
