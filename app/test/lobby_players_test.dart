import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/firebase_room_repository.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/lobby_players.dart';

OnlineRoom lobby({bool started = false, List<RoomSeat>? seats}) => OnlineRoom(
  code: 'ABC234',
  version: 1,
  hostUid: 'host',
  state: WindowGameEngine(<String>['Host'], seed: 1).exportState(),
  seats:
      seats ??
      const <RoomSeat>[RoomSeat(index: 0, name: 'Host', ownerUid: 'host')],
  started: started,
);

void main() {
  test('host device edits preserve ownership, reindex seats and retain empty devices', () {
    final room = OnlineRoom(
      code: 'ABC234',
      version: 1,
      hostUid: 'host',
      state: WindowGameEngine(['Host', 'Anna']).exportState(),
      started: false,
      devices: const {'host': 'Living room', 'guest': 'Kitchen'},
      seats: const [
        RoomSeat(index: 0, name: 'Host', ownerUid: 'host'),
        RoomSeat(index: 1, name: 'Anna', ownerUid: 'guest'),
      ],
    );
    final edited = replaceDevicePlayers(room, 'guest', ['Ben', 'Carla']);
    expect(edited.map((s) => s.name), ['Host', 'Ben', 'Carla']);
    expect(edited.map((s) => s.index), [0, 1, 2]);
    expect(edited.skip(1).every((s) => s.ownerUid == 'guest'), isTrue);
    final empty = replaceDevicePlayers(room, 'guest', []);
    final emptyRoom = OnlineRoom(
      code: room.code,
      version: 2,
      hostUid: room.hostUid,
      state: room.state,
      started: false,
      seats: empty,
      devices: room.devices,
    );
    expect(emptyRoom.deviceLabels['guest'], 'Kitchen');
    expect(
      replaceDevicePlayers(emptyRoom, 'guest', ['Dana']).last.ownerUid,
      'guest',
    );
    expect(
      () => replaceDevicePlayers(room, 'guest', ['host']),
      throwsStateError,
    );
    expect(
      () => replaceDevicePlayers(room, 'guest', ['Ben', 'ben']),
      throwsStateError,
    );
    expect(
      () => replaceDevicePlayers(room, 'unknown', ['Ben']),
      throwsStateError,
    );
    expect(() => replaceDevicePlayers(lobby(), 'host', []), throwsStateError);
    expect(
      () => replaceDevicePlayers(lobby(started: true), 'host', ['Ben']),
      throwsStateError,
    );
  });

  test('shared-device names are trimmed and must be unique', () {
    expect(parseLobbyPlayers(' Anna, , Ben '), <String>['Anna', 'Ben']);
    expect(() => parseLobbyPlayers(' , '), throwsStateError);
    expect(() => parseLobbyPlayers('Anna, anna'), throwsStateError);
  });

  test(
    'joins several players atomically and preserves seat order and ownership',
    () {
      final List<RoomSeat> seats = addLobbyPlayers(lobby(), 'guest', <String>[
        'Anna',
        'Ben',
      ]);
      expect(seats.map((RoomSeat seat) => seat.name), <String>[
        'Host',
        'Anna',
        'Ben',
      ]);
      expect(seats.map((RoomSeat seat) => seat.index), <int>[0, 1, 2]);
      expect(
        seats.skip(1).every((RoomSeat seat) => seat.ownerUid == 'guest'),
        isTrue,
      );
      final List<RoomSeat> next = addLobbyPlayers(
        lobby(seats: seats),
        'other',
        <String>['Carla'],
      );
      expect(next.map((RoomSeat seat) => seat.name), <String>[
        'Host',
        'Anna',
        'Ben',
        'Carla',
      ]);
    },
  );

  test('rejects late players, conflicting names and repeated device joins', () {
    expect(
      () => addLobbyPlayers(lobby(started: true), 'guest', <String>['Anna']),
      throwsStateError,
    );
    expect(
      () => addLobbyPlayers(lobby(), 'guest', <String>['Anna', 'host']),
      throwsStateError,
    );
    expect(
      () => addLobbyPlayers(lobby(), 'guest', <String>['Anna', 'anna']),
      throwsStateError,
    );
    expect(
      () => addLobbyPlayers(lobby(), 'host', <String>['Anna']),
      throwsStateError,
    );
  });

  test('accepts both old one-name requests and shared-device requests', () {
    final RoomRequest old = RoomRequest.fromJson('old', <String, dynamic>{
      'uid': 'guest',
      'type': 'joinLobby',
      'seatName': ' Anna ',
    });
    expect(old.requestedNames, <String>['Anna']);
    final RoomRequest shared = RoomRequest.fromJson('new', <String, dynamic>{
      'uid': 'guest',
      'type': 'joinLobby',
      'seatName': 'Anna',
      'seatNames': <String>['Anna', 'Ben'],
    });
    expect(shared.requestedNames, <String>['Anna', 'Ben']);
  });
}
