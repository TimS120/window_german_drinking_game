import 'dart:async';
import 'dart:convert';

import 'firebase_events_native.dart'
    if (dart.library.js_interop) 'firebase_events_web.dart'
    as platform;

class FirebaseEvent {
  const FirebaseEvent(this.type, this.data);
  final String type;
  final String data;
}

typedef FirebaseEventOpener = Stream<FirebaseEvent> Function(Uri uri);

/// Firebase SSE sends a complete snapshot first, then relative put/patch events.
/// Reconnects always start with a fresh complete snapshot.
Stream<Object?> watchFirebase(
  Uri Function() uri, {
  FirebaseEventOpener? open,
  Future<void> Function()? refreshAuth,
}) {
  late StreamController<Object?> controller;
  StreamSubscription<FirebaseEvent>? subscription;
  Timer? retry;
  Timer? watchdog;
  Object? snapshot;
  var stopped = false;
  var reconnecting = false;
  var failures = 0;
  late void Function() connect;

  Future<void> reconnect({bool authExpired = false}) async {
    if (stopped || reconnecting) return;
    reconnecting = true;
    watchdog?.cancel();
    await subscription?.cancel();
    subscription = null;
    if (stopped) return;
    if (authExpired && refreshAuth != null) {
      try {
        await refreshAuth();
      } catch (error, stack) {
        if (!stopped) controller.addError(error, stack);
      }
    }
    if (stopped) return;
    final delay = Duration(milliseconds: 250 * (1 << failures.clamp(0, 5)));
    failures++;
    retry = Timer(delay, () {
      reconnecting = false;
      connect();
    });
  }

  connect = () {
    if (stopped) return;
    void armWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(const Duration(seconds: 65), reconnect);
    }

    armWatchdog();
    subscription = (open ?? platform.openFirebaseEvents)(uri()).listen(
      (event) {
        armWatchdog();
        if (event.type == 'auth_revoked') {
          unawaited(reconnect(authExpired: true));
        } else if (event.type == 'cancel') {
          controller.addError(StateError('Firebase room access was denied.'));
          unawaited(reconnect());
        } else if (event.type == 'put' || event.type == 'patch') {
          try {
            snapshot = applyFirebaseEvent(snapshot, event);
            failures = 0;
            controller.add(snapshot);
          } catch (error, stack) {
            controller.addError(error, stack);
            unawaited(reconnect());
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!stopped) controller.addError(error, stack);
        unawaited(reconnect());
      },
      onDone: () => unawaited(reconnect()),
    );
  };
  controller = StreamController<Object?>(
    onListen: connect,
    onCancel: () async {
      stopped = true;
      retry?.cancel();
      watchdog?.cancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}

/// Copies each changed branch so previously emitted snapshots stay unchanged.
Object? applyFirebaseEvent(Object? snapshot, FirebaseEvent event) {
  final payload = jsonDecode(event.data) as Map<String, dynamic>;
  final path = (payload['path'] as String)
      .split('/')
      .where((p) => p.isNotEmpty)
      .toList();
  if (event.type == 'put') return _replace(snapshot, path, payload['data']);
  for (final entry in (payload['data'] as Map<String, dynamic>).entries) {
    snapshot = _replace(snapshot, [
      ...path,
      ...entry.key.split('/'),
    ], entry.value);
  }
  return snapshot;
}

Object? _replace(Object? value, List<String> path, Object? replacement) {
  if (path.isEmpty) return replacement;
  final key = path.first;
  final tail = path.sublist(1);
  if (value is List) {
    final result = List<Object?>.from(value);
    final index = int.parse(key);
    while (result.length <= index) {
      result.add(null);
    }
    result[index] = _replace(result[index], tail, replacement);
    return result;
  }
  final result = value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};
  final updated = _replace(result[key], tail, replacement);
  if (updated == null) {
    result.remove(key);
  } else {
    result[key] = updated;
  }
  return result.isEmpty ? null : result;
}
