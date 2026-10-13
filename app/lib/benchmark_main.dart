/// Dedicated native entry point. The Python launcher always isolates its display.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'advisor_benchmark.dart';
import 'game_engine.dart';
import 'rl_policy.dart';

AiMoveProposal _statistics(({GameState state, int rounds}) request) =>
    WindowRlPolicy.statisticsProposal(
      WindowGameEngine.fromState(request.state),
      fixedRounds: request.rounds,
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['WINDOW_BENCHMARK_CONFIG'];
  if (path == null) {
    stderr.writeln(
      'Launch this entry point through tools/compare_advisers.py.',
    );
    exit(2);
  }
  final raw = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final directory = Directory(raw['outputDirectory'] as String)
    ..createSync(recursive: true);
  final config = BenchmarkConfig.fromJson(raw);
  final provenance = raw['provenance'];
  final started = DateTime.now().toUtc();
  final clock = Stopwatch()..start();
  final records = File('${directory.path}/games.jsonl')
      .openSync(mode: FileMode.write);
  BenchmarkRunner? runner;
  int code = 0;
  Map<String, dynamic> summary;
  try {
    config.validate();
    final policy = WindowRlPolicy();
    await policy.preload().timeout(
      Duration(seconds: config.decisionTimeoutSeconds),
    );
    if (policy.availability != PolicyAvailability.ready) {
      throw StateError(
        'Trained RL policy unavailable: ${policy.availabilityMessage}',
      );
    }
    runner = BenchmarkRunner(
      config,
      (agent, publicGame, opponentRandom) async {
        switch (agent) {
          case BenchmarkAgent.rl:
            final proposal = await policy.propose(publicGame);
            if (proposal == null || proposal.source != 'ONNX policy') {
              throw StateError('RL produced no trained ONNX suggestion');
            }
            return proposal.action;
          case BenchmarkAgent.statistics:
            final proposal = await compute(_statistics, (
              state: publicGame.publicObservation(),
              rounds: config.statisticsRounds,
            ));
            if (proposal.source != 'Pure statistics') {
              throw StateError('Statistics returned an unexpected source');
            }
            return proposal.action;
          case BenchmarkAgent.casual:
          case BenchmarkAgent.probability:
          case BenchmarkAgent.cautious:
            return benchmarkOpponent(agent, publicGame, opponentRandom);
        }
      },
      onGame: (game) {
        records.writeStringSync('${jsonEncode(game.toJson())}\n');
        records.flushSync();
        stdout.writeln(
          'Completed ${runner!.games.length}: ${game.scenario}, '
          'deal ${game.deal + 1}/${config.deals}, seat ${game.seat + 1}, ${game.method} '
          '(${game.actions} actions)',
        );
      },
    );
    await runner.run();
    summary = summarizeBenchmark(config, runner.games);
  } catch (error, stack) {
    code = 1;
    summary = {
      'status': 'failed',
      'completedGames': runner?.games.length ?? 0,
      'config': config.toJson(),
      'error': '$error',
      'context': runner?.currentContext,
      'progress': runner?.progress,
      'stackTrace': '$stack',
    };
    stderr.writeln('Benchmark failed: $error');
  } finally {
    records.closeSync();
  }
  summary['startedUtc'] = started.toIso8601String();
  summary['finishedUtc'] = DateTime.now().toUtc().toIso8601String();
  summary['elapsedSeconds'] = clock.elapsedMilliseconds / 1000;
  summary['provenance'] = provenance;
  File('${directory.path}/summary.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
  File('${directory.path}/report.md')
      .writeAsStringSync(benchmarkReport(summary));
  stdout.writeln('Report: ${directory.path}/report.md');
  exit(code);
}
