import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/localization.dart';
import 'package:window_game/main.dart';
import 'package:window_game/rl_policy.dart';

class MemoryLanguages implements LanguagePreferenceStore {
  MemoryLanguages([this.saved]);
  String? saved;
  final writes = <String>[];
  Completer<String?>? readGate;
  @override
  Future<String?> read() => readGate?.future ?? Future.value(saved);
  @override
  Future<void> write(String language) async {
    writes.add(language);
    saved = language;
  }
}

class _Policy extends WindowRlPolicy {
  @override
  Future<void> preload() async {}
}

class _UnavailablePolicy extends _Policy {
  @override
  Future<AiMoveProposal?> propose(WindowGameEngine game) async {
    throw const RlPolicyException('Test runtime unavailable');
  }
}

Future<void> chooseLanguage(
  WidgetTester tester,
  String tooltip,
  String name,
) async {
  await tester.ensureVisible(find.byTooltip(tooltip));
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(PopupMenuItem<String>, name));
  await tester.pumpAndSettle();
}

void main() {
  test('English and German contain the same complete resource set', () {
    Map<String, dynamic> read(String language) =>
        jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
            as Map<String, dynamic>;
    final en = read('en');
    final de = read('de');
    final keys = en.keys.where((k) => !k.startsWith('@')).toSet();
    expect(de.keys.where((k) => !k.startsWith('@')).toSet(), keys);
    for (final key in keys) {
      expect(de[key], isNotEmpty, reason: key);
    }
  });

  test('language choice persists across controllers and ignores unsupported preferences', () async {
    final store = MemoryLanguages();
    final controller = LanguageController(store: store);
    await controller.select('de');
    final restarted = LanguageController(store: store);
    await restarted.load();
    expect(restarted.locale, const Locale('de'));
    store.saved = 'fr';
    final unsupported = LanguageController(store: store);
    await unsupported.load();
    expect(
      unsupported.locale,
      isNull,
    ); // MaterialApp uses supported device locale.
    controller.dispose();
    restarted.dispose();
    unsupported.dispose();
  });

  test(
    'an in-flight preference read cannot overwrite a newer choice',
    () async {
      final store = MemoryLanguages()..readGate = Completer<String?>();
      final controller = LanguageController(store: store);
      final load = controller.load();
      await controller.select('de');
      store.readGate!.complete('en');
      await load;
      expect(controller.locale, const Locale('de'));
      await Future.wait([controller.select('en'), controller.select('de')]);
      expect(store.writes, ['de', 'en', 'de']);
      expect(store.saved, 'de');
      controller.dispose();
    },
  );

  testWidgets('system language follows device changes and can be restored', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryLanguages();
    final controller = LanguageController(store: store);
    addTearDown(controller.dispose);
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.binding.platformDispatcher.localesTestValue = [const Locale('de')];
    await tester.pumpWidget(
      WindowGameApp(
        firebaseEnabled: false,
        rlPolicy: _Policy(),
        languageController: controller,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sprache wählen'), findsWidgets);
    await chooseLanguage(tester, 'Sprache wählen', 'English');
    expect(controller.locale, const Locale('en'));
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    await tester.pumpAndSettle();
    tester.binding.platformDispatcher.localesTestValue = [const Locale('de')];
    await tester.pumpAndSettle();
    expect(find.byTooltip('Choose language'), findsWidgets);
    await chooseLanguage(tester, 'Choose language', 'Use system language');
    expect(controller.locale, isNull);
    expect(find.byTooltip('Sprache wählen'), findsWidgets);
    final restarted = LanguageController(store: store);
    await restarted.load();
    expect(restarted.locale, isNull);
    restarted.dispose();
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    await tester.pumpAndSettle();
    expect(find.byTooltip('Choose language'), findsWidgets);
  });

  test('German plural rules, action descriptions and decimal formatting', () {
    final de = lookupAppLocalizations(const Locale('de'));
    expect(de.wrongPenalty('Max', 1, 1), contains('einen Schluck'));
    expect(de.wrongPenalty('Max', 1, 1), contains('Eine Karte'));
    expect(de.wrongPenalty('Max', 3, 4), contains('3 Schlucke'));
    expect(de.wrongPenalty('Max', 3, 4), contains('4 Karten'));
    expect(localizedNumber(de, 0.75, 2), '0,75');
    expect(
      localizedDomainText(de, 'Low risk, small penalty (current board only)'),
      'Geringes Risiko, wenige Strafschlucke (nur aktuelles Spielfeld)',
    );
    expect(
      localizedError(
        de,
        StateError(
          'Player names must be unique in the lobby. Choose other names.',
        ),
      ),
      contains('eindeutig'),
    );
    expect(
      localizedDomainText(de, 'Custom player content'),
      'Custom player content',
    );
  });

  testWidgets(
    'join selector translates validation and preserves entered names and room code',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = LanguageController(
        store: MemoryLanguages(),
        initialLocale: const Locale('en'),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        WindowGameApp(
          firebaseEnabled: true,
          rlPolicy: _Policy(),
          browserGuest: true,
          languageController: controller,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Room code'),
        'ABC',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Players on this device'),
        'Max, Anna',
      );
      await tester.ensureVisible(find.text('Join online room'));
      await tester.tap(find.text('Join online room'));
      await tester.pumpAndSettle();
      expect(find.textContaining('six-character room code'), findsOneWidget);
      await chooseLanguage(tester, 'Choose language', 'Deutsch');
      expect(find.text('Fenster beitreten'), findsOneWidget);
      expect(find.textContaining('sechsstelligen Raumcode'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Spieler auf diesem Gerät'),
            )
            .controller!
            .text,
        'Max, Anna',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Raumcode'))
            .controller!
            .text,
        'ABC',
      );
      expect(find.text('Online-Raum beitreten'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'device language is respected and game can switch languages without restarting',
    (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('de', 'DE')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = LanguageController(store: MemoryLanguages());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        WindowGameApp(
          firebaseEnabled: false,
          rlPolicy: _Policy(),
          browserGuest: false,
          languageController: controller,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lokales Spiel starten'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Spieler'),
        'Max, Heiko',
      );
      await tester.tap(find.text('Lokales Spiel starten'));
      await tester.pumpAndSettle();
      expect(find.text('Aktueller Spieler'), findsOneWidget);
      expect(find.textContaining('Max beginnt.'), findsOneWidget);
      final card = tester.element(find.byKey(const ValueKey('card:0:0')));
      await chooseLanguage(tester, 'Sprache wählen', 'English');
      expect(find.text('Current player'), findsOneWidget);
      expect(find.textContaining('Max starts.'), findsOneWidget);
      expect(
        tester.element(find.byKey(const ValueKey('card:0:0'))),
        same(card),
      );
      expect(find.text('Max'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'unavailable RL adviser displays an error instead of a suggestion',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = LanguageController(store: MemoryLanguages('en'));
      await controller.load();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        WindowGameApp(
          firebaseEnabled: false,
          rlPolicy: _UnavailablePolicy(),
          browserGuest: false,
          languageController: controller,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Players'), 'Ada');
      await tester.tap(find.text('Start local game'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.text('Propose best move'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RL model').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Prediction failed: RL adviser unavailable:'),
        findsOneWidget,
      );
      expect(find.textContaining('Suggested move:'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
