import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'game_engine.dart';
import 'game_state_codec.dart';

class RoomSeat {
  const RoomSeat({required this.index, required this.name, this.ownerUid});
  final int index;
  final String name;
  final String? ownerUid;
  bool get isRemote => ownerUid == null;

  factory RoomSeat.fromJson(Map<Object?, Object?> value) => RoomSeat(
    index: (value['index'] as num?)?.toInt() ?? 0,
    name: '${value['name'] ?? ''}',
    ownerUid: value['ownerUid'] as String?,
  );
}

class OnlineRoom {
  const OnlineRoom({
    required this.code,
    required this.version,
    required this.hostUid,
    required this.state,
    required this.seats,
  });

  final String code;
  final int version;
  final String hostUid;
  final GameState state;
  final List<RoomSeat> seats;

  factory OnlineRoom.fromSnapshot(String code, DataSnapshot snapshot) {
    final Map<Object?, Object?> raw = Map<Object?, Object?>.from(
      snapshot.value as Map,
    );
    final List<RoomSeat> seats = (raw['seats'] as List? ?? const <Object?>[])
        .whereType<Map>()
        .map((Map value) => RoomSeat.fromJson(Map<Object?, Object?>.from(value)))
        .toList();
    return OnlineRoom(
      code: code,
      version: (raw['version'] as num?)?.toInt() ?? 0,
      hostUid: '${raw['hostUid'] ?? ''}',
      state: GameStateCodec.decode(Map<Object?, Object?>.from(raw['state'] as Map)),
      seats: seats,
    );
  }
}

/// The client may observe room snapshots, but it never writes game state.
/// Every mutation goes through a callable Cloud Function.
class FirebaseRoomRepository {
  FirebaseRoomRepository({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<String> signInAnonymously() async {
    final User? user = FirebaseAuth.instance.currentUser;
    return user?.uid ?? (await FirebaseAuth.instance.signInAnonymously()).user!.uid;
  }

  String get uid => FirebaseAuth.instance.currentUser!.uid;

  Stream<OnlineRoom?> observeRoom(String roomCode) => FirebaseDatabase.instance
      .ref('rooms/${roomCode.toUpperCase()}/public')
      .onValue
      .map((DatabaseEvent event) => event.snapshot.exists
          ? OnlineRoom.fromSnapshot(roomCode.toUpperCase(), event.snapshot)
          : null);

  Future<String> createRoom({
    required List<String> localPlayers,
    required List<String> remoteSeats,
  }) async {
    final HttpsCallableResult<dynamic> result = await _functions
        .httpsCallable('createRoom')
        .call(<String, dynamic>{
          'localPlayers': localPlayers,
          'remoteSeats': remoteSeats,
        });
    return '${(result.data as Map)['roomCode']}';
  }

  Future<void> joinRoom({required String roomCode, required String seatName}) =>
      _call('joinRoom', <String, dynamic>{
        'roomCode': roomCode.toUpperCase(),
        'seatName': seatName,
      });

  Future<void> submitAction({
    required String roomCode,
    required int expectedVersion,
    required Map<String, dynamic> action,
  }) => _call('submitAction', <String, dynamic>{
    'roomCode': roomCode,
    'expectedVersion': expectedVersion,
    'action': action,
  });

  Future<void> _call(String name, Map<String, dynamic> data) async {
    await _functions.httpsCallable(name).call(data);
  }
}
