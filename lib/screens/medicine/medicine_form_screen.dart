import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../components/atom/button_atom.dart';
import '../../components/atom/textfield_atom.dart';
import '../../components/dialogs/notification_rationale_dialog.dart';
import '../../components/dose_editor.dart';
import '../../constants.dart';
import '../../helpers/date_helpers.dart';
import '../../helpers/stock_math.dart';
import '../../helpers/validation_helpers.dart';
import '../../models/dose_assignment.dart';
import '../../models/medicine.dart';
import '../../providers/app_provider.dart';
import '../../services/image_service.dart';
import '../patients/patients_screen.dart';

/// What the photo bottom sheet returned.
enum _PhotoAction { camera, gallery, remove }

/// Add or edit a medicine. Only the name is required — everything else is
/// optional, with the rarely-used fields folded into "Additional information".
class MedicineFormScreen extends StatefulWidget {
  const MedicineFormScreen({super.key, this.medicine});

  /// Null when adding.
  final Medicine? medicine;

  @override
  State<MedicineFormScreen> createState() => _MedicineFormScreenState();
}

class _MedicineFormScreenState extends State<MedicineFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _strength;
  late final TextEditingController _stock;
  late final TextEditingController _packSize;
  late final TextEditingController _lowStockDays;
  late final TextEditingController _description;
  late final TextEditingController _notes;
  late final TextEditingController _prescribedBy;
  late final TextEditingController _manufacturer;
  late final TextEditingController _storage;
  late final TextEditingController _packPrice;

  late MedicineType _type;
  DateTime? _expiryDate;
  bool _reminderEnabled = true;
  String? _imagePath;

  /// Working set of dosages, keyed by patient id.
  final Map<int, DoseAssignment> _doses = {};

  bool _showAdditional = false;
  bool _saving = false;

  bool get _isEdit => widget.medicine != null;

  @override
  void initState() {
    super.initState();
    final m = widget.medicine;

    _name = TextEditingController(text: m?.name ?? '');
    _strength = TextEditingController(text: m?.strength ?? '');
    _stock = TextEditingController(
      // Show what is actually left today, not the raw snapshot, so editing
      // an existing medicine starts from the truth.
      text: m == null ? '' : Dates.qty(StockMath.remainingToday(m)),
    );
    _packSize = TextEditingController(
      text: (m?.packSize ?? 0) > 0 ? '${m!.packSize}' : '',
    );
    _lowStockDays = TextEditingController(
      text: '${m?.lowStockDays ?? K.defaultLowStockDays}',
    );
    _description = TextEditingController(text: m?.description ?? '');
    _notes = TextEditingController(text: m?.notes ?? '');
    _prescribedBy = TextEditingController(text: m?.prescribedBy ?? '');
    _manufacturer = TextEditingController(text: m?.manufacturer ?? '');
    _storage = TextEditingController(text: m?.storage ?? '');
    _packPrice = TextEditingController(
      text: m?.packPrice == null ? '' : Dates.qty(m!.packPrice!),
    );

    _type = m?.type ?? MedicineType.tablet;
    _expiryDate = m?.expiryDate;
    _reminderEnabled = m?.reminderEnabled ?? true;
    _imagePath = m?.imagePath;

    for (final a in m?.assignments ?? const <DoseAssignment>[]) {
      _doses[a.patientId] = a;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _strength,
      _stock,
      _packSize,
      _lowStockDays,
      _description,
      _notes,
      _prescribedBy,
      _manufacturer,
      _storage,
      _packPrice,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ image

  Future<void> _pickImage() async {
    final choice = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(ctx).pop(_PhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(_PhotoAction.gallery),
            ),
            if (_imagePath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () => Navigator.of(ctx).pop(_PhotoAction.remove),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == _PhotoAction.remove) {
      setState(() => _imagePath = null);
      return;
    }

    try {
      final path = await ImageService.instance.pick(
        fromCamera: choice == _PhotoAction.camera,
      );
      if (path != null && mounted) setState(() => _imagePath = path);
    } catch (e) {
      if (!mounted) return;
      _toast('Could not attach the photo');
      debugPrint('Medstock: image pick failed — $e');
    }
  }

  // ------------------------------------------------------------------- save

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _showAdditional = true);
      return;
    }

    setState(() => _saving = true);
    final provider = context.read<AppProvider>();

    final stockQty = Validators.parseQty(_stock.text);
    final assignments = _doses.values.toList();

    final enteredLowStock = Validators.parseInt(_lowStockDays.text);
    final lowStockDays =
        enteredLowStock == 0 ? K.defaultLowStockDays : enteredLowStock;
    final packPrice = _packPrice.text.trim().isEmpty
        ? null
        : Validators.parseQty(_packPrice.text);

    String? trimmed(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    try {
      if (_isEdit) {
        final base = widget.medicine!;
        // Built field by field rather than via copyWith: copyWith treats a
        // null as "leave unchanged", which would silently keep an optional
        // field the user just cleared.
        await provider.updateMedicine(Medicine(
          id: base.id,
          name: _name.text.trim(),
          strength: trimmed(_strength),
          type: _type,
          imagePath: _imagePath,
          // Re-baseline the snapshot to today so the number just typed is
          // what "in stock right now" means from here on.
          stockQty: stockQty,
          stockAsOf: Dates.today(),
          packSize: Validators.parseInt(_packSize.text),
          lowStockDays: lowStockDays,
          reminderEnabled: _reminderEnabled,
          description: trimmed(_description),
          notes: trimmed(_notes),
          prescribedBy: trimmed(_prescribedBy),
          manufacturer: trimmed(_manufacturer),
          storage: trimmed(_storage),
          expiryDate: _expiryDate,
          packPrice: packPrice,
          createdAt: base.createdAt,
          updatedAt: DateTime.now(),
          assignments: assignments,
        ));
      } else {
        final now = DateTime.now();
        await provider.addMedicine(Medicine(
          name: _name.text.trim(),
          strength: trimmed(_strength),
          type: _type,
          imagePath: _imagePath,
          stockQty: stockQty,
          stockAsOf: Dates.today(),
          packSize: Validators.parseInt(_packSize.text),
          lowStockDays: lowStockDays,
          reminderEnabled: _reminderEnabled,
          description: trimmed(_description),
          notes: trimmed(_notes),
          prescribedBy: trimmed(_prescribedBy),
          manufacturer: trimmed(_manufacturer),
          storage: trimmed(_storage),
          expiryDate: _expiryDate,
          packPrice: packPrice,
          createdAt: now,
          updatedAt: now,
          assignments: assignments,
        ));
      }

      if (!mounted) return;

      // The medicine now exists, so reminders have obvious value — this is the
      // moment to explain them and ask. Never blocks the save.
      if (_reminderEnabled) {
        await NotificationRationaleDialog.maybeAsk(context);
        if (!mounted) return;
        await provider.rescheduleReminders();
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save this medicine');
      debugPrint('Medstock: save failed — $e');
    }
  }

  /// True when the user has typed a price, which is what makes pack size
  /// required rather than optional.
  bool get _pricingEntered => _packPrice.text.trim().isNotEmpty;

  String? _validatePackSize(String? value) {
    final base = Validators.optionalInt(value, field: 'Pack size');
    if (base != null) return base;

    if (!_pricingEntered) return null;

    final size = Validators.parseInt(value);
    if (size < 1) {
      return 'Needed to work out the price per '
          '${_type.unitSingular}';
    }
    return null;
  }

  /// Shows what one unit works out to, so "price per pack" is unambiguous.
  String? _perUnitHint() {
    if (!_pricingEntered) return 'used for order estimates';

    final price = Validators.parseQty(_packPrice.text);
    final size = Validators.parseInt(_packSize.text);
    if (price <= 0) return 'used for order estimates';
    if (size < 1) return 'set a pack size too';

    return '≈ ${Dates.money(price / size)} per ${_type.unitSingular}';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = context.watch<AppProvider>();
    final patients = provider.patients;

    final totalPerDay = _doses.values
        .fold<double>(0, (sum, a) => sum + a.avgPerDay);
    final totalHeadline =
        StockMath.headline(_doses.values.toList(), _type.unitPlural);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit medicine' : 'Add medicine'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_saving ? 'Saving…' : 'Save medicine'),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // ---------------------------------------------------- identity
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ImagePickerTile(
                  imagePath: _imagePath,
                  type: _type,
                  onTap: _pickImage,
                  onClear: _imagePath == null
                      ? null
                      : () => setState(() => _imagePath = null),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      AppTextField(
                        controller: _name,
                        label: 'Medicine name',
                        hint: 'Dytor, Lithosun SR…',
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            Validators.required(v, field: 'Medicine name'),
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: _strength,
                        label: 'Strength (optional)',
                        hint: '5mg, 400mg, SR…',
                        textCapitalization: TextCapitalization.none,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            DropdownButtonFormField<MedicineType>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final type in MedicineType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Row(
                      children: [
                        Icon(type.icon, size: 18),
                        const SizedBox(width: 10),
                        Text(type.label),
                      ],
                    ),
                  ),
              ],
              onChanged: (type) {
                if (type == null) return;
                setState(() => _type = type);
              },
            ),

            const SizedBox(height: 24),

            // ------------------------------------------------------- stock
            const SectionLabel('Current stock'),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _stock,
                    label: 'In stock now',
                    hint: '0',
                    numericOnly: true,
                    decimal: true,
                    prefixIcon: Icons.inventory_2_outlined,
                    helperText: _type.isContinuousUse
                        ? 'whole + part-used ${_type.unitPlural}'
                        : _type.unitPlural,
                    validator: (v) =>
                        Validators.optionalNumber(v, field: 'Stock'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    controller: _packSize,
                    label: _pricingEntered ? 'Pack size *' : 'Pack size',
                    hint: 'e.g. 10',
                    numericOnly: true,
                    prefixIcon: Icons.widgets_outlined,
                    helperText: _pricingEntered
                        ? '${_type.unitPlural} per pack'
                        : 'per strip / box',
                    onChanged: (_) => setState(() {}),
                    validator: _validatePackSize,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ---------------------------------------- patients and dosage
            SectionLabel(
              'Patients & dosage',
              trailing: totalPerDay > 0
                  ? PillTag(
                      label: 'Total $totalHeadline',
                      icon: Icons.functions,
                      dense: true,
                    )
                  : null,
            ),

            if (patients.isEmpty)
              _NoPatientsNotice(
                onAdd: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PatientsScreen()),
                ),
              )
            else
              Column(
                children: [
                  for (final patient in patients)
                    if (patient.id != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DoseEditor(
                          patient: patient,
                          assignment: _doses[patient.id!],
                          unitLabel: _type.unitPlural,
                          onToggle: (on) => setState(() {
                            if (on) {
                              _doses[patient.id!] = DoseAssignment(
                                patientId: patient.id!,
                                startDate: Dates.today(),
                                scheduleType: _type.defaultSchedule,
                                intervalDays: 30,
                              );
                            } else {
                              _doses.remove(patient.id!);
                            }
                          }),
                          onChanged: (updated) =>
                              setState(() => _doses[patient.id!] = updated),
                        ),
                      ),
                  if (_doses.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Without a dosage, Medstock tracks the medicine as '
                        'plain stock — it cannot project when it runs out or '
                        'add it to an order.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),

            const SizedBox(height: 20),

            // -------------------------------------- additional information
            _ExpandableSection(
              expanded: _showAdditional,
              onToggle: () =>
                  setState(() => _showAdditional = !_showAdditional),
              child: Column(
                children: [
                  AppTextField(
                    controller: _description,
                    label: 'What is it for',
                    hint: 'Blood pressure, thyroid…',
                    maxLines: 2,
                    prefixIcon: Icons.notes_outlined,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _prescribedBy,
                    label: 'Prescribed by',
                    hint: 'Dr. Sharma',
                    textCapitalization: TextCapitalization.words,
                    prefixIcon: Icons.medical_information_outlined,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _manufacturer,
                    label: 'Manufacturer / brand',
                    textCapitalization: TextCapitalization.words,
                    prefixIcon: Icons.business_outlined,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _storage,
                    label: 'Storage',
                    hint: 'Keep refrigerated…',
                    prefixIcon: Icons.thermostat_outlined,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _packPrice,
                          label: _type.isContinuousUse
                              ? 'Price per ${_type.unitSingular}'
                              : 'Price per strip / pack',
                          numericOnly: true,
                          decimal: true,
                          prefixIcon: Icons.currency_rupee,
                          helperText: _perUnitHint(),
                          onChanged: (_) => setState(() {}),
                          validator: (v) =>
                              Validators.optionalNumber(v, field: 'Price'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DatePickerField(
                          label: 'Expiry date',
                          value: _expiryDate,
                          onChanged: (d) => setState(() => _expiryDate = d),
                          onClear: () => setState(() => _expiryDate = null),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _notes,
                    label: 'Notes',
                    hint: 'Anything else worth remembering',
                    maxLines: 3,
                    prefixIcon: Icons.sticky_note_2_outlined,
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('Refill reminder'),
                  AppTextField(
                    controller: _lowStockDays,
                    label: 'Warn me this many days before running out',
                    numericOnly: true,
                    prefixIcon: Icons.notifications_active_outlined,
                    validator: (v) =>
                        Validators.optionalInt(v, field: 'Days'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _reminderEnabled,
                    onChanged: (v) => setState(() => _reminderEnabled = v),
                    title: const Text('Notify me before this runs out'),
                    subtitle: const Text('A reminder at 9 a.m. on the day'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Square photo tile that doubles as the picker button.
class _ImagePickerTile extends StatelessWidget {
  const _ImagePickerTile({
    required this.imagePath,
    required this.type,
    required this.onTap,
    this.onClear,
  });

  final String? imagePath;
  final MedicineType type;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = imagePath != null && File(imagePath!).existsSync();

    return SizedBox(
      width: 104,
      height: 132,
      child: Stack(
        children: [
          Positioned.fill(
            child: Material(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: hasImage
                    ? Image.file(File(imagePath!), fit: BoxFit.cover)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            size: 26,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add photo',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          if (hasImage && onClear != null)
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onClear,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tap-to-open date field with a clear affordance.
class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(K.fieldRadius),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 20),
        );
        if (picked != null) onChanged(Dates.dayOf(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_outlined, size: 20),
          suffixIcon: value == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClear,
                ),
        ),
        child: Text(
          value == null ? '—' : Dates.prettyShort(value!),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

/// The collapsible "Additional information" block.
class _ExpandableSection extends StatelessWidget {
  const _ExpandableSection({
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Material rather than a decorated Container: the section contains a
    // SwitchListTile whose ink splash needs a Material ancestor to paint on.
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Row(
                children: [
                  Icon(Icons.tune, size: 20, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Additional information',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    'optional',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _NoPatientsNotice extends StatelessWidget {
  const _NoPatientsNotice({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No patients yet',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Add the people you buy for to record who takes this and how '
            'much. You can also save the medicine now and attach them later.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Add patients'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ),
    );
  }
}
