import 'package:flutter/material.dart';

import '../../components/atom/button_atom.dart';
import '../../components/medicine_thumb.dart';
import '../../components/patient_avatar.dart';
import '../../components/stock_badge.dart';
import '../../helpers/date_helpers.dart';
import '../../helpers/stock_math.dart';
import '../../models/medicine.dart';
import '../../models/patient.dart';

/// One medicine on the dashboard.
///
/// The same card serves the "All" tab and each patient tab; [patientId]
/// switches the dose figure between the household total and that one
/// patient's share.
class MedicineCard extends StatelessWidget {
  const MedicineCard({
    super.key,
    required this.medicine,
    required this.patientsById,
    this.patientId,
    this.onTap,
  });

  final Medicine medicine;
  final Map<int, Patient> patientsById;

  /// Null on the "All" tab.
  final int? patientId;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final status = StockMath.status(medicine);
    final statusColor = StockPalette.colorFor(status.level, scheme);

    // The dose figure shown depends on which tab we are in.
    final assignments = patientId == null
        ? medicine.assignments
        : StockMath.forPatient(medicine, patientId!);
    final perDay = StockMath.perDay(assignments);
    final doseHeadline = StockMath.headline(assignments, medicine.unitLabel);

    return TappableCard(
      onTap: onTap,
      borderColor: status.needsAttention
          ? statusColor.withValues(alpha: 0.35)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MedicineThumb(
                type: medicine.type,
                imagePath: medicine.imagePath,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medicine.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
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
                        if (perDay > 0)
                          PillTag(
                            label: doseHeadline,
                            icon: Icons.schedule,
                            dense: true,
                            color: scheme.onSecondaryContainer,
                            background: scheme.secondaryContainer,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Stock line: how many units are physically left, and for how long.
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${Dates.qtyWithUnit(status.remaining, medicine.unitLabel)} in stock',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (status.runOutDate != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Runs out ${Dates.prettyShort(status.runOutDate!)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              StockBadge(status: status, dense: true),
            ],
          ),

          const SizedBox(height: 10),
          CoverageBar(
            status: status,
            // A month of cover reads as a full bar.
            horizonDays: (medicine.lowStockDays * 4).clamp(14, 120),
          ),

          // On the "All" tab, show who takes it and at what dose — this is
          // where the shared-medicine case becomes legible at a glance.
          if (patientId == null && medicine.assignments.isNotEmpty) ...[
            const SizedBox(height: 14),
            _TakersRow(
              medicine: medicine,
              patientsById: patientsById,
            ),
          ],

          if (patientId != null && assignments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              assignments
                  .map((a) =>
                      a.scheduleSummary(unitLabel: medicine.unitLabel))
                  .join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Avatar + per-patient dose, e.g. "M 1/day   D 2/day".
class _TakersRow extends StatelessWidget {
  const _TakersRow({required this.medicine, required this.patientsById});

  final Medicine medicine;
  final Map<int, Patient> patientsById;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final entries = medicine.assignments
        .map((a) => (patient: patientsById[a.patientId], assignment: a))
        .where((e) => e.patient != null)
        .toList()
      ..sort((a, b) => a.patient!.sortOrder.compareTo(b.patient!.sortOrder));

    if (entries.isEmpty) return const SizedBox.shrink();

    // Each entry is a Row inside a Wrap, so it has no width of its own to
    // push back against. Cap it at the card width and let long names and
    // dose figures ellipsize instead of overflowing.
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          for (final e in entries)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PatientAvatar(patient: e.patient!, size: 26),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${e.patient!.name} · '
                      '${e.assignment.doseHeadline(medicine.unitLabel)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
