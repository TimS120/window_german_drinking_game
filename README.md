# Window

Cross-platform implementation of the German Window card game. The Flutter app
in `app/` is the single player-facing client for Android, iOS, browsers, and
Windows. It supports complete offline/local games and Firebase-backed online
rooms and an untrained, on-device best-move proposal pipeline.

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

Online rooms begin as an open lobby. Player names in **Players** are people
sharing the host device; other people join independently with the six-character
room code and a name they choose themselves. The host sees the roster and
presses **Start game and lock lobby** when everybody is present. After that,
the roster and turn order are fixed. Each turn can be controlled only by the
Firebase account that owns that player seat.

This version works on Firebase's free Spark plan. The device that creates a
room is the **host**: it alone reads the private deck and validates actions
before publishing the next sanitized board. Other devices can only read the
public board and submit a seat or move request. Face-down card identities and
the deck never reach guest devices.

Keep the host game open while people are playing. This is an excellent
lightweight solution for a friendly drinking game, but it deliberately does
not claim to be cheat-proof: the host device is trusted instead of a paid
server runtime.

There is deliberately no static shared password. Enable **Anonymous** sign-in
in Firebase Authentication. The `firebase-database.rules.json` file lets only
the room host publish state or read private state; guests can create only
requests bearing their own Firebase UID.

To connect a build, create a local `firebase-options.json` beside this README
(it is ignored by Git) with the public Firebase identifiers from the
`window-game` project:

```json
{
  "FIREBASE_API_KEY": "...",
  "FIREBASE_WEB_API_KEY": "...",
  "FIREBASE_ANDROID_APP_ID": "...",
  "FIREBASE_WEB_APP_ID": "...",
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

Once, deploy the database rules from the repository root after signing into
the intended Firebase project:

```powershell
$env:NODE_OPTIONS = "--use-system-ca" # needed on this PC because Avast scans HTTPS
npx firebase-tools deploy --only database --project window-game
```

This deploy uses Realtime Database only; it does **not** need the Blaze plan.

## Repository layout

- `app/lib/game_engine.dart` — canonical pure-Dart game rules, no UI or network code.
- `app/lib/main.dart` — responsive local/online Flutter game interface.
- `app/lib/firebase_room_repository.dart` — authenticated Firebase room
  transport, host state publisher, and guest-request client.
- `app/lib/rl_policy.dart` — shared RL observation/action contract, ONNX
  inference adapter, and safe untrained heuristic fallback.
- `app/test/game_engine_test.dart` — deterministic rules compatibility tests.
- `app/test/rl_policy_test.dart` — RL input/action contract tests.
- `app/assets/cards/` — shared card artwork bundled into all Flutter targets.
- `ml/` — future PyTorch RL checkpoint format and checkpoint-to-ONNX exporter.

## Best-move proposal / future RL model

The **Propose best move** button is available during an eligible turn. It is
advisory only: it never plays a card or changes a multiplayer room. Until a
trained model is exported, it uses a transparent probability-based heuristic
and says so in the UI.

The future RL policy contract is fixed at a 95-float observation and 300 action
logits. Train and export it on this PC using the instructions in
[`ml/README.md`](ml/README.md). Exported models belong at
`app/assets/models/window_policy.onnx`; that directory is bundled for Windows,
Android, iOS, and web. The runtime then loads the ONNX model automatically and
masks invalid moves before it proposes the highest-scoring legal action.

`window_policy.onnx` is a deliberately untrained, deterministic test model
that is shared in Git to exercise the full workflow. Local checkpoints and any
other exported ONNX artifacts are ignored by Git intentionally.
