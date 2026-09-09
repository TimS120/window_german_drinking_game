# Window

Cross-platform implementation of the German Window card game. The Flutter app
in `app/` is the single player-facing client for Android, iOS, browsers, and
Windows. It currently supports complete offline/local games; online rooms and
the optional best-move model are deliberately scheduled for later stages.

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
`app/`. iOS builds need a Mac with Xcode. The Flutter Windows target is present,
but this PC's pre-existing Visual Studio Build Tools instance is incomplete;
`flutter doctor` identifies the remaining Microsoft C++ setup issue before a
native Windows executable can be built.

## Repository layout

- `app/lib/game_engine.dart` — canonical pure-Dart game rules, no UI or network code.
- `app/lib/main.dart` — responsive local Flutter game interface.
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
