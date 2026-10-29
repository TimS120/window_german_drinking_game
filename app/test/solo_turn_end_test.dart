import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/game_state_codec.dart';
import 'package:window_game/policy_core.dart';

void main() {
  final fixtures = jsonDecode(
    File('../ml/fixtures/recurrent_contract_v5.json').readAsStringSync(),
  ) as List<dynamic>;

  WindowGameEngine afterSuccess(int players) {
    final fixture = fixtures.firstWhere(
      (dynamic item) => item['name'] == 'players_${players}_correct',
    );
    return WindowGameEngine.fromState(
      GameStateCodec.decode(
        Map<Object?, Object?>.from(fixture['state'] as Map),
      ),
    );
  }

  test(
    'solo success never permits passing or changes state through endTurn',
    () {
      final game = afterSuccess(1);
      // Keep the established observation/history encoding for existing weights.
      expect(game.turnCanEnd, isTrue);
      expect(WindowRlCodec.encodeHistory(game, historyLength: 1)[129], 1);
      expect(game.canEndTurn, isFalse);
      expect(game.snapshot().turnCanEnd, isFalse);
      final actions = WindowRlCodec.validActions(game);
      expect(actions, isNotEmpty);
      expect(actions.any((action) => action.isPass), isFalse);
      final before = jsonEncode(GameStateCodec.encode(game.exportState()));
      game.endTurn();
      expect(jsonEncode(GameStateCodec.encode(game.exportState())), before);
      final restored = WindowGameEngine.fromState(game.exportState());
      expect(restored.canEndTurn, isFalse);
      expect(
        WindowRlCodec.validActions(restored).any((a) => a.isPass),
        isFalse,
      );
    },
  );

  test('solo progress is recorded when its continuous turn completes', () {
    final state = GameStateCodec.encode(afterSuccess(1).exportState());
    final grid = state['cardGrid'] as List;
    state['faceUp'] = [
      for (final row in grid) [for (final card in row as List) card != null],
    ];
    (state['faceUp'] as List)[2][4] = false;
    state['mustSelectAdjacentToHandle'] = false;
    final game = WindowGameEngine.fromState(GameStateCodec.decode(state));
    const position = Position(2, 4);
    final option = game.getValidOptionsForCard(position).first;
    final rank = game.cardAt(position)! ~/ 4;
    final neighbors = option.neighbors.map((p) => game.cardAt(p)! ~/ 4).toList()
      ..sort();
    final guess = option.guesses.firstWhere(
      (guess) => switch (guess) {
        GuessType.higher => rank > neighbors.single,
        GuessType.lower => rank < neighbors.single,
        GuessType.same => rank == neighbors.single,
        GuessType.inBetween =>
          rank >= neighbors.first && rank <= neighbors.last,
        GuessType.outside => rank < neighbors.first || rank > neighbors.last,
      },
    );
    final result = game.applyGuess(position, option, guess);
    if (result.requiresSameConfirmation) game.confirmSameGuess();
    expect(game.gameEnded, isTrue);
    expect(game.playerStats('Ada').changedCards, 17);
    expect(game.canEndTurn, isFalse);
  });

  for (final players in [2, 3, 4]) {
    test('$players players can still pass after a successful guess', () {
      final game = afterSuccess(players);
      expect(game.canEndTurn, isTrue);
      expect(game.snapshot().turnCanEnd, isTrue);
      expect(WindowRlCodec.validActions(game).any((a) => a.isPass), isTrue);
      game.endTurn();
      expect(game.currentPlayer, 'Ben');
      expect(game.canEndTurn, isFalse);
    });
  }
}
