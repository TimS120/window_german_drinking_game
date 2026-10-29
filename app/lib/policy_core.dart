import 'dart:math' as math;

import 'game_engine.dart';
part 'statistics/statistics_advisor.dart';
part 'statistics/statistics_card_beliefs.dart';
part 'statistics/statistics_table_model.dart';
part 'statistics/statistics_policy.dart';

/// Versioned recurrent observation/action contract shared with the trainer.
class WindowRlContract {
  static const int checkpointFormat = 5;
  static const int rows = 5;
  static const int columns = 6;
  static const int cardFeatures = 2;
  static const int boardFeatureSize = rows * columns * cardFeatures;
  static const int actionFeatureSize = 5;
  static const int outcomeFeatureSize = 3;
  static const int removedFeatureSize = rows * columns * cardFeatures;
  static const int flagFeatureSize = 2;
  static const int legacyHistoryFeatureSize =
      boardFeatureSize +
      actionFeatureSize +
      outcomeFeatureSize +
      removedFeatureSize +
      flagFeatureSize;
  static const int historyFeatureSize = legacyHistoryFeatureSize + 4;
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
    this.explanation,
    this.expectedDrinks,
    this.statisticsDiagnostics,
    this.rank = 0,
  });

  final int rank;
  final PolicyAction action;
  final double confidence;
  final String source;
  final double? valueEstimate;
  final String? explanation;
  final double? expectedDrinks;
  final StatisticsDiagnostics? statisticsDiagnostics;

  AiMoveProposal withRank(int rank) => AiMoveProposal(
    action: action,
    confidence: confidence,
    source: source,
    valueEstimate: valueEstimate,
    explanation: explanation,
    expectedDrinks: expectedDrinks,
    statisticsDiagnostics: statisticsDiagnostics,
    rank: rank,
  );
}

class WindowRlCodec {
  static List<double> encodeHistory(
    WindowGameEngine game, {
    int historyLength = WindowRlContract.defaultHistoryLength,
    int featureSize = WindowRlContract.historyFeatureSize,
  }) {
    if (historyLength < 1 ||
        historyLength > WindowRlContract.maxHistoryLength ||
        (featureSize != WindowRlContract.historyFeatureSize &&
            featureSize != WindowRlContract.legacyHistoryFeatureSize) ||
        game.players.isEmpty ||
        game.players.length > 4) {
      throw ArgumentError("Unsupported RL history or player count");
    }
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
        ...List<double>.filled(featureSize, 0),
      for (final List<double> record in recent) ...<double>[
        ...record,
        if (featureSize == WindowRlContract.historyFeatureSize)
          for (int count = 1; count <= 4; count++)
            count == game.players.length ? 1 : 0,
      ],
    ];
    assert(result.length == historyLength * featureSize);
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
        result.addAll(
          card == null
              ? <double>[slot ? -1 : -2, slot ? -1 : -2]
              : <double>[(card ~/ 4) / 8, (card % 4) / 3],
        );
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
        result.addAll(
          card == null
              ? <double>[slot ? -1 : -2, slot ? -1 : -2]
              : <double>[(card ~/ 4) / 8, (card % 4) / 3],
        );
      }
    }
    result.addAll(<double>[mustSelect ? 1 : 0, canEnd ? 1 : 0]);
    assert(result.length == WindowRlContract.legacyHistoryFeatureSize);
    return result;
  }

  static List<PolicyAction> validActions(WindowGameEngine game) {
    final List<PolicyAction> actions = <PolicyAction>[];
    if (game.pendingRemovals.isNotEmpty || game.pendingSamePosition != null) {
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
    if (game.canEndTurn) actions.add(const PolicyAction.pass());
    return actions;
  }
}
