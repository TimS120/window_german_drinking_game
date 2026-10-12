import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'firebase_events.dart';

Stream<FirebaseEvent> openFirebaseEvents(Uri uri) {
  final client = http.Client();
  late StreamController<FirebaseEvent> controller;
  StreamSubscription<String>? lines;
  var cancelled = false;
  var event = 'message';
  final data = <String>[];
  Future<void> start() async {
    try {
      final request = http.Request('GET', uri)
        ..headers['accept'] = 'text/event-stream';
      final response = await client.send(request);
      if (cancelled) return;
      if (response.statusCode != 200) {
        throw StateError(
          'Firebase live connection failed (${response.statusCode}).',
        );
      }
      lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line.isEmpty) {
                if (data.isNotEmpty) {
                  controller.add(FirebaseEvent(event, data.join('\n')));
                }
                event = 'message';
                data.clear();
              } else if (line.startsWith('event:')) {
                event = line.substring(6).trim();
              } else if (line.startsWith('data:')) {
                data.add(line.substring(5).trimLeft());
              }
            },
            onError: controller.addError,
            onDone: controller.close,
          );
    } catch (error, stack) {
      if (!cancelled) {
        controller.addError(error, stack);
        await controller.close();
      }
    }
  }

  controller = StreamController<FirebaseEvent>(
    onListen: () => unawaited(start()),
    onCancel: () async {
      cancelled = true;
      client.close();
      await lines?.cancel();
    },
  );
  return controller.stream;
}
