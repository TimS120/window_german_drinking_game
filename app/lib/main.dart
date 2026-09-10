import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart' hide Orientation;

import 'firebase_options.dart';
import 'firebase_room_repository.dart';
import 'game_engine.dart';

// The board has six portrait-card columns and five rows.  Its aspect ratio is
// calculated from the card aspect ratio and the grid gaps, rather than from
// the number of cells alone.  This keeps every card fully visible.
const double _boardAspectRatio = 0.74;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Multiplayer uses Firebase's HTTPS APIs. Local play stays available when
  // the public Firebase build configuration was not supplied.
  final bool firebaseEnabled = WindowFirebaseOptions.windowsRestOptions != null;
  runApp(WindowGameApp(firebaseEnabled: firebaseEnabled));
}

class WindowGameApp extends StatelessWidget {
  const WindowGameApp({super.key, required this.firebaseEnabled});
  final bool firebaseEnabled;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Window',
    navigatorKey: navigatorKey,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffd4a72c),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F381C),
      useMaterial3: true,
    ),
    home: GameShell(firebaseEnabled: firebaseEnabled),
  );
}

class GameShell extends StatefulWidget {
  const GameShell({super.key, required this.firebaseEnabled});
  final bool firebaseEnabled;
  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> {
  final TextEditingController _players = TextEditingController(
    text: 'Player 1',
  );
  final TextEditingController _roomCode = TextEditingController();
  final TextEditingController _seatName = TextEditingController();
  WindowGameEngine? _game;
  String _message = 'Choose player names to begin a local game.';
  FirebaseRoomRepository? _rooms;
  StreamSubscription<OnlineRoom?>? _roomSubscription;
  StreamSubscription<RoomRequest>? _requestSubscription;
  String? _requestRoomCode;
  OnlineRoom? _room;
  int _hostVersion = 0;
  bool _busy = false;

  @override
  void dispose() {
    _players.dispose();
    _roomCode.dispose();
    _seatName.dispose();
    _roomSubscription?.cancel();
    _requestSubscription?.cancel();
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

  List<String> _names(TextEditingController controller) => controller.text
      .split(',')
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .toList();

  Future<void> _createRoom() async {
    if (!widget.firebaseEnabled) {
      setState(
        () => _message = 'Firebase is not configured for this build yet.',
      );
      return;
    }
    final List<String> local = _names(_players);
    if (local.isEmpty) {
      setState(() => _message = 'Enter at least one player on this device.');
      return;
    }
    if (local.toSet().length != local.length) {
      setState(
        () =>
            _message = 'Every player sharing this device needs a unique name.',
      );
      return;
    }
    try {
      setState(() => _busy = true);
      final FirebaseRoomRepository rooms = _rooms ??= FirebaseRoomRepository();
      await rooms.signInAnonymously();
      final WindowGameEngine game = WindowGameEngine(local);
      final String code = await rooms.createRoom(
        state: game.exportState(),
        localPlayers: local,
      );
      _roomCode.text = code;
      _game = game;
      await _watchRoom(code);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Could not create room: $error';
        });
      }
    }
  }

  Future<void> _joinRoom() async {
    if (!widget.firebaseEnabled) {
      setState(
        () => _message = 'Firebase is not configured for this build yet.',
      );
      return;
    }
    try {
      setState(() => _busy = true);
      final FirebaseRoomRepository rooms = _rooms ??= FirebaseRoomRepository();
      await rooms.signInAnonymously();
      final String code = _roomCode.text.trim().toUpperCase();
      final String seatName = _seatName.text.trim();
      if (code.isEmpty || seatName.isEmpty) {
        setState(() {
          _busy = false;
          _message = 'Enter both the room code and your player name.';
        });
        return;
      }
      await _watchRoom(code);
      await rooms.requestLobbyJoin(roomCode: code, seatName: seatName);
      if (mounted) {
        setState(() => _message = 'Join request sent. Waiting for the lobby.');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Could not join room: $error';
        });
      }
    }
  }

  Future<void> _watchRoom(String code) async {
    await _roomSubscription?.cancel();
    _roomSubscription = _rooms!
        .observeRoom(code)
        .listen(
          (OnlineRoom? room) {
            if (!mounted || room == null) return;
            final bool isHost = room.hostUid == _rooms?.uid;
            setState(() {
              _room = room;
              _hostVersion = isHost
                  ? math.max(_hostVersion, room.version)
                  : room.version;
              if (!isHost) _game = WindowGameEngine.fromState(room.state);
              _busy = false;
              _message = !room.started
                  ? 'Lobby ${room.code}: waiting for the host to start.'
                  : _game == null
                  ? 'Restoring host state for room ${room.code}…'
                  : 'Room ${room.code}: ${_game!.currentPlayer}\'s turn.';
            });
            if (isHost) {
              _watchRequests(room.code);
              _restoreHostStateIfNeeded(room);
            }
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                _busy = false;
                _message = 'Room connection failed: $error';
              });
            }
          },
        );
  }

  Future<void> _returnToMenu() async {
    await _roomSubscription?.cancel();
    await _requestSubscription?.cancel();
    if (!mounted) return;
    setState(() {
      _room = null;
      _game = null;
      _requestRoomCode = null;
      _hostVersion = 0;
      _busy = false;
      _message = 'Choose player names to begin a local game.';
    });
  }

  Future<void> _restoreHostStateIfNeeded(OnlineRoom room) async {
    if (_game != null || !_isHost) return;
    try {
      final GameState? privateState = await _rooms!.loadPrivateState(room.code);
      if (!mounted || privateState == null || !_isHost) return;
      setState(() {
        _game = WindowGameEngine.fromState(privateState);
        _message = 'Room ${room.code}: ${_game!.currentPlayer}\'s turn.';
      });
      await _requestSubscription?.cancel();
      _requestSubscription = null;
      _requestRoomCode = null;
      _watchRequests(room.code);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = 'The host state could not be restored: $error',
        );
      }
    }
  }

  bool get _isOnline => _room != null;
  bool get _isHost => _isOnline && _room!.hostUid == _rooms?.uid;
  bool get _canControlCurrentTurn {
    if (!_isOnline) return true;
    if (!_room!.started) return false;
    final int index = _isHost
        ? _game!.exportState().currentPlayerIndex
        : _room!.state.currentPlayerIndex;
    return _room!.seats.elementAtOrNull(index)?.ownerUid == _rooms?.uid;
  }

  Future<void> _submitOnline(Map<String, dynamic> action) async {
    final OnlineRoom? room = _room;
    if (room == null || !room.started || !_canControlCurrentTurn || _busy) {
      return;
    }
    try {
      setState(() {
        _busy = true;
        _message = 'Submitting move…';
      });
      if (_isHost) {
        await _applyHostAction(action);
      } else {
        await _rooms!.requestAction(
          roomCode: room.code,
          expectedVersion: room.version,
          action: action,
        );
        if (mounted) {
          setState(() {
            _busy = false;
            _message = 'Move request sent to host.';
          });
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Move rejected: $error';
        });
      }
    }
  }

  Future<void> _startLobbyGame() async {
    final OnlineRoom? room = _room;
    if (room == null || room.started || !_isHost || _busy) return;
    try {
      setState(() {
        _busy = true;
        _message = 'Starting game…';
        _game = WindowGameEngine(
          room.seats.map((RoomSeat seat) => seat.name).toList(),
        );
      });
      await _publishHostState(started: true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Could not start the lobby: $error';
        });
      }
    }
  }

  void _watchRequests(String code) {
    if (_requestRoomCode == code && _requestSubscription != null) return;
    _requestSubscription?.cancel();
    _requestRoomCode = code;
    _requestSubscription = _rooms!
        .observeRequests(code)
        .listen(
          _processHostRequest,
          onError: (Object error) {
            if (mounted) {
              setState(() => _message = 'Room host request error: $error');
            }
          },
        );
  }

  Future<void> _processHostRequest(RoomRequest request) async {
    final OnlineRoom? room = _room;
    final WindowGameEngine? game = _game;
    if (!_isHost || room == null || game == null) return;
    try {
      if (request.type == 'joinLobby' && !room.started) {
        final String name = request.seatName?.trim() ?? '';
        final bool nameTaken = room.seats.any(
          (RoomSeat seat) => seat.name.toLowerCase() == name.toLowerCase(),
        );
        final bool alreadyJoined = room.seats.any(
          (RoomSeat seat) => seat.ownerUid == request.uid,
        );
        if (name.isNotEmpty && !nameTaken && !alreadyJoined) {
          final List<RoomSeat> seats = <RoomSeat>[
            ...room.seats,
            RoomSeat(
              index: room.seats.length,
              name: name,
              ownerUid: request.uid,
            ),
          ];
          await _publishHostState(seats: seats);
        }
      } else if (room.started &&
          request.type == 'action' &&
          request.expectedVersion == _hostVersion &&
          _seatOwnerForCurrentTurn == request.uid) {
        await _applyHostAction(request.action);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Ignored invalid room request: $error');
      }
    } finally {
      await _rooms!.deleteRequest(room.code, request.id);
    }
  }

  String? get _seatOwnerForCurrentTurn {
    final WindowGameEngine? game = _game;
    final OnlineRoom? room = _room;
    if (game == null || room == null) return null;
    return room.seats
        .elementAtOrNull(game.exportState().currentPlayerIndex)
        ?.ownerUid;
  }

  Future<void> _applyHostAction(Map<String, dynamic> action) async {
    final WindowGameEngine game = _game!;
    final String type = '${action['type']}';
    GuessResult? result;
    if (type == 'guess') {
      final List<dynamic> values = List<dynamic>.from(
        action['position'] as List,
      );
      if (values.length != 2 || values.any((dynamic value) => value is! num)) {
        return;
      }
      final Position position = Position(
        (values[0] as num).toInt(),
        (values[1] as num).toInt(),
      );
      final Orientation orientation = Orientation.values.byName(
        '${action['orientation']}',
      );
      final List<GuessOption> options = game
          .getValidOptionsForCard(position)
          .where((GuessOption value) => value.orientation == orientation)
          .toList();
      if (options.isEmpty) return;
      result = game.applyGuess(
        position,
        options.first,
        GuessType.values.byName('${action['guess']}'),
      );
    } else if (type == 'confirmSame') {
      result = game.confirmSameGuess();
    } else if (type == 'confirmRemovals') {
      if (game.pendingRemovals.isEmpty) return;
      game.confirmRemovals();
    } else if (type == 'endTurn') {
      if (!game.turnCanEnd) return;
      game.endTurn();
    } else {
      return;
    }
    if (result?.invalidReason != null) return;
    await _publishHostState();
  }

  Future<void> _publishHostState({List<RoomSeat>? seats, bool? started}) async {
    final OnlineRoom room = _room!;
    final int previousVersion = _hostVersion;
    final int nextVersion = _hostVersion + 1;
    _hostVersion = nextVersion;
    try {
      await _rooms!.publishState(
        roomCode: room.code,
        hostUid: room.hostUid,
        version: nextVersion,
        seats: seats ?? room.seats,
        state: _game!.exportState(),
        started: started ?? room.started,
      );
    } catch (_) {
      _hostVersion = previousVersion;
      rethrow;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _message = '${_game!.currentPlayer}\'s turn.';
      });
    }
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
        : await _showMovableGameDialog<GuessOption>(
            title: 'Choose the comparison',
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
          );
    if (!mounted || option == null) return;
    final GuessType? guess = await _showMovableGameDialog<GuessType>(
      title: 'Your guess',
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
    );
    if (!mounted || guess == null) return;
    if (_isOnline) {
      await _submitOnline(<String, dynamic>{
        'type': 'guess',
        'position': <int>[position.row, position.column],
        'orientation': option.orientation.name,
        'guess': guess.name,
      });
    } else {
      await _handle(game.applyGuess(position, option, guess));
    }
  }

  Future<void> _handle(GuessResult result) async {
    final WindowGameEngine game = _game!;
    if (result.invalidReason != null) {
      setState(() => _message = result.invalidReason!);
      return;
    }
    if (result.requiresSameConfirmation) {
      await _showMovableGameDialog<void>(
        title: 'Correct: same rank!',
        barrierDismissible: false,
        content: Text(
          'Every other player takes one swallow. ${game.currentPlayer} can continue after confirming.',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue'),
          ),
        ],
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
      setState(
        () => _message = 'Wrong guess. The revealed card and every card with a red border will be redealt.',
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _showMovableGameDialog<void>(
        title: 'Wrong guess',
        barrierDismissible: false,
        content: Text(
          '${game.currentPlayer} takes $penalty swallow${penalty == 1 ? '' : 's'}. $removed card${removed == 1 ? '' : 's'} will be removed and redealt.',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Redeal cards'),
          ),
        ],
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
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _busy ? null : _createRoom,
                      icon: const Icon(Icons.group),
                      label: Text(
                        widget.firebaseEnabled
                            ? 'Create online lobby'
                            : 'Online rooms need Firebase setup',
                      ),
                    ),
                    const Divider(height: 32),
                    TextField(
                      controller: _roomCode,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Room code'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _seatName,
                      decoration: const InputDecoration(
                        labelText: 'Your player name',
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _joinRoom,
                      icon: const Icon(Icons.login),
                      label: const Text('Join online room'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (_isOnline && !_room!.started) {
      final OnlineRoom room = _room!;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Window lobby'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Leave lobby and return to menu',
              icon: const Icon(Icons.home_outlined),
              onPressed: _returnToMenu,
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Room ${room.code}',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isHost
                            ? 'Share this code. Players may join until you start the game.'
                            : 'You are in the lobby. Waiting for the host to start.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Players (${room.seats.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ...room.seats.map(
                        (RoomSeat seat) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.person),
                          title: Text(seat.name),
                          trailing: seat.ownerUid == room.hostUid
                              ? const Text('Host')
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _message,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_isHost) ...<Widget>[
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _busy ? null : _startLobbyGame,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start game and lock lobby'),
                        ),
                      ],
                    ],
                  ),
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
      roomCode: _room?.code,
      busy: _busy,
      canControl: _canControlCurrentTurn,
      onEndTurn: () {
        if (_isOnline) {
          _submitOnline(<String, dynamic>{'type': 'endTurn'});
        } else {
          game.endTurn();
          setState(() => _message = '${game.currentPlayer}\'s turn.');
        }
      },
      onReset: () {
        if (!_isOnline) {
          game.resetGame();
          setState(() => _message = '${game.currentPlayer} starts a new game.');
        }
      },
      onConfirmSame: () =>
          _submitOnline(<String, dynamic>{'type': 'confirmSame'}),
      onConfirmRemovals: () =>
          _submitOnline(<String, dynamic>{'type': 'confirmRemovals'}),
    );
    final Widget board = _Board(
      game: game,
      snapshot: snapshot,
      enabled: _canControlCurrentTurn && !_busy,
      onSelect: _select,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Window'),
        actions: <Widget>[
          IconButton(
            tooltip: _isOnline
                ? 'Leave room and return to menu'
                : 'Return to menu',
            icon: const Icon(Icons.home_outlined),
            onPressed: _returnToMenu,
          ),
        ],
      ),
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
    required this.roomCode,
    required this.busy,
    required this.canControl,
    required this.onEndTurn,
    required this.onReset,
    required this.onConfirmSame,
    required this.onConfirmRemovals,
  });
  final WindowGameEngine game;
  final GameSnapshot snapshot;
  final String message;
  final String? roomCode;
  final bool busy;
  final bool canControl;
  final VoidCallback onEndTurn;
  final VoidCallback onReset;
  final VoidCallback onConfirmSame;
  final VoidCallback onConfirmRemovals;
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
              if (roomCode == null)
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
          if (roomCode != null) ...<Widget>[
            const SizedBox(height: 8),
            SelectableText('Online room: $roomCode'),
            if (!canControl)
              const Text('Waiting for the player who owns this seat.'),
          ],
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
            onPressed: snapshot.turnCanEnd && canControl && !busy
                ? onEndTurn
                : null,
            child: const Text('End turn'),
          ),
          if (roomCode != null &&
              snapshot.pendingSamePosition != null) ...<Widget>[
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: canControl && !busy ? onConfirmSame : null,
              child: const Text('Confirm same-rank penalty'),
            ),
          ],
          if (roomCode != null &&
              snapshot.pendingRemovals.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: canControl && !busy ? onConfirmRemovals : null,
              child: const Text('Redeal marked cards'),
            ),
          ],
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

Future<T?> _showMovableGameDialog<T>({
  required String title,
  required Widget content,
  List<Widget> actions = const <Widget>[],
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: navigatorKey.currentContext!,
  barrierDismissible: barrierDismissible,
  builder: (BuildContext context) =>
      _MovableGameDialog(title: title, content: content, actions: actions),
);

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class _MovableGameDialog extends StatefulWidget {
  const _MovableGameDialog({
    required this.title,
    required this.content,
    required this.actions,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  State<_MovableGameDialog> createState() => _MovableGameDialogState();
}

class _MovableGameDialogState extends State<_MovableGameDialog> {
  Offset _translation = Offset.zero;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: _translation,
    child: Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (DragUpdateDetails details) =>
                    setState(() => _translation += details.delta),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.drag_indicator),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: widget.content,
            ),
            if (widget.actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.actions,
                ),
              ),
          ],
        ),
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
    required this.enabled,
    required this.onSelect,
  });
  final WindowGameEngine game;
  final GameSnapshot snapshot;
  final bool enabled;
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
    final bool selectable =
        enabled && snapshot.validSelectable.contains(position);
    final bool markedForRemoval = snapshot.pendingRemovals.contains(position);
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
              color: markedForRemoval
                  ? Colors.redAccent
                  : (selectable
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black54),
              width: markedForRemoval ? 4 : (selectable ? 3 : 1),
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
