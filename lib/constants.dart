import 'package:flutter/material.dart';

/// App-wide constants for Medstock.
class K {
  K._();

  static const String appName = 'Medstock';
  static const String dbName = 'medstock.db';
  static const int dbVersion = 2;

  /// Hour of day (24h) used for refill reminder notifications.
  static const int reminderHour = 9;

  /// Default number of days of remaining stock at which we warn.
  static const int defaultLowStockDays = 7;

  static const double cardRadius = 20;
  static const double fieldRadius = 16;
  static const double sheetRadius = 28;
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: 16);
}

/// The physical form of a medicine. Drives the unit label shown in the UI
/// and in the WhatsApp order message.
enum MedicineType {
  tablet('Tablet', 'tablets', Icons.medication_outlined),
  capsule('Capsule', 'capsules', Icons.medication_liquid_outlined),
  pill('Pill', 'pills', Icons.local_pharmacy_outlined),
  syrup('Syrup', 'bottles', Icons.liquor_outlined),
  drops('Drops', 'bottles', Icons.water_drop_outlined),
  injection('Injection', 'vials', Icons.vaccines_outlined),
  inhaler('Inhaler', 'inhalers', Icons.air_outlined),
  cream('Cream / Ointment', 'tubes', Icons.sanitizer_outlined),
  powder('Powder / Sachet', 'sachets', Icons.grain_outlined),
  patch('Patch', 'patches', Icons.healing_outlined),
  other('Other', 'units', Icons.category_outlined);

  const MedicineType(this.label, this.unitPlural, this.icon);

  final String label;
  final String unitPlural;
  final IconData icon;

  static MedicineType fromName(String? name) => MedicineType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => MedicineType.tablet,
      );

  /// True for forms you use gradually out of one container rather than
  /// counting out individual doses. These default to
  /// [ScheduleType.perDuration] on the dosage editor.
  bool get isContinuousUse => const {
        MedicineType.syrup,
        MedicineType.drops,
        MedicineType.inhaler,
        MedicineType.cream,
        MedicineType.patch,
      }.contains(this);

  /// Sensible starting schedule when a patient is attached to this medicine.
  ScheduleType get defaultSchedule =>
      isContinuousUse ? ScheduleType.perDuration : ScheduleType.daily;

  /// Singular unit noun, e.g. "bottles" -> "bottle".
  String get unitSingular => unitPlural.endsWith('s')
      ? unitPlural.substring(0, unitPlural.length - 1)
      : unitPlural;
}

/// How often a dose recurs.
enum ScheduleType {
  daily('Every day'),
  weekdays('Specific days'),
  interval('Every N days'),

  /// For things you can't count per dose — eye drops, syrups, inhalers,
  /// creams. You record how long one unit lasts and Medstock burns it down
  /// continuously, so a bottle half way through its month reads as half full.
  perDuration('One unit lasts N days');

  const ScheduleType(this.label);
  final String label;

  static ScheduleType fromName(String? name) => ScheduleType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => ScheduleType.daily,
      );
}

enum OrderStatus {
  draft('Draft', Icons.edit_note_outlined),
  ordered('Ordered', Icons.send_outlined),
  received('Received', Icons.check_circle_outline);

  const OrderStatus(this.label, this.icon);
  final String label;
  final IconData icon;

  static OrderStatus fromName(String? name) => OrderStatus.values.firstWhere(
        (t) => t.name == name,
        orElse: () => OrderStatus.draft,
      );
}

/// A recorded change to a medicine. The log is append-only and read-only in
/// the UI — it answers "when did I last touch this?".
enum MedicineEventType {
  created('Added to the book', Icons.add_circle_outline),
  stockAdded('Stock added', Icons.add_shopping_cart_outlined),
  stockRecounted('Recounted', Icons.fact_check_outlined),
  orderReceived('Order received', Icons.local_shipping_outlined),
  priceChanged('Price changed', Icons.currency_rupee),
  dosageChanged('Dosage changed', Icons.people_outline),
  detailsUpdated('Details edited', Icons.edit_outlined),
  imported('Imported', Icons.download_outlined);

  const MedicineEventType(this.label, this.icon);

  final String label;
  final IconData icon;

  static MedicineEventType fromName(String? name) =>
      MedicineEventType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => MedicineEventType.detailsUpdated,
      );
}

const List<String> kWeekdayShort = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];
