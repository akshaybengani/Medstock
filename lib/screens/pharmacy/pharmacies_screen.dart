import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../components/atom/button_atom.dart';
import '../../components/atom/loading_atom.dart';
import '../../components/atom/textfield_atom.dart';
import '../../helpers/validation_helpers.dart';
import '../../models/pharmacy.dart';
import '../../providers/app_provider.dart';

/// Saved WhatsApp contacts for the shops you order from. Optional — orders
/// can always be shared through WhatsApp's own contact picker instead.
class PharmaciesScreen extends StatelessWidget {
  const PharmaciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final pharmacies = provider.pharmacies;

    return Scaffold(
      appBar: AppBar(title: const Text('Pharmacy contacts')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-add-pharmacy',
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Pharmacy'),
      ),
      body: pharmacies.isEmpty
          ? EmptyState(
              icon: Icons.storefront_outlined,
              title: 'No pharmacy saved',
              message:
                  'Save a WhatsApp number to send orders straight to your '
                  'shop. Without one, orders open WhatsApp so you can pick a '
                  'chat yourself.',
              actionLabel: 'Add pharmacy',
              onAction: () => _openForm(context),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: pharmacies.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _PharmacyTile(
                pharmacy: pharmacies[index],
                provider: provider,
              ),
            ),
    );
  }

  static void _openForm(BuildContext context, {Pharmacy? pharmacy}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PharmacyFormSheet(pharmacy: pharmacy),
    );
  }
}

class _PharmacyTile extends StatelessWidget {
  const _PharmacyTile({required this.pharmacy, required this.provider});

  final Pharmacy pharmacy;
  final AppProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return TappableCard(
      onTap: () => PharmaciesScreen._openForm(context, pharmacy: pharmacy),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.storefront_outlined,
              color: scheme.onSecondaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        pharmacy.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (pharmacy.isDefault) ...[
                      const SizedBox(width: 8),
                      const PillTag(label: 'Default', dense: true),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '+${pharmacy.sanitizedNumber}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case 'default':
                  await provider.makeDefaultPharmacy(pharmacy.id!);
                case 'delete':
                  await provider.deletePharmacy(pharmacy.id!);
              }
            },
            itemBuilder: (_) => [
              if (!pharmacy.isDefault)
                const PopupMenuItem(
                  value: 'default',
                  child: Text('Make default'),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PharmacyFormSheet extends StatefulWidget {
  const _PharmacyFormSheet({this.pharmacy});
  final Pharmacy? pharmacy;

  @override
  State<_PharmacyFormSheet> createState() => _PharmacyFormSheetState();
}

class _PharmacyFormSheetState extends State<_PharmacyFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _number;
  bool _saving = false;

  bool get _isEdit => widget.pharmacy != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.pharmacy?.name ?? '');
    _number =
        TextEditingController(text: widget.pharmacy?.whatsappNumber ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final provider = context.read<AppProvider>();

    if (_isEdit) {
      await provider.updatePharmacy(
        widget.pharmacy!.copyWith(
          name: _name.text.trim(),
          whatsappNumber: Pharmacy.sanitize(_number.text),
        ),
      );
    } else {
      await provider.addPharmacy(_name.text, _number.text);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
              _isEdit ? 'Edit pharmacy' : 'Add pharmacy',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            AppTextField(
              controller: _name,
              label: 'Pharmacy name',
              hint: 'Sharma Medicos',
              prefixIcon: Icons.storefront_outlined,
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.words,
              validator: (v) => Validators.required(v, field: 'Name'),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _number,
              label: 'WhatsApp number',
              hint: '919876543210',
              prefixIcon: Icons.chat_outlined,
              numericOnly: true,
              validator: Validators.whatsappNumber,
              helperText: 'Include the country code, without + or spaces',
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.info_outline, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Used to open the right WhatsApp chat with your order '
                    'already typed out.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
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
