import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/main.dart';
import 'package:window_game/rl_policy.dart';

class _TestPolicy extends WindowRlPolicy {
  @override
  Future<void> preload() async {}
}

void main() {
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
        firebaseEnabled: true,
        rlPolicy: _TestPolicy(),
        browserGuest: true,
      ),
    );
    await tester.pumpAndSettle();
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
        firebaseEnabled: false,
        rlPolicy: _TestPolicy(),
        browserGuest: false,
      ),
    );
    await tester.tap(find.text('Start local game'));
    await tester.pumpAndSettle();
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
