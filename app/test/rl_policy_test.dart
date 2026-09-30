import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/game_state_codec.dart';
import 'package:window_game/rl_policy.dart';

void main() {
  group('Window RL contract', () {
    test('encodes the fixed recurrent history size', () {
      final WindowGameEngine game = WindowGameEngine(<String>['Ada'], seed: 1);
      expect(
        WindowRlCodec.encodeHistory(game),
        hasLength(
          WindowRlContract.defaultHistoryLength *
              WindowRlContract.historyFeatureSize,
        ),
      );
    });

    test('records a public event after a legal guess', () {
      final WindowGameEngine game = WindowGameEngine(<String>['Ada'], seed: 7);
      final Position position = game.validSelectablePositions().first;
      final GuessOption option = game.getValidOptionsForCard(position).first;
      game.applyGuess(position, option, option.guesses.first);
      expect(game.recentEvents, hasLength(1));
      final PublicMoveEvent event = game.recentEvents.single;
      expect(event.actionIndex, inInclusiveRange(0, 299));
      expect(event.boardBefore, hasLength(windowLayout.length));
      expect(
        WindowRlCodec.encodeHistory(game),
        hasLength(
          WindowRlContract.defaultHistoryLength *
              WindowRlContract.historyFeatureSize,
        ),
      );
    });

    test('restoring serialized state preserves recurrent public history', () {
      final WindowGameEngine game = WindowGameEngine(
        <String>['Ada', 'Ben'],
        seed: 9,
      );
      final Position position = game.validSelectablePositions().first;
      final GuessOption option = game.getValidOptionsForCard(position).first;
      game.applyGuess(position, option, option.guesses.first);

      final GameState restoredState = GameStateCodec.decode(
        Map<Object?, Object?>.from(GameStateCodec.encode(game.exportState())),
      );
      final WindowGameEngine restored = WindowGameEngine.fromState(restoredState);
      expect(WindowRlCodec.encodeHistory(restored), WindowRlCodec.encodeHistory(game));
    });

    test('only emits valid action indices', () {
      final WindowGameEngine game = WindowGameEngine(<String>['Ada'], seed: 2);
      final List<PolicyAction> actions = WindowRlCodec.validActions(game);
      expect(actions, isNotEmpty);
      for (final PolicyAction action in actions) {
        expect(
          action.index,
          inInclusiveRange(0, WindowRlContract.actionSize - 1),
        );
      }
    });

    test('can preload the model before a proposal is requested', () async {
      final WindowRlPolicy policy = WindowRlPolicy();
      await policy.preload();
      expect(
        policy.availabilityMessage,
        isNot(contains('will load when you request a proposal')),
      );
    });

    test('reserves a policy action for ending a legal turn', () {
      const PolicyAction pass = PolicyAction.pass();
      expect(pass.isPass, isTrue);
      expect(pass.index, WindowRlContract.passActionIndex);
      expect(pass.label, 'end turn (pass)');
      expect(WindowRlContract.actionSize, WindowRlContract.cardActionSize + 1);
    });

    test(
      'offers a statistics fallback when a runtime is unavailable',
      () async {
        final WindowGameEngine game = WindowGameEngine(<String>[
          'Ada',
        ], seed: 3);
        final AiMoveProposal? proposal = await WindowRlPolicy().propose(game);
        expect(proposal, isNotNull);
        expect(proposal!.source, 'Pure statistics');
        expect(proposal.confidence, inInclusiveRange(0, 1));
      },
    );
  });
}
