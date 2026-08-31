import 'dart:math' as math;

import '../constants.dart';
import '../models/dose_assignment.dart';
import '../models/medicine.dart';
import 'date_helpers.dart';

/// How healthy a medicine's stock is right now.
enum StockLevel { out, low, healthy, untracked }

/// The derived stock picture for one medicine at one moment.
class StockStatus {
  /// Units held at the start of today, after replaying consumption from the
  /// stored snapshot date.
  final double remaining;

  /// Whole days of cover left, counting today. `null` means "no consumption
  /// scheduled", i.e. stock never depletes.
  final int? daysLeft;

  /// First day whose full dose cannot be met. `null` when [daysLeft] is null.
  final DateTime? runOutDate;

  /// Average units consumed per calendar day across every patient.
  final double perDay;

  final StockLevel level;

  const StockStatus({
    required this.remaining,
    required this.daysLeft,
    required this.runOutDate,
    required this.perDay,
    required this.level,
  });

  bool get isTracked => daysLeft != null;
  bool get needsAttention =>
      level == StockLevel.out || level == StockLevel.low;

  /// "12 days left" / "Out of stock" / "No dosage set".
  String get coverageLabel {
    switch (level) {
      case StockLevel.untracked:
        return 'No dosage set';
      case StockLevel.out:
        return 'Out of stock';
      case StockLevel.low:
      case StockLevel.healthy:
        final d = daysLeft!;
        if (d == 0) return 'Runs out today';
        if (d == 1) return '1 day left';
        return '$d days left';
    }
  }
}

/// Pure functions that turn a stock snapshot plus dosage schedules into
/// current stock, coverage and order quantities.
///
/// Nothing here mutates state and nothing depends on the app having been
/// opened on any particular day: stock is always *replayed* from the snapshot
/// date, so closing the app for a week still yields the right number.
class StockMath {
  StockMath._();

  /// Guard against unbounded walks when consumption is tiny relative to stock.
  static const int _horizonDays = 3650;

  /// Floating point slack — quantities are small and often halves.
  static const double _eps = 1e-9;

  /// Units consumed by [assignments] over the half-open range
  /// `[from, to)`. Returns 0 when the range is empty or reversed.
  static double consumedBetween(
    List<DoseAssignment> assignments,
    DateTime from,
    DateTime to,
  ) {
    if (assignments.isEmpty) return 0;

    final start = Dates.dayOf(from);
    final end = Dates.dayOf(to);
    final span = Dates.daysBetween(start, end);
    if (span <= 0) return 0;

    var total = 0.0;
    for (var i = 0; i < span; i++) {
      final day = start.add(Duration(days: i));
      for (final a in assignments) {
        total += a.qtyOn(day);
      }
    }
    return total;
  }

  /// Units consumed by [assignments] over `[from, through]` — inclusive of the
  /// last day. This is the shape an order needs: "enough to cover me through
  /// the 1st of October".
  static double consumedThrough(
    List<DoseAssignment> assignments,
    DateTime from,
    DateTime through,
  ) =>
      consumedBetween(
        assignments,
        from,
        Dates.dayOf(through).add(const Duration(days: 1)),
      );

  /// Total units consumed per calendar day, averaged across all schedules.
  static double perDay(List<DoseAssignment> assignments) =>
      assignments.fold<double>(0, (sum, a) => sum + a.avgPerDay);

  /// Stock held at the start of [on], replaying doses from the snapshot.
  ///
  /// Clamped at zero: you cannot hold a negative number of tablets, and
  /// letting it go negative would distort order quantities.
  static double remainingOn(Medicine medicine, DateTime on) {
    final used =
        consumedBetween(medicine.assignments, medicine.stockAsOf, on);
    return math.max(0, medicine.stockQty - used);
  }

  /// Stock held right now (start of today).
  static double remainingToday(Medicine medicine) =>
      remainingOn(medicine, Dates.today());

  /// The full derived stock picture for [medicine].
  static StockStatus status(Medicine medicine) {
    final today = Dates.today();
    final rate = perDay(medicine.assignments);
    var remaining = remainingToday(medicine);

    // No dosage attached — the medicine is a plain inventory line.
    if (rate <= _eps) {
      return StockStatus(
        remaining: remaining,
        daysLeft: null,
        runOutDate: null,
        perDay: 0,
        level: StockLevel.untracked,
      );
    }

    // Walk forward one day at a time so weekday and every-N-days schedules
    // are honoured exactly rather than averaged.
    int? daysLeft;
    DateTime? runOut;
    for (var i = 0; i < _horizonDays; i++) {
      final day = today.add(Duration(days: i));
      final need = medicine.assignments
          .fold<double>(0, (sum, a) => sum + a.qtyOn(day));

      if (need > remaining + _eps) {
        daysLeft = i;
        runOut = day;
        break;
      }
      remaining -= need;
    }

    if (daysLeft == null) {
      // Cover extends past the horizon — treat as effectively unlimited.
      return StockStatus(
        remaining: remainingToday(medicine),
        daysLeft: _horizonDays,
        runOutDate: null,
        perDay: rate,
        level: StockLevel.healthy,
      );
    }

    final level = daysLeft <= 0
        ? StockLevel.out
        : (daysLeft <= medicine.lowStockDays
            ? StockLevel.low
            : StockLevel.healthy);

    return StockStatus(
      remaining: remainingToday(medicine),
      daysLeft: daysLeft,
      runOutDate: runOut,
      perDay: rate,
      level: level,
    );
  }

  /// Units of [medicine] needed to cover every dose from today through
  /// [targetDate] inclusive.
  static double neededThrough(Medicine medicine, DateTime targetDate) =>
      consumedThrough(medicine.assignments, Dates.today(), targetDate);

  /// How many units to buy so stock lasts through [targetDate].
  ///
  /// Rounds up to a whole unit, then up to a whole pack when the medicine has
  /// a pack size — you cannot buy 37 tablets of a 10-strip.
  static double orderQtyFor(Medicine medicine, DateTime targetDate) {
    final needed = neededThrough(medicine, targetDate);
    if (needed <= 0) return 0;

    final shortfall = needed - remainingToday(medicine);
    if (shortfall <= _eps) return 0;

    var qty = shortfall.ceil();
    if (medicine.packSize > 1) {
      final packs = (qty / medicine.packSize).ceil();
      qty = packs * medicine.packSize;
    }
    return qty.toDouble();
  }

  /// The day a refill reminder should fire: [lowStockDays] before the stock
  /// runs out. `null` when the medicine never depletes or has reminders off.
  static DateTime? reminderDateFor(Medicine medicine) {
    if (!medicine.reminderEnabled) return null;

    final st = status(medicine);
    if (st.runOutDate == null) return null;

    return st.runOutDate!
        .subtract(Duration(days: medicine.lowStockDays));
  }

  /// The dose figure for a set of assignments, phrased the way the cards
  /// need it.
  ///
  /// A single assignment speaks for itself. Several continuous-use
  /// assignments sharing one duration combine ("2 bottles / 30 days").
  /// Anything mixed falls back to a per-day total, which is always valid
  /// even if it is less evocative.
  static String headline(
    List<DoseAssignment> assignments,
    String unitLabel,
  ) {
    final active = assignments.where((a) => !a.isInert).toList();
    if (active.isEmpty) return '';

    if (active.length == 1) return active.first.doseHeadline(unitLabel);

    final allDuration =
        active.every((a) => a.scheduleType == ScheduleType.perDuration);
    if (allDuration) {
      final spans = active.map((a) => a.intervalDays).toSet();
      if (spans.length == 1) {
        final qty = active.fold<double>(0, (sum, a) => sum + a.qtyPerIntake);
        return '${Dates.qtyWithUnit(qty, unitLabel)} / ${spans.first} days';
      }
    }

    return '${Dates.qtyWithUnit(perDay(active), unitLabel)} / day';
  }

  /// Assignments belonging to one patient, used by the per-patient tabs.
  static List<DoseAssignment> forPatient(Medicine medicine, int patientId) =>
      medicine.assignments.where((a) => a.patientId == patientId).toList();

  /// A patient's own consumption of [medicine] per day.
  static double perDayForPatient(Medicine medicine, int patientId) =>
      perDay(forPatient(medicine, patientId));
}
