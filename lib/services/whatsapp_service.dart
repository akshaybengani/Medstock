import 'package:url_launcher/url_launcher.dart';

import '../helpers/date_helpers.dart';
import '../models/order.dart';

/// Formats an order as a plain-text message and hands it to WhatsApp.
class WhatsappService {
  WhatsappService._();
  static final WhatsappService instance = WhatsappService._();

  /// Builds the message body in the exact shape used when ordering:
  ///
  /// ```
  /// Lithosun SR 400mg
  /// 40 tablets
  ///
  /// Nexito 10mg
  /// 45 tablets
  /// ```
  ///
  /// Name on one line, quantity on the next, a blank line between items.
  String formatOrder(Order order, {String? header}) {
    final blocks = <String>[];

    if (header != null && header.trim().isNotEmpty) {
      blocks.add(header.trim());
    }

    for (final item in order.items) {
      if (item.qty <= 0) continue;
      blocks.add('${item.medicineName}\n${item.qtyLabel}');
    }

    final notes = order.notes;
    if (notes != null && notes.trim().isNotEmpty) {
      blocks.add(notes.trim());
    }

    return blocks.join('\n\n');
  }

  /// Opens WhatsApp with the message pre-filled.
  ///
  /// With a [phoneNumber] the chat opens directly; without one WhatsApp shows
  /// its own contact picker, so a pharmacy contact is optional.
  ///
  /// Returns false when no app could handle the link.
  Future<bool> shareOrder(
    Order order, {
    String? phoneNumber,
    String? header,
  }) async {
    final text = formatOrder(order, header: header);
    return shareText(text, phoneNumber: phoneNumber);
  }

  Future<bool> shareText(String text, {String? phoneNumber}) async {
    final digits = (phoneNumber ?? '').replaceAll(RegExp(r'[^0-9]'), '');

    // wa.me accepts digits only, with no leading "+".
    final uri = Uri.parse(
      digits.isEmpty
          ? 'https://wa.me/?text=${Uri.encodeComponent(text)}'
          : 'https://wa.me/$digits?text=${Uri.encodeComponent(text)}',
    );

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Default header, e.g. "Order for 1 Oct 2026".
  String defaultHeader(Order order) =>
      'Medicines needed till ${Dates.pretty(order.targetDate)}';
}
