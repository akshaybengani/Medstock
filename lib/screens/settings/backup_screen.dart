import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../components/atom/button_atom.dart';
import '../../helpers/date_helpers.dart';
import '../../providers/app_provider.dart';
import '../../services/backup_service.dart';

/// Export the whole book to a JSON file, or restore one.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ export

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final file = await BackupService.instance.exportToFile();
      if (!mounted) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          fileNameOverrides: [file.uri.pathSegments.last],
          subject: 'Medstock backup',
          text: 'Medstock backup — keep this file somewhere safe.',
        ),
      );
    } catch (e) {
      _toast('Could not create the backup file');
      debugPrint('Medstock: export failed — $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------ import

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      // file_picker 12 exposes a static single-file picker.
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Choose a Medstock backup',
        type: FileType.any,
      );
      final path = picked?.path;
      if (path == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      final text = await File(path).readAsString();
      final preview = await BackupService.instance.inspect(text);
      if (!mounted) return;

      final provider = context.read<AppProvider>();
      final confirmed = await _confirmRestore(preview);
      if (confirmed != true) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      await provider.restoreBackup(preview);
      if (!mounted) return;
      _toast('Backup restored');
      Navigator.of(context).pop();
    } on BackupFormatException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Could not read that file');
      debugPrint('Medstock: import failed — $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Restoring is destructive, so it always needs an explicit yes and shows
  /// exactly what is about to replace what.
  Future<bool?> _confirmRestore(BackupPreview preview) {
    final provider = context.read<AppProvider>();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace everything?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preview.exportedAt == null
                  ? 'This backup does not say when it was made.'
                  : 'Backup from ${Dates.pretty(preview.exportedAt!)}.',
            ),
            const SizedBox(height: 12),
            _line(ctx, 'Medicines', provider.medicines.length, preview.medicines),
            _line(ctx, 'Patients', provider.patients.length, preview.patients),
            _line(ctx, 'Orders', provider.orders.length, preview.orders),
            _line(ctx, 'Pharmacies', provider.pharmacies.length,
                preview.pharmacies),
            const SizedBox(height: 12),
            Text(
              'Everything currently in the app is deleted first. This cannot '
              'be undone.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.error,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(88, 44),
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  /// "1 medicine" but "3 medicines" — a count is worth getting right when it
  /// is the reassurance that a backup covers everything.
  static String _count(int n, String singular) =>
      '$n ${n == 1 ? singular : '${singular}s'}';

  Widget _line(BuildContext ctx, String label, int now, int incoming) {
    final theme = Theme.of(ctx);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            '$now → $incoming',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = context.watch<AppProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your book lives only on this phone',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Medstock is fully offline and is deliberately excluded from '
                  'cloud backup, so an export is the only copy that survives '
                  'losing this device. Keep one somewhere safe.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    PillTag(
                      label: _count(provider.medicines.length, 'medicine'),
                      icon: Icons.medication_outlined,
                      dense: true,
                    ),
                    PillTag(
                      label: _count(provider.patients.length, 'patient'),
                      icon: Icons.people_outline,
                      dense: true,
                    ),
                    PillTag(
                      label: _count(provider.orders.length, 'order'),
                      icon: Icons.receipt_long_outlined,
                      dense: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Export'),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.ios_share),
            label: const Text('Export everything as JSON'),
          ),
          const SizedBox(height: 8),
          Text(
            'Writes one readable JSON file with every medicine, patient, '
            'pharmacy, order and history entry, then opens the share sheet so '
            'you can put it in Drive, email it to yourself, or save it to '
            'Files.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          const SectionLabel('Import'),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Restore from a backup file'),
          ),
          const SizedBox(height: 8),
          Text(
            'Shows you what the file contains and asks before replacing '
            'anything. The restore happens in a single transaction, so a bad '
            'file leaves your current book untouched.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (_busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
