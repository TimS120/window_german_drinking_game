import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'game_engine.dart';
import 'onnx_session_loader.dart';

import 'policy_core.dart';
export 'policy_core.dart';

AiMoveProposal _statisticsFromPublicState(GameState state) =>
    StatisticsPolicy.proposeFromState(state);

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
  String? _inferenceError;

  /// Starts model initialization during app startup. Calls share one future,
  /// so an early proposal waits for the same loading work.
  Future<void> preload() => _ensureSession();

  Future<AiMoveProposal?> propose(WindowGameEngine game) async {
    final List<PolicyAction> actions = WindowRlCodec.validActions(game);
    if (actions.isEmpty) return null;
    await _ensureSession();
    final OrtSession? session = _session;
    if (session == null) {
      throw RlPolicyException(_inferenceError ?? 'Model unavailable.');
    }
    OrtValue? input;
    Map<String, OrtValue> outputs = <String, OrtValue>{};
    try {
      input = await OrtValue.fromList(
        WindowRlCodec.encodeHistory(game, historyLength: _historyLength),
        <int>[1, _historyLength, WindowRlContract.historyFeatureSize],
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
      final PolicyAction best = actions.reduce(
        (PolicyAction current, PolicyAction candidate) =>
            logits[candidate.index] > logits[current.index]
            ? candidate
            : current,
      );
      _inferenceError = null;
      return AiMoveProposal(
        action: best,
        confidence: _maskedConfidence(best, actions, logits),
        valueEstimate: value,
        source: _modelIsTrained ? 'ONNX policy' : 'ONNX test model (untrained)',
      );
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
        if (metadata['format'] != WindowRlContract.checkpointFormat ||
            metadata['historyFeatureSize'] !=
                WindowRlContract.historyFeatureSize ||
            metadata['historyLength'] is! num ||
            (metadata['historyLength'] as num).toInt() < 1 ||
            (metadata['historyLength'] as num).toInt() >
                WindowRlContract.maxHistoryLength) {
          throw StateError(
            'Bundled model does not match the recurrent policy contract.',
          );
        }
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

  static Future<AiMoveProposal> proposeStatistics(WindowGameEngine game) =>
      compute(_statisticsFromPublicState, game.publicObservation());

  static AiMoveProposal statisticsProposal(
    WindowGameEngine game, {
    List<PolicyAction>? actions,
    int budgetMilliseconds = 180,
    int? fixedRounds,
  }) => StatisticsPolicy.propose(
    game,
    actions: actions,
    budgetMilliseconds: budgetMilliseconds,
    fixedRounds: fixedRounds,
  );

  static List<({PolicyAction action, double success, int penalty})>
  immediateMoveRisks(WindowGameEngine game) =>
      StatisticsPolicy.immediateMoveRisks(game);

  static Map<Position, List<double>> statisticsRankProbabilities(
    WindowGameEngine game,
  ) => StatisticsPolicy.rankProbabilities(game);

  double _maskedConfidence(
    PolicyAction selected,
    List<PolicyAction> actions,
    List<double> logits,
  ) {
    final double maximum = actions
        .map((PolicyAction action) => logits[action.index])
        .reduce(math.max);
    final double denominator = actions.fold<double>(
      0,
      (double sum, PolicyAction action) =>
          sum + math.exp(logits[action.index] - maximum),
    );
    return math.exp(logits[selected.index] - maximum) / denominator;
  }

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
