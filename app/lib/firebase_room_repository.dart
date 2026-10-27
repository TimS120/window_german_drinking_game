import 'game_engine.dart';
import 'game_state_codec.dart';
import 'windows_firebase_rest.dart';
import 'room_social.dart';

class RoomDeletedException implements Exception {
  const RoomDeletedException();
}

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
    this.deckSize,
    this.debugState,
    this.devices = const {},
    this.controlId = 0,
    this.controlNotice,
    this.revision,
    this.createdDate,
    this.lastActiveDate,
  });

  final String code;
  final int version;
  final String hostUid;
  final GameState state;
  final List<RoomSeat> seats;
  final bool started;

  /// Public count only; guests never receive the cards remaining in the deck.
  final int? deckSize;
  final GameState? debugState;
  final Map<String, String> devices;
  final int controlId;
  final String? controlNotice;
  final int? revision;
  final String? createdDate;
  final String? lastActiveDate;
  Map<String, String> get deviceLabels {
    final labels = Map<String, String>.from(devices);
    for (final uid in [
      hostUid,
      ...seats.map((seat) => seat.ownerUid).whereType<String>(),
    ]) {
      labels.putIfAbsent(uid, () => 'Device ${labels.length + 1}');
    }
    return labels;
  }

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
      deckSize: (raw['deckSize'] as num?)?.toInt(),
      devices: raw['devices'] is Map
          ? (raw['devices'] as Map).map(
              (key, value) => MapEntry('$key', '$value'),
            )
          : const {},
      controlId: (raw['controlId'] as num?)?.toInt() ?? 0,
      controlNotice: raw['controlNotice'] as String?,
      revision: (raw['revision'] as num?)?.toInt(),
      createdDate: raw['createdDate'] as String?,
      lastActiveDate: raw['lastActiveDate'] as String?,
      debugState: raw['debugState'] is Map
          ? GameStateCodec.decode(
              Map<Object?, Object?>.from(raw['debugState'] as Map),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'code': code,
    'version': version,
    'hostUid': hostUid,
    'state': GameStateCodec.encode(state),
    'seats': seats.map((RoomSeat seat) => seat.toJson()).toList(),
    'started': started,
    'deckSize': deckSize,
    'devices': deviceLabels,
    'controlId': controlId,
    'controlNotice': controlNotice,
    if (revision != null) 'revision': revision,
    if (createdDate != null) 'createdDate': createdDate,
    if (lastActiveDate != null) 'lastActiveDate': lastActiveDate,
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
    this.seatNames = const <String>[],
    this.createdAt,
  });

  final String id;
  final String uid;
  final String type;
  final Map<String, dynamic> action;
  final int expectedVersion;
  final String? seatName;
  final List<String> seatNames;
  final int? createdAt;

  List<String> get requestedNames => seatNames.isNotEmpty
      ? seatNames
      : <String>[if (seatName != null) seatName!.trim()];

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
      createdAt: (raw['createdAt'] as num?)?.toInt(),
      seatName: raw['seatName'] as String?,
      seatNames:
          (raw['seatNames'] as List?)?.whereType<String>().toList() ??
          const <String>[],
    );
  }
}

/// Cross-platform Firebase transport using HTTPS APIs and anonymous auth.
/// This avoids the unstable native Firebase Windows plugin while retaining
/// Firebase's existing security rules and host-authoritative room model.
class FirebaseRoomRepository {
  FirebaseRoomRepository({WindowsFirebaseRestRoomRepository? transport})
    : _rest = transport ?? WindowsFirebaseRestRoomRepository();

  final WindowsFirebaseRestRoomRepository _rest;

  bool get serverHosted => false;
  Future<void> refreshRoom() async {}
  Future<void> controlRoom(String type, int version) =>
      throw UnsupportedError('Client-hosted room.');
  Future<void> editPlayers(
    String uid,
    List<String> names,
    String label,
    int version,
  ) => throw UnsupportedError('Client-hosted room.');

  Future<void> publishTurnUi(String code, Map<String, dynamic> ui) =>
      _rest.publishTurnUi(code, ui);

  Future<String> signInAnonymously() => _rest.signInAnonymously();
  Stream<RoomSocialSnapshot> observeSocial(String code) =>
      _rest.observeSocial(code);
  Future<RoomSocialSnapshot> loadSocial(String code) => _rest.loadSocial(code);
  Future<void> publishSocial(String code, Map<String, dynamic> patch) =>
      _rest.publishSocial(code, patch);
  Future<void> requestSocial({
    required String roomCode,
    required String type,
    required Map<String, dynamic> action,
    int expectedVersion = -1,
  }) => _rest.requestSocial(
    roomCode: roomCode,
    type: type,
    action: action,
    expectedVersion: expectedVersion,
  );
  String get uid => _rest.uid;
  Stream<OnlineRoom?> observeRoom(String roomCode) =>
      _rest.observeRoom(roomCode);
  Future<OnlineRoom?> loadRoom(String roomCode) => _rest.loadRoom(roomCode);
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
    List<String> seatNames = const <String>[],
  }) => _rest.requestLobbyJoin(
    roomCode: roomCode,
    seatName: seatName,
    seatNames: seatNames,
  );
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
    bool developerMode = false,
    Map<String, dynamic> roomMetadata = const {},
  }) => _rest.publishState(
    roomCode: roomCode,
    hostUid: hostUid,
    version: version,
    seats: seats,
    state: state,
    started: started,
    developerMode: developerMode,
    roomMetadata: roomMetadata,
  );
  Future<void> deleteRequest(String roomCode, String requestId) =>
      _rest.deleteRequest(roomCode, requestId);
}
