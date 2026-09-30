import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'game_engine.dart';
import 'onnx_session_loader.dart';

/// Versioned recurrent observation/action contract shared with the trainer.
class WindowRlContract {
  static const int checkpointFormat = 4;
  static const int rows = 5;
  static const int columns = 6;
  static const int cardFeatures = 2;
  static const int boardFeatureSize = rows * columns * cardFeatures;
  static const int actionFeatureSize = 5;
  static const int outcomeFeatureSize = 3;
  static const int removedFeatureSize = rows * columns * cardFeatures;
  static const int flagFeatureSize = 2;
  static const int historyFeatureSize =
      boardFeatureSize + actionFeatureSize + outcomeFeatureSize +
      removedFeatureSize + flagFeatureSize;
  static const int defaultHistoryLength = 16;
  static const int maxHistoryLength = maxPublicHistoryEvents + 1;
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
  static List<double> encodeHistory(
    WindowGameEngine game, {
    int historyLength = WindowRlContract.defaultHistoryLength,
  }) {
    final List<PublicMoveEvent> events = game.recentEvents;
    final List<List<double>> records = <List<double>>[
      for (final PublicMoveEvent event in events) _eventFeatures(event),
      _currentFeatures(game),
    ];
    final List<List<double>> recent = records.length > historyLength
        ? records.sublist(records.length - historyLength)
        : records;
    final List<double> result = <double>[
      for (int index = recent.length; index < historyLength; index++)
        ...List<double>.filled(WindowRlContract.historyFeatureSize, 0),
      for (final List<double> record in recent) ...record,
    ];
    assert(
      result.length == historyLength * WindowRlContract.historyFeatureSize,
    );
    return result;
  }

  static List<double> _currentFeatures(WindowGameEngine game) => _features(
    board: List<List<int?>>.generate(
      WindowRlContract.rows,
      (int row) => List<int?>.generate(WindowRlContract.columns, (int column) {
        final Position position = Position(row, column);
        return game.isValidSlot(position) && game.isFaceUp(position)
            ? game.cardAt(position)
            : null;
      }),
    ),
    actionIndex: -1,
    outcome: '',
    removed: _emptyBoard(),
    mustSelect: game.mustSelectAdjacentToHandle,
    canEnd: game.turnCanEnd,
  );

  static List<double> _eventFeatures(PublicMoveEvent event) => _features(
    board: event.boardBefore,
    actionIndex: event.actionIndex,
    outcome: event.outcome,
    removed: event.removedCards,
    mustSelect: event.mustSelectAdjacentToHandle,
    canEnd: event.turnCanEnd,
  );

  static List<List<int?>> _emptyBoard() => List<List<int?>>.generate(
    WindowRlContract.rows,
    (int _) => List<int?>.filled(WindowRlContract.columns, null),
  );

  static List<double> _features({
    required List<List<int?>> board,
    required int actionIndex,
    required String outcome,
    required List<List<int?>> removed,
    required bool mustSelect,
    required bool canEnd,
  }) {
    final List<double> result = <double>[];
    for (int row = 0; row < WindowRlContract.rows; row++) {
      for (int column = 0; column < WindowRlContract.columns; column++) {
        final bool slot = windowLayout[row][column];
        final int? card = board[row][column];
        result.addAll(card == null
            ? <double>[slot ? -1 : -2, slot ? -1 : -2]
            : <double>[(card ~/ 4) / 8, (card % 4) / 3]);
      }
    }
    if (actionIndex < 0) {
      result.addAll(List<double>.filled(WindowRlContract.actionFeatureSize, 0));
    } else if (actionIndex == WindowRlContract.passActionIndex) {
      result.addAll(const <double>[1, 0, 0, 0, 0]);
    } else {
      int encoded = actionIndex;
      final double guess = (encoded % 5) / 4;
      encoded ~/= 5;
      final double orientation = (encoded % 2).toDouble();
      encoded ~/= 2;
      result.addAll(<double>[
        0,
        (encoded ~/ 6) / 4,
        (encoded % 6) / 5,
        orientation,
        guess,
      ]);
    }
    result.addAll(<double>[
      outcome == 'correct' ? 1 : 0,
      outcome == 'wrong' ? 1 : 0,
      outcome == 'pass' ? 1 : 0,
    ]);
    for (int row = 0; row < WindowRlContract.rows; row++) {
      for (int column = 0; column < WindowRlContract.columns; column++) {
        final bool slot = windowLayout[row][column];
        final int? card = removed[row][column];
        result.addAll(card == null
            ? <double>[slot ? -1 : -2, slot ? -1 : -2]
            : <double>[(card ~/ 4) / 8, (card % 4) / 3]);
      }
    }
    result.addAll(<double>[
      mustSelect ? 1 : 0,
      canEnd ? 1 : 0,
    ]);
    assert(result.length == WindowRlContract.historyFeatureSize);
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
  Future<void>? _loadFuture;
  bool _modelIsTrained = false;
  int _historyLength = WindowRlContract.defaultHistoryLength;
  String? _inferenceError;

  /// Starts model initialization during app startup. Calls share one future,
  /// so an early proposal waits for the same loading work instead of falling
  /// back while a session is still being created.
  Future<void> preload() => _ensureSession();

  Future<AiMoveProposal?> propose(WindowGameEngine game) async {
    final List<PolicyAction> actions = WindowRlCodec.validActions(game);
    if (actions.isEmpty) return null;
    await _ensureSession();
    final OrtSession? session = _session;
    if (session == null) return statisticsProposal(game, actions: actions);
    final OrtValue input = await OrtValue.fromList(
      WindowRlCodec.encodeHistory(game, historyLength: _historyLength),
      <int>[1, _historyLength, WindowRlContract.historyFeatureSize],
    );
    Map<String, OrtValue> outputs = <String, OrtValue>{};
    try {
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
      return _statisticsFallback(game, actions);
    } finally {
      await input.dispose();
      for (final OrtValue output in outputs.values) {
        await output.dispose();
      }
    }
  }

  String get availabilityMessage {
    if (_inferenceError != null) {
      return 'ONNX inference failed; using pure statistics. $_inferenceError';
    }
    if (_session != null) {
      return _modelIsTrained
          ? 'ONNX policy loaded.'
          : 'ONNX test model loaded.';
    }
    if (!_loadTried) {
      return 'Bundled ONNX test model will load when you request a proposal.';
    }
    if (_loadFuture != null && _session == null) {
      return 'Loading bundled ONNX model…';
    }
    return 'Model unavailable; using the pure-statistics fallback.';
  }

  AiMoveProposal _statisticsFallback(
    WindowGameEngine game,
    List<PolicyAction> actions,
  ) {
    final AiMoveProposal fallback = statisticsProposal(game, actions: actions);
    return AiMoveProposal(
      action: fallback.action,
      confidence: fallback.confidence,
      source: 'ONNX inference failed → Pure statistics',
    );
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
