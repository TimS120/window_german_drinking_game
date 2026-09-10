/// Firebase's public client identifiers. They are supplied at build time so
/// the repository contains no project-specific configuration file.
///
/// Example: --dart-define=FIREBASE_API_KEY=... (see README).
class WindowFirebaseOptions {
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
    final String apiKey = _webApiKey.isNotEmpty ? _webApiKey : _apiKey;
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
