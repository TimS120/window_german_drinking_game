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
    'fixed search rounds ignore the clock budget and reject unbalanced rounds',
    () {
      final game = WindowGameEngine(['Ada', 'Ben'], seed: 42);
      final first = WindowRlPolicy.statisticsProposal(
        game,
        fixedRounds: 3,
        budgetMilliseconds: 0,
      );
      final second = WindowRlPolicy.statisticsProposal(
        game,
        fixedRounds: 3,
        budgetMilliseconds: 10000,
      );
      expect(first.action.index, second.action.index);
      expect(first.expectedDrinks, second.expectedDrinks);
      expect(
        () => WindowRlPolicy.statisticsProposal(game, fixedRounds: 4),
        throwsArgumentError,
      );
    },
  );

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

  test(
    'untouched cards in the same cohort have identical rank probabilities',
    () {
      final before = blank();
      before[0][0] = 0;
      before[0][4] = 4;
      before[4][0] = 8;
      before[4][4] = 12;
      before[2][5] = 33;
      final removed = blank();
      removed[2][4] = 32;
      removed[2][5] = 33;
      final now = before.map((row) => List<int?>.from(row)).toList();
      now[2][5] = 16;
      final game = WindowGameEngine.fromState(
        publicState(
          now,
          events: [
            PublicMoveEvent(
              boardBefore: before,
              actionIndex: 160,
              outcome: 'wrong',
              removedCards: removed,
              mustSelectAdjacentToHandle: true,
              turnCanEnd: false,
            ),
          ],
        ),
      );
      final ranks = WindowRlPolicy.statisticsRankProbabilities(game);
      final expected = ranks[const Position(0, 1)]!;
      for (final entry in ranks.entries) {
        if (entry.key == const Position(2, 4)) continue;
        expect(
          entry.value,
          expected,
          reason: 'Geometry provides no rank evidence for untouched cards',
        );
      }
    },
  );

  test('equivalent orientations retain the same future estimate', () {
    final board = blank();
    board[0][0] = 0;
    board[0][4] = 4;
    board[4][0] = 8;
    board[4][4] = 12;
    board[2][5] = 16;
    board[2][1] = 1;
    board[2][3] = 32;
    board[1][2] = 2;
    board[3][2] = 33;
    final game = WindowGameEngine.fromState(publicState(board, canPass: true));
    final actions = WindowRlCodec.validActions(game)
        .where(
          (action) =>
              action.position == const Position(2, 2) &&
              action.guess == GuessType.inBetween,
        )
        .toList();
    expect(actions, hasLength(2));
    final shared = WindowRlPolicy.statisticsProposal(
      game,
      actions: actions,
      fixedRounds: 3,
    );
    for (final action in actions) {
      final single = WindowRlPolicy.statisticsProposal(
        game,
        actions: [action],
        fixedRounds: 3,
      );
      expect(shared.confidence, single.confidence);
      expect(shared.expectedDrinks, single.expectedDrinks);
    }
  });

  test('uncertain simulated gains do not trigger a risky extra turn', () {
    final game = WindowGameEngine(['Ada', 'Ben', 'Cat', 'Dan'], seed: 2);
    final target = game.validSelectablePositions().first;
    final option = game.getValidOptionsForCard(target).first;
    // Reveal one correct move to reach a public decision where passing is legal.
    final rank = game.cardAt(target)! ~/ 4;
    final boundary = game.cardAt(option.neighbors.first)! ~/ 4;
    final guess = rank == boundary
        ? GuessType.same
        : rank > boundary
        ? GuessType.higher
        : GuessType.lower;
    final result = game.applyGuess(target, option, guess);
    if (result.requiresSameConfirmation) game.confirmSameGuess();
    expect(game.turnCanEnd, isTrue);
    final proposal = WindowRlPolicy.statisticsProposal(game, fixedRounds: 3);
    expect(proposal.action.isPass, isTrue);
    expect(proposal.explanation, 'Pass; benefit of guessing is unclear');
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
