import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/appearance.dart';
import 'package:window_game/localization.dart';
import 'package:window_game/main.dart';
import 'package:window_game/rl_policy.dart';

import 'localization_test.dart' show MemoryLanguages, chooseLanguage;

class _Themes implements ThemePreferenceStore {
  String? saved;
  Completer<String?>? readGate;
  @override
  Future<String?> read() => readGate?.future ?? Future.value(saved);
  @override
  Future<void> write(String mode) async {
    saved = mode;
  }
}

class _Policy extends WindowRlPolicy {
  @override
  Future<void> preload() async {}
}

void main() {
  test(
    'theme persists across launches including restoring the system default',
    () async {
      final store = _Themes();
      final controller = ThemeController(store: store);
      expect(controller.mode, ThemeMode.system);
      await controller.select(ThemeMode.dark);
      final restored = ThemeController(store: store);
      await restored.load();
      expect(restored.mode, ThemeMode.dark);
      await restored.select(ThemeMode.system);
      await controller.load();
      expect(controller.mode, ThemeMode.system);
      store.saved = 'unsupported';
      await controller.load();
      expect(controller.mode, ThemeMode.system);
      restored.dispose();
      controller.dispose();
    },
  );
  test(
    'a delayed preference read cannot override a newer theme choice',
    () async {
      final store = _Themes()..readGate = Completer<String?>();
      final controller = ThemeController(store: store);
      final load = controller.load();
      await controller.select(ThemeMode.light);
      store.readGate!.complete('dark');
      await load;
      expect(controller.mode, ThemeMode.light);
      expect(store.saved, 'light');
      controller.dispose();
    },
  );
  testWidgets(
    'system brightness is live; overrides and language changes preserve the game',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      final store = _Themes();
      final appearance = ThemeController(store: store);
      final language = LanguageController(
        store: MemoryLanguages(),
        initialLocale: const Locale('en'),
      );
      addTearDown(appearance.dispose);
      addTearDown(language.dispose);
      await tester.pumpWidget(
        WindowGameApp(
          firebaseEnabled: false,
          browserGuest: false,
          rlPolicy: _Policy(),
          themeController: appearance,
          languageController: language,
        ),
      );
      await tester.pumpAndSettle();
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(Scaffold))).brightness;
      expect(brightness(), Brightness.light);
      expect(
        find.textContaining('Friends can join a lobby hosted'),
        findsOneWidget,
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light mode'));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
      expect(store.saved, 'light');
      await tester.enterText(
        find.widgetWithText(TextField, 'Players'),
        'Ada, Ben',
      );
      await tester.tap(find.text('Start local game'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      final card = tester.element(find.byKey(const ValueKey('card:0:0')));
      await chooseLanguage(tester, 'Choose language', 'Deutsch');
      expect(brightness(), Brightness.light);
      expect(find.text('Ada'), findsWidgets);
      await tester.tap(find.byTooltip('Darstellung'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dunkler Modus'));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      expect(
        tester.element(find.byKey(const ValueKey('card:0:0'))),
        same(card),
      );
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor,
        const Color(0xff0f381c),
      );
      await appearance.select(ThemeMode.system);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
