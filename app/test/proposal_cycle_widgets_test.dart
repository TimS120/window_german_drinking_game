import 'dart:async';

import 'package:flutter/material.dart' hide Orientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/localization.dart';
import 'package:window_game/main.dart';
import 'package:window_game/rl_policy.dart';

import 'localization_test.dart' show MemoryLanguages, chooseLanguage;

class RankedPolicy extends WindowRlPolicy {
  int rlCalls = 0, statisticsCalls = 0;
  Completer<void>? nextGate;
  @override
  Future<void> preload() async {}
  List<AiMoveProposal> pair(WindowGameEngine game, String method) {
    final actions = WindowRlCodec.validActions(game);
    return [
      for (int i = 0; i < 2; i++)
        AiMoveProposal(
          action: actions[i],
          confidence: i == 0 ? .8 : .2,
          source: 'Test',
          explanation: '$method ${i == 0 ? 'best' : 'second'}',
        ),
    ];
  }

  @override
  Future<List<AiMoveProposal>> rankedProposals(WindowGameEngine game) async {
    rlCalls++;
    final result = pair(game, 'RL');
    final gate = nextGate;
    nextGate = null;
    if (gate != null) await gate.future;
    return result;
  }

  @override
  Future<List<AiMoveProposal>> rankedStatisticsProposals(
    WindowGameEngine game,
  ) async {
    statisticsCalls++;
    return pair(game, 'Statistics');
  }
}

Future<void> start(WidgetTester tester, RankedPolicy policy) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final language = LanguageController(
    store: MemoryLanguages(),
    initialLocale: const Locale('en'),
  );
  addTearDown(language.dispose);
  await tester.pumpWidget(
    WindowGameApp(
      firebaseEnabled: false,
      rlPolicy: policy,
      languageController: language,
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Players'), 'Ada');
  await tester.tap(find.text('Start local game'));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 3));
}

Future<void> choose(WidgetTester tester, String method) async {
  final notice = find.byKey(const ValueKey('turn-notice'));
  if (notice.evaluate().isNotEmpty) {
    await tester.tap(notice);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Propose best move'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(method).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('same method cycles; switching resets; rankings are cached', (
    tester,
  ) async {
    final policy = RankedPolicy();
    await start(tester, policy);
    await choose(tester, 'RL model');
    expect(find.text('RL best'), findsOneWidget);
    await choose(tester, 'RL model');
    expect(find.text('RL second'), findsOneWidget);
    expect(find.textContaining('Second-best suggestion:'), findsWidgets);
    await chooseLanguage(tester, 'Choose language', 'Deutsch');
    expect(find.textContaining('Zweitbeste Empfehlung:'), findsWidgets);
    await chooseLanguage(tester, 'Sprache wählen', 'English');
    await choose(tester, 'RL model');
    expect(find.text('RL best'), findsOneWidget);
    await choose(tester, 'Pure statistics');
    expect(find.text('Statistics best'), findsOneWidget);
    await choose(tester, 'Pure statistics');
    expect(find.text('Statistics second'), findsOneWidget);
    await choose(tester, 'RL model');
    expect(find.text('RL best'), findsOneWidget);
    expect(find.textContaining('Second-best suggestion:'), findsNothing);
    expect(policy.rlCalls, 1);
    expect(policy.statisticsCalls, 1);
    // Restart invalidates both cached methods and their rank.
    await tester.tap(find.byKey(const ValueKey('restart-local-game')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    await choose(tester, 'RL model');
    expect(find.text('RL best'), findsOneWidget);
    expect(policy.rlCalls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a result arriving after restart cannot populate the new cycle', (
    tester,
  ) async {
    final policy = RankedPolicy();
    final gate = Completer<void>();
    policy.nextGate = gate;
    await start(tester, policy);
    await tester.tap(find.text('Propose best move'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RL model').last);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('restart-local-game')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('RL best'), findsNothing);
    await choose(tester, 'RL model');
    expect(find.text('RL best'), findsOneWidget);
    expect(policy.rlCalls, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
