import 'package:intl/intl.dart';

/// Date utilities. Medstock reasons in whole *local* days — every date that
/// reaches the database or the projection engine is normalised to midnight so
/// that day arithmetic can never be thrown off by a time component or DST.
class Dates {
  Dates._();

  static final DateFormat _iso = DateFormat('yyyy-MM-dd');
  static final DateFormat _pretty = DateFormat('d MMM yyyy');
  static final DateFormat _prettyShort = DateFormat('d MMM');
  static final DateFormat _withDay = DateFormat('EEE, d MMM yyyy');

  /// Strips the time component, returning local midnight of the same day.
  static DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime today() => dayOf(DateTime.now());

  static String toIso(DateTime d) => _iso.format(dayOf(d));

  static DateTime? fromIso(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return dayOf(DateTime.parse(s));
    } catch (_) {
      return null;
    }
  }

  static String pretty(DateTime d) => _pretty.format(d);
  static String prettyShort(DateTime d) => _prettyShort.format(d);
  static String withWeekday(DateTime d) => _withDay.format(d);

  /// Whole days from [from] to [to] (`to - from`). Computed on normalised
  /// dates via UTC so a DST shift can't produce 23- or 25-hour "days".
  static int daysBetween(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  /// A human phrase for a forward-looking day count.
  static String relativeDays(int days) {
    if (days <= 0) return 'today';
    if (days == 1) return 'tomorrow';
    if (days < 30) return 'in $days days';
    final months = (days / 30).floor();
    if (months < 12) return 'in $months ${months == 1 ? 'month' : 'months'}';
    final years = (days / 365).floor();
    return 'in $years ${years == 1 ? 'year' : 'years'}';
  }

  /// "₹1,240" / "₹58.50" — no decimals when the amount is whole.
  static String money(num amount) {
    final d = amount.toDouble();
    final whole = d == d.roundToDouble();
    final f = NumberFormat(whole ? '#,##0' : '#,##0.00', 'en_IN');
    return '₹${f.format(d)}';
  }

  /// "1 tablet" but "3 tablets" and "0.5 tablets" — only an exact 1 takes
  /// the singular. [plural] is the unit's plural form, e.g. "bottles".
  static String unit(String plural, num quantity) {
    if (quantity != 1) return plural;
    return plural.endsWith('s')
        ? plural.substring(0, plural.length - 1)
        : plural;
  }

  /// A quantity and its correctly-pluralised unit, e.g. "1 bottle".
  static String qtyWithUnit(num quantity, String plural) =>
      '${qty(quantity)} ${unit(plural, quantity)}';

  /// Formats a quantity without a trailing `.0` for whole numbers, since
  /// stock is usually counted in whole tablets but may be halved.
  static String qty(num value) {
    final d = value.toDouble();
    if (d == d.roundToDouble()) return d.round().toString();
    // Trim padding zeros, then any bare decimal point left behind.
    return d
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
