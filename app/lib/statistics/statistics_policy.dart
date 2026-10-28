part of '../policy_core.dart';

/// Investigation metadata; these counters never influence action selection.
class StatisticsDiagnostics {
  const StatisticsDiagnostics({
    required this.historyLimit,
    required this.historyEvents,
    required this.historyFallback,
    required this.beliefMicros,
    required this.searchRounds,
    required this.elapsedMicros,
    this.searchHistoryFallback = false,
    this.guaranteedFinish = false,
    this.probabilityMicros = 0,
  });
  final int historyLimit;
  final int historyEvents;

  /// The direct reported-probability calculation rejected inconsistent history.
  final bool historyFallback;

  /// The strategic sampler lost compatible samples; meaningful when search ran.
  final bool searchHistoryFallback;
  final bool guaranteedFinish;
  final int probabilityMicros;
  final int beliefMicros;
  final int searchRounds;
  final int elapsedMicros;
}

class StatisticsBeliefSnapshot {
  const StatisticsBeliefSnapshot(this.ranks, this.diagnostics);
  final Map<Position, List<double>> ranks;
  final StatisticsDiagnostics diagnostics;
}

class StatisticsPolicy {
  static const int defaultHistoryLength = 16;
  static const int maxHistoryLength = 32;

  static int checkHistoryLength(int length) => RangeError.checkValueInInterval(
    length,
    0,
    maxHistoryLength,
    'historyLength',
  );

  static AiMoveProposal proposeFromState(
    GameState publicState, {
    int? fixedRounds,
    int historyLength = defaultHistoryLength,
    int budgetMilliseconds = 180,
    int? scenarioSeed,
  }) => propose(
    WindowGameEngine.fromState(publicState),
    fixedRounds: fixedRounds,
    historyLength: historyLength,
    budgetMilliseconds: budgetMilliseconds,
    scenarioSeed: scenarioSeed,
  );

  static AiMoveProposal propose(
    WindowGameEngine game, {
    List<PolicyAction>? actions,
    int budgetMilliseconds = 180,
    int? fixedRounds,
    int historyLength = defaultHistoryLength,
    int? scenarioSeed,
  }) => _StatisticsAdvisor(
    game.publicObservation(maxEvents: checkHistoryLength(historyLength)),
    budgetMilliseconds: budgetMilliseconds,
    fixedRounds: fixedRounds,
    historyLength: historyLength,
    scenarioSeed: scenarioSeed,
  ).propose(actions: actions);

  static List<({PolicyAction action, double success, int penalty})>
  immediateMoveRisks(WindowGameEngine game) => [
    for (final candidate in _StatisticsAdvisor._publicRisks(
      WindowGameEngine.fromState(game.publicObservation(maxEvents: 0)),
    ))
      (
        action: candidate.action,
        success: candidate.success,
        penalty: candidate.penalty,
      ),
  ];

  static Map<Position, List<double>> rankProbabilities(
    WindowGameEngine game, {
    int historyLength = defaultHistoryLength,
  }) => inspectBeliefs(game, historyLength: historyLength).ranks;

  static StatisticsBeliefSnapshot inspectBeliefs(
    WindowGameEngine game, {
    int historyLength = defaultHistoryLength,
  }) {
    final public = game.publicObservation(
      maxEvents: checkHistoryLength(historyLength),
    );
    final watch = Stopwatch()..start();
    final beliefs = _ExactCardBeliefs(public);
    final beliefMicros = watch.elapsedMicroseconds;
    final ranks = {
      for (int r = 0; r < 5; r++)
        for (int c = 0; c < 6; c++)
          if (windowLayout[r][c] && !public.faceUp[r][c])
            Position(r, c): beliefs.ranksAt(r * 6 + c),
    };
    return StatisticsBeliefSnapshot(
      ranks,
      StatisticsDiagnostics(
        historyLimit: historyLength,
        historyEvents: public.recentEvents.length,
        historyFallback: !beliefs.historyConsistent,
        beliefMicros: beliefMicros,
        searchRounds: 0,
        elapsedMicros: watch.elapsedMicroseconds,
      ),
    );
  }
}
