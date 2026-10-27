import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'async_games.dart';
import 'async_notifications.dart';
import 'async_lobby_management.dart';
import 'appearance.dart';
import 'localization.dart';
import 'main.dart';
import 'player_names.dart';
import 'firebase_room_repository.dart';
import 'firebase_options.dart';
import 'rl_policy.dart';

class AsyncGamesScreen extends StatefulWidget {
  const AsyncGamesScreen({
    super.key,
    required this.rlPolicy,
    this.initialCode,
    this.client,
  });
  final WindowRlPolicy rlPolicy;
  final String? initialCode;
  final AsyncGamesClient? client;
  @override
  State<AsyncGamesScreen> createState() => _AsyncGamesScreenState();
}

class _AsyncGamesScreenState extends State<AsyncGamesScreen>
    with WidgetsBindingObserver {
  final _names = TextEditingController();
  final _code = TextEditingController();
  late final _identity = AsyncIdentity();
  AsyncGamesClient? _client;
  bool _busy = true;
  bool _inGame = false;
  String? _error;
  bool _notifications = false;
  List<OnlineRoom> _games = [];
  AppLocalizations get l => tr(context);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _code.text = (widget.initialCode ?? '').toUpperCase();
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.client == null) _client?.close();
    _names.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_inGame &&
        !_busy &&
        _client != null) {
      unawaited(_refresh());
    }
  }

  Future<void> _load() async {
    await _run(() async {
      if (widget.client != null) {
        _client = widget.client;
      } else {
        await _identity.load();
        _client = AsyncGamesClient(identity: _identity);
      }
      if (widget.client == null && AsyncNotifications.supported) {
        _notifications = await AsyncNotifications.enabled;
      }
      await _refreshList();
      if (AsyncNotifications.supported) {
        unawaited(
          AsyncNotifications.restoreRegistration().catchError((Object _) {}),
        );
      }
      if (widget.initialCode != null) {
        final existing = _games
            .where((game) => game.code == widget.initialCode)
            .firstOrNull;
        if (existing != null && mounted) await _open(existing.code);
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PlatformException
              ? (error.message ?? error.code).split('\n').first
              : error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshList() async {
    final client = _client!;
    final codes = await client.games();
    final games = <OnlineRoom>[];
    // A list refresh is explicit; it never polls every saved game in background.
    for (final code in codes.reversed) {
      try {
        final value = await client.call('/games/$code');
        games.add(
          OnlineRoom.fromJson(
            code,
            Map<String, dynamic>.from(value['room'] as Map),
          ),
        );
      } on AsyncApiException catch (error) {
        if (error.status != 404 && error.status != 410) rethrow;
      }
    }
    if (mounted) setState(() => _games = games);
  }

  Future<void> _refresh() => _run(_refreshList);
  Future<void> _open(String code, [Map<String, dynamic>? initial]) async {
    final value = initial ?? await _client!.call('/games/$code');
    if (!mounted) return;
    final repository = AsyncRoomRepository(_client!, code, value);
    _inGame = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => GameShell(
            firebaseEnabled: true,
            rlPolicy: widget.rlPolicy,
            browserGuest: false,
            repository: repository,
            asyncRoomCode: code,
          ),
        ),
      );
    } finally {
      repository.close();
      _inGame = false;
    }
    if (mounted) await _refreshList();
  }

  List<String> _playerNames() {
    final names = splitPlayerNames(_names.text);
    if (names.isEmpty) throw StateError(l.enterPlayer);
    if (names.map((n) => n.toLowerCase()).toSet().length != names.length) {
      throw StateError(l.uniquePlayers);
    }
    _names.text = names.join(', ');
    return names;
  }

  Future<void> _create() => _run(() async {
    final value = await _client!.create(_playerNames());
    final code = (value['room'] as Map)['code'] as String;
    await _open(code, value);
  });
  Future<void> _join() => _run(() async {
    final code = _code.text.trim().toUpperCase();
    if (!RegExp(r'^[A-HJ-NP-Z2-9]{10}$').hasMatch(code)) {
      throw StateError(l.asyncCodeHelp);
    }
    final value = await _client!.join(code, _playerNames());
    await _open(code, value);
  });
  Future<void> _recovery() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.asyncRecovery),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.asyncRecoveryHelp),
              const SizedBox(height: 12),
              SelectableText(_client!.identity.recoveryCode),
              TextButton.icon(
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: _client!.identity.recoveryCode),
                ),
                icon: const Icon(Icons.copy),
                label: Text(l.asyncCopyCode),
              ),
              TextField(
                controller: controller,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: l.asyncRestoreCode),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l.asyncRestore),
          ),
        ],
      ),
    );
    // Dispose after the dialog's exit animation no longer uses the controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (code == null || !mounted) return;
    await _run(() async {
      final registration = await AsyncNotifications.registeredId;
      if (registration != null) await _client!.unregisterToken(registration);
      await _client!.identity.recover(code);
      await _refreshList();
      if (registration != null) await _client!.registerToken(registration);
    });
  }

  Future<void> _delete(OnlineRoom game) async {
    if (!await confirmLobbyDeletion(context, game.code) || !mounted) return;
    await _run(() async {
      await _client!.deleteGame(game);
      await _refreshList();
    });
  }

  Future<void> _manage() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AsyncLobbyManagement(client: _client!),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _enableNotifications() => _run(() async {
    final token = await AsyncNotifications.enable();
    await _client!.registerToken(token);
    await AsyncNotifications.rememberEnabled();
    if (mounted) setState(() => _notifications = true);
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(l.asyncGames),
      actions: [
        const ThemePicker(),
        const LanguagePicker(),
        IconButton(
          tooltip: l.asyncRecovery,
          onPressed: _busy || _client == null ? null : _recovery,
          icon: const Icon(Icons.key),
        ),
        IconButton(
          tooltip: l.asyncRefresh,
          onPressed: _busy || _client == null ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(l.asyncDescription),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (AsyncNotifications.supported)
              OutlinedButton.icon(
                onPressed: _busy || _client == null
                    ? null
                    : _enableNotifications,
                icon: Icon(
                  _notifications
                      ? Icons.notifications_active
                      : Icons.notifications_outlined,
                ),
                label: Text(
                  _notifications
                      ? l.asyncNotificationsEnabled
                      : l.asyncEnableNotifications,
                ),
              ),
            OutlinedButton.icon(
              onPressed: _busy || _client == null ? null : _manage,
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: Text(l.asyncManageLobbies),
            ),
            TextField(
              controller: _names,
              decoration: InputDecoration(
                labelText: l.devicePlayers,
                hintText: 'Anna, Ben',
                helperText: l.separateNames,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || _client == null ? null : _create,
              icon: const Icon(Icons.add),
              label: Text(l.asyncCreate),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l.asyncCode,
                helperText: l.asyncCodeHelp,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _busy || _client == null ? null : _join,
              icon: const Icon(Icons.login),
              label: Text(l.asyncJoin),
            ),
            const Divider(height: 32),
            Text(l.asyncOngoing, style: Theme.of(context).textTheme.titleLarge),
            if (_games.isEmpty && !_busy) Text(l.asyncEmpty),
            for (final game in _games)
              Card(
                child: ListTile(
                  title: Text(game.state.players.join(', ')),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${game.code} · ${!game.started
                            ? l.asyncLobby
                            : game.state.faceUp.expand((r) => r).where((v) => v).length == 22
                            ? l.windowComplete
                            : l.playerTurn(game.state.players[game.state.currentPlayerIndex])}',
                      ),
                      Text(
                        l.asyncLastActive(
                          lobbyDate(context, game.lastActiveDate),
                        ),
                      ),
                    ],
                  ),
                  leading: Icon(
                    !game.started
                        ? Icons.group
                        : game.seats[game.state.currentPlayerIndex].ownerUid ==
                              _client?.uid
                        ? Icons.play_circle
                        : Icons.hourglass_empty,
                  ),
                  onTap: _busy ? null : () => _run(() => _open(game.code)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l.asyncCopyInvite,
                        icon: const Icon(Icons.share),
                        onPressed: () {
                          final base = WindowFirebaseOptions.browserUrl;
                          Clipboard.setData(
                            ClipboardData(
                              text: base == null
                                  ? game.code
                                  : Uri.parse(base)
                                        .replace(
                                          queryParameters: {'async': game.code},
                                        )
                                        .toString(),
                            ),
                          );
                        },
                      ),
                      if (game.hostUid == _client?.uid)
                        IconButton(
                          tooltip: l.asyncDeleteLobby,
                          onPressed: _busy ? null : () => _delete(game),
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
