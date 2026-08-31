import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../components/atom/button_atom.dart';
import '../../components/atom/loading_atom.dart';
import '../../components/atom/textfield_atom.dart';
import '../../helpers/date_helpers.dart';
import '../../helpers/stock_math.dart';
import '../../helpers/validation_helpers.dart';
import '../../models/medicine.dart';
import '../../models/order.dart';
import '../../providers/app_provider.dart';
import 'order_detail_screen.dart';

/// Review step for a new order.
///
/// The quantities arrive pre-computed from the projection ("how much do I
/// burn between today and the target date, minus what I already have") and
/// stay editable — the projection is a starting point, not a verdict.
class OrderDraftScreen extends StatefulWidget {
  const OrderDraftScreen({super.key, required this.targetDate});

  final DateTime targetDate;

  @override
  State<OrderDraftScreen> createState() => _OrderDraftScreenState();
}

class _OrderDraftScreenState extends State<OrderDraftScreen> {
  late List<OrderItem> _items;
  final TextEditingController _notes = TextEditingController();
  bool _creating = false;
  bool _initialised = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Build the draft once; later provider notifications must not wipe the
    // user's manual edits.
    if (_initialised) return;
    _items = context.read<AppProvider>().buildDraft(widget.targetDate);
    _initialised = true;
  }

  int get _daysAhead =>
      Dates.daysBetween(Dates.today(), widget.targetDate) + 1;

  double get _totalUnits =>
      _items.fold<double>(0, (sum, i) => sum + i.qty);

  /// Estimated spend across the lines that carry a price.
  double? get _estimatedCost {
    var total = 0.0;
    var any = false;
    for (final item in _items) {
      final cost = item.lineCost;
      if (cost == null) continue;
      total += cost;
      any = true;
    }
    return any ? total : null;
  }

  int get _unpricedCount => _items.where((i) => i.unitPrice == null).length;

  Future<void> _create() async {
    final kept = _items.where((i) => i.qty > 0).toList();
    if (kept.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to order — every quantity is 0.')),
      );
      return;
    }

    setState(() => _creating = true);
    final provider = context.read<AppProvider>();

    final order = await provider.createOrder(
      targetDate: widget.targetDate,
      items: kept,
      pharmacy: provider.defaultPharmacy,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );

    if (!mounted) return;
    // Replace so Back from the detail page lands on the order list.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(orderId: order.id!),
      ),
    );
  }

  Future<void> _addManually() async {
    final provider = context.read<AppProvider>();
    final alreadyIn = _items.map((i) => i.medicineId).toSet();
    final available = provider.medicines
        .where((m) => !alreadyIn.contains(m.id))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Every medicine is already on this order.')),
      );
      return;
    }

    final picked = await showModalBottomSheet<Medicine>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _MedicinePickerSheet(medicines: available),
    );

    if (picked == null || !mounted) return;

    setState(() {
      final suggested = StockMath.orderQtyFor(picked, widget.targetDate);
      _items = [
        ..._items,
        OrderItem(
          medicineId: picked.id,
          medicineName: picked.displayName,
          unitLabel: picked.unitLabel,
          suggestedQty: suggested,
          qty: suggested > 0 ? suggested : 1,
          unitPrice: picked.unitPrice,
        ),
      ]..sort((a, b) => a.medicineName
          .toLowerCase()
          .compareTo(b.medicineName.toLowerCase()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review order'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add a medicine',
            onPressed: _addManually,
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _creating ? null : _create,
            icon: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_creating ? 'Creating…' : 'Create order'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _DraftSummary(
            targetDate: widget.targetDate,
            daysAhead: _daysAhead,
            itemCount: _items.where((i) => i.qty > 0).length,
            totalUnits: _totalUnits,
            estimatedCost: _estimatedCost,
            unpricedCount: _unpricedCount,
          ),
          const SizedBox(height: 20),
          const SectionLabel('What to buy'),
          if (_items.isEmpty)
            EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Nothing needed yet',
              message:
                  'Current stock already covers everything through '
                  '${Dates.pretty(widget.targetDate)}. Pick a later date, or '
                  'add a medicine by hand.',
              actionLabel: 'Add a medicine',
              onAction: _addManually,
            )
          else
            Column(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _DraftItemRow(
                      // Keyed by the medicine so removing a line does not
                      // leave the next row holding the old row's controller.
                      key: ValueKey(
                        _items[i].medicineId ?? _items[i].medicineName,
                      ),
                      item: _items[i],
                      onQtyChanged: (qty) => setState(() {
                        _items = [..._items];
                        _items[i] = _items[i].copyWith(qty: qty);
                      }),
                      onRemove: () => setState(() {
                        _items = [..._items]..removeAt(i);
                      }),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _notes,
            label: 'Note for the pharmacy (optional)',
            hint: 'Please deliver by evening',
            maxLines: 2,
            prefixIcon: Icons.chat_bubble_outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Quantities cover every dose from today through '
            '${Dates.pretty(widget.targetDate)}, minus what is already in '
            'stock, rounded up to whole packs where a pack size is set.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DraftSummary extends StatelessWidget {
  const _DraftSummary({
    required this.targetDate,
    required this.daysAhead,
    required this.itemCount,
    required this.totalUnits,
    required this.estimatedCost,
    required this.unpricedCount,
  });

  final DateTime targetDate;
  final int daysAhead;
  final int itemCount;
  final double totalUnits;
  final double? estimatedCost;
  final int unpricedCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stock to last until',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            Dates.withWeekday(targetDate),
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PillTag(
                label: '$daysAhead days of cover',
                icon: Icons.calendar_month_outlined,
                dense: true,
              ),
              PillTag(
                label: '$itemCount ${itemCount == 1 ? 'medicine' : 'medicines'}',
                icon: Icons.medication_outlined,
                dense: true,
              ),
              PillTag(
                label: '${Dates.qty(totalUnits)} units',
                icon: Icons.numbers,
                dense: true,
              ),
              if (estimatedCost != null)
                PillTag(
                  label: '≈ ${Dates.money(estimatedCost!)}',
                  icon: Icons.payments_outlined,
                  dense: true,
                  color: scheme.onTertiaryContainer,
                  background: scheme.tertiaryContainer,
                ),
            ],
          ),
          if (estimatedCost != null && unpricedCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Estimate excludes $unpricedCount '
              '${unpricedCount == 1 ? 'medicine' : 'medicines'} with no price '
              'recorded.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// One editable draft line.
class _DraftItemRow extends StatefulWidget {
  const _DraftItemRow({
    super.key,
    required this.item,
    required this.onQtyChanged,
    required this.onRemove,
  });

  final OrderItem item;
  final ValueChanged<double> onQtyChanged;
  final VoidCallback onRemove;

  @override
  State<_DraftItemRow> createState() => _DraftItemRowState();
}

class _DraftItemRowState extends State<_DraftItemRow> {
  late final TextEditingController _qty;

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(text: Dates.qty(widget.item.qty));
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final edited = widget.item.qty != widget.item.suggestedQty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.medicineName,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (edited)
                      'suggested ${Dates.qty(widget.item.suggestedQty)} ${widget.item.unitLabel}'
                    else
                      widget.item.unitLabel,
                    if (widget.item.lineCost != null)
                      '≈ ${Dates.money(widget.item.lineCost!)}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 78,
            child: TextField(
              controller: _qty,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              ),
              onChanged: (v) => widget.onQtyChanged(Validators.parseQty(v)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove from order',
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}

/// Picker for adding a medicine the projection did not include.
class _MedicinePickerSheet extends StatelessWidget {
  const _MedicinePickerSheet({required this.medicines});
  final List<Medicine> medicines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Add a medicine',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: medicines.length,
              itemBuilder: (context, index) {
                final m = medicines[index];
                return ListTile(
                  leading: Icon(m.type.icon),
                  title: Text(m.displayName),
                  subtitle: Text(
                    '${Dates.qtyWithUnit(StockMath.remainingToday(m), m.unitLabel)} in stock',
                  ),
                  onTap: () => Navigator.of(context).pop(m),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
