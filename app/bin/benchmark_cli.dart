/// Native Dart CLI: the app's exact rules, encoding and statistical adviser.
library;

// Standalone cached snapshots intentionally avoid the Flutter package graph.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lib/advisor_benchmark.dart';
import '../lib/policy_core.dart';
import '../lib/game_engine.dart';

void send(Map<String, dynamic> value) => stdout.writeln(jsonEncode(value));

class OnnxBridge {
  OnnxBridge(this.process, this.lines, this.historyLength, this.info);
  final Process process;
  final StreamIterator<String> lines;
  final int historyLength;
  final Map<String, dynamic> info;

  static Future<OnnxBridge> start(Map<String, dynamic> raw) async {
    final process = await Process.start(raw['python'] as String, [
      raw['onnxWorker'] as String,
      raw['modelPath'] as String,
      raw['metadataPath'] as String,
    ]);
    process.stderr.transform(utf8.decoder).listen(stderr.write);
    final lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    if (!await lines.moveNext()) {
      throw StateError('ONNX worker failed to start');
    }
    final hello = jsonDecode(lines.current) as Map<String, dynamic>;
    if (hello['ready'] != true) {
      throw StateError('ONNX worker is not ready: $hello');
    }
    return OnnxBridge(process, lines, hello['historyLength'] as int, hello);
  }

  Future<PolicyAction> propose(WindowGameEngine game) async {
    final actions = WindowRlCodec.validActions(game);
    process.stdin.writeln(
      jsonEncode({
        'history': WindowRlCodec.encodeHistory(
          game,
          historyLength: historyLength,
        ),
        'legal': actions.map((a) => a.index).toList(),
      }),
    );
    await process.stdin.flush();
    if (!await lines.moveNext()) {
      throw StateError('ONNX worker closed unexpectedly');
    }
    final response = jsonDecode(lines.current) as Map<String, dynamic>;
    if (response['error'] != null) throw StateError(response['error']);
    return actions.firstWhere((a) => a.index == response['action']);
  }

  Future<void> close() async {
    await process.stdin.close();
    await lines.cancel();
    process.kill();
    await process.exitCode;
  }
}

Future<void> main(List<String> args) async {
  Map<String, dynamic>? raw;
  BenchmarkRunner? runner;
  OnnxBridge? bridge;
  try {
    raw =
        jsonDecode(File(args.last).readAsStringSync()) as Map<String, dynamic>;
    final config = BenchmarkConfig.fromJson(raw)..validate();
    if (args.first == '--plan') {
      send({
        'scenarios': [
          for (final s in benchmarkScenarios(config))
            {
              'name': s.name,
              'players': s.players,
              'gamesPerDeal': benchmarkGamesPerDeal(config, s),
            },
        ],
      });
      return;
    }
    if (args.first == '--summarize') {
      final directory = raw['outputDirectory'] as String;
      final games = File('$directory/games.jsonl')
          .readAsLinesSync()
          .map(
            (line) => BenchmarkGame.fromJson(
              jsonDecode(line) as Map<String, dynamic>,
            ),
          )
          .toList();
      final summary = summarizeBenchmark(config, games);
      for (final key in [
        'startedUtc',
        'elapsedSeconds',
        'provenance',
        'execution',
      ]) {
        summary[key] = raw[key];
      }
      summary['finishedUtc'] = DateTime.now().toUtc().toIso8601String();
      File(
        '$directory/summary.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
      File('$directory/report.md').writeAsStringSync(benchmarkReport(summary));
      return;
    }
    bridge = await OnnxBridge.start(raw)
        .timeout(Duration(seconds: config.decisionTimeoutSeconds));
    send({'type': 'ready', 'runtime': bridge.info});
    final heart = Stopwatch()..start();
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      final job = jsonDecode(line) as Map<String, dynamic>;
      runner = BenchmarkRunner(config, (
        agent,
        publicGame,
        opponentRandom,
      ) async {
        if (heart.elapsedMilliseconds >= 1000) {
          send({'type': 'heartbeat', 'progress': runner?.progress});
          heart.reset();
        }
        final timer = Stopwatch()..start();
        final action = switch (agent) {
          BenchmarkAgent.rl => await bridge!.propose(publicGame),
          BenchmarkAgent.statistics => StatisticsPolicy.propose(
            publicGame,
            fixedRounds: config.statisticsRounds,
          ).action,
          _ => benchmarkOpponent(agent, publicGame, opponentRandom),
        };
        if (timer.elapsedMilliseconds > config.decisionTimeoutSeconds * 1000) {
          throw TimeoutException(
            '$agent decision exceeded the configured timeout',
          );
        }
        return action;
      }, onGame: (game) => send({'type': 'game', 'game': game.toJson()}));
      await runner.run(
        scenarioName: job['scenario'] as String,
        dealIndex: job['deal'] as int,
      );
      send({'type': 'done', 'job': job});
    }
  } catch (error, stack) {
    send({
      'type': 'error',
      'error': '$error',
      'context': runner?.currentContext,
      'progress': runner?.progress,
      'stackTrace': '$stack',
    });
    exitCode = 1;
  } finally {
    await bridge?.close();
  }
}
