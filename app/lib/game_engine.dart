import 'dart:math';

const List<List<bool>> windowLayout = <List<bool>>[
  <bool>[true, true, true, true, true, false],
  <bool>[true, false, true, false, true, false],
  <bool>[true, true, true, true, true, true],
  <bool>[true, false, true, false, true, false],
  <bool>[true, true, true, true, true, false],
];

const Position handlePosition = Position(2, 5);
final Set<Position> cornerPositions = <Position>{
  const Position(0, 0),
  const Position(0, 4),
  const Position(4, 0),
  const Position(4, 4),
};

class Position {
  const Position(this.row, this.column);

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is Position && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);
}

enum GuessType { higher, same, lower, inBetween, outside }

enum Orientation { horizontal, vertical }

enum GuessOptionType { higherLower, inBetween }

class GuessOption {
  const GuessOption({
    required this.type,
    required this.guesses,
    required this.neighbors,
    required this.orientation,
  });

  final GuessOptionType type;
  final List<GuessType> guesses;
  final List<Position> neighbors;
  final Orientation orientation;
}

class PlayerStats {
  const PlayerStats({
    this.drinks = 0,
    this.correct = 0,
    this.wrong = 0,
    this.changedCards = 0,
    this.turns = 0,
  });

  final int drinks;
  final int correct;
  final int wrong;
  final int changedCards;
  final int turns;

  PlayerStats copyWith({
    int? drinks,
    int? correct,
    int? wrong,
    int? changedCards,
    int? turns,
  }) => PlayerStats(
    drinks: drinks ?? this.drinks,
    correct: correct ?? this.correct,
    wrong: wrong ?? this.wrong,
    changedCards: changedCards ?? this.changedCards,
    turns: turns ?? this.turns,
  );
}

class GuessResult {
  const GuessResult({
    this.correct = false,
    this.invalidReason,
    this.requiresSameConfirmation = false,
    this.requiresRemovalConfirmation = false,
    this.gameEnded = false,
  });

  final bool correct;
  final String? invalidReason;
  final bool requiresSameConfirmation;
  final bool requiresRemovalConfirmation;
  final bool gameEnded;
}

/// A transport-friendly state object. It is intentionally independent of UI
/// and persistence; Firebase serialization will be added in the multiplayer stage.
class GameState {
  const GameState({
    required this.players,
    required this.currentPlayerIndex,
    required this.turnStartFaceUp,
    required this.deck,
    required this.cardGrid,
    required this.faceUp,
    required this.pendingRemovals,
    required this.pendingPenalty,
    required this.mustSelectAdjacentToHandle,
    required this.turnCanEnd,
    required this.stats,
    this.pendingSamePosition,
  });

  final List<String> players;
  final int currentPlayerIndex;
  final int turnStartFaceUp;
  final List<int> deck;
  final List<List<int?>> cardGrid;
  final List<List<bool>> faceUp;
  final Set<Position> pendingRemovals;
  final int pendingPenalty;
  final bool mustSelectAdjacentToHandle;
  final bool turnCanEnd;
  final Map<String, PlayerStats> stats;
  final Position? pendingSamePosition;
}

class GameSnapshot {
  const GameSnapshot({
    required this.cardGrid,
    required this.faceUp,
    required this.currentPlayer,
    required this.deckSize,
    required this.mustSelectAdjacentToHandle,
    required this.turnCanEnd,
    required this.validSelectable,
    required this.stats,
    required this.pendingRemovals,
    required this.gameEnded,
  });

  final List<List<int?>> cardGrid;
  final List<List<bool>> faceUp;
  final String currentPlayer;
  final int deckSize;
  final bool mustSelectAdjacentToHandle;
  final bool turnCanEnd;
  final Set<Position> validSelectable;
  final Map<String, PlayerStats> stats;
  final Set<Position> pendingRemovals;
  final bool gameEnded;
}

/// The canonical Window rules engine for every Flutter platform.
class WindowGameEngine {
  WindowGameEngine(List<String> players, {int? seed})
    : _random = Random(seed),
      _players = List<String>.unmodifiable(
        players.where((String name) => name.trim().isNotEmpty).toList().isEmpty
            ? <String>['Player 1']
            : players
                  .where((String name) => name.trim().isNotEmpty)
                  .map((String name) => name.trim())
                  .toList(),
      ) {
    resetGame();
  }

  WindowGameEngine.fromState(GameState state) : _random = Random() {
    _players = List<String>.unmodifiable(state.players);
    restore(state);
  }

  final Random _random;
  late List<String> _players;
  late List<int> _deck;
  late List<List<int?>> _cardGrid;
  late List<List<bool>> _faceUp;
  late Map<String, PlayerStats> _stats;
  late int _currentPlayerIndex;
  late int _turnStartFaceUp;
  Set<Position> _pendingRemovals = <Position>{};
  int _pendingPenalty = 0;
  bool _mustSelectAdjacentToHandle = true;
  bool _turnCanEnd = false;
  Position? _pendingSamePosition;

  List<String> get players => _players;
  String get currentPlayer => _players[_currentPlayerIndex];
  bool get mustSelectAdjacentToHandle => _mustSelectAdjacentToHandle;
  bool get turnCanEnd => _turnCanEnd;
  int get pendingPenalty => _pendingPenalty;
  Set<Position> get pendingRemovals =>
      Set<Position>.unmodifiable(_pendingRemovals);

  void resetGame() {
    _currentPlayerIndex = 0;
    _deck = List<int>.generate(36, (int index) => index)..shuffle(_random);
    _cardGrid = List<List<int?>>.generate(
      windowLayout.length,
      (int _) => List<int?>.filled(windowLayout.first.length, null),
    );
    _faceUp = List<List<bool>>.generate(
      windowLayout.length,
      (int _) => List<bool>.filled(windowLayout.first.length, false),
    );
    _stats = <String, PlayerStats>{
      for (final String player in _players) player: const PlayerStats(),
    };
    for (int row = 0; row < windowLayout.length; row++) {
      for (int column = 0; column < windowLayout[row].length; column++) {
        final Position position = Position(row, column);
        if (!isValidSlot(position)) continue;
        _cardGrid[row][column] = _deck.removeLast();
        _faceUp[row][column] =
            cornerPositions.contains(position) || position == handlePosition;
      }
    }
    _pendingRemovals = <Position>{};
    _pendingPenalty = 0;
    _pendingSamePosition = null;
    _mustSelectAdjacentToHandle = true;
    _turnCanEnd = false;
    _turnStartFaceUp = countFaceUpCards();
    _incrementTurns(currentPlayer);
  }

  GameState exportState() => GameState(
    players: List<String>.from(_players),
    currentPlayerIndex: _currentPlayerIndex,
    turnStartFaceUp: _turnStartFaceUp,
    deck: List<int>.from(_deck),
    cardGrid: _cardGrid.map((List<int?> row) => List<int?>.from(row)).toList(),
    faceUp: _faceUp.map((List<bool> row) => List<bool>.from(row)).toList(),
    pendingRemovals: Set<Position>.from(_pendingRemovals),
    pendingPenalty: _pendingPenalty,
    mustSelectAdjacentToHandle: _mustSelectAdjacentToHandle,
    turnCanEnd: _turnCanEnd,
    stats: Map<String, PlayerStats>.from(_stats),
    pendingSamePosition: _pendingSamePosition,
  );

  void restore(GameState state) {
    if (state.players.isEmpty) {
      throw ArgumentError.value(state.players, 'players');
    }
    _players = List<String>.unmodifiable(state.players);
    _currentPlayerIndex = state.currentPlayerIndex.clamp(
      0,
      _players.length - 1,
    );
    _turnStartFaceUp = state.turnStartFaceUp;
    _deck = List<int>.from(state.deck);
    _cardGrid = state.cardGrid
        .map((List<int?> row) => List<int?>.from(row))
        .toList();
    _faceUp = state.faceUp
        .map((List<bool> row) => List<bool>.from(row))
        .toList();
    _pendingRemovals = Set<Position>.from(state.pendingRemovals);
    _pendingPenalty = state.pendingPenalty;
    _mustSelectAdjacentToHandle = state.mustSelectAdjacentToHandle;
    _turnCanEnd = state.turnCanEnd;
    _stats = Map<String, PlayerStats>.from(state.stats);
    _pendingSamePosition = state.pendingSamePosition;
  }

  bool isValidSlot(Position position) =>
      position.row >= 0 &&
      position.row < windowLayout.length &&
      position.column >= 0 &&
      position.column < windowLayout[position.row].length &&
      windowLayout[position.row][position.column];

  int? cardAt(Position position) => _cardGrid[position.row][position.column];
  bool isFaceUp(Position position) => _faceUp[position.row][position.column];
  String cardLabel(int cardId) =>
      '${const <String>['6', '7', '8', '9', '10', 'U', 'O', 'K', 'A'][cardId ~/ 4]}.${const <String>['E', 'B', 'H', 'S'][cardId % 4]}';

  List<Position> adjacentPositions(Position position) {
    const List<Position> offsets = <Position>[
      Position(-1, 0),
      Position(1, 0),
      Position(0, -1),
      Position(0, 1),
    ];
    return offsets
        .map(
          (Position offset) => Position(
            position.row + offset.row,
            position.column + offset.column,
          ),
        )
        .where(isValidSlot)
        .toList();
  }

  List<GuessOption> getValidOptionsForCard(Position position) {
    if (!isValidSlot(position) || isFaceUp(position)) {
      return const <GuessOption>[];
    }
    if (_mustSelectAdjacentToHandle &&
        !adjacentPositions(handlePosition).contains(position)) {
      return const <GuessOption>[];
    }
    final List<Position> horizontal = <Position>[];
    final List<Position> vertical = <Position>[];
    for (final Position neighbor in adjacentPositions(position)) {
      if (!isFaceUp(neighbor)) continue;
      if (neighbor.row == position.row) {
        horizontal.add(neighbor);
      } else {
        vertical.add(neighbor);
      }
    }
    final List<GuessOption> options = <GuessOption>[];
    if (horizontal.length >= 2) {
      horizontal.sort((Position a, Position b) => a.column.compareTo(b.column));
      options.add(
        GuessOption(
          type: GuessOptionType.inBetween,
          guesses: const <GuessType>[GuessType.inBetween, GuessType.outside],
          neighbors: <Position>[horizontal.first, horizontal.last],
          orientation: Orientation.horizontal,
        ),
      );
    } else if (horizontal.length == 1) {
      options.add(
        GuessOption(
          type: GuessOptionType.higherLower,
          guesses: const <GuessType>[
            GuessType.higher,
            GuessType.same,
            GuessType.lower,
          ],
          neighbors: horizontal,
          orientation: Orientation.horizontal,
        ),
      );
    }
    if (vertical.length >= 2) {
      vertical.sort((Position a, Position b) => a.row.compareTo(b.row));
      options.add(
        GuessOption(
          type: GuessOptionType.inBetween,
          guesses: const <GuessType>[GuessType.inBetween, GuessType.outside],
          neighbors: <Position>[vertical.first, vertical.last],
          orientation: Orientation.vertical,
        ),
      );
    } else if (vertical.length == 1) {
      options.add(
        GuessOption(
          type: GuessOptionType.higherLower,
          guesses: const <GuessType>[
            GuessType.higher,
            GuessType.same,
            GuessType.lower,
          ],
          neighbors: vertical,
          orientation: Orientation.vertical,
        ),
      );
    }
    final List<GuessOption> between = options
        .where((GuessOption option) => option.type == GuessOptionType.inBetween)
        .toList();
    return between.isEmpty ? options : between;
  }

  Set<Position> validSelectablePositions() {
    final Set<Position> positions = <Position>{};
    for (int row = 0; row < windowLayout.length; row++) {
      for (int column = 0; column < windowLayout[row].length; column++) {
        final Position position = Position(row, column);
        if (isValidSlot(position) &&
            getValidOptionsForCard(position).isNotEmpty) {
          positions.add(position);
        }
      }
    }
    return positions;
  }

  GuessResult applyGuess(
    Position position,
    GuessOption option,
    GuessType guess,
  ) {
    if (_pendingSamePosition != null || _pendingRemovals.isNotEmpty) {
      return const GuessResult(
        invalidReason: 'Finish the pending action first.',
      );
    }
    if (!isValidSlot(position) ||
        isFaceUp(position) ||
        !_isCurrentOption(position, option)) {
      return const GuessResult(invalidReason: 'Invalid card selection.');
    }
    if (!option.guesses.contains(guess)) {
      return const GuessResult(invalidReason: 'Invalid guess.');
    }
    final int card = cardAt(position)!;
    bool correct;
    if (option.type == GuessOptionType.higherLower) {
      final int comparison = cardAt(option.neighbors.single)!;
      correct = switch (guess) {
        GuessType.higher => _rank(card) > _rank(comparison),
        GuessType.same => _rank(card) == _rank(comparison),
        GuessType.lower => _rank(card) < _rank(comparison),
        _ => false,
      };
      if (correct && guess == GuessType.same) {
        _pendingSamePosition = position;
        return const GuessResult(correct: true, requiresSameConfirmation: true);
      }
    } else {
      final bool inRange = _isBetween(
        card,
        cardAt(option.neighbors[0])!,
        cardAt(option.neighbors[1])!,
      );
      correct =
          (guess == GuessType.inBetween && inRange) ||
          (guess == GuessType.outside && !inRange);
    }
    return _finalizeGuess(position, correct);
  }

  GuessResult confirmSameGuess() {
    final Position? position = _pendingSamePosition;
    if (position == null) {
      return const GuessResult(invalidReason: 'No same guess is pending.');
    }
    for (final String player in _players.where(
      (String player) => player != currentPlayer,
    )) {
      _stats[player] = _stats[player]!.copyWith(
        drinks: _stats[player]!.drinks + 1,
      );
    }
    _pendingSamePosition = null;
    return _finalizeGuess(position, true);
  }

  void confirmRemovals() {
    if (_pendingRemovals.isEmpty) return;
    for (final Position position in _pendingRemovals) {
      final int? card = cardAt(position);
      if (card != null) _deck.add(card);
      _cardGrid[position.row][position.column] = null;
      _faceUp[position.row][position.column] = false;
    }
    _mustSelectAdjacentToHandle = _pendingRemovals.contains(handlePosition);
    _pendingRemovals = <Position>{};
    _pendingPenalty = 0;
    _deck.shuffle(_random);
    _redealSpots();
  }

  void endTurn() {
    if (!_turnCanEnd ||
        _pendingRemovals.isNotEmpty ||
        _pendingSamePosition != null) {
      return;
    }
    final PlayerStats current = _stats[currentPlayer]!;
    _stats[currentPlayer] = current.copyWith(
      changedCards:
          current.changedCards + countFaceUpCards() - _turnStartFaceUp,
    );
    _currentPlayerIndex = (_currentPlayerIndex + 1) % _players.length;
    _turnStartFaceUp = countFaceUpCards();
    _incrementTurns(currentPlayer);
    _turnCanEnd = false;
  }

  int countFaceUpCards() {
    int total = 0;
    for (int row = 0; row < windowLayout.length; row++) {
      for (int column = 0; column < windowLayout[row].length; column++) {
        if (windowLayout[row][column] && _faceUp[row][column]) total++;
      }
    }
    return total;
  }

  bool get gameEnded => countFaceUpCards() == _slotCount;

  GameSnapshot snapshot() => GameSnapshot(
    cardGrid: _cardGrid
        .map((List<int?> row) => List<int?>.unmodifiable(row))
        .toList(),
    faceUp: _faceUp
        .map((List<bool> row) => List<bool>.unmodifiable(row))
        .toList(),
    currentPlayer: currentPlayer,
    deckSize: _deck.length,
    mustSelectAdjacentToHandle: _mustSelectAdjacentToHandle,
    turnCanEnd: _turnCanEnd,
    validSelectable: validSelectablePositions(),
    stats: Map<String, PlayerStats>.unmodifiable(_stats),
    pendingRemovals: pendingRemovals,
    gameEnded: gameEnded,
  );

  GuessResult _finalizeGuess(Position position, bool correct) {
    final PlayerStats stats = _stats[currentPlayer]!;
    if (correct) {
      _faceUp[position.row][position.column] = true;
      _stats[currentPlayer] = stats.copyWith(correct: stats.correct + 1);
      _mustSelectAdjacentToHandle = false;
      _turnCanEnd = true;
      return GuessResult(correct: true, gameEnded: gameEnded);
    }
    _faceUp[position.row][position.column] = true;
    _pendingRemovals = _collectConnectedOpenCards(position);
    _pendingPenalty = _pendingRemovals.length;
    _stats[currentPlayer] = stats.copyWith(
      wrong: stats.wrong + 1,
      drinks: stats.drinks + _pendingPenalty,
    );
    _turnCanEnd = false;
    return const GuessResult(requiresRemovalConfirmation: true);
  }

  Set<Position> _collectConnectedOpenCards(Position start) {
    final Set<Position> visited = <Position>{};
    final List<Position> queue = <Position>[start];
    while (queue.isNotEmpty) {
      final Position current = queue.removeLast();
      if (!visited.add(current)) continue;
      for (final Position neighbor in adjacentPositions(current)) {
        if (isFaceUp(neighbor) && !visited.contains(neighbor)) {
          queue.add(neighbor);
        }
      }
    }
    return visited;
  }

  void _redealSpots() {
    for (int row = 0; row < windowLayout.length; row++) {
      for (int column = 0; column < windowLayout[row].length; column++) {
        final Position position = Position(row, column);
        if (!isValidSlot(position) ||
            cardAt(position) != null ||
            _deck.isEmpty) {
          continue;
        }
        _cardGrid[row][column] = _deck.removeLast();
        _faceUp[row][column] =
            cornerPositions.contains(position) || position == handlePosition;
      }
    }
  }

  int _rank(int card) => card ~/ 4;
  int get _slotCount => windowLayout
      .expand((List<bool> row) => row)
      .where((bool isSlot) => isSlot)
      .length;
  bool _isBetween(int card, int first, int second) =>
      _rank(card) >= min(_rank(first), _rank(second)) &&
      _rank(card) <= max(_rank(first), _rank(second));
  bool _isCurrentOption(Position position, GuessOption option) =>
      getValidOptionsForCard(position).any(
        (GuessOption candidate) =>
            candidate.type == option.type &&
            candidate.orientation == option.orientation &&
            candidate.neighbors.length == option.neighbors.length &&
            List<bool>.generate(
              candidate.neighbors.length,
              (int index) =>
                  candidate.neighbors[index] == option.neighbors[index],
            ).every((bool equal) => equal),
      );
  void _incrementTurns(String player) => _stats[player] = _stats[player]!
      .copyWith(turns: _stats[player]!.turns + 1);
}
