import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../providers/app_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/patients/patients_screen.dart';
import '../screens/pharmacy/pharmacies_screen.dart';
import '../screens/settings/backup_screen.dart';
import 'dialogs/theme_picker_sheet.dart';

/// Side drawer holding everything that is not day-to-day: people, pharmacies,
/// appearance and backup, with the build number at the foot.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final app = context.watch<AppProvider>();
    final themeProvider = context.watch<ThemeProvider>();

    /// Closes the drawer first so the pushed route animates from the page,
    /// not from behind the panel.
    void go(Widget Function() build) {
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => build()));
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            _Header(medicines: app.medicines.length, patients: app.patients.length),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ListTile(
                    leading: const Icon(Icons.people_outline),
                    title: const Text('Patients'),
                    subtitle: Text(
                      app.patients.isEmpty
                          ? 'Nobody added yet'
                          : app.patients.map((p) => p.name).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => go(() => const PatientsScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: const Text('Pharmacy contacts'),
                    subtitle: Text(
                      app.pharmacies.isEmpty
                          ? 'No pharmacy saved'
                          : app.pharmacies.map((p) => p.name).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => go(() => const PharmaciesScreen()),
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: Icon(themeProvider.icon),
                    title: const Text('Appearance'),
                    subtitle: Text(themeProvider.label),
                    onTap: () {
                      Navigator.of(context).pop();
                      ThemePickerSheet.show(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('Backup & restore'),
                    subtitle: const Text('Export or import a JSON file'),
                    onTap: () => go(() => const BackupScreen()),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${K.appName} · offline',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const _VersionLabel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.medicines, required this.patients});
  final int medicines;
  final int patients;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      color: scheme.primaryContainer.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.medication_liquid_outlined,
                color: scheme.onPrimary, size: 26),
          ),
          const SizedBox(height: 14),
          Text(
            K.appName,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            '$medicines ${medicines == 1 ? 'medicine' : 'medicines'} · '
            '$patients ${patients == 1 ? 'patient' : 'patients'}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Reads the real version and build number from the platform package info, so
/// it can never drift from what was actually installed.
class _VersionLabel extends StatefulWidget {
  const _VersionLabel();

  @override
  State<_VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends State<_VersionLabel> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = 'v${info.version} (${info.buildNumber})');
    } catch (e) {
      debugPrint('Medstock: could not read package info — $e');
      if (mounted) setState(() => _version = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      _version ?? '',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
