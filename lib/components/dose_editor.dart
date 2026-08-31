import 'package:flutter/material.dart';

import '../constants.dart';
import '../helpers/date_helpers.dart';
import '../models/dose_assignment.dart';
import '../models/patient.dart';
import '../theme/pallete.dart';
import 'patient_avatar.dart';

/// A compact +/- number control. Touch-friendlier than a keypad for the
/// small integers and halves that dosages are made of.
class StepperField extends StatelessWidget {
  const StepperField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.step = 1,
    this.min = 0,
    this.max = 99,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double step;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _button(
                context,
                Icons.remove,
                value > min ? () => onChanged((value - step).clamp(min, max)) : null,
              ),
              SizedBox(
                width: 40,
                child: Text(
                  Dates.qty(value),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              _button(
                context,
                Icons.add,
                value < max ? () => onChanged((value + step).clamp(min, max)) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _button(BuildContext context, IconData icon, VoidCallback? onTap) {
    return IconButton(
      icon: Icon(icon, size: 18),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
    );
  }
}

/// Attaches one patient to a medicine and captures *their* dosage.
///
/// This widget is the answer to the shared-medicine case: two of these on the
/// same medicine give Mom 1/day and Dad 2/day, and the medicine's total
/// becomes 3/day without either patient's own figure being distorted.
class DoseEditor extends StatelessWidget {
  const DoseEditor({
    super.key,
    required this.patient,
    required this.assignment,
    required this.unitLabel,
    required this.onChanged,
    required this.onToggle,
  });

  final Patient patient;

  /// Null when this patient is not attached to the medicine.
  final DoseAssignment? assignment;

  final String unitLabel;
  final ValueChanged<DoseAssignment> onChanged;
  final ValueChanged<bool> onToggle;

  bool get _enabled => assignment != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = Pallete.accentFor(patient.colorIndex);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 14),
      decoration: BoxDecoration(
        color: _enabled
            ? accent.withValues(alpha: 0.07)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _enabled
              ? accent.withValues(alpha: 0.3)
              : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PatientAvatar(patient: patient, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (_enabled) ...[
                      const SizedBox(height: 2),
                      Text(
                        assignment!.scheduleSummary(unitLabel: unitLabel),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: accent),
                      ),
                    ],
                  ],
                ),
              ),
              Switch(
                value: _enabled,
                onChanged: onToggle,
              ),
            ],
          ),
          if (_enabled) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _DoseControls(
                assignment: assignment!,
                unitLabel: unitLabel,
                onChanged: onChanged,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DoseControls extends StatelessWidget {
  const _DoseControls({
    required this.assignment,
    required this.unitLabel,
    required this.onChanged,
  });

  final DoseAssignment assignment;
  final String unitLabel;
  final ValueChanged<DoseAssignment> onChanged;

  bool get _isDuration =>
      assignment.scheduleType == ScheduleType.perDuration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StepperField(
              label: _isDuration ? 'Units at a time' : 'Each dose',
              value: assignment.qtyPerIntake,
              step: _isDuration ? 1 : 0.5,
              min: _isDuration ? 1 : 0.5,
              max: 20,
              onChanged: (v) => onChanged(assignment.copyWith(qtyPerIntake: v)),
            ),
            const SizedBox(width: 14),
            // "Times a day" is meaningless for something measured by how long
            // it lasts, so it is replaced by the duration itself.
            if (_isDuration)
              StepperField(
                label: 'Lasts (days)',
                value: assignment.intervalDays.toDouble(),
                step: 5,
                min: 1,
                max: 365,
                onChanged: (v) =>
                    onChanged(assignment.copyWith(intervalDays: v.round())),
              )
            else
              StepperField(
                label: 'Times a day',
                value: assignment.intakesPerDay.toDouble(),
                min: 1,
                max: 12,
                onChanged: (v) =>
                    onChanged(assignment.copyWith(intakesPerDay: v.round())),
              ),
          ],
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<ScheduleType>(
          initialValue: assignment.scheduleType,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Repeats',
            isDense: true,
          ),
          items: [
            for (final type in ScheduleType.values)
              DropdownMenuItem(value: type, child: Text(type.label)),
          ],
          onChanged: (type) {
            if (type == null) return;
            // Entering duration mode: one unit at a time, a month by default.
            if (type == ScheduleType.perDuration) {
              onChanged(assignment.copyWith(
                scheduleType: type,
                intakesPerDay: 1,
                qtyPerIntake: assignment.qtyPerIntake < 1
                    ? 1
                    : assignment.qtyPerIntake.roundToDouble(),
                intervalDays: assignment.scheduleType == ScheduleType.interval
                    ? assignment.intervalDays
                    : 30,
              ));
              return;
            }
            onChanged(assignment.copyWith(scheduleType: type));
          },
        ),
        if (assignment.scheduleType == ScheduleType.weekdays) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  label: Text(kWeekdayShort[day - 1]),
                  selected: assignment.weekdays.contains(day),
                  onSelected: (selected) {
                    final next = {...assignment.weekdays};
                    if (selected) {
                      next.add(day);
                    } else {
                      next.remove(day);
                    }
                    onChanged(assignment.copyWith(weekdays: next));
                  },
                ),
            ],
          ),
        ],
        if (_isDuration) ...[
          const SizedBox(height: 10),
          Text(
            'Stock drains a little each day, so a part-used $unitLabel still '
            'shows what is left.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (assignment.scheduleType == ScheduleType.interval) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              StepperField(
                label: 'Every N days',
                value: assignment.intervalDays.toDouble(),
                min: 1,
                max: 90,
                onChanged: (v) =>
                    onChanged(assignment.copyWith(intervalDays: v.round())),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Counted from ${Dates.prettyShort(assignment.startDate)}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
