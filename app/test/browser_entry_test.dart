import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:window_game/async_games.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/main.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/localization.dart';
import 'package:window_game/rl_policy.dart';

class _TestPolicy extends WindowRlPolicy {
  @override
  Future<void> preload() async {}
}

class _IdentityStore implements AsyncIdentityStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String secret) async {}
}

class _Preferences implements LanguagePreferenceStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String language) async {}
}

void main() {
  testWidgets(
    'offline toolbar restart asks first, preserves players and resets only after Yes',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        WindowGameApp(
          languageController: LanguageController(
            store: _Preferences(),
            initialLocale: const Locale('en'),
          ),
          firebaseEnabled: false,
          rlPolicy: _TestPolicy(),
          browserGuest: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Players'),
        'tim, élise',
      );
      await tester.tap(find.text('Start local game'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Tim'), findsWidgets);
      expect(find.text('Élise'), findsOneWidget);
      final restart = find.byKey(const ValueKey('restart-local-game'));
      expect(
        find.ancestor(of: restart, matching: find.byType(AppBar)),
        findsOneWidget,
      );
      expect(find.byTooltip('New local game'), findsNothing);
      expect(
        tester.getRect(restart).right,
        lessThanOrEqualTo(
          tester.getRect(find.byTooltip('Return to menu')).left,
        ),
      );
      List<ImageProvider> cards() => tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => image.image)
          .toList();
      final before = cards();
      await tester.tap(restart);
      await tester.pumpAndSettle();
      expect(find.text('Restart the game?'), findsOneWidget);
      expect(
        find.text('This resets the board and scores and keeps your players.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(cards(), before);
      expect(find.byKey(const ValueKey('turn-notice')), findsNothing);
      await tester.tap(restart);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Yes'));
      await tester.pumpAndSettle();
      expect(find.text('Your turn, Tim!'), findsOneWidget);
      expect(find.text('Tim'), findsWidgets);
      expect(find.text('Élise'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'capitalization collisions are rejected before an offline game starts',
    (tester) async {
      await tester.pumpWidget(
        WindowGameApp(
          languageController: LanguageController(
            store: _Preferences(),
            initialLocale: const Locale('en'),
          ),
          firebaseEnabled: false,
          rlPolicy: _TestPolicy(),
          browserGuest: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Players'),
        'tim, Tim',
      );
      await tester.tap(find.text('Start local game'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('restart-local-game')), findsNothing);
      expect(find.text('Start local game'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'developer mode labels every grid card while preserving card backs and lists the deck',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        WindowGameApp(
          languageController: LanguageController(
            store: _Preferences(),
            initialLocale: const Locale('en'),
          ),
          firebaseEnabled: false,
          rlPolicy: _TestPolicy(),
          browserGuest: false,
          adminClientFactory: () => AsyncGamesClient(
            identity: AsyncIdentity(store: _IdentityStore()),
            endpoint: 'https://example.invalid',
            client: MockClient(
              (request) async =>
                  request.headers['Authorization'] == 'Bearer ${'b' * 64}'
                  ? http.Response('{"lobbies":[]}', 200)
                  : http.Response('{"error":"Invalid admin key."}', 403),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('developer-mode')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Admin key'),
        'wrong',
      );
      await tester.tap(find.text('Open management'));
      await tester.pumpAndSettle();
      expect(find.text('The admin key is invalid.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Admin key'),
        'b' * 64,
      );
      await tester.tap(find.text('Open management'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start local game'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      for (var row = 0; row < windowLayout.length; row++) {
        for (var column = 0; column < windowLayout[row].length; column++) {
          if (!windowLayout[row][column]) continue;
          expect(
            find.descendant(
              of: find.byKey(ValueKey('card:$row:$column')),
              matching: find.byType(Text),
            ),
            findsOneWidget,
          );
        }
      }
      expect(find.text('Remaining deck (next card first)'), findsOneWidget);
      final backs = tester
          .widgetList<Image>(find.byType(Image))
          .where(
            (image) =>
                image.image is AssetImage &&
                (image.image as AssetImage).assetName.endsWith(
                  'card_back.webp',
                ),
          );
      expect(backs.length, 17);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'browser guests only see joining and can use a room from a link',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: GameShell(
            firebaseEnabled: true,
            rlPolicy: _TestPolicy(),
            browserGuest: true,
            initialRoomCode: 'abc234',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Join Window'), findsOneWidget);
      expect(find.text('Start local game'), findsNothing);
      expect(find.text('Create online lobby'), findsNothing);
      final List<TextField> fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields.first.controller!.text, 'ABC234');
      expect(find.text('Players on this device'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unconfigured browser disables joining and explains the problem',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        WindowGameApp(
          languageController: LanguageController(
            store: _Preferences(),
            initialLocale: const Locale('en'),
          ),
          firebaseEnabled: false,
          rlPolicy: _TestPolicy(),
          browserGuest: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.textContaining('no Firebase configuration'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('invalid room codes are rejected before contacting Firebase', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      WindowGameApp(
        languageController: LanguageController(
          store: _Preferences(),
          initialLocale: const Locale('en'),
        ),
        firebaseEnabled: true,
        rlPolicy: _TestPolicy(),
        browserGuest: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Join online room'));
    await tester.tap(find.text('Join online room'));
    await tester.pumpAndSettle();
    expect(find.textContaining('six-character room code'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('installed app still offers local play and lobby hosting', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      WindowGameApp(
        languageController: LanguageController(
          store: _Preferences(),
          initialLocale: const Locale('en'),
        ),
        firebaseEnabled: true,
        rlPolicy: _TestPolicy(),
        browserGuest: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start local game'), findsOneWidget);
    expect(find.text('Create online lobby'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('statistics hint displays future drinks and a short reason', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      WindowGameApp(
        languageController: LanguageController(
          store: _Preferences(),
          initialLocale: const Locale('en'),
        ),
        firebaseEnabled: false,
        rlPolicy: _TestPolicy(),
        browserGuest: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start local game'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.ensureVisible(find.text('Propose best move'));
    await tester.tap(find.text('Propose best move'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Pure statistics'));
      final timer = Stopwatch()..start();
      while (timer.elapsedMilliseconds < 5000) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find
            .textContaining('estimated remaining drinks')
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('estimated remaining drinks'), findsOneWidget);
    expect(find.textContaining('Suggestion:'), findsOneWidget);
    expect(find.textContaining('estimated success'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
