part of '../policy_core.dart';

/// Sequential importance sampling over physical cards. Cohorts contain cards
/// which are exchangeable given public observations; after a shuffle only the
/// deck and replacements form a new cohort. No actual hidden values enter here.
class _CardBeliefs {
  _CardBeliefs(this.state, this.random) {
    final events = state.recentEvents;
    final first = events.isEmpty ? state.cardGrid : events.first.boardBefore;
    particles = List.generate(128, (_) => _Particle.initial(first, random));
    for (final event in events) {
      if (!_observe(event.boardBefore)) break;
      if (event.outcome == 'wrong') {
        if (!_observe(event.removedCards)) break;
        for (final particle in particles) {
          particle.redeal(event.removedCards, random);
        }
      }
    }
    if (!_observe(state.cardGrid)) _reset();
  }

  final GameState state;
  final math.Random random;
  late List<_Particle> particles;
  bool historyConsistent = true;

  bool get exchangeable => particles.first.groups.every(
    (group) => group < 0 || group == particles.first.deckGroup,
  );

  List<double> ranksAt(int index) {
    if (exchangeable) {
      final counts = List<int>.filled(9, 4);
      for (final card in state.cardGrid.expand((row) => row).whereType<int>()) {
        counts[card ~/ 4]--;
      }
      final total = counts.reduce((a, b) => a + b);
      return counts.map((count) => count / total).toList();
    }
    // Cards in one cohort are exchangeable. Integrate their possible ranks
    // inside each particle before averaging particles, rather than promoting
    // random sampled placements to evidence about individual board positions.
    final result = List<double>.filled(9, 0);
    for (final particle in particles) {
      final group = particle.groups[index];
      final counts = List<int>.filled(9, 0);
      int total = 0;
      for (int slot = 0; slot < particle.cards.length; slot++) {
        if (particle.groups[slot] != group) continue;
        counts[particle.cards[slot]! ~/ 4]++;
        total++;
      }
      if (group == particle.deckGroup) {
        for (final card in particle.deck) {
          counts[card ~/ 4]++;
          total++;
        }
      }
      for (int rank = 0; rank < 9; rank++) {
        result[rank] += counts[rank] / total / particles.length;
      }
    }
    return result;
  }

  void _reset() {
    historyConsistent = false;
    particles = List.generate(
      128,
      (_) => _Particle.initial(state.cardGrid, random),
    );
  }

  bool _observe(List<List<int?>> board) {
    for (int row = 0; row < 5; row++) {
      for (int col = 0; col < 6; col++) {
        final card = board[row][col];
        if (card == null) continue;
        if (particles.every(
          (p) => p.groups[row * 6 + col] < 0 && p.cards[row * 6 + col] == card,
        )) {
          continue;
        }
        final weights = <double>[];
        double total = 0;
        for (final particle in particles) {
          final weight = particle.condition(row * 6 + col, card, random);
          weights.add(weight);
          total += weight;
        }
        if (total == 0) {
          _reset();
          return false;
        }
        // Systematic resampling keeps a fixed bound on memory and work.
        final next = <_Particle>[];
        final step = total / particles.length;
        final start = random.nextDouble() * step;
        int index = 0;
        double cumulative = weights.first;
        for (int n = 0; n < particles.length; n++) {
          final point = start + n * step;
          while (index < weights.length - 1 && point >= cumulative) {
            cumulative += weights[++index];
          }
          next.add(particles[index].copy());
        }
        particles = next;
      }
    }
    return true;
  }
}

class _Particle {
  _Particle(this.cards, this.groups, this.deck, this.deckGroup);

  factory _Particle.initial(List<List<int?>> board, math.Random random) {
    final visible = board.expand((row) => row).whereType<int>().toSet();
    final unseen = List.generate(36, (i) => i)
      ..removeWhere(visible.contains)
      ..shuffle(random);
    final cards = List<int?>.filled(30, null);
    final groups = List<int>.filled(30, -1);
    for (int row = 0; row < 5; row++) {
      for (int col = 0; col < 6; col++) {
        if (!windowLayout[row][col]) continue;
        final index = row * 6 + col;
        cards[index] = board[row][col] ?? unseen.removeLast();
        if (board[row][col] == null) groups[index] = 0;
      }
    }
    return _Particle(cards, groups, unseen, 0);
  }

  final List<int?> cards;
  final List<int> groups;
  final List<int> deck;
  int deckGroup;

  _Particle copy() => _Particle(
    List.from(cards),
    List.from(groups),
    List.from(deck),
    deckGroup,
  );

  double condition(int position, int card, math.Random random) {
    final group = groups[position];
    if (group < 0) return cards[position] == card ? 1 : 0;
    final slots = <int>[
      for (int i = 0; i < 30; i++)
        if (groups[i] == group) i,
    ];
    final deckIncluded = group == deckGroup;
    final total = slots.length + (deckIncluded ? deck.length : 0);
    final source = slots.where((i) => cards[i] == card).firstOrNull;
    if (source != null) {
      cards[source] = cards[position];
    } else {
      final deckIndex = deckIncluded ? deck.indexOf(card) : -1;
      if (deckIndex < 0) return 0;
      deck[deckIndex] = cards[position]!;
    }
    cards[position] = card;
    groups[position] = -1;
    // Rejuvenate assignments inside this cohort without changing its contents.
    final remaining = slots.where((i) => i != position).toList();
    final pool = <int>[
      for (final i in remaining) cards[i]!,
      if (deckIncluded) ...deck,
    ]..shuffle(random);
    for (final i in remaining) {
      cards[i] = pool.removeLast();
    }
    if (deckIncluded) {
      deck
        ..clear()
        ..addAll(pool);
    }
    return 1 / total;
  }

  void redeal(List<List<int?>> removed, math.Random random) {
    final spots = <int>[];
    for (int row = 0; row < 5; row++) {
      for (int col = 0; col < 6; col++) {
        if (removed[row][col] == null) continue;
        final index = row * 6 + col;
        deck.add(cards[index]!);
        spots.add(index);
      }
    }
    // Old face-down slots remain in their earlier cohort, including slots that
    // previously shared a cohort with the deck. Only the actual deck is mixed.
    deck.shuffle(random);
    deckGroup++;
    for (final index in spots) {
      cards[index] = deck.removeLast();
      groups[index] = deckGroup;
    }
  }

  GameState world(GameState public) => GameState(
    players: public.players,
    currentPlayerIndex: public.currentPlayerIndex,
    turnStartFaceUp: public.turnStartFaceUp,
    deck: List.from(deck),
    cardGrid: List.generate(5, (r) => cards.sublist(r * 6, r * 6 + 6)),
    faceUp: public.faceUp.map((row) => List<bool>.from(row)).toList(),
    pendingRemovals: const {},
    pendingPenalty: 0,
    mustSelectAdjacentToHandle: public.mustSelectAdjacentToHandle,
    turnCanEnd: public.turnCanEnd,
    stats: {for (final name in public.players) name: const PlayerStats()},
    recentEvents: const [],
  );
}

class _Candidate {
  _Candidate(this.action, this.success, this.penalty);
  final PolicyAction action;
  final double success;
  final int penalty;
  double get risk => (1 - success) * penalty;
}

/// Bounded rollout search, not a learned policy or an optimality guarantee.
class _StatisticsAdvisor {
  _StatisticsAdvisor(
    this.state, {
    this.budgetMilliseconds = 180,
    this.fixedRounds,
    this.historyLength = StatisticsPolicy.defaultHistoryLength,
    this.scenarioSeed,
  }) {
    if (fixedRounds != null &&
        (fixedRounds! < 3 || fixedRounds! > 12 || fixedRounds! % 3 != 0)) {
      throw ArgumentError.value(
        fixedRounds,
        'fixedRounds',
        'Use 3, 6, 9 or 12',
      );
    }
  }
  final int budgetMilliseconds;
  final int? fixedRounds;
  final int historyLength;
  final int? scenarioSeed;
  final GameState state;

  AiMoveProposal propose({List<PolicyAction>? actions}) {
    final stopwatch = Stopwatch()..start();
    final random = math.Random(1701);
    final publicGame = WindowGameEngine.fromState(state);
    final table = StatisticsTableModel(state.players.length);
    final legal = WindowRlCodec.validActions(publicGame);
    final requested = actions == null
        ? legal
        : legal.where((a) => actions.any((b) => a.index == b.index)).toList();
    // Passing in solo play returns to the same player and changes no card or
    // drink outcome. Keep an explicitly requested pass-only restriction legal,
    // but never spend normal advice/search effort on that dominated action.
    if (!table.hasOpponents && requested.any((action) => !action.isPass)) {
      requested.removeWhere((action) => action.isPass);
    }
    if (requested.isEmpty) throw StateError('No legal action can be proposed.');
    final beliefWatch = Stopwatch()..start();
    final beliefs = _CardBeliefs(state, random);
    final beliefMicros = beliefWatch.elapsedMicroseconds;
    // Optional independent stream for matched history-length experiments.
    // Null preserves the deployed search sequence and its current default.
    final scenarioRandom = scenarioSeed == null
        ? random
        : math.Random(scenarioSeed);

    final publicRisks = _publicRisks(publicGame);
    final baseline = {for (final c in publicRisks) c.action.index: c};
    final options = <(Position, Orientation), GuessOption>{};
    final candidates = <_Candidate>[];
    final rankCache = <Position, List<double>>{};
    for (final action in requested) {
      if (action.isPass) {
        candidates.add(_Candidate(action, 1, 0));
        continue;
      }
      final known = baseline[action.index]!;
      double success = known.success;
      if (!beliefs.exchangeable && success != 0 && success != 1) {
        final option = options.putIfAbsent(
          (action.position!, action.orientation!),
          () => publicGame
              .getValidOptionsForCard(action.position!)
              .firstWhere((o) => o.orientation == action.orientation),
        );
        final first = publicGame.cardAt(option.neighbors.first)! ~/ 4;
        final last = publicGame.cardAt(option.neighbors.last)! ~/ 4;
        final matchingRanks = List.generate(
          9,
          (rank) => _matches(rank, first, last, action.guess!),
        );
        final position = action.position!.row * 6 + action.position!.column;
        final ranks = rankCache.putIfAbsent(
          action.position!,
          () => beliefs.ranksAt(position),
        );
        success = 0;
        for (int rank = 0; rank < 9; rank++) {
          if (matchingRanks[rank]) success += ranks[rank];
        }
        success = success.clamp(0.01, 0.99);
      }
      candidates.add(_Candidate(action, success, known.penalty));
    }
    candidates.sort((a, b) {
      final risk = a.risk.compareTo(b.risk);
      if (risk != 0) return risk;
      return b.success.compareTo(a.success);
    });
    // Keep two complementary criteria and always retain passing. All actions
    // are scored above; only the expensive future search is shortlisted.
    final bySuccess = List<_Candidate>.from(candidates)
      ..sort((a, b) => b.success.compareTo(a.success));
    final shortlist = <_Candidate>[];
    for (final candidate in [
      ...candidates.take(4),
      ...bySuccess.take(4),
      ...candidates.where((c) => c.action.isPass),
    ]) {
      if (!shortlist.any((c) => c.action.index == candidate.action.index)) {
        shortlist.add(candidate);
      }
    }
    // Orientation has no effect on a move's result when its target and rank
    // predicate and same-rank drink effects are identical. Reuse those rollouts without changing candidate
    // order, tie breaking, or how many paired scenario rounds are evaluated.
    final effects = [
      for (final candidate in shortlist) _effect(publicGame, candidate.action),
    ];
    final totals = List<double>.filled(shortlist.length, 0);
    final passIndex = shortlist.indexWhere((c) => c.action.isPass);
    final differenceSquares = List<double>.filled(shortlist.length, 0);
    int rounds = 0;
    // Finish complete paired rounds to avoid giving earlier candidates a larger
    // budget. Native Flutter runs this in compute(); web keeps this bound small.
    while (rounds < (fixedRounds ?? 12) &&
        (fixedRounds != null ||
            rounds < 3 ||
            rounds % 3 != 0 ||
            stopwatch.elapsedMilliseconds < budgetMilliseconds)) {
      final particle =
          beliefs.particles[scenarioRandom.nextInt(beliefs.particles.length)];
      final seed = scenarioRandom.nextInt(1 << 30);
      final opponentStyles = table.opponentStyles(
        ownerIndex: state.currentPlayerIndex,
        scenario: rounds,
      );
      final scenarioCosts = <(int, int, bool), double>{};
      final costs = List<double>.filled(shortlist.length, 0);
      for (int i = 0; i < shortlist.length; i++) {
        costs[i] = scenarioCosts.putIfAbsent(
          effects[i],
          () => _rollout(
            particle.world(state),
            shortlist[i].action,
            seed,
            opponentStyles,
            shortlist[i].risk,
          ),
        );
      }
      for (int i = 0; i < shortlist.length; i++) {
        totals[i] += costs[i];
        if (passIndex >= 0) {
          final difference = costs[i] - costs[passIndex];
          differenceSquares[i] += difference * difference;
        }
      }
      rounds++;
    }
    int best = 0;
    for (int i = 1; i < totals.length; i++) {
      if (totals[i] < totals[best] - 1e-9 ||
          ((totals[i] - totals[best]).abs() < 1e-9 &&
              (shortlist[i].success > shortlist[best].success ||
                  (shortlist[i].success == shortlist[best].success &&
                      !shortlist[i].action.isPass &&
                      shortlist[best].action.isPass)))) {
        best = i;
      }
    }
    bool uncertainContinuation = false;
    if (state.players.length > 1 &&
        passIndex >= 0 &&
        best != passIndex &&
        shortlist[best].success < 1) {
      final meanDifference = (totals[best] - totals[passIndex]) / rounds;
      final variance = math.max(
        0.0,
        (differenceSquares[best] - rounds * meanDifference * meanDifference) /
            (rounds - 1),
      );
      final standardError = math.sqrt(variance / rounds);
      // Prefer the zero-immediate-cost alternative unless the simulated gain
      // exceeds one paired standard error. This is a conservative decision
      // heuristic, not a calibrated confidence interval (styles are fixed).
      if (-meanDifference <= standardError) {
        best = passIndex;
        uncertainContinuation = true;
      }
    }
    // Keep the validated search/ranking untouched. Exact public constraints
    // improve the reported probability after search, without consuming its RNG.
    final probabilityWatch = Stopwatch()..start();
    final exact = _ExactCardBeliefs(state);
    double probability(PolicyAction action) {
      if (action.isPass) return 1;
      final option = publicGame
          .getValidOptionsForCard(action.position!)
          .firstWhere((o) => o.orientation == action.orientation);
      final first = publicGame.cardAt(option.neighbors.first)! ~/ 4;
      final last = publicGame.cardAt(option.neighbors.last)! ~/ 4;
      final ranks = exact.ranksAt(
        action.position!.row * 6 + action.position!.column,
      );
      double success = 0;
      bool certain = true;
      for (int rank = 0; rank < 9; rank++) {
        if (_matches(rank, first, last, action.guess!)) {
          success += ranks[rank];
        } else if (ranks[rank] > 0) {
          certain = false;
        }
      }
      return certain ? 1 : success.clamp(0.0, 1.0);
    }

    // A certain final reveal has zero remaining personal drinks. This is the
    // only strategy override: it is provably optimal, not a noisy rollout gain.
    PolicyAction? guaranteedFinish;
    if (state.cardGrid.expand((row) => row).whereType<int>().length == 21) {
      for (final action in requested) {
        if (!action.isPass && probability(action) == 1) {
          guaranteedFinish = action;
          break;
        }
      }
    }
    final selected = shortlist[best];
    final action = guaranteedFinish ?? selected.action;
    final confidence = probability(action);
    final reportedRisk = (1 - confidence) * selected.penalty;
    final explanation = guaranteedFinish != null
        ? 'Certain finish, no more drinks'
        : uncertainContinuation
        ? 'Pass; benefit of guessing is unclear'
        : action.isPass
        ? 'Pass to avoid more risk'
        : confidence == 1
        ? 'Certain guess, no immediate drinks'
        : reportedRisk < 0.5 && selected.penalty <= 3
        ? 'Low risk, small penalty'
        : confidence >= 0.75
        ? 'Strong odds, lower future risk'
        : 'Lower expected future drinks';
    return AiMoveProposal(
      action: action,
      confidence: confidence,
      expectedDrinks: guaranteedFinish != null ? 0 : totals[best] / rounds,
      explanation: exact.historyConsistent
          ? explanation
          : '$explanation (current board only)',
      source: 'Pure statistics',
      statisticsDiagnostics: StatisticsDiagnostics(
        historyLimit: historyLength,
        historyEvents: state.recentEvents.length,
        historyFallback: !exact.historyConsistent,
        searchHistoryFallback: !beliefs.historyConsistent,
        guaranteedFinish: guaranteedFinish != null,
        probabilityMicros: probabilityWatch.elapsedMicroseconds,
        beliefMicros: beliefMicros + probabilityWatch.elapsedMicroseconds,
        searchRounds: rounds,
        elapsedMicros: stopwatch.elapsedMicroseconds,
      ),
    );
  }

  static (int, int, bool) _effect(WindowGameEngine game, PolicyAction action) {
    if (action.isPass) return (-1, 0, false);
    final option = game
        .getValidOptionsForCard(action.position!)
        .firstWhere((option) => option.orientation == action.orientation);
    final first = game.cardAt(option.neighbors.first)! ~/ 4;
    final last = game.cardAt(option.neighbors.last)! ~/ 4;
    int mask = 0;
    for (int rank = 0; rank < 9; rank++) {
      if (_matches(rank, first, last, action.guess!)) mask |= 1 << rank;
    }
    return (
      action.position!.row * 6 + action.position!.column,
      mask,
      action.guess == GuessType.same,
    );
  }

  static bool _matches(int rank, int first, int last, GuessType guess) =>
      switch (guess) {
        GuessType.higher => rank > first,
        GuessType.same => rank == first,
        GuessType.lower => rank < first,
        GuessType.inBetween =>
          rank >= math.min(first, last) && rank <= math.max(first, last),
        GuessType.outside =>
          rank < math.min(first, last) || rank > math.max(first, last),
      };

  // Face-up components are shared by all hypothetical failed guesses. Build
  // them once per public board instead of repeating a flood fill per action.
  static Map<Position, int> _removalPenalties(WindowGameEngine game) {
    final groups = List<int>.filled(30, -1);
    final sizes = <int>[];
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        final start = Position(r, c);
        if (!windowLayout[r][c] ||
            !game.isFaceUp(start) ||
            groups[r * 6 + c] >= 0) {
          continue;
        }
        final group = sizes.length;
        int size = 0;
        final queue = <Position>[start];
        groups[r * 6 + c] = group;
        while (queue.isNotEmpty) {
          final p = queue.removeLast();
          size++;
          for (final neighbor in game.adjacentPositions(p)) {
            final index = neighbor.row * 6 + neighbor.column;
            if (game.isFaceUp(neighbor) && groups[index] < 0) {
              groups[index] = group;
              queue.add(neighbor);
            }
          }
        }
        sizes.add(size);
      }
    }
    final penalties = <Position, int>{};
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        final p = Position(r, c);
        if (!windowLayout[r][c] || game.isFaceUp(p)) continue;
        final connected = <int>{};
        for (final neighbor in game.adjacentPositions(p)) {
          final group = groups[neighbor.row * 6 + neighbor.column];
          if (group >= 0) connected.add(group);
        }
        penalties[p] =
            1 + connected.fold<int>(0, (n, group) => n + sizes[group]);
      }
    }
    return penalties;
  }

  static void _play(WindowGameEngine game, PolicyAction action) {
    if (action.isPass) {
      game.endTurn();
      return;
    }
    final option = game
        .getValidOptionsForCard(action.position!)
        .firstWhere((o) => o.orientation == action.orientation);
    final result = game.applyGuess(action.position!, option, action.guess!);
    if (result.requiresSameConfirmation) game.confirmSameGuess();
    if (result.requiresRemovalConfirmation) game.confirmRemovals();
  }

  static List<_Candidate> _publicRisks(WindowGameEngine game) {
    final counts = List<int>.filled(9, 4);
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        final p = Position(r, c);
        if (game.isValidSlot(p) && game.isFaceUp(p)) {
          counts[game.cardAt(p)! ~/ 4]--;
        }
      }
    }
    final total = counts.reduce((a, b) => a + b);
    final prefix = List<int>.filled(10, 0);
    for (int rank = 0; rank < 9; rank++) {
      prefix[rank + 1] = prefix[rank] + counts[rank];
    }
    final results = <_Candidate>[];
    final penalties = _removalPenalties(game);
    // Same ordering as WindowRlCodec.validActions, with each option built once.
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 6; c++) {
        if (!windowLayout[r][c]) continue;
        final position = Position(r, c);
        if (game.isFaceUp(position)) continue;
        for (final option in game.getValidOptionsForCard(position)) {
          final first = game.cardAt(option.neighbors.first)! ~/ 4;
          final last = game.cardAt(option.neighbors.last)! ~/ 4;
          final inBetween =
              prefix[math.max(first, last) + 1] - prefix[math.min(first, last)];
          for (final guess in option.guesses) {
            final matches = switch (guess) {
              GuessType.higher => total - prefix[first + 1],
              GuessType.same => counts[first],
              GuessType.lower => prefix[first],
              GuessType.inBetween => inBetween,
              GuessType.outside => total - inBetween,
            };
            results.add(
              _Candidate(
                PolicyAction.guess(
                  position: position,
                  orientation: option.orientation,
                  guess: guess,
                ),
                matches / math.max(1, total),
                penalties[position]!,
              ),
            );
          }
        }
      }
    }
    return results;
  }

  static double _rollout(
    GameState world,
    PolicyAction root,
    int seed,
    List<int> opponentStyles,
    double immediateRisk,
  ) {
    final game = WindowGameEngine.fromState(
      world,
      seed: seed,
      recordHistory: false,
    );
    final random = math.Random(seed);
    final table = StatisticsTableModel(world.players.length);
    final owner = world.players[world.currentPlayerIndex];
    _play(game, root);
    final immediateDrinks = game.playerStats(owner).drinks;
    for (int step = 0; step < 48 && !game.gameEnded; step++) {
      final risks = _publicRisks(game);
      if (risks.isEmpty) break;
      final self = game.currentPlayer == owner;
      final style = opponentStyles[world.players.indexOf(game.currentPlayer)];
      risks.sort((a, b) => a.risk.compareTo(b.risk));
      // Public-only rollout policies: no sampled answer is consulted in choosing
      // an action. Fixed opponent styles never adapt to observed human behavior.
      PolicyAction action;
      final certain = risks.where((c) => c.success == 1).toList();
      if (certain.isNotEmpty) {
        action = certain.first.action;
      } else if (table.hasOpponents &&
          game.turnCanEnd &&
          (self || random.nextDouble() < [0.45, 0.7, 0.95][style])) {
        action = const PolicyAction.pass();
      } else if (!self && style == 0 && random.nextDouble() < 0.6) {
        action = risks[random.nextInt(risks.length)].action;
      } else if (!self && style == 1) {
        risks.sort((a, b) => b.success.compareTo(a.success));
        action = risks.first.action;
      } else {
        action = risks.first.action;
      }
      _play(game, action);
    }
    // Replace sampled first-move penalties with their analytically estimated
    // expectation. This control variate reduces noise with a small rollout budget.
    final drinks =
        game.playerStats(owner).drinks - immediateDrinks + immediateRisk;
    if (game.gameEnded) return drinks;
    final risks = _publicRisks(game)..sort((a, b) => a.risk.compareTo(b.risk));
    if (risks.isEmpty) return drinks;
    final remaining =
        windowLayout.expand((r) => r).where((v) => v).length -
        game.countFaceUpCards();
    final reveals = table.scheduledReveals(
      remaining: remaining,
      currentIndex: world.players.indexOf(game.currentPlayer),
      canEnd: game.turnCanEnd,
    );
    final safest = risks.first;
    final ownTail =
        reveals[world.currentPlayerIndex] *
        safest.risk /
        math.max(0.15, safest.success);
    double sameTail = 0;
    for (int seat = 0; seat < world.players.length; seat++) {
      if (seat == world.currentPlayerIndex || reveals[seat] == 0) continue;
      sameTail += reveals[seat] * _samePerSuccess(risks, opponentStyles[seat]);
    }
    return drinks + ownTail + sameTail;
  }

  /// Approximate public same-rank charges per successful opponent reveal in the
  /// tail's one-success-per-turn model. This includes drinking without taking
  /// another turn, rather than assuming all future penalties are self-inflicted.
  static double _samePerSuccess(List<_Candidate> risks, int style) {
    final certain = risks.where((candidate) => candidate.success == 1);
    if (certain.isNotEmpty) {
      return certain.first.action.guess == GuessType.same ? 1 : 0;
    }
    final safest = risks.first;
    if (style == 1) {
      final best = risks.reduce((a, b) => b.success > a.success ? b : a);
      return best.action.guess == GuessType.same ? 1 : 0;
    }
    if (style == 2) return safest.action.guess == GuessType.same ? 1 : 0;
    final randomSuccess =
        risks.fold<double>(0, (s, c) => s + c.success) / risks.length;
    final randomSame =
        risks
            .where((c) => c.action.guess == GuessType.same)
            .fold<double>(0, (s, c) => s + c.success) /
        risks.length;
    final success = 0.6 * randomSuccess + 0.4 * safest.success;
    final same =
        0.6 * randomSame +
        0.4 * (safest.action.guess == GuessType.same ? safest.success : 0);
    return success == 0 ? 0 : (same / success).clamp(0.0, 1.0);
  }
}
