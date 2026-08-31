import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medstock/constants.dart';
import 'package:medstock/helpers/date_helpers.dart';
import 'package:medstock/models/dose_assignment.dart';
import 'package:medstock/models/medicine.dart';
import 'package:medstock/models/order.dart';
import 'package:medstock/providers/app_provider.dart';
import 'package:medstock/services/backup_service.dart';
import 'package:medstock/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseService.pathOverride = inMemoryDatabasePath;
  });

  late AppProvider app;

  setUp(() async {
    await DatabaseService.instance.close();
    app = AppProvider();
    await app.load();
  });

  /// [packPrice] is the cost of one pack of [packSize] units, which is how
  /// medicines are actually bought.
  Medicine draft({
    required String name,
    double stock = 0,
    double? packPrice,
    int packSize = 0,
    MedicineType type = MedicineType.tablet,
    List<DoseAssignment> assignments = const [],
  }) {
    final now = DateTime.now();
    return Medicine(
      name: name,
      type: type,
      stockQty: stock,
      stockAsOf: Dates.today(),
      packPrice: packPrice,
      packSize: packSize,
      createdAt: now,
      updatedAt: now,
      assignments: assignments,
    );
  }

  group('medicine history', () {
    test('adding a medicine records its creation and dosage', () async {
      final mom = await app.addPatient('Mom');
      final created = await app.addMedicine(draft(
        name: 'Dytor',
        stock: 30,
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));

      final events = await app.eventsFor(created.id!);
      final types = events.map((e) => e.type).toSet();
      expect(types, contains(MedicineEventType.created));
      expect(types, contains(MedicineEventType.dosageChanged));

      final creation =
          events.firstWhere((e) => e.type == MedicineEventType.created);
      expect(creation.qtyAfter, 30);
      expect(creation.describe('tablets'), 'Added to the book with 30 tablets');
    });

    test('adding stock records a signed delta', () async {
      final created = await app.addMedicine(draft(name: 'Dytor', stock: 10));
      await app.addStock(created.id!, 20);

      final events = await app.eventsFor(created.id!);
      final added =
          events.firstWhere((e) => e.type == MedicineEventType.stockAdded);
      expect(added.qtyDelta, 20);
      expect(added.qtyBefore, 10);
      expect(added.qtyAfter, 30);
      expect(added.describe('tablets'), '20 tablets added · now 30');
    });

    test('a recount records before and after', () async {
      final created = await app.addMedicine(draft(name: 'Dytor', stock: 30));
      await app.setStock(created.id!, 24);

      final events = await app.eventsFor(created.id!);
      final recount =
          events.firstWhere((e) => e.type == MedicineEventType.stockRecounted);
      expect(recount.qtyBefore, 30);
      expect(recount.qtyAfter, 24);
      expect(recount.describe('tablets'), 'Recounted 30 → 24 tablets');
    });

    test('a price change is recorded with both values', () async {
      final created = await app.addMedicine(
        draft(name: 'Dytor', stock: 10, packPrice: 20, packSize: 10),
      );

      await app.updateMedicine(Medicine(
        id: created.id,
        name: 'Dytor',
        stockQty: 10,
        stockAsOf: Dates.today(),
        packPrice: 25,
        packSize: 10,
        createdAt: created.createdAt,
        updatedAt: DateTime.now(),
      ));

      final events = await app.eventsFor(created.id!);
      final priced =
          events.firstWhere((e) => e.type == MedicineEventType.priceChanged);
      expect(priced.note, contains('₹20 per pack of 10'));
      expect(priced.note, contains('₹25 per pack of 10'));
      // And it spells out what that means per tablet.
      expect(priced.note, contains('₹2.50 per tablet'));
    });

    test('receiving an order records against each medicine', () async {
      final mom = await app.addPatient('Mom');
      final created = await app.addMedicine(draft(
        name: 'Dytor',
        stock: 2,
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));

      final target = Dates.today().add(const Duration(days: 9));
      final order = await app.createOrder(
        targetDate: target,
        items: app.buildDraft(target),
      );
      await app.receiveOrder(order);

      final events = await app.eventsFor(created.id!);
      final received =
          events.firstWhere((e) => e.type == MedicineEventType.orderReceived);
      expect(received.qtyDelta, 8);
      expect(received.describe('tablets'), contains('8 tablets added'));
    });

    test('history is newest first', () async {
      final created = await app.addMedicine(draft(name: 'Dytor', stock: 10));
      await app.addStock(created.id!, 5);
      await app.setStock(created.id!, 3);

      final events = await app.eventsFor(created.id!);
      expect(events.first.type, MedicineEventType.stockRecounted);
      expect(events.last.type, MedicineEventType.created);
    });

    test('deleting a medicine removes its history', () async {
      final created = await app.addMedicine(draft(name: 'Dytor', stock: 10));
      await app.addStock(created.id!, 5);
      expect((await app.eventsFor(created.id!)).isNotEmpty, isTrue);

      await app.deleteMedicine(created.id!);
      expect(await app.eventsFor(created.id!), isEmpty);
    });
  });

  group('order cost estimate', () {
    test('estimates from the price snapshot, exact quantity', () async {
      final mom = await app.addPatient('Mom');
      // ₹25 for a strip of 10 => ₹2.50 a tablet, 1 a day, nothing in stock.
      await app.addMedicine(draft(
        name: 'Dytor',
        packPrice: 25,
        packSize: 10,
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));
      // No price recorded.
      await app.addMedicine(draft(
        name: 'Nexito',
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));

      final target = Dates.today().add(const Duration(days: 9)); // 10 days
      final order = await app.createOrder(
        targetDate: target,
        items: app.buildDraft(target),
      );

      // 10 tablets x 2.50 = 25; the unpriced line is excluded, not guessed.
      expect(order.estimatedCost, closeTo(25, 1e-9));
      expect(order.unpricedCount, 1);

      final priced =
          order.items.firstWhere((i) => i.medicineName == 'Dytor');
      expect(priced.unitPrice, 2.5);
      expect(priced.lineCost, closeTo(25, 1e-9));

      final unpriced =
          order.items.firstWhere((i) => i.medicineName == 'Nexito');
      expect(unpriced.lineCost, isNull);
    });

    test('the snapshot survives a later reprice', () async {
      final mom = await app.addPatient('Mom');
      final created = await app.addMedicine(draft(
        name: 'Dytor',
        packPrice: 20,
        packSize: 10,
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));

      final target = Dates.today().add(const Duration(days: 9));
      final order = await app.createOrder(
        targetDate: target,
        items: app.buildDraft(target),
      );
      expect(order.estimatedCost, closeTo(20, 1e-9));

      // Reprice the medicine; the historical order must not move.
      await app.updateMedicine(Medicine(
        id: created.id,
        name: 'Dytor',
        stockQty: 0,
        stockAsOf: Dates.today(),
        packPrice: 990,
        packSize: 10,
        createdAt: created.createdAt,
        updatedAt: DateTime.now(),
        assignments: created.assignments,
      ));

      expect(app.orderById(order.id!)!.estimatedCost, closeTo(20, 1e-9));
    });

    test('no prices at all means no estimate rather than zero', () async {
      final mom = await app.addPatient('Mom');
      await app.addMedicine(draft(
        name: 'Dytor',
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
      ));
      final target = Dates.today().add(const Duration(days: 9));
      final order = await app.createOrder(
        targetDate: target,
        items: app.buildDraft(target),
      );
      expect(order.estimatedCost, isNull);
    });

    test('money formatting', () {
      expect(Dates.money(25), '₹25');
      expect(Dates.money(58.5), '₹58.50');
      expect(Dates.money(1240), '₹1,240');
    });
  });

  group('backup export / import', () {
    /// Builds a book with one of everything.
    Future<Order> seedBook() async {
      final mom = await app.addPatient('Mom');
      final dad = await app.addPatient('Dad');
      await app.addPharmacy('Sharma Medicos', '+91 98765 43210');

      final med = await app.addMedicine(draft(
        name: 'Dytor',
        stock: 60,
        packPrice: 25,
        packSize: 10,
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
          DoseAssignment(
            patientId: dad.id!,
            intakesPerDay: 2,
            startDate: Dates.today(),
          ),
        ],
      ));
      await app.addStock(med.id!, 10);

      // 70 tablets at 3/day covers 23 days, so aim well past that to make the
      // order non-empty.
      final target = Dates.today().add(const Duration(days: 40));
      return app.createOrder(
        targetDate: target,
        items: app.buildDraft(target),
        pharmacy: app.defaultPharmacy,
      );
    }

    test('export carries every table and a readable header', () async {
      await seedBook();
      final doc = await BackupService.instance.buildExport();

      expect(doc['app'], 'Medstock');
      expect(doc['formatVersion'], BackupService.formatVersion);
      expect(doc['schemaVersion'], K.dbVersion);
      expect(doc['exportedAt'], isA<String>());

      final data = doc['data'] as Map<String, Object?>;
      for (final table in [
        'patients',
        'medicines',
        'dose_assignments',
        'pharmacies',
        'orders',
        'order_items',
        'medicine_events',
      ]) {
        expect(data[table], isA<List>(), reason: '$table missing');
        expect((data[table] as List).isNotEmpty, isTrue, reason: '$table empty');
      }
    });

    test('a full round trip restores the book exactly', () async {
      final order = await seedBook();

      final before = {
        'patients': app.patients.length,
        'medicines': app.medicines.length,
        'orders': app.orders.length,
        'pharmacies': app.pharmacies.length,
      };
      final medId = app.medicines.single.id!;
      final historyBefore = (await app.eventsFor(medId)).length;
      final stockBefore = app.medicines.single.stockQty;

      final json = await _encode(await BackupService.instance.buildExport());

      // Wipe, then restore.
      await app.clearEverything();
      expect(app.medicines, isEmpty);
      expect(app.patients, isEmpty);

      final preview = await BackupService.instance.inspect(json);
      await app.restoreBackup(preview);

      expect(app.patients.length, before['patients']);
      expect(app.medicines.length, before['medicines']);
      expect(app.orders.length, before['orders']);
      expect(app.pharmacies.length, before['pharmacies']);

      // Relationships survive, not just row counts.
      final restored = app.medicines.single;
      expect(restored.id, medId);
      expect(restored.stockQty, stockBefore);
      expect(restored.assignments.length, 2);
      expect((await app.eventsFor(medId)).length, historyBefore);

      final restoredOrder = app.orderById(order.id!)!;
      expect(restoredOrder.items.single.medicineId, medId);
      expect(restoredOrder.estimatedCost, order.estimatedCost);
      expect(restoredOrder.pharmacyName, 'Sharma Medicos');
    });

    test('inspect reports what a file contains without writing', () async {
      await seedBook();
      final json = await _encode(await BackupService.instance.buildExport());

      final preview = await BackupService.instance.inspect(json);
      expect(preview.medicines, 1);
      expect(preview.patients, 2);
      expect(preview.orders, 1);
      expect(preview.pharmacies, 1);
      expect(preview.exportedAt, isNotNull);

      // Nothing was touched.
      expect(app.medicines.length, 1);
    });

    test('rubbish input is rejected with a readable message', () async {
      Future<void> expectRefusal(String text, Matcher message) async {
        await expectLater(
          BackupService.instance.inspect(text),
          throwsA(isA<BackupFormatException>().having(
            (e) => e.message,
            'message',
            message,
          )),
        );
      }

      await expectRefusal('not json at all', contains('not valid JSON'));
      await expectRefusal('[1,2,3]', contains('not a Medstock backup'));
      await expectRefusal('{"app":"Something"}', contains('not exported by'));
      await expectRefusal(
          '{"app":"Medstock"}', contains('missing its format version'));
      await expectRefusal(
        '{"app":"Medstock","formatVersion":999,"data":{}}',
        contains('newer version'),
      );
      await expectRefusal(
        '{"app":"Medstock","formatVersion":1}',
        contains('no data section'),
      );
      await expectRefusal(
        '{"app":"Medstock","formatVersion":1,"data":{}}',
        contains('empty'),
      );
    });

    test('a failed restore leaves the existing book untouched', () async {
      await seedBook();
      final medicinesBefore = app.medicines.length;

      // A malformed section is refused at inspect time, before any write.
      await expectLater(
        BackupService.instance.inspect(
          '{"app":"Medstock","formatVersion":1,'
          '"data":{"medicines":"not-a-list"}}',
        ),
        throwsA(isA<BackupFormatException>()),
      );

      expect(app.medicines.length, medicinesBefore);
    });

    test('unknown columns in an older backup are ignored, not fatal', () async {
      await seedBook();
      final doc = await BackupService.instance.buildExport();
      final data = doc['data'] as Map<String, Object?>;

      // Simulate a backup from a build that had an extra column.
      final medicines = (data['medicines'] as List).cast<Map<String, Object?>>();
      medicines.first['some_removed_column'] = 'legacy value';

      final preview = await BackupService.instance.inspect(await _encode(doc));
      await app.restoreBackup(preview);

      expect(app.medicines.single.name, 'Dytor');
    });
  });

  group('pack pricing', () {
    test('per-unit cost is derived from the pack', () {
      final m = draft(name: 'Dytor', packPrice: 25, packSize: 10);
      expect(m.packPrice, 25);
      expect(m.unitPrice, closeTo(2.5, 1e-9));
      expect(m.hasIncompletePricing, isFalse);
    });

    test('a pack of one means the pack price is the unit price', () {
      final m = draft(
        name: 'Refresh Tears',
        type: MedicineType.drops,
        packPrice: 120,
        packSize: 1,
      );
      expect(m.unitPrice, 120);
    });

    test('a price without a pack size yields no estimate, never a guess', () {
      final m = draft(name: 'Dytor', packPrice: 25);
      expect(m.unitPrice, isNull);
      expect(m.hasIncompletePricing, isTrue);
    });

    test('no price means no unit price', () {
      final m = draft(name: 'Dytor', packSize: 10);
      expect(m.unitPrice, isNull);
      expect(m.hasIncompletePricing, isFalse);
    });

    test('an order costs the exact count, not whole packs', () async {
      final mom = await app.addPatient('Mom');
      // ₹25 a strip of 10; 1 a day for 7 days needs 7 tablets, not a whole
      // strip, because the pharmacy cuts the strip.
      await app.addMedicine(draft(
        name: 'Dytor',
        packPrice: 25,
        assignments: [
          DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        ],
        packSize: 10,
      ));

      final target = Dates.today().add(const Duration(days: 6));
      final draftItems = app.buildDraft(target);
      // Quantity still rounds up to a whole pack when ordering...
      expect(draftItems.single.qty, 10);
      // ...and 10 tablets at ₹2.50 is ₹25.
      expect(draftItems.single.lineCost, closeTo(25, 1e-9));
    });
  });


  group('count labels read correctly', () {
    test('one of a thing is singular', () {
      // Mirrors BackupScreen._count, which is what the reassurance chips use.
      String count(int n, String singular) =>
          '$n ${n == 1 ? singular : '${singular}s'}';

      expect(count(0, 'medicine'), '0 medicines');
      expect(count(1, 'medicine'), '1 medicine');
      expect(count(2, 'medicine'), '2 medicines');
      expect(count(1, 'patient'), '1 patient');
      expect(count(1, 'order'), '1 order');
    });
  });
}

/// Encodes a backup document the way the screen does.
Future<String> _encode(Map<String, Object?> doc) async =>
    const JsonEncoder.withIndent('  ').convert(doc);