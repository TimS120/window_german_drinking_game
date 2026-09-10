import 'dart:math' as math;

import 'package:flutter/material.dart' hide Orientation;

import 'game_engine.dart';

// The board has six portrait-card columns and five rows.  Its aspect ratio is
// calculated from the card aspect ratio and the grid gaps, rather than from
// the number of cells alone.  This keeps every card fully visible.
const double _boardAspectRatio = 0.74;

void main() => runApp(const WindowGameApp());

class WindowGameApp extends StatelessWidget {
  const WindowGameApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Window',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffd4a72c),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: const GameShell(),
  );
}

class GameShell extends StatefulWidget {
  const GameShell({super.key});
  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> {
  final TextEditingController _players = TextEditingController(
    text: 'Player 1, Player 2',
  );
  WindowGameEngine? _game;
  String _message = 'Choose player names to begin a local game.';

  @override
  void dispose() {
    _players.dispose();
    super.dispose();
  }

  void _start() {
    final List<String> names = _players.text
        .split(',')
        .map((String name) => name.trim())
        .where((String name) => name.isNotEmpty)
        .toList();
    setState(() {
      _game = WindowGameEngine(names);
      _message =
          '${_game!.currentPlayer} starts. Select a card next to the handle.';
    });
  }

  Future<void> _select(Position position) async {
    final WindowGameEngine game = _game!;
    final List<GuessOption> options = game.getValidOptionsForCard(position);
    if (options.isEmpty) {
      setState(() => _message = 'That card cannot be selected yet.');
      return;
    }
    final GuessOption? option = options.length == 1
        ? options.single
        : await showDialog<GuessOption>(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: const Text('Choose the comparison'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: options
                    .map(
                      (GuessOption value) => ListTile(
                        title: Text(
                          value.orientation == Orientation.horizontal
                              ? 'Horizontal cards'
                              : 'Vertical cards',
                        ),
                        subtitle: Text(
                          value.type == GuessOptionType.inBetween
                              ? 'In-between or outside'
                              : 'Higher, same, or lower',
                        ),
                        onTap: () => Navigator.pop(context, value),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
    if (!mounted || option == null) return;
    final GuessType? guess = await showDialog<GuessType>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Your guess'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: option.guesses
              .map(
                (GuessType value) => FilledButton(
                  onPressed: () => Navigator.pop(context, value),
                  child: Text(_guessLabel(value)),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (!mounted || guess == null) return;
    await _handle(game.applyGuess(position, option, guess));
  }

  Future<void> _handle(GuessResult result) async {
    final WindowGameEngine game = _game!;
    if (result.invalidReason != null) {
      setState(() => _message = result.invalidReason!);
      return;
    }
    if (result.requiresSameConfirmation) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Correct: same rank!'),
          content: Text(
            'Every other player takes one swallow. ${game.currentPlayer} can continue after confirming.',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      final GuessResult confirmed = game.confirmSameGuess();
      setState(
        () => _message = confirmed.gameEnded
            ? 'The window is complete!'
            : 'Correct. You may guess again or end your turn.',
      );
      return;
    }
    if (result.requiresRemovalConfirmation) {
      final int penalty = game.pendingPenalty;
      final int removed = game.pendingRemovals.length;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Wrong guess'),
          content: Text(
            '${game.currentPlayer} takes $penalty swallow${penalty == 1 ? '' : 's'}. $removed card${removed == 1 ? '' : 's'} will be removed and redealt.',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Redeal cards'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      game.confirmRemovals();
      setState(
        () => _message =
            '${game.currentPlayer} keeps the turn after a wrong guess.',
      );
      return;
    }
    setState(
      () => _message = result.gameEnded
          ? 'The window is complete!'
          : 'Correct. You may guess again or end your turn.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final WindowGameEngine? game = _game;
    if (game == null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Window',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'A local, cross-platform edition of the German card game.',
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _players,
                      decoration: const InputDecoration(
                        labelText: 'Players',
                        hintText: 'Anna, Ben, Carla',
                      ),
                      onSubmitted: (_) => _start(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _message,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start local game'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final GameSnapshot snapshot = game.snapshot();
    final Widget info = _Info(
      game: game,
      snapshot: snapshot,
      message: _message,
      onEndTurn: () {
        game.endTurn();
        setState(() => _message = '${game.currentPlayer}\'s turn.');
      },
      onReset: () {
        game.resetGame();
        setState(() => _message = '${game.currentPlayer} starts a new game.');
      },
    );
    final Widget board = _Board(
      game: game,
      snapshot: snapshot,
      onSelect: _select,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Window')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints size) => Padding(
            padding: const EdgeInsets.all(16),
            child: size.maxWidth >= 900
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: LayoutBuilder(
                          builder:
                              (
                                BuildContext context,
                                BoxConstraints boardConstraints,
                              ) {
                                final double boardWidth = math.min(
                                  boardConstraints.maxWidth,
                                  boardConstraints.maxHeight *
                                      _boardAspectRatio,
                                );
                                return Center(
                                  child: SizedBox(
                                    width: boardWidth,
                                    child: board,
                                  ),
                                );
                              },
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(child: SingleChildScrollView(child: info)),
                    ],
                  )
                : ListView(
                    children: <Widget>[info, const SizedBox(height: 18), board],
                  ),
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({
    required this.game,
    required this.snapshot,
    required this.message,
    required this.onEndTurn,
    required this.onReset,
  });
  final WindowGameEngine game;
  final GameSnapshot snapshot;
  final String message;
  final VoidCallback onEndTurn;
  final VoidCallback onReset;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Current player',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              IconButton(
                onPressed: onReset,
                tooltip: 'New local game',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Text(
            snapshot.currentPlayer,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(message),
          if (snapshot.mustSelectAdjacentToHandle)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Handle rule: choose a card directly beside the handle.',
              ),
            ),
          const Divider(height: 30),
          Text('Deck: ${snapshot.deckSize} cards'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: snapshot.turnCanEnd ? onEndTurn : null,
            child: const Text('End turn'),
          ),
          const Divider(height: 30),
          Text('Scoreboard', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Scoreboard(
            players: game.players,
            currentPlayer: snapshot.currentPlayer,
            stats: snapshot.stats,
          ),
        ],
      ),
    ),
  );
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({
    required this.players,
    required this.currentPlayer,
    required this.stats,
  });

  final List<String> players;
  final String currentPlayer;
  final Map<String, PlayerStats> stats;

  @override
  Widget build(BuildContext context) {
    final List<PlayerStats> playerStats = players
        .map((String player) => stats[player]!)
        .toList();
    final int totalDrinks = playerStats.fold(
      0,
      (int total, PlayerStats value) => total + value.drinks,
    );
    final int totalCorrect = playerStats.fold(
      0,
      (int total, PlayerStats value) => total + value.correct,
    );
    final int totalWrong = playerStats.fold(
      0,
      (int total, PlayerStats value) => total + value.wrong,
    );
    final int totalChanged = playerStats.fold(
      0,
      (int total, PlayerStats value) => total + value.changedCards,
    );
    final int totalTurns = playerStats.fold(
      0,
      (int total, PlayerStats value) => total + value.turns,
    );
    final double averageRatio = playerStats.isEmpty
        ? 0
        : playerStats
                  .map(_correctWrongRatio)
                  .reduce((double total, double value) => total + value) /
              playerStats.length;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 520;
        final Widget table = Table(
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          columnWidths: const <int, TableColumnWidth>{
            0: FlexColumnWidth(1.5),
            1: FlexColumnWidth(),
            2: FlexColumnWidth(),
            3: FlexColumnWidth(),
            4: FlexColumnWidth(1.25),
            5: FlexColumnWidth(1.2),
            6: FlexColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: <TableRow>[
            _tableRow(const <String>[
              'Player',
              'Drinks',
              'Correct',
              'Wrong',
              'C/W ratio',
              'Changed',
              'Turns',
            ], bold: true),
            for (final String player in players)
              _tableRow(<String>[
                player,
                '${stats[player]!.drinks}',
                '${stats[player]!.correct}',
                '${stats[player]!.wrong}',
                _correctWrongRatio(stats[player]!).toStringAsFixed(2),
                '${stats[player]!.changedCards}',
                '${stats[player]!.turns}',
              ], bold: player == currentPlayer),
            _tableRow(<String>[
              'Total',
              '$totalDrinks',
              '$totalCorrect',
              '$totalWrong',
              averageRatio.toStringAsFixed(2),
              '$totalChanged of 17',
              '$totalTurns',
            ], bold: true),
          ],
        );
        if (!compact) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: 520, child: table),
        );
      },
    );
  }

  TableRow _tableRow(List<String> values, {bool bold = false}) => TableRow(
    children: values
        .map(
          (String value) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : null),
            ),
          ),
        )
        .toList(),
  );
}

double _correctWrongRatio(PlayerStats stats) =>
    stats.wrong == 0 ? stats.correct.toDouble() : stats.correct / stats.wrong;

class _Board extends StatelessWidget {
  const _Board({
    required this.game,
    required this.snapshot,
    required this.onSelect,
  });
  final WindowGameEngine game;
  final GameSnapshot snapshot;
  final ValueChanged<Position> onSelect;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: _boardAspectRatio,
    child: Column(
      children: List<Widget>.generate(
        windowLayout.length,
        (int row) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: row == windowLayout.length - 1 ? 0 : 6,
            ),
            child: Row(
              children: List<Widget>.generate(
                windowLayout.first.length,
                (int column) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: column == windowLayout.first.length - 1 ? 0 : 6,
                    ),
                    child: _cardSlot(context, Position(row, column)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _cardSlot(BuildContext context, Position position) {
    if (!game.isValidSlot(position)) return const SizedBox.shrink();
    final bool faceUp = snapshot.faceUp[position.row][position.column];
    final bool selectable = snapshot.validSelectable.contains(position);
    final int? card = snapshot.cardGrid[position.row][position.column];
    return Semantics(
      button: selectable,
      label: position == handlePosition
          ? 'Handle card'
          : (faceUp ? 'Face-up ${game.cardLabel(card!)}' : 'Face-down card'),
      child: InkWell(
        onTap: selectable ? () => onSelect(position) : null,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: faceUp ? const Color(0xfff3ead2) : const Color(0xff164b83),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selectable
                  ? Theme.of(context).colorScheme.primary
                  : Colors.black54,
              width: selectable ? 3 : 1,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Colors.black38,
                blurRadius: 3,
                offset: Offset(1, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset(
              faceUp
                  ? 'assets/cards/c${card! % 4 + 1}_v${card ~/ 4 + 1}.png'
                  : 'assets/cards/card_back.png',
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  faceUp ? game.cardLabel(card!) : '?',
                  style: TextStyle(
                    color: faceUp ? const Color(0xff251c13) : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: faceUp ? 18 : 30,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _guessLabel(GuessType guess) => switch (guess) {
  GuessType.higher => 'Higher',
  GuessType.same => 'Same',
  GuessType.lower => 'Lower',
  GuessType.inBetween => 'In-between',
  GuessType.outside => 'Outside',
};
