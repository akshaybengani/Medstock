import '../constants.dart';
import '../helpers/date_helpers.dart';

/// Links a medicine to one patient *with that patient's own dosage*.
///
/// This is the row that makes the "Mom takes Dytor once a day, Dad takes it
/// twice a day" case work: the medicine has two assignments, the dashboard's
/// "All" tab sums them to 3/day, and each patient tab reads only its own.
class DoseAssignment {
  final int? id;
  final int? medicineId;
  final int patientId;

  /// Units taken at one sitting (0.5 for half a tablet, etc).
  final double qtyPerIntake;

  /// Sittings per active day — 2 for "twice a day".
  final int intakesPerDay;

  final ScheduleType scheduleType;

  /// For [ScheduleType.weekdays] — ISO weekday numbers (Mon = 1 … Sun = 7).
  final Set<int> weekdays;

  /// Days per cycle. For [ScheduleType.interval] it is the gap between
  /// doses; for [ScheduleType.perDuration] it is how long one unit lasts.
  final int intervalDays;

  /// Anchor for interval schedules, and the day the course begins.
  final DateTime startDate;

  /// Optional free text, e.g. "after breakfast".
  final String? timing;

  const DoseAssignment({
    this.id,
    this.medicineId,
    required this.patientId,
    this.qtyPerIntake = 1,
    this.intakesPerDay = 1,
    this.scheduleType = ScheduleType.daily,
    this.weekdays = const {1, 2, 3, 4, 5, 6, 7},
    this.intervalDays = 2,
    required this.startDate,
    this.timing,
  });

  DoseAssignment copyWith({
    int? id,
    int? medicineId,
    int? patientId,
    double? qtyPerIntake,
    int? intakesPerDay,
    ScheduleType? scheduleType,
    Set<int>? weekdays,
    int? intervalDays,
    DateTime? startDate,
    String? timing,
    bool clearTiming = false,
  }) =>
      DoseAssignment(
        id: id ?? this.id,
        medicineId: medicineId ?? this.medicineId,
        patientId: patientId ?? this.patientId,
        qtyPerIntake: qtyPerIntake ?? this.qtyPerIntake,
        intakesPerDay: intakesPerDay ?? this.intakesPerDay,
        scheduleType: scheduleType ?? this.scheduleType,
        weekdays: weekdays ?? this.weekdays,
        intervalDays: intervalDays ?? this.intervalDays,
        startDate: startDate ?? this.startDate,
        timing: clearTiming ? null : (timing ?? this.timing),
      );

  /// Units consumed on a day when the schedule is active.
  double get qtyPerActiveDay => qtyPerIntake * intakesPerDay;

  /// Whether a dose falls on [day].
  bool isActiveOn(DateTime day) {
    final d = Dates.dayOf(day);
    if (d.isBefore(Dates.dayOf(startDate))) return false;

    switch (scheduleType) {
      case ScheduleType.daily:
        return true;
      case ScheduleType.weekdays:
        return weekdays.contains(d.weekday);
      case ScheduleType.interval:
        final step = intervalDays < 1 ? 1 : intervalDays;
        final offset = Dates.daysBetween(Dates.dayOf(startDate), d);
        return offset % step == 0;
      case ScheduleType.perDuration:
        // A bottle is in use every day, not on scattered dose days.
        return true;
    }
  }

  /// Units consumed on [day] — zero on a non-dosing day.
  ///
  /// [ScheduleType.perDuration] spreads one unit evenly across the days it
  /// lasts, so stock drains smoothly instead of vanishing on day one.
  double qtyOn(DateTime day) {
    if (!isActiveOn(day)) return 0;
    if (scheduleType == ScheduleType.perDuration) {
      final span = intervalDays < 1 ? 1 : intervalDays;
      return qtyPerIntake / span;
    }
    return qtyPerActiveDay;
  }

  /// Long-run average consumption per calendar day. Used for headline figures
  /// and for estimating coverage; exact projections walk day by day instead.
  double get avgPerDay {
    switch (scheduleType) {
      case ScheduleType.daily:
        return qtyPerActiveDay;
      case ScheduleType.weekdays:
        if (weekdays.isEmpty) return 0;
        return qtyPerActiveDay * weekdays.length / 7;
      case ScheduleType.interval:
        final step = intervalDays < 1 ? 1 : intervalDays;
        return qtyPerActiveDay / step;
      case ScheduleType.perDuration:
        final span = intervalDays < 1 ? 1 : intervalDays;
        return qtyPerIntake / span;
    }
  }

  /// True when this assignment never consumes anything.
  bool get isInert => avgPerDay <= 0;

  /// Short human description of the cadence, e.g. "2 × 1 a day" or
  /// "1 bottle lasts 30 days". Pass [unitLabel] to name the unit.
  String scheduleSummary({String? unitLabel}) {
    final dose = Dates.qty(qtyPerIntake);
    final base = intakesPerDay > 1 ? '$dose × $intakesPerDay' : dose;

    switch (scheduleType) {
      case ScheduleType.daily:
        return '$base a day';
      case ScheduleType.weekdays:
        if (weekdays.length == 7) return '$base a day';
        if (weekdays.isEmpty) return '$base — no days selected';
        final names = (weekdays.toList()..sort())
            .map((w) => kWeekdayShort[w - 1])
            .join(', ');
        return '$base on $names';
      case ScheduleType.interval:
        return '$base every $intervalDays days';
      case ScheduleType.perDuration:
        final unit = unitLabel == null
            ? ''
            : ' ${Dates.unit(unitLabel, qtyPerIntake)}';
        return '$dose$unit lasts $intervalDays days';
    }
  }

  /// The figure shown on dashboard cards. Continuous items read as
  /// "1 bottle / 30 days"; everything else as "3 tablets / day", because
  /// a third of a hundredth of a bottle per day tells nobody anything.
  String doseHeadline(String unitLabel) {
    if (scheduleType == ScheduleType.perDuration) {
      return '${Dates.qtyWithUnit(qtyPerIntake, unitLabel)} '
          '/ $intervalDays days';
    }
    return '${Dates.qtyWithUnit(avgPerDay, unitLabel)} / day';
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'medicine_id': medicineId,
        'patient_id': patientId,
        'qty_per_intake': qtyPerIntake,
        'intakes_per_day': intakesPerDay,
        'schedule_type': scheduleType.name,
        'weekdays': (weekdays.toList()..sort()).join(','),
        'interval_days': intervalDays,
        'start_date': Dates.toIso(startDate),
        'timing': timing,
      };

  factory DoseAssignment.fromMap(Map<String, Object?> m) {
    final raw = (m['weekdays'] as String?) ?? '';
    final days = raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .where((d) => d >= 1 && d <= 7)
        .toSet();

    return DoseAssignment(
      id: m['id'] as int?,
      medicineId: m['medicine_id'] as int?,
      patientId: (m['patient_id'] as int?) ?? 0,
      qtyPerIntake: (m['qty_per_intake'] as num?)?.toDouble() ?? 1,
      intakesPerDay: (m['intakes_per_day'] as int?) ?? 1,
      scheduleType: ScheduleType.fromName(m['schedule_type'] as String?),
      weekdays: days.isEmpty ? const {1, 2, 3, 4, 5, 6, 7} : days,
      intervalDays: (m['interval_days'] as int?) ?? 2,
      startDate: Dates.fromIso(m['start_date'] as String?) ?? Dates.today(),
      timing: m['timing'] as String?,
    );
  }
}
