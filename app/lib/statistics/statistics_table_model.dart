part of '../policy_core.dart';

/// Public seat-cycle assumptions shared by search and its diagnostic tests.
/// These are fixed hypotheses, not learned descriptions of human opponents.
class StatisticsTableModel {
  StatisticsTableModel(this.playerCount) {
    if (playerCount < 1) throw ArgumentError.value(playerCount, 'playerCount');
  }

  final int playerCount;
  bool get hasOpponents => playerCount > 1;

  /// Each opponent keeps one style throughout a rollout. Every group of three
  /// scenarios covers all styles for each seat, while later groups also cover
  /// different styles at different seats. Two-player games retain the original three hypotheses.
  List<int> opponentStyles({required int ownerIndex, required int scenario}) {
    RangeError.checkValidIndex(ownerIndex, List.filled(playerCount, 0));
    if (scenario < 0) throw ArgumentError.value(scenario, 'scenario');
    final result = List<int>.filled(playerCount, -1);
    final profile = math.Random(4817 + scenario ~/ 3);
    for (int distance = 1; distance < playerCount; distance++) {
      final group = scenario ~/ 3;
      // Stress-test uniformly weak/strong tables first, then mixed tables as
      // more time permits. Marginals stay balanced for every individual seat.
      final offset = playerCount == 2 || group.isEven
          ? 0
          : group == 1
          ? distance - 1
          : profile.nextInt(3);
      result[(ownerIndex + distance) % playerCount] = (scenario + offset) % 3;
    }
    return result;
  }

  /// Tail approximation: one successful reveal per turn, then pass. Its exact
  /// seat accounting replaces fractional remaining/playerCount exposure. Real
  /// failures/redeals and extra guesses are handled in the preceding rollout.
  List<int> scheduledReveals({
    required int remaining,
    required int currentIndex,
    required bool canEnd,
  }) {
    if (remaining < 0) throw ArgumentError.value(remaining, 'remaining');
    RangeError.checkValidIndex(currentIndex, List.filled(playerCount, 0));
    final first =
        (currentIndex + (canEnd && hasOpponents ? 1 : 0)) % playerCount;
    final result = List<int>.filled(playerCount, remaining ~/ playerCount);
    for (int offset = 0; offset < remaining % playerCount; offset++) {
      result[(first + offset) % playerCount]++;
    }
    return result;
  }
}
