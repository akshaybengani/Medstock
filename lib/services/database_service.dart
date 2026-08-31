import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../constants.dart';

/// Owns the single sqflite connection and the schema.
///
/// Everything is local: there is no network layer anywhere in Medstock.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  /// Lets tests point the connection at an in-memory database.
  @visibleForTesting
  static String? pathOverride;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = pathOverride ??
        p.join(await getDatabasesPath(), K.dbName);

    return openDatabase(
      path,
      version: K.dbVersion,
      onConfigure: (db) async {
        // Assignments and order items are meaningless without their parent.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
      onDowngrade: _refuseDowngrade,
    );
  }

  /// Migrations keyed by the schema version they produce.
  ///
  /// An upgrade runs every step between the installed version and
  /// [K.dbVersion] in order, so a user who skips several app releases still
  /// lands on the current schema with their data intact. Never edit a step
  /// that has shipped — add a new one.
  static final Map<int, Future<void> Function(Database)> _migrations = {
    2: _migrateTo2,
  };

  /// v1 -> v2: the medicine history log, and a price snapshot on order lines.
  static Future<void> _migrateTo2(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medicine_events (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        medicine_id INTEGER NOT NULL,
        type        TEXT    NOT NULL,
        at          TEXT    NOT NULL,
        qty_delta   REAL,
        qty_before  REAL,
        qty_after   REAL,
        note        TEXT,
        FOREIGN KEY (medicine_id) REFERENCES medicines (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_events_medicine '
        'ON medicine_events (medicine_id, at DESC)');

    // Snapshot the unit price on each order line so a historical order keeps
    // its cost even after the medicine is repriced.
    final columns = await db.rawQuery('PRAGMA table_info(order_items)');
    final hasPrice = columns.any((c) => c['name'] == 'unit_price');
    if (!hasPrice) {
      await db.execute('ALTER TABLE order_items ADD COLUMN unit_price REAL');
    }
  }

  Future<void> _createSchema(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE patients (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        relation    TEXT,
        color_index INTEGER NOT NULL DEFAULT 0,
        sort_order  INTEGER NOT NULL DEFAULT 0,
        created_at  TEXT    NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE medicines (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        name            TEXT    NOT NULL,
        strength        TEXT,
        type            TEXT    NOT NULL DEFAULT 'tablet',
        image_path      TEXT,
        stock_qty       REAL    NOT NULL DEFAULT 0,
        stock_as_of     TEXT    NOT NULL,
        pack_size       INTEGER NOT NULL DEFAULT 0,
        low_stock_days  INTEGER NOT NULL DEFAULT ${K.defaultLowStockDays},
        reminder_enabled INTEGER NOT NULL DEFAULT 1,
        description     TEXT,
        notes           TEXT,
        prescribed_by   TEXT,
        manufacturer    TEXT,
        storage         TEXT,
        expiry_date     TEXT,
        unit_price      REAL,
        created_at      TEXT    NOT NULL,
        updated_at      TEXT    NOT NULL
      )
    ''');

    // One row per (medicine, patient) — this is where per-patient dosage lives.
    batch.execute('''
      CREATE TABLE dose_assignments (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        medicine_id     INTEGER NOT NULL,
        patient_id      INTEGER NOT NULL,
        qty_per_intake  REAL    NOT NULL DEFAULT 1,
        intakes_per_day INTEGER NOT NULL DEFAULT 1,
        schedule_type   TEXT    NOT NULL DEFAULT 'daily',
        weekdays        TEXT    NOT NULL DEFAULT '1,2,3,4,5,6,7',
        interval_days   INTEGER NOT NULL DEFAULT 2,
        start_date      TEXT    NOT NULL,
        timing          TEXT,
        UNIQUE (medicine_id, patient_id),
        FOREIGN KEY (medicine_id) REFERENCES medicines (id) ON DELETE CASCADE,
        FOREIGN KEY (patient_id)  REFERENCES patients  (id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE pharmacies (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        name            TEXT    NOT NULL,
        whatsapp_number TEXT    NOT NULL,
        is_default      INTEGER NOT NULL DEFAULT 0,
        created_at      TEXT    NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE orders (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        target_date   TEXT    NOT NULL,
        status        TEXT    NOT NULL DEFAULT 'draft',
        pharmacy_id   INTEGER,
        pharmacy_name TEXT,
        notes         TEXT,
        created_at    TEXT    NOT NULL,
        received_at   TEXT,
        FOREIGN KEY (pharmacy_id) REFERENCES pharmacies (id) ON DELETE SET NULL
      )
    ''');

    // medicine_id is nullable and SET NULL on delete so past orders survive
    // a medicine being removed; the name is snapshotted on the row.
    batch.execute('''
      CREATE TABLE order_items (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id      INTEGER NOT NULL,
        medicine_id   INTEGER,
        medicine_name TEXT    NOT NULL,
        unit_label    TEXT    NOT NULL DEFAULT 'units',
        suggested_qty REAL    NOT NULL DEFAULT 0,
        qty           REAL    NOT NULL DEFAULT 0,
        FOREIGN KEY (order_id)    REFERENCES orders    (id) ON DELETE CASCADE,
        FOREIGN KEY (medicine_id) REFERENCES medicines (id) ON DELETE SET NULL
      )
    ''');

    batch.execute(
        'CREATE INDEX idx_assign_medicine ON dose_assignments (medicine_id)');
    batch.execute(
        'CREATE INDEX idx_assign_patient ON dose_assignments (patient_id)');
    batch.execute(
        'CREATE INDEX idx_items_order ON order_items (order_id)');
    batch.execute(
        'CREATE INDEX idx_orders_created ON orders (created_at DESC)');

    await batch.commit(noResult: true);

    // A fresh install jumps straight to the current schema by replaying every
    // migration on top of v1, so onCreate and onUpgrade can never diverge.
    for (var v = 2; v <= version; v++) {
      await _migrations[v]!(db);
    }
  }

  /// Applies every migration step between the installed and target version.
  ///
  /// Data is never dropped: each step only adds tables or columns.
  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (var version = oldVersion + 1; version <= newVersion; version++) {
      final step = _migrations[version];
      if (step == null) {
        throw StateError(
          'Medstock: no migration defined for schema v$version. '
          'Add one to DatabaseService._migrations before shipping.',
        );
      }
      await step(db);
    }
  }

  /// Installing an older build over a newer one would otherwise let sqflite
  /// wipe the file. Failing loudly keeps the data.
  Future<void> _refuseDowngrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    throw StateError(
      'Medstock: this database is schema v$oldVersion but the app expects '
      'v$newVersion. Downgrading would lose data, so it is refused. '
      'Install the newer build again, or export your data first.',
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Wipes every row, keeping the schema. Used by "Clear all data".
  Future<void> clearAll() async {
    final db = await database;
    final batch = db.batch();
    for (final table in [
      'medicine_events',
      'order_items',
      'orders',
      'dose_assignments',
      'medicines',
      'patients',
      'pharmacies',
    ]) {
      batch.delete(table);
    }
    await batch.commit(noResult: true);
  }
}
