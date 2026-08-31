import '../models/pharmacy.dart';
import '../services/database_service.dart';

class PharmacyRepository {
  final DatabaseService _dbs;
  PharmacyRepository([DatabaseService? dbs])
      : _dbs = dbs ?? DatabaseService.instance;

  Future<List<Pharmacy>> all() async {
    final db = await _dbs.database;
    final rows = await db.query(
      'pharmacies',
      orderBy: 'is_default DESC, name COLLATE NOCASE',
    );
    return rows.map(Pharmacy.fromMap).toList();
  }

  Future<Pharmacy> insert(Pharmacy pharmacy) async {
    final db = await _dbs.database;
    final existing = await db.query('pharmacies', limit: 1);

    // The first pharmacy saved becomes the default automatically.
    final row = existing.isEmpty
        ? pharmacy.copyWith(isDefault: true)
        : pharmacy;

    final id = await db.insert('pharmacies', row.toMap()..remove('id'));
    if (row.isDefault) await _clearOtherDefaults(id);
    return row.copyWith(id: id);
  }

  Future<void> update(Pharmacy pharmacy) async {
    final db = await _dbs.database;
    await db.update(
      'pharmacies',
      pharmacy.toMap(),
      where: 'id = ?',
      whereArgs: [pharmacy.id],
    );
    if (pharmacy.isDefault) await _clearOtherDefaults(pharmacy.id!);
  }

  Future<void> delete(int id) async {
    final db = await _dbs.database;
    await db.delete('pharmacies', where: 'id = ?', whereArgs: [id]);

    // Keep exactly one default alive if any pharmacies remain.
    final remaining = await all();
    if (remaining.isNotEmpty && !remaining.any((p) => p.isDefault)) {
      await update(remaining.first.copyWith(isDefault: true));
    }
  }

  Future<void> makeDefault(int id) async {
    final db = await _dbs.database;
    await db.update('pharmacies', {'is_default': 1},
        where: 'id = ?', whereArgs: [id]);
    await _clearOtherDefaults(id);
  }

  Future<void> _clearOtherDefaults(int keepId) async {
    final db = await _dbs.database;
    await db.update(
      'pharmacies',
      {'is_default': 0},
      where: 'id != ?',
      whereArgs: [keepId],
    );
  }
}
