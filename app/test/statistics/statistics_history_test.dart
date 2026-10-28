import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/game_state_codec.dart';
import 'package:window_game/rl_policy.dart';

WindowGameEngine historyGame() {
  final game = WindowGameEngine(['A', 'B', 'C', 'D'], seed: 27);
  for (int i = 0; i < 40; i++) {
    final target = game.validSelectablePositions().first;
    final option = game.getValidOptionsForCard(target).first;
    final rank = game.cardAt(target)! ~/ 4;
    final boundary = game.cardAt(option.neighbors.first)! ~/ 4;
    final result = game.applyGuess(
      target,
      option,
      rank > boundary ? GuessType.lower : GuessType.higher,
    );
    expect(result.requiresRemovalConfirmation, isTrue);
    game.confirmRemovals();
  }
  return game;
}

void sameProposal(AiMoveProposal a, AiMoveProposal b) {
  expect(a.action.index, b.action.index);
  expect(a.confidence, b.confidence);
  expect(a.expectedDrinks, b.expectedDrinks);
}

void main() {
  test('sync and worker entry points reject histories outside 0–32', () {
    final game = WindowGameEngine(['A'], seed: 1);
    for (final invalid in [-1, 33]) {
      expect(
        () => StatisticsPolicy.propose(game, historyLength: invalid),
        throwsRangeError,
      );
      expect(
        () => StatisticsPolicy.inspectBeliefs(game, historyLength: invalid),
        throwsRangeError,
      );
      expect(
        () => WindowRlPolicy.proposeStatistics(game, historyLength: invalid),
        throwsRangeError,
      );
    }
  });

  test(
    'default stays sixteen and full-state entry obeys each requested limit',
    () {
      final game = historyGame();
      sameProposal(
        StatisticsPolicy.propose(game, fixedRounds: 3),
        StatisticsPolicy.propose(game, historyLength: 16, fixedRounds: 3),
      );
      for (final length in [0, 1, 4, 8, 16, 24, 32]) {
        final fromGame = StatisticsPolicy.propose(
          game,
          historyLength: length,
          fixedRounds: 3,
          scenarioSeed: 48271,
        );
        // Supplying a full private state must still sanitize hidden values.
        final fromState = StatisticsPolicy.proposeFromState(
          game.exportState(),
          historyLength: length,
          fixedRounds: 3,
          scenarioSeed: 48271,
        );
        sameProposal(fromGame, fromState);
        final d = fromState.statisticsDiagnostics!;
        expect(d.historyLimit, length);
        expect(d.historyEvents, length);
        expect(d.searchRounds, 3);
        expect(d.beliefMicros, isNonNegative);
        expect(d.elapsedMicros, greaterThanOrEqualTo(d.beliefMicros));
      }
    },
  );

  test(
    'zero history ignores all past moves and uses exact current rank counts',
    () {
      final game = historyGame();
      final empty = WindowGameEngine.fromState(
        game.publicObservation(maxEvents: 0),
      );
      sameProposal(
        StatisticsPolicy.propose(
          game,
          historyLength: 0,
          fixedRounds: 3,
          scenarioSeed: 48271,
        ),
        StatisticsPolicy.propose(
          empty,
          historyLength: 0,
          fixedRounds: 3,
          scenarioSeed: 48271,
        ),
      );
      final snapshot = StatisticsPolicy.inspectBeliefs(game, historyLength: 0);
      expect(snapshot.diagnostics.historyFallback, isFalse);
      final counts = List<int>.filled(9, 4);
      for (final card
          in game
              .publicObservation()
              .cardGrid
              .expand((r) => r)
              .whereType<int>()) {
        counts[card ~/ 4]--;
      }
      final total = counts.reduce((a, b) => a + b);
      for (final distribution in snapshot.ranks.values) {
        expect(distribution, counts.map((n) => n / total).toList());
      }
    },
  );

  test('events older than the chosen 32-event window are irrelevant', () {
    final game = historyGame();
    final json = GameStateCodec.encode(game.exportState());
    final events = json['recentEvents'] as List;
    for (int i = 0; i < events.length - 32; i++) {
      (events[i] as Map)['outcome'] = 'discarded';
      (events[i] as Map)['boardBefore'] = List.generate(
        5,
        (_) => List<int?>.filled(6, null),
      );
    }
    final other = WindowGameEngine.fromState(GameStateCodec.decode(json));
    sameProposal(
      StatisticsPolicy.propose(
        game,
        historyLength: 32,
        fixedRounds: 3,
        scenarioSeed: 48271,
      ),
      StatisticsPolicy.propose(
        other,
        historyLength: 32,
        fixedRounds: 3,
        scenarioSeed: 48271,
      ),
    );
  });

  test('hidden permutations cannot affect any investigated game length', () {
    final game = historyGame();
    final json = GameStateCodec.encode(game.exportState());
    final grid = json['cardGrid'] as List<List<int?>>;
    final hidden = <int>[...json['deck'] as List<int>];
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        if (windowLayout[r][c] && !game.isFaceUp(Position(r, c))) {
          hidden.add(grid[r][c]!);
        }
      }
    }
    final shuffled = hidden.reversed.toList();
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        if (windowLayout[r][c] && !game.isFaceUp(Position(r, c))) {
          grid[r][c] = shuffled.removeLast();
        }
      }
    }
    json['deck'] = shuffled;
    final other = WindowGameEngine.fromState(GameStateCodec.decode(json));
    for (final length in [0, 4, 8, 16, 24, 32]) {
      sameProposal(
        StatisticsPolicy.propose(
          game,
          historyLength: length,
          fixedRounds: 3,
          scenarioSeed: 48271,
        ),
        StatisticsPolicy.propose(
          other,
          historyLength: length,
          fixedRounds: 3,
          scenarioSeed: 48271,
        ),
      );
    }
  });

  test('all thirty-three lengths return normalized public beliefs', () {
    final game = historyGame();
    for (int length = 0; length <= 32; length++) {
      final snapshot = StatisticsPolicy.inspectBeliefs(
        game,
        historyLength: length,
      );
      expect(snapshot.diagnostics.historyEvents, length);
      for (final distribution in snapshot.ranks.values) {
        expect(distribution.reduce((a, b) => a + b), closeTo(1, 1e-12));
        expect(distribution, everyElement(inInclusiveRange(0, 1)));
      }
    }
  });

  test('worker path retains explicit zero and 32-event settings', () async {
    final game = historyGame();
    for (final length in [0, 32]) {
      final result = await WindowRlPolicy.proposeStatistics(
        game,
        historyLength: length,
      );
      expect(result.statisticsDiagnostics!.historyLimit, length);
      expect(result.statisticsDiagnostics!.historyEvents, length);
      expect(
        WindowRlCodec.validActions(game).map((a) => a.index),
        contains(result.action.index),
      );
    }
  });
}
