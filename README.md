# Window - a German drinking game

![Window game board](resources/docs/full_game.png)

This project's purpose is the:
- Development of the basic functionality of the German "Window" drinking game
- The creation of methods to predict the next best move, via
   - The training of a DRL-Agend
   - The development of a pure statistical method

**Window** is a cross-platform implementation of the German Window drinking
card game. Play locally on one device, host an online room for friends, or ask
the app for an advisory next-move proposal. The installed Flutter app targets
Android smartphones and PC/laptops running Linux or Windows. Friends can also
join an app-hosted game in their browser without installing anything. iOS
project files remain in the repository, but iOS is outside the current support scope.

> Play responsibly, use non-alcoholic alternatives whenever appropriate, and
> never pressure anyone to drink.

## What you can do

- Start an offline game with any non-empty list of player names.
- Create or join a Firebase-backed online room with a six-character code.
- Join from an installation-free browser client served by Firebase Hosting.
- Register one or more players sharing an installed app or browser device.
- Play the complete Window ruleset: handle moves, passes, redeals, and
  same-rank confirmations.
- Use **Propose best move** for an advisory model/heuristic suggestion. It
  never plays a move automatically.
- Train and deploy a replacement ONNX policy with the GPU-native RL pipeline.

## Get the Android app and share it

The Android installer is a single **compressed universal APK file** at
```text
app/build/app/outputs/flutter-apk/app-release.apk
```

Users do only need the apk-file. APKs and the `build/` directory are Git-ignored, so cloning the repository does not download an installer, so someone must build and share it first.

To install on an Android phone:

1. Download the shared `app-release.apk` onto the phone and open it.
2. If Android asks, allow **Install unknown apps** for the browser or file
   manager used to open it. The wording varies by phone.
3. Choose **Install**, then open **Window**. The permission from step 2 can be turned off again afterward.

To build the compressed universal installer (native libraries are compressed in
the APK and extracted on installation), install Flutter and the Android SDK, then run from the repository root:

```bash
cd app
flutter pub get
flutter build apk --release --dart-define-from-file=../firebase-options.json
```

For online play, first set up `firebase-options.json` as described in
[Firebase multiplayer and browser joining](#firebase-multiplayer-and-browser-joining).
Use the same Firebase project as the other players. For an offline-only APK,
omit `--dart-define-from-file=../firebase-options.json`.

The project currently signs release APKs with the local **debug key**, as
configured in `app/android/app/build.gradle.kts`. This supports direct sharing for testing with friends. Before wider distribution, configure a private release
keystore using the [Flutter Android release guide](https://docs.flutter.dev/deployment/android#sign-the-app)
and keep a backup of it.

## Run on a PC/laptop or smartphone

Install the [Flutter SDK](https://docs.flutter.dev/get-started/install) and
platform tooling. On Ubuntu, install the Linux desktop build prerequisites:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev
```

From the repository root:

```bash
cd app
flutter pub get
flutter test
flutter run -d linux --dart-define-from-file=../firebase-options.json
```

For a Windows PC/laptop, select its `windows` target. For Android, install the
Android SDK, connect a device or start an emulator, then use the device ID from
`flutter devices`:

```bash
flutter run -d YOUR_ANDROID_DEVICE_ID --dart-define-from-file=../firebase-options.json
flutter build apk --release --dart-define-from-file=../firebase-options.json
```

The Linux runner is included. Local play also works without Firebase: omit the
`--dart-define-from-file` argument. To distribute a desktop app, build with
`flutter build linux` on Linux or `flutter build windows` on Windows, passing
that same configuration argument. Keep the entire generated desktop bundle
together when distributing it.

For a Linux desktop task-list icon, build the release bundle and register its
application ID with your desktop (repeat after moving the project):

```bash
python3 tools/install_linux_launcher.py
```

Browser icon changes become visible on the hosted game after running the browser
build command; browsers may retain older icons in their cache.

On Linux, the app prefers X11 (or XWayland in a Wayland desktop session) to
avoid GTK crashes when legacy GNOME font-settings keys are unavailable. This
choice only affects the app; native Wayland remains a fallback when X11 is
unavailable. An explicit `GDK_BACKEND` setting still takes precedence. If your
shell forces Wayland and you see an `xsettings` / `antialiasing` startup error,
run with `GDK_BACKEND=x11` before the `flutter run` command.

## Firebase multiplayer and browser joining

Online rooms require Firebase Anonymous Authentication and Realtime Database.
Enable Anonymous sign-in in Firebase Authentication, create the database, and
create a Git-ignored `firebase-options.json` in the repository root:

```json
{
  "FIREBASE_API_KEY": "...",
  "FIREBASE_WEB_API_KEY": "...",
  "FIREBASE_PROJECT_ID": "your-project-id",
  "FIREBASE_DATABASE_URL": "https://your-database-url"
}
```

The HTTPS connection accepts either API-key field on installed apps; a separate
Android app ID is not required for this connection. After changing the build
configuration, stop the app and run it again with the configuration argument;
hot reload does not update these settings.

Use the same Firebase project for all installed and browser builds. Additional
existing Firebase configuration keys may remain in this file. Optionally set
`WINDOW_BROWSER_URL` to the actual browser address when using a custom domain
or a Hosting site whose name differs from the project ID; otherwise the app
displays `https://YOUR_PROJECT_ID.web.app`.

Deploy the database rules once (or when changing them):

```bash
npx firebase-tools login
npx firebase-tools deploy --only database --project YOUR_PROJECT_ID
```

### Publish the browser client

Firebase Hosting serves the release files while Firebase Realtime Database
connects the host and players. No Flutter development server, laptop, or
Cloudflare tunnel needs to run during a smartphone-hosted game.

Room state and move requests use Firebase's live change stream on Android,
Linux, Windows, and browsers. Updates arrive without the previous 700 ms polling
timers; the host still validates each move. Private and public state publish
together in one atomic update. Connections retry after interruptions and refresh
expired sign-in credentials. Network latency still affects delivery. On Android, creating a room starts a foreground hosting service with an ongoing
notification, so guests can continue during short app switches or screen lock.
Leaving the room stops the service. Force-stopping the app, losing connectivity,
or Android stopping the service still pauses hosting. Cursor sharing is not
included. Online rooms include chat below the game on phones and in a right-hand column
on tablets and desktops, flying emoji reactions, and
a shared view of the active player's selections, comparison/guess panels, and
adviser suggestions. Spectators see legal-card highlights and advice without
gaining permission to play the turn.

Chat can be minimized with the minus button in its header and reopened with the
chat button in the app bar. The board and statistics reclaim the freed space;
unsent drafts and incoming messages are retained while chat is minimized.

English and German are available from the flag selector on the join/menu screen
and beside the chat/home controls in the lobby and game. The app initially uses
the device language (English for unsupported languages), then remembers the
selected language on that device. Switching languages preserves the game,
shared turn view, player names, messages, and chat draft.

The in-app rules are editable Markdown files: `app/assets/rules/en.md` and
`app/assets/rules/de.md`. Edit both when the rules change, then rebuild the app
(or rebuild and publish the browser client). The rules screen supports `#` section
headings, plain paragraphs, and `-` list items and follows the selected app language.

Translations use Flutter's official `gen-l10n` workflow: edit
`app/lib/l10n/app_en.arb` and `app/lib/l10n/app_de.arb`, then run
`flutter gen-l10n` from `app/`. Generated files in `lib/l10n/generated/` should
not be edited manually. ARB placeholders and plural rules handle variable game
text; display numbers use the selected locale. The resource-coverage test
checks that both languages contain every key. Shared game enum values and
existing host proposal descriptions remain compatible across languages.

From the repository root, build the browser client and publish it to Firebase
Hosting automatically:

```bash
python3 tools/browser.py build
```

The helper reads the local Firebase configuration and publishes Hosting only
after a successful build. Firebase CLI login, Node.js/npm, Python 3, and Flutter
are required. To build without publishing, run:

```bash
python3 tools/browser.py build --local-only
```

When database rules also need to be published, use the explicit command:

```bash
python3 tools/browser.py deploy
```

That command deploys both Database rules and Hosting. Running Flutter's own
`flutter build web` directly still builds locally without publishing.

After a successful deployment, the browser client is available at
`https://YOUR_PROJECT_ID.web.app` (also `https://YOUR_PROJECT_ID.firebaseapp.com`).
Rebuild and publish it when updating the game. The browser interface only
joins rooms; local play and lobby creation belong to the installed apps.

For chat and the shared turn view, update the installed host app as well as the
browser client, deploy the new rules, and create a new room. Older hosts do not
relay social events or publish room membership for the new social access rules.
Board/lobby updates use only the original public/private paths, so optional
social permissions cannot block core gameplay. The new rules also preserve
move requests for older hosts that do not yet publish a membership map.

### Chat, reactions, and watching a turn

Chat is available in the lobby, during play, and after the game finishes while
the host remains connected. The panel stays at the bottom; on small screens,
expand its history using the arrow. Messages include a sender and local time;
the room retains its latest 100 messages, with a maximum of 500 characters each.
One-player devices use the player's name. Shared devices use labels such as
`Device 1 (Max, Heiko, Tom)`; numbering follows the order devices joined.

Tap an emoji below the composer to release a short burst on every connected
device. A burst carries one event, and all animation runs locally. Reactions
have a one-second device cooldown, at most five bursts appear at once, and the
motion button reduces the effect to a stationary reaction. System reduced-motion
preferences are also respected. Reconnection restores chat and turn panels
without replaying reactions or clicks from the reconnect snapshot.

Yellow card borders show legal choices to everyone; blue marks the suggested
card. Selecting a card also thickens its border. The original movable dialogs
show comparison and guess choices and adviser selection/calculation to everyone;
spectator controls are read-only. Chat stays usable below the dialog. Dialogs
can be moved locally, and the active player can dismiss them with the backdrop,
Escape, or Android Back. Advice details and blue suggested-button highlights
are shared too. Dialogs adapt to each screen instead of streaming pixels.

The host validates and relays chat and reaction requests in a separate queue
from gameplay. Messages publish as individual deltas; only the latest reaction
and turn view per device are stored. The active player publishes its turn view
directly to Firebase through a separate HTTP client. Rules check seat ownership
and the board version. View uploads run in the background and coalesce pending
changes; selecting a card, choosing a guess, and submitting a move never await
them. Host moves apply directly, and request cleanup also runs in the background.
The host loads chat history once and keeps its relay cache current. Guests
use two database streams (board and social); hosts also watch move requests.
Android hosting continues during short app switches through the foreground service;
the host device still needs a network connection.

Run Flutter's headless tests from `app/` with `flutter test`. Firebase access
rules also have an isolated emulator suite in `tools/firebase-tests/`: with
Node.js 24.12+ and Java 21+ available, run `npm install` followed by `npm test`
there. It uses a local demo project and does not access the deployed database.

### Host and guest flow

1. Open the installed smartphone or PC/laptop app, enter the players sharing
   that device, and choose **Create online lobby**.
2. Share the six-character room code outside the app. For browser guests,
   also share the browser address displayed in the lobby; **Copy browser
   address** copies an invitation link with the room code already filled in.
3. Guests either enter that code in their installed app or open the website
   on their phone or PC/laptop. Enter one or more player names separated by
   commas, then choose **Join online room**. Names must be unique in the lobby.
4. Once everyone appears in the lobby, the host chooses **Start game and lock
   lobby**. New players cannot join after this point.

The room creator is the trusted host: it validates moves and retains the deck
and face-down card identities. Guests receive the public board and submit
requests only for seats owned by their device. Keep the host connected during play. Android hosts can switch apps briefly;
other platforms must keep the host process running. Refresh/restart behavior remains unchanged: anonymous
identity is held in memory, so refreshing or restarting does not recover the
previous seat. Optional links ending in `?room=ABC234` prefill the room code;
guests still enter their names and explicitly join.

## Room access and expiry

The hosted browser address is public. Current rules allow anonymously signed-in
clients to read a room's public snapshot if they know its code. Open lobbies
accept devices with unique player names; starting the game locks new joining.
Private hidden-card state is host-only in normal mode, and chat is limited to
registered room members. Host developer mode deliberately shares hidden values
in the public debug payload. The room code is an invitation, not a user login.

Rooms currently have no automatic thirty-minute expiry. Leaving the app stops
its hosting work but does not delete the stored Firebase room. A future idle-room
expiry should use accepted room activity and server-enforced access/cleanup;
merely stopping the host's network connection does not revoke access to stored
public snapshots. Expiry should not count a host app switch as inactivity while
guests are still playing. Longer invitation secrets, host approval of devices,
and membership-gated board reads would further limit access by strangers.

## Appearance and saved settings

The appearance menu (sun/moon/automatic icon) is available on the home/join
screen and in the lobby/game toolbar. Choose **Use system theme**, **Light
mode**, or **Dark mode**. New installations follow the system's theme, including
changes while the app is running. Selecting a mode overrides that default until
you change it again. Dark mode retains the original green/gold design.

Theme and language choices are saved on that device or browser profile and
restored on later launches. Browser preferences persist until site data is
cleared; they are independent of the host and other players' preferences.

A single hosted browser client can join new lobbies from either PC or Android
hosts without a separate deployment per room. The home screen reminds players
of this option, and each lobby displays a browser invitation with its room code
prefilled. Guests still enter their names and explicitly join before the host
locks the lobby by starting the game.

During an online game the host can use **Restart game** in the toolbar at any
time, including while another device owns the turn. The host must confirm the
restart; Cancel leaves the game untouched. Everyone sees a shared three-second
restart notice, dismissible by tapping it. Restarting resets the board,
deck, turn, and scores in the same locked room, preserving seats and chat.
Guests cannot use this control or write the authoritative room state. Offline
games use the same toolbar position and confirmation; there is no separate
instant-reset button in the information panel. Restarting preserves the player
list in either mode.

Player and device-group names are trimmed and start with a capital letter when
starting, joining, or saving. The rest of the spelling is preserved (for example
`tim` becomes `Tim`, while `McDonald` and `TIM` stay as entered).

The host's overflow menu also offers **Return to lobby**, with confirmation.
Everyone returns to the same room code and chat, and new devices can join again.
The lobby groups players by the device connection they share. The host can name
each group after its physical room (for example Living room or Kitchen) and edit
its comma-separated player list. Removing every player from a device leaves the
group registered so the host can add players back without reconnecting it.
Names must remain unique across the lobby, and at least one player must remain.
Editing is disabled after the host starts the game again.

Portrait screens put the board first. The free top-right board slot shows the
deck count; the lower-right slots hold **End turn** and **Propose best move**.
Landscape layouts retain the controls in the information panel. Routine room-code,
seat-waiting and successful model-loading text is hidden during play. Adviser
failures appear as red local System messages in online chat, or a red error in
local play; these diagnostic messages are not sent as player chat.

## Turn indicators, winning, and developer mode

At the start of each local turn (or a turn owned by your online device), a
notice appears for three seconds. Tap it to dismiss it immediately. Other
devices see a grey game area with disabled gameplay controls; scrolling,
chat, and leaving the room remain available.

Completing the window celebrates the whole lobby with “You won!” and plays
rockets that launch from the bottom and burst across the screen for fifteen
seconds. Devices requesting reduced motion see the result without fireworks.
The host can request a restart immediately, including during the animation,
then confirm it in the same locked room, preserving
its code, players, seat ownership, and chat. Local games can restart too.

Enable **Developer mode** on the home/join screen before starting or joining.
Grid cards keep their normal fronts/backs with a value label overlaid; the
remaining deck is listed in draw order, next card first. This does not change
what the advisers know. In online games the host must enable developer mode
before hidden values can be shared with developer-mode guests. Treat these as
test rooms: enabling it on the host publishes the full deck and hidden grid in
the room's public debug payload. Normal rooms still publish only visible cards.

Android hosting uses a data-sync foreground service and a partial wake lock
while the room is open. Android 15+ limits this service type to six hours in the
background, resetting the allowance when the app returns to the foreground;
the service stops cleanly at its timeout. It is intended for short app switches,
not permanent server hosting. For uninterrupted hosting independent of any
player's device, move authoritative validation to a server in a future change.

## Documentation

- [Game rules](GAME_README.md) — setup, valid guesses, redeals, and scoring.
- [Statistics adviser](STATISTICS_README.md) — public-history beliefs, bounded simulations, and explanations.
- [ML development](ML_README.md) — CUDA training, evaluation, export, and
  deployment.
- [ML agent specification](ml/ml_move_prediction_plan.txt) — target,
  information restrictions, contract, and acceptance criteria.

## Repository map

| Location | Purpose |
| --- | --- |
| `app/` | Flutter application for all player-facing platforms. |
| `app/lib/game_engine.dart` | Canonical rules, independent of UI and networking. |
| `app/lib/main.dart` | Responsive local and online game interface. |
| `app/lib/firebase_room_repository.dart` | Host-authoritative Firebase room transport. |
| `app/lib/rl_policy.dart` | ONNX inference, legal-action masking, and explicit adviser errors. |
| `app/assets/` | Card artwork and bundled ONNX policy. |
| `app/test/` | Game-engine, policy, browser entry, and lobby transport tests. |
| `tools/browser.py` | Build and publish the browser guest client to Firebase Hosting. |
| `ml/` | GPU-native masked-PPO trainer, simulator, and ONNX exporter. |
| `firebase-database.rules.json` | Firebase Realtime Database access rules. |
| `resources/docs/` | Documentation imagery. |

## Current model status

`app/assets/models/window_policy.onnx` is deliberately untrained and verifies
only packaging and inference. Until a trained policy is exported, the app
labels its proposal accordingly. Pure statistics is independently selectable
and also handles unavailable models or inference failures.

## Comparing the advisers

Run `python3 tools/compare_advisers.py` from the repository root to compare the current RL and statistics advisers through full games in parallel headless Dart workers using the same app rules engine. Unchanged code reuses a cached executable; model inference uses persistent ONNX workers. The default runs 240 games, with a hard 250-game limit. Read `benchmark-results/YYYY-MM-DD_HH-MM-SS/report.md` (the same timestamp format as RL training). See [BENCHMARK_README.md](BENCHMARK_README.md) for scenario selection, runtime, interpretation, and failure handling.

### Asynchronous cooperative games

Open **Asynchronous games** from the home screen (installed app or browser).
Create a lobby, share its 10-character game code or invitation, and start after
the players have joined. It uses the same cooperative rules, board, adviser,
chat, host-only restart confirmation and lobby editing as live play.

Players can close the app between turns. The Cloudflare server saves and
validates moves, so no host device has to remain online. There is no turn
deadline or automatic lobby expiry, including after winning. Creating more
lobbies adds stored data and saved-game entries; idle servers can sleep while
their data stays saved. The saved-games list restores after restarting the app. Its key button
shows a private recovery code: save it to restore the same player and games on
another device. Anyone with that code can act as that player. Invitations contain
only the game code, never the recovery code.

Enable turn notifications on Android or supported browsers. Notifications need
permission; Linux/Windows can check the saved-games list. While a room is open,
changes refresh within 30 seconds, immediately after your own move, on manual
refresh, and when the app returns from the background. Push delivery is subject
to the device/browser's background restrictions and does not determine whether
the game is saved.

This mode uses **Cloudflare Workers Free** with SQLite-backed Durable Objects and
**Firebase Spark** for messaging. It does not require a billing account or paid
plan. Setup, deployment, notification configuration and tests are documented in
[backend/README.md](backend/README.md). Local and live online modes keep their
existing behavior.

For a new checkout, copy `firebase-options.example.json` to
`firebase-options.json`, and `backend/wrangler.example.jsonc` to
`backend/wrangler.jsonc`. Fill in the local copies only. Real configs, local
secret files, generated Firebase resources and Wrangler state are excluded from
Git; the example files contain placeholders.


Asynchronous lobbies can be deleted by their host from **Your saved games**, with
confirmation. **Manage all lobbies** provides an admin-key-protected overview of
all rooms, players, status and last activity date (UTC), plus confirmed deletion.
Playing daily keeps a lobby available indefinitely; there is no automatic expiry.
See [backend lobby management](backend/README.md#lobby-management) for private key
setup and indexing older lobbies. Only example configs belong in Git.
