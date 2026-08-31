import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small key/value store for app preferences. Kept separate from the sqflite
/// database, which holds the medicine book itself.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const String _themeModeKey = 'theme_mode';
  static const String _systemPromptSpentKey = 'notif_system_prompt_spent';

  Future<ThemeMode> readThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _decode(prefs.getString(_themeModeKey));
    } catch (e) {
      // A preference is never worth failing a launch over.
      debugPrint('Medstock: could not read theme preference — $e');
      return ThemeMode.system;
    }
  }

  Future<void> writeThemeMode(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, _encode(mode));
    } catch (e) {
      debugPrint('Medstock: could not save theme preference — $e');
    }
  }

  /// True once Android's own permission prompt has been used and refused, so
  /// asking again would silently do nothing and the user must be sent to
  /// system settings instead.
  Future<bool> readSystemPromptSpent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_systemPromptSpentKey) ?? false;
    } catch (e) {
      debugPrint('Medstock: could not read notification prompt state — $e');
      return false;
    }
  }

  Future<void> writeSystemPromptSpent(bool spent) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_systemPromptSpentKey, spent);
    } catch (e) {
      debugPrint('Medstock: could not save notification prompt state — $e');
    }
  }

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  /// Anything unrecognised (or absent) falls back to following the device.
  static ThemeMode _decode(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
