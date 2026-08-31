import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../components/atom/textfield_atom.dart';
import '../../helpers/date_helpers.dart';
import '../../helpers/stock_math.dart';
import '../../helpers/validation_helpers.dart';
import '../../models/medicine.dart';
import '../../providers/app_provider.dart';

enum StockSheetMode {
  /// Bought more — add on top of what is left.
  add,

  /// Counted the box — replace the figure entirely.
  count,
}

/// Corrects a medicine's stock.
///
/// Both paths re-baseline the snapshot to today, which is what makes the
/// entered number authoritative from this moment forward.
class StockSheet extends StatefulWidget {
  const StockSheet({super.key, required this.medicine, required this.mode});

  final Medicine medicine;
  final StockSheetMode mode;

  static Future<void> show(
    BuildContext context, {
    required Medicine medicine,
    required StockSheetMode mode,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => StockSheet(medicine: medicine, mode: mode),
      );

  @override
  State<StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends State<StockSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _qty;
  bool _saving = false;

  bool get _isAdd => widget.mode == StockSheetMode.add;

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(
      text: _isAdd
          ? ''
          : Dates.qty(StockMath.remainingToday(widget.medicine)),
    );
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final value = Validators.parseQty(_qty.text);
    setState(() => _saving = true);

    final provider = context.read<AppProvider>();
    final id = widget.medicine.id!;

    if (_isAdd) {
      await provider.addStock(id, value);
    } else {
      await provider.setStock(id, value);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final current = StockMath.remainingToday(widget.medicine);
    final unit = widget.medicine.unitLabel;

    // Live preview of the resulting figure.
    final entered = Validators.parseQty(_qty.text);
    final resulting = _isAdd ? current + entered : entered;

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
              _isAdd ? 'Add stock' : 'Recount stock',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _isAdd
                  ? 'How many $unit did you buy? They are added to the '
                      '${Dates.qty(current)} already counted.'
                  : 'Counted the box? Enter what is actually there and '
                      'Medstock will count down from today.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            AppTextField(
              controller: _qty,
              label: _isAdd ? 'Units bought' : 'Units in hand',
              numericOnly: true,
              decimal: true,
              autofocus: true,
              prefixIcon: Icons.inventory_2_outlined,
              helperText: unit,
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final base = Validators.optionalNumber(v, field: 'Quantity');
                if (base != null) return base;
                if (Validators.parseQty(v) <= 0 && _isAdd) {
                  return 'Enter how many you bought';
                }
                return null;
              },
            ),
            if (entered > 0 || !_isAdd) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.arrow_forward, size: 16, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Stock becomes '
                        '${Dates.qtyWithUnit(resulting, unit)} as of today',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
