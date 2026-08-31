import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../components/atom/button_atom.dart';
import '../../components/atom/loading_atom.dart';
import '../../components/atom/textfield_atom.dart';
import '../../components/patient_avatar.dart';
import '../../helpers/date_helpers.dart';
import '../../helpers/validation_helpers.dart';
import '../../models/patient.dart';
import '../../providers/app_provider.dart';

/// Add, rename, reorder and remove the people whose medicines are tracked.
/// The dashboard tab row follows this list, including its order.
class PatientsScreen extends StatelessWidget {
  const PatientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final patients = provider.patients;

    return Scaffold(
      appBar: AppBar(title: const Text('Patients')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-add-patient',
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Patient'),
      ),
      body: patients.isEmpty
          ? EmptyState(
              icon: Icons.people_outline,
              title: 'No patients yet',
              message:
                  'Add the people you buy medicines for. Each one gets their '
                  'own tab on the dashboard.',
              actionLabel: 'Add patient',
              onAction: () => _openForm(context),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: patients.length,
              // onReorderItem already accounts for the removed item, so the
              // target index needs no adjusting.
              onReorderItem: (from, to) {
                final list = [...patients];
                list.insert(to, list.removeAt(from));
                provider.reorderPatients(list);
              },
              proxyDecorator: (child, _, _) => Material(
                color: Colors.transparent,
                child: child,
              ),
              itemBuilder: (context, index) {
                final patient = patients[index];
                return Padding(
                  key: ValueKey(patient.id),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PatientTile(
                    patient: patient,
                    provider: provider,
                    index: index,
                  ),
                );
              },
            ),
    );
  }

  static void _openForm(BuildContext context, {Patient? patient}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PatientFormSheet(patient: patient),
    );
  }
}

class _PatientTile extends StatelessWidget {
  const _PatientTile({
    required this.patient,
    required this.provider,
    required this.index,
  });

  final Patient patient;
  final AppProvider provider;

  /// Position in the reorderable list, needed by the drag handle.
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final id = patient.id;
    final medicineCount = id == null
        ? 0
        : provider.medicines
            .where((m) => m.assignments.any((a) => a.patientId == id))
            .length;
    final perDay = id == null ? 0.0 : provider.dailyTotal(patientId: id);

    return TappableCard(
      onTap: () => PatientsScreen._openForm(context, patient: patient),
      child: Row(
        children: [
          PatientAvatar(patient: patient, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.name,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (patient.relation != null &&
                        patient.relation!.trim().isNotEmpty)
                      patient.relation!.trim(),
                    '$medicineCount ${medicineCount == 1 ? 'medicine' : 'medicines'}',
                    if (perDay > 0) '${Dates.qty(perDay)} units / day',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove patient',
            onPressed: () => _confirmDelete(context, medicineCount),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.drag_handle, color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, int medicineCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${patient.name}?'),
        content: Text(
          medicineCount == 0
              ? 'Their tab disappears from the dashboard. No medicines are '
                  'affected.'
              : 'Their tab disappears and their dosage is removed from '
                  '$medicineCount ${medicineCount == 1 ? 'medicine' : 'medicines'}. '
                  'The medicines themselves and their stock are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(88, 44),
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || patient.id == null) return;
    await provider.deletePatient(patient.id!);
  }
}

/// Bottom sheet used for both adding and renaming a patient.
class _PatientFormSheet extends StatefulWidget {
  const _PatientFormSheet({this.patient});
  final Patient? patient;

  @override
  State<_PatientFormSheet> createState() => _PatientFormSheetState();
}

class _PatientFormSheetState extends State<_PatientFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _relation;
  bool _saving = false;

  bool get _isEdit => widget.patient != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.patient?.name ?? '');
    _relation = TextEditingController(text: widget.patient?.relation ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _relation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final provider = context.read<AppProvider>();
    final relation = _relation.text.trim();

    if (_isEdit) {
      await provider.updatePatient(
        widget.patient!.copyWith(
          name: _name.text.trim(),
          relation: relation.isEmpty ? null : relation,
          clearRelation: relation.isEmpty,
        ),
      );
    } else {
      await provider.addPatient(
        _name.text.trim(),
        relation: relation.isEmpty ? null : relation,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit ? 'Edit patient' : 'Add patient',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            AppTextField(
              controller: _name,
              label: 'Name',
              hint: 'Mom, Dad, Dada ji…',
              prefixIcon: Icons.person_outline,
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.words,
              validator: (v) => Validators.required(v, field: 'Name'),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _relation,
              label: 'Relation (optional)',
              hint: 'Mother, Father, Self…',
              prefixIcon: Icons.family_restroom_outlined,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
