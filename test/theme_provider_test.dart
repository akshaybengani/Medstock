import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medstock/providers/theme_provider.dart';
import 'package:medstock/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to following the device', () async {
    final provider = ThemeProvider();
    expect(provider.mode, ThemeMode.system);

    // Nothing saved yet, so loading must not change the default.
    await provider.load();
    expect(provider.mode, ThemeMode.system);
    expect(provider.label, 'System');
  });

  test('a chosen mode is persisted and read back', () async {
    final provider = ThemeProvider();
    await provider.setMode(ThemeMode.dark);
    expect(provider.mode, ThemeMode.dark);
    expect(provider.label, 'Dark');

    // A fresh provider over the same store picks the choice back up.
    final reopened = ThemeProvider();
    await reopened.load();
    expect(reopened.mode, ThemeMode.dark);
  });

  test('switching back to system is persisted too', () async {
    final provider = ThemeProvider();
    await provider.setMode(ThemeMode.light);
    await provider.setMode(ThemeMode.system);

    final reopened = ThemeProvider();
    await reopened.load();
    expect(reopened.mode, ThemeMode.system);
  });

  test('notifies listeners exactly once per real change', () async {
    final provider = ThemeProvider();
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.setMode(ThemeMode.dark);
    expect(notifications, 1);

    // Re-selecting the same mode is a no-op.
    await provider.setMode(ThemeMode.dark);
    expect(notifications, 1);

    await provider.setMode(ThemeMode.light);
    expect(notifications, 2);
  });

  test('a corrupt stored value falls back to system', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'chartreuse'});

    final provider = ThemeProvider();
    await provider.load();
    expect(provider.mode, ThemeMode.system);
  });

  test('each mode has its own icon', () async {
    final provider = ThemeProvider();
    final icons = <IconData>{};
    for (final mode in ThemeMode.values) {
      await provider.setMode(mode);
      icons.add(provider.icon);
    }
    expect(icons.length, ThemeMode.values.length);
  });

  test('settings service round-trips every mode', () async {
    for (final mode in ThemeMode.values) {
      await SettingsService.instance.writeThemeMode(mode);
      expect(await SettingsService.instance.readThemeMode(), mode);
    }
  });
}
