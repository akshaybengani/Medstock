import 'package:flutter_test/flutter_test.dart';
import 'package:medstock/constants.dart';
import 'package:medstock/helpers/date_helpers.dart';
import 'package:medstock/helpers/stock_math.dart';
import 'package:medstock/models/dose_assignment.dart';
import 'package:medstock/models/medicine.dart';
import 'package:medstock/providers/app_provider.dart';
import 'package:medstock/services/database_service.dart';
import 'package:medstock/services/whatsapp_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Exercises the real sqflite schema, repositories and provider end to end —
/// no mocks — using an in-memory database.
void main() {
  setUpAll(() {
    // Initialises the binding so the notification plugin's method channels
    // return null in tests instead of throwing.
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseService.pathOverride = inMemoryDatabasePath;
  });

  late AppProvider app;

  setUp(() async {
    // A fresh in-memory database per test.
    await DatabaseService.instance.close();
    app = AppProvider();
    await app.load();
  });

  Medicine draftMedicine({
    required String name,
    String? strength,
    double stock = 0,
    int packSize = 0,
    MedicineType type = MedicineType.tablet,
    List<DoseAssignment> assignments = const [],
    String? notes,
  }) {
    final now = DateTime.now();
    return Medicine(
      name: name,
      strength: strength,
      type: type,
      stockQty: stock,
      stockAsOf: Dates.today(),
      packSize: packSize,
      notes: notes,
      createdAt: now,
      updatedAt: now,
      assignments: assignments,
    );
  }

  group('patients and the dynamic dashboard', () {
    test('patients persist and get distinct accent colours', () async {
      final mom = await app.addPatient('Mom', relation: 'Mother');
      final dad = await app.addPatient('Dad');

      expect(app.patients.length, 2);
      expect(mom.id, isNotNull);
      expect(app.patientById(mom.id!)?.relation, 'Mother');
      expect(mom.colorIndex, isNot(dad.colorIndex));
      // Tab order follows sort_order.
      expect(app.patients.map((p) => p.name), ['Mom', 'Dad']);
    });

    test('deleting a patient removes their dosage but keeps the medicine',
        () async {
      final mom = await app.addPatient('Mom');
      final dad = await app.addPatient('Dad');

      await app.addMedicine(draftMedicine(
        name: 'Dytor',
        strength: '5',
        stock: 30,
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
          DoseAssignment(
            patientId: dad.id!,
            intakesPerDay: 2,
            startDate: Dates.today(),
          ),
        ],
      ));

      expect(app.medicines.single.assignments.length, 2);

      await app.deletePatient(dad.id!);

      // The cascade removed Dad's row; the medicine and its stock survive.
      expect(app.medicines.length, 1);
      expect(app.medicines.single.assignments.length, 1);
      expect(app.medicines.single.assignments.single.patientId, mom.id);
      expect(StockMath.remainingToday(app.medicines.single), 30);
    });
  });

  group('the shared-medicine case', () {
    test('All tab sums dosages while patient tabs stay separate', () async {
      final mom = await app.addPatient('Mom');
      final dad = await app.addPatient('Dad');

      await app.addMedicine(draftMedicine(
        name: 'Dytor',
        strength: '5',
        stock: 60,
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
          DoseAssignment(
            patientId: dad.id!,
            intakesPerDay: 2,
            startDate: Dates.today(),
          ),
        ],
      ));

      final dytor = app.medicines.single;

      expect(StockMath.perDay(dytor.assignments), 3);
      expect(StockMath.perDayForPatient(dytor, mom.id!), 1);
      expect(StockMath.perDayForPatient(dytor, dad.id!), 2);

      // Both tabs list it; household burn is 3/day so 60 lasts 20 days.
      expect(app.medicinesFor(null).length, 1);
      expect(app.medicinesFor(mom.id).length, 1);
      expect(StockMath.status(dytor).daysLeft, 20);

      expect(app.dailyTotal(), 3);
      expect(app.dailyTotal(patientId: dad.id), 2);
    });

    test('a patient tab excludes medicines they do not take', () async {
      final mom = await app.addPatient('Mom');
      final me = await app.addPatient('Akshay');

      await app.addMedicine(draftMedicine(
        name: 'Dytor',
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));
      await app.addMedicine(draftMedicine(
        name: 'Multivitamin',
        assignments: [
          DoseAssignment(patientId: me.id!, startDate: Dates.today()),
        ],
      ));

      expect(app.medicinesFor(null).length, 2);
      expect(app.medicinesFor(mom.id).single.name, 'Dytor');
      expect(app.medicinesFor(me.id).single.name, 'Multivitamin');
    });
  });

  group('search', () {
    test('matches across every field and patient names', () async {
      final mom = await app.addPatient('Mom');

      await app.addMedicine(draftMedicine(
        name: 'Lithosun SR',
        strength: '400mg',
        notes: 'Keep away from sunlight',
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));
      await app.addMedicine(draftMedicine(name: 'Nexito', strength: '10mg'));

      app.setSearch('lithosun');
      expect(app.medicinesFor(null).single.name, 'Lithosun SR');

      // A note field.
      app.setSearch('sunlight');
      expect(app.medicinesFor(null).single.name, 'Lithosun SR');

      // A patient name.
      app.setSearch('mom');
      expect(app.medicinesFor(null).single.name, 'Lithosun SR');

      // Strength.
      app.setSearch('10mg');
      expect(app.medicinesFor(null).single.name, 'Nexito');

      // Terms are ANDed, so this narrows to nothing.
      app.setSearch('nexito sunlight');
      expect(app.medicinesFor(null), isEmpty);

      app.clearSearch();
      expect(app.medicinesFor(null).length, 2);
    });
  });

  group('stock adjustments', () {
    test('add stock accumulates on top of what is left', () async {
      final mom = await app.addPatient('Mom');
      final created = await app.addMedicine(draftMedicine(
        name: 'Dytor',
        stock: 10,
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));

      await app.addStock(created.id!, 30);
      expect(StockMath.remainingToday(app.medicines.single), 40);

      await app.setStock(created.id!, 12);
      expect(StockMath.remainingToday(app.medicines.single), 12);
    });
  });

  group('order flow', () {
    test('draft projects quantities, respects stock and pack sizes', () async {
      final mom = await app.addPatient('Mom');
      final dad = await app.addPatient('Dad');
      final target = Dates.today().add(const Duration(days: 9)); // 10 days

      // 3/day household, nothing in stock => 30 needed.
      await app.addMedicine(draftMedicine(
        name: 'Dytor',
        strength: '5',
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
          DoseAssignment(
            patientId: dad.id!,
            intakesPerDay: 2,
            startDate: Dates.today(),
          ),
        ],
      ));

      // 1/day, 4 in stock, strips of 10 => needs 6, rounds up to 10.
      await app.addMedicine(draftMedicine(
        name: 'Nexito',
        strength: '10mg',
        stock: 4,
        packSize: 10,
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));

      // Already covered — must not appear in the draft.
      await app.addMedicine(draftMedicine(
        name: 'Glufomin XL',
        stock: 500,
        assignments: [
          DoseAssignment(patientId: dad.id!, startDate: Dates.today()),
        ],
      ));

      // No dosage — cannot be projected, so it is left out.
      await app.addMedicine(draftMedicine(name: 'Random Balm'));

      final draft = app.buildDraft(target);

      expect(draft.map((i) => i.medicineName), ['Dytor 5', 'Nexito 10mg']);
      expect(draft[0].qty, 30);
      expect(draft[1].qty, 10);
    });

    test('created order persists and formats the WhatsApp message', () async {
      final mom = await app.addPatient('Mom');
      final target = Dates.today().add(const Duration(days: 9));

      await app.addMedicine(draftMedicine(
        name: 'Lithosun SR',
        strength: '400mg',
        assignments: [
          DoseAssignment(
            patientId: mom.id!,
            qtyPerIntake: 2,
            intakesPerDay: 2,
            startDate: Dates.today(),
          ),
        ],
      ));

      await app.addPharmacy('Sharma Medicos', '+91 98765 43210');
      expect(app.defaultPharmacy?.sanitizedNumber, '919876543210');

      final order = await app.createOrder(
        targetDate: target,
        items: app.buildDraft(target),
        pharmacy: app.defaultPharmacy,
      );

      expect(app.orders.length, 1);
      expect(order.status, OrderStatus.draft);
      expect(order.pharmacyName, 'Sharma Medicos');
      // 4/day over 10 days.
      expect(order.items.single.qty, 40);

      final message = WhatsappService.instance.formatOrder(order);
      expect(message, 'Lithosun SR 400mg\n40 tablets');
    });

    test('message uses the name/quantity block format with blank lines',
        () async {
      final mom = await app.addPatient('Mom');
      final target = Dates.today().add(const Duration(days: 29));

      for (final (name, strength) in [
        ('Nexito', '10mg'),
        ('Telvok AM', '40'),
      ]) {
        await app.addMedicine(draftMedicine(
          name: name,
          strength: strength,
          assignments: [
            DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
          ],
        ));
      }

      final order = await app.createOrder(
        targetDate: target,
        items: app.buildDraft(target),
      );

      expect(
        WhatsappService.instance.formatOrder(order),
        'Nexito 10mg\n30 tablets\n\nTelvok AM 40\n30 tablets',
      );
    });

    test('receiving an order tops up stock and closes the loop', () async {
      final mom = await app.addPatient('Mom');
      final target = Dates.today().add(const Duration(days: 9));

      await app.addMedicine(draftMedicine(
        name: 'Dytor',
        stock: 2,
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));

      // Needs 10 over the window, has 2 => order 8.
      final order = await app.createOrder(
        targetDate: target,
        items: app.buildDraft(target),
      );
      expect(order.items.single.qty, 8);

      await app.receiveOrder(order);

      final refreshed = app.medicines.single;
      expect(StockMath.remainingToday(refreshed), 10);
      expect(app.orderById(order.id!)?.status, OrderStatus.received);
      expect(app.orderById(order.id!)?.receivedAt, isNotNull);

      // Stock now reaches exactly the target date.
      expect(StockMath.orderQtyFor(refreshed, target), 0);
      expect(StockMath.status(refreshed).daysLeft, 10);
    });

    test('a deleted medicine leaves its order line intact', () async {
      final mom = await app.addPatient('Mom');
      final target = Dates.today().add(const Duration(days: 9));

      final created = await app.addMedicine(draftMedicine(
        name: 'Nexito',
        strength: '10mg',
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));

      final order = await app.createOrder(
        targetDate: target,
        items: app.buildDraft(target),
      );

      await app.deleteMedicine(created.id!);

      final kept = app.orderById(order.id!)!;
      expect(kept.items.single.medicineName, 'Nexito 10mg');
      expect(kept.items.single.qty, 10);
      // The link is severed but the snapshot survives.
      expect(kept.items.single.medicineId, isNull);
    });
  });

  group('assignment editing', () {
    test('upsert replaces only that patient\'s dosage', () async {
      final mom = await app.addPatient('Mom');
      final dad = await app.addPatient('Dad');

      final created = await app.addMedicine(draftMedicine(
        name: 'Dytor',
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
          DoseAssignment(patientId: dad.id!, startDate: Dates.today()),
        ],
      ));
      expect(StockMath.perDay(app.medicines.single.assignments), 2);

      await app.upsertAssignment(
        created.id!,
        DoseAssignment(
          patientId: dad.id!,
          intakesPerDay: 3,
          startDate: Dates.today(),
        ),
      );

      final m = app.medicines.single;
      expect(StockMath.perDayForPatient(m, mom.id!), 1);
      expect(StockMath.perDayForPatient(m, dad.id!), 3);
      expect(StockMath.perDay(m.assignments), 4);

      await app.removeAssignment(created.id!, dad.id!);
      expect(StockMath.perDay(app.medicines.single.assignments), 1);
    });

    test('weekday schedules survive a round trip through sqflite', () async {
      final mom = await app.addPatient('Mom');

      await app.addMedicine(draftMedicine(
        name: 'Weekly shot',
        type: MedicineType.injection,
        assignments: [
          DoseAssignment(
            patientId: mom.id!,
            scheduleType: ScheduleType.weekdays,
            weekdays: const {1, 4},
            startDate: Dates.today(),
          ),
        ],
      ));

      final a = app.medicines.single.assignments.single;
      expect(a.scheduleType, ScheduleType.weekdays);
      expect(a.weekdays, {1, 4});
      expect(a.avgPerDay, closeTo(2 / 7, 1e-9));
      expect(app.medicines.single.unitLabel, 'vials');
    });
  });

  group('attention ordering', () {
    test('out-of-stock sorts above low, low above healthy', () async {
      final mom = await app.addPatient('Mom');

      Future<void> add(String name, double stock) => app.addMedicine(
            draftMedicine(
              name: name,
              stock: stock,
              assignments: [
                DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
              ],
            ),
          );

      await add('Healthy', 90);
      await add('Empty', 0);
      await add('Low', 3);
      await app.addMedicine(draftMedicine(name: 'Untracked', stock: 5));

      expect(
        app.medicinesFor(null).map((m) => m.name),
        ['Empty', 'Low', 'Healthy', 'Untracked'],
      );
      expect(app.needsAttention.map((m) => m.name).toSet(), {'Empty', 'Low'});
    });
  });

  group('editing clears optional fields', () {
    test('blanking an optional medicine field actually clears it', () async {
      final mom = await app.addPatient('Mom');
      final created = await app.addMedicine(draftMedicine(
        name: 'Dytor',
        strength: '5',
        notes: 'Morning only',
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));

      // Rebuild the row the way the edit form does, with the optional fields
      // blanked out.
      await app.updateMedicine(Medicine(
        id: created.id,
        name: 'Dytor',
        strength: null,
        notes: null,
        stockQty: 0,
        stockAsOf: Dates.today(),
        createdAt: created.createdAt,
        updatedAt: DateTime.now(),
        assignments: created.assignments,
      ));

      final after = app.medicines.single;
      expect(after.strength, isNull);
      expect(after.notes, isNull);
      expect(after.displayName, 'Dytor');
    });

    test('blanking a patient relation clears it', () async {
      final mom = await app.addPatient('Mom', relation: 'Mother');
      expect(app.patientById(mom.id!)?.relation, 'Mother');

      await app.updatePatient(mom.copyWith(clearRelation: true));
      expect(app.patientById(mom.id!)?.relation, isNull);
    });
  });

  group('continuous-use medicines round-trip', () {
    test('an eye-drop bottle persists its duration schedule', () async {
      final mom = await app.addPatient('Mom');

      await app.addMedicine(draftMedicine(
        name: 'Refresh Tears',
        type: MedicineType.drops,
        stock: 1,
        assignments: [
          DoseAssignment(
            patientId: mom.id!,
            scheduleType: ScheduleType.perDuration,
            intervalDays: 30,
            startDate: Dates.today(),
          ),
        ],
      ));

      final drops = app.medicines.single;
      expect(drops.type, MedicineType.drops);
      expect(drops.unitLabel, 'bottles');

      final a = drops.assignments.single;
      expect(a.scheduleType, ScheduleType.perDuration);
      expect(a.intervalDays, 30);
      expect(a.avgPerDay, closeTo(1 / 30, 1e-9));

      // One bottle is exactly a month of cover.
      expect(StockMath.status(drops).daysLeft, 30);
      expect(
        StockMath.headline(drops.assignments, drops.unitLabel),
        '1 bottle / 30 days',
      );
    });

    test('a 90-day order asks for the right number of bottles', () async {
      final mom = await app.addPatient('Mom');
      await app.addMedicine(draftMedicine(
        name: 'Refresh Tears',
        type: MedicineType.drops,
        stock: 1,
        assignments: [
          DoseAssignment(
            patientId: mom.id!,
            scheduleType: ScheduleType.perDuration,
            intervalDays: 30,
            startDate: Dates.today(),
          ),
        ],
      ));

      // 90 days of cover needs 3 bottles; one is already in hand.
      final target = Dates.today().add(const Duration(days: 89));
      final draft = app.buildDraft(target);
      expect(draft.single.qty, 2);
      expect(draft.single.unitLabel, 'bottles');

      final order = await app.createOrder(
        targetDate: target,
        items: draft,
      );
      expect(
        WhatsappService.instance.formatOrder(order),
        'Refresh Tears\n2 bottles',
      );
    });

    test('the dashboard headline figure is the soonest run-out', () async {
      final mom = await app.addPatient('Mom');

      // A bottle lasting a month, and a tablet that runs out in 5 days.
      await app.addMedicine(draftMedicine(
        name: 'Refresh Tears',
        type: MedicineType.drops,
        stock: 1,
        assignments: [
          DoseAssignment(
            patientId: mom.id!,
            scheduleType: ScheduleType.perDuration,
            intervalDays: 30,
            startDate: Dates.today(),
          ),
        ],
      ));
      await app.addMedicine(draftMedicine(
        name: 'Dytor',
        stock: 5,
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));

      final soonest = app.soonestRunOut;
      expect(soonest, isNotNull);
      expect(soonest!.$1.name, 'Dytor');
      expect(soonest.$2.daysLeft, 5);
    });
  });

  group('day rollover', () {
    test('figures are recomputed when the calendar day changes', () async {
      final mom = await app.addPatient('Mom');
      await app.addMedicine(draftMedicine(
        name: 'Dytor',
        stock: 10,
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));

      // Same day: nothing to do.
      expect(app.refreshIfDayChanged(), isFalse);

      // Simulate yesterday's render by rewinding the stamp, the way an app
      // left open overnight would look.
      app.debugSetFiguresDate(Dates.today().subtract(const Duration(days: 1)));
      expect(app.refreshIfDayChanged(), isTrue);
      // And it settles again.
      expect(app.refreshIfDayChanged(), isFalse);
    });

    test('a rollover notifies listeners exactly once', () async {
      var notifications = 0;
      app.addListener(() => notifications++);

      app.debugSetFiguresDate(Dates.today().subtract(const Duration(days: 2)));
      app.refreshIfDayChanged();
      expect(notifications, 1);

      app.refreshIfDayChanged();
      expect(notifications, 1);
    });
  });

  group('attention ordering is computed once per medicine', () {
    test('ordering still holds after the sort refactor', () async {
      final mom = await app.addPatient('Mom');
      Future<void> add(String name, double stock) => app.addMedicine(
            draftMedicine(
              name: name,
              stock: stock,
              assignments: [
                DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
              ],
            ),
          );

      await add('Zebra healthy', 90);
      await add('Alpha healthy', 90);
      await add('Empty', 0);
      await add('Low', 3);

      expect(
        app.medicinesFor(null).map((m) => m.name),
        ['Empty', 'Low', 'Alpha healthy', 'Zebra healthy'],
      );
    });
  });
}
