import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/rl_policy.dart';

void main() {
  group('Window RL contract', () {
    test('encodes the fixed observation size', () {
      final WindowGameEngine game = WindowGameEngine(<String>['Ada'], seed: 1);
      expect(
        WindowRlCodec.encodeObservation(game),
        hasLength(WindowRlContract.featureSize),
      );
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
