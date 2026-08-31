import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../components/atom/button_atom.dart';
import '../../constants.dart';
import '../../models/medicine.dart';
import '../../models/medicine_event.dart';
import '../../providers/app_provider.dart';

/// Read-only history for one medicine: what changed and when.
///
/// Loaded on demand rather than held in the provider — it is only ever shown
/// on this screen and grows without bound.
class MedicineHistoryCard extends StatefulWidget {
  const MedicineHistoryCard({super.key, required this.medicine});

  final Medicine medicine;

  @override
  State<MedicineHistoryCard> createState() => _MedicineHistoryCardState();
}

class _MedicineHistoryCardState extends State<MedicineHistoryCard> {
  /// How many entries to show before the "show all" affordance.
  static const int _collapsedCount = 4;

  bool _expanded = false;

  /// Held in state rather than created in build: a future built during build
  /// re-queries the database on every rebuild, which with a listening provider
  /// becomes an endless load loop.
  Future<List<MedicineEvent>>? _future;
  int _loadedVersion = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-query only when the provider's data actually changed.
    final version = context.watch<AppProvider>().dataVersion;
    if (version == _loadedVersion) return;
    _loadedVersion = version;
    final id = widget.medicine.id;
    if (id != null) {
      _future = context.read<AppProvider>().eventsFor(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final id = widget.medicine.id;
    if (id == null || _future == null) return const SizedBox.shrink();

    return FutureBuilder<List<MedicineEvent>>(
      future: _future,
      builder: (context, snapshot) {
        final events = snapshot.data;
        if (events == null) {
          // A local database read is effectively instant, so a spinner would
          // only flicker. An inert placeholder also lets tests settle.
          return const SizedBox(height: 8);
        }

        if (events.isEmpty) {
          return Text(
            'Nothing recorded yet.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          );
        }

        final shown = _expanded || events.length <= _collapsedCount
            ? events
            : events.take(_collapsedCount).toList();
        final hidden = events.length - shown.length;

        return Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < shown.length; i++)
                _EventRow(
                  event: shown[i],
                  unitLabel: widget.medicine.unitLabel,
                  isFirst: i == 0,
                  isLast: i == shown.length - 1 && hidden == 0,
                ),
              if (hidden > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextButton.icon(
                    onPressed: () => setState(() => _expanded = true),
                    icon: const Icon(Icons.expand_more, size: 18),
                    label: Text(
                      'Show $hidden older '
                      '${hidden == 1 ? 'entry' : 'entries'}',
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One row with a timeline rail down the left.
class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.unitLabel,
    required this.isFirst,
    required this.isLast,
  });

  final MedicineEvent event;
  final String unitLabel;
  final bool isFirst;
  final bool isLast;

  static final DateFormat _stamp = DateFormat('d MMM yyyy · h:mm a');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Stock going up reads positive; a recount downwards is neutral.
    final isGain = (event.qtyDelta ?? 0) > 0;
    final accent = switch (event.type) {
      MedicineEventType.stockAdded ||
      MedicineEventType.orderReceived =>
        isGain ? scheme.primary : scheme.onSurfaceVariant,
      MedicineEventType.created => scheme.primary,
      MedicineEventType.priceChanged => scheme.tertiary,
      _ => scheme.onSurfaceVariant,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // rail
          SizedBox(
            width: 28,
            child: Column(
              children: [
                SizedBox(
                  height: isFirst ? 18 : 0,
                  child: isFirst
                      ? null
                      : VerticalDivider(
                          width: 1,
                          color: scheme.outlineVariant,
                        ),
                ),
                if (!isFirst)
                  Container(
                    width: 1,
                    height: 10,
                    color: scheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(event.type.icon, size: 14, color: accent),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                top: isFirst ? 16 : 8,
                bottom: isLast ? 16 : 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.describe(unitLabel),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _stamp.format(event.at),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          if (event.qtyDelta != null && event.qtyDelta != 0)
            Padding(
              padding: EdgeInsets.only(top: isFirst ? 16 : 8),
              child: PillTag(
                label: '${isGain ? '+' : ''}'
                    '${event.qtyDelta!.toStringAsFixed(0)}',
                dense: true,
                color: accent,
                background: accent.withValues(alpha: 0.12),
              ),
            ),
        ],
      ),
    );
  }
}
