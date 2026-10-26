import 'firebase_room_repository.dart';
import 'player_names.dart';

/// All names on a shared device join together, before the host starts play.
List<String> parseLobbyPlayers(String text) {
  final List<String> names = splitPlayerNames(text);
  if (names.isEmpty) throw StateError('Enter at least one player name.');
  if (names.map((String name) => name.toLowerCase()).toSet().length !=
      names.length) {
    throw StateError('Every player on this device needs a unique name.');
  }
  return names;
}

List<RoomSeat> addLobbyPlayers(
  OnlineRoom room,
  String uid,
  List<String> names,
) {
  names = names.map(capitalizeName).toList();
  if (room.started) {
    throw StateError(
      'This game has already started. Ask the host for a new lobby.',
    );
  }
  if (room.seats.any((RoomSeat seat) => seat.ownerUid == uid)) {
    throw StateError('This device has already joined the lobby.');
  }
  final Set<String> taken = room.seats
      .map((RoomSeat seat) => seat.name.toLowerCase())
      .toSet();
  if (names.isEmpty ||
      names.any(
        (String name) => name.trim().isEmpty || !taken.add(name.toLowerCase()),
      )) {
    throw StateError(
      'Player names must be unique in the lobby. Choose other names.',
    );
  }
  return <RoomSeat>[
    ...room.seats,
    for (int index = 0; index < names.length; index++)
      RoomSeat(
        index: room.seats.length + index,
        name: names[index],
        ownerUid: uid,
      ),
  ];
}

/// Host-only lobby editing. An empty group stays registered so its device can
/// receive players again without reconnecting or changing anonymous identity.
List<RoomSeat> replaceDevicePlayers(
  OnlineRoom room,
  String uid,
  List<String> names,
) {
  if (room.started) {
    throw StateError('Return to the lobby before editing players.');
  }
  if (!room.deviceLabels.containsKey(uid)) {
    throw StateError('This device has not joined the room.');
  }
  final cleaned = names
      .map(capitalizeName)
      .where((name) => name.isNotEmpty)
      .toList();
  final taken = room.seats
      .where((seat) => seat.ownerUid != uid)
      .map((seat) => seat.name.toLowerCase())
      .toSet();
  if (cleaned.any((name) => !taken.add(name.toLowerCase()))) {
    throw StateError(
      'Player names must be unique in the lobby. Choose other names.',
    );
  }
  final result = <RoomSeat>[];
  bool inserted = false;
  void insert() {
    for (final name in cleaned) {
      result.add(RoomSeat(index: result.length, name: name, ownerUid: uid));
    }
    inserted = true;
  }

  for (final seat in room.seats) {
    if (seat.ownerUid == uid) {
      if (!inserted) insert();
    } else {
      result.add(
        RoomSeat(
          index: result.length,
          name: seat.name,
          ownerUid: seat.ownerUid,
        ),
      );
    }
  }
  if (!inserted) insert();
  if (result.isEmpty) {
    throw StateError('Keep at least one player in the lobby.');
  }
  return result;
}
