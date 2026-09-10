import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/game_state_codec.dart';

void main() {
  group('WindowGameEngine', () {
    test('deals the 22-slot window with only corners and handle face-up', () {
      final WindowGameEngine game = WindowGameEngine(<String>[
        'Anna',
        'Ben',
      ], seed: 1);
      expect(game.countFaceUpCards(), 5);
      expect(game.snapshot().deckSize, 14);
      for (final Position corner in cornerPositions) {
        expect(game.isFaceUp(corner), isTrue);
      }
      expect(game.isFaceUp(handlePosition), isTrue);
      expect(game.validSelectablePositions(), <Position>{const Position(2, 4)});
    });

    test('wrong first guess removes the open handle chain and restores the handle rule', () {
      final WindowGameEngine game = WindowGameEngine(<String>[
        'Anna',
        'Ben',
      ], seed: 2);
      const Position target = Position(2, 4);
      final GuessOption option = game.getValidOptionsForCard(target).single;
      final int targetRank = game.cardAt(target)! ~/ 4;
      final int handleRank = game.cardAt(handlePosition)! ~/ 4;
      final GuessType wrong = targetRank > handleRank
          ? GuessType.lower
          : GuessType.higher;
      final GuessResult result = game.applyGuess(target, option, wrong);
      expect(result.requiresRemovalConfirmation, isTrue);
      expect(
        game.pendingRemovals,
        containsAll(<Position>[target, handlePosition]),
      );
      expect(
        game.isFaceUp(target),
        isTrue,
        reason: 'The wrong card stays revealed until removal is confirmed.',
      );
      expect(game.snapshot().stats['Anna']!.wrong, 1);
      expect(
        game.snapshot().stats['Anna']!.drinks,
        game.pendingRemovals.length,
      );
      game.confirmRemovals();
      expect(game.isFaceUp(handlePosition), isTrue);
      expect(game.mustSelectAdjacentToHandle, isTrue);
      expect(game.validSelectablePositions(), <Position>{target});
    });

    test('same guess makes every other player drink after confirmation', () {
      WindowGameEngine? matching;
      for (int seed = 0; seed < 200; seed++) {
        final WindowGameEngine candidate = WindowGameEngine(<String>[
          'Anna',
          'Ben',
          'Carla',
        ], seed: seed);
        if (candidate.cardAt(const Position(2, 4))! ~/ 4 ==
            candidate.cardAt(handlePosition)! ~/ 4) {
          matching = candidate;
          break;
        }
      }
      expect(matching, isNotNull);
      final WindowGameEngine game = matching!;
      final GuessResult pending = game.applyGuess(
        const Position(2, 4),
        game.getValidOptionsForCard(const Position(2, 4)).single,
        GuessType.same,
      );
      expect(pending.requiresSameConfirmation, isTrue);
      expect(game.snapshot().stats['Ben']!.drinks, 0);
      final GuessResult result = game.confirmSameGuess();
      expect(result.correct, isTrue);
      expect(game.snapshot().stats['Ben']!.drinks, 1);
      expect(game.snapshot().stats['Carla']!.drinks, 1);
      expect(game.snapshot().turnCanEnd, isTrue);
    });

    test(
      'in-between options win over a one-card comparison in another direction',
      () {
        final WindowGameEngine game = WindowGameEngine.fromState(
          _stateForOptions(),
        );
        final List<GuessOption> options = game.getValidOptionsForCard(
          const Position(2, 2),
        );
        expect(options, hasLength(1));
        expect(options.single.type, GuessOptionType.inBetween);
        expect(options.single.orientation, Orientation.horizontal);
        expect(options.single.neighbors, <Position>[
          const Position(2, 1),
          const Position(2, 3),
        ]);
      },
    );

    test('ending a turn advances player and records changed face-up cards', () {
      final WindowGameEngine game = WindowGameEngine(<String>[
        'Anna',
        'Ben',
      ], seed: 3);
      const Position target = Position(2, 4);
      final GuessOption option = game.getValidOptionsForCard(target).single;
      final int targetRank = game.cardAt(target)! ~/ 4;
      final int handleRank = game.cardAt(handlePosition)! ~/ 4;
      final GuessType correct = targetRank > handleRank
          ? GuessType.higher
          : (targetRank < handleRank ? GuessType.lower : GuessType.same);
      final GuessResult result = game.applyGuess(target, option, correct);
      if (result.requiresSameConfirmation) game.confirmSameGuess();
      expect(game.turnCanEnd, isTrue);
      game.endTurn();
      expect(game.currentPlayer, 'Ben');
      expect(game.snapshot().stats['Anna']!.changedCards, 1);
      expect(game.snapshot().stats['Ben']!.turns, 1);
    });

    test(
      'decodes a sparse Firebase public card grid at the full board size',
      () {
        final WindowGameEngine game = WindowGameEngine(<String>[
          'Anna',
        ], seed: 4);
        final Map<String, dynamic> encoded = GameStateCodec.encode(
          game.exportState(),
        );
        encoded['cardGrid'] = <String, Object?>{
          '0': <String, Object?>{'0': 3},
        };
        encoded['faceUp'] = <String, Object?>{
          '0': <String, Object?>{'0': true},
        };

        final GameState decoded = GameStateCodec.decode(
          Map<Object?, Object?>.from(encoded),
        );

        expect(decoded.cardGrid, hasLength(windowLayout.length));
        expect(decoded.cardGrid[0], hasLength(windowLayout.first.length));
        expect(decoded.cardGrid[0][0], 3);
        expect(decoded.cardGrid[2][4], isNull);
        expect(decoded.faceUp[0][0], isTrue);
        expect(decoded.faceUp[2][4], isFalse);
      },
    );
  });
}

GameState _stateForOptions() {
  final List<List<int?>> cards = List<List<int?>>.generate(
    5,
    (_) => List<int?>.filled(6, null),
  );
  final List<List<bool>> open = List<List<bool>>.generate(
    5,
    (_) => List<bool>.filled(6, false),
  );
  for (int row = 0; row < windowLayout.length; row++) {
    for (int column = 0; column < windowLayout[row].length; column++) {
      if (windowLayout[row][column]) cards[row][column] = 0;
    }
  }
  open[2][1] = true;
  open[2][3] = true;
  open[1][2] = true;
  return GameState(
    players: const <String>['Anna'],
    currentPlayerIndex: 0,
    turnStartFaceUp: 3,
    deck: const <int>[],
    cardGrid: cards,
    faceUp: open,
    pendingRemovals: const <Position>{},
    pendingPenalty: 0,
    mustSelectAdjacentToHandle: false,
    turnCanEnd: false,
    stats: const <String, PlayerStats>{'Anna': PlayerStats(turns: 1)},
  );
}
