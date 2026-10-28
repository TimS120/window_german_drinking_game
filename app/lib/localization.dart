import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_engine.dart' hide Orientation;
import 'game_engine.dart' as engine;
import 'l10n/generated/app_localizations.dart';
import 'l10n/generated/app_localizations_en.dart';
import 'rl_policy.dart';

export 'l10n/generated/app_localizations.dart';

typedef LocalizedMessage = String Function(AppLocalizations strings);

final _english = AppLocalizationsEn();
AppLocalizations tr(BuildContext context) =>
    Localizations.of<AppLocalizations>(context, AppLocalizations) ?? _english;

abstract interface class LanguagePreferenceStore {
  Future<String?> read();
  Future<void> write(String language);
}

class DeviceLanguagePreferences implements LanguagePreferenceStore {
  SharedPreferencesAsync get _preferences => SharedPreferencesAsync();
  static const key = 'window.language';
  @override
  Future<String?> read() => _preferences.getString(key);
  @override
  Future<void> write(String language) => _preferences.setString(key, language);
}

/// A device preference only: never published with room or game state.
class LanguageController extends ChangeNotifier {
  LanguageController({LanguagePreferenceStore? store, Locale? initialLocale})
    : _store = store ?? DeviceLanguagePreferences(),
      _locale = initialLocale;
  final LanguagePreferenceStore _store;
  Locale? _locale;
  Locale? get locale => _locale;
  int _revision = 0;
  Future<void> _saveQueue = Future<void>.value();

  @override
  void dispose() {
    _revision++;
    super.dispose();
  }

  Future<void> load() async {
    final revision = _revision;
    try {
      final saved = await _store.read();
      if (revision == _revision && (saved == 'en' || saved == 'de')) {
        _locale = Locale(saved!);
        notifyListeners();
      }
    } catch (error) {
      // Storage failure does not prevent playing or selecting a language.
      debugPrint('Could not read language preference: $error');
    }
  }

  Future<void> select(String language) {
    if (language != 'system' && language != 'en' && language != 'de') {
      throw ArgumentError.value(language, 'language');
    }
    _revision++;
    _locale = language == 'system' ? null : Locale(language);
    notifyListeners();
    final save = _saveQueue.then((_) => _store.write(language));
    _saveQueue = save.catchError((Object error) {
      debugPrint('Could not save language preference: $error');
    });
    return _saveQueue;
  }
}

class LanguageScope extends InheritedNotifier<LanguageController> {
  const LanguageScope({
    super.key,
    required LanguageController controller,
    required super.child,
  }) : super(notifier: controller);
  static LanguageController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageScope>()?.notifier;
}

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, this.showName = false});
  final bool showName;
  @override
  Widget build(BuildContext context) {
    final controller = LanguageScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    final language = tr(context).localeName;
    return PopupMenuButton<String>(
      key: const ValueKey('language-picker'),
      tooltip: tr(context).chooseLanguage,
      onSelected: (language) => unawaited(controller.select(language)),
      itemBuilder: (context) => [
        for (final code in ['system', 'en', 'de'])
          PopupMenuItem(
            value: code,
            child: Row(
              children: [
                if (code == 'system')
                  const Icon(Icons.language, size: 24)
                else
                  _LanguageFlag(language: code),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    code == 'system'
                        ? tr(context).languageSystem
                        : code == 'de'
                        ? 'Deutsch'
                        : 'English',
                  ),
                ),
                if ((controller.locale?.languageCode ?? 'system') == code)
                  const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LanguageFlag(language: language),
            if (showName) ...[
              const SizedBox(width: 8),
              Text(language == 'de' ? 'Deutsch' : 'English'),
            ],
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

// Draw the flags so they also work on systems without flag-emoji glyphs.
class _LanguageFlag extends StatelessWidget {
  const _LanguageFlag({required this.language});
  final String language;
  @override
  Widget build(BuildContext context) => Semantics(
    label: language == 'de' ? 'Deutsch' : 'English',
    child: SizedBox(
      width: 28,
      height: 18,
      child: CustomPaint(painter: _FlagPainter(language)),
    ),
  );
}

class _FlagPainter extends CustomPainter {
  const _FlagPainter(this.language);
  final String language;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint();
    canvas.save();
    canvas.clipRect(rect);
    if (language == 'de') {
      for (var i = 0; i < 3; i++) {
        paint.color = [
          Colors.black,
          const Color(0xffdd0000),
          const Color(0xffffce00),
        ][i];
        canvas.drawRect(
          Rect.fromLTWH(0, i * size.height / 3, size.width, size.height / 3),
          paint,
        );
      }
    } else {
      canvas.drawRect(rect, paint..color = const Color(0xff012169));
      paint
        ..color = Colors.white
        ..strokeWidth = 5;
      canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
      canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), paint);
      paint
        ..color = const Color(0xffc8102e)
        ..strokeWidth = 2;
      canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
      canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), paint);
      canvas.drawRect(
        Rect.fromCenter(center: rect.center, width: size.width, height: 7),
        paint..color = Colors.white,
      );
      canvas.drawRect(
        Rect.fromCenter(center: rect.center, width: 7, height: size.height),
        paint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: rect.center, width: size.width, height: 4),
        paint..color = const Color(0xffc8102e),
      );
      canvas.drawRect(
        Rect.fromCenter(center: rect.center, width: 4, height: size.height),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlagPainter oldDelegate) =>
      language != oldDelegate.language;
}

String guessLabel(AppLocalizations l, GuessType guess) => switch (guess) {
  GuessType.higher => l.higher,
  GuessType.same => l.same,
  GuessType.lower => l.lower,
  GuessType.inBetween => l.inBetween,
  GuessType.outside => l.outside,
};

String actionLabel(AppLocalizations l, PolicyAction action) => action.isPass
    ? l.passAction
    : l.actionLabel(
        action.position!.row + 1,
        action.position!.column + 1,
        action.orientation == engine.Orientation.horizontal
            ? l.horizontal
            : l.vertical,
        guessLabel(l, action.guess!).toLowerCase(),
      );

String localizedNumber(AppLocalizations l, num value, int decimals) =>
    NumberFormat.decimalPatternDigits(
      locale: l.localeName,
      decimalDigits: decimals,
    ).format(value);

String proposalDetails(AppLocalizations l, AiMoveProposal proposal) {
  final statistics = proposal.source.contains('statistics');
  final summary = proposal.action.isPass && statistics
      ? l.noImmediateDrinks
      : '${statistics ? l.estimatedSuccess : l.modelConfidence} ${localizedNumber(l, proposal.confidence * 100, 0)}%';
  return [
    localizedDomainText(l, proposal.source),
    summary,
    if (proposal.valueEstimate != null)
      l.valueEstimate(localizedNumber(l, proposal.valueEstimate!, 2)),
    if (proposal.expectedDrinks != null)
      l.remainingDrinks(localizedNumber(l, proposal.expectedDrinks!, 1)),
  ].join(' · ');
}

class LocalizedFailure implements Exception {
  LocalizedFailure(this.message);
  final LocalizedMessage message;
}

String localizedError(AppLocalizations l, Object error) =>
    error is LocalizedFailure
    ? error.message(l)
    : error is RlPolicyException
    ? l.inferenceFailed(error.details)
    : localizedDomainText(l, '${error is StateError ? error.message : error}');

String localizedPolicyStatus(AppLocalizations l, WindowRlPolicy policy) =>
    switch (policy.availability) {
      PolicyAvailability.ready => l.modelLoaded,
      PolicyAvailability.testReady => l.testModelLoaded,
      PolicyAvailability.deferred => l.modelWillLoad,
      PolicyAvailability.loading => l.modelLoading,
      PolicyAvailability.unavailable => l.modelUnavailable,
      PolicyAvailability.inferenceFailed => l.inferenceFailed(
        policy.inferenceError ?? '',
      ),
    };

// Existing hosts send these model descriptions in the shared proposal. Translate
// only known domain descriptions, never arbitrary chat text or player names.
String localizedDomainText(AppLocalizations l, String text) {
  final firebaseFailure = RegExp(
    r'^Firebase request failed \((\d+)\): ([\s\S]*)$',
  ).firstMatch(text);
  if (firebaseFailure != null) {
    return l.firebaseRequestFailed(
      int.parse(firebaseFailure.group(1)!),
      firebaseFailure.group(2)!,
    );
  }
  if (text.endsWith(' (current board only)')) {
    return l.currentBoardOnly(
      localizedDomainText(
        l,
        text.substring(0, text.length - ' (current board only)'.length),
      ),
    );
  }
  return switch (text) {
    'Enter the six-character room code shared by your host.' => l.validRoomCode,
    'Room not found. Check the room code.' => l.roomNotFound,
    'The host did not respond. Ask them to keep the lobby open, then try again.' =>
      l.hostTimeout,
    'This room is no longer available.' => l.roomUnavailable,
    'Pure statistics' => l.pureStatistics,
    'ONNX policy' => l.modelSource,
    'ONNX test model (untrained)' => l.testModelSource,
    'Pass to avoid more risk' => l.passExplanation,
    'Certain guess, no immediate drinks' => l.certainExplanation,
    'Low risk, small penalty' => l.smallPenaltyExplanation,
    'Lower expected future drinks' => l.futureDrinksExplanation,
    'Strong odds, lower future risk' => l.strongOddsExplanation,
    'Finish the pending action first.' => l.pendingAction,
    'Invalid card selection.' => l.invalidSelection,
    'Invalid guess.' => l.invalidGuess,
    'No same guess is pending.' => l.noSamePending,
    'Enter at least one player name.' => l.enterName,
    'Every player on this device needs a unique name.' => l.uniqueDeviceNames,
    'This game has already started. Ask the host for a new lobby.' =>
      l.gameAlreadyStarted,
    'This device has already joined the lobby.' => l.deviceAlreadyJoined,
    'Player names must be unique in the lobby. Choose other names.' =>
      l.uniqueLobbyNames,
    'Please rejoin the room.' => l.rejoinRoom,
    'Firebase sign-in expired. Please rejoin.' => l.signInExpired,
    'Could not reserve a room code. Please try again.' => l.reserveRoomFailed,
    _ => text,
  };
}
