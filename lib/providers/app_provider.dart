import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../helpers/date_helpers.dart';
import '../helpers/stock_math.dart';
import '../models/dose_assignment.dart';
import '../models/medicine.dart';
import '../models/medicine_event.dart';
import '../models/order.dart';
import '../models/patient.dart';
import '../models/pharmacy.dart';
import '../repositories/event_repository.dart';
import '../repositories/medicine_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/patient_repository.dart';
import '../repositories/pharmacy_repository.dart';
import '../services/backup_service.dart';
import '../services/image_service.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

/// Single source of truth for the UI.
///
/// The whole dataset is a family medicine cabinet — tens of rows, not
/// thousands — so it is held in memory and reloaded after each write. That
/// keeps every derived figure (per-patient totals, coverage, order drafts)
/// consistent without a stream/cache layer.
class AppProvider extends ChangeNotifier {
  AppProvider({
    PatientRepository? patients,
    MedicineRepository? medicines,
    OrderRepository? orders,
    PharmacyRepository? pharmacies,
    EventRepository? events,
  })  : _patientRepo = patients ?? PatientRepository(),
        _medicineRepo = medicines ?? MedicineRepository(),
        _orderRepo = orders ?? OrderRepository(),
        _pharmacyRepo = pharmacies ?? PharmacyRepository(),
        _eventRepo = events ?? EventRepository();

  final PatientRepository _patientRepo;
  final MedicineRepository _medicineRepo;
  final OrderRepository _orderRepo;
  final PharmacyRepository _pharmacyRepo;
  final EventRepository _eventRepo;

  bool _loading = true;
  bool get loading => _loading;

  /// Increments on every reload. Screens that read data the provider does not
  /// cache (the medicine history) use this to know when to re-query, instead
  /// of firing a query on every rebuild.
  int _dataVersion = 0;
  int get dataVersion => _dataVersion;

  List<Patient> _patients = [];
  List<Medicine> _medicines = [];
  List<Order> _orders = [];
  List<Pharmacy> _pharmacies = [];

  List<Patient> get patients => List.unmodifiable(_patients);
  List<Medicine> get medicines => List.unmodifiable(_medicines);
  List<Order> get orders => List.unmodifiable(_orders);
  List<Pharmacy> get pharmacies => List.unmodifiable(_pharmacies);

  String _search = '';
  String get search => _search;

  /// The day the currently displayed figures were computed for.
  DateTime _figuresFor = Dates.today();

  /// Test seam: pretends the visible figures were computed on [day].
  @visibleForTesting
  void debugSetFiguresDate(DateTime day) => _figuresFor = Dates.dayOf(day);

  /// Recomputes if the calendar day has rolled over since the last build.
  ///
  /// Everything in Medstock is derived from today's date, so an app left open
  /// overnight would otherwise keep showing yesterday's stock and coverage.
  /// Returns true when the date had in fact moved on.
  bool refreshIfDayChanged() {
    final today = Dates.today();
    if (today == _figuresFor) return false;

    _figuresFor = today;
    notifyListeners();
    // Reminder dates shift with the new day too.
    rescheduleReminders();
    return true;
  }

  // ---------------------------------------------------------------- loading

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    final results = await Future.wait([
      _patientRepo.all(),
      _medicineRepo.all(),
      _orderRepo.all(),
      _pharmacyRepo.all(),
    ]);

    _patients = results[0] as List<Patient>;
    _medicines = results[1] as List<Medicine>;
    _orders = results[2] as List<Order>;
    _pharmacies = results[3] as List<Pharmacy>;

    _loading = false;
    _dataVersion++;
    notifyListeners();
  }

  /// Reloads data and rebuilds the pending refill reminders. Called after any
  /// write that could change consumption or stock.
  Future<void> _refresh({bool reschedule = true}) async {
    _patients = await _patientRepo.all();
    _medicines = await _medicineRepo.all();
    _orders = await _orderRepo.all();
    _pharmacies = await _pharmacyRepo.all();
    _dataVersion++;
    notifyListeners();

    if (reschedule) {
      // Reminders are a side effect — never let a failure break a save.
      try {
        await NotificationService.instance.rescheduleAll(_medicines);
      } catch (e) {
        debugPrint('Medstock: reminder rescheduling failed — $e');
      }
    }
  }

  Future<void> rescheduleReminders() async {
    try {
      await NotificationService.instance.rescheduleAll(_medicines);
    } catch (e) {
      debugPrint('Medstock: reminder rescheduling failed — $e');
    }
  }

  // ----------------------------------------------------------------- search

  void setSearch(String value) {
    if (_search == value) return;
    _search = value;
    notifyListeners();
  }

  void clearSearch() => setSearch('');

  /// Matches the query against every text field on the medicine plus the
  /// names of the patients taking it. All terms must match (AND), so
  /// "mom dytor" narrows rather than widens.
  bool _matchesSearch(Medicine medicine) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;

    final patientNames = medicine.assignments
        .map((a) => patientById(a.patientId)?.name ?? '')
        .join(' ')
        .toLowerCase();

    final blob = '${medicine.searchBlob} $patientNames';
    return q
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .every(blob.contains);
  }

  // -------------------------------------------------------------- selectors

  Patient? patientById(int id) =>
      _patients.where((p) => p.id == id).firstOrNull;

  Medicine? medicineById(int id) =>
      _medicines.where((m) => m.id == id).firstOrNull;

  Order? orderById(int id) => _orders.where((o) => o.id == id).firstOrNull;

  Pharmacy? get defaultPharmacy =>
      _pharmacies.where((p) => p.isDefault).firstOrNull ??
      _pharmacies.firstOrNull;

  /// Medicines for the dashboard. [patientId] null means the "All" tab;
  /// otherwise only medicines that patient actually takes.
  ///
  /// Sorted so anything needing attention floats to the top.
  List<Medicine> medicinesFor(int? patientId) {
    final list = _medicines.where((m) {
      if (!_matchesSearch(m)) return false;
      if (patientId == null) return true;
      return m.assignments.any((a) => a.patientId == patientId);
    }).toList();

    // Rank each medicine once rather than recomputing its projection on
    // every comparison — the comparator runs O(n log n) times and each
    // status() call walks forward day by day.
    final ranked = [
      for (final m in list) (medicine: m, rank: _attentionRank(StockMath.status(m))),
    ];
    ranked.sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      return a.medicine.name
          .toLowerCase()
          .compareTo(b.medicine.name.toLowerCase());
    });

    return [for (final e in ranked) e.medicine];
  }

  int _attentionRank(StockStatus s) {
    switch (s.level) {
      case StockLevel.out:
        return 0;
      case StockLevel.low:
        return 1;
      case StockLevel.healthy:
        return 2;
      case StockLevel.untracked:
        return 3;
    }
  }

  /// Medicines that are out or low on stock, across everyone.
  List<Medicine> get needsAttention => _medicines
      .where((m) => StockMath.status(m).needsAttention)
      .toList();

  /// The medicine that will run out first, with its status. Null when nothing
  /// is being consumed.
  ///
  /// This replaces a per-day unit total on the dashboard: summing tablets and
  /// bottles into one "units per day" figure is arithmetically valid but
  /// tells nobody anything — a monthly eye-drop bottle reads as 0.03/day.
  (Medicine, StockStatus)? get soonestRunOut {
    (Medicine, StockStatus)? best;
    for (final medicine in _medicines) {
      final status = StockMath.status(medicine);
      final runOut = status.runOutDate;
      if (runOut == null) continue;
      if (best == null || runOut.isBefore(best.$2.runOutDate!)) {
        best = (medicine, status);
      }
    }
    return best;
  }

  /// Total units consumed per day, optionally for one patient.
  double dailyTotal({int? patientId}) => _medicines.fold<double>(0, (sum, m) {
        final assignments = patientId == null
            ? m.assignments
            : StockMath.forPatient(m, patientId);
        return sum + StockMath.perDay(assignments);
      });

  /// The newest-first history for one medicine. Read straight from the
  /// database rather than cached: it is only opened on the detail screen.
  Future<List<MedicineEvent>> eventsFor(int medicineId) =>
      _eventRepo.forMedicine(medicineId);

  // ------------------------------------------------------------- patients

  Future<Patient> addPatient(String name, {String? relation}) async {
    final created = await _patientRepo.insert(
      Patient(name: name.trim(), relation: relation, createdAt: DateTime.now()),
    );
    await _refresh(reschedule: false);
    return created;
  }

  Future<void> updatePatient(Patient patient) async {
    await _patientRepo.update(patient);
    await _refresh(reschedule: false);
  }

  /// Removes a patient. Their dose assignments cascade away, which lowers the
  /// consumption of any shared medicine — so reminders are rebuilt.
  Future<void> deletePatient(int id) async {
    await _patientRepo.delete(id);
    await _refresh();
  }

  Future<void> reorderPatients(List<Patient> ordered) async {
    await _patientRepo.reorder(ordered);
    await _refresh(reschedule: false);
  }

  // ------------------------------------------------------------- medicines

  Future<Medicine> addMedicine(Medicine medicine) async {
    final created = await _medicineRepo.insert(medicine);

    await _eventRepo.record(
      created.id!,
      MedicineEventType.created,
      qtyAfter: created.stockQty,
    );
    if (created.assignments.isNotEmpty) {
      await _eventRepo.record(
        created.id!,
        MedicineEventType.dosageChanged,
        note: _describeDosage(created),
      );
    }

    await _refresh();
    return created;
  }

  Future<Medicine> updateMedicine(Medicine medicine) async {
    final previous = medicineById(medicine.id!);
    final updated = await _medicineRepo.update(medicine);

    if (previous != null) await _logMedicineDiff(previous, updated);

    // Drop the old photo only once the new row is safely written.
    if (previous != null &&
        previous.imagePath != null &&
        previous.imagePath != medicine.imagePath) {
      await ImageService.instance.deleteIfOwned(previous.imagePath);
    }

    await _refresh();
    return updated;
  }

  /// Records what an edit actually changed, so the history reads as a story
  /// rather than a wall of "Details edited".
  Future<void> _logMedicineDiff(Medicine before, Medicine after) async {
    final id = after.id!;

    // Stock: the form re-baselines the snapshot, so compare what was
    // effectively in hand against what was entered.
    final wasInHand = StockMath.remainingToday(before);
    if ((after.stockQty - wasInHand).abs() > 0.0001) {
      await _eventRepo.record(
        id,
        MedicineEventType.stockRecounted,
        qtyBefore: wasInHand,
        qtyAfter: after.stockQty,
      );
    }

    if (before.unitPrice != after.unitPrice) {
      await _eventRepo.record(
        id,
        MedicineEventType.priceChanged,
        note: _describePriceChange(before, after),
      );
    }

    if (_dosageSignature(before) != _dosageSignature(after)) {
      await _eventRepo.record(
        id,
        MedicineEventType.dosageChanged,
        note: _describeDosage(after),
      );
    }

    // Anything else textual.
    final textChanged = before.name != after.name ||
        before.strength != after.strength ||
        before.type != after.type ||
        before.description != after.description ||
        before.notes != after.notes ||
        before.prescribedBy != after.prescribedBy ||
        before.manufacturer != after.manufacturer ||
        before.storage != after.storage ||
        before.expiryDate != after.expiryDate ||
        before.packSize != after.packSize ||
        before.lowStockDays != after.lowStockDays ||
        before.reminderEnabled != after.reminderEnabled ||
        before.imagePath != after.imagePath;
    if (textChanged) {
      await _eventRepo.record(id, MedicineEventType.detailsUpdated);
    }
  }

  String _describePriceChange(Medicine before, Medicine after) {
    String money(double? v) => v == null ? 'not set' : '₹${Dates.qty(v)}';
    final unit = after.type.unitSingular;
    return 'Price per $unit: ${money(before.unitPrice)} → '
        '${money(after.unitPrice)}';
  }

  /// A stable string for comparing dosage sets between two versions.
  String _dosageSignature(Medicine m) {
    final parts = m.assignments
        .map((a) => '${a.patientId}:${a.qtyPerIntake}:${a.intakesPerDay}:'
            '${a.scheduleType.name}:${(a.weekdays.toList()..sort()).join()}:'
            '${a.intervalDays}')
        .toList()
      ..sort();
    return parts.join('|');
  }

  /// "Mom 1/day · Dad 2/day", or a note that nobody is attached.
  String _describeDosage(Medicine m) {
    if (m.assignments.isEmpty) return 'No patient attached';
    final parts = m.assignments.map((a) {
      final name = patientById(a.patientId)?.name ?? 'Someone';
      return '$name ${a.doseHeadline(m.unitLabel)}';
    }).toList()
      ..sort();
    return parts.join(' · ');
  }

  Future<void> deleteMedicine(int id) async {
    final medicine = medicineById(id);
    await _medicineRepo.delete(id);
    await ImageService.instance.deleteIfOwned(medicine?.imagePath);
    await _refresh();
  }

  /// Replaces the stock snapshot with [qty] units as of today — a recount.
  Future<void> setStock(int medicineId, double qty) async {
    final medicine = medicineById(medicineId);
    final before =
        medicine == null ? null : StockMath.remainingToday(medicine);

    await _medicineRepo.setStock(medicineId, qty);
    await _eventRepo.record(
      medicineId,
      MedicineEventType.stockRecounted,
      qtyBefore: before,
      qtyAfter: qty < 0 ? 0 : qty,
    );
    await _refresh();
  }

  /// Adds [qty] units on top of what is actually left today.
  Future<void> addStock(int medicineId, double qty) async {
    final medicine = medicineById(medicineId);
    if (medicine == null) return;

    final current = StockMath.remainingToday(medicine);
    await _medicineRepo.setStock(medicineId, current + qty);
    await _eventRepo.record(
      medicineId,
      MedicineEventType.stockAdded,
      qtyDelta: qty,
      qtyBefore: current,
      qtyAfter: current + qty,
    );
    await _refresh();
  }

  /// Attaches or updates one patient's dosage without touching the rest.
  Future<void> upsertAssignment(
    int medicineId,
    DoseAssignment assignment,
  ) async {
    final medicine = medicineById(medicineId);
    if (medicine == null) return;

    final next = medicine.assignments
        .where((a) => a.patientId != assignment.patientId)
        .toList()
      ..add(assignment.copyWith(medicineId: medicineId));

    await updateMedicine(medicine.copyWith(assignments: next));
  }

  Future<void> removeAssignment(int medicineId, int patientId) async {
    final medicine = medicineById(medicineId);
    if (medicine == null) return;

    final next = medicine.assignments
        .where((a) => a.patientId != patientId)
        .toList();

    await updateMedicine(medicine.copyWith(assignments: next));
  }

  // ------------------------------------------------------------- pharmacies

  Future<void> addPharmacy(String name, String number) async {
    await _pharmacyRepo.insert(Pharmacy(
      name: name.trim(),
      whatsappNumber: Pharmacy.sanitize(number),
      createdAt: DateTime.now(),
    ));
    await _refresh(reschedule: false);
  }

  Future<void> updatePharmacy(Pharmacy pharmacy) async {
    await _pharmacyRepo.update(pharmacy);
    await _refresh(reschedule: false);
  }

  Future<void> deletePharmacy(int id) async {
    await _pharmacyRepo.delete(id);
    await _refresh(reschedule: false);
  }

  Future<void> makeDefaultPharmacy(int id) async {
    await _pharmacyRepo.makeDefault(id);
    await _refresh(reschedule: false);
  }

  // ----------------------------------------------------------------- orders

  /// Builds the draft for "everything I need to last through [targetDate]".
  ///
  /// Only medicines with a dosage attached can be projected; medicines with
  /// no assignment have no burn rate and are left out of the draft (they can
  /// still be added by hand during review).
  List<OrderItem> buildDraft(DateTime targetDate) {
    final items = <OrderItem>[];

    for (final medicine in _medicines) {
      if (medicine.assignments.isEmpty) continue;

      final qty = StockMath.orderQtyFor(medicine, targetDate);
      if (qty <= 0) continue;

      items.add(OrderItem(
        medicineId: medicine.id,
        medicineName: medicine.displayName,
        unitLabel: medicine.unitLabel,
        suggestedQty: qty,
        qty: qty,
        unitPrice: medicine.unitPrice,
      ));
    }

    items.sort((a, b) =>
        a.medicineName.toLowerCase().compareTo(b.medicineName.toLowerCase()));
    return items;
  }

  Future<Order> createOrder({
    required DateTime targetDate,
    required List<OrderItem> items,
    Pharmacy? pharmacy,
    String? notes,
  }) async {
    final created = await _orderRepo.insert(Order(
      targetDate: targetDate,
      status: OrderStatus.draft,
      pharmacyId: pharmacy?.id,
      pharmacyName: pharmacy?.name,
      notes: notes,
      createdAt: DateTime.now(),
      items: items.where((i) => i.qty > 0).toList(),
    ));
    await _refresh(reschedule: false);
    return created;
  }

  Future<Order> updateOrder(Order order) async {
    final updated = await _orderRepo.update(order);
    await _refresh(reschedule: false);
    return updated;
  }

  Future<void> markOrderStatus(Order order, OrderStatus status) async {
    await _orderRepo.updateStatusFields(
      order.copyWith(
        status: status,
        receivedAt: status == OrderStatus.received ? DateTime.now() : null,
      ),
    );
    await _refresh(reschedule: false);
  }

  /// Marks an order received and tops up stock with the quantities bought.
  ///
  /// This is what closes the loop: the projection that produced the order
  /// becomes the stock the projection now counts down from.
  Future<void> receiveOrder(Order order) async {
    for (final item in order.items) {
      final id = item.medicineId;
      if (id == null || item.qty <= 0) continue;
      final medicine = medicineById(id);
      if (medicine == null) continue;

      final current = StockMath.remainingToday(medicine);
      await _medicineRepo.setStock(id, current + item.qty);
      await _eventRepo.record(
        id,
        MedicineEventType.orderReceived,
        qtyDelta: item.qty,
        qtyBefore: current,
        qtyAfter: current + item.qty,
        note: 'Order for ${Dates.pretty(order.targetDate)}',
      );
    }

    await _orderRepo.updateStatusFields(
      order.copyWith(
        status: OrderStatus.received,
        receivedAt: DateTime.now(),
      ),
    );
    await _refresh();
  }

  Future<void> deleteOrder(int id) async {
    await _orderRepo.delete(id);
    await _refresh(reschedule: false);
  }

  // ---------------------------------------------------------------- backup

  /// Replaces the whole book with an imported backup, then reloads.
  Future<void> restoreBackup(BackupPreview preview) async {
    await BackupService.instance.restore(preview);
    await _refresh();
  }

  /// Wipes every row. Used by "clear all data" and before a fresh import.
  Future<void> clearEverything() async {
    await DatabaseService.instance.clearAll();
    await _refresh();
  }

  /// Convenience for the order form: today + one month is the usual cycle.
  DateTime get suggestedTargetDate {
    final today = Dates.today();
    return DateTime(today.year, today.month + 1, today.day);
  }
}
