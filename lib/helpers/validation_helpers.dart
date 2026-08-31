/// Form validators. Medstock deliberately validates very little: every field
/// except the medicine name is optional, so a validator's job is mostly to
/// reject nonsense rather than to demand input.
class Validators {
  Validators._();

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  /// Accepts an empty value, a whole number or a decimal — never negative.
  static String? optionalNumber(String? value, {String field = 'Value'}) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;

    final parsed = double.tryParse(raw);
    if (parsed == null) return '$field must be a number';
    if (parsed < 0) return '$field cannot be negative';
    return null;
  }

  static String? optionalInt(String? value, {String field = 'Value'}) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;

    final parsed = int.tryParse(raw);
    if (parsed == null) return '$field must be a whole number';
    if (parsed < 0) return '$field cannot be negative';
    return null;
  }

  /// A WhatsApp number needs the country code, so require a plausible length
  /// once the punctuation is stripped.
  static String? whatsappNumber(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 'Number is required';
    if (digits.length < 8) return 'Include the country code, e.g. 9198…';
    if (digits.length > 15) return 'That number looks too long';
    return null;
  }

  /// Parses a user-entered quantity, treating blank as zero.
  static double parseQty(String? value) =>
      double.tryParse((value ?? '').trim()) ?? 0;

  static int parseInt(String? value) =>
      int.tryParse((value ?? '').trim()) ?? 0;
}
