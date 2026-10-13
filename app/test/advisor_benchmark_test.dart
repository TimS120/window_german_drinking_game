import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/advisor_benchmark.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/rl_policy.dart';

GameState finishingSameState() {
  final original = WindowGameEngine(['A', 'B'], seed: 5).exportState();
  const target = Position(2, 4);
  final wantedRank = original.cardGrid[2][5]! ~/ 4;
  final old = original.cardGrid[2][4]!;
  if (old ~/ 4 != wantedRank) {
    bool found = false;
    for (int r = 0; r < 5 && !found; r++) {
      for (int c = 0; c < 6 && !found; c++) {
        final card = original.cardGrid[r][c];
        if (Position(r, c) != handlePosition &&
            card != null &&
            card ~/ 4 == wantedRank) {
          original.cardGrid[2][4] = card;
          original.cardGrid[r][c] = old;
          found = true;
        }
      }
    }
    if (!found) {
      final index = original.deck.indexWhere((card) => card ~/ 4 == wantedRank);
      original.cardGrid[2][4] = original.deck[index];
      original.deck[index] = old;
    }
  }
  for (int r = 0; r < 5; r++) {
    for (int c = 0; c < 6; c++) {
      original.faceUp[r][c] =
          windowLayout[r][c] &&
          ![
            target,
            const Position(2, 3),
            const Position(1, 4),
            const Position(3, 4),
          ].contains(Position(r, c));
    }
  }
  // The handle rule permits a single-neighbor comparison despite other boundaries.
  return GameState(
    players: original.players,
    currentPlayerIndex: 0,
    turnStartFaceUp: 20,
    deck: original.deck,
    cardGrid: original.cardGrid,
    faceUp: original.faceUp,
    pendingRemovals: {},
    pendingPenalty: 0,
    mustSelectAdjacentToHandle: true,
    turnCanEnd: false,
    stats: original.stats,
  );
}

void main() {
  test('JSON configuration retains filters and search settings', () {
    final config = BenchmarkConfig.fromJson({
      'deals': 1,
      'scenarios': ['focal-3'],
      'opponentStyles': ['cautious'],
      'statisticsRounds': 3,
    });
    config.validate();
    expect(
      benchmarkScenarios(config).single.name,
      '3 players / cautious opponents',
    );
    expect(config.toJson()['statisticsRounds'], 3);
    expect(config.toJson()['opponentStyles'], ['cautious']);
  });

  test('default suite contains 240 games across all player counts', () {
    const config = BenchmarkConfig();
    final scenarios = benchmarkScenarios(config);
    expect(config.deals, 30);
    expect(scenarios.map((s) => s.players), [1, 2, 3, 4]);
    expect(scenarios.length, 4);
    expect(benchmarkGameCount(config), 240);
    for (final scenario in scenarios) {
      expect(config.deals * benchmarkGamesPerDeal(config, scenario), 60);
      final seats = List<int>.filled(scenario.players, 0);
      final opponentCounts = {
        for (final agent in BenchmarkAgent.values) agent: 0,
      };
      for (int deal = 0; deal < config.deals; deal++) {
        for (final seat in benchmarkSeats(config, scenario, deal)) {
          seats[seat]++;
        }
        if (scenario.variedOpponents) {
          final opponents = benchmarkOpponents(config, scenario, deal);
          expect(opponents.length, scenario.players - 1);
          for (final opponent in opponents) {
            opponentCounts[opponent] = opponentCounts[opponent]! + 1;
          }
        }
      }
      expect(
        seats.reduce(math.max) - seats.reduce(math.min),
        lessThanOrEqualTo(1),
      );
      if (scenario.variedOpponents) {
        expect(opponentCounts.values.toSet().length, 1);
      }
    }
  });

  test(
    'full run refuses more than 250 games before any adviser call',
    () async {
      int decisions = 0;
      final runner = BenchmarkRunner(const BenchmarkConfig(deals: 32), (
        agent,
        game,
        random,
      ) async {
        decisions++;
        return const PolicyAction.pass();
      });
      await expectLater(runner.run(), throwsArgumentError);
      expect(decisions, 0);
      expect(runner.games, isEmpty);
    },
  );

  test('rotating focal seats are paired and scored correctly', () {
    const config = BenchmarkConfig(scenarios: ['focal-3']);
    final scenario = benchmarkScenarios(config).single;
    final games = <BenchmarkGame>[];
    for (int deal = 0; deal < config.deals; deal++) {
      final seat = benchmarkSeats(config, scenario, deal).single;
      for (final method in ['rl', 'statistics']) {
        games.add(
          BenchmarkGame(
            scenario: scenario.name,
            deal: deal,
            seat: seat,
            method: method,
            agents: List.filled(3, BenchmarkAgent.casual),
            drinks: List.generate(
              3,
              (i) => i == seat ? (method == 'rl' ? 2 : 5) : 20,
            ),
            guesses: [1, 1, 1],
            passes: [0, 0, 0],
            actions: 3,
            latencyMicros: {},
            decisions: {},
          ),
        );
      }
    }
    final row =
        (summarizeBenchmark(config, games)['rows'] as List).single as Map;
    expect(row['independentDeals'], 30);
    expect(row['pairedSeatComparisons'], 30);
    expect(row['rlMeanDrinks'], 2);
    expect(row['statisticsMeanDrinks'], 5);
    expect(row['difference95Interval'], [-3, -3]);
  });

  test('benchmark callback has no hidden cards and includes opponents same penalties', () async {
    final initial = finishingSameState();
    final runner = BenchmarkRunner(const BenchmarkConfig(), (
      agent,
      game,
      random,
    ) async {
      final public = game.exportState();
      expect(public.deck, isEmpty);
      for (int r = 0; r < 5; r++) {
        for (int c = 0; c < 6; c++) {
          if (!public.faceUp[r][c]) expect(public.cardGrid[r][c], isNull);
        }
      }
      if (game.mustSelectAdjacentToHandle) {
        return const PolicyAction.guess(
          position: Position(2, 4),
          orientation: Orientation.horizontal,
          guess: GuessType.same,
        );
      }
      // Fixture-only scripted correct continuation; never used in a benchmark.
      return WindowRlCodec.validActions(
        game,
      ).where((a) => !a.isPass).firstWhere((action) {
        final option = game
            .getValidOptionsForCard(action.position!)
            .firstWhere((o) => o.orientation == action.orientation);
        final rank =
            initial.cardGrid[action.position!.row][action.position!.column]! ~/
            4;
        final first = game.cardAt(option.neighbors.first)! ~/ 4;
        final last = game.cardAt(option.neighbors.last)! ~/ 4;
        return switch (action.guess!) {
          GuessType.higher => rank > first,
          GuessType.same => rank == first,
          GuessType.lower => rank < first,
          GuessType.inBetween =>
            rank >= math.min(first, last) && rank <= math.max(first, last),
          GuessType.outside =>
            rank < math.min(first, last) || rank > math.max(first, last),
        };
      });
    });
    final result = await runner.play(
      initial,
      [BenchmarkAgent.rl, BenchmarkAgent.statistics],
      scenario: 'test',
      deal: 0,
      seat: 0,
      method: 'rl',
      shuffleSeed: 4,
      opponentSeed: 6,
    );
    expect(result.drinks[0], 0);
    expect(result.drinks[1], greaterThanOrEqualTo(1));
    expect(result.actions, 4);
    expect(result.guesses, [4, 0]);
    expect(result.toJson()['completed'], isTrue);
  });

  test(
    'action guard rejects an unfinished game and retains no scored result',
    () async {
      final runner = BenchmarkRunner(
        const BenchmarkConfig(deals: 1, maxActions: 1, scenarios: ['solo']),
        (agent, game, random) async => WindowRlCodec.validActions(game).first,
      );
      await expectLater(runner.run(), throwsA(isA<BenchmarkFailure>()));
      expect(runner.games, isEmpty);
      expect(runner.currentContext, contains('solo, deal 0, seat 1'));
    },
  );

  test(
    'illegal suggestion fails rather than passing or substituting a method',
    () async {
      final runner = BenchmarkRunner(
        const BenchmarkConfig(deals: 1, scenarios: ['solo']),
        (agent, game, random) async => const PolicyAction.pass(),
      );
      await expectLater(runner.run(), throwsA(isA<BenchmarkFailure>()));
      expect(runner.games, isEmpty);
    },
  );

  test(
    'paired head-to-head summary respects seats and clusters deal rotations',
    () {
      const config = BenchmarkConfig(deals: 30, scenarios: ['head-to-head']);
      final games = <BenchmarkGame>[];
      for (int deal = 0; deal < config.deals; deal++) {
        for (int seat = 0; seat < 2; seat++) {
          games.add(
            BenchmarkGame(
              scenario: 'head-to-head',
              deal: deal,
              seat: seat,
              method: 'rl',
              agents: seat == 0
                  ? [BenchmarkAgent.rl, BenchmarkAgent.statistics]
                  : [BenchmarkAgent.statistics, BenchmarkAgent.rl],
              drinks: seat == 0 ? [2, 5] : [5, 2],
              guesses: [7, 7],
              passes: [3, 3],
              actions: 20,
              latencyMicros: {'rl': 2000, 'statistics': 3000},
              decisions: {'rl': 2, 'statistics': 3},
            ),
          );
        }
      }
      final summary = summarizeBenchmark(config, games);
      final row = (summary['rows'] as List).single as Map<String, dynamic>;
      expect(row['rlMeanDrinks'], 2);
      expect(row['statisticsMeanDrinks'], 5);
      expect(row['difference95Interval'], [-3, -3]);
      expect(row['lowerMeanSupported'], 'RL');
      expect(row['practicalAdvantageSupported'], 'RL');
      expect(row['pairedSeatComparisons'], 60);
      expect(row['independentDeals'], 30);
      expect(row['rlFewerDrinksFrequency'], 1);
      expect(summary['meanDecisionMilliseconds'], {
        'rl': 1.0,
        'statistics': 1.0,
      });
      expect(benchmarkReport(summary), contains('negative favors RL'));
    },
  );

  test('one-deal report cannot claim a winner or an uncertainty interval', () {
    const config = BenchmarkConfig(deals: 1, scenarios: ['solo']);
    final games = [
      for (final method in ['rl', 'statistics'])
        BenchmarkGame(
          scenario: 'solo',
          deal: 0,
          seat: 0,
          method: method,
          agents: [
            method == 'rl' ? BenchmarkAgent.rl : BenchmarkAgent.statistics,
          ],
          drinks: [method == 'rl' ? 0 : 100],
          guesses: [10],
          passes: [0],
          actions: 10,
          latencyMicros: {},
          decisions: {},
        ),
    ];
    final row =
        (summarizeBenchmark(config, games)['rows'] as List).single as Map;
    expect(row['lowerMeanSupported'], 'pilot only');
    expect(row['difference95Interval'], isNull);
    expect(
      benchmarkReport({
        'status': 'failed',
        'error': 'stalled',
        'completedGames': 2,
      }),
      contains('No winner'),
    );
  });

  test('baseline opponents do not depend on actual hidden identities', () {
    final game = WindowGameEngine(['A', 'B'], seed: 5);
    final hidden = game.exportState();
    final concealed = <Position>[];
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        if (windowLayout[r][c] && !hidden.faceUp[r][c]) {
          concealed.add(Position(r, c));
        }
      }
    }
    final first = concealed.first, last = concealed.last;
    final old = hidden.cardGrid[first.row][first.column];
    hidden.cardGrid[first.row][first.column] =
        hidden.cardGrid[last.row][last.column];
    hidden.cardGrid[last.row][last.column] = old;
    final other = WindowGameEngine.fromState(hidden);
    for (final agent in [
      BenchmarkAgent.casual,
      BenchmarkAgent.probability,
      BenchmarkAgent.cautious,
    ]) {
      expect(
        benchmarkOpponent(agent, game, math.Random(4)).index,
        benchmarkOpponent(agent, other, math.Random(4)).index,
      );
    }
  });
}
