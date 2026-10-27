import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/localization.dart';
import 'package:window_game/main.dart';
import 'package:window_game/rl_policy.dart';

class _Languages implements LanguagePreferenceStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String language) async {}
}

class _Policy extends WindowRlPolicy {
  @override
  Future<void> preload() async {}
}

void main() {
  for (final browser in [false, true]) {
    testWidgets(
      'rules open in selected language and switch while open (browser: $browser)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final language = LanguageController(
          store: _Languages(),
          initialLocale: const Locale('en'),
        );
        addTearDown(language.dispose);
        await tester.pumpWidget(
          WindowGameApp(
            firebaseEnabled: false,
            rlPolicy: _Policy(),
            browserGuest: browser,
            languageController: language,
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('game-rules')));
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('game-rules'))).dy,
          closeTo(
            tester.getTopLeft(find.byKey(const ValueKey('language-picker'))).dy,
            12,
          ),
        );
        await tester.tap(find.byKey(const ValueKey('game-rules')));
        await tester.pumpAndSettle();
        expect(find.text('Goal and cards'), findsOneWidget);
        await language.select('de');
        await tester.pumpAndSettle();
        expect(find.text('Ziel und Karten'), findsOneWidget);
        expect(find.text('Spielregeln'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byTooltip('Spielregeln'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('rules remain accessible during a local game', (tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final language = LanguageController(
      store: _Languages(),
      initialLocale: const Locale('en'),
    );
    addTearDown(language.dispose);
    await tester.pumpWidget(
      WindowGameApp(
        firebaseEnabled: false,
        rlPolicy: _Policy(),
        browserGuest: false,
        languageController: language,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start local game'));
    await tester.tap(find.text('Start local game'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('game-rules')));
    await tester.pumpAndSettle();
    expect(find.text('Goal and cards'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
