import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'async_games.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class AsyncNotifications {
  static bool get supported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;
  static const _project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _vapid = String.fromEnvironment('FIREBASE_VAPID_KEY');
  static Future<void>? _initializing;
  static Future<void> initialize() => _initializing ??= _initialize()
      .catchError((Object error, StackTrace stack) {
        _initializing = null;
        Error.throwWithStackTrace(error, stack);
      });
  static Future<void> _initialize() async {
    if (!supported || _project.isEmpty) return;
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: kIsWeb
            ? String.fromEnvironment('FIREBASE_WEB_API_KEY')
            : String.fromEnvironment('FIREBASE_API_KEY'),
        appId: kIsWeb
            ? String.fromEnvironment('FIREBASE_WEB_APP_ID')
            : String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
        messagingSenderId: _sender,
        projectId: _project,
      ),
    );
    // Notification payloads are displayed by Android/the browser when the app
    // is closed. No foreground service or background polling is needed.
    if (!kIsWeb) await FirebaseMessaging.instance.setAutoInitEnabled(true);
  }

  static final _preferences = SharedPreferencesAsync();
  static StreamSubscription<String>? _registrations;
  static Future<bool> get enabled async =>
      await _preferences.getBool('window.async.notifications') == true;
  static Future<String?> get registeredId =>
      _preferences.getString('window.async.notificationId');
  static Future<void> rememberEnabled() =>
      _preferences.setBool('window.async.notifications', true);
  static Future<void>? _restoring;
  static Future<void> restoreRegistration() {
    final existing = _restoring;
    if (existing != null) return existing;
    final future = _restoreRegistration();
    _restoring = future;
    return future.whenComplete(() => _restoring = null);
  }

  static Future<void> _uploadRegistration(String id) async {
    final identity = AsyncIdentity();
    await identity.load();
    final client = AsyncGamesClient(identity: identity);
    try {
      await client.registerToken(id);
      await _preferences.setString('window.async.notificationId', id);
    } finally {
      client.close();
    }
  }

  static Future<void> _restoreRegistration() async {
    if (!supported || _project.isEmpty || asyncBackendUrl.isEmpty) return;
    if (!await enabled) return;
    await initialize();
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      throw StateError('Notification permission was not granted.');
    }
    _registrations ??= FirebaseMessaging.instance.onRegistered.listen((id) {
      unawaited(_uploadRegistration(id).catchError((Object _) {}));
    });
    final registration = Completer<String>();
    final listener = FirebaseMessaging.instance.onRegistered.listen((id) {
      if (!registration.isCompleted) registration.complete(id);
    });
    try {
      await FirebaseMessaging.instance
          .register(vapidKey: kIsWeb && _vapid.isNotEmpty ? _vapid : null)
          .timeout(const Duration(seconds: 30));
      final id = await registration.future.timeout(const Duration(seconds: 30));
      await _uploadRegistration(id);
    } finally {
      await listener.cancel();
    }
  }

  static Future<String> enable() async {
    if (!supported) {
      throw UnsupportedError(
        'Use Android or a browser for turn notifications.',
      );
    }
    await initialize();
    if (!await FirebaseMessaging.instance.isSupported()) {
      throw UnsupportedError(
        'This browser does not support turn notifications. Saved games still work.',
      );
    }
    final permission = await FirebaseMessaging.instance.requestPermission();
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      throw StateError('Notification permission was not granted.');
    }
    if (!kIsWeb) await FirebaseMessaging.instance.setAutoInitEnabled(true);
    final registration = Completer<String>();
    final listener = FirebaseMessaging.instance.onRegistered.listen((id) {
      if (!registration.isCompleted) registration.complete(id);
    });
    late final String token;
    try {
      await FirebaseMessaging.instance
          .register(vapidKey: kIsWeb && _vapid.isNotEmpty ? _vapid : null)
          .timeout(const Duration(seconds: 30));
      token = await registration.future.timeout(const Duration(seconds: 30));
    } finally {
      await listener.cancel();
    }
    await _preferences.setString('window.async.notificationId', token);
    return token;
  }

  static Future<String?> initialGame() async {
    if (!supported || _project.isEmpty) return null;
    await initialize();
    return (await FirebaseMessaging.instance.getInitialMessage())
            ?.data['gameCode']
        as String?;
  }

  static Stream<String> get openedGames => FirebaseMessaging.onMessageOpenedApp
      .where((message) => message.data['gameCode'] is String)
      .map((message) => message.data['gameCode'] as String);
}
