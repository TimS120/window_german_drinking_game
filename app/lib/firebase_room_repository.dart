import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'game_engine.dart';
import 'game_state_codec.dart';

class RoomSeat {
  const RoomSeat({required this.index, required this.name, this.ownerUid});
  final int index;
  final String name;
  final String? ownerUid;

  factory RoomSeat.fromJson(Map<Object?, Object?> value) => RoomSeat(
    index: (value['index'] as num?)?.toInt() ?? 0,
    name: '${value['name'] ?? ''}',
    ownerUid: value['ownerUid'] as String?,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'index': index,
    'name': name,
    'ownerUid': ownerUid,
  };
}

class OnlineRoom {
  const OnlineRoom({
    required this.code,
    required this.version,
    required this.hostUid,
    required this.state,
    required this.seats,
    required this.started,
  });

  final String code;
  final int version;
  final String hostUid;
  final GameState state;
  final List<RoomSeat> seats;
  final bool started;

  factory OnlineRoom.fromSnapshot(String code, DataSnapshot snapshot) {
    final Map<Object?, Object?> raw = Map<Object?, Object?>.from(
      snapshot.value as Map,
    );
    final List<RoomSeat> seats = (raw['seats'] as List? ?? const <Object?>[])
        .whereType<Map>()
        .map(
          (Map value) => RoomSeat.fromJson(Map<Object?, Object?>.from(value)),
        )
        .toList();
    return OnlineRoom(
      code: code,
      version: (raw['version'] as num?)?.toInt() ?? 0,
      hostUid: '${raw['hostUid'] ?? ''}',
      state: GameStateCodec.decode(
        Map<Object?, Object?>.from(raw['state'] as Map),
      ),
      seats: seats,
      // Rooms created before the lobby migration were already active games.
      started: raw['started'] != false,
    );
  }
}

class RoomRequest {
  const RoomRequest({
    required this.id,
    required this.uid,
    required this.type,
    required this.action,
    required this.expectedVersion,
    this.seatName,
  });

  final String id;
  final String uid;
  final String type;
  final Map<String, dynamic> action;
  final int expectedVersion;
  final String? seatName;

  factory RoomRequest.fromSnapshot(DataSnapshot snapshot) {
    final Map<Object?, Object?> raw = Map<Object?, Object?>.from(
      snapshot.value as Map,
    );
    final Object? rawAction = raw['action'];
    return RoomRequest(
      id: snapshot.key!,
      uid: '${raw['uid'] ?? ''}',
      type: '${raw['type'] ?? ''}',
      action: rawAction is Map
          ? rawAction.map(
              (Object? key, Object? value) => MapEntry('$key', value),
            )
          : <String, dynamic>{},
      expectedVersion: (raw['expectedVersion'] as num?)?.toInt() ?? -1,
      seatName: raw['seatName'] as String?,
    );
  }
}

/// Spark-plan multiplayer transport.
///
/// The room creator is the trusted host: only its authenticated Firebase UID
/// may read/write private state, publish board snapshots, or process requests.
/// Guests can read the sanitized public state and add a request only under
/// their own UID. This is intentionally host-authoritative, not a substitute
/// for a server-side anti-cheat service.
class FirebaseRoomRepository {
  FirebaseRoomRepository({FirebaseDatabase? database})
    : _database = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _database;
  final Random _random = Random.secure();

  Future<String> signInAnonymously() async {
    final User? user = FirebaseAuth.instance.currentUser;
    return user?.uid ??
        (await FirebaseAuth.instance.signInAnonymously()).user!.uid;
  }

  String get uid => FirebaseAuth.instance.currentUser!.uid;

  Stream<OnlineRoom?> observeRoom(String roomCode) =>
      _publicRef(roomCode).onValue.map(
        (DatabaseEvent event) => event.snapshot.exists
            ? OnlineRoom.fromSnapshot(roomCode.toUpperCase(), event.snapshot)
            : null,
      );

  Stream<RoomRequest> observeRequests(String roomCode) => _requestsRef(roomCode)
      .onChildAdded
      .where((DatabaseEvent event) => event.snapshot.exists)
      .map((DatabaseEvent event) => RoomRequest.fromSnapshot(event.snapshot));

  Future<GameState?> loadPrivateState(String roomCode) async =>
      decodePrivate(await _privateRef(roomCode).get());

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
      final DatabaseReference publicRef = _publicRef(code);
      final TransactionResult reserved = await publicRef.runTransaction((
        Object? current,
      ) {
        if (current != null) return Transaction.abort();
        return Transaction.success(
          _publicRoom(
            hostUid: uid,
            version: 1,
            seats: seats,
            state: state,
            started: false,
          ),
        );
      });
      if (!reserved.committed) continue;
      await _privateRef(code).set(GameStateCodec.encode(state));
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
    'createdAt': ServerValue.timestamp,
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
    'createdAt': ServerValue.timestamp,
  });

  Future<void> publishState({
    required String roomCode,
    required String hostUid,
    required int version,
    required List<RoomSeat> seats,
    required GameState state,
    required bool started,
  }) =>
      _database.ref('rooms/${roomCode.toUpperCase()}').update(<String, dynamic>{
        'private': GameStateCodec.encode(state),
        'public': _publicRoom(
          hostUid: hostUid,
          version: version,
          seats: seats,
          state: state,
          started: started,
        ),
      });

  Future<void> deleteRequest(String roomCode, String requestId) =>
      _requestsRef(roomCode).child(requestId).remove();

  GameState? decodePrivate(DataSnapshot snapshot) {
    if (!snapshot.exists || snapshot.value is! Map) return null;
    return GameStateCodec.decode(
      Map<Object?, Object?>.from(snapshot.value as Map),
    );
  }

  DatabaseReference _publicRef(String code) =>
      _database.ref('rooms/${code.toUpperCase()}/public');
  DatabaseReference _privateRef(String code) =>
      _database.ref('rooms/${code.toUpperCase()}/private');
  DatabaseReference _requestsRef(String code) =>
      _database.ref('rooms/${code.toUpperCase()}/requests');

  Future<void> _addRequest(String roomCode, Map<String, dynamic> value) =>
      _requestsRef(roomCode).push().set(value);

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
        // Do not write null here: Realtime Database may turn the row into a
        // sparse map. -1 is not a real card id and is never displayed while
        // the matching faceUp entry is false.
        if (!state.faceUp[row][column]) cards[row][column] = -1;
      }
    }
    value['cardGrid'] = cards;
    value['deck'] = <int>[];
    return value;
  }
}
