import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/firebase_room_repository.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/rl_policy.dart';
import 'package:window_game/room_social.dart';

void main() {
  late WindowGameEngine game;
  late OnlineRoom room;
  setUp(() {
    game = WindowGameEngine(['Max', 'Heiko', 'Tom', 'Anna'], seed: 1);
    room = OnlineRoom(
      code: 'ABC234',
      version: 7,
      hostUid: 'host',
      state: game.exportState(),
      started: true,
      seats: const [
        RoomSeat(index: 0, name: 'Max', ownerUid: 'host'),
        RoomSeat(index: 1, name: 'Heiko', ownerUid: 'host'),
        RoomSeat(index: 2, name: 'Tom', ownerUid: 'host'),
        RoomSeat(index: 3, name: 'Anna', ownerUid: 'guest'),
      ],
    );
  });

  Map<String, dynamic> patch(
    String type,
    Map<String, dynamic> action, {
    String uid = 'host',
    int version = 7,
    int time = 10000,
    String id = 'new',
    Object? social,
  }) => socialRequestPatch(
    request: RoomRequest(
      id: id,
      uid: uid,
      type: type,
      action: action,
      expectedVersion: version,
      createdAt: time,
    ),
    room: room,
    game: game,
    social: RoomSocialSnapshot(social),
  );

  test(
    'shared devices have stable grouped names; single players use their name',
    () {
      expect(roomDeviceLabel(room.seats, 'host'), 'Device 1 (Max, Heiko, Tom)');
      expect(roomDeviceLabel(room.seats, 'guest'), 'Anna');
    },
  );

  test('chat derives its sender and prunes history using deltas', () {
    final messages = {
      for (var i = 0; i < 100; i++)
        'old$i': {
          'uid': 'guest',
          'sender': 'Anna',
          'text': 'Message $i',
          'createdAt': i,
        },
    };
    final result = patch(
      'chat',
      {'text': ' Hello 😂 ', 'sender': 'Impostor'},
      social: {'messages': messages},
    );
    expect(result['messages/new']['sender'], 'Device 1 (Max, Heiko, Tom)');
    expect(result['messages/new']['text'], 'Hello 😂');
    expect(result.containsKey('messages/old0'), isTrue);
    expect(result['messages/old0'], isNull);
    expect(result.length, 2);
    expect(patch('chat', {'text': 'x'}, uid: 'outsider'), isEmpty);
    expect(patch('chat', {'text': 'x' * 501}), isEmpty);
  });

  test('reaction palette and per-device cooldown are enforced by host', () {
    final result = patch('reaction', {'emoji': '🎉'});
    expect(result['reactions/host']['sender'], 'Device 1 (Max, Heiko, Tom)');
    final social = {
      'reactions': {'host': result['reactions/host']},
    };
    expect(
      patch('reaction', {'emoji': '😂'}, time: 10999, social: social),
      isEmpty,
    );
    expect(
      patch('reaction', {'emoji': '😂'}, time: 11000, social: social),
      isNotEmpty,
    );
    expect(patch('reaction', {'emoji': 'unsupported'}), isEmpty);
  });

  test('only current seat owner at the current version can share turn UI', () {
    final position = game.snapshot().validSelectable.first;
    final option = game.getValidOptionsForCard(position).first;
    final ui = {
      'stage': 'guess',
      'row': position.row,
      'column': position.column,
      'orientation': option.orientation.name,
      'clicked': 'card:${position.row}:${position.column}',
      'label': 'selected a card',
    };
    final owner = room.seats[game.exportState().currentPlayerIndex].ownerUid!;
    final result = patch('turnUi', ui, uid: owner);
    expect(result['turn']['stage'], 'guess');
    expect(result['activity']['player'], game.currentPlayer);
    expect(patch('turnUi', ui, uid: 'outsider'), isEmpty);
    expect(patch('turnUi', ui, uid: owner, version: 6), isEmpty);
    final otherOwner = owner == 'host' ? 'guest' : 'host';
    expect(patch('turnUi', ui, uid: otherOwner), isEmpty);
    expect(patch('turnUi', {...ui, 'row': 99}, uid: owner), isEmpty);
    expect(
      patch('turnUi', {...ui, 'orientation': 'invalid'}, uid: owner),
      isEmpty,
    );
  });

  test('shared proposals preserve advice and reject illegal moves', () {
    final position = game.snapshot().validSelectable.first;
    final option = game.getValidOptionsForCard(position).first;
    final proposal = AiMoveProposal(
      action: PolicyAction.guess(
        position: position,
        orientation: option.orientation,
        guess: option.guesses.first,
      ),
      confidence: 0.75,
      source: 'Pure statistics',
      expectedDrinks: 2.5,
      explanation: 'A reason everyone can see.',
    );
    final encoded = encodeSharedProposal(proposal);
    final decoded = decodeSharedProposal(encoded)!;
    expect(decoded.action.label, proposal.action.label);
    expect(decoded.expectedDrinks, 2.5);
    expect(decoded.explanation, proposal.explanation);
    final owner = room.seats[game.exportState().currentPlayerIndex].ownerUid!;
    expect(
      patch('turnUi', {'stage': 'suggestion', 'proposal': encoded}, uid: owner),
      isNotEmpty,
    );
    expect(
      patch('turnUi', {
        'stage': 'suggestion',
        'proposal': {...encoded, 'row': 99},
      }, uid: owner),
      isEmpty,
    );
    final social = RoomSocialSnapshot({
      'turn': {'version': 6, 'uid': owner, 'stage': 'guess'},
    });
    expect(social.turnFor(room), isEmpty);
  });
}
