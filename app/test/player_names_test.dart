import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/player_names.dart';
import 'package:window_game/lobby_players.dart';
import 'package:window_game/firebase_room_repository.dart';
import 'package:window_game/game_engine.dart';

void main() {
  test(
    'names capitalize the initial Unicode character while preserving spelling',
    () {
      expect(capitalizeName('  tom  '), 'Tom');
      expect(capitalizeName('äNNA'), 'ÄNNA');
      expect(capitalizeName('élise'), 'Élise');
      expect(capitalizeName('o’Neill'), 'O’Neill');
      expect(capitalizeName('McDonald'), 'McDonald');
      expect(capitalizeName('TOM'), 'TOM');
      expect(capitalizeName(''), '');
      expect(capitalizeName('  '), '');
      expect(capitalizeName('😀tom'), '😀tom');
      expect(splitPlayerNames('tom, , anna, élise '), ['Tom', 'Anna', 'Élise']);
    },
  );
  test('browser joins and host edits enforce capitalization at the acceptance boundary', () {
    expect(parseLobbyPlayers(' tom, äNNA '), ['Tom', 'ÄNNA']);
    expect(() => parseLobbyPlayers('tom, Tom'), throwsStateError);
    final room = OnlineRoom(
      code: 'ABC234',
      version: 1,
      hostUid: 'host',
      started: false,
      state: WindowGameEngine(['Host']).exportState(),
      seats: const [RoomSeat(index: 0, name: 'Host', ownerUid: 'host')],
    );
    final joined = addLobbyPlayers(room, 'guest', ['  anna ', 'élise']);
    expect(joined.skip(1).map((seat) => seat.name), ['Anna', 'Élise']);
    final shared = OnlineRoom(
      code: room.code,
      version: 2,
      hostUid: room.hostUid,
      state: room.state,
      started: false,
      seats: joined,
    );
    final edited = replaceDevicePlayers(shared, 'guest', ['sam', '  zoë ']);
    expect(edited.skip(1).map((seat) => seat.name), ['Sam', 'Zoë']);
    expect(edited.skip(1).every((seat) => seat.ownerUid == 'guest'), isTrue);
    expect(
      () => replaceDevicePlayers(shared, 'guest', ['host']),
      throwsStateError,
    );
  });
}
