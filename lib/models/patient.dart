/// A person whose medicines are tracked. Patients drive the dynamic tab row
/// on the dashboard.
class Patient {
  final int? id;
  final String name;
  final String? relation;
  final int colorIndex;
  final int sortOrder;
  final DateTime createdAt;

  const Patient({
    this.id,
    required this.name,
    this.relation,
    this.colorIndex = 0,
    this.sortOrder = 0,
    required this.createdAt,
  });

  Patient copyWith({
    int? id,
    String? name,
    String? relation,
    int? colorIndex,
    int? sortOrder,
    bool clearRelation = false,
  }) =>
      Patient(
        id: id ?? this.id,
        name: name ?? this.name,
        relation: clearRelation ? null : (relation ?? this.relation),
        colorIndex: colorIndex ?? this.colorIndex,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'relation': relation,
        'color_index': colorIndex,
        'sort_order': sortOrder,
        'created_at': createdAt.toIso8601String(),
      };

  factory Patient.fromMap(Map<String, Object?> m) => Patient(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        relation: m['relation'] as String?,
        colorIndex: (m['color_index'] as int?) ?? 0,
        sortOrder: (m['sort_order'] as int?) ?? 0,
        createdAt:
            DateTime.tryParse((m['created_at'] as String?) ?? '') ??
                DateTime.now(),
      );

  /// Initials for the avatar, e.g. "Mom" -> "M", "Dada Ji" -> "DJ".
  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }
}
