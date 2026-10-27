import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'async_games.dart';
import 'localization.dart';

String lobbyDate(BuildContext context, String? value) {
  if (value == null) return tr(context).asyncUnknownDate;
  final date = DateTime.tryParse(value);
  return date == null
      ? tr(context).asyncUnknownDate
      : DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
            .format(date);
}

String lobbyStatus(AppLocalizations l, String value) => switch (value) {
  'playing' => l.asyncInProgress,
  'finished' => l.asyncFinished,
  _ => l.asyncLobby,
};
Future<bool> confirmLobbyDeletion(BuildContext context, String code) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context).asyncDeleteQuestion(code)),
        content: Text(tr(context).asyncDeleteHelp),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context).cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context).asyncDeleteLobby),
          ),
        ],
      ),
    ) ==
    true;

class AsyncLobbyManagement extends StatefulWidget {
  const AsyncLobbyManagement({super.key, required this.client});
  final AsyncGamesClient client;
  @override
  State<AsyncLobbyManagement> createState() => _AsyncLobbyManagementState();
}

class _AsyncLobbyManagementState extends State<AsyncLobbyManagement> {
  final _input = TextEditingController();
  String? _key;
  String? _error;
  bool _busy = false;
  List<Map<String, dynamic>> _lobbies = [];
  int? _next;
  AppLocalizations get l => tr(context);
  @override
  void dispose() {
    _key = null;
    _input.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AsyncApiException && error.status == 403
              ? l.asyncInvalidAdminKey
              : error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetch({String? key, bool more = false}) async {
    final usedKey = key ?? _key!;
    final data = await widget.client.adminCall(
      usedKey,
      '/lobbies?offset=${more ? _next ?? 0 : 0}',
    );
    if (!mounted) return;
    setState(() {
      _key = usedKey;
      _input.clear();
      final rows = (data['lobbies'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      _lobbies = more ? [..._lobbies, ...rows] : rows;
      _next = (data['nextOffset'] as num?)?.toInt();
    });
  }

  Future<void> _delete(Map<String, dynamic> room) async {
    if (!await confirmLobbyDeletion(context, room['code'] as String) ||
        !mounted) {
      return;
    }
    await _run(() async {
      await widget.client.adminCall(_key!, '/lobbies/${room['code']}', {
        'type': 'delete',
        'version': room['version'],
        'revision': room['revision'],
      });
      await _fetch();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(l.asyncManageLobbies),
      actions: [
        if (_key != null)
          IconButton(
            tooltip: l.asyncRefresh,
            onPressed: _busy ? null : () => _run(() => _fetch()),
            icon: const Icon(Icons.refresh),
          ),
        if (_key != null)
          IconButton(
            tooltip: l.asyncAdminLock,
            onPressed: _busy
                ? null
                : () => setState(() {
                    _key = null;
                    _lobbies = [];
                    _next = null;
                    _error = null;
                  }),
            icon: const Icon(Icons.lock),
          ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(_key == null ? l.asyncAdminHelp : l.asyncManagementHelp),
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
            if (_key == null) ...[
              TextField(
                controller: _input,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: l.asyncAdminKey),
                onSubmitted: (_) {
                  if (!_busy) {
                    _run(() => _fetch(key: _input.text.trim().toLowerCase()));
                  }
                },
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => _fetch(key: _input.text.trim().toLowerCase()),
                      ),
                child: Text(l.asyncAdminUnlock),
              ),
            ] else ...[
              if (_lobbies.isEmpty && !_busy) Text(l.asyncNoLobbies),
              for (final room in _lobbies)
                Card(
                  child: ListTile(
                    title: Text(
                      '${room['code']} · ${lobbyStatus(l, room['status'] as String)}',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((room['players'] as List).join(', ')),
                        Text(
                          l.asyncCreated(
                            lobbyDate(context, room['createdDate'] as String?),
                          ),
                        ),
                        Text(
                          l.asyncLastActive(
                            lobbyDate(
                              context,
                              room['lastActiveDate'] as String?,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      tooltip: l.asyncDeleteLobby,
                      onPressed: _busy ? null : () => _delete(room),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
              if (_next != null)
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => _fetch(more: true)),
                  child: Text(l.asyncLoadMore),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}
