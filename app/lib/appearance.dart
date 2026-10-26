import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization.dart';

abstract interface class ThemePreferenceStore {
  Future<String?> read();
  Future<void> write(String mode);
}

class DeviceThemePreferences implements ThemePreferenceStore {
  static const key = 'window.theme';
  SharedPreferencesAsync get _preferences => SharedPreferencesAsync();
  @override
  Future<String?> read() => _preferences.getString(key);
  @override
  Future<void> write(String mode) => _preferences.setString(key, mode);
}

/// System follows live platform brightness until the user explicitly overrides
/// it. This device preference is independent of room state and language.
class ThemeController extends ChangeNotifier {
  ThemeController({ThemePreferenceStore? store})
    : _store = store ?? DeviceThemePreferences();
  final ThemePreferenceStore _store;
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;
  int _revision = 0;
  Future<void> _saveQueue = Future<void>.value();

  Future<void> load() async {
    final revision = _revision;
    try {
      final saved = await _store.read();
      if (_revision != revision) return;
      _mode =
          ThemeMode.values.where((mode) => mode.name == saved).firstOrNull ??
          ThemeMode.system;
      notifyListeners();
    } catch (error) {
      debugPrint('Could not read theme preference: $error');
    }
  }

  Future<void> select(ThemeMode mode) {
    _revision++;
    _mode = mode;
    notifyListeners();
    final save = _saveQueue.then((_) => _store.write(mode.name));
    _saveQueue = save.catchError((Object error) {
      debugPrint('Could not save theme preference: $error');
    });
    return _saveQueue;
  }

  @override
  void dispose() {
    _revision++;
    super.dispose();
  }
}

class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);
  static ThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.notifier;
}

class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = ThemeScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    final l = tr(context);
    final labels = {
      ThemeMode.system: l.themeSystem,
      ThemeMode.light: l.themeLight,
      ThemeMode.dark: l.themeDark,
    };
    return PopupMenuButton<ThemeMode>(
      key: const ValueKey('theme-picker'),
      tooltip: l.appearance,
      icon: Icon(switch (controller.mode) {
        ThemeMode.system => Icons.brightness_auto,
        ThemeMode.light => Icons.light_mode,
        ThemeMode.dark => Icons.dark_mode,
      }),
      onSelected: (mode) => unawaited(controller.select(mode)),
      itemBuilder: (context) => [
        for (final mode in ThemeMode.values)
          PopupMenuItem(
            value: mode,
            child: Row(
              children: [
                Expanded(child: Text(labels[mode]!)),
                if (controller.mode == mode) const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}
