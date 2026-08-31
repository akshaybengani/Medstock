import '../constants.dart';
import '../models/medicine_event.dart';
import '../services/database_service.dart';

/// Append-only history of what happened to each medicine.
class EventRepository {
  final DatabaseService _dbs;
  EventRepository([DatabaseService? dbs])
      : _dbs = dbs ?? DatabaseService.instance;

  Future<void> log(MedicineEvent event) async {
    if (event.medicineId == null) return;
    final db = await _dbs.database;
    await db.insert('medicine_events', event.toMap()..remove('id'));
  }

  /// Convenience for the common shape.
  Future<void> record(
    int medicineId,
    MedicineEventType type, {
    double? qtyDelta,
    double? qtyBefore,
    double? qtyAfter,
    String? note,
    DateTime? at,
  }) =>
      log(MedicineEvent(
        medicineId: medicineId,
        type: type,
        at: at ?? DateTime.now(),
        qtyDelta: qtyDelta,
        qtyBefore: qtyBefore,
        qtyAfter: qtyAfter,
        note: note,
      ));

  /// Newest first.
  Future<List<MedicineEvent>> forMedicine(int medicineId) async {
    final db = await _dbs.database;
    final rows = await db.query(
      'medicine_events',
      where: 'medicine_id = ?',
      whereArgs: [medicineId],
      orderBy: 'at DESC, id DESC',
    );
    return rows.map(MedicineEvent.fromMap).toList();
  }

  /// Every event, used by the JSON export.
  Future<List<MedicineEvent>> all() async {
    final db = await _dbs.database;
    final rows =
        await db.query('medicine_events', orderBy: 'at DESC, id DESC');
    return rows.map(MedicineEvent.fromMap).toList();
  }
}
