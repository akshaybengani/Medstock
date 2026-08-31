import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../components/atom/button_atom.dart';
import '../../components/medicine_thumb.dart';
import '../../components/patient_avatar.dart';
import '../../components/stock_badge.dart';
import '../../helpers/date_helpers.dart';
import '../../helpers/stock_math.dart';
import '../../models/medicine.dart';
import '../../providers/app_provider.dart';
import 'medicine_form_screen.dart';
import 'medicine_history_card.dart';
import 'stock_sheet.dart';

/// Everything known about one medicine: derived stock, per-patient dosage and
/// the optional detail fields.
class MedicineDetailScreen extends StatelessWidget {
  const MedicineDetailScreen({super.key, required this.medicineId});

  final int medicineId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final medicine = provider.medicineById(medicineId);

    // The medicine can disappear while this screen is open (deleted from
    // here, or its patient removed) — fall back rather than crash.
    if (medicine == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This medicine is no longer here.')),
      );
    }

    final status = StockMath.status(medicine);

    return Scaffold(
      appBar: AppBar(
        title: Text(medicine.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MedicineFormScreen(medicine: medicine),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context, provider, medicine),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _HeaderCard(medicine: medicine, status: status),
          const SizedBox(height: 16),
          _StockCard(medicine: medicine, status: status),
          const SizedBox(height: 20),
          if (medicine.assignments.isNotEmpty) ...[
            const SectionLabel('Who takes it'),
            _DosageCard(medicine: medicine, provider: provider),
            const SizedBox(height: 20),
          ],
          _DetailsCard(medicine: medicine),
          const SizedBox(height: 20),
          const SectionLabel('History'),
          MedicineHistoryCard(medicine: medicine),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppProvider provider,
    Medicine medicine,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${medicine.displayName}?'),
        content: const Text(
          'The medicine, its stock and every patient dosage attached to it '
          'are removed. Past orders keep their record of it.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await provider.deleteMedicine(medicine.id!);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.medicine, required this.status});

  final Medicine medicine;
  final StockStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: medicine.imagePath == null
              ? null
              : () => _openPhoto(context, medicine.imagePath!),
          child: MedicineThumb(
            type: medicine.type,
            imagePath: medicine.imagePath,
            size: 84,
            radius: 22,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                medicine.displayName,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  PillTag(
                    label: medicine.type.label,
                    icon: medicine.type.icon,
                    dense: true,
                    color: scheme.onSurfaceVariant,
                    background: scheme.surfaceContainerHighest,
                  ),
                  if (status.perDay > 0)
                    PillTag(
                      label: StockMath.headline(
                        medicine.assignments,
                        medicine.unitLabel,
                      ),
                      icon: Icons.schedule,
                      dense: true,
                    ),
                  if (medicine.packSize > 1)
                    PillTag(
                      label: '${medicine.packSize} per pack',
                      icon: Icons.widgets_outlined,
                      dense: true,
                      color: scheme.onSurfaceVariant,
                      background: scheme.surfaceContainerHighest,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openPhoto(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(child: Image.file(File(path))),
      ),
    );
  }
}

/// The derived stock figure plus the two ways to correct it.
class _StockCard extends StatelessWidget {
  const _StockCard({required this.medicine, required this.status});

  final Medicine medicine;
  final StockStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = StockPalette.colorFor(status.level, scheme);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Dates.qty(status.remaining),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${Dates.unit(medicine.unitLabel, status.remaining)} '
                      'left today',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              StockBadge(status: status),
            ],
          ),
          const SizedBox(height: 16),
          CoverageBar(
            status: status,
            horizonDays: (medicine.lowStockDays * 4).clamp(14, 120),
          ),
          const SizedBox(height: 14),
          _factLine(
            context,
            Icons.event_available_outlined,
            status.runOutDate == null
                ? status.level == StockLevel.untracked
                    ? 'No dosage attached, so stock does not count down.'
                    : 'Stock lasts beyond the next few years.'
                : 'Runs out on ${Dates.withWeekday(status.runOutDate!)}.',
          ),
          const SizedBox(height: 6),
          _factLine(
            context,
            Icons.history,
            'Counted from ${Dates.pretty(medicine.stockAsOf)} '
            '(${Dates.qtyWithUnit(medicine.stockQty, medicine.unitLabel)}).',
          ),
          if (medicine.reminderEnabled && status.runOutDate != null) ...[
            const SizedBox(height: 6),
            _factLine(
              context,
              Icons.notifications_active_outlined,
              'Reminder ${medicine.lowStockDays} days before — '
              '${Dates.pretty(status.runOutDate!.subtract(Duration(days: medicine.lowStockDays)))}.',
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => StockSheet.show(
                    context,
                    medicine: medicine,
                    mode: StockSheetMode.add,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add stock'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => StockSheet.show(
                    context,
                    medicine: medicine,
                    mode: StockSheetMode.count,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Recount'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _factLine(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Per-patient dosage rows — the household breakdown.
class _DosageCard extends StatelessWidget {
  const _DosageCard({required this.medicine, required this.provider});

  final Medicine medicine;
  final AppProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final rows = medicine.assignments
        .map((a) => (patient: provider.patientById(a.patientId), assignment: a))
        .where((e) => e.patient != null)
        .toList()
      ..sort((a, b) => a.patient!.sortOrder.compareTo(b.patient!.sortOrder));

    // A Material (not a decorated Container) so the ListTiles' ink splashes
    // have somewhere to paint.
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                indent: 66,
                endIndent: 16,
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ListTile(
              leading: PatientAvatar(patient: rows[i].patient!, size: 40),
              title: Text(
                rows[i].patient!.name,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [
                  rows[i]
                      .assignment
                      .scheduleSummary(unitLabel: medicine.unitLabel),
                  if (rows[i].assignment.timing != null)
                    rows[i].assignment.timing!,
                ].join(' · '),
              ),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 116),
                child: Text(
                  rows[i].assignment.doseHeadline(medicine.unitLabel),
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ],
          Divider(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Household total',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Flexible(
                  child: Text(
                    StockMath.headline(
                      medicine.assignments,
                      medicine.unitLabel,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// The optional fields, rendered only when they hold something.
class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.medicine});
  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    final entries = <(IconData, String, String)>[
      if (_has(medicine.description))
        (Icons.notes_outlined, 'What it is for', medicine.description!),
      if (_has(medicine.prescribedBy))
        (
          Icons.medical_information_outlined,
          'Prescribed by',
          medicine.prescribedBy!
        ),
      if (_has(medicine.manufacturer))
        (Icons.business_outlined, 'Manufacturer', medicine.manufacturer!),
      if (_has(medicine.storage))
        (Icons.thermostat_outlined, 'Storage', medicine.storage!),
      if (medicine.expiryDate != null)
        (
          Icons.event_busy_outlined,
          'Expires',
          Dates.pretty(medicine.expiryDate!)
        ),
      if (medicine.packPrice != null)
        (
          Icons.currency_rupee,
          medicine.packSize > 1
              ? 'Price per pack of ${medicine.packSize}'
              : 'Price per ${_singular(medicine.unitLabel)}',
          medicine.unitPrice == null
              ? Dates.money(medicine.packPrice!)
              : '${Dates.money(medicine.packPrice!)}  ·  '
                  '${Dates.money(medicine.unitPrice!)} per '
                  '${_singular(medicine.unitLabel)}',
        ),
      if (_has(medicine.notes))
        (Icons.sticky_note_2_outlined, 'Notes', medicine.notes!),
    ];

    if (entries.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Additional information'),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      entries[i].$1,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entries[i].$2,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entries[i].$3,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  bool _has(String? v) => v != null && v.trim().isNotEmpty;

  String _singular(String plural) =>
      plural.endsWith('s') ? plural.substring(0, plural.length - 1) : plural;
}
