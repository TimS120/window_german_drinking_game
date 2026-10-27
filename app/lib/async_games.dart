import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_room_repository.dart';
import 'firebase_options.dart';
import 'windows_firebase_rest.dart';
import 'room_social.dart';

const asyncBackendUrl = String.fromEnvironment('WINDOW_ASYNC_URL');
String randomIdentity([int bytes = 32]) {
  final random = Random.secure();
  return List.generate(
    bytes,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

abstract interface class AsyncIdentityStore {
  Future<String?> read();
  Future<void> write(String secret);
}

class PreferencesIdentityStore implements AsyncIdentityStore {
  final _preferences = SharedPreferencesAsync();
  @override
  Future<String?> read() => _preferences.getString('window.async.identity');
  @override
  Future<void> write(String secret) =>
      _preferences.setString('window.async.identity', secret);
}

class AsyncIdentity {
  AsyncIdentity({AsyncIdentityStore? store})
    : _store = store ?? PreferencesIdentityStore();
  final AsyncIdentityStore _store;
  String? _secret;
  String get recoveryCode => _secret!;
  Future<void> load() async {
    final saved = await _store.read();
    _secret = saved != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(saved)
        ? saved
        : randomIdentity();
    // Persistence must succeed before any game is created under this identity.
    await _store.write(_secret!);
  }

  Future<void> recover(String code) async {
    final normalized = code.replaceAll(RegExp(r'[\s-]'), '').toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(normalized)) {
      throw const FormatException('Invalid recovery code.');
    }
    await _store.write(normalized);
    _secret = normalized;
  }
}

class AsyncApiException extends StateError {
  AsyncApiException(this.status, String message) : super(message);
  final int status;
}

class AsyncGamesClient {
  AsyncGamesClient({
    required this.identity,
    String? endpoint,
    http.Client? client,
  }) : endpoint = endpoint ?? asyncBackendUrl,
       _http = client ?? http.Client();
  final AsyncIdentity identity;
  final String endpoint;
  final http.Client _http;
  String? uid;
  Future<Map<String, dynamic>> call(
    String path, [
    Map<String, dynamic>? body,
  ]) => _request(path, body, identity.recoveryCode);
  Future<Map<String, dynamic>> adminCall(
    String key,
    String path, [
    Map<String, dynamic>? body,
  ]) => _request('/admin$path', body, key);
  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, dynamic>? body,
    String token,
  ) async {
    if (endpoint.isEmpty) {
      throw StateError('The asynchronous backend has not been configured.');
    }
    final uri = Uri.parse('$endpoint$path');
    http.Response response;
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    // Same body and request ID on retry. The server deduplicates mutations.
    for (var attempt = 0; ; attempt++) {
      try {
        response =
            await (body == null
                    ? _http.get(uri, headers: headers)
                    : _http.post(uri, headers: headers, body: jsonEncode(body)))
                .timeout(const Duration(seconds: 20));
        break;
      } on Object {
        if (attempt >= 1) rethrow;
      }
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw AsyncApiException(
        response.statusCode,
        data['error'] as String? ?? 'Service unavailable.',
      );
    }
    return data;
  }

  Future<List<String>> games() async {
    final result = await call('/me');
    uid = result['uid'] as String;
    return List<String>.from(result['games'] as List);
  }

  Future<Map<String, dynamic>> create(List<String> names) =>
      call('/games', {'names': names, 'requestId': randomIdentity(16)});
  Future<Map<String, dynamic>> join(String code, List<String> names) =>
      call('/games/$code', {'type': 'join', 'names': names});
  Future<void> registerToken(String token) async {
    await call('/me', {'type': 'token', 'token': token});
  }

  Future<void> unregisterToken(String token) async {
    await call('/me', {'type': 'removeToken', 'token': token});
  }

  Future<void> deleteGame(OnlineRoom room) async {
    await call('/games/${room.code}', {
      'type': 'delete',
      'version': room.version,
      'revision': room.revision ?? room.version,
    });
  }

  void close() => _http.close();
}

/// Server-authoritative adapter for the existing lobby/board UI. Only visible
/// cards reach the device; the host gets the same redacted snapshot as guests.
class AsyncRoomRepository extends FirebaseRoomRepository
    with WidgetsBindingObserver {
  AsyncRoomRepository(this.client, this.code, Map<String, dynamic> initial)
    : super(
        transport: WindowsFirebaseRestRoomRepository(
          options: const WindowFirebaseRestOptions(
            apiKey: 'unused',
            databaseUrl: 'https://unused.invalid',
          ),
        ),
      ) {
    _accept(initial);
    WidgetsBinding.instance.addObserver(this);
  }
  final AsyncGamesClient client;
  final String code;
  late OnlineRoom _room;
  RoomSocialSnapshot _social = RoomSocialSnapshot(null);
  final _rooms = StreamController<OnlineRoom?>.broadcast();
  final _socials = StreamController<RoomSocialSnapshot>.broadcast();
  Timer? _timer;
  bool _closed = false, _polling = false, _deleted = false;
  int _revision = -1;
  @override
  bool get serverHosted => true;
  @override
  String get uid => client.uid!;
  @override
  Future<String> signInAnonymously() async => uid;
  void _accept(Map<String, dynamic> value) {
    if (_deleted || _closed) return;
    final revision = ((value['room'] as Map)['revision'] as num?)?.toInt() ?? 0;
    if (revision < _revision) return;
    _revision = revision;
    _room = OnlineRoom.fromJson(
      code,
      Map<String, dynamic>.from(value['room'] as Map),
    );
    _social = RoomSocialSnapshot(value['social']);
    if (!_closed) {
      _rooms.add(_room);
      _socials.add(_social);
    }
  }

  @override
  Future<void> refreshRoom() => refresh();

  Future<void> refresh() async {
    if (_closed || _deleted || _polling) return;
    _polling = true;
    try {
      _accept(await client.call('/games/$code'));
    } catch (error) {
      if (error is AsyncApiException && error.status == 410) {
        _markDeleted();
      } else if (!_closed) {
        _rooms.addError(error);
      }
    } finally {
      _polling = false;
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
      _startPolling();
    } else {
      _timer?.cancel();
    }
  }

  @override
  Stream<OnlineRoom?> observeRoom(String roomCode) {
    _startPolling();
    return Stream<OnlineRoom?>.multi((sink) {
      final subscription = _rooms.stream.listen(
        sink.add,
        onError: sink.addError,
      );
      sink.add(_room);
      sink.onCancel = subscription.cancel;
    });
  }

  @override
  Stream<RoomSocialSnapshot> observeSocial(String code) => Stream.multi((sink) {
    final subscription = _socials.stream.listen(
      sink.add,
      onError: sink.addError,
    );
    sink.add(_social);
    sink.onCancel = subscription.cancel;
  });
  @override
  Future<OnlineRoom?> loadRoom(String roomCode) async =>
      _deleted ? null : _room;
  @override
  Future<RoomSocialSnapshot> loadSocial(String code) async => _social;
  void _markDeleted() {
    if (_deleted) return;
    _deleted = true;
    _timer?.cancel();
    if (!_closed) _rooms.addError(const RoomDeletedException());
  }

  Future<void> _send(Map<String, dynamic> body) async {
    if (_deleted) throw const RoomDeletedException();
    try {
      _accept(
        await client.call('/games/$code', {
          ...body,
          'requestId': randomIdentity(16),
        }),
      );
    } on AsyncApiException catch (error) {
      if (error.status == 410) _markDeleted();
      rethrow;
    }
  }

  @override
  Future<void> controlRoom(String type, int version) =>
      _send({'type': type, 'version': version});
  @override
  Future<void> editPlayers(
    String uid,
    List<String> names,
    String label,
    int version,
  ) => _send({
    'type': 'edit',
    'uid': uid,
    'names': names,
    'label': label,
    'version': version,
  });
  @override
  Future<void> requestAction({
    required String roomCode,
    required int expectedVersion,
    required Map<String, dynamic> action,
  }) => _send({'type': 'action', 'version': expectedVersion, 'action': action});
  @override
  Future<void> requestSocial({
    required String roomCode,
    required String type,
    required Map<String, dynamic> action,
    int expectedVersion = -1,
  }) => _send({'type': type, 'action': action});
  @override
  Future<void> publishTurnUi(String code, Map<String, dynamic> ui) async {}
  void close() {
    _closed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_rooms.close());
    unawaited(_socials.close());
  }
}
