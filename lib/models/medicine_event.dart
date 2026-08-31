import '../constants.dart';
import '../helpers/date_helpers.dart';

/// One entry in a medicine's history. Append-only: nothing in the UI edits or
/// deletes these, they exist so you can see when you last touched something.
class MedicineEvent {
  final int? id;
  final int? medicineId;
  final MedicineEventType type;
  final DateTime at;

  /// Signed change in units, for stock movements.
  final double? qtyDelta;

  /// Stock before and after, for a recount.
  final double? qtyBefore;
  final double? qtyAfter;

  /// Extra human detail — the dosage summary, the old and new price, etc.
  final String? note;

  const MedicineEvent({
    this.id,
    this.medicineId,
    required this.type,
    required this.at,
    this.qtyDelta,
    this.qtyBefore,
    this.qtyAfter,
    this.note,
  });

  /// The line shown in the history list, e.g. "10 tablets added" or
  /// "Recounted 24 → 30 tablets".
  String describe(String unitLabel) {
    switch (type) {
      case MedicineEventType.created:
        final start = qtyAfter ?? 0;
        return start > 0
            ? 'Added to the book with '
                '${Dates.qtyWithUnit(start, unitLabel)}'
            : 'Added to the book';

      case MedicineEventType.stockAdded:
        final d = qtyDelta ?? 0;
        return '${Dates.qtyWithUnit(d, unitLabel)} added'
            '${qtyAfter == null ? '' : ' · now ${Dates.qty(qtyAfter!)}'}';

      case MedicineEventType.stockRecounted:
        if (qtyBefore == null || qtyAfter == null) return 'Recounted';
        return 'Recounted ${Dates.qty(qtyBefore!)} → '
            '${Dates.qtyWithUnit(qtyAfter!, unitLabel)}';

      case MedicineEventType.orderReceived:
        final d = qtyDelta ?? 0;
        return 'Order received · ${Dates.qtyWithUnit(d, unitLabel)} added';

      case MedicineEventType.priceChanged:
        return note ?? 'Price changed';

      case MedicineEventType.dosageChanged:
        return note ?? 'Dosage changed';

      case MedicineEventType.detailsUpdated:
        return note ?? 'Details edited';

      case MedicineEventType.imported:
        return 'Restored from an imported backup';
    }
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'medicine_id': medicineId,
        'type': type.name,
        'at': at.toIso8601String(),
        'qty_delta': qtyDelta,
        'qty_before': qtyBefore,
        'qty_after': qtyAfter,
        'note': note,
      };

  factory MedicineEvent.fromMap(Map<String, Object?> m) => MedicineEvent(
        id: m['id'] as int?,
        medicineId: m['medicine_id'] as int?,
        type: MedicineEventType.fromName(m['type'] as String?),
        at: DateTime.tryParse((m['at'] as String?) ?? '') ?? DateTime.now(),
        qtyDelta: (m['qty_delta'] as num?)?.toDouble(),
        qtyBefore: (m['qty_before'] as num?)?.toDouble(),
        qtyAfter: (m['qty_after'] as num?)?.toDouble(),
        note: m['note'] as String?,
      );
}
