/// A saved pharmacy contact used to pre-fill the WhatsApp share target.
class Pharmacy {
  final int? id;
  final String name;

  /// Digits only, including country code — e.g. "919876543210".
  final String whatsappNumber;
  final bool isDefault;
  final DateTime createdAt;

  const Pharmacy({
    this.id,
    required this.name,
    required this.whatsappNumber,
    this.isDefault = false,
    required this.createdAt,
  });

  Pharmacy copyWith({
    int? id,
    String? name,
    String? whatsappNumber,
    bool? isDefault,
  }) =>
      Pharmacy(
        id: id ?? this.id,
        name: name ?? this.name,
        whatsappNumber: whatsappNumber ?? this.whatsappNumber,
        isDefault: isDefault ?? this.isDefault,
        createdAt: createdAt,
      );

  /// Strips spaces, dashes and a leading "+" so the number can go into a
  /// wa.me link, which accepts digits only.
  static String sanitize(String raw) =>
      raw.replaceAll(RegExp(r'[^0-9]'), '');

  String get sanitizedNumber => sanitize(whatsappNumber);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'whatsapp_number': whatsappNumber,
        'is_default': isDefault ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory Pharmacy.fromMap(Map<String, Object?> m) => Pharmacy(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        whatsappNumber: (m['whatsapp_number'] as String?) ?? '',
        isDefault: ((m['is_default'] as int?) ?? 0) == 1,
        createdAt:
            DateTime.tryParse((m['created_at'] as String?) ?? '') ??
                DateTime.now(),
      );
}
