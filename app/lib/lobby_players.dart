import 'firebase_room_repository.dart';

/// All names on a shared device join together, before the host starts play.
List<String> parseLobbyPlayers(String text) {
  final List<String> names = text
      .split(',')
      .map((String name) => name.trim())
      .where((String name) => name.isNotEmpty)
      .toList();
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
