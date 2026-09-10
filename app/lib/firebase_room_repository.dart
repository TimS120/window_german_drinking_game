import 'game_engine.dart';
import 'game_state_codec.dart';
import 'windows_firebase_rest.dart';

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

  factory OnlineRoom.fromJson(String code, Map<String, dynamic> raw) {
    final Object? rawSeats = raw['seats'];
    final List<RoomSeat> seats = rawSeats is List
        ? rawSeats
              .whereType<Map>()
              .map(
                (Map value) =>
                    RoomSeat.fromJson(Map<Object?, Object?>.from(value)),
              )
              .toList()
        : <RoomSeat>[];
    return OnlineRoom(
      code: code,
      version: (raw['version'] as num?)?.toInt() ?? 0,
      hostUid: '${raw['hostUid'] ?? ''}',
      state: GameStateCodec.decode(
        Map<Object?, Object?>.from(raw['state'] as Map),
      ),
      seats: seats,
      started: raw['started'] != false,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'code': code,
    'version': version,
    'hostUid': hostUid,
    'state': GameStateCodec.encode(state),
    'seats': seats.map((RoomSeat seat) => seat.toJson()).toList(),
    'started': started,
  };
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

  factory RoomRequest.fromJson(String id, Map<String, dynamic> raw) {
    final Object? rawAction = raw['action'];
    return RoomRequest(
      id: id,
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

/// Cross-platform Firebase transport using HTTPS APIs and anonymous auth.
/// This avoids the unstable native Firebase Windows plugin while retaining
/// Firebase's existing security rules and host-authoritative room model.
class FirebaseRoomRepository {
  FirebaseRoomRepository() : _rest = WindowsFirebaseRestRoomRepository();

  final WindowsFirebaseRestRoomRepository _rest;

  Future<String> signInAnonymously() => _rest.signInAnonymously();
  String get uid => _rest.uid;
  Stream<OnlineRoom?> observeRoom(String roomCode) =>
      _rest.observeRoom(roomCode);
  Stream<RoomRequest> observeRequests(String roomCode) =>
      _rest.observeRequests(roomCode);
  Future<GameState?> loadPrivateState(String roomCode) =>
      _rest.loadPrivateState(roomCode);
  Future<String> createRoom({
    required GameState state,
    required List<String> localPlayers,
  }) => _rest.createRoom(state: state, localPlayers: localPlayers);
  Future<void> requestLobbyJoin({
    required String roomCode,
    required String seatName,
  }) => _rest.requestLobbyJoin(roomCode: roomCode, seatName: seatName);
  Future<void> requestAction({
    required String roomCode,
    required int expectedVersion,
    required Map<String, dynamic> action,
  }) => _rest.requestAction(
    roomCode: roomCode,
    expectedVersion: expectedVersion,
    action: action,
  );
  Future<void> publishState({
    required String roomCode,
    required String hostUid,
    required int version,
    required List<RoomSeat> seats,
    required GameState state,
    required bool started,
  }) => _rest.publishState(
    roomCode: roomCode,
    hostUid: hostUid,
    version: version,
    seats: seats,
    state: state,
    started: started,
  );
  Future<void> deleteRequest(String roomCode, String requestId) =>
      _rest.deleteRequest(roomCode, requestId);
}
