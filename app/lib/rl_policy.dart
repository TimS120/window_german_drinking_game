import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'game_engine.dart';

/// Fixed observation/action contract shared with the future Python trainer.
class WindowRlContract {
  static const int rows = 5;
  static const int columns = 6;
  static const int featuresPerCell = 3;
  static const int globalFeatures = 5;
  static const int featureSize =
      rows * columns * featuresPerCell + globalFeatures;
  static const int orientations = 2;
  static const int guessTypes = 5;
  static const int cardActionSize = rows * columns * orientations * guessTypes;
  static const int passActionIndex = cardActionSize;
  static const int actionSize = cardActionSize + 1;
  static const String modelAsset = 'assets/models/window_policy.onnx';
  static const String metadataAsset =
      'assets/models/window_policy.metadata.json';
  static const String policyOutput = 'policy_logits';
  static const String valueOutput = 'state_value';
}

class PolicyAction {
  const PolicyAction.guess({
    required this.position,
    required this.orientation,
    required this.guess,
  }) : isPass = false;

  const PolicyAction.pass()
    : position = null,
      orientation = null,
      guess = null,
      isPass = true;

  final Position? position;
  final Orientation? orientation;
  final GuessType? guess;
  final bool isPass;

  int get index {
    if (isPass) return WindowRlContract.passActionIndex;
    return (((position!.row * WindowRlContract.columns + position!.column) *
                    WindowRlContract.orientations +
                orientation!.index) *
            WindowRlContract.guessTypes) +
        guess!.index;
  }

  String get label {
    if (isPass) return 'end turn (pass)';
    return 'row ${position!.row + 1}, column ${position!.column + 1}: '
        '${orientation == Orientation.horizontal ? 'horizontal' : 'vertical'} '
        '${switch (guess!) {
          GuessType.higher => 'higher',
          GuessType.same => 'same',
          GuessType.lower => 'lower',
          GuessType.inBetween => 'in-between',
          GuessType.outside => 'outside',
        }}';
  }
}

class AiMoveProposal {
  const AiMoveProposal({
    required this.action,
    required this.confidence,
    required this.source,
    this.valueEstimate,
  });

  final PolicyAction action;
  final double confidence;
  final String source;
  final double? valueEstimate;
}

class WindowRlCodec {
  static List<double> encodeObservation(WindowGameEngine game) {
    final List<double> result = <double>[];
    for (int row = 0; row < WindowRlContract.rows; row++) {
      for (int column = 0; column < WindowRlContract.columns; column++) {
        final Position position = Position(row, column);
        final bool slot = game.isValidSlot(position);
        final bool faceUp = slot && game.isFaceUp(position);
        final int? card = slot ? game.cardAt(position) : null;
        result.addAll(<double>[
          slot ? 1 : 0,
          faceUp ? 1 : 0,
          faceUp && card != null ? (card ~/ 4) / 8 : -1,
        ]);
      }
    }
    final GameState state = game.exportState();
    result.addAll(<double>[
      game.mustSelectAdjacentToHandle ? 1 : 0,
      game.turnCanEnd ? 1 : 0,
      game.pendingRemovals.isNotEmpty ? 1 : 0,
      state.pendingSamePosition == null ? 0 : 1,
      state.players.length.clamp(1, 8) / 8,
    ]);
    assert(result.length == WindowRlContract.featureSize);
    return result;
  }

  static List<PolicyAction> validActions(WindowGameEngine game) {
    final List<PolicyAction> actions = <PolicyAction>[];
    if (game.pendingRemovals.isNotEmpty ||
        game.exportState().pendingSamePosition != null) {
      return actions;
    }
    for (final Position position in game.validSelectablePositions()) {
      for (final GuessOption option in game.getValidOptionsForCard(position)) {
        for (final GuessType guess in option.guesses) {
          actions.add(
            PolicyAction.guess(
              position: position,
              orientation: option.orientation,
              guess: guess,
            ),
          );
        }
      }
    }
    if (game.turnCanEnd) actions.add(const PolicyAction.pass());
    return actions;
  }
}

/// Loads an exported policy/value ONNX model when one is bundled. Until then,
/// a probability-based fallback keeps the feature useful and testable.
class WindowRlPolicy {
  WindowRlPolicy({OnnxRuntime? runtime}) : _runtime = runtime ?? OnnxRuntime();

  final OnnxRuntime _runtime;
  OrtSession? _session;
  bool _loadTried = false;
  String? _loadError;
  bool _modelIsTrained = false;

  Future<AiMoveProposal?> propose(WindowGameEngine game) async {
    final List<PolicyAction> actions = WindowRlCodec.validActions(game);
    if (actions.isEmpty) return null;
    await _ensureSession();
    final OrtSession? session = _session;
    if (session == null) return statisticsProposal(game, actions: actions);
    try {
      final OrtValue input = await OrtValue.fromList(
        WindowRlCodec.encodeObservation(game),
        <int>[1, WindowRlContract.featureSize],
      );
      final Map<String, OrtValue> outputs = await session.run(
        <String, OrtValue>{session.inputNames.first: input},
      );
      try {
        final List<double> logits = _toDoubles(
          await outputs[WindowRlContract.policyOutput]!.asList(),
        );
        if (logits.length != WindowRlContract.actionSize) {
          throw StateError(
            'Policy has ${logits.length} actions; expected '
            '${WindowRlContract.actionSize}.',
          );
        }
        final OrtValue? valueOutput = outputs[WindowRlContract.valueOutput];
        final double? value = valueOutput == null
            ? null
            : _toDoubles(await valueOutput.asList()).firstOrNull;
        final PolicyAction best = actions.reduce(
          (PolicyAction current, PolicyAction candidate) =>
              logits[candidate.index] > logits[current.index]
              ? candidate
              : current,
        );
        return AiMoveProposal(
          action: best,
          confidence: _maskedConfidence(best, actions, logits),
          valueEstimate: value,
          source: _modelIsTrained
              ? 'ONNX policy'
              : 'ONNX test model (untrained)',
        );
      } finally {
        input.dispose();
        for (final OrtValue output in outputs.values) {
          output.dispose();
        }
      }
    } catch (_) {
      return statisticsProposal(game, actions: actions);
    }
  }

  String get availabilityMessage {
    if (_session != null) return 'ONNX test model loaded.';
    if (!_loadTried) {
      return 'Bundled ONNX test model will load when you request a proposal.';
    }
    return 'Model unavailable; using the pure-statistics fallback.';
  }

  Future<void> _ensureSession() async {
    if (_loadTried) return;
    _loadTried = true;
    try {
      await rootBundle.load(WindowRlContract.modelAsset);
      final Object? metadata = jsonDecode(
        await rootBundle.loadString(WindowRlContract.metadataAsset),
      );
      if (metadata is Map) {
        _modelIsTrained = metadata['trained'] == true;
      }
      _session = await _runtime.createSessionFromAsset(
        WindowRlContract.modelAsset,
      );
    } catch (error) {
      _loadError = '$error';
    }
  }

  static AiMoveProposal statisticsProposal(
    WindowGameEngine game, {
    List<PolicyAction>? actions,
  }) {
    final List<PolicyAction> legalActions =
        actions ?? WindowRlCodec.validActions(game);
    if (legalActions.isEmpty) {
      throw StateError('No legal action can be proposed right now.');
    }
    final List<double> scores = legalActions
        .map((PolicyAction action) => _estimatedSuccess(game, action))
        .toList();
    int bestIndex = 0;
    for (int index = 1; index < scores.length; index++) {
      if (scores[index] > scores[bestIndex]) bestIndex = index;
    }
    return AiMoveProposal(
      action: legalActions[bestIndex],
      confidence: scores[bestIndex],
      source: 'Pure statistics',
    );
  }

  static double _estimatedSuccess(WindowGameEngine game, PolicyAction action) {
    // Ending a legal turn cannot add an immediate drink. The future trained
    // policy will learn the longer-horizon trade-off from game rewards.
    if (action.isPass) return 1;
    final List<int> unseen = List<int>.filled(9, 4);
    for (int row = 0; row < WindowRlContract.rows; row++) {
      for (int column = 0; column < WindowRlContract.columns; column++) {
        final Position position = Position(row, column);
        if (!game.isValidSlot(position) || !game.isFaceUp(position)) continue;
        final int? card = game.cardAt(position);
        if (card != null) unseen[card ~/ 4]--;
      }
    }
    final GuessOption option = game
        .getValidOptionsForCard(action.position!)
        .firstWhere(
          (GuessOption value) => value.orientation == action.orientation!,
        );
    final int total = math.max(
      1,
      unseen.fold<int>(0, (int sum, int count) => sum + count),
    );
    int countFor(bool Function(int rank) matches) => List<int>.generate(
      9,
      (int rank) => rank,
    ).where(matches).fold<int>(0, (int sum, int rank) => sum + unseen[rank]);
    if (option.type == GuessOptionType.higherLower) {
      final int rank = game.cardAt(option.neighbors.single)! ~/ 4;
      return switch (action.guess!) {
        GuessType.higher => countFor((int value) => value > rank) / total,
        GuessType.same => unseen[rank] / total,
        GuessType.lower => countFor((int value) => value < rank) / total,
        _ => 0,
      };
    }
    final int first = game.cardAt(option.neighbors.first)! ~/ 4;
    final int second = game.cardAt(option.neighbors.last)! ~/ 4;
    final int low = math.min(first, second);
    final int high = math.max(first, second);
    final double between =
        countFor((int value) => value >= low && value <= high) / total;
    return action.guess! == GuessType.inBetween ? between : 1 - between;
  }

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
