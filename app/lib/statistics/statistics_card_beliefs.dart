part of '../policy_core.dart';

class _ExactCardBeliefs {
  _ExactCardBeliefs(this.state) {
    final events = state.recentEvents;
    var model = _CardDomains(
      events.isEmpty ? state.cardGrid : events.first.boardBefore,
    );
    bool valid = model.valid;
    for (final event in events) {
      if (!valid || !model.observe(event.boardBefore)) {
        valid = false;
        break;
      }
      if (event.outcome == 'wrong' &&
          (!model.observe(event.removedCards) ||
              !model.redeal(event.removedCards))) {
        valid = false;
        break;
      }
    }
    valid =
        valid &&
        model.observe(state.cardGrid) &&
        model.matches(state) &&
        model.feasible;
    historyConsistent = valid;
    if (!valid) model = _CardDomains(state.cardGrid);
    if (!model.matches(state) || !model.feasible) {
      throw StateError('Invalid public card observations.');
    }
    exchangeable = model.exchangeable;
    _ranks = model.marginals();
  }
  final GameState state;
  late final bool historyConsistent;
  late final bool exchangeable;
  late final Map<int, List<double>> _ranks;

  List<double> ranksAt(int index) {
    if (exchangeable) {
      final counts = List<int>.filled(9, 4);
      for (final card in state.cardGrid.expand((row) => row).whereType<int>()) {
        counts[card ~/ 4]--;
      }
      final total = counts.reduce((a, b) => a + b);
      return counts.map((count) => count / total).toList();
    }
    return List<double>.from(_ranks[index]!);
  }
}

/// Hidden slots exclude cards observed elsewhere since their last deal. Older
/// slots' allowed sets are subsets of younger slots' sets. Observing a card
/// removes it from every other hidden set; a redeal creates a widest new set.
/// Full shuffling makes all compatible assignments equally likely. Assigning
/// narrowest sets first is uniform: every subsequent set loses the same number
/// of cards regardless of which earlier cards were assigned.
class _CardDomains {
  _CardDomains(List<List<int?>> board) {
    final visible = <int>{};
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        final card = board[r][c];
        if (card == null) continue;
        if (!windowLayout[r][c] ||
            card < 0 ||
            card >= 36 ||
            !visible.add(card)) {
          valid = false;
          continue;
        }
        cards[r * 6 + c] = card;
      }
    }
    final unseen = {
      for (int card = 0; card < 36; card++)
        if (!visible.contains(card)) card,
    };
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        if (windowLayout[r][c] && cards[r * 6 + c] == null) {
          domains[r * 6 + c] = Set<int>.from(unseen);
        }
      }
    }
  }
  final cards = List<int?>.filled(30, null);
  final domains = List<Set<int>?>.filled(30, null);
  bool valid = true;

  List<int> get ordered =>
      [
        for (int i = 0; i < 30; i++)
          if (domains[i] != null) i,
      ]..sort((a, b) {
        final size = domains[a]!.length.compareTo(domains[b]!.length);
        return size == 0 ? a.compareTo(b) : size;
      });

  bool get feasible {
    if (!valid) return false;
    final slots = ordered;
    for (int i = 0; i < slots.length; i++) {
      final domain = domains[slots[i]]!;
      if (domain.length <= i) return false;
      if (i > 0 && !domain.containsAll(domains[slots[i - 1]]!)) return false;
    }
    return true;
  }

  bool get exchangeable {
    final unseen = 36 - cards.whereType<int>().length;
    return domains.whereType<Set<int>>().every(
      (domain) => domain.length == unseen,
    );
  }

  bool observe(List<List<int?>> board) {
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        final card = board[r][c];
        if (card == null) continue;
        final index = r * 6 + c;
        if (!windowLayout[r][c] || card < 0 || card >= 36) return false;
        if (cards[index] != null) {
          if (cards[index] != card) return false;
          continue;
        }
        if (!(domains[index]?.contains(card) ?? false)) return false;
        cards[index] = card;
        domains[index] = null;
        for (final domain in domains.whereType<Set<int>>()) {
          domain.remove(card);
        }
      }
    }
    return true;
  }

  bool redeal(List<List<int?>> removed) {
    final spots = <int>[];
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        if (removed[r][c] == null) continue;
        final index = r * 6 + c;
        if (cards[index] != removed[r][c]) return false;
        spots.add(index);
      }
    }
    for (final index in spots) {
      cards[index] = null;
    }
    final visible = cards.whereType<int>().toSet();
    final pool = {
      for (int card = 0; card < 36; card++)
        if (!visible.contains(card)) card,
    };
    for (final index in spots) {
      domains[index] = Set<int>.from(pool);
    }
    return true;
  }

  bool matches(GameState state) {
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        if (!windowLayout[r][c]) continue;
        if (state.faceUp[r][c] != (cards[r * 6 + c] != null)) return false;
        if (state.cardGrid[r][c] != cards[r * 6 + c]) return false;
      }
    }
    return true;
  }

  Map<int, List<double>> marginals() {
    final result = <int, List<double>>{};
    final available = List<double>.generate(
      36,
      (card) => cards.contains(card) ? 0 : 1,
    );
    final slots = ordered;
    int assigned = 0;
    while (assigned < slots.length) {
      final domain = domains[slots[assigned]]!;
      int groupEnd = assigned + 1;
      while (groupEnd < slots.length &&
          domains[slots[groupEnd]]!.length == domain.length) {
        groupEnd++;
      }
      final remaining = domain.length - assigned;
      final ranks = List<double>.filled(9, 0);
      for (final card in domain) {
        ranks[card ~/ 4] += available[card] / remaining;
      }
      for (int i = assigned; i < groupEnd; i++) {
        result[slots[i]] = List<double>.from(ranks);
      }
      final survival = (remaining - (groupEnd - assigned)) / remaining;
      for (final card in domain) {
        available[card] *= survival;
      }
      assigned = groupEnd;
    }
    return result;
  }
}
