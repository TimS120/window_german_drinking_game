import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/policy_core.dart';
import 'package:window_game/proposal_cycle.dart';
import 'package:window_game/room_social.dart';

AiMoveProposal choice(GuessType guess) => AiMoveProposal(
  action: PolicyAction.guess(
    position: const Position(2, 4),
    orientation: Orientation.horizontal,
    guess: guess,
  ),
  confidence: .5,
  source: 'Test',
);

void main() {
  final pair = [choice(GuessType.higher), choice(GuessType.lower)];
  test(
    'same-method repetition alternates; switching methods starts at best',
    () {
      final cycle = ProposalCycle();
      AiMoveProposal click(String method) => cycle.accept(
        'board',
        method,
        cycle.cached('board', method) ?? pair,
        cycle.nextRank('board', method),
      )!;
      expect(click('rl').action.guess, GuessType.higher);
      expect(click('rl').rank, 1);
      expect(click('rl').action.guess, GuessType.higher);
      expect(click('statistics').rank, 0);
      expect(click('statistics').action.guess, GuessType.lower);
      expect(click('rl').rank, 0);
    },
  );
  test('new position and explicit move invalidation reset rankings', () {
    final cycle = ProposalCycle();
    cycle.accept('old', 'rl', pair, 0);
    cycle.accept('old', 'rl', pair, 1);
    expect(cycle.nextRank('new', 'rl'), 0);
    expect(cycle.cached('new', 'rl'), isNull);
    cycle.clear();
    expect(cycle.nextRank('old', 'rl'), 0);
    expect(cycle.cached('old', 'rl'), isNull);
  });
  test('one available action does not fabricate an alternative; cache is immutable', () {
    final cycle = ProposalCycle();
    cycle.accept('board', 'rl', pair.take(1).toList(), 0);
    expect(cycle.nextRank('board', 'rl'), 0);
    expect(() => cycle.cached('board', 'rl')!.clear(), throwsUnsupportedError);
    expect(cycle.accept('board', 'rl', [], 1), isNull);
    expect(cycle.cached('board', 'rl'), isNull);
  });
  test('second-best rank survives shared proposal serialization; old payloads work', () {
    final encoded = encodeSharedProposal(pair.last.withRank(1));
    expect(decodeSharedProposal(encoded)!.rank, 1);
    encoded.remove('rank');
    expect(decodeSharedProposal(encoded)!.rank, 0);
  });
}
