import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Orientation;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, LogicalKeyboardKey;

import 'firebase_options.dart';
import 'firebase_room_repository.dart';
import 'game_engine.dart';
import 'game_state_codec.dart';
import 'lobby_players.dart';
import 'rl_policy.dart';
import 'room_social.dart';
import 'room_social_widgets.dart';

// The board has six portrait-card columns and five rows.  Its aspect ratio is
// calculated from the card aspect ratio and the grid gaps, rather than from
// the number of cells alone.  This keeps every card fully visible.
const double _boardAspectRatio = 0.74;

enum _AdvisorMethod { rlModel, statistics }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Multiplayer uses Firebase's HTTPS APIs. Local play stays available when
  // the public Firebase build configuration was not supplied.
  final bool firebaseEnabled = WindowFirebaseOptions.windowsRestOptions != null;
  final WindowRlPolicy rlPolicy = WindowRlPolicy();
  // Start asynchronous ONNX loading before the first frame. The game remains
  // responsive while assets/runtime initialize, and a proposal shares this
  // future instead of triggering a second, late load.
  unawaited(rlPolicy.preload());
  runApp(WindowGameApp(firebaseEnabled: firebaseEnabled, rlPolicy: rlPolicy));
}

class WindowGameApp extends StatelessWidget {
  const WindowGameApp({
    super.key,
    required this.firebaseEnabled,
    required this.rlPolicy,
    this.browserGuest = kIsWeb,
  });
  final bool firebaseEnabled;
  final WindowRlPolicy rlPolicy;
  final bool browserGuest;
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
    home: GameShell(
      firebaseEnabled: firebaseEnabled,
      rlPolicy: rlPolicy,
      browserGuest: browserGuest,
    ),
  );
}

class GameShell extends StatefulWidget {
  const GameShell({
    super.key,
    required this.firebaseEnabled,
    required this.rlPolicy,
    this.browserGuest = kIsWeb,
    this.initialRoomCode,
    this.repository,
  });
  final bool firebaseEnabled;
  final WindowRlPolicy rlPolicy;
  final bool browserGuest;
  final String? initialRoomCode;
  final FirebaseRoomRepository? repository;
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
  late final WindowRlPolicy _rlPolicy;
  AiMoveProposal? _proposal;
  bool _proposing = false;
  Future<void> _hostRequestQueue = Future<void>.value();
  Future<void> _socialSendQueue = Future<void>.value();
  Future<void> _hostSocialQueue = Future<void>.value();
  Map<String, dynamic>? _pendingSharedUi;
  String? _pendingUiRoom;
  bool _publishingUi = false;
  int _uiSequence = 0;
  final GlobalKey _footerKey = GlobalKey();
  double _footerExtent = 0;
  double _chatSideExtent = 0;
  bool _chatMinimized = false;
  bool _footerMeasureScheduled = false;
  StreamSubscription<RoomSocialSnapshot>? _socialSubscription;
  String? _socialRoomCode;
  RoomSocialSnapshot _social = RoomSocialSnapshot(null);
  RoomSocialSnapshot? _hostSocial;
  String? _hostSocialRoomCode;
  Map<String, dynamic> _localTurnUi = {};
  int _localTurnVersion = -1;
  final Set<String> _seenReactions = {};
  final List<Map<String, dynamic>> _flyingReactions = [];
  final List<Timer> _reactionTimers = [];
  Timer? _activityTimer;
  String? _socialStatus;
  bool _reducedMotion = false;
  String? _pressedTarget;

  @override
  void initState() {
    super.initState();
    _rlPolicy = widget.rlPolicy;
    _rooms = widget.repository;
    if (widget.browserGuest) {
      _roomCode.text =
          (widget.initialRoomCode ?? Uri.base.queryParameters['room'] ?? '')
              .trim()
              .toUpperCase();
      _message = widget.firebaseEnabled
          ? 'Enter the room code shared by your host and your player names.'
          : 'Browser joining is unavailable: this build has no Firebase configuration.';
    }
    // Refresh the advisor subtitle once startup loading has settled.
    unawaited(_refreshPolicyAvailability());
  }

  Future<void> _refreshPolicyAvailability() async {
    await _rlPolicy.preload();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _players.dispose();
    _roomCode.dispose();
    _seatName.dispose();
    _roomSubscription?.cancel();
    _requestSubscription?.cancel();
    _socialSubscription?.cancel();
    _activityTimer?.cancel();
    for (final timer in _reactionTimers) {
      timer.cancel();
    }
    super.dispose();
  }

  void _start() {
    if (widget.browserGuest) return;
    final List<String> names = _players.text
        .split(',')
        .map((String name) => name.trim())
        .where((String name) => name.isNotEmpty)
        .toList();
    setState(() {
      _game = WindowGameEngine(names);
      _proposal = null;
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
    if (widget.browserGuest) return;
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
      final String code = _roomCode.text.trim().toUpperCase();
      if (!RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(code)) {
        throw StateError(
          'Enter the six-character room code shared by your host.',
        );
      }
      final List<String> names = parseLobbyPlayers(_seatName.text);
      final FirebaseRoomRepository rooms = _rooms ??= FirebaseRoomRepository();
      await rooms.signInAnonymously();
      final OnlineRoom? lobby = await rooms.loadRoom(code);
      if (!mounted) return;
      if (lobby == null) {
        throw StateError('Room not found. Check the room code.');
      }
      final bool alreadyJoined = lobby.seats.any(
        (RoomSeat seat) => seat.ownerUid == rooms.uid,
      );
      if (!alreadyJoined) {
        addLobbyPlayers(lobby, rooms.uid, names);
        await rooms.requestLobbyJoin(
          roomCode: code,
          seatName: names.first,
          seatNames: names,
        );
        if (!mounted) return;
        setState(
          () => _message = 'Waiting for the host to accept your player names…',
        );
        await rooms
            .observeRoom(code)
            .timeout(
              const Duration(seconds: 20),
              onTimeout: (sink) {
                sink.addError(
                  StateError(
                    'The host did not respond. Ask them to keep the lobby open, then try again.',
                  ),
                );
                sink.close();
              },
            )
            .firstWhere((current) {
              if (current == null) {
                throw StateError('This room is no longer available.');
              }
              if (current.seats.any((seat) => seat.ownerUid == rooms.uid)) {
                return true;
              }
              addLobbyPlayers(current, rooms.uid, names);
              return false;
            });
        if (!mounted) return;
      }
      await _watchRoom(code);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message =
              'Could not join room: ${error is StateError ? error.message : error}';
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
            if (isHost && room.version < _hostVersion) return;
            setState(() {
              if (_room?.version != room.version) {
                _localTurnUi = {};
                _localTurnVersion = -1;
                _proposal = null;
              }
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
            if (_socialRoomCode != room.code) {
              unawaited(_watchSocial(room.code));
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
    await _socialSubscription?.cancel();
    _activityTimer?.cancel();
    for (final timer in _reactionTimers) {
      timer.cancel();
    }
    _reactionTimers.clear();
    if (!mounted) return;
    setState(() {
      _room = null;
      _game = null;
      _requestRoomCode = null;
      _hostVersion = 0;
      _busy = false;
      _social = RoomSocialSnapshot(null);
      _localTurnUi = {};
      _localTurnVersion = -1;
      _proposal = null;
      _seenReactions.clear();
      _flyingReactions.clear();
      _pressedTarget = null;
      _socialStatus = null;
      _socialRoomCode = null;
      _lastActivityId = null;
      _hostSocial = null;
      _pendingSharedUi = null;
      _pendingUiRoom = null;
      _footerExtent = 0;
      _chatSideExtent = 0;
      _chatMinimized = false;
      _hostSocialRoomCode = null;
      _message = widget.browserGuest
          ? 'Enter a room code and your player names to join.'
          : 'Choose player names to begin a local game.';
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

  Map<String, dynamic> get _turnUi => !_isOnline
      ? {}
      : _canControlCurrentTurn && _localTurnVersion == _room!.version
      ? _localTurnUi
      : _social.turnFor(_room!);

  AiMoveProposal? get _visibleProposal =>
      _isOnline ? decodeSharedProposal(_turnUi['proposal']) : _proposal;

  Future<void> _watchSocial(String code) async {
    _socialRoomCode = code;
    await _socialSubscription?.cancel();
    var initial = true;
    _socialSubscription = _rooms!
        .observeSocial(code)
        .listen(
          (snapshot) {
            if (!mounted || _room?.code != code) return;
            final now = DateTime.now().millisecondsSinceEpoch;
            setState(() {
              _social = snapshot;
              _socialStatus = null;
              for (final raw in snapshot.reactions.values) {
                final reaction = socialMap(raw);
                final id = reaction['id'] as String?;
                if (id == null || !_seenReactions.add(id)) continue;
                final age =
                    now - ((reaction['createdAt'] as num?)?.toInt() ?? 0);
                if (initial ||
                    snapshot.isFullSnapshot ||
                    age < -5000 ||
                    age > 5000) {
                  continue;
                }
                if (_flyingReactions.length == 5) _flyingReactions.removeAt(0);
                _flyingReactions.add(reaction);
                late Timer timer;
                timer = Timer(const Duration(seconds: 2), () {
                  _reactionTimers.remove(timer);
                  if (mounted) {
                    setState(
                      () => _flyingReactions.removeWhere((r) => r['id'] == id),
                    );
                  }
                });
                _reactionTimers.add(timer);
              }
              // A reconnect snapshot may restore a dialog, but never replays an old click.
              final activity = snapshot.activityFor(_room!);
              final age = now - ((activity['createdAt'] as num?)?.toInt() ?? 0);
              if (!initial &&
                  !snapshot.isFullSnapshot &&
                  age >= -5000 &&
                  age < 1500 &&
                  activity['id'] != _lastActivityId) {
                _lastActivityId = activity['id'] as String?;
                _pressedTarget = activity['clicked'] as String?;
                _activityTimer?.cancel();
                _activityTimer = Timer(const Duration(milliseconds: 900), () {
                  if (mounted) setState(() => _pressedTarget = null);
                });
              }
            });
            initial = false;
            if (_seenReactions.length > 1000) {
              _seenReactions.retainAll(
                snapshot.reactions.values.map((r) => '${socialMap(r)['id']}'),
              );
            }
          },
          onError: (Object error) {
            if (mounted) {
              setState(() => _socialStatus = 'Room chat is reconnecting…');
            }
          },
        );
  }

  String? _lastActivityId;

  Future<void> _sendSocial(
    String type,
    Map<String, dynamic> action, {
    int? version,
  }) {
    final room = _room;
    if (room == null) return Future<void>.value();
    final send = _socialSendQueue.then(
      (_) => _rooms!.requestSocial(
        roomCode: room.code,
        type: type,
        action: action,
        expectedVersion: version ?? room.version,
      ),
    );
    _socialSendQueue = send.catchError((Object _) {});
    return send;
  }

  void _shareUi(
    String stage, {
    Position? position,
    Orientation? orientation,
    String? clicked,
    String? label,
    _AdvisorMethod? method,
    bool clearProposal = false,
  }) {
    if (!_isOnline || !_canControlCurrentTurn) return;
    final version = _room!.version;
    final proposal = clearProposal ? null : (_proposal ?? _visibleProposal);
    final ui = <String, dynamic>{
      'stage': stage,
      'version': version,
      'playerIndex': _room!.state.currentPlayerIndex,
      'eventId': '${_rooms!.uid}:${_uiSequence++}',
      if (position != null) 'row': position.row,
      if (position != null) 'column': position.column,
      if (orientation != null) 'orientation': orientation.name,
      if (proposal != null) 'proposal': encodeSharedProposal(proposal),
      if (method != null) 'method': method.name,
      'clicked': ?clicked,
      'label': ?label,
    };
    setState(() {
      _localTurnUi = ui;
      _localTurnVersion = version;
    });
    _pendingSharedUi = ui;
    _pendingUiRoom = _room!.code;
    unawaited(_flushSharedUi());
  }

  Future<void> _flushSharedUi() async {
    if (_publishingUi) return;
    _publishingUi = true;
    try {
      while (_pendingSharedUi != null && mounted) {
        final ui = _pendingSharedUi!;
        final code = _pendingUiRoom!;
        _pendingSharedUi = null;
        if (_room?.code != code ||
            _room?.version != ui['version'] ||
            !_canControlCurrentTurn) {
          continue;
        }
        try {
          await _rooms!.publishTurnUi(code, ui);
        } catch (_) {
          // An old view may arrive after the move changed the version. Its
          // rejection is harmless and must never delay or reject that move.
          if (mounted &&
              _room?.code == code &&
              _room?.version == ui['version']) {
            setState(
              () => _socialStatus = 'Turn sharing is temporarily unavailable. Gameplay remains available.',
            );
          }
        }
      }
    } finally {
      _publishingUi = false;
    }
  }

  Future<void> _turnAction(Map<String, dynamic> action, String label) async {
    if (!_canControlCurrentTurn || _busy) return;
    final version = _room!.version;
    _shareUi('idle', clicked: '${action['type']}', label: label);
    if (mounted && _room?.version == version) await _submitOnline(action);
  }

  Widget _chatPanel() => RoomChatPanel(
    sidePanel: !_chatBelow,
    onMinimize: () {
      FocusScope.of(context).unfocus();
      setState(() => _chatMinimized = true);
    },
    sender: roomDeviceLabel(_room!.seats, _rooms!.uid),
    messages: _social.messages,
    onSend: (text) => _sendSocial('chat', {'text': text}),
    onReact: (emoji) => _sendSocial('reaction', {'emoji': emoji}),
    reducedMotion: _reducedMotion,
    onReducedMotion: (value) => setState(() => _reducedMotion = value),
    status: _socialStatus,
  );

  Widget _onlineFrame(Widget child) {
    _measureFooter();
    final dialog = _sharedTurnDialog();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (dialog != null && _canControlCurrentTurn && !_proposing) {
            _shareUi('idle');
          }
        },
      },
      child: PopScope(
        canPop: dialog == null || !_canControlCurrentTurn,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && dialog != null && _canControlCurrentTurn) {
            _shareUi('idle');
          }
        },
        child: Stack(
          children: [
            Positioned.fill(child: child),
            if (dialog != null)
              Positioned.fill(
                top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                bottom: _chatBelow && !_chatMinimized ? _footerExtent : 0,
                right: !_chatBelow && !_chatMinimized ? _chatSideExtent : 0,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !_canControlCurrentTurn,
                        child: ModalBarrier(
                          color: Colors.black54,
                          dismissible: _canControlCurrentTurn && !_proposing,
                          onDismiss: () => _shareUi(
                            'idle',
                            clicked: 'close',
                            label: 'closed the dialog',
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: MediaQuery.removeViewInsets(
                        context: context,
                        removeBottom: true,
                        child: dialog,
                      ),
                    ),
                  ],
                ),
              ),
            Positioned.fill(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
              child: RoomReactionLayer(
                reactions: _flyingReactions,
                reducedMotion: _reducedMotion,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _measureFooter() {
    if (_footerMeasureScheduled) return;
    _footerMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _footerMeasureScheduled = false;
      if (!mounted) return;
      final box = _footerKey.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.hasSize &&
          ((box.size.height - _footerExtent).abs() > 0.5 ||
              (box.size.width - _chatSideExtent).abs() > 0.5)) {
        setState(() {
          _footerExtent = box.size.height;
          _chatSideExtent = box.size.width;
        });
      }
    });
  }

  bool get _chatBelow =>
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      MediaQuery.sizeOf(context).shortestSide < 600;

  Widget _chatRegion(Widget child) => SizedBox(
    key: _footerKey,
    child: Visibility(
      visible: !_chatMinimized,
      maintainState: true,
      child: child,
    ),
  );

  Widget _withSideChat(Widget child) {
    if (!_isOnline || _chatBelow) return child;
    return LayoutBuilder(
      builder: (context, size) => Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, area) => area.maxWidth >= 480
                  ? child
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: 480,
                        height: area.maxHeight,
                        child: child,
                      ),
                    ),
            ),
          ),
          _chatRegion(
            SizedBox(
              width: (size.maxWidth * 0.26).clamp(240.0, 360.0),
              height: size.maxHeight,
              child: SafeArea(top: false, left: false, child: _chatPanel()),
            ),
          ),
        ],
      ),
    );
  }

  Widget get _reopenChat => IconButton(
    tooltip: 'Open chat',
    icon: const Icon(Icons.chat_bubble_outline),
    onPressed: () => setState(() => _chatMinimized = false),
  );

  Widget _roomFooter() => _chatRegion(_bottomChat());

  Widget _bottomChat() {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(
              80,
              media.size.height -
                  media.viewInsets.bottom -
                  media.padding.top -
                  media.padding.bottom -
                  100,
            ),
          ),
          child: SingleChildScrollView(
            reverse: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [_chatPanel()],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseSharedGuess(GuessType guess) async {
    final ui = _turnUi;
    if (ui['stage'] != 'guess' || !_canControlCurrentTurn || _busy) return;
    final position = Position(ui['row'] as int, ui['column'] as int);
    final orientation = Orientation.values.byName(ui['orientation'] as String);
    final version = _room!.version;
    setState(() => _proposal = null);
    _shareUi(
      'idle',
      clicked: guess.name,
      clearProposal: true,
      label:
          'chose ${_guessLabel(guess)} for row ${position.row + 1}, column ${position.column + 1}',
    );
    if (mounted && _room?.version == version) {
      await _submitOnline({
        'type': 'guess',
        'position': [position.row, position.column],
        'orientation': orientation.name,
        'guess': guess.name,
      });
    }
  }

  Widget? _sharedTurnDialog() {
    if (!_isOnline || _game == null || !_room!.started) return null;
    final ui = _turnUi;
    final stage = ui['stage'];
    final active = _canControlCurrentTurn && !_busy;
    final proposal = _visibleProposal;
    Position? position;
    List<GuessOption> options = [];
    if (ui['row'] is int && ui['column'] is int) {
      position = Position(ui['row'], ui['column']);
      if (_game!.isValidSlot(position)) {
        options = _game!.getValidOptionsForCard(position);
      }
    }
    Widget button(
      String key,
      String label,
      VoidCallback action, {
      bool suggested = false,
    }) => FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: _pressedTarget == key
            ? Colors.amber
            : suggested
            ? Colors.lightBlue
            : null,
        disabledBackgroundColor: _pressedTarget == key
            ? Colors.amber
            : suggested
            ? Colors.lightBlue
            : null,
        disabledForegroundColor: _pressedTarget == key || suggested
            ? Colors.black
            : null,
        foregroundColor: _pressedTarget == key || suggested
            ? Colors.black
            : null,
      ),
      onPressed: active ? action : null,
      child: Text(label),
    );
    final widgets = <Widget>[];
    String? title;
    if (stage == 'comparison' && position != null) {
      title = 'Choose the comparison';
      for (final option in options) {
        final selected = position;
        final suggested =
            proposal?.action.position == position &&
            proposal?.action.orientation == option.orientation;
        widgets.add(
          ListTile(
            title: Text(
              option.orientation == Orientation.horizontal
                  ? 'Horizontal cards'
                  : 'Vertical cards',
            ),
            subtitle: Text(
              option.type == GuessOptionType.inBetween
                  ? 'In-between or outside'
                  : 'Higher, same, or lower',
            ),
            tileColor: suggested
                ? Colors.lightBlue.withValues(alpha: 0.25)
                : null,
            trailing: suggested
                ? const Icon(Icons.auto_awesome, color: Colors.lightBlueAccent)
                : null,
            onTap: active
                ? () => _shareUi(
                    'guess',
                    position: selected,
                    orientation: option.orientation,
                    clicked: option.orientation.name,
                    label: 'chose ${option.orientation.name} comparison',
                  )
                : null,
          ),
        );
      }
    } else if (stage == 'guess' && position != null) {
      title = 'Your guess';
      final option = options
          .where((o) => o.orientation.name == ui['orientation'])
          .firstOrNull;
      for (final guess in option?.guesses ?? <GuessType>[]) {
        final suggested =
            proposal?.action.position == position &&
            proposal?.action.orientation == option?.orientation &&
            proposal?.action.guess == guess;
        widgets.add(
          button(
            guess.name,
            '${_guessLabel(guess)}${suggested ? ' · suggested' : ''}',
            () => _chooseSharedGuess(guess),
            suggested: suggested,
          ),
        );
      }
    } else if (stage == 'adviser') {
      title = 'Best-move prediction';
      widgets.add(
        ListTile(
          leading: const Icon(Icons.psychology_outlined),
          title: const Text('RL model'),
          subtitle: Text(_rlPolicy.availabilityMessage),
          onTap: active
              ? () => _calculateProposal(_AdvisorMethod.rlModel)
              : null,
        ),
      );
      widgets.add(
        ListTile(
          leading: const Icon(Icons.query_stats_outlined),
          title: const Text('Pure statistics'),
          subtitle: const Text(
            'Estimate your future drinks using public card history.',
          ),
          onTap: active
              ? () => _calculateProposal(_AdvisorMethod.statistics)
              : null,
        ),
      );
    } else if (stage == 'calculating') {
      title = 'Finding best move…';
      widgets.add(
        Text(ui['method'] == 'statistics' ? 'Pure statistics' : 'RL model'),
      );
    }
    if (title == null) return null;
    return _MovableGameDialog(
      key: ValueKey('turn-dialog:${_room!.version}:$stage'),
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!active)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Watching ${_game!.currentPlayer}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (stage == 'adviser' || stage == 'comparison')
            ...widgets
          else
            Wrap(spacing: 8, runSpacing: 8, children: widgets),
        ],
      ),
      actions: const [],
    );
  }

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
        _proposal = null;
        _message = 'Submitting move…';
      });
      if (_isHost) {
        await _queueHostOperation(() => _applyHostAction(action));
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

  Future<void> _proposeMove() async {
    final WindowGameEngine? game = _game;
    if (game == null || !_canControlCurrentTurn || _busy || _proposing) return;
    if (_isOnline) {
      _shareUi(
        'adviser',
        clicked: 'propose',
        label: 'opened best-move prediction',
      );
      return;
    }
    final _AdvisorMethod? method = await _showMovableGameDialog<_AdvisorMethod>(
      title: 'Best-move prediction',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.psychology_outlined),
            title: const Text('RL model'),
            subtitle: Text(_rlPolicy.availabilityMessage),
            onTap: () => Navigator.pop(context, _AdvisorMethod.rlModel),
          ),
          ListTile(
            leading: const Icon(Icons.query_stats_outlined),
            title: const Text('Pure statistics'),
            subtitle: const Text(
              'Estimate your future drinks using public card history.',
            ),
            onTap: () => Navigator.pop(context, _AdvisorMethod.statistics),
          ),
        ],
      ),
    );
    if (!mounted || method == null) return;
    await _calculateProposal(method);
  }

  Future<void> _calculateProposal(_AdvisorMethod method) async {
    final game = _game;
    if (game == null || !_canControlCurrentTurn || _busy || _proposing) return;
    final requestState = jsonEncode(
      GameStateCodec.encode(game.publicObservation()),
    );
    setState(() => _proposing = true);
    _shareUi(
      'calculating',
      method: method,
      clicked: method.name,
      label:
          'selected ${method == _AdvisorMethod.statistics ? 'Pure statistics' : 'RL model'}',
    );
    try {
      final AiMoveProposal? proposal = method == _AdvisorMethod.rlModel
          ? await _rlPolicy.propose(game)
          : await WindowRlPolicy.proposeStatistics(game);
      if (!mounted ||
          !identical(game, _game) ||
          jsonEncode(GameStateCodec.encode(game.publicObservation())) !=
              requestState) {
        return;
      }
      setState(() {
        _proposal = proposal;
        _message = proposal == null
            ? 'Finish the pending action before requesting a proposal.'
            : 'Suggested move: ${proposal.action.label}.';
      });
      _shareUi('suggestion', method: method, clearProposal: proposal == null);
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Prediction failed: $error');
        _shareUi('idle');
      }
    } finally {
      if (mounted) setState(() => _proposing = false);
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

  Future<void> _queueHostOperation(Future<void> Function() action) {
    final Future<void> operation = _hostRequestQueue.then((_) => action());
    _hostRequestQueue = operation.catchError((Object error) {
      if (mounted) {
        setState(() => _message = 'Room request failed: $error');
      }
    });
    return operation;
  }

  void _watchRequests(String code) {
    if (_requestRoomCode == code && _requestSubscription != null) return;
    _requestSubscription?.cancel();
    _requestRoomCode = code;
    _requestSubscription = _rooms!
        .observeRequests(code)
        .listen(
          (RoomRequest request) {
            final social = [
              'chat',
              'reaction',
              'turnUi',
            ].contains(request.type);
            if (social) {
              final operation = _hostSocialQueue.then(
                (_) => _processHostRequest(request),
              );
              _hostSocialQueue = operation.catchError((Object _) {});
            } else {
              unawaited(
                _queueHostOperation(() => _processHostRequest(request))
                    .catchError((Object _) {}),
              );
            }
          },
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
      if (['chat', 'reaction', 'turnUi'].contains(request.type)) {
        if (_hostSocialRoomCode != room.code || _hostSocial == null) {
          _hostSocial = await _rooms!.loadSocial(room.code);
          _hostSocialRoomCode = room.code;
        }
        if (!mounted || _room?.code != room.code) return;
        final patch = socialRequestPatch(
          request: request,
          room: room,
          game: game,
          social: _hostSocial!,
        );
        if (patch.isNotEmpty) {
          await _rooms!.publishSocial(room.code, patch);
          _hostSocial = _hostSocial!.updated(patch);
        }
      } else if (request.type == 'joinLobby' && !room.started) {
        final List<RoomSeat> seats = addLobbyPlayers(
          room,
          request.uid,
          request.requestedNames.map((String name) => name.trim()).toList(),
        );
        await _publishHostState(seats: seats);
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
      unawaited(
        _rooms!.deleteRequest(room.code, request.id).catchError((Object _) {
          if (mounted && _room?.code == room.code) {
            setState(
              () => _socialStatus =
                  'Room request cleanup failed; gameplay remains available.',
            );
          }
        }),
      );
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
        _room = OnlineRoom(
          code: room.code,
          version: nextVersion,
          hostUid: room.hostUid,
          state: _game!.exportState(),
          seats: seats ?? room.seats,
          started: started ?? room.started,
          deckSize: _game!.exportState().deck.length,
        );
        _busy = false;
        _message = '${_game!.currentPlayer}\'s turn.';
      });
    }
  }

  Future<void> _select(Position position) async {
    final WindowGameEngine game = _game!;
    final PolicyAction? suggestedAction = _proposal?.action;
    final List<GuessOption> options = game.getValidOptionsForCard(position);
    if (options.isEmpty) {
      setState(() => _message = 'That card cannot be selected yet.');
      return;
    }
    if (_isOnline) {
      if (!_canControlCurrentTurn || _busy) return;
      _shareUi(
        options.length == 1 ? 'guess' : 'comparison',
        position: position,
        orientation: options.length == 1 ? options.single.orientation : null,
        clicked: 'card:${position.row}:${position.column}',
        label:
            'selected card at row ${position.row + 1}, column ${position.column + 1}',
      );
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
                      tileColor:
                          suggestedAction?.position == position &&
                              suggestedAction?.orientation == value.orientation
                          ? Colors.lightBlue.withValues(alpha: 0.25)
                          : null,
                      trailing:
                          suggestedAction?.position == position &&
                              suggestedAction?.orientation == value.orientation
                          ? const Icon(
                              Icons.auto_awesome,
                              color: Colors.lightBlueAccent,
                            )
                          : null,
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
                style:
                    suggestedAction?.position == position &&
                        suggestedAction?.orientation == option.orientation &&
                        suggestedAction?.guess == value
                    ? FilledButton.styleFrom(
                        backgroundColor: Colors.lightBlue,
                        foregroundColor: Colors.black,
                      )
                    : null,
                onPressed: () => Navigator.pop(context, value),
                child: Text(
                  suggestedAction?.position == position &&
                          suggestedAction?.orientation == option.orientation &&
                          suggestedAction?.guess == value
                      ? '${_guessLabel(value)} · suggested'
                      : _guessLabel(value),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (!mounted || guess == null) return;
    // A proposal is deliberately a one-move hint. It disappears as soon as
    // the player commits any guess, whether or not it was the suggested one.
    setState(() => _proposal = null);
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

  Widget _buildBrowserEntry() => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
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
                      'Join Window',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Play with friends, directly in your browser. No installation required.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ask your host to create a lobby in the smartphone or PC/laptop app and share its room code.',
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _roomCode,
                      enabled: widget.firebaseEnabled && !_busy,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Room code',
                        hintText: 'ABC234',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _seatName,
                      enabled: widget.firebaseEnabled && !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Players on this device',
                        hintText: 'Anna, Ben',
                        helperText: 'One or more names, separated by commas.',
                      ),
                      onSubmitted: (_) {
                        if (widget.firebaseEnabled && !_busy) _joinRoom();
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _message,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: widget.firebaseEnabled && !_busy
                          ? _joinRoom
                          : null,
                      icon: const Icon(Icons.login),
                      label: Text(_busy ? 'Joining…' : 'Join online room'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final WindowGameEngine? game = _game;
    if (game == null && widget.browserGuest) return _buildBrowserEntry();
    if (game == null) {
      return Scaffold(
        body: Center(
          child: SingleChildScrollView(
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
                        decoration: const InputDecoration(
                          labelText: 'Room code',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _seatName,
                        decoration: const InputDecoration(
                          labelText: 'Players on this device',
                          hintText: 'Anna, Ben',
                          helperText: 'Separate names with commas.',
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
        ),
      );
    }
    if (_isOnline && !_room!.started) {
      final OnlineRoom room = _room!;
      return _onlineFrame(
        Scaffold(
          bottomNavigationBar: _chatBelow ? _roomFooter() : null,
          appBar: AppBar(
            title: const Text('Window lobby'),
            actions: <Widget>[
              if (_isOnline && _chatMinimized) _reopenChat,
              IconButton(
                tooltip: 'Leave lobby and return to menu',
                icon: const Icon(Icons.home_outlined),
                onPressed: _returnToMenu,
              ),
            ],
          ),
          body: _withSideChat(
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
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
                            if (_isHost &&
                                WindowFirebaseOptions.browserUrl !=
                                    null) ...<Widget>[
                              const SizedBox(height: 12),
                              const Text(
                                'Friends can join in the app with this room code, or in their browser at:',
                              ),
                              SelectableText(WindowFirebaseOptions.browserUrl!),
                              const Text(
                                'Browser players enter the room code above. No installation required.',
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(
                                      text: WindowFirebaseOptions.browserUrl!,
                                    ),
                                  );
                                  if (mounted) {
                                    setState(
                                      () => _message =
                                          'Browser address copied. Share it together with room ${room.code}.',
                                    );
                                  }
                                },
                                icon: const Icon(Icons.copy),
                                label: const Text('Copy browser address'),
                              ),
                            ],
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
                                onPressed: _busy
                                    ? null
                                    : () {
                                        unawaited(
                                          _queueHostOperation(_startLobbyGame)
                                              .catchError((Object _) {}),
                                        );
                                      },
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
      deckSize: _isOnline && !_isHost ? _room!.deckSize : snapshot.deckSize,
      busy: _busy,
      canControl: _canControlCurrentTurn,
      onEndTurn: () {
        if (_isOnline) {
          _turnAction(<String, dynamic>{'type': 'endTurn'}, 'clicked End turn');
        } else {
          game.endTurn();
          setState(() {
            _proposal = null;
            _message = '${game.currentPlayer}\'s turn.';
          });
        }
      },
      onReset: () {
        if (!_isOnline) {
          game.resetGame();
          setState(() => _message = '${game.currentPlayer} starts a new game.');
        }
      },
      onConfirmSame: () => _turnAction(<String, dynamic>{
        'type': 'confirmSame',
      }, 'confirmed the same-rank penalty'),
      onConfirmRemovals: () => _turnAction(<String, dynamic>{
        'type': 'confirmRemovals',
      }, 'clicked Redeal marked cards'),
      proposal: _visibleProposal,
      pressedTarget: _pressedTarget,
      proposing: _proposing || _turnUi['stage'] == 'calculating',
      policyStatus: _rlPolicy.availabilityMessage,
      onPropose: _proposeMove,
    );
    final Widget board = _Board(
      game: game,
      snapshot: snapshot,
      enabled: _canControlCurrentTurn && !_busy,
      onSelect: _select,
      proposal: _visibleProposal,
      selectedPosition: _turnUi['row'] is int && _turnUi['column'] is int
          ? Position(_turnUi['row'], _turnUi['column'])
          : null,
      pressedTarget: _pressedTarget,
    );
    final scaffold = Scaffold(
      bottomNavigationBar: _isOnline && _chatBelow ? _roomFooter() : null,
      appBar: AppBar(
        title: const Text('Window'),
        actions: <Widget>[
          if (_isOnline && _chatMinimized) _reopenChat,
          IconButton(
            tooltip: _isOnline
                ? 'Leave room and return to menu'
                : 'Return to menu',
            icon: const Icon(Icons.home_outlined),
            onPressed: _returnToMenu,
          ),
        ],
      ),
      body: _withSideChat(
        SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints size) => Padding(
              padding: const EdgeInsets.all(16),
              child: (_isOnline && !_chatBelow) || size.maxWidth >= 900
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
                      children: <Widget>[
                        info,
                        const SizedBox(height: 18),
                        board,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
    return _isOnline ? _onlineFrame(scaffold) : scaffold;
  }
}

class _Info extends StatelessWidget {
  const _Info({
    required this.game,
    required this.snapshot,
    required this.message,
    required this.roomCode,
    required this.deckSize,
    required this.busy,
    required this.canControl,
    required this.onEndTurn,
    required this.onReset,
    required this.onConfirmSame,
    required this.onConfirmRemovals,
    required this.proposal,
    required this.proposing,
    required this.policyStatus,
    required this.onPropose,
    this.pressedTarget,
  });
  final WindowGameEngine game;
  final GameSnapshot snapshot;
  final String message;
  final String? roomCode;
  final int? deckSize;
  final bool busy;
  final bool canControl;
  final VoidCallback onEndTurn;
  final VoidCallback onReset;
  final VoidCallback onConfirmSame;
  final VoidCallback onConfirmRemovals;
  final AiMoveProposal? proposal;
  final bool proposing;
  final String policyStatus;
  final VoidCallback onPropose;
  final String? pressedTarget;
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
          Text(
            deckSize == null
                ? 'Deck: managed by host'
                : 'Deck: $deckSize cards',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: snapshot.turnCanEnd && canControl && !busy
                ? onEndTurn
                : null,
            style: pressedTarget == 'endTurn' || proposal?.action.isPass == true
                ? FilledButton.styleFrom(
                    backgroundColor: pressedTarget == 'endTurn'
                        ? Colors.amber
                        : Colors.lightBlue,
                    disabledBackgroundColor: pressedTarget == 'endTurn'
                        ? Colors.amber
                        : Colors.lightBlue,
                    disabledForegroundColor: Colors.black,
                    foregroundColor: Colors.black,
                  )
                : null,
            child: Text(
              proposal?.action.isPass == true
                  ? 'End turn · suggested'
                  : 'End turn',
            ),
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
          OutlinedButton.icon(
            onPressed: canControl && !busy && !proposing ? onPropose : null,
            icon: const Icon(Icons.psychology_outlined),
            label: Text(proposing ? 'Finding best move…' : 'Propose best move'),
          ),
          const SizedBox(height: 8),
          Text(policyStatus, style: Theme.of(context).textTheme.bodySmall),
          if (proposal != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Suggestion: ${proposal!.action.label}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              '${proposal!.source} · ${proposal!.action.isPass && proposal!.source.contains('statistics') ? 'no immediate drinks' : '${proposal!.source.contains('statistics') ? 'estimated success' : 'model confidence'} ${(proposal!.confidence * 100).toStringAsFixed(0)}%'}'
              '${proposal!.valueEstimate == null ? '' : ' · value ${proposal!.valueEstimate!.toStringAsFixed(2)}'}'
              '${proposal!.expectedDrinks == null ? '' : ' · estimated remaining drinks ${proposal!.expectedDrinks!.toStringAsFixed(1)}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (proposal!.explanation != null) Text(proposal!.explanation!),
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
    super.key,
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
      child: SingleChildScrollView(
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
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
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
    required this.proposal,
    this.selectedPosition,
    this.pressedTarget,
  });
  final WindowGameEngine game;
  final GameSnapshot snapshot;
  final bool enabled;
  final ValueChanged<Position> onSelect;
  final AiMoveProposal? proposal;
  final Position? selectedPosition;
  final String? pressedTarget;
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
    final bool legal = snapshot.validSelectable.contains(position);
    final bool selectable = enabled && legal;
    final bool selected =
        selectedPosition == position ||
        pressedTarget == 'card:${position.row}:${position.column}';
    final bool markedForRemoval = snapshot.pendingRemovals.contains(position);
    final bool proposed = proposal?.action.position == position;
    final double borderWidth = selected
        ? 6
        : markedForRemoval || proposed
        ? 4
        : legal
        ? 3
        : 1;
    final int? card = snapshot.cardGrid[position.row][position.column];
    return Semantics(
      button: selectable,
      label: position == handlePosition
          ? 'Handle card'
          : '${faceUp ? 'Face-up ${game.cardLabel(card!)}' : 'Face-down card'}, '
                'row ${position.row + 1}, column ${position.column + 1}'
                '${legal ? ', selectable' : ''}${proposed ? ', suggested' : ''}${selected ? ', selected' : ''}',
      child: InkWell(
        key: ValueKey('card:${position.row}:${position.column}'),
        onTap: selectable ? () => onSelect(position) : null,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: faceUp ? const Color(0xfff3ead2) : const Color(0xff164b83),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: markedForRemoval
                  ? Colors.redAccent
                  : (proposed
                        ? Colors.lightBlueAccent
                        : (legal || selected ? Colors.amber : Colors.black54)),
              width: borderWidth,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Colors.black38,
                blurRadius: 3,
                offset: Offset(1, 2),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(borderWidth),
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
