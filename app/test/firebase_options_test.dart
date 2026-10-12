import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/firebase_options.dart';

void main() {
  test('native Firebase connection accepts either configured API key', () {
    const nativeKey = String.fromEnvironment('FIREBASE_API_KEY');
    const webKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
    const databaseUrl = String.fromEnvironment('FIREBASE_DATABASE_URL');
    final options = WindowFirebaseOptions.windowsRestOptions;
    if ((nativeKey.isEmpty && webKey.isEmpty) || databaseUrl.isEmpty) {
      expect(options, isNull);
    } else {
      expect(options, isNotNull);
      expect(options!.apiKey, nativeKey.isNotEmpty ? nativeKey : webKey);
      expect(options.databaseUrl, databaseUrl);
    }
  });
}
