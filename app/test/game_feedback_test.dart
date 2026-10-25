import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/game_feedback.dart';
import 'package:window_game/localization.dart';

void main() {
  Widget frame({
    String turn = 'Ada:1',
    bool active = true,
    bool finished = false,
    bool canRestart = true,
    bool busy = false,
    VoidCallback? restart,
    VoidCallback? play,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: GameFeedback(
        turnKey: turn,
        player: 'Ada',
        active: active,
        finished: finished,
        canRestart: canRestart,
        busy: busy,
        onRestart: restart ?? () {},
        child: FilledButton(
          onPressed: play ?? () {},
          child: const Text('Play'),
        ),
      ),
    ),
  );

  testWidgets(
    'notice dismisses on tap or after three seconds and repeats only on a new turn',
    (tester) async {
      var plays = 0;
      await tester.pumpWidget(frame(play: () => plays++));
      expect(find.text('Your turn, Ada!'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('turn-notice')));
      await tester.pump();
      expect(plays, 0);
      expect(find.text('Your turn, Ada!'), findsNothing);
      await tester.pumpWidget(frame());
      expect(find.text('Your turn, Ada!'), findsNothing);
      await tester.pumpWidget(frame(turn: 'Ada:2'));
      expect(find.text('Your turn, Ada!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2999));
      expect(find.text('Your turn, Ada!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Your turn, Ada!'), findsNothing);
    },
  );

  testWidgets('host can restart immediately during the lobby celebration', (
    tester,
  ) async {
    var restarts = 0;
    await tester.pumpWidget(frame(finished: true, restart: () => restarts++));
    expect(find.text('You won!'), findsOneWidget);
    final restart = find.widgetWithText(FilledButton, 'Restart game');
    expect(find.textContaining('Ada'), findsNothing);
    expect(tester.widget<FilledButton>(restart).onPressed, isNotNull);
    await tester.tap(restart);
    expect(restarts, 1);
    await tester.pumpWidget(frame());
    expect(find.text('Your turn, Ada!'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('restart is disabled only while an operation is in progress', (
    tester,
  ) async {
    await tester.pumpWidget(frame(finished: true, busy: true));
    final restart = find.widgetWithText(FilledButton, 'Restart game');
    expect(tester.widget<FilledButton>(restart).onPressed, isNull);
    await tester.pumpWidget(frame(finished: true));
    expect(tester.widget<FilledButton>(restart).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('guests share the lobby victory but cannot restart', (
    tester,
  ) async {
    await tester.pumpWidget(
      frame(finished: true, active: false, canRestart: false),
    );
    expect(find.text('You won!'), findsOneWidget);
    expect(find.textContaining('Ada'), findsNothing);
    expect(find.text('Restart game'), findsNothing);
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('Restart game'), findsNothing);
    expect(find.text('Waiting for the host to restart…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
