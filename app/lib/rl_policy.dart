import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'game_engine.dart';
import 'onnx_session_loader.dart';

import 'policy_core.dart';
export 'policy_core.dart';

AiMoveProposal _statisticsFromPublicState(
  ({GameState state, int historyLength}) request,
) => StatisticsPolicy.proposeFromState(
  request.state,
  historyLength: request.historyLength,
);

List<AiMoveProposal> _rankedStatisticsFromPublicState(GameState state) =>
    StatisticsPolicy.rankedProposals(WindowGameEngine.fromState(state));

/// Availability of the exported policy/value ONNX model.
enum PolicyAvailability {
  ready,
  testReady,
  deferred,
  loading,
  unavailable,
  inferenceFailed,
}

class RlPolicyException implements Exception {
  const RlPolicyException(this.details);
  final String details;
  @override
  String toString() => 'RL adviser unavailable: $details';
}

class WindowRlPolicy {
  WindowRlPolicy({OnnxRuntime? runtime}) : _runtime = runtime ?? OnnxRuntime();

  final OnnxRuntime _runtime;
  OrtSession? _session;
  bool _loadTried = false;
  Future<void>? _loadFuture;
  bool _modelIsTrained = false;
  int _historyLength = WindowRlContract.defaultHistoryLength;
  int _featureSize = WindowRlContract.historyFeatureSize;
  String? _inferenceError;

  /// Starts model initialization during app startup. Calls share one future,
  /// so an early proposal waits for the same loading work.
  Future<void> preload() => _ensureSession();

  Future<AiMoveProposal?> propose(WindowGameEngine game) async {
    final proposals = await rankedProposals(game);
    return proposals.isEmpty ? null : proposals.first;
  }

  Future<List<AiMoveProposal>> rankedStatisticsProposals(
    WindowGameEngine game,
  ) => compute(_rankedStatisticsFromPublicState, game.publicObservation());

  Future<List<AiMoveProposal>> rankedProposals(WindowGameEngine game) async {
    final List<PolicyAction> actions = WindowRlCodec.validActions(game);
    if (actions.isEmpty) return const [];
    await _ensureSession();
    final OrtSession? session = _session;
    if (session == null) {
      throw RlPolicyException(_inferenceError ?? 'Model unavailable.');
    }
    OrtValue? input;
    Map<String, OrtValue> outputs = <String, OrtValue>{};
    try {
      input = await OrtValue.fromList(
        WindowRlCodec.encodeHistory(
          game,
          historyLength: _historyLength,
          featureSize: _featureSize,
        ),
        <int>[1, _historyLength, _featureSize],
      );
      outputs = await session.run(<String, OrtValue>{
        session.inputNames.first: input,
      });
      final OrtValue? policyOutput = outputs[WindowRlContract.policyOutput];
      if (policyOutput == null) {
        throw StateError(
          'Model did not return ${WindowRlContract.policyOutput}.',
        );
      }
      // Flattened output avoids platform plugins reporting a symbolic batch
      // dimension, which cannot be reshaped by `asList()` on some targets.
      List<double> logits = _toDoubles(await policyOutput.asFlattenedList());
      if (logits.length != WindowRlContract.actionSize) {
        throw StateError(
          'Policy has ${logits.length} actions (runtime tensor '
          '${policyOutput.shape}); expected '
          '${WindowRlContract.actionSize}.',
        );
      }
      final OrtValue? valueOutput = outputs[WindowRlContract.valueOutput];
      final double? value = valueOutput == null
          ? null
          : _toDoubles(await valueOutput.asFlattenedList()).firstOrNull;
      // Stable ties follow the original legal-action order.
      final ordered = List<int>.generate(actions.length, (index) => index)
        ..sort((a, b) {
          final score = logits[actions[b].index].compareTo(
            logits[actions[a].index],
          );
          return score != 0 ? score : a.compareTo(b);
        });
      final maximum = actions.map((a) => logits[a.index]).reduce(math.max);
      final weights = [
        for (final a in actions) math.exp(logits[a.index] - maximum),
      ];
      final denominator = weights.fold<double>(0, (sum, value) => sum + value);
      _inferenceError = null;
      return [
        for (int rank = 0; rank < ordered.length; rank++)
          AiMoveProposal(
            action: actions[ordered[rank]],
            confidence: weights[ordered[rank]] / denominator,
            valueEstimate: value,
            source: _modelIsTrained
                ? 'ONNX policy'
                : 'ONNX test model (untrained)',
            rank: rank,
          ),
      ];
    } catch (error) {
      _inferenceError = '$error';
      throw RlPolicyException(_inferenceError!);
    } finally {
      await input?.dispose();
      for (final OrtValue output in outputs.values) {
        await output.dispose();
      }
    }
  }

  String? get inferenceError => _inferenceError;
  PolicyAvailability get availability {
    if (_inferenceError != null) return PolicyAvailability.inferenceFailed;
    if (_session != null) {
      return _modelIsTrained
          ? PolicyAvailability.ready
          : PolicyAvailability.testReady;
    }
    if (!_loadTried) return PolicyAvailability.deferred;
    if (_loadFuture != null) return PolicyAvailability.loading;
    return PolicyAvailability.unavailable;
  }

  String get availabilityMessage {
    if (_inferenceError != null) {
      return 'RL adviser unavailable. $_inferenceError';
    }
    if (_session != null) {
      return _modelIsTrained
          ? 'ONNX policy loaded.'
          : 'ONNX test model loaded.';
    }
    if (!_loadTried) {
      return 'Bundled ONNX model will load when you request a proposal.';
    }
    if (_loadFuture != null && _session == null) {
      return 'Loading bundled ONNX model…';
    }
    return 'RL model unavailable.';
  }

  Future<void> _ensureSession() => _loadFuture ??= _loadSession();

  Future<void> _loadSession() async {
    _loadTried = true;
    try {
      await rootBundle.load(WindowRlContract.modelAsset);
      final Object? metadata = jsonDecode(
        await rootBundle.loadString(WindowRlContract.metadataAsset),
      );
      if (metadata is Map) {
        if (!((metadata['format'] == WindowRlContract.checkpointFormat &&
                    metadata['historyFeatureSize'] ==
                        WindowRlContract.historyFeatureSize) ||
                (metadata['format'] == 4 &&
                    metadata['historyFeatureSize'] ==
                        WindowRlContract.legacyHistoryFeatureSize)) ||
            metadata['historyLength'] is! num ||
            (metadata['historyLength'] as num).toInt() < 1 ||
            (metadata['historyLength'] as num).toInt() >
                WindowRlContract.maxHistoryLength) {
          throw StateError(
            'Bundled model does not match the recurrent policy contract.',
          );
        }
        _featureSize = (metadata['historyFeatureSize'] as num).toInt();
        _historyLength = (metadata['historyLength'] as num).toInt();
        _modelIsTrained = metadata['trained'] == true;
      }
      _session = await createWindowPolicySession(
        _runtime,
        WindowRlContract.modelAsset,
      );
    } catch (error) {
      _inferenceError = '$error';
    }
  }

  static Future<AiMoveProposal> proposeStatistics(
    WindowGameEngine game, {
    int historyLength = StatisticsPolicy.defaultHistoryLength,
  }) => compute(_statisticsFromPublicState, (
    state: game.publicObservation(
      maxEvents: StatisticsPolicy.checkHistoryLength(historyLength),
    ),
    historyLength: historyLength,
  ));

  static AiMoveProposal statisticsProposal(
    WindowGameEngine game, {
    List<PolicyAction>? actions,
    int budgetMilliseconds = 180,
    int? fixedRounds,
    int historyLength = StatisticsPolicy.defaultHistoryLength,
    int? scenarioSeed,
  }) => StatisticsPolicy.propose(
    game,
    actions: actions,
    budgetMilliseconds: budgetMilliseconds,
    fixedRounds: fixedRounds,
    historyLength: historyLength,
    scenarioSeed: scenarioSeed,
  );

  static List<({PolicyAction action, double success, int penalty})>
  immediateMoveRisks(WindowGameEngine game) =>
      StatisticsPolicy.immediateMoveRisks(game);

  static Map<Position, List<double>> statisticsRankProbabilities(
    WindowGameEngine game, {
    int historyLength = StatisticsPolicy.defaultHistoryLength,
  }) => StatisticsPolicy.rankProbabilities(game, historyLength: historyLength);

  List<double> _toDoubles(Object? value) {
    if (value is num) {
      return <double>[value.toDouble()];
    }
    if (value is List) {
      return value.expand<double>((Object? item) => _toDoubles(item)).toList();
    }
    throw StateError('ONNX output is not numeric.');
  }
}

extension on List<double> {
  double? get firstOrNull => isEmpty ? null : first;
}
