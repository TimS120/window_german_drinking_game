import 'package:flutter/foundation.dart';

/// Firebase's public client identifiers. They are supplied at build time so
/// the repository contains no project-specific configuration file.
///
/// Example: --dart-define=FIREBASE_API_KEY=... (see README).
class WindowFirebaseOptions {
  static const String _projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const String _browserUrl = String.fromEnvironment(
    'WINDOW_BROWSER_URL',
  );

  /// Firebase Hosting's default address; custom hosting sites can override it.
  static String? get browserUrl {
    if (_browserUrl.isNotEmpty) return _browserUrl;
    return _projectId.isEmpty ? null : 'https://$_projectId.web.app';
  }

  static const String _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _webApiKey = String.fromEnvironment(
    'FIREBASE_WEB_API_KEY',
  );
  static const String _databaseUrl = String.fromEnvironment(
    'FIREBASE_DATABASE_URL',
  );

  /// The Windows build uses Firebase's HTTPS APIs instead of the native
  /// FlutterFire desktop plugins. Those plugins currently dispatch some
  /// callbacks from the wrong thread on Windows.
  static WindowFirebaseRestOptions? get windowsRestOptions {
    final String apiKey = kIsWeb && _webApiKey.isNotEmpty
        ? _webApiKey
        : (_apiKey.isNotEmpty ? _apiKey : _webApiKey);
    if (apiKey.isEmpty || _databaseUrl.isEmpty) return null;
    return WindowFirebaseRestOptions(apiKey: apiKey, databaseUrl: _databaseUrl);
  }
}

class WindowFirebaseRestOptions {
  const WindowFirebaseRestOptions({
    required this.apiKey,
    required this.databaseUrl,
  });

  final String apiKey;
  final String databaseUrl;
}
