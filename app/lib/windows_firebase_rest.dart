import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'firebase_options.dart';
import 'firebase_room_repository.dart';
import 'game_engine.dart';
import 'game_state_codec.dart';

/// Firebase Auth and Realtime Database transport for native Windows.
///
/// It deliberately uses Firebase's documented HTTPS endpoints rather than
/// the FlutterFire Windows plugins. This avoids their platform-thread
/// callbacks while retaining anonymous auth and the existing database rules.
class WindowsFirebaseRestRoomRepository {
  WindowsFirebaseRestRoomRepository({WindowFirebaseRestOptions? options})
    : _options = options ?? WindowFirebaseOptions.windowsRestOptions!,
      _client = http.Client();

  final WindowFirebaseRestOptions _options;
  final http.Client _client;
  final Random _random = Random.secure();
  String? _uid;
  String? _idToken;

  String get uid {
    final String? currentUid = _uid;
    if (currentUid == null) throw StateError('Sign in before using a room.');
    return currentUid;
  }

  Future<String> signInAnonymously() async {
    if (_uid != null) return _uid!;
    final Object? response = await _jsonRequest(
      method: 'POST',
      uri: Uri.https(
        'identitytoolkit.googleapis.com',
        '/v1/accounts:signUp',
        <String, String>{'key': _options.apiKey},
      ),
      body: <String, dynamic>{'returnSecureToken': true},
    );
    if (response is! Map) {
      throw StateError('Firebase returned an invalid identity.');
    }
    final Map<String, dynamic> result = Map<String, dynamic>.from(response);
    _uid = result['localId'] as String?;
    _idToken = result['idToken'] as String?;
    if (_uid == null || _idToken == null) {
      throw StateError('Firebase did not return an anonymous identity.');
    }
    return _uid!;
  }

  Stream<OnlineRoom?> observeRoom(
    String roomCode,
  ) => _poll<OnlineRoom?>(() async {
    final Object? value = await _read('rooms/${roomCode.toUpperCase()}/public');
    return value is Map
        ? OnlineRoom.fromJson(
            roomCode.toUpperCase(),
            Map<String, dynamic>.from(value),
          )
        : null;
  }, (OnlineRoom? room) => room == null ? 'null' : jsonEncode(room.toJson()));

  Stream<RoomRequest> observeRequests(String roomCode) {
    final Set<String> emitted = <String>{};
    late StreamController<RoomRequest> controller;
    Timer? timer;
    var running = false;
    Future<void> poll() async {
      if (running || controller.isClosed) return;
      running = true;
      try {
        final Object? value = await _read(
          'rooms/${roomCode.toUpperCase()}/requests',
        );
        if (value is Map) {
          for (final MapEntry<dynamic, dynamic> entry in value.entries) {
            final String id = '${entry.key}';
            if (!emitted.add(id) || entry.value is! Map) continue;
            controller.add(
              RoomRequest.fromJson(
                id,
                Map<String, dynamic>.from(entry.value as Map),
              ),
            );
          }
        }
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      } finally {
        running = false;
      }
    }

    controller = StreamController<RoomRequest>(
      onListen: () {
        unawaited(poll());
        timer = Timer.periodic(
          const Duration(milliseconds: 700),
          (_) => unawaited(poll()),
        );
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }

  Future<GameState?> loadPrivateState(String roomCode) async {
    final Object? value = await _read(
      'rooms/${roomCode.toUpperCase()}/private',
    );
    return value is Map
        ? GameStateCodec.decode(Map<Object?, Object?>.from(value))
        : null;
  }

  Future<String> createRoom({
    required GameState state,
    required List<String> localPlayers,
  }) async {
    final List<RoomSeat> seats = localPlayers
        .asMap()
        .entries
        .map(
          (MapEntry<int, String> entry) =>
              RoomSeat(index: entry.key, name: entry.value, ownerUid: uid),
        )
        .toList();
    for (int attempt = 0; attempt < 8; attempt++) {
      final String code = _newCode();
      final bool reserved = await _putIfMissing(
        'rooms/$code/public',
        _publicRoom(
          hostUid: uid,
          version: 1,
          seats: seats,
          state: state,
          started: false,
        ),
      );
      if (!reserved) continue;
      await _write('PUT', 'rooms/$code/private', GameStateCodec.encode(state));
      return code;
    }
    throw StateError('Could not reserve a room code. Please try again.');
  }

  Future<void> requestLobbyJoin({
    required String roomCode,
    required String seatName,
  }) => _addRequest(roomCode, <String, dynamic>{
    'uid': uid,
    'type': 'joinLobby',
    'seatName': seatName,
    'expectedVersion': -1,
    'createdAt': <String, String>{'.sv': 'timestamp'},
  });

  Future<void> requestAction({
    required String roomCode,
    required int expectedVersion,
    required Map<String, dynamic> action,
  }) => _addRequest(roomCode, <String, dynamic>{
    'uid': uid,
    'type': 'action',
    'expectedVersion': expectedVersion,
    'action': action,
    'createdAt': <String, String>{'.sv': 'timestamp'},
  });

  Future<void> publishState({
    required String roomCode,
    required String hostUid,
    required int version,
    required List<RoomSeat> seats,
    required GameState state,
    required bool started,
  }) async {
    final String code = roomCode.toUpperCase();
    await _write('PUT', 'rooms/$code/private', GameStateCodec.encode(state));
    await _write(
      'PUT',
      'rooms/$code/public',
      _publicRoom(
        hostUid: hostUid,
        version: version,
        seats: seats,
        state: state,
        started: started,
      ),
    );
  }

  Future<void> deleteRequest(String roomCode, String requestId) => _write(
    'DELETE',
    'rooms/${roomCode.toUpperCase()}/requests/$requestId',
    null,
  );

  Stream<T> _poll<T>(
    Future<T> Function() load,
    String Function(T) fingerprint,
  ) {
    late StreamController<T> controller;
    Timer? timer;
    var running = false;
    String? previous;
    Future<void> poll() async {
      if (running || controller.isClosed) return;
      running = true;
      try {
        final T value = await load();
        final String current = fingerprint(value);
        if (current != previous) {
          previous = current;
          controller.add(value);
        }
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      } finally {
        running = false;
      }
    }

    controller = StreamController<T>(
      onListen: () {
        unawaited(poll());
        timer = Timer.periodic(
          const Duration(milliseconds: 700),
          (_) => unawaited(poll()),
        );
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }

  Future<void> _addRequest(String roomCode, Map<String, dynamic> value) async {
    await _write('POST', 'rooms/${roomCode.toUpperCase()}/requests', value);
  }

  Future<Object?> _read(String path) =>
      _jsonRequest(method: 'GET', uri: _databaseUri(path));

  Future<void> _write(String method, String path, Object? body) async {
    await _jsonRequest(method: method, uri: _databaseUri(path), body: body);
  }

  Future<bool> _putIfMissing(String path, Map<String, dynamic> body) async {
    final http.Response response = await _client.put(
      _databaseUri(path),
      headers: <String, String>{
        'content-type': 'application/json',
        'if-match': 'null_etag',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode == 412) return false;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Firebase request failed (${response.statusCode}): ${response.body}',
      );
    }
    return true;
  }

  Uri _databaseUri(String path) {
    final Uri base = Uri.parse(_options.databaseUrl);
    return base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/$path.json',
      queryParameters: <String, String>{'auth': _idToken!},
    );
  }

  Future<Object?> _jsonRequest({
    required String method,
    required Uri uri,
    Object? body,
  }) async {
    final http.Request request = http.Request(method, uri);
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.StreamedResponse response = await _client.send(request);
    final String text = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Firebase request failed (${response.statusCode}): $text',
      );
    }
    final Object? decoded = text.isEmpty ? null : jsonDecode(text);
    return decoded;
  }

  String _newCode() {
    const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List<String>.generate(
      6,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }

  Map<String, dynamic> _publicRoom({
    required String hostUid,
    required int version,
    required List<RoomSeat> seats,
    required GameState state,
    required bool started,
  }) => <String, dynamic>{
    'hostUid': hostUid,
    'version': version,
    'seats': seats.map((RoomSeat seat) => seat.toJson()).toList(),
    'started': started,
    'state': _publicState(state),
  };

  Map<String, dynamic> _publicState(GameState state) {
    final Map<String, dynamic> value = GameStateCodec.encode(state);
    final List<List<dynamic>> cards = (value['cardGrid'] as List<dynamic>)
        .map((dynamic row) => List<dynamic>.from(row as List<dynamic>))
        .toList();
    for (int row = 0; row < cards.length; row++) {
      for (int column = 0; column < cards[row].length; column++) {
        if (!state.faceUp[row][column]) cards[row][column] = -1;
      }
    }
    value['cardGrid'] = cards;
    value['deck'] = <int>[];
    return value;
  }
}
