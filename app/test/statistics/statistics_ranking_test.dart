import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/game_state_codec.dart';
import 'package:window_game/policy_core.dart';

void main() {
  for (final count in [1, 2, 3, 4]) {
    test(
      '$count players: alternatives share a search and stay legal/public',
      () {
        final game = WindowGameEngine(
          List.generate(count, (i) => 'P$i'),
          seed: 17,
        );
        final before = jsonEncode(GameStateCodec.encode(game.exportState()));
        final ranked = StatisticsPolicy.rankedProposals(game, fixedRounds: 3);
        final single = StatisticsPolicy.propose(game, fixedRounds: 3);
        expect(ranked.length, greaterThanOrEqualTo(2));
        expect(ranked.first.action.index, single.action.index);
        expect(ranked.first.expectedDrinks, single.expectedDrinks);
        expect(ranked.map((p) => p.action.index).toSet().length, ranked.length);
        final legal = WindowRlCodec.validActions(game)
            .map((a) => a.index)
            .toSet();
        for (int i = 0; i < ranked.length; i++) {
          expect(legal, contains(ranked[i].action.index));
          expect(ranked[i].rank, i);
          expect(ranked[i].statisticsDiagnostics!.searchRounds, 3);
          expect(ranked[i].confidence, inInclusiveRange(0, 1));
        }
        final sanitized = StatisticsPolicy.rankedProposals(
          WindowGameEngine.fromState(game.publicObservation()),
          fixedRounds: 3,
        );
        expect(
          sanitized.map((p) => p.action.index),
          ranked.map((p) => p.action.index),
        );
        expect(jsonEncode(GameStateCodec.encode(game.exportState())), before);
        if (count == 1) expect(ranked.any((p) => p.action.isPass), isFalse);
      },
    );
  }
}
