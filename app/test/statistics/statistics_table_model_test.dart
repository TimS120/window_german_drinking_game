import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/game_state_codec.dart';
import 'package:window_game/policy_core.dart';

void revealCorrectCard(WindowGameEngine game) {
  final target = game.validSelectablePositions().first;
  final option = game.getValidOptionsForCard(target).first;
  final rank = game.cardAt(target)! ~/ 4;
  final boundary = game.cardAt(option.neighbors.first)! ~/ 4;
  final guess = rank == boundary
      ? GuessType.same
      : rank > boundary
      ? GuessType.higher
      : GuessType.lower;
  final result = game.applyGuess(target, option, guess);
  if (result.requiresSameConfirmation) game.confirmSameGuess();
  expect(result.correct, isTrue);
}

void main() {
  test('rejects invalid seat-cycle input', () {
    expect(() => StatisticsTableModel(0), throwsArgumentError);
    final table = StatisticsTableModel(2);
    expect(
      () => table.opponentStyles(ownerIndex: 2, scenario: 0),
      throwsRangeError,
    );
    expect(
      () => table.opponentStyles(ownerIndex: 0, scenario: -1),
      throwsArgumentError,
    );
    expect(
      () =>
          table.scheduledReveals(remaining: -1, currentIndex: 0, canEnd: false),
      throwsArgumentError,
    );
  });

  for (int count = 1; count <= 4; count++) {
    test(
      '$count players: every opponent has balanced fixed style hypotheses',
      () {
        final table = StatisticsTableModel(count);
        for (int owner = 0; owner < count; owner++) {
          for (int group = 0; group < 4; group++) {
            final profiles = [
              for (
                int scenario = group * 3;
                scenario < group * 3 + 3;
                scenario++
              )
                table.opponentStyles(ownerIndex: owner, scenario: scenario),
            ];
            for (int seat = 0; seat < count; seat++) {
              final styles = profiles.map((p) => p[seat]).toList();
              expect(
                styles,
                seat == owner ? [-1, -1, -1] : unorderedEquals([0, 1, 2]),
              );
            }
          }
        }
      },
    );

    test(
      '$count players: remaining reveals follow the actual cyclic seat order',
      () {
        final table = StatisticsTableModel(count);
        for (int current = 0; current < count; current++) {
          for (final canEnd in [false, true]) {
            for (int remaining = 0; remaining <= 22; remaining++) {
              final expected = List<int>.filled(count, 0);
              int seat = (current + (canEnd && count > 1 ? 1 : 0)) % count;
              for (int turn = 0; turn < remaining; turn++) {
                expected[seat]++;
                seat = (seat + 1) % count;
              }
              expect(
                table.scheduledReveals(
                  remaining: remaining,
                  currentIndex: current,
                  canEnd: canEnd,
                ),
                expected,
              );
            }
          }
        }
      },
    );

    test(
      '$count players: initial and continuing advice is legal and public-only',
      () {
        final game = WindowGameEngine(
          List.generate(count, (i) => 'P$i'),
          seed: 17,
        );
        for (int stage = 0; stage < 2; stage++) {
          final before = GameStateCodec.encode(game.exportState());
          final public = game.publicObservation();
          expect(public.deck, isEmpty);
          for (int r = 0; r < 5; r++) {
            for (int c = 0; c < 6; c++) {
              if (!public.faceUp[r][c]) expect(public.cardGrid[r][c], isNull);
            }
          }
          final host = StatisticsPolicy.propose(game, fixedRounds: 3);
          final guest = StatisticsPolicy.proposeFromState(
            public,
            fixedRounds: 3,
          );
          expect(host.action.index, guest.action.index);
          expect(host.confidence, guest.confidence);
          expect(host.expectedDrinks, guest.expectedDrinks);
          expect(host.expectedDrinks, isNonNegative);
          expect(host.confidence, inInclusiveRange(0, 1));
          expect(host.explanation, isNotEmpty);
          expect(
            WindowRlCodec.validActions(game).map((a) => a.index),
            contains(host.action.index),
          );
          if (count == 1) expect(host.action.isPass, isFalse);
          expect(GameStateCodec.encode(game.exportState()), before);
          if (stage == 0) revealCorrectCard(game);
        }
      },
    );
  }

  test('mixed tables are represented after homogeneous stress cases', () {
    for (final count in [3, 4]) {
      final table = StatisticsTableModel(count);
      final pure = table.opponentStyles(ownerIndex: count - 1, scenario: 0);
      final mixed = table.opponentStyles(ownerIndex: count - 1, scenario: 3);
      expect(pure.where((s) => s >= 0).toSet(), hasLength(1));
      expect(mixed.where((s) => s >= 0).toSet().length, greaterThan(1));
    }
  });

  test('seat order can finish the window before the owner plays again', () {
    final table = StatisticsTableModel(4);
    expect(
      table.scheduledReveals(remaining: 1, currentIndex: 0, canEnd: true),
      [0, 1, 0, 0],
    );
    expect(
      table.scheduledReveals(remaining: 1, currentIndex: 0, canEnd: false),
      [1, 0, 0, 0],
    );
  });

  test('player count does not change card rank evidence', () {
    final solo = WindowGameEngine(['Solo'], seed: 42);
    final four = WindowGameEngine(['A', 'B', 'C', 'D'], seed: 42);
    expect(
      StatisticsPolicy.rankProbabilities(solo),
      StatisticsPolicy.rankProbabilities(four),
    );
  });
}
