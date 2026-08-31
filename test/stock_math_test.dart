import 'package:flutter_test/flutter_test.dart';
import 'package:medstock/constants.dart';
import 'package:medstock/helpers/date_helpers.dart';
import 'package:medstock/helpers/stock_math.dart';
import 'package:medstock/models/dose_assignment.dart';
import 'package:medstock/models/medicine.dart';

/// Builds a medicine whose stock snapshot is [asOfOffset] days from today,
/// so tests can exercise the "app was closed for a week" replay.
Medicine med({
  required double stock,
  int asOfOffset = 0,
  List<DoseAssignment> assignments = const [],
  int packSize = 0,
  int lowStockDays = K.defaultLowStockDays,
}) {
  final now = DateTime.now();
  return Medicine(
    id: 1,
    name: 'Test',
    stockQty: stock,
    stockAsOf: Dates.today().add(Duration(days: asOfOffset)),
    packSize: packSize,
    lowStockDays: lowStockDays,
    createdAt: now,
    updatedAt: now,
    assignments: assignments,
  );
}

DoseAssignment dose({
  int patientId = 1,
  double qtyPerIntake = 1,
  int intakesPerDay = 1,
  ScheduleType type = ScheduleType.daily,
  Set<int> weekdays = const {1, 2, 3, 4, 5, 6, 7},
  int intervalDays = 2,
  int startOffset = 0,
}) =>
    DoseAssignment(
      patientId: patientId,
      qtyPerIntake: qtyPerIntake,
      intakesPerDay: intakesPerDay,
      scheduleType: type,
      weekdays: weekdays,
      intervalDays: intervalDays,
      startDate: Dates.today().add(Duration(days: startOffset)),
    );

void main() {
  group('per-day totals', () {
    test('sums each patient\'s own dosage — the shared-medicine case', () {
      // Mom takes it once a day, Dad twice a day: total must be 3/day while
      // each patient's own figure stays intact.
      final m = med(stock: 90, assignments: [
        dose(patientId: 1, intakesPerDay: 1),
        dose(patientId: 2, intakesPerDay: 2),
      ]);

      expect(StockMath.perDay(m.assignments), 3);
      expect(StockMath.perDayForPatient(m, 1), 1);
      expect(StockMath.perDayForPatient(m, 2), 2);
    });

    test('half tablets and multiple intakes multiply out', () {
      final a = dose(qtyPerIntake: 0.5, intakesPerDay: 3);
      expect(a.qtyPerActiveDay, 1.5);
      expect(a.avgPerDay, 1.5);
    });

    test('weekday schedules average over the week', () {
      final a = dose(type: ScheduleType.weekdays, weekdays: {1, 3, 5});
      expect(a.avgPerDay, closeTo(3 / 7, 1e-9));
    });

    test('every-N-days schedules divide by the interval', () {
      final a = dose(type: ScheduleType.interval, intervalDays: 3);
      expect(a.avgPerDay, closeTo(1 / 3, 1e-9));
    });
  });

  group('stock replay', () {
    test('stock counts down from the snapshot date, not from app launches', () {
      // 100 tablets counted 10 days ago at 2/day => 80 left today.
      final m = med(
        stock: 100,
        asOfOffset: -10,
        assignments: [dose(intakesPerDay: 2, startOffset: -10)],
      );
      expect(StockMath.remainingToday(m), 80);
    });

    test('never reports negative stock', () {
      final m = med(
        stock: 5,
        asOfOffset: -30,
        assignments: [dose(intakesPerDay: 2, startOffset: -30)],
      );
      expect(StockMath.remainingToday(m), 0);
    });

    test('doses that had not started yet consume nothing', () {
      // Stock counted 10 days ago, but the course only begins today: none of
      // those 10 days should be charged against the snapshot.
      final m = med(
        stock: 100,
        asOfOffset: -10,
        assignments: [dose(intakesPerDay: 2)],
      );
      expect(StockMath.remainingToday(m), 100);
    });

    test('a fresh snapshot today reports the full count', () {
      final m = med(stock: 42, assignments: [dose(intakesPerDay: 2)]);
      expect(StockMath.remainingToday(m), 42);
    });
  });

  group('coverage', () {
    test('days left is the number of fully covered days', () {
      // 10 tablets at 2/day covers exactly 5 days, running out on day 5.
      final m = med(stock: 10, assignments: [dose(intakesPerDay: 2)]);
      final s = StockMath.status(m);

      expect(s.daysLeft, 5);
      expect(s.runOutDate, Dates.today().add(const Duration(days: 5)));
    });

    test('a partial day is not counted as covered', () {
      // 9 tablets at 2/day: 4 full days, then day 4 cannot be met.
      final s = StockMath.status(
        med(stock: 9, assignments: [dose(intakesPerDay: 2)]),
      );
      expect(s.daysLeft, 4);
    });

    test('empty stock reads as out, not as low', () {
      final s = StockMath.status(
        med(stock: 0, assignments: [dose()]),
      );
      expect(s.level, StockLevel.out);
      expect(s.daysLeft, 0);
    });

    test('low threshold drives the level', () {
      final s = StockMath.status(
        med(stock: 5, lowStockDays: 7, assignments: [dose()]),
      );
      expect(s.daysLeft, 5);
      expect(s.level, StockLevel.low);

      final healthy = StockMath.status(
        med(stock: 30, lowStockDays: 7, assignments: [dose()]),
      );
      expect(healthy.level, StockLevel.healthy);
    });

    test('a medicine with no dosage is untracked, never "out"', () {
      final s = StockMath.status(med(stock: 12));
      expect(s.level, StockLevel.untracked);
      expect(s.daysLeft, isNull);
      expect(s.runOutDate, isNull);
      expect(s.remaining, 12);
    });

    test('weekday schedules skip non-dosing days when projecting', () {
      // 2 tablets, taken only on the weekday that is 3 days from now.
      final target = Dates.today().add(const Duration(days: 3));
      final m = med(
        stock: 2,
        assignments: [
          dose(type: ScheduleType.weekdays, weekdays: {target.weekday}),
        ],
      );
      final s = StockMath.status(m);

      // Two weekly doses of 1 => covers this week and next; runs out on the
      // third occurrence, 17 days out.
      expect(s.runOutDate, target.add(const Duration(days: 14)));
    });
  });

  group('order quantities', () {
    test('covers every dose through the target date, inclusive', () {
      // 10 days ahead inclusive of today and the target = 11 days at 2/day.
      final target = Dates.today().add(const Duration(days: 10));
      final m = med(stock: 0, assignments: [dose(intakesPerDay: 2)]);

      expect(StockMath.neededThrough(m, target), 22);
      expect(StockMath.orderQtyFor(m, target), 22);
    });

    test('subtracts what is already in stock', () {
      final target = Dates.today().add(const Duration(days: 10));
      final m = med(stock: 10, assignments: [dose(intakesPerDay: 2)]);
      expect(StockMath.orderQtyFor(m, target), 12);
    });

    test('orders nothing when stock already covers the target', () {
      final target = Dates.today().add(const Duration(days: 5));
      final m = med(stock: 100, assignments: [dose(intakesPerDay: 2)]);
      expect(StockMath.orderQtyFor(m, target), 0);
    });

    test('rounds up to whole packs', () {
      // Needs 22, has 10 => shortfall 12, rounded up to two strips of 10.
      final target = Dates.today().add(const Duration(days: 10));
      final m = med(
        stock: 10,
        packSize: 10,
        assignments: [dose(intakesPerDay: 2)],
      );
      expect(StockMath.orderQtyFor(m, target), 20);
    });

    test('rounds a fractional shortfall up to a whole unit', () {
      // Half a tablet a day for 10 days = 5.5 units needed, none in stock.
      final target = Dates.today().add(const Duration(days: 10));
      final m = med(stock: 0, assignments: [dose(qtyPerIntake: 0.5)]);
      expect(StockMath.neededThrough(m, target), 5.5);
      expect(StockMath.orderQtyFor(m, target), 6);
    });

    test('a medicine with no dosage needs nothing ordered', () {
      final target = Dates.today().add(const Duration(days: 30));
      expect(StockMath.orderQtyFor(med(stock: 0), target), 0);
    });
  });

  group('reminders', () {
    test('fires lowStockDays before the run-out date', () {
      final m = med(
        stock: 20,
        lowStockDays: 7,
        assignments: [dose(intakesPerDay: 2)],
      );
      final s = StockMath.status(m);
      expect(s.daysLeft, 10);
      expect(
        StockMath.reminderDateFor(m),
        s.runOutDate!.subtract(const Duration(days: 7)),
      );
    });

    test('no reminder when reminders are switched off', () {
      final m = med(stock: 20, assignments: [dose()])
          .copyWith(reminderEnabled: false);
      expect(StockMath.reminderDateFor(m), isNull);
    });

    test('no reminder for a medicine that never depletes', () {
      expect(StockMath.reminderDateFor(med(stock: 20)), isNull);
    });
  });

  group('date helpers', () {
    test('daysBetween is DST-proof', () {
      final a = DateTime(2026, 3, 1);
      final b = DateTime(2026, 4, 1);
      expect(Dates.daysBetween(a, b), 31);
    });

    test('qty drops trailing zeros but keeps halves', () {
      expect(Dates.qty(3), '3');
      expect(Dates.qty(3.0), '3');
      expect(Dates.qty(2.5), '2.5');
    });
  });

  group('continuous-use items (eye drops, syrups)', () {
    /// One bottle recorded as lasting 30 days.
    DoseAssignment bottle({int lastsDays = 30, double units = 1, int startOffset = 0}) =>
        dose(
          qtyPerIntake: units,
          type: ScheduleType.perDuration,
          intervalDays: lastsDays,
          startOffset: startOffset,
        );

    test('burns down a fraction of a unit per day', () {
      final a = bottle();
      expect(a.avgPerDay, closeTo(1 / 30, 1e-9));
      // Every day counts, unlike an alternate-day tablet.
      expect(a.isActiveOn(Dates.today()), isTrue);
      expect(a.isActiveOn(Dates.today().add(const Duration(days: 1))), isTrue);
      expect(a.qtyOn(Dates.today()), closeTo(1 / 30, 1e-9));
    });

    test('one bottle covers exactly its stated duration', () {
      final s = StockMath.status(med(stock: 1, assignments: [bottle()]));
      expect(s.daysLeft, 30);
      expect(s.runOutDate, Dates.today().add(const Duration(days: 30)));
    });

    test('a part-used bottle still reads as part full', () {
      // Counted 15 days ago; half the bottle should remain, not none.
      final m = med(
        stock: 1,
        asOfOffset: -15,
        assignments: [bottle(startOffset: -15)],
      );
      expect(StockMath.remainingToday(m), closeTo(0.5, 1e-9));
      expect(StockMath.status(m).daysLeft, 15);
    });

    test('two bottles cover twice the duration', () {
      final s = StockMath.status(med(stock: 2, assignments: [bottle()]));
      expect(s.daysLeft, 60);
    });

    test('a shorter-lived bottle runs out sooner', () {
      final s = StockMath.status(med(stock: 1, assignments: [bottle(lastsDays: 10)]));
      expect(s.daysLeft, 10);
    });

    test('orders round a fractional need up to whole bottles', () {
      // 45 days of cover needs 1.5 bottles; you cannot buy half a bottle.
      final target = Dates.today().add(const Duration(days: 44));
      final m = med(stock: 0, assignments: [bottle()]);
      expect(StockMath.neededThrough(m, target), closeTo(1.5, 1e-9));
      expect(StockMath.orderQtyFor(m, target), 2);
    });

    test('an in-hand bottle reduces the order', () {
      final target = Dates.today().add(const Duration(days: 44));
      final m = med(stock: 1, assignments: [bottle()]);
      // Shortfall of 0.5 still means buying one more bottle.
      expect(StockMath.orderQtyFor(m, target), 1);
    });

    test('two people sharing one bottle halve its life', () {
      final m = med(stock: 1, assignments: [
        bottle().copyWith(patientId: 1),
        bottle().copyWith(patientId: 2),
      ]);
      expect(StockMath.perDay(m.assignments), closeTo(2 / 30, 1e-9));
      expect(StockMath.status(m).daysLeft, 15);
    });

    test('headline reads in bottles-per-duration, not fractions per day', () {
      final m = med(stock: 1, assignments: [bottle()]);
      expect(StockMath.headline(m.assignments, 'bottles'), '1 bottle / 30 days');

      // Two patients on the same duration combine.
      final shared = med(stock: 2, assignments: [
        bottle().copyWith(patientId: 1),
        bottle().copyWith(patientId: 2),
      ]);
      expect(
        StockMath.headline(shared.assignments, 'bottles'),
        '2 bottles / 30 days',
      );

      // Mixed modes fall back to a per-day total, which is always valid.
      final mixed = med(stock: 5, assignments: [
        bottle().copyWith(patientId: 1),
        dose(patientId: 2, intakesPerDay: 2),
      ]);
      expect(
        StockMath.headline(mixed.assignments, 'units'),
        contains('/ day'),
      );
    });

    test('summary names the unit', () {
      expect(
        bottle().scheduleSummary(unitLabel: 'bottles'),
        '1 bottle lasts 30 days',
      );
      expect(dose(intakesPerDay: 2).scheduleSummary(), '1 × 2 a day');
    });

    test('drops and syrups default to the duration mode, tablets do not', () {
      expect(MedicineType.drops.defaultSchedule, ScheduleType.perDuration);
      expect(MedicineType.syrup.defaultSchedule, ScheduleType.perDuration);
      expect(MedicineType.inhaler.isContinuousUse, isTrue);
      expect(MedicineType.tablet.defaultSchedule, ScheduleType.daily);
      expect(MedicineType.tablet.isContinuousUse, isFalse);
      expect(MedicineType.drops.unitSingular, 'bottle');
    });

    test('interval mode stays discrete — unchanged by the new mode', () {
      // Alternate-day tablet: a whole tablet on dosing days, none between.
      final a = dose(type: ScheduleType.interval, intervalDays: 2);
      expect(a.qtyOn(Dates.today()), 1);
      expect(a.qtyOn(Dates.today().add(const Duration(days: 1))), 0);
      expect(a.avgPerDay, closeTo(0.5, 1e-9));
    });
  });

  group('unit pluralisation', () {
    test('only an exact 1 takes the singular', () {
      expect(Dates.unit('tablets', 1), 'tablet');
      expect(Dates.unit('tablets', 3), 'tablets');
      expect(Dates.unit('tablets', 0), 'tablets');
      expect(Dates.unit('tablets', 0.5), 'tablets');
      expect(Dates.unit('bottles', 1), 'bottle');
      expect(Dates.unit('units', 1), 'unit');
    });

    test('qtyWithUnit pairs the number with the right form', () {
      expect(Dates.qtyWithUnit(1, 'bottles'), '1 bottle');
      expect(Dates.qtyWithUnit(2, 'bottles'), '2 bottles');
      expect(Dates.qtyWithUnit(0.6, 'bottles'), '0.6 bottles');
      expect(Dates.qtyWithUnit(40, 'tablets'), '40 tablets');
    });
  });
}
