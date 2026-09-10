# Window

Cross-platform implementation of the German Window card game. The Flutter app
in `app/` is the single player-facing client for Android, iOS, browsers, and
Windows. It supports complete offline/local games and Firebase-backed online
rooms; the optional best-move model remains a later stage.

## Test the game on this PC

Flutter has been installed locally at:

`C:\Users\timss\Documents\Codex\tools\flutter_prebuilt\flutter`

Open PowerShell and run:

```powershell
$env:Path = "C:\Users\timss\Documents\Codex\tools\flutter_prebuilt\flutter\bin;$env:Path"
Set-Location C:\Users\timss\Desktop\window_german_drinking_game\app
flutter test
flutter run -d chrome
```

The last command opens the game in Chrome on this PC. Enter comma-separated
player names, start a local game, and play through card guesses, incorrect-guess
redeals, same-rank penalties, and turn changes.

To build a browser release instead of launching a development session:

```powershell
flutter build web
```

The generated Windows, Android, iOS, and web project targets are already in
`app/`. iOS builds need a Mac with Xcode.

## Online rooms (Firebase)

Online rooms have mixed seats: player names in **Players** are people sharing
the device that creates the room; names in **Remote player seats** are reserved
for players who join from their own device. The host shares the six-character
room code and the reserved seat name. Each turn can be controlled only by the
Firebase account that owns that player seat.

The client never writes room state. It can only read a sanitized public board:
the identities of face-down cards and the deck stay in the private server
state. `createRoom`, `joinRoom`, and `submitAction` are callable Cloud
Functions. The function validates the active seat, expected version, legal
card option, and rule outcome before publishing the next snapshot.

There is deliberately no static shared password. Enable **Anonymous** sign-in
in Firebase Authentication. The `firebase-database.rules.json` file denies all
client room writes and denies reads of `/rooms/$roomCode/private`.

To connect a build, create a local `firebase-options.json` beside this README
(it is ignored by Git) with the public Firebase identifiers from the
`window-game` project:

```json
{
  "FIREBASE_API_KEY": "...",
  "FIREBASE_APP_ID": "...",
  "FIREBASE_PROJECT_ID": "window-game",
  "FIREBASE_MESSAGING_SENDER_ID": "644351731437",
  "FIREBASE_DATABASE_URL": "https://window-game-default-rtdb.europe-west1.firebasedatabase.app",
  "FIREBASE_AUTH_DOMAIN": "window-game.firebaseapp.com"
}
```

Use a Web app's configuration for browser builds. Register the Flutter Android
application id (`com.timss.window.window_game`) and the future iOS bundle id in
the Firebase console, then use their configuration values for native builds.
Run the app with:

```powershell
flutter run -d chrome --dart-define-from-file=..\firebase-options.json
```

Deploy the authoritative backend from the repository root after signing into
the intended Firebase project:

```powershell
$env:NODE_OPTIONS = "--use-system-ca" # needed on this PC because Avast scans HTTPS
npx firebase-tools use window-game
npm --prefix functions run deploy
```

Cloud Functions require the Firebase project's billing configuration to permit
the Cloud Functions runtime. Do not deploy until the project is deliberately
selected in the Firebase CLI.

## Repository layout

- `app/lib/game_engine.dart` — canonical pure-Dart game rules, no UI or network code.
- `app/lib/main.dart` — responsive local/online Flutter game interface.
- `app/lib/firebase_room_repository.dart` — authenticated, read-only room
  listener and callable-action client.
- `functions/src/index.ts` — authoritative Firebase room and rules backend.
- `app/test/game_engine_test.dart` — deterministic rules compatibility tests.
- `app/assets/cards/` — shared card artwork bundled into all Flutter targets.
- `scripts/`, `configs/`, `requirements/` — retained Python simulation and RL-training tooling. These are not part of the player application and will be connected to the Flutter advisor only in the later model stage.

## Current migration boundary

The old Android-specific application and Tkinter desktop interface remain in
the repository only as a temporary rollback reference while this Flutter stage
is being tested. They will be removed in the next cleanup commit after you
confirm the new game works. The Python rules implementation then remains only
as the established training/simulation implementation. Before the best-move
model is migrated, we will add explicit cross-language fixtures so that the
Dart and Python training rules remain behaviorally aligned.
