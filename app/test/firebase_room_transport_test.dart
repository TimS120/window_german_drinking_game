import 'dart:convert';
import 'dart:async';

import 'package:window_game/firebase_events.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:window_game/firebase_options.dart';
import 'package:window_game/firebase_room_repository.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/game_state_codec.dart';
import 'package:window_game/windows_firebase_rest.dart';

void main() {
  test(
    'requests arrive live, are deduplicated across reconnect snapshots',
    () async {
      final events = StreamController<FirebaseEvent>();
      final rooms = WindowsFirebaseRestRoomRepository(
        options: const WindowFirebaseRestOptions(
          apiKey: 'key',
          databaseUrl: 'https://test.invalid',
        ),
        client: MockClient(
          (_) async =>
              http.Response('{"localId":"host","idToken":"token"}', 200),
        ),
        eventOpener: (_) => events.stream,
      );
      await rooms.signInAnonymously();
      final requests = <String>[];
      final listener = rooms
          .observeRequests('ABC234')
          .listen((r) => requests.add(r.id));
      final request = {
        'uid': 'guest',
        'type': 'joinLobby',
        'seatName': 'Guest',
      };
      events.add(
        FirebaseEvent(
          'put',
          jsonEncode({
            'path': '/',
            'data': {'one': request},
          }),
        ),
      );
      events.add(
        FirebaseEvent(
          'put',
          jsonEncode({
            'path': '/',
            'data': {'one': request},
          }),
        ),
      );
      events.add(
        FirebaseEvent('put', jsonEncode({'path': '/two', 'data': request})),
      );
      await Future<void>.delayed(Duration.zero);
      expect(requests, ['one', 'two']);
      await listener.cancel();
      await events.close();
    },
  );

  test('publishes private and public state in one atomic write', () async {
    final calls = <http.Request>[];
    final rooms = WindowsFirebaseRestRoomRepository(
      options: const WindowFirebaseRestOptions(
        apiKey: 'key',
        databaseUrl: 'https://test.invalid',
      ),
      client: MockClient((request) async {
        calls.add(request);
        return http.Response(
          request.url.host == 'identitytoolkit.googleapis.com'
              ? '{"localId":"host","idToken":"token"}'
              : 'null',
          200,
        );
      }),
    );
    await rooms.signInAnonymously();
    await rooms.publishState(
      roomCode: 'abc234',
      hostUid: 'host',
      version: 2,
      seats: [const RoomSeat(index: 0, name: 'Host', ownerUid: 'host')],
      state: WindowGameEngine(['Host'], seed: 1).exportState(),
      started: true,
    );
    expect(calls.length, 2);
    expect(calls.last.method, 'PATCH');
    expect(calls.last.url.path, '/rooms/ABC234.json');
    final body = jsonDecode(calls.last.body);
    expect(body['public']['version'], 2);
    expect(body['public']['state']['deck'], isEmpty);
    expect(body['private']['deck'], isNotEmpty);
  });

  test(
    'public rooms expose deck count while keeping card identities private',
    () async {
      final List<http.Request> calls = <http.Request>[];
      final WindowsFirebaseRestRoomRepository rooms =
          WindowsFirebaseRestRoomRepository(
            options: const WindowFirebaseRestOptions(
              apiKey: 'test-key',
              databaseUrl: 'https://test.invalid',
            ),
            client: MockClient((http.Request request) async {
              calls.add(request);
              return http.Response(
                request.url.host == 'identitytoolkit.googleapis.com'
                    ? '{"localId":"host","idToken":"test-token"}'
                    : 'null',
                200,
              );
            }),
          );
      final GameState state = WindowGameEngine(<String>[
        'Host',
      ], seed: 1).exportState();
      await rooms.signInAnonymously();
      await rooms.createRoom(state: state, localPlayers: <String>['Host']);
      final Map<String, dynamic> public =
          jsonDecode(calls[1].body) as Map<String, dynamic>;
      final Map<String, dynamic> private =
          jsonDecode(calls[2].body) as Map<String, dynamic>;
      expect(public['deckSize'], state.deck.length);
      expect(public['state']['deck'], isEmpty);
      expect(private['deck'], state.deck);
      for (int row = 0; row < state.cardGrid.length; row++) {
        for (int column = 0; column < state.cardGrid[row].length; column++) {
          if (!state.faceUp[row][column]) {
            expect(public['state']['cardGrid'][row][column], -1);
          }
        }
      }
    },
  );

  test(
    'Firebase transport loads rooms and submits shared-device join requests',
    () async {
      final List<http.Request> calls = <http.Request>[];
      final WindowsFirebaseRestRoomRepository rooms =
          WindowsFirebaseRestRoomRepository(
            options: const WindowFirebaseRestOptions(
              apiKey: 'test-key',
              databaseUrl: 'https://test.invalid',
            ),
            client: MockClient((http.Request request) async {
              calls.add(request);
              if (request.url.host == 'identitytoolkit.googleapis.com') {
                return http.Response(
                  jsonEncode(<String, dynamic>{
                    'localId': 'guest',
                    'idToken': 'test-token',
                  }),
                  200,
                );
              }
              if (request.method == 'GET') {
                return http.Response(
                  jsonEncode(<String, dynamic>{
                    'hostUid': 'host',
                    'version': 1,
                    'started': false,
                    'seats': <Map<String, dynamic>>[
                      <String, dynamic>{
                        'index': 0,
                        'name': 'Host',
                        'ownerUid': 'host',
                      },
                    ],
                    'state': GameStateCodec.encode(
                      WindowGameEngine(<String>['Host'], seed: 1).exportState(),
                    ),
                  }),
                  200,
                );
              }
              return http.Response('{"name":"request1"}', 200);
            }),
          );
      await rooms.signInAnonymously();
      final room = await rooms.loadRoom('abc234');
      expect(room!.code, 'ABC234');
      await rooms.requestLobbyJoin(
        roomCode: 'abc234',
        seatName: 'Anna',
        seatNames: <String>['Anna', 'Ben'],
      );
      expect(calls[1].url.path, '/rooms/ABC234/public.json');
      expect(calls.last.url.path, '/rooms/ABC234/requests.json');
      final Map<String, dynamic> payload =
          jsonDecode(calls.last.body) as Map<String, dynamic>;
      expect(payload['uid'], 'guest');
      expect(payload['seatName'], 'Anna');
      expect(payload['seatNames'], <String>['Anna', 'Ben']);
      expect(payload['type'], 'joinLobby');
    },
  );
}
