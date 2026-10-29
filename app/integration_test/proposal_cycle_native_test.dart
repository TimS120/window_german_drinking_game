import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_game/appearance.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/localization.dart';
import 'package:window_game/main.dart';
import 'package:window_game/rl_policy.dart';

class _Preferences implements LanguagePreferenceStore, ThemePreferenceStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
}

class _ObservedPolicy extends WindowRlPolicy {
  int rlCalls = 0, statisticsCalls = 0;
  @override
  Future<List<AiMoveProposal>> rankedProposals(WindowGameEngine game) {
    rlCalls++;
    return super.rankedProposals(game);
  }

  @override
  Future<List<AiMoveProposal>> rankedStatisticsProposals(
    WindowGameEngine game,
  ) {
    statisticsCalls++;
    return super.rankedStatisticsProposals(game);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real advisers cycle best/second and reset on method or round changes',
    (tester) async {
      final policy = _ObservedPolicy();
      final language = LanguageController(
        store: _Preferences(),
        initialLocale: const Locale('en'),
      );
      final theme = ThemeController(store: _Preferences());
      await tester.runAsync(policy.preload);
      expect(
        policy.availability,
        PolicyAvailability.ready,
        reason: policy.inferenceError,
      );
      await tester.pumpWidget(
        WindowGameApp(
          firebaseEnabled: false,
          rlPolicy: policy,
          languageController: language,
          themeController: theme,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(TextField, 'Players'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Players'),
        'Verifier',
      );
      await tester.ensureVisible(find.text('Start local game'));
      await tester.tap(find.text('Start local game'));
      await tester.pumpAndSettle();

      Future<void> choose(String method, int rank) async {
        final notice = find.byKey(const ValueKey('turn-notice'));
        if (notice.evaluate().isNotEmpty) {
          await tester.tap(notice);
          await tester.pumpAndSettle();
        }
        final control = find.byKey(const ValueKey('board-propose'));
        final button = control.evaluate().isNotEmpty
            ? control
            : find.text('Propose best move');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.tap(find.text(method).last);
        await tester.pumpAndSettle();
        for (
          int i = 0;
          i < 200 && find.textContaining('Finding').evaluate().isNotEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.textContaining('Finding'), findsNothing);
        expect(find.textContaining('Prediction failed'), findsNothing);
        expect(
          find.textContaining('Second-best suggestion:'),
          rank == 1 ? findsWidgets : findsNothing,
        );
      }

      await choose('RL model', 0);
      await choose('RL model', 1);
      await choose('RL model', 0);
      await choose('Pure statistics', 0);
      await choose('Pure statistics', 1);
      await choose('RL model', 0);
      expect(policy.rlCalls, 1);
      expect(policy.statisticsCalls, 1);
      await tester.tap(find.byKey(const ValueKey('restart-local-game')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      await choose('RL model', 0);
      expect(policy.rlCalls, 2);
      await tester.pumpWidget(const SizedBox());
      language.dispose();
      theme.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
