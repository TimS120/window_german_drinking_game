// Headless history-length experiments; only the evaluator reads hidden truth.
// Cached standalone snapshots avoid the Flutter package graph.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../app/lib/game_engine.dart';
import '../../app/lib/policy_core.dart';

void play(WindowGameEngine game, PolicyAction action) {
  if (action.isPass) {
    game.endTurn();
    return;
  }
  final option = game
      .getValidOptionsForCard(action.position!)
      .firstWhere((o) => o.orientation == action.orientation);
  final result = game.applyGuess(action.position!, option, action.guess!);
  if (result.invalidReason != null) throw StateError(result.invalidReason!);
  if (result.requiresSameConfirmation) game.confirmSameGuess();
  if (result.requiresRemovalConfirmation) game.confirmRemovals();
}

PolicyAction opponent(WindowGameEngine game, int style, Random rng) {
  final risks = StatisticsPolicy.immediateMoveRisks(game);
  final certain = risks.where((r) => r.success == 1);
  if (certain.isNotEmpty) return certain.first.action;
  if (game.turnCanEnd && rng.nextDouble() < [0.45, 0.7, 0.95][style]) {
    return const PolicyAction.pass();
  }
  if (style == 0 && rng.nextDouble() < 0.6) {
    return risks[rng.nextInt(risks.length)].action;
  }
  risks.sort(
    (a, b) => style == 1
        ? b.success.compareTo(a.success)
        : ((1 - a.success) * a.penalty).compareTo((1 - b.success) * b.penalty),
  );
  return risks.first.action;
}

Map<String, Object> runGame(Map<String, dynamic> config) {
  final count = config['players'] as int;
  final seed = config['seed'] as int;
  final history = config['historyLength'] as int;
  final game = WindowGameEngine(List.generate(count, (i) => 'P$i'), seed: seed);
  final focal = seed % count;
  final rng = Random(seed + 100);
  int actions = 0, decisions = 0, micros = 0, beliefMicros = 0;
  int fallbacks = 0,
      searchFallbacks = 0,
      usedEvents = 0,
      availableEvents = 0,
      passes = 0;
  while (!game.gameEnded && actions < 30000) {
    PolicyAction action;
    if (game.currentPlayer == 'P$focal') {
      final timer = Stopwatch()..start();
      final proposal = StatisticsPolicy.propose(
        game,
        historyLength: history,
        fixedRounds: config['rounds'] as int,
        scenarioSeed: config['scenarioSeed'] as int?,
      );
      micros += timer.elapsedMicroseconds;
      final diagnostics = proposal.statisticsDiagnostics!;
      beliefMicros += diagnostics.beliefMicros;
      fallbacks += diagnostics.historyFallback ? 1 : 0;
      searchFallbacks += diagnostics.searchHistoryFallback ? 1 : 0;
      usedEvents += diagnostics.historyEvents;
      availableEvents += game.recentEvents.length;
      decisions++;
      action = proposal.action;
      if (action.isPass) passes++;
    } else {
      final seat = int.parse(game.currentPlayer.substring(1));
      action = opponent(game, (seat + seed ~/ count) % 3, rng);
    }
    play(game, action);
    actions++;
  }
  if (!game.gameEnded) throw StateError('Game exceeded 30000 actions: $config');
  return {
    'players': count,
    'seed': seed,
    'historyLength': history,
    'complete': true,
    'drinks': game.playerStats('P$focal').drinks,
    'actions': actions,
    'decisions': decisions,
    'micros': micros,
    'beliefMicros': beliefMicros,
    'fallbacks': fallbacks,
    'searchFallbacks': searchFallbacks,
    'usedEvents': usedEvents,
    'availableEvents': availableEvents,
    'passes': passes,
  };
}

List<Map<String, Object>> probe(Map<String, dynamic> config) {
  final rows = <Map<String, Object>>[];
  for (int count = 1; count <= 4; count++) {
    for (int deal = 0; deal < (config['probeDeals'] as int); deal++) {
      final seed = 23000 + count * 1000 + deal;
      final game = WindowGameEngine(
        List.generate(count, (i) => 'P$i'),
        seed: seed,
      );
      final rng = Random(seed + 97);
      int snapshots = 0;
      for (
        int step = 0;
        step < 300 && !game.gameEnded && snapshots < 8;
        step++
      ) {
        final risks = StatisticsPolicy.immediateMoveRisks(game);
        risks.sort(
          (a, b) => ((1 - a.success) * a.penalty).compareTo(
            (1 - b.success) * b.penalty,
          ),
        );
        final action = count > 1 && game.turnCanEnd && rng.nextDouble() < 0.75
            ? const PolicyAction.pass()
            : rng.nextDouble() < 0.2
            ? risks[rng.nextInt(risks.length)].action
            : risks.first.action;
        play(game, action);
        if (game.gameEnded || game.recentEvents.length < 32 || step % 8 != 7) {
          continue;
        }
        snapshots++;
        for (int history = 0; history <= 32; history++) {
          final beliefs = StatisticsPolicy.inspectBeliefs(
            game,
            historyLength: history,
          );
          double brier = 0, logLoss = 0;
          // Hidden truth is used only AFTER predictions, for evaluator scoring.
          // It is never passed to the adviser or used to choose these actions.
          for (final entry in beliefs.ranks.entries) {
            final actual = game.cardAt(entry.key)! ~/ 4;
            for (int rank = 0; rank < 9; rank++) {
              final error = entry.value[rank] - (rank == actual ? 1 : 0);
              brier += error * error;
            }
            logLoss -= log(max(1e-12, entry.value[actual]));
          }
          final d = beliefs.diagnostics;
          rows.add({
            'players': count,
            'trajectorySeed': seed,
            'step': step + 1,
            'historyLength': history,
            'cards': beliefs.ranks.length,
            'brierSum': brier,
            'logLossSum': logLoss,
            'historyEvents': d.historyEvents,
            'fallback': d.historyFallback,
            'beliefMicros': d.beliefMicros,
            'micros': d.elapsedMicros,
          });
        }
      }
    }
  }
  return rows;
}

void main(List<String> args) {
  final config = jsonDecode(args[1]) as Map<String, dynamic>;
  stdout.writeln(
    jsonEncode(args[0] == 'probe' ? probe(config) : runGame(config)),
  );
}
