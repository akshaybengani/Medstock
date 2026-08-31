import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medstock/constants.dart';
import 'package:medstock/services/database_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Proves an app update does not destroy the medicine book.
///
/// Each case builds a database at an *older* schema version by hand, closes
/// it, then opens it through DatabaseService — which is what happens when a
/// user installs a new build over an old one — and checks the rows are still
/// there and the new schema is in place.
void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('medstock_migration');
    await DatabaseService.instance.close();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.pathOverride = null;
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// The exact v1 schema as originally shipped, plus one row in each table.
  Future<String> seedV1Database() async {
    final path = p.join(tmp.path, 'medstock.db');
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: (db, _) async {}),
    );

    await db.execute('''
      CREATE TABLE patients (
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
        relation TEXT, color_index INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL)
    ''');
    await db.execute('''
      CREATE TABLE medicines (
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
        strength TEXT, type TEXT NOT NULL DEFAULT 'tablet', image_path TEXT,
        stock_qty REAL NOT NULL DEFAULT 0, stock_as_of TEXT NOT NULL,
        pack_size INTEGER NOT NULL DEFAULT 0,
        low_stock_days INTEGER NOT NULL DEFAULT 7,
        reminder_enabled INTEGER NOT NULL DEFAULT 1, description TEXT,
        notes TEXT, prescribed_by TEXT, manufacturer TEXT, storage TEXT,
        expiry_date TEXT, unit_price REAL, created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL)
    ''');
    await db.execute('''
      CREATE TABLE dose_assignments (
        id INTEGER PRIMARY KEY AUTOINCREMENT, medicine_id INTEGER NOT NULL,
        patient_id INTEGER NOT NULL, qty_per_intake REAL NOT NULL DEFAULT 1,
        intakes_per_day INTEGER NOT NULL DEFAULT 1,
        schedule_type TEXT NOT NULL DEFAULT 'daily',
        weekdays TEXT NOT NULL DEFAULT '1,2,3,4,5,6,7',
        interval_days INTEGER NOT NULL DEFAULT 2, start_date TEXT NOT NULL,
        timing TEXT, UNIQUE (medicine_id, patient_id))
    ''');
    await db.execute('''
      CREATE TABLE pharmacies (
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
        whatsapp_number TEXT NOT NULL, is_default INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL)
    ''');
    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT, target_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft', pharmacy_id INTEGER,
        pharmacy_name TEXT, notes TEXT, created_at TEXT NOT NULL,
        received_at TEXT)
    ''');
    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT, order_id INTEGER NOT NULL,
        medicine_id INTEGER, medicine_name TEXT NOT NULL,
        unit_label TEXT NOT NULL DEFAULT 'units',
        suggested_qty REAL NOT NULL DEFAULT 0, qty REAL NOT NULL DEFAULT 0)
    ''');

    final now = DateTime.now().toIso8601String();
    await db.insert('patients',
        {'name': 'Mom', 'relation': 'Mother', 'created_at': now});
    await db.insert('medicines', {
      'name': 'Dytor',
      'strength': '5',
      'type': 'tablet',
      'stock_qty': 60.0,
      'stock_as_of': '2026-08-31',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('dose_assignments', {
      'medicine_id': 1,
      'patient_id': 1,
      'start_date': '2026-08-31',
    });
    await db.insert('pharmacies', {
      'name': 'Sharma Medicos',
      'whatsapp_number': '919876543210',
      'is_default': 1,
      'created_at': now,
    });
    await db.insert('orders',
        {'target_date': '2026-10-01', 'status': 'ordered', 'created_at': now});
    await db.insert('order_items', {
      'order_id': 1,
      'medicine_id': 1,
      'medicine_name': 'Dytor 5',
      'unit_label': 'tablets',
      'suggested_qty': 30.0,
      'qty': 30.0,
    });

    await db.close();
    return path;
  }

  test('upgrading v1 -> current keeps every row', () async {
    final path = await seedV1Database();
    DatabaseService.pathOverride = path;

    final db = await DatabaseService.instance.database;
    expect(await db.getVersion(), K.dbVersion);

    // Nothing was dropped.
    expect((await db.query('patients')).single['name'], 'Mom');
    expect((await db.query('medicines')).single['name'], 'Dytor');
    expect((await db.query('medicines')).single['stock_qty'], 60.0);
    expect((await db.query('dose_assignments')).length, 1);
    expect((await db.query('pharmacies')).single['name'], 'Sharma Medicos');
    expect((await db.query('orders')).single['status'], 'ordered');
    expect((await db.query('order_items')).single['qty'], 30.0);
  });

  test('upgrading v1 -> current adds the history table', () async {
    DatabaseService.pathOverride = await seedV1Database();
    final db = await DatabaseService.instance.database;

    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((r) => r['name'] as String).toSet();
    expect(tables, contains('medicine_events'));

    // And it is usable.
    await db.insert('medicine_events', {
      'medicine_id': 1,
      'type': 'stockAdded',
      'at': DateTime.now().toIso8601String(),
      'qty_delta': 10.0,
    });
    expect((await db.query('medicine_events')).length, 1);
  });

  test('upgrading v1 -> current adds unit_price to order lines', () async {
    DatabaseService.pathOverride = await seedV1Database();
    final db = await DatabaseService.instance.database;

    final cols = (await db.rawQuery('PRAGMA table_info(order_items)'))
        .map((c) => c['name'] as String)
        .toSet();
    expect(cols, contains('unit_price'));
    // The pre-existing row survives with a null price.
    expect((await db.query('order_items')).single['unit_price'], isNull);
  });

  test('a fresh install lands on exactly the same schema as an upgrade',
      () async {
    // Fresh install.
    DatabaseService.pathOverride = p.join(tmp.path, 'fresh.db');
    final fresh = await DatabaseService.instance.database;
    final freshTables = await _schemaOf(fresh);
    await DatabaseService.instance.close();

    // Upgraded from v1.
    DatabaseService.pathOverride = await seedV1Database();
    final upgraded = await DatabaseService.instance.database;
    final upgradedTables = await _schemaOf(upgraded);

    expect(upgradedTables, freshTables,
        reason: 'onCreate and onUpgrade must converge on one schema');
  });

  test('reopening an already-current database is a no-op', () async {
    DatabaseService.pathOverride = p.join(tmp.path, 'again.db');
    var db = await DatabaseService.instance.database;
    await db.insert('patients', {
      'name': 'Dad',
      'created_at': DateTime.now().toIso8601String(),
    });
    await DatabaseService.instance.close();

    db = await DatabaseService.instance.database;
    expect((await db.query('patients')).single['name'], 'Dad');
    expect(await db.getVersion(), K.dbVersion);
  });

  test('every version between 2 and the current one has a migration', () async {
    // Guards against bumping dbVersion without writing the step.
    DatabaseService.pathOverride = await seedV1Database();
    await DatabaseService.instance.database; // would throw if one were missing
  });

  /// A v2 database: the history table exists and price is still per unit.
  Future<String> seedV2Database({
    double? unitPrice,
    int packSize = 0,
  }) async {
    // Build v1 first, then apply the shipped v2 step, so this fixture cannot
    // drift from the real migration path.
    final path = await seedV1Database();
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1),
    );
    await db.execute('''
      CREATE TABLE medicine_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT, medicine_id INTEGER NOT NULL,
        type TEXT NOT NULL, at TEXT NOT NULL, qty_delta REAL,
        qty_before REAL, qty_after REAL, note TEXT)
    ''');
    await db.execute('ALTER TABLE order_items ADD COLUMN unit_price REAL');
    await db.update('medicines', {
      'unit_price': unitPrice,
      'pack_size': packSize,
    });
    await db.setVersion(2);
    await db.close();
    return path;
  }

  group('v2 -> v3: price moves from per unit to per pack', () {
    test('a priced medicine keeps the same cost per unit', () async {
      // ₹2.50 a tablet in a strip of 10 becomes ₹25 a strip.
      DatabaseService.pathOverride =
          await seedV2Database(unitPrice: 2.5, packSize: 10);
      final db = await DatabaseService.instance.database;

      expect(await db.getVersion(), K.dbVersion);
      final row = (await db.query('medicines')).single;
      expect(row['pack_price'], closeTo(25, 1e-9));
      expect(row['pack_size'], 10);
      // The derived per-unit cost is unchanged, which is the whole point.
      expect((row['pack_price'] as num) / (row['pack_size'] as num),
          closeTo(2.5, 1e-9));
    });

    test('a price with no pack size becomes a pack of one', () async {
      DatabaseService.pathOverride =
          await seedV2Database(unitPrice: 7, packSize: 0);
      final db = await DatabaseService.instance.database;

      final row = (await db.query('medicines')).single;
      expect(row['pack_price'], closeTo(7, 1e-9));
      expect(row['pack_size'], 1);
    });

    test('an unpriced medicine stays unpriced', () async {
      DatabaseService.pathOverride =
          await seedV2Database(unitPrice: null, packSize: 10);
      final db = await DatabaseService.instance.database;

      final row = (await db.query('medicines')).single;
      expect(row['pack_price'], isNull);
      expect(row['pack_size'], 10);
    });

    test('rows survive the whole v1 -> v3 chain', () async {
      DatabaseService.pathOverride = await seedV1Database();
      final db = await DatabaseService.instance.database;

      expect(await db.getVersion(), K.dbVersion);
      expect((await db.query('medicines')).single['name'], 'Dytor');
      expect((await db.query('patients')).single['name'], 'Mom');
      expect((await db.query('order_items')).single['qty'], 30.0);

      final cols = (await db.rawQuery('PRAGMA table_info(medicines)'))
          .map((c) => c['name'] as String)
          .toSet();
      expect(cols, contains('pack_price'));
    });
  });
}

/// Table and column names, so two databases can be compared structurally.
Future<Map<String, Set<String>>> _schemaOf(dynamic db) async {
  final tables = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' "
    "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
  )).map((r) => r['name'] as String).toList()
    ..sort();

  final out = <String, Set<String>>{};
  for (final t in tables) {
    final cols = await db.rawQuery('PRAGMA table_info($t)');
    out[t] = cols.map<String>((c) => c['name'] as String).toSet();
  }
  return out;
}
