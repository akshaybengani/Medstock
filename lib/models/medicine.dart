import '../constants.dart';
import '../helpers/date_helpers.dart';
import 'dose_assignment.dart';

/// A medicine in the stock book. Only [name] is required.
///
/// Stock is stored as a *snapshot*: [stockQty] is the number of units held at
/// the start of the day [stockAsOf]. Current stock is derived by replaying
/// consumption from that date forward (see `StockMath`), so the figure stays
/// correct whether or not the app was opened every night.
class Medicine {
  final int? id;
  final String name;

  /// Strength / brand detail, e.g. "5mg" or "SR 400mg".
  final String? strength;
  final MedicineType type;

  /// Absolute path to a copy of the photo in app documents storage.
  final String? imagePath;

  final double stockQty;
  final DateTime stockAsOf;

  /// Units per strip / bottle / box. When set, order quantities round up to
  /// a whole pack.
  final int packSize;

  /// Warn when remaining stock drops below this many days of cover.
  final int lowStockDays;

  final bool reminderEnabled;

  /// Free-text fields — all optional, surfaced under "Additional information".
  final String? description;
  final String? notes;
  final String? prescribedBy;
  final String? manufacturer;
  final String? storage;
  final DateTime? expiryDate;
  final double? unitPrice;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Hydrated from the join table — not persisted on the medicine row itself.
  final List<DoseAssignment> assignments;

  const Medicine({
    this.id,
    required this.name,
    this.strength,
    this.type = MedicineType.tablet,
    this.imagePath,
    this.stockQty = 0,
    required this.stockAsOf,
    this.packSize = 0,
    this.lowStockDays = K.defaultLowStockDays,
    this.reminderEnabled = true,
    this.description,
    this.notes,
    this.prescribedBy,
    this.manufacturer,
    this.storage,
    this.expiryDate,
    this.unitPrice,
    required this.createdAt,
    required this.updatedAt,
    this.assignments = const [],
  });

  Medicine copyWith({
    int? id,
    String? name,
    String? strength,
    MedicineType? type,
    String? imagePath,
    double? stockQty,
    DateTime? stockAsOf,
    int? packSize,
    int? lowStockDays,
    bool? reminderEnabled,
    String? description,
    String? notes,
    String? prescribedBy,
    String? manufacturer,
    String? storage,
    DateTime? expiryDate,
    double? unitPrice,
    DateTime? updatedAt,
    List<DoseAssignment>? assignments,
    bool clearImage = false,
    bool clearExpiry = false,
  }) =>
      Medicine(
        id: id ?? this.id,
        name: name ?? this.name,
        strength: strength ?? this.strength,
        type: type ?? this.type,
        imagePath: clearImage ? null : (imagePath ?? this.imagePath),
        stockQty: stockQty ?? this.stockQty,
        stockAsOf: stockAsOf ?? this.stockAsOf,
        packSize: packSize ?? this.packSize,
        lowStockDays: lowStockDays ?? this.lowStockDays,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        description: description ?? this.description,
        notes: notes ?? this.notes,
        prescribedBy: prescribedBy ?? this.prescribedBy,
        manufacturer: manufacturer ?? this.manufacturer,
        storage: storage ?? this.storage,
        expiryDate: clearExpiry ? null : (expiryDate ?? this.expiryDate),
        unitPrice: unitPrice ?? this.unitPrice,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        assignments: assignments ?? this.assignments,
      );

  /// "Dytor 5mg" — name plus strength when present.
  String get displayName =>
      (strength == null || strength!.trim().isEmpty)
          ? name
          : '$name ${strength!.trim()}';

  String get unitLabel => type.unitPlural;

  /// Every field a search query should be matched against.
  String get searchBlob => [
        name,
        strength,
        type.label,
        description,
        notes,
        prescribedBy,
        manufacturer,
        storage,
      ].whereType<String>().join(' ').toLowerCase();

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'strength': strength,
        'type': type.name,
        'image_path': imagePath,
        'stock_qty': stockQty,
        'stock_as_of': Dates.toIso(stockAsOf),
        'pack_size': packSize,
        'low_stock_days': lowStockDays,
        'reminder_enabled': reminderEnabled ? 1 : 0,
        'description': description,
        'notes': notes,
        'prescribed_by': prescribedBy,
        'manufacturer': manufacturer,
        'storage': storage,
        'expiry_date': expiryDate == null ? null : Dates.toIso(expiryDate!),
        'unit_price': unitPrice,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Medicine.fromMap(
    Map<String, Object?> m, {
    List<DoseAssignment> assignments = const [],
  }) =>
      Medicine(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        strength: m['strength'] as String?,
        type: MedicineType.fromName(m['type'] as String?),
        imagePath: m['image_path'] as String?,
        stockQty: (m['stock_qty'] as num?)?.toDouble() ?? 0,
        stockAsOf: Dates.fromIso(m['stock_as_of'] as String?) ?? Dates.today(),
        packSize: (m['pack_size'] as int?) ?? 0,
        lowStockDays:
            (m['low_stock_days'] as int?) ?? K.defaultLowStockDays,
        reminderEnabled: ((m['reminder_enabled'] as int?) ?? 1) == 1,
        description: m['description'] as String?,
        notes: m['notes'] as String?,
        prescribedBy: m['prescribed_by'] as String?,
        manufacturer: m['manufacturer'] as String?,
        storage: m['storage'] as String?,
        expiryDate: Dates.fromIso(m['expiry_date'] as String?),
        unitPrice: (m['unit_price'] as num?)?.toDouble(),
        createdAt:
            DateTime.tryParse((m['created_at'] as String?) ?? '') ??
                DateTime.now(),
        updatedAt:
            DateTime.tryParse((m['updated_at'] as String?) ?? '') ??
                DateTime.now(),
        assignments: assignments,
      );
}
