import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/firebase_options.dart';

void main() {
  test(
    'browser invitations prefill a room on the single hosted browser client',
    () {
      final url = WindowFirebaseOptions.browserInvite('abc234');
      if (WindowFirebaseOptions.browserUrl == null) {
        expect(url, isNull);
      } else {
        final uri = Uri.parse(url!);
        expect(uri.queryParameters['room'], 'ABC234');
        expect(uri.host, Uri.parse(WindowFirebaseOptions.browserUrl!).host);
      }
    },
  );

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
