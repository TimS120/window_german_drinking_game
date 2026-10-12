import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/firebase_events.dart';
import 'package:window_game/firebase_events_native.dart';

FirebaseEvent change(String type, String path, Object? data) =>
    FirebaseEvent(type, jsonEncode({'path': path, 'data': data}));

void main() {
  test(
    'patches nested paths, arrays and deletions without mutating old snapshots',
    () {
      final first = applyFirebaseEvent(
        null,
        change('put', '/', {
          'version': 1,
          'seats': [
            {'name': 'Host'},
          ],
          'requests': {
            'a': {'type': 'action'},
          },
        }),
      );
      final next = applyFirebaseEvent(
        first,
        change('patch', '/', {
          'version': 2,
          'seats/0/name': 'Updated',
          'requests/a': null,
        }),
      ) as Map;
      expect(next['version'], 2);
      expect((next['seats'] as List).first['name'], 'Updated');
      expect(next['requests'], isNull);
      expect((first as Map)['version'], 1);
      expect((first['seats'] as List).first['name'], 'Host');
      expect(applyFirebaseEvent(next, change('put', '/', null)), isNull);
    },
  );

  test(
    'live updates arrive immediately and reconnect replaces stale cache',
    () async {
      final sources = <StreamController<FirebaseEvent>>[];
      final seen = <Object?>[];
      final listener = watchFirebase(
        () => Uri.parse('https://example.invalid'),
        open: (_) {
          final source = StreamController<FirebaseEvent>();
          sources.add(source);
          return source.stream;
        },
      ).listen(seen.add);
      sources.first.add(change('put', '/', {'version': 1}));
      sources.first.add(change('patch', '/', {'version': 2}));
      await Future<void>.delayed(Duration.zero);
      expect(seen, [
        {'version': 1},
        {'version': 2},
      ]);
      await sources.first.close();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(sources.length, 2);
      sources.last.add(change('put', '/', {'fresh': true}));
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, {'fresh': true});
      await listener.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(sources.length, 2);
      await sources.last.close();
    },
  );

  test('expired credentials refresh before reconnect', () async {
    final sources = <StreamController<FirebaseEvent>>[];
    var refreshes = 0;
    var token = 'old';
    final uris = <Uri>[];
    final listener = watchFirebase(
      () => Uri.parse('https://example.invalid/?auth=$token'),
      refreshAuth: () async {
        refreshes++;
        token = 'new';
      },
      open: (uri) {
        uris.add(uri);
        final c = StreamController<FirebaseEvent>();
        sources.add(c);
        return c.stream;
      },
    ).listen((_) {});
    sources.first.add(const FirebaseEvent('auth_revoked', '"expired"'));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(refreshes, 1);
    expect(uris.last.queryParameters['auth'], 'new');
    await listener.cancel();
    for (final source in sources) {
      await source.close();
    }
  });

  test('native SSE delivers chunked events before response ends and closes on cancel', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestReady = Completer<HttpRequest>();
    final serverListener = server.listen((request) {
      requestReady.complete(request);
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(
        'event: put\r\ndata: {"path":"/","data":1}\r\n\r\n',
      );
      unawaited(request.response.flush());
    });
    final event = await openFirebaseEvents(
      Uri.parse('http://127.0.0.1:${server.port}/room'),
    ).first.timeout(const Duration(seconds: 5));
    expect(event.type, 'put');
    expect(jsonDecode(event.data)['data'], 1);
    final request = await requestReady.future;
    expect(request.headers.value('accept'), 'text/event-stream');
    await serverListener.cancel();
    await server.close(force: true);
  });
}
