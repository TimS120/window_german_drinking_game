import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Orientation;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:window_game/async_games.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/game_state_codec.dart';
import 'package:window_game/localization.dart';
import 'package:window_game/main.dart';
import 'package:window_game/rl_policy.dart';

class _Store implements AsyncIdentityStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String secret) async {
    value = secret;
  }
}

class _Policy extends WindowRlPolicy {
  @override
  Future<void> preload() async {}
}

class _Language implements LanguagePreferenceStore {
  @override
  Future<String?> read() async => 'en';
  @override
  Future<void> write(String value) async {}
}

Map<String, dynamic> savedRoom({
  int version = 0,
  bool started = false,
  int current = 0,
}) {
  final game = WindowGameEngine(['Anna', 'Ben'], seed: 4);
  final state = GameStateCodec.encode(game.publicObservation());
  state['currentPlayerIndex'] = current;
  return {
    'room': {
      'code': 'ABCDEFGHJK',
      'hostUid': 'host',
      'version': version,
      'revision': version,
      'started': started,
      'seats': [
        {'index': 0, 'name': 'Anna', 'ownerUid': 'host'},
        {'index': 1, 'name': 'Ben', 'ownerUid': 'guest'},
      ],
      'devices': {'host': 'Kitchen', 'guest': 'Sofa'},
      'state': state,
      'deckSize': 14,
    },
    'social': {},
  };
}

void main() {
  test('identity persists across restarts and recovery accepts formatted uppercase code', () async {
    final store = _Store(), identity = AsyncIdentity(store: _Store());
    await identity.load();
    expect(identity.recoveryCode, matches(RegExp(r'^[a-f0-9]{64}$')));
    final first = AsyncIdentity(store: store);
    await first.load();
    final second = AsyncIdentity(store: store);
    await second.load();
    expect(second.recoveryCode, first.recoveryCode);
    final code = List.filled(64, 'b').join();
    await second.recover(
      '${code.substring(0, 32).toUpperCase()}-${code.substring(32)}',
    );
    final restored = AsyncIdentity(store: store);
    await restored.load();
    expect(restored.recoveryCode, code);
    await expectLater(restored.recover('invalid'), throwsFormatException);
    expect(restored.recoveryCode, code);
  });
  test('a dropped creation response retries with the same identity and operation ID', () async {
    final identity = AsyncIdentity(store: _Store());
    await identity.load();
    final requests = <http.Request>[];
    final client = AsyncGamesClient(
      identity: identity,
      endpoint: 'https://example.invalid',
      client: MockClient((request) async {
        requests.add(request);
        if (requests.length == 1) throw http.ClientException('Lost connection');
        return http.Response(jsonEncode(savedRoom()), 200);
      }),
    );
    await client.create(['Anna']);
    expect(requests.length, 2);
    expect(requests[0].body, requests[1].body);
    expect(
      requests[0].headers['Authorization'],
      'Bearer ${identity.recoveryCode}',
    );
    client.close();
  });
  testWidgets(
    'server-hosted room uses remote controls, confirms reset, preserves public deck count and returns to its hub',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final identity = AsyncIdentity(store: _Store());
      await identity.load();
      final operations = <String>[];
      var value = savedRoom();
      final client = AsyncGamesClient(
        identity: identity,
        endpoint: 'https://example.invalid',
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode(value), 200);
          }
          final body = jsonDecode(request.body) as Map;
          operations.add(body['type'] as String);
          if (body['type'] == 'start') {
            value = savedRoom(version: 1, started: true);
          }
          if (body['type'] == 'restart') {
            value = savedRoom(version: 2, started: true);
          }
          return http.Response(jsonEncode(value), 200);
        }),
      );
      client.uid = 'host';
      final repository = AsyncRoomRepository(client, 'ABCDEFGHJK', value);
      final language = LanguageController(
        store: _Language(),
        initialLocale: const Locale('en'),
      );
      await tester.pumpWidget(
        LanguageScope(
          controller: language,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => GameShell(
                        firebaseEnabled: true,
                        rlPolicy: _Policy(),
                        repository: repository,
                        asyncRoomCode: 'ABCDEFGHJK',
                      ),
                    ),
                  ),
                  child: const Text('Saved games'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Saved games'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ABCDEFGHJK'), findsWidgets);
      final start = find.text('Start game and lock lobby');
      expect(start, findsOneWidget);
      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(operations, ['start']);
      expect(find.byKey(const ValueKey('restart-online-game')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('restart-online-game')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(operations, ['start']);
      await tester.tap(find.byKey(const ValueKey('restart-online-game')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Yes'));
      await tester.pumpAndSettle();
      expect(operations, ['start', 'restart']);
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byTooltip('Your saved games'));
      await tester.pumpAndSettle();
      expect(find.text('Saved games'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repository.close();
      client.close();
      language.dispose();
    },
  );
  for (final activeUid in ['host', 'guest']) {
    testWidgets(
      'wrong guess requires a visible redeal before continuing as $activeUid on a phone, including after reopening',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final serverGame = WindowGameEngine(['Anna', 'Ben'], seed: 2);
        var version = 0;
        Map<String, dynamic> payload() {
          final value = savedRoom(version: version, started: true);
          final room = value['room'] as Map<String, dynamic>;
          room['state'] = GameStateCodec.encode(serverGame.publicObservation());
          (room['seats'] as List)[0]['ownerUid'] = activeUid;
          (room['seats'] as List)[1]['ownerUid'] = activeUid == 'host'
              ? 'guest'
              : 'host';
          return value;
        }

        final identity = AsyncIdentity(store: _Store());
        await identity.load();
        final actions = <String>[];
        final client = AsyncGamesClient(
          identity: identity,
          endpoint: 'https://example.invalid',
          client: MockClient((request) async {
            if (request.method == 'POST') {
              final body = jsonDecode(request.body) as Map;
              expect(body['type'], 'action');
              final action = body['action'] as Map;
              actions.add(action['type'] as String);
              if (action['type'] == 'guess') {
                const position = Position(2, 4);
                final result = serverGame.applyGuess(
                  position,
                  serverGame.getValidOptionsForCard(position).single,
                  GuessType.values.byName(action['guess'] as String),
                );
                expect(result.requiresRemovalConfirmation, isTrue);
              } else if (action['type'] == 'confirmRemovals') {
                serverGame.confirmRemovals();
              }
              version++;
            }
            return http.Response(jsonEncode(payload()), 200);
          }),
        );
        client.uid = activeUid;
        final repository = AsyncRoomRepository(client, 'ABCDEFGHJK', payload());
        final language = LanguageController(
          store: _Language(),
          initialLocale: const Locale('en'),
        );
        Widget screen() => LanguageScope(
          controller: language,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GameShell(
              firebaseEnabled: true,
              rlPolicy: _Policy(),
              repository: repository,
              asyncRoomCode: 'ABCDEFGHJK',
            ),
          ),
        );
        await tester.pumpWidget(screen());
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 3));
        final target = find.byKey(const ValueKey('card:2:4'));
        await tester.tap(target);
        await tester.pumpAndSettle();
        final wrongLabel =
            serverGame.cardAt(const Position(2, 4))! ~/ 4 >
                serverGame.cardAt(handlePosition)! ~/ 4
            ? 'Lower'
            : 'Higher';
        await tester.tap(find.widgetWithText(FilledButton, wrongLabel));
        await tester.pumpAndSettle();
        expect(actions, ['guess']);
        expect(find.text('Wrong guess'), findsOneWidget);
        final confirm = find.byKey(const ValueKey('confirm-pending-action'));
        expect(confirm, findsOneWidget);
        expect(tester.getRect(confirm).top, greaterThan(0));
        expect(tester.getRect(confirm).bottom, lessThan(844));
        expect(tester.widget<InkWell>(target).onTap, isNull);
        expect(
          tester.widget<InkWell>(find.byKey(const ValueKey('card:2:3'))).onTap,
          isNull,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(confirm, findsOneWidget);
        expect(actions, ['guess']);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(screen());
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 3));
        expect(confirm, findsOneWidget);
        expect(tester.widget<InkWell>(target).onTap, isNull);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(actions, ['guess', 'confirmRemovals']);
        expect(find.text('Wrong guess'), findsNothing);
        expect(serverGame.pendingRemovals, isEmpty);
        expect(serverGame.currentPlayer, 'Anna');
        expect(tester.widget<InkWell>(target).onTap, isNotNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        repository.close();
        client.close();
        language.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
  test('slow old snapshots cannot replace a newer server version', () async {
    final identity = AsyncIdentity(store: _Store());
    await identity.load();
    final delayed = Completer<http.Response>();
    final client = AsyncGamesClient(
      identity: identity,
      endpoint: 'https://example.invalid',
      client: MockClient(
        (request) async => request.method == 'GET'
            ? delayed.future
            : http.Response(
                jsonEncode(savedRoom(version: 2, started: true)),
                200,
              ),
      ),
    );
    client.uid = 'host';
    final repository = AsyncRoomRepository(client, 'ABCDEFGHJK', savedRoom());
    final refresh = repository.refresh();
    await repository.controlRoom('start', 0);
    delayed.complete(http.Response(jsonEncode(savedRoom(version: 1)), 200));
    await refresh;
    expect((await repository.loadRoom('ABCDEFGHJK'))!.version, 2);
    repository.close();
    client.close();
  });
}
