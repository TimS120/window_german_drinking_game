import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/game_state_codec.dart';
import 'package:window_game/rl_policy.dart';

import 'rl_deployment_cases.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('bundled trained policy matches PyTorch through native ONNX', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final data = jsonDecode(deploymentProbeJson) as Map<String, dynamic>;
      final metadata = jsonDecode(
        await rootBundle.loadString(WindowRlContract.metadataAsset),
      ) as Map<String, dynamic>;
      expect(metadata['checkpointSha256'], data['checkpointSha256']);
      expect(metadata['trained'], isTrue);
      expect(metadata['historyLength'], 33);
      expect(metadata['historyFeatureSize'], 134);
      expect(metadata['trainingPlayerCounts'], [1, 2, 3, 4]);
      final policy = WindowRlPolicy();
      await policy.preload();
      expect(
        policy.availability,
        PolicyAvailability.ready,
        reason: policy.inferenceError,
      );
      final watch = Stopwatch()..start();
      final cases = data['cases'] as List<dynamic>;
      for (final raw in cases) {
        final fixture = raw as Map<String, dynamic>;
        final game = WindowGameEngine.fromState(
          GameStateCodec.decode(
            Map<Object?, Object?>.from(fixture['state'] as Map),
          ),
        );
        final before = jsonEncode(GameStateCodec.encode(game.exportState()));
        final ranked = await policy.rankedProposals(game);
        final proposal = ranked.isEmpty ? null : ranked.first;
        if (fixture['secondAction'] != null) {
          expect(
            ranked[1].action.index,
            fixture['secondAction'],
            reason: fixture['name'] as String,
          );
          expect(ranked[1].rank, 1);
          expect(
            ranked[1].confidence,
            closeTo((fixture['secondConfidence'] as num).toDouble(), .0001),
          );
          expect(ranked[1].action.index, isNot(ranked[0].action.index));
          if (game.players.length == 1) {
            expect(ranked[1].action.isPass, isFalse);
          }
        }
        expect(proposal, isNotNull, reason: fixture['name'] as String);
        if (game.players.length == 1) {
          expect(proposal!.action.isPass, isFalse);
        }
        expect(
          proposal!.action.index,
          fixture['action'],
          reason: fixture['name'] as String,
        );
        expect(
          proposal.valueEstimate,
          closeTo((fixture['value'] as num).toDouble(), 0.001),
          reason: fixture['name'] as String,
        );
        expect(
          proposal.confidence,
          closeTo((fixture['confidence'] as num).toDouble(), 0.0001),
        );
        expect(jsonEncode(GameStateCodec.encode(game.exportState())), before);
      }
      watch.stop();
      // This measures fixture inference, not a general device latency guarantee.
      // ignore: avoid_print
      print(
        'Native policy parity: ${cases.length} cases; '
        '${watch.elapsedMilliseconds} ms including encoding and assertions.',
      );
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
