import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'firebase_events.dart';

// Browser HTTP clients can buffer responses. EventSource delivers SSE events
// immediately, follows Firebase redirects, and uses the browser's connection pool.
Stream<FirebaseEvent> openFirebaseEvents(Uri uri) {
  late StreamController<FirebaseEvent> controller;
  web.EventSource? source;
  controller = StreamController<FirebaseEvent>(
    onListen: () {
      final events = source = web.EventSource(uri.toString());
      for (final type in [
        'put',
        'patch',
        'keep-alive',
        'cancel',
        'auth_revoked',
      ]) {
        events.addEventListener(
          type,
          ((web.Event event) {
            final message = event as web.MessageEvent;
            controller.add(
              FirebaseEvent(type, (message.data as JSString).toDart),
            );
          }).toJS,
        );
      }
      events.onerror = ((web.Event event) {
        // The shared watcher owns reconnects and refreshes expired credentials.
        controller.addError(
          StateError('Firebase live connection interrupted.'),
        );
        events.close();
        unawaited(controller.close());
      }).toJS;
    },
    onCancel: () => source?.close(),
  );
  return controller.stream;
}
