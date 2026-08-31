import '../models/patient.dart';
import '../services/database_service.dart';

class PatientRepository {
  final DatabaseService _dbs;
  PatientRepository([DatabaseService? dbs])
      : _dbs = dbs ?? DatabaseService.instance;

  Future<List<Patient>> all() async {
    final db = await _dbs.database;
    final rows = await db.query(
      'patients',
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(Patient.fromMap).toList();
  }

  /// Inserts and returns the row with its assigned id. The colour index and
  /// sort order default to the end of the current list.
  Future<Patient> insert(Patient patient) async {
    final db = await _dbs.database;
    final count = (await db.query('patients')).length;

    final row = patient.copyWith(
      sortOrder: patient.sortOrder == 0 ? count : patient.sortOrder,
      colorIndex: patient.colorIndex == 0 ? count : patient.colorIndex,
    );

    final id = await db.insert('patients', row.toMap()..remove('id'));
    return row.copyWith(id: id);
  }

  Future<void> update(Patient patient) async {
    final db = await _dbs.database;
    await db.update(
      'patients',
      patient.toMap(),
      where: 'id = ?',
      whereArgs: [patient.id],
    );
  }

  /// Deleting a patient cascades to their dose assignments, so any medicine
  /// they were the only taker of simply becomes untracked stock.
  Future<void> delete(int id) async {
    final db = await _dbs.database;
    await db.delete('patients', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> reorder(List<Patient> ordered) async {
    final db = await _dbs.database;
    final batch = db.batch();
    for (var i = 0; i < ordered.length; i++) {
      batch.update(
        'patients',
        {'sort_order': i},
        where: 'id = ?',
        whereArgs: [ordered[i].id],
      );
    }
    await batch.commit(noResult: true);
  }
}
