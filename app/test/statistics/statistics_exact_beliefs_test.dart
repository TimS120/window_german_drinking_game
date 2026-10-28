import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/policy_core.dart';

List<List<int?>> blank() => List.generate(5, (_) => List<int?>.filled(6, null));

GameState publicState(List<List<int?>> board, List<PublicMoveEvent> events) =>
    GameState(
      players: ['A', 'B'],
      currentPlayerIndex: 0,
      turnStartFaceUp: 5,
      deck: [],
      cardGrid: board,
      faceUp: board
          .map((row) => row.map((card) => card != null).toList())
          .toList(),
      pendingRemovals: {},
      pendingPenalty: 0,
      mustSelectAdjacentToHandle: true,
      turnCanEnd: false,
      stats: {'A': const PlayerStats(), 'B': const PlayerStats()},
      recentEvents: events,
    );

void main() {
  test(
    'nested card probabilities agree with all 50400 feasible assignments',
    () {
      const target = Position(2, 4);
      const older = [Position(1, 4), Position(2, 3), Position(3, 4)];
      final before = blank();
      before[2][5] = 32;
      int next = 0;
      for (int r = 0; r < 5; r++) {
        for (int c = 0; c < 6; c++) {
          final p = Position(r, c);
          if (!windowLayout[r][c] ||
              p == target ||
              older.contains(p) ||
              p == handlePosition) {
            continue;
          }
          before[r][c] = next++;
        }
      }
      expect(next, 17);
      final removed = blank();
      removed[2][5] = 32;
      removed[2][4] = 33;
      final now = before.map((r) => List<int?>.from(r)).toList();
      now[2][5] = 20;
      final event = PublicMoveEvent(
        boardBefore: before,
        actionIndex: 160,
        outcome: 'wrong',
        removedCards: removed,
        mustSelectAdjacentToHandle: true,
        turnCanEnd: false,
      );
      final game = WindowGameEngine.fromState(publicState(now, [event]));
      final snapshot = StatisticsPolicy.inspectBeliefs(game);
      expect(snapshot.diagnostics.historyFallback, isFalse);

      // Older hidden slots cannot contain either publicly returned ace. The
      // replacement slot can contain either, subject to all cards being unique.
      final visible = now.expand((r) => r).whereType<int>().toSet();
      final pool = [
        for (int id = 0; id < 36; id++)
          if (!visible.contains(id)) id,
      ];
      final oldPool = pool.where((id) => id != 32 && id != 33).toList();
      expect(pool, hasLength(18));
      expect(oldPool, hasLength(16));
      final frequencies = List.generate(4, (_) => List<int>.filled(9, 0));
      int assignments = 0;
      for (final a in oldPool) {
        for (final b in oldPool) {
          if (b == a) continue;
          for (final c in oldPool) {
            if (c == a || c == b) continue;
            for (final d in pool) {
              if ([a, b, c].contains(d)) continue;
              frequencies[0][a ~/ 4]++;
              frequencies[1][b ~/ 4]++;
              frequencies[2][c ~/ 4]++;
              frequencies[3][d ~/ 4]++;
              assignments++;
            }
          }
        }
      }
      expect(assignments, 50400);
      final positions = [...older, target];
      for (int slot = 0; slot < 4; slot++) {
        for (int rank = 0; rank < 9; rank++) {
          expect(
            snapshot.ranks[positions[slot]]![rank],
            closeTo(frequencies[slot][rank] / assignments, 1e-12),
          );
        }
      }
    },
  );

  test(
    'valid long public histories never exhaust a sampled belief population',
    () {
      for (int seed = 1; seed <= 8; seed++) {
        final game = WindowGameEngine(['A', 'B'], seed: seed);
        for (int step = 0; step < 80; step++) {
          final target = game.validSelectablePositions().first;
          final option = game.getValidOptionsForCard(target).first;
          final rank = game.cardAt(target)! ~/ 4;
          final boundary = game.cardAt(option.neighbors.first)! ~/ 4;
          final result = game.applyGuess(
            target,
            option,
            rank > boundary ? GuessType.lower : GuessType.higher,
          );
          expect(result.requiresRemovalConfirmation, isTrue);
          game.confirmRemovals();
        }
        for (final history in [0, 4, 16, 32]) {
          final snapshot = StatisticsPolicy.inspectBeliefs(
            game,
            historyLength: history,
          );
          expect(snapshot.diagnostics.historyFallback, isFalse);
          for (final ranks in snapshot.ranks.values) {
            expect(ranks.reduce((a, b) => a + b), closeTo(1, 1e-12));
            expect(ranks, everyElement(inInclusiveRange(0, 1)));
          }
        }
      }
    },
  );

  test(
    'inconsistent historical observations fall back to the current board',
    () {
      final game = WindowGameEngine(['A'], seed: 7);
      final current = game.publicObservation().cardGrid;
      final bad = current.map((r) => List<int?>.from(r)).toList();
      bad[0][0] = 99;
      final event = PublicMoveEvent(
        boardBefore: bad,
        actionIndex: 300,
        outcome: 'pass',
        removedCards: blank(),
        mustSelectAdjacentToHandle: true,
        turnCanEnd: false,
      );
      final withBadHistory = WindowGameEngine.fromState(
        publicState(current, [event]),
      );
      final actual = StatisticsPolicy.inspectBeliefs(withBadHistory);
      final prior = StatisticsPolicy.inspectBeliefs(
        withBadHistory,
        historyLength: 0,
      );
      expect(actual.diagnostics.historyFallback, isTrue);
      expect(actual.ranks, prior.ranks);
    },
  );
  test('publicly deduced certain finish overrides uncertain search safely', () {
    const target = Position(1, 4);
    const wrongSpot = Position(2, 2);
    const holes = [target, wrongSpot, Position(0, 1), Position(4, 1)];
    final visible = blank();
    visible[2][1] = 32;
    visible[2][3] = 33;
    final openIds = [
      34,
      35,
      for (int id = 0; id < 32; id++)
        if (![4, 5, 6, 7].contains(id)) id,
    ];
    int next = 0;
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        if (windowLayout[r][c] &&
            !holes.contains(Position(r, c)) &&
            visible[r][c] == null) {
          visible[r][c] = openIds[next++];
        }
      }
    }
    final private = visible.map((row) => List<int?>.from(row)).toList();
    private[1][4] = 4;
    private[2][2] = 7;
    private[0][1] = 5;
    private[4][1] = 6;
    final used = private.expand((row) => row).whereType<int>().toSet();
    var game = WindowGameEngine.fromState(
      GameState(
        players: ['A', 'B'],
        currentPlayerIndex: 0,
        turnStartFaceUp: 18,
        deck: [
          for (int id = 0; id < 36; id++)
            if (!used.contains(id)) id,
        ],
        cardGrid: private,
        faceUp: visible
            .map((row) => row.map((id) => id != null).toList())
            .toList(),
        pendingRemovals: {},
        pendingPenalty: 0,
        mustSelectAdjacentToHandle: false,
        turnCanEnd: false,
        stats: {'A': const PlayerStats(), 'B': const PlayerStats()},
      ),
      seed: 2,
    );
    final wrong = game.getValidOptionsForCard(wrongSpot).first;
    game.applyGuess(wrongSpot, wrong, GuessType.inBetween);
    expect(game.pendingRemovals, hasLength(19));
    game.confirmRemovals();
    // Pick one physically possible shuffle. No hidden truth from this fixture
    // is supplied to the adviser; all four aces were publicly returned above.
    final after = game.exportState();
    final dealt = blank();
    dealt[1][4] = 4;
    dealt[0][1] = 5;
    dealt[4][1] = 6;
    dealt[0][4] = 0;
    dealt[2][4] = 28;
    final pool = [
      for (int id = 0; id < 32; id++)
        if (![0, 4, 5, 6, 28].contains(id)) id,
    ];
    next = 0;
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        if (windowLayout[r][c] && dealt[r][c] == null) {
          dealt[r][c] = pool[next++];
        }
      }
    }
    final placed = dealt.expand((row) => row).whereType<int>().toSet();
    game = WindowGameEngine.fromState(
      GameState(
        players: after.players,
        currentPlayerIndex: after.currentPlayerIndex,
        turnStartFaceUp: after.turnStartFaceUp,
        deck: [
          for (int id = 0; id < 36; id++)
            if (!placed.contains(id)) id,
        ],
        cardGrid: dealt,
        faceUp: after.faceUp,
        pendingRemovals: {},
        pendingPenalty: 0,
        mustSelectAdjacentToHandle: true,
        turnCanEnd: false,
        stats: after.stats,
        recentEvents: after.recentEvents,
      ),
    );
    while (game.countFaceUpCards() < 21) {
      final position = game.validSelectablePositions().firstWhere(
        (p) => p != target,
      );
      final option = game.getValidOptionsForCard(position).first;
      final rank = game.cardAt(position)! ~/ 4;
      final first = game.cardAt(option.neighbors.first)! ~/ 4;
      final last = game.cardAt(option.neighbors.last)! ~/ 4;
      final guess = option.type == GuessOptionType.inBetween
          ? rank >= (first < last ? first : last) &&
                    rank <= (first > last ? first : last)
                ? GuessType.inBetween
                : GuessType.outside
          : rank == first
          ? GuessType.same
          : rank > first
          ? GuessType.higher
          : GuessType.lower;
      final result = game.applyGuess(position, option, guess);
      expect(result.correct, isTrue);
      if (result.requiresSameConfirmation) game.confirmSameGuess();
    }
    final drinksBefore = game.playerStats('A').drinks;
    final proposal = StatisticsPolicy.propose(
      game,
      historyLength: 32,
      fixedRounds: 3,
    );
    expect(proposal.action.position, target);
    expect(proposal.action.guess, GuessType.inBetween);
    expect(proposal.confidence, 1);
    expect(proposal.expectedDrinks, 0);
    expect(proposal.statisticsDiagnostics!.guaranteedFinish, isTrue);
    final option = game.getValidOptionsForCard(target).single;
    expect(
      game.applyGuess(target, option, proposal.action.guess!).correct,
      isTrue,
    );
    expect(game.gameEnded, isTrue);
    expect(game.playerStats('A').drinks, drinksBefore);
  });
}
