import '../constants.dart';
import '../helpers/date_helpers.dart';

/// One line of a refill order. Name and unit are snapshotted so a historical
/// order still reads correctly after the medicine is renamed or deleted.
class OrderItem {
  final int? id;
  final int? orderId;
  final int? medicineId;
  final String medicineName;
  final String unitLabel;

  /// The quantity the projection suggested, kept for reference.
  final double suggestedQty;

  /// The quantity actually ordered — editable in the draft review.
  final double qty;

  /// Price per unit at the time the order was made. Snapshotted so a
  /// historical order keeps its cost after the medicine is repriced. Null when
  /// no price was recorded for that medicine.
  final double? unitPrice;

  const OrderItem({
    this.id,
    this.orderId,
    this.medicineId,
    required this.medicineName,
    required this.unitLabel,
    required this.suggestedQty,
    required this.qty,
    this.unitPrice,
  });

  OrderItem copyWith({int? orderId, double? qty}) => OrderItem(
        id: id,
        orderId: orderId ?? this.orderId,
        medicineId: medicineId,
        medicineName: medicineName,
        unitLabel: unitLabel,
        suggestedQty: suggestedQty,
        qty: qty ?? this.qty,
        unitPrice: unitPrice,
      );

  /// Line cost, or null when this medicine has no recorded price.
  ///
  /// Pharmacies here cut strips to the exact count, so the estimate is a
  /// straight quantity × unit price with no rounding up to whole packs.
  double? get lineCost =>
      unitPrice == null ? null : unitPrice! * qty;

  /// "40 tablets" / "1 bottle" — the line as it appears in the WhatsApp
  /// message.
  String get qtyLabel => Dates.qtyWithUnit(qty, unitLabel);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'order_id': orderId,
        'medicine_id': medicineId,
        'medicine_name': medicineName,
        'unit_label': unitLabel,
        'suggested_qty': suggestedQty,
        'qty': qty,
        'unit_price': unitPrice,
      };

  factory OrderItem.fromMap(Map<String, Object?> m) => OrderItem(
        id: m['id'] as int?,
        orderId: m['order_id'] as int?,
        medicineId: m['medicine_id'] as int?,
        medicineName: (m['medicine_name'] as String?) ?? '',
        unitLabel: (m['unit_label'] as String?) ?? 'units',
        suggestedQty: (m['suggested_qty'] as num?)?.toDouble() ?? 0,
        qty: (m['qty'] as num?)?.toDouble() ?? 0,
        unitPrice: (m['unit_price'] as num?)?.toDouble(),
      );
}

/// A refill order: "buy enough of everything to last until [targetDate]".
class Order {
  final int? id;

  /// The date the stock should last through.
  final DateTime targetDate;
  final OrderStatus status;
  final int? pharmacyId;
  final String? pharmacyName;
  final String? notes;
  final DateTime createdAt;

  /// Set when the order is marked received — that top-up resets each
  /// medicine's stock snapshot.
  final DateTime? receivedAt;

  final List<OrderItem> items;

  const Order({
    this.id,
    required this.targetDate,
    this.status = OrderStatus.draft,
    this.pharmacyId,
    this.pharmacyName,
    this.notes,
    required this.createdAt,
    this.receivedAt,
    this.items = const [],
  });

  Order copyWith({
    int? id,
    DateTime? targetDate,
    OrderStatus? status,
    int? pharmacyId,
    String? pharmacyName,
    String? notes,
    DateTime? receivedAt,
    List<OrderItem>? items,
  }) =>
      Order(
        id: id ?? this.id,
        targetDate: targetDate ?? this.targetDate,
        status: status ?? this.status,
        pharmacyId: pharmacyId ?? this.pharmacyId,
        pharmacyName: pharmacyName ?? this.pharmacyName,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        receivedAt: receivedAt ?? this.receivedAt,
        items: items ?? this.items,
      );

  int get itemCount => items.length;

  double get totalUnits =>
      items.fold<double>(0, (sum, item) => sum + item.qty);

  /// Estimated cost of the lines that have a price. Null when none do.
  double? get estimatedCost {
    var total = 0.0;
    var any = false;
    for (final item in items) {
      final cost = item.lineCost;
      if (cost == null) continue;
      total += cost;
      any = true;
    }
    return any ? total : null;
  }

  /// Lines with no recorded price, so the UI can say the estimate is partial.
  int get unpricedCount =>
      items.where((i) => i.unitPrice == null).length;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'target_date': Dates.toIso(targetDate),
        'status': status.name,
        'pharmacy_id': pharmacyId,
        'pharmacy_name': pharmacyName,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'received_at': receivedAt?.toIso8601String(),
      };

  factory Order.fromMap(
    Map<String, Object?> m, {
    List<OrderItem> items = const [],
  }) =>
      Order(
        id: m['id'] as int?,
        targetDate:
            Dates.fromIso(m['target_date'] as String?) ?? Dates.today(),
        status: OrderStatus.fromName(m['status'] as String?),
        pharmacyId: m['pharmacy_id'] as int?,
        pharmacyName: m['pharmacy_name'] as String?,
        notes: m['notes'] as String?,
        createdAt:
            DateTime.tryParse((m['created_at'] as String?) ?? '') ??
                DateTime.now(),
        receivedAt: DateTime.tryParse((m['received_at'] as String?) ?? ''),
        items: items,
      );
}
