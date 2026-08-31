import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Holds the chosen theme mode. Defaults to [ThemeMode.system] so Medstock
/// follows the phone's light/dark setting until the user overrides it.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider({SettingsService? settings})
      : _settings = settings ?? SettingsService.instance;

  final SettingsService _settings;

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  /// Loads the saved preference. Safe to call before the first frame.
  Future<void> load() async {
    final saved = await _settings.readThemeMode();
    if (saved == _mode) return;
    _mode = saved;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await _settings.writeThemeMode(mode);
  }

  /// Label for the current choice, used by the picker and its tooltip.
  String get label => switch (_mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };

  /// The icon that represents the current choice in the app bar.
  IconData get icon => switch (_mode) {
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
        ThemeMode.system => Icons.brightness_auto_outlined,
      };
}
