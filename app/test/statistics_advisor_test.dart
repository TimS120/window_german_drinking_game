import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/game_state_codec.dart';
import 'package:window_game/rl_policy.dart';

GameState publicState(
  List<List<int?>> board, {
  List<PublicMoveEvent> events = const [],
  bool canPass = false,
}) => GameState(
  players: ['Ada', 'Ben', 'Cat'],
  currentPlayerIndex: 0,
  turnStartFaceUp: 5,
  deck: const [],
  cardGrid: board,
  faceUp: board.map((row) => row.map((card) => card != null).toList()).toList(),
  pendingRemovals: const {},
  pendingPenalty: 0,
  mustSelectAdjacentToHandle: !canPass,
  turnCanEnd: canPass,
  stats: {
    for (final name in ['Ada', 'Ben', 'Cat']) name: const PlayerStats(),
  },
  recentEvents: events,
);

List<List<int?>> blank() => List.generate(5, (_) => List<int?>.filled(6, null));

void main() {
  test(
    'hidden permutations cannot change beliefs or a fixed-budget proposal',
    () {
      final game = WindowGameEngine(['Ada', 'Ben'], seed: 42);
      final json = GameStateCodec.encode(game.exportState());
      final hidden = <int>[];
      final grid = (json['cardGrid'] as List<List<int?>>);
      for (int r = 0; r < 5; r++) {
        for (int c = 0; c < 6; c++) {
          if (windowLayout[r][c] && !game.isFaceUp(Position(r, c))) {
            hidden.add(grid[r][c]!);
          }
        }
      }
      hidden.addAll((json['deck'] as List<int>));
      final reversed = hidden.reversed.toList();
      for (int r = 0; r < 5; r++) {
        for (int c = 0; c < 6; c++) {
          if (windowLayout[r][c] && !game.isFaceUp(Position(r, c))) {
            grid[r][c] = reversed.removeLast();
          }
        }
      }
      json['deck'] = reversed;
      final other = WindowGameEngine.fromState(GameStateCodec.decode(json));
      expect(
        WindowRlPolicy.statisticsRankProbabilities(other),
        WindowRlPolicy.statisticsRankProbabilities(game),
      );
      final a = WindowRlPolicy.statisticsProposal(game, budgetMilliseconds: 0);
      final b = WindowRlPolicy.statisticsProposal(other, budgetMilliseconds: 0);
      expect(b.action.index, a.action.index);
      expect(b.confidence, a.confidence);
      expect(b.expectedDrinks, a.expectedDrinks);
      expect(b.explanation, a.explanation);
    },
  );

  test('returned aces favor replacements over untouched hidden cards', () {
    final before = blank();
    before[0][0] = 0;
    before[0][4] = 4;
    before[4][0] = 8;
    before[4][4] = 12;
    before[2][5] = 33;
    final removed = blank();
    removed[2][4] = 32;
    removed[2][5] = 33;
    final now = before.map((r) => List<int?>.from(r)).toList();
    now[2][5] = 16;
    final event = PublicMoveEvent(
      boardBefore: before,
      actionIndex: ((2 * 6 + 4) * 2) * 5,
      outcome: 'wrong',
      removedCards: removed,
      mustSelectAdjacentToHandle: true,
      turnCanEnd: false,
    );
    final game = WindowGameEngine.fromState(publicState(now, events: [event]));
    final probabilities = WindowRlPolicy.statisticsRankProbabilities(game);
    expect(
      probabilities[const Position(2, 4)]![8],
      greaterThan(probabilities[const Position(0, 1)]![8] + 0.05),
    );
    for (final distribution in probabilities.values) {
      expect(distribution.reduce((a, b) => a + b), closeTo(1, 1e-12));
    }
  });

  test('public observation keeps only sixteen events and no private cards', () {
    final game = WindowGameEngine(['Ada'], seed: 2);
    final state = GameStateCodec.encode(game.exportState());
    final board = game.publicObservation().cardGrid;
    final event = PublicMoveEvent(
      boardBefore: board,
      actionIndex: 300,
      outcome: 'pass',
      removedCards: blank(),
      mustSelectAdjacentToHandle: true,
      turnCanEnd: true,
    );
    state['recentEvents'] = List.generate(
      20,
      (_) => {
        'boardBefore': event.boardBefore,
        'actionIndex': event.actionIndex,
        'outcome': event.outcome,
        'removedCards': event.removedCards,
        'mustSelectAdjacentToHandle': true,
        'turnCanEnd': true,
      },
    );
    final observation = WindowGameEngine.fromState(GameStateCodec.decode(state))
        .publicObservation();
    expect(observation.recentEvents, hasLength(16));
    expect(observation.deck, isEmpty);
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        if (!observation.faceUp[r][c]) {
          expect(observation.cardGrid[r][c], isNull);
        }
      }
    }
  });

  test('proposal is legal, explanatory, non-mutating and bounded', () {
    final game = WindowGameEngine(['Ada', 'Ben', 'Cat'], seed: 7);
    final before = GameStateCodec.encode(game.exportState());
    final timer = Stopwatch()..start();
    final proposal = WindowRlPolicy.statisticsProposal(game);
    // A generous regression bound for debug CI, not a smartphone benchmark.
    expect(timer.elapsedMilliseconds, lessThan(3000));
    expect(
      WindowRlCodec.validActions(game).map((a) => a.index),
      contains(proposal.action.index),
    );
    expect(proposal.confidence, inInclusiveRange(0, 1));
    expect(proposal.expectedDrinks, isNonNegative);
    expect(proposal.explanation, isNotEmpty);
    expect(GameStateCodec.encode(game.exportState()), before);
  });

  test('takes a guaranteed finishing move instead of passing', () {
    final board = blank();
    int id = 0;
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        if (windowLayout[r][c]) board[r][c] = id++;
      }
    }
    board[0][1] = null;
    board[0][2] = 32;
    final game = WindowGameEngine.fromState(publicState(board, canPass: true));
    final proposal = WindowRlPolicy.statisticsProposal(
      game,
      budgetMilliseconds: 0,
    );
    expect(proposal.action.isPass, isFalse);
    expect(proposal.action.position, const Position(0, 1));
    expect(proposal.action.guess, GuessType.inBetween);
    expect(proposal.confidence, 1);
    expect(proposal.expectedDrinks, 0);
  });

  test('the async UI path carries the explanation and estimates', () async {
    final game = WindowGameEngine(['Ada', 'Ben'], seed: 9);
    final proposal = await WindowRlPolicy.proposeStatistics(game);
    expect(proposal.explanation, isNotEmpty);
    expect(proposal.expectedDrinks, isNonNegative);
    expect(
      WindowRlCodec.validActions(game).map((a) => a.index),
      contains(proposal.action.index),
    );
  });

  test('does not suggest an action while confirmation is pending', () {
    final game = WindowGameEngine(['Ada'], seed: 2);
    final target = game.validSelectablePositions().first;
    final option = game.getValidOptionsForCard(target).first;
    final wrong =
        game.cardAt(target)! ~/ 4 > game.cardAt(option.neighbors.first)! ~/ 4
        ? GuessType.lower
        : GuessType.higher;
    game.applyGuess(target, option, wrong);
    expect(() => WindowRlPolicy.statisticsProposal(game), throwsStateError);
  });
}
