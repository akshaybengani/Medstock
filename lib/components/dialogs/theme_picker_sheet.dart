import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';

/// Lets the user follow the device theme or pin light/dark.
class ThemePickerSheet extends StatelessWidget {
  const ThemePickerSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        builder: (_) => const ThemePickerSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = context.watch<ThemeProvider>();

    const options = <(ThemeMode, String, String, IconData)>[
      (
        ThemeMode.system,
        'Match device',
        "Follows your phone's light or dark setting",
        Icons.brightness_auto_outlined,
      ),
      (ThemeMode.light, 'Light', 'Always light', Icons.light_mode_outlined),
      (ThemeMode.dark, 'Dark', 'Always dark', Icons.dark_mode_outlined),
    ];

    // RadioGroup owns the selection; the individual Radios just declare
    // their value (the per-Radio groupValue/onChanged pair is deprecated).
    // Choosing a mode applies it and closes the sheet — the change is visible
    // behind the sheet anyway, so there is nothing left to confirm.
    void choose(ThemeMode? chosen) {
      if (chosen == null) return;
      provider.setMode(chosen);
      Navigator.of(context).maybePop();
    }

    return SafeArea(
      child: RadioGroup<ThemeMode>(
        groupValue: provider.mode,
        onChanged: choose,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Appearance',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          for (final (mode, title, subtitle, icon) in options)
            ListTile(
              onTap: () => choose(mode),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(icon, color: scheme.onSurfaceVariant),
              title: Text(title),
              subtitle: Text(
                subtitle,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              trailing: Radio<ThemeMode>(value: mode),
            ),
          const SizedBox(height: 12),
        ],
        ),
      ),
    );
  }
}
