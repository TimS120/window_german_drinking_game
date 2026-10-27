import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:window_game/async_games.dart';
import 'package:window_game/async_games_screen.dart';
import 'package:window_game/async_lobby_management.dart';
import 'package:window_game/firebase_room_repository.dart';
import 'package:window_game/localization.dart';
import 'package:window_game/rl_policy.dart';

import 'async_games_test.dart' show savedRoom;

class Store implements AsyncIdentityStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String secret) async {
    value = secret;
  }
}

Widget localized(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);
void main() {
  testWidgets(
    'admin authentication, dates, cancellation, confirmation and locking',
    (tester) async {
      final store = Store();
      final identity = AsyncIdentity(store: store);
      await identity.load();
      final requests = <http.Request>[];
      var deleted = false;
      final key = 'b' * 64;
      final client = AsyncGamesClient(
        identity: identity,
        endpoint: 'https://example.invalid',
        client: MockClient((r) async {
          requests.add(r);
          expect(r.url.toString(), isNot(contains(key)));
          expect(r.body, isNot(contains(key)));
          if (r.headers['Authorization'] != 'Bearer $key') {
            return http.Response('{"error":"Forbidden"}', 403);
          }
          if (r.method == 'POST') {
            deleted = true;
            return http.Response('{}', 200);
          }
          return http.Response(
            jsonEncode({
              'lobbies': deleted
                  ? []
                  : [
                      {
                        'code': 'ABCDEFGHJK',
                        'players': ['Anna', 'Ben'],
                        'status': 'playing',
                        'version': 3,
                        'revision': 8,
                        'createdDate': null,
                        'lastActiveDate': '2026-10-26',
                      },
                    ],
              'nextOffset': null,
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(localized(AsyncLobbyManagement(client: client)));
      expect(requests, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text('Open management'));
      await tester.pumpAndSettle();
      expect(find.text('Anna, Ben'), findsNothing);
      expect(find.textContaining('The admin key is invalid'), findsOneWidget);
      await tester.enterText(find.byType(TextField), key);
      await tester.tap(find.text('Open management'));
      await tester.pumpAndSettle();
      expect(find.text('Anna, Ben'), findsOneWidget);
      expect(find.text('Last activity (UTC): Oct 26, 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete lobby'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deleted, isFalse);
      await tester.tap(find.byTooltip('Lock management'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('Anna, Ben'), findsNothing);
      await tester.enterText(find.byType(TextField), key);
      await tester.tap(find.text('Open management'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete lobby'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete lobby'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
      expect(jsonDecode(requests.singleWhere((r) => r.method == 'POST').body), {
        'type': 'delete',
        'version': 3,
        'revision': 8,
      });
      expect(find.text('Anna, Ben'), findsNothing);
      expect(store.value, identity.recoveryCode);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );
  for (final uid in ['host', 'guest']) {
    testWidgets(
      'saved list skips deleted references and permits only host deletion: $uid',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final identity = AsyncIdentity(store: Store());
        await identity.load();
        var deleted = false;
        final client = AsyncGamesClient(
          identity: identity,
          endpoint: 'https://example.invalid',
          client: MockClient((r) async {
            if (r.url.path == '/me') {
              return http.Response(
                jsonEncode({
                  'uid': uid,
                  'games': ['OLDROOM123', 'ABCDEFGHJK'],
                }),
                200,
              );
            }
            if (r.url.path.endsWith('OLDROOM123') || deleted) {
              return http.Response('{"error":"Gone"}', 410);
            }
            if (r.method == 'POST') {
              deleted = true;
              return http.Response('{}', 200);
            }
            return http.Response(jsonEncode(savedRoom()), 200);
          }),
        );
        await tester.pumpWidget(
          localized(
            AsyncGamesScreen(rlPolicy: WindowRlPolicy(), client: client),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(Card),
            matching: find.text('Anna, Ben'),
          ),
          findsOneWidget,
        );
        expect(
          find.byTooltip('Delete lobby'),
          uid == 'host' ? findsOneWidget : findsNothing,
        );
        if (uid == 'host') {
          await tester.tap(find.byTooltip('Delete lobby'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(deleted, isFalse);
          await tester.tap(find.byTooltip('Delete lobby'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Delete lobby'));
          await tester.pumpAndSettle();
          expect(deleted, isTrue);
          expect(
            find.descendant(
              of: find.byType(Card),
              matching: find.text('Anna, Ben'),
            ),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        client.close();
      },
    );
  }
  test(
    'deleted repository ignores delayed snapshot and emits deletion once',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final identity = AsyncIdentity(store: Store());
      await identity.load();
      final delayed = Completer<http.Response>();
      var reads = 0;
      final client = AsyncGamesClient(
        identity: identity,
        endpoint: 'https://example.invalid',
        client: MockClient((r) async {
          if (reads++ == 0) return delayed.future;
          return http.Response('{"error":"Deleted"}', 410);
        }),
      );
      final repo = AsyncRoomRepository(client, 'ABCDEFGHJK', savedRoom());
      final errors = <Object>[];
      final sub = repo
          .observeRoom('ABCDEFGHJK')
          .listen((_) {}, onError: errors.add);
      final old = repo.refresh();
      await expectLater(
        repo.controlRoom('restart', 0),
        throwsA(isA<AsyncApiException>()),
      );
      delayed.complete(http.Response(jsonEncode(savedRoom(version: 5)), 200));
      await old;
      await Future<void>.delayed(Duration.zero);
      expect(await repo.loadRoom('ABCDEFGHJK'), isNull);
      expect(errors, hasLength(1));
      expect(errors.single, isA<RoomDeletedException>());
      await expectLater(
        repo.controlRoom('restart', 0),
        throwsA(isA<RoomDeletedException>()),
      );
      await sub.cancel();
      repo.close();
      client.close();
    },
  );
}
