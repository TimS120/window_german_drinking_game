import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase's public client identifiers. They are supplied at build time so
/// the repository contains no project-specific configuration file.
///
/// Example: --dart-define=FIREBASE_API_KEY=... (see README).
class WindowFirebaseOptions {
  static const String _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String _databaseUrl = String.fromEnvironment('FIREBASE_DATABASE_URL');
  static const String _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');

  static FirebaseOptions? get currentPlatform {
    if (_apiKey.isEmpty ||
        _appId.isEmpty ||
        _projectId.isEmpty ||
        _senderId.isEmpty ||
        _databaseUrl.isEmpty) {
      return null;
    }
    return FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      projectId: _projectId,
      messagingSenderId: _senderId,
      databaseURL: _databaseUrl,
      authDomain: kIsWeb && _authDomain.isNotEmpty ? _authDomain : null,
    );
  }
}
