/// Repeated, paired full-game comparisons using the authoritative rules engine.
library;

import 'dart:math' as math;

import 'game_engine.dart';
import 'policy_core.dart';

enum BenchmarkAgent { rl, statistics, casual, probability, cautious }

typedef BenchmarkDecision = Future<PolicyAction> Function(
  BenchmarkAgent agent,
  WindowGameEngine publicGame,
  math.Random opponentRandom,
);

class BenchmarkConfig {
  const BenchmarkConfig({
    this.deals = 30,
    this.seed = 20261013,
    this.maxActions = 100000,
    this.decisionTimeoutSeconds = 60,
    this.statisticsRounds = 12,
    this.bootstrapSamples = 2000,
    this.practicalDifference = 1,
    this.balanceSeatsAcrossDeals = true,
    this.opponentStyles = const ['varied'],
    this.scenarios = const ['solo', 'head-to-head', 'focal-3', 'focal-4'],
  });

  factory BenchmarkConfig.fromJson(
    Map<String, dynamic> value,
  ) => BenchmarkConfig(
    deals: value['deals'] as int? ?? 30,
    seed: value['seed'] as int? ?? 20261013,
    maxActions: value['maxActions'] as int? ?? 100000,
    decisionTimeoutSeconds: value['decisionTimeoutSeconds'] as int? ?? 60,
    statisticsRounds: value['statisticsRounds'] as int? ?? 12,
    bootstrapSamples: value['bootstrapSamples'] as int? ?? 2000,
    practicalDifference: (value['practicalDifference'] as num? ?? 1).toDouble(),
    // Older saved configurations replay every seat for each deal.
    balanceSeatsAcrossDeals: value['balanceSeatsAcrossDeals'] as bool? ?? false,
    opponentStyles:
        (value['opponentStyles'] as List?)?.cast<String>() ?? const ['varied'],
    scenarios:
        (value['scenarios'] as List?)?.cast<String>() ??
        const ['solo', 'head-to-head', 'focal-3', 'focal-4'],
  );

  final int deals, seed, maxActions, decisionTimeoutSeconds, statisticsRounds;
  final int bootstrapSamples;
  final bool balanceSeatsAcrossDeals;
  final double practicalDifference;
  final List<String> scenarios, opponentStyles;

  void validate() {
    if (deals < 1 ||
        seed < 0 ||
        seed > 0x7fffffff ||
        maxActions < 1 ||
        decisionTimeoutSeconds < 1 ||
        bootstrapSamples < 100 ||
        !practicalDifference.isFinite ||
        practicalDifference < 0 ||
        ![3, 6, 9, 12].contains(statisticsRounds) ||
        scenarios.isEmpty ||
        opponentStyles.isEmpty ||
        opponentStyles.toSet().length != opponentStyles.length ||
        opponentStyles.any(
          (s) => ![
            'rl',
            'statistics',
            'casual',
            'probability',
            'cautious',
            'mixed',
            'varied',
          ].contains(s),
        ) ||
        scenarios.toSet().length != scenarios.length ||
        scenarios.any(
          (s) => ![
            'solo',
            'head-to-head',
            'focal-2',
            'focal-3',
            'focal-4',
          ].contains(s),
        )) {
      throw ArgumentError('Invalid benchmark configuration');
    }
  }

  Map<String, dynamic> toJson() => {
    'deals': deals,
    'balanceSeatsAcrossDeals': balanceSeatsAcrossDeals,
    'seed': seed,
    'maxActions': maxActions,
    'decisionTimeoutSeconds': decisionTimeoutSeconds,
    'statisticsRounds': statisticsRounds,
    'bootstrapSamples': bootstrapSamples,
    'practicalDifference': practicalDifference,
    'scenarios': scenarios,
    'opponentStyles': opponentStyles,
  };
}

class BenchmarkScenario {
  const BenchmarkScenario(
    this.name,
    this.players,
    this.opponents, {
    this.headToHead = false,
    this.variedOpponents = false,
  });
  final String name;
  final int players;
  final List<BenchmarkAgent> opponents;
  final bool headToHead, variedOpponents;
}

List<BenchmarkScenario> benchmarkScenarios(BenchmarkConfig config) {
  final result = <BenchmarkScenario>[];
  if (config.scenarios.contains('solo')) {
    result.add(const BenchmarkScenario('solo', 1, []));
  }
  if (config.scenarios.contains('head-to-head')) {
    result.add(
      const BenchmarkScenario('head-to-head', 2, [], headToHead: true),
    );
  }
  for (int n = 2; n <= 4; n++) {
    if (!config.scenarios.contains('focal-$n')) continue;
    if (config.opponentStyles.contains('varied')) {
      result.add(
        BenchmarkScenario(
          '$n players / varied opponents',
          n,
          [],
          variedOpponents: true,
        ),
      );
    }
    for (final opponent in BenchmarkAgent.values) {
      if (!config.opponentStyles.contains(opponent.name)) continue;
      result.add(
        BenchmarkScenario(
          '$n players / ${opponent.name} opponents',
          n,
          List.filled(n - 1, opponent),
        ),
      );
    }
    // A two-player table cannot contain a mixture of opponent methods.
    if (n > 2 && config.opponentStyles.contains('mixed')) {
      result.add(
        BenchmarkScenario(
          '$n players / mixed RL+statistics opponents',
          n,
          List.generate(
            n - 1,
            (i) => i.isEven ? BenchmarkAgent.rl : BenchmarkAgent.statistics,
          ),
        ),
      );
    }
  }
  return result;
}

const int maximumBenchmarkGames = 250;

List<List<BenchmarkAgent>> _opponentCombinations(int players, int seed) {
  final combinations = <List<BenchmarkAgent>>[];
  void choose(List<BenchmarkAgent> chosen, int start) {
    if (chosen.length == players - 1) {
      combinations.add(List.of(chosen));
      return;
    }
    for (int i = start; i < BenchmarkAgent.values.length; i++) {
      choose([...chosen, BenchmarkAgent.values[i]], i + 1);
    }
  }

  choose([], 0);
  combinations.shuffle(math.Random(seed ^ (players * 1009)));
  return combinations;
}

List<BenchmarkAgent> benchmarkOpponents(
  BenchmarkConfig config,
  BenchmarkScenario scenario,
  int deal,
) {
  if (!scenario.variedOpponents) return scenario.opponents;
  final combinations = _opponentCombinations(scenario.players, config.seed);
  final group = combinations[deal % combinations.length];
  final rotation = (deal ~/ combinations.length) % group.length;
  return List.generate(
    group.length,
    (i) => group[(i + rotation) % group.length],
  );
}

List<int> benchmarkSeats(
  BenchmarkConfig config,
  BenchmarkScenario scenario,
  int deal,
) {
  if (scenario.headToHead || !config.balanceSeatsAcrossDeals) {
    return List.generate(scenario.players, (i) => i);
  }
  if (scenario.variedOpponents) {
    final width = _opponentCombinations(scenario.players, config.seed).length;
    return [((deal % width) + deal ~/ width) % scenario.players];
  }
  return [deal % scenario.players];
}

int benchmarkGamesPerDeal(BenchmarkConfig config, BenchmarkScenario scenario) =>
    scenario.headToHead
    ? 2
    : config.balanceSeatsAcrossDeals
    ? 2
    : 2 * scenario.players;

int benchmarkGameCount(BenchmarkConfig config) => benchmarkScenarios(
  config,
).fold<int>(0, (n, s) => n + config.deals * benchmarkGamesPerDeal(config, s));

class BenchmarkGame {
  BenchmarkGame({
    required this.scenario,
    required this.deal,
    required this.seat,
    required this.method,
    required this.agents,
    required this.drinks,
    required this.guesses,
    required this.passes,
    required this.actions,
    required this.latencyMicros,
    required this.decisions,
  });
  factory BenchmarkGame.fromJson(Map<String, dynamic> value) {
    if (value['completed'] != true) {
      throw ArgumentError('Unfinished game cannot be scored');
    }
    return BenchmarkGame(
      scenario: value['scenario'] as String,
      deal: value['deal'] as int,
      seat: value['seat'] as int,
      method: value['method'] as String,
      agents: (value['agents'] as List)
          .map((a) => BenchmarkAgent.values.byName(a as String))
          .toList(),
      drinks: (value['drinks'] as List).cast<int>(),
      guesses: (value['guesses'] as List).cast<int>(),
      passes: (value['passes'] as List).cast<int>(),
      actions: value['actions'] as int,
      latencyMicros: (value['latencyMicros'] as Map).cast<String, int>(),
      decisions: (value['decisions'] as Map).cast<String, int>(),
    );
  }
  final String scenario, method;
  final int deal, seat, actions;
  final List<BenchmarkAgent> agents;
  final List<int> drinks, guesses, passes;
  final Map<String, int> latencyMicros, decisions;

  Map<String, dynamic> toJson() => {
    'scenario': scenario,
    'deal': deal,
    'seat': seat,
    'method': method,
    'agents': agents.map((a) => a.name).toList(),
    'completed': true,
    'drinks': drinks,
    'guesses': guesses,
    'passes': passes,
    'actions': actions,
    'latencyMicros': latencyMicros,
    'decisions': decisions,
  };
}

class BenchmarkFailure implements Exception {
  BenchmarkFailure(this.context, this.cause);
  final String context;
  final Object cause;
  @override
  String toString() => '$context: $cause';
}

class BenchmarkRunner {
  BenchmarkRunner(this.config, this.decide, {this.onGame});
  final BenchmarkConfig config;
  final BenchmarkDecision decide;
  final void Function(BenchmarkGame game)? onGame;
  final List<BenchmarkGame> games = [];
  String currentContext = 'initialization';
  Map<String, dynamic>? progress;

  Future<List<BenchmarkGame>> run({
    String? scenarioName,
    int? dealIndex,
  }) async {
    config.validate();
    if (benchmarkScenarios(config).isEmpty) {
      throw ArgumentError('No scenarios match this opponent selection');
    }
    if (dealIndex != null && (dealIndex < 0 || dealIndex >= config.deals)) {
      throw ArgumentError('Deal index is outside the configured suite');
    }
    final selected = benchmarkScenarios(config)
        .where((s) => scenarioName == null || s.name == scenarioName)
        .toList();
    if (selected.isEmpty) {
      throw ArgumentError('Unknown scenario: $scenarioName');
    }
    final planned = selected.fold<int>(
      0,
      (n, s) =>
          n +
          (dealIndex == null ? config.deals : 1) *
              benchmarkGamesPerDeal(config, s),
    );
    if (planned > maximumBenchmarkGames) {
      throw ArgumentError(
        'Selected comparison needs $planned games; maximum is $maximumBenchmarkGames',
      );
    }
    for (final scenario in selected) {
      for (
        int deal = dealIndex ?? 0;
        deal < (dealIndex == null ? config.deals : dealIndex + 1);
        deal++
      ) {
        // Recreate this exact initial physical deal for every seat/method run.
        final dealSeed = (config.seed + deal * 104729) & 0x7fffffff;
        final initial = WindowGameEngine(
          List.generate(scenario.players, (i) => 'Seat ${i + 1}'),
          seed: dealSeed,
        ).exportState();
        final opponents = benchmarkOpponents(config, scenario, deal);
        for (final seat in benchmarkSeats(config, scenario, deal)) {
          final methods = scenario.headToHead
              ? [BenchmarkAgent.rl]
              : [BenchmarkAgent.rl, BenchmarkAgent.statistics];
          // Alternate evaluation order without changing opponent RNG streams.
          final ordered = (deal + seat).isEven ? methods : methods.reversed;
          for (final method in ordered) {
            final agents = <BenchmarkAgent>[];
            int opponentIndex = 0;
            for (int i = 0; i < scenario.players; i++) {
              agents.add(
                i == seat
                    ? method
                    : scenario.headToHead
                    ? BenchmarkAgent.statistics
                    : opponents[opponentIndex++],
              );
            }
            currentContext =
                '${scenario.name}, deal $deal, seat ${seat + 1}, ${method.name}';
            try {
              final game = await play(
                initial,
                agents,
                scenario: scenario.name,
                deal: deal,
                seat: seat,
                method: method.name,
                shuffleSeed: (dealSeed ^ 0x35a61c47) & 0x7fffffff,
                opponentSeed: (dealSeed ^ 0x71b9423 ^ seat * 8191) & 0x7fffffff,
              );
              games.add(game);
              onGame?.call(game);
            } catch (error) {
              throw BenchmarkFailure(currentContext, error);
            }
          }
        }
      }
    }
    return games;
  }

  Future<BenchmarkGame> play(
    GameState initial,
    List<BenchmarkAgent> agents, {
    required String scenario,
    required int deal,
    required int seat,
    required String method,
    required int shuffleSeed,
    required int opponentSeed,
  }) async {
    final game = WindowGameEngine.fromState(initial, seed: shuffleSeed);
    final randoms = List.generate(
      agents.length,
      (i) => math.Random(opponentSeed + i * 997),
    );
    final guesses = List.filled(agents.length, 0);
    final passes = List.filled(agents.length, 0);
    final latency = <String, int>{};
    final decisions = <String, int>{};
    int actions = 0;
    while (!game.gameEnded) {
      if (actions >= config.maxActions) {
        throw StateError(
          'Game did not finish after ${config.maxActions} actions. '
          'No truncated result is scored; increase --max-actions or investigate this policy.',
        );
      }
      final actor = game.players.indexOf(game.currentPlayer);
      progress = {
        'scenario': scenario,
        'deal': deal,
        'focalSeat': seat,
        'method': method,
        'actions': actions,
        'actingSeat': actor,
        'actingAgent': agents[actor].name,
        'drinksSoFar': [
          for (final name in game.players)
            game.publicObservation().stats[name]!.drinks,
        ],
      };
      // The callback cannot see actual hidden identities, deck or engine RNG.
      final publicGame = WindowGameEngine.fromState(
        game.publicObservation(maxEvents: maxPublicHistoryEvents),
        seed: 0,
      );
      final timer = Stopwatch()..start();
      final action = await decide(
        agents[actor],
        publicGame,
        randoms[actor],
      ).timeout(Duration(seconds: config.decisionTimeoutSeconds));
      timer.stop();
      final key = agents[actor].name;
      latency[key] = (latency[key] ?? 0) + timer.elapsedMicroseconds;
      decisions[key] = (decisions[key] ?? 0) + 1;
      if (!WindowRlCodec.validActions(publicGame)
          .any((a) => a.index == action.index)) {
        throw StateError(
          '${agents[actor].name} suggested an illegal action ${action.index}',
        );
      }
      if (action.isPass) {
        game.endTurn();
        passes[actor]++;
      } else {
        final option = game
            .getValidOptionsForCard(action.position!)
            .firstWhere((o) => o.orientation == action.orientation);
        final result = game.applyGuess(action.position!, option, action.guess!);
        if (result.invalidReason != null) {
          throw StateError(result.invalidReason!);
        }
        if (result.requiresSameConfirmation) game.confirmSameGuess();
        if (result.requiresRemovalConfirmation) game.confirmRemovals();
        guesses[actor]++;
      }
      actions++;
    }
    final finalState = game.publicObservation();
    return BenchmarkGame(
      scenario: scenario,
      deal: deal,
      seat: seat,
      method: method,
      agents: agents,
      drinks: [for (final name in game.players) finalState.stats[name]!.drinks],
      guesses: guesses,
      passes: passes,
      actions: actions,
      latencyMicros: latency,
      decisions: decisions,
    );
  }
}

/// Independent baseline opponents; these are proxies, not fitted human models.
PolicyAction benchmarkOpponent(
  BenchmarkAgent agent,
  WindowGameEngine publicGame,
  math.Random random,
) {
  final risks = StatisticsPolicy.immediateMoveRisks(publicGame);
  if (risks.isEmpty) throw StateError('No legal guesses for opponent');
  risks.sort((a, b) {
    final ar = (1 - a.success) * a.penalty;
    final br = (1 - b.success) * b.penalty;
    final comparison = ar.compareTo(br);
    return comparison != 0
        ? comparison
        : a.action.index.compareTo(b.action.index);
  });
  final certain = risks.where((r) => r.success == 1);
  if (certain.isNotEmpty) return certain.first.action;
  final passChance = switch (agent) {
    BenchmarkAgent.casual => 0.45,
    BenchmarkAgent.probability => 0.70,
    BenchmarkAgent.cautious => 0.95,
    _ => throw ArgumentError('An adviser is not a baseline opponent'),
  };
  if (publicGame.canEndTurn && random.nextDouble() < passChance) {
    return const PolicyAction.pass();
  }
  if (agent == BenchmarkAgent.casual && random.nextDouble() < 0.6) {
    return risks[random.nextInt(risks.length)].action;
  }
  if (agent == BenchmarkAgent.probability) {
    risks.sort((a, b) {
      final comparison = b.success.compareTo(a.success);
      return comparison != 0
          ? comparison
          : a.action.index.compareTo(b.action.index);
    });
  }
  return risks.first.action;
}

double _mean(List<num> values) =>
    values.fold<double>(0, (a, b) => a + b) / values.length;

double _percentile(List<num> values, double fraction) {
  final ordered = List<num>.from(values)..sort((a, b) => a.compareTo(b));
  final index = (ordered.length - 1) * fraction;
  final low = index.floor(), high = index.ceil();
  return ordered[low] + (ordered[high] - ordered[low]) * (index - low);
}

Map<String, dynamic> summarizeBenchmark(
  BenchmarkConfig config,
  List<BenchmarkGame> games,
) {
  final rows = <Map<String, dynamic>>[];
  for (final scenario in benchmarkScenarios(config)) {
    final selected = games.where((g) => g.scenario == scenario.name).toList();
    final rl = <int>[],
        statistics = <int>[],
        rlGuesses = <int>[],
        statisticsGuesses = <int>[];
    final rlPasses = <int>[], statisticsPasses = <int>[];
    final blocks = <double>[];
    int winsRl = 0, winsStatistics = 0, ties = 0;
    for (int deal = 0; deal < config.deals; deal++) {
      final differences = <double>[];
      for (final seat in benchmarkSeats(config, scenario, deal)) {
        final matches = selected
            .where((g) => g.deal == deal && g.seat == seat)
            .toList();
        final r = matches.singleWhere((g) => g.method == 'rl');
        final s = scenario.headToHead
            ? r
            : matches.singleWhere((g) => g.method == 'statistics');
        final rs = seat, ss = scenario.headToHead ? 1 - seat : seat;
        final rd = r.drinks[rs], sd = s.drinks[ss];
        rl.add(rd);
        statistics.add(sd);
        rlGuesses.add(r.guesses[rs]);
        statisticsGuesses.add(s.guesses[ss]);
        rlPasses.add(r.passes[rs]);
        statisticsPasses.add(s.passes[ss]);
        differences.add((rd - sd).toDouble());
        if (rd < sd) {
          winsRl++;
        } else if (rd > sd) {
          winsStatistics++;
        } else {
          ties++;
        }
      }
      blocks.add(_mean(differences));
    }
    // Resample initial-deal blocks, retaining all related seat rotations/pairs.
    final random = math.Random(config.seed ^ 0x567812);
    final bootstraps = List.generate(
      config.bootstrapSamples,
      (_) => _mean(
        List.generate(
          blocks.length,
          (_) => blocks[random.nextInt(blocks.length)],
        ),
      ),
    );
    final interval = config.deals < 2
        ? null
        : [_percentile(bootstraps, 0.025), _percentile(bootstraps, 0.975)];
    final difference = _mean(blocks);
    final verdict = config.deals < 30
        ? 'pilot only'
        : interval![1] < 0
        ? 'RL'
        : interval[0] > 0
        ? 'statistics'
        : 'inconclusive';
    final practical = config.deals < 30
        ? 'pilot only'
        : interval![1] < -config.practicalDifference
        ? 'RL'
        : interval[0] > config.practicalDifference
        ? 'statistics'
        : 'not established';
    rows.add({
      'scenario': scenario.name,
      'players': scenario.players,
      'independentDeals': config.deals,
      'pairedSeatComparisons': rl.length,
      'rlMeanDrinks': _mean(rl),
      'statisticsMeanDrinks': _mean(statistics),
      'rlMedianDrinks': _percentile(rl, 0.5),
      'statisticsMedianDrinks': _percentile(statistics, 0.5),
      'rlP95Drinks': _percentile(rl, 0.95),
      'statisticsP95Drinks': _percentile(statistics, 0.95),
      'difference': difference,
      'difference95Interval': interval,
      'lowerMeanSupported': verdict,
      'practicalAdvantageSupported': practical,
      'rlMeanGuesses': _mean(rlGuesses),
      'statisticsMeanGuesses': _mean(statisticsGuesses),
      'rlMeanPasses': _mean(rlPasses),
      'statisticsMeanPasses': _mean(statisticsPasses),
      'rlFewerDrinksFrequency': winsRl / rl.length,
      'statisticsFewerDrinksFrequency': winsStatistics / rl.length,
      'tieFrequency': ties / rl.length,
      'meanGameActions': _mean(selected.map((g) => g.actions).toList()),
    });
  }
  final latencies = <String, double>{};
  for (final agent in [BenchmarkAgent.rl, BenchmarkAgent.statistics]) {
    final count = games.fold<int>(
      0,
      (n, g) => n + (g.decisions[agent.name] ?? 0),
    );
    final micros = games.fold<int>(
      0,
      (n, g) => n + (g.latencyMicros[agent.name] ?? 0),
    );
    if (count > 0) latencies[agent.name] = micros / count / 1000;
  }
  return {
    'status': 'complete',
    'completedGames': games.length,
    'failedGames': 0,
    'completionRate': 1,
    'config': config.toJson(),
    'rows': rows,
    'meanDecisionMilliseconds': latencies,
  };
}

String benchmarkReport(Map<String, dynamic> summary) {
  if (summary['status'] != 'complete') {
    return '# Adviser comparison — FAILED\n\nNo winner: the benchmark did not complete.\n\n'
        'Completed games retained in games.jsonl: ${summary['completedGames'] ?? 0}.\n\n'
        'Error: ${summary['error']}\n';
  }
  String f(num value) => value.toStringAsFixed(2);
  final config = summary['config'] as Map<String, dynamic>;
  final rows = (summary['rows'] as List).cast<Map<String, dynamic>>();
  final buffer = StringBuffer('# Adviser comparison\n\n')
    ..writeln(
      '${summary['completedGames']} games completed; no unfinished games scored. '
      '${config['deals']} independent deals per scenario; seed ${config['seed']}.',
    )
    ..writeln(
      '\nScore: mean personal drinks through completion. Δ = RL − statistics; negative favors RL.',
    )
    ..writeln(
      '\n| Scenario | RL drinks | Statistics drinks | Δ [95% interval] | Lower mean supported |',
    )
    ..writeln('|---|---:|---:|---|---|');
  for (final row in rows) {
    final interval = row['difference95Interval'] as List?;
    final ci = interval == null
        ? 'unavailable'
        : '${f(interval[0] as num)}, ${f(interval[1] as num)}';
    buffer.writeln(
      '| ${row['scenario']} | ${f(row['rlMeanDrinks'] as num)} | '
      '${f(row['statisticsMeanDrinks'] as num)} | ${f(row['difference'] as num)} [$ci] | ${row['lowerMeanSupported']} |',
    );
  }
  if (summary['elapsedSeconds'] is num) {
    buffer.writeln(
      '\nElapsed: ${f((summary['elapsedSeconds'] as num) / 60)} minutes.',
    );
  }
  final provenance = summary['provenance'] as Map<String, dynamic>?;
  final hashes = provenance?['sha256'] as Map<String, dynamic>?;
  final modelHash = hashes?['app/assets/models/window_policy.onnx'] as String?;
  if (modelHash != null) {
    buffer.writeln(
      'Model SHA-256: ${modelHash.substring(0, 16)}…; '
      'source commit: ${provenance?['gitCommit']}. Exact fingerprints are in summary.json.',
    );
  }
  buffer.writeln(
    '\nFocal seats rotate across deals; head-to-head includes both starting-seat assignments.'
    ' Varied opponents include RL, statistics, casual, probability-aware and cautious styles.'
    ' Seats and starting exposure are balanced across the sample. Confidence intervals resample whole initial-deal blocks. '
    'Intervals are per scenario, without correction for multiple comparisons; investigate consistent patterns. '
    'Fewer than 30 deals is labeled pilot only; 30 deals does not guarantee adequate precision.',
  );
  buffer.writeln(
    '\nPractical improvement threshold: ${config['practicalDifference']} drink(s) per player per game.',
  );
  final practicalRows = rows.where(
    (r) => ['RL', 'statistics'].contains(r['practicalAdvantageSupported']),
  );
  if (practicalRows.isEmpty) {
    buffer.writeln(
      'No scenario establishes an advantage beyond that threshold.',
    );
  } else {
    for (final row in practicalRows) {
      buffer.writeln(
        '- ${row['scenario']}: ${row['practicalAdvantageSupported']} exceeds the threshold.',
      );
    }
  }
  final execution = summary['execution'] as Map<String, dynamic>?;
  if (execution != null) {
    buffer.writeln(
      '\nExecution: ${execution['backend']}; ${execution['workers']} parallel workers. '
      'The rules and statistical search are shared with the app, with no Flutter UI or inference channels.',
    );
  }
  final latency = summary['meanDecisionMilliseconds'] as Map<String, dynamic>;
  buffer.writeln(
    '\nMean adviser latency (all seats): ${latency.entries.map((e) => '${e.key} ${f(e.value as num)} ms').join('; ')}. '
    'Statistics uses ${config['statisticsRounds']} fixed paired rounds (app default uses a time budget).',
  );
  buffer.writeln(
    '\nBaseline opponents are approximate casual/probability/cautious policies, not measured human behavior. '
    'Focal tests replace only the evaluated player; head-to-head compares both methods within the same game. '
    'There is no weighted overall winner across different table setups.',
  );
  buffer.writeln(
    '\nsummary.json also contains medians, 95th percentiles, guesses, passes, pairwise win/tie frequencies, '
    'game duration, and source fingerprints. games.jsonl contains every completed game.',
  );
  return buffer.toString();
}
