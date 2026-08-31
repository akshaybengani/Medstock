import 'package:sqflite/sqflite.dart';

import '../helpers/date_helpers.dart';
import '../models/dose_assignment.dart';
import '../models/medicine.dart';
import '../services/database_service.dart';

class MedicineRepository {
  final DatabaseService _dbs;
  MedicineRepository([DatabaseService? dbs])
      : _dbs = dbs ?? DatabaseService.instance;

  /// Loads every medicine with its dose assignments attached. Two queries
  /// total rather than one per medicine.
  Future<List<Medicine>> all() async {
    final db = await _dbs.database;

    final medRows = await db.query('medicines', orderBy: 'name COLLATE NOCASE');
    final assignRows = await db.query('dose_assignments');

    final byMedicine = <int, List<DoseAssignment>>{};
    for (final row in assignRows) {
      final a = DoseAssignment.fromMap(row);
      if (a.medicineId == null) continue;
      byMedicine.putIfAbsent(a.medicineId!, () => []).add(a);
    }

    return medRows.map((row) {
      final id = row['id'] as int?;
      return Medicine.fromMap(
        row,
        assignments: id == null ? const [] : (byMedicine[id] ?? const []),
      );
    }).toList();
  }

  Future<Medicine?> byId(int id) async {
    final db = await _dbs.database;
    final rows =
        await db.query('medicines', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;

    final assignRows = await db.query(
      'dose_assignments',
      where: 'medicine_id = ?',
      whereArgs: [id],
    );

    return Medicine.fromMap(
      rows.first,
      assignments: assignRows.map(DoseAssignment.fromMap).toList(),
    );
  }

  /// Inserts the medicine and its assignments in one transaction.
  Future<Medicine> insert(Medicine medicine) async {
    final db = await _dbs.database;

    final id = await db.transaction((txn) async {
      final medId =
          await txn.insert('medicines', medicine.toMap()..remove('id'));
      await _writeAssignments(txn, medId, medicine.assignments);
      return medId;
    });

    return (await byId(id))!;
  }

  /// Updates the medicine row and replaces its assignment set.
  Future<Medicine> update(Medicine medicine) async {
    final db = await _dbs.database;
    final id = medicine.id!;

    await db.transaction((txn) async {
      await txn.update(
        'medicines',
        medicine.copyWith(updatedAt: DateTime.now()).toMap(),
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'dose_assignments',
        where: 'medicine_id = ?',
        whereArgs: [id],
      );
      await _writeAssignments(txn, id, medicine.assignments);
    });

    return (await byId(id))!;
  }

  Future<void> delete(int id) async {
    final db = await _dbs.database;
    await db.delete('medicines', where: 'id = ?', whereArgs: [id]);
  }

  /// Re-baselines the stock snapshot: [qty] units as of today. Because stock
  /// is always replayed from the snapshot date, resetting the date here is
  /// what makes the new count authoritative.
  Future<void> setStock(int medicineId, double qty) async {
    final db = await _dbs.database;
    await db.update(
      'medicines',
      {
        'stock_qty': qty < 0 ? 0 : qty,
        'stock_as_of': Dates.toIso(Dates.today()),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [medicineId],
    );
  }

  Future<void> _writeAssignments(
    DatabaseExecutor txn,
    int medicineId,
    List<DoseAssignment> assignments,
  ) async {
    for (final a in assignments) {
      await txn.insert(
        'dose_assignments',
        a.copyWith(medicineId: medicineId).toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}
