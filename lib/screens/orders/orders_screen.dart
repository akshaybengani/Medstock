import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../components/app_drawer.dart';
import '../../components/atom/button_atom.dart';
import '../../components/atom/loading_atom.dart';
import '../../constants.dart';
import '../../helpers/date_helpers.dart';
import '../../models/order.dart';
import '../../providers/app_provider.dart';
import '../pharmacy/pharmacies_screen.dart';
import 'order_detail_screen.dart';
import 'order_draft_screen.dart';

/// The order book: every past refill order, newest first.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final orders = provider.orders;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: 'Pharmacy contacts',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PharmaciesScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-new-order',
        onPressed: () => _startNewOrder(context, provider),
        icon: const Icon(Icons.add_shopping_cart_outlined),
        label: const Text('New order'),
      ),
      body: provider.loading
          ? const LoadingAtom()
          : orders.isEmpty
              ? EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No orders yet',
                  message:
                      'Pick the date you want your stock to last until and '
                      'Medstock works out how much of each medicine to buy.',
                  actionLabel: 'Create first order',
                  onAction: () => _startNewOrder(context, provider),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _OrderCard(
                    order: orders[index],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            OrderDetailScreen(orderId: orders[index].id!),
                      ),
                    ),
                  ),
                ),
    );
  }

  /// Asks for the target date, then opens the generated draft for review.
  static Future<void> _startNewOrder(
    BuildContext context,
    AppProvider provider,
  ) async {
    if (provider.medicines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a medicine first — there is nothing to order.'),
        ),
      );
      return;
    }

    final today = Dates.today();
    final picked = await showDatePicker(
      context: context,
      helpText: 'Stock should last until',
      initialDate: provider.suggestedTargetDate,
      firstDate: today.add(const Duration(days: 1)),
      lastDate: DateTime(today.year + 3),
    );

    if (picked == null || !context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDraftScreen(targetDate: Dates.dayOf(picked)),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (statusColor, statusBg) = switch (order.status) {
      OrderStatus.draft => (scheme.onSurfaceVariant, scheme.surfaceContainerHighest),
      OrderStatus.ordered => (scheme.onTertiaryContainer, scheme.tertiaryContainer),
      OrderStatus.received => (scheme.onPrimaryContainer, scheme.primaryContainer),
    };

    return TappableCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: scheme.onSecondaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Until ${Dates.pretty(order.targetDate)}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Created ${Dates.prettyShort(order.createdAt)}'
                      '${order.pharmacyName == null ? '' : ' · ${order.pharmacyName}'}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PillTag(
                label: order.status.label,
                icon: order.status.icon,
                dense: true,
                color: statusColor,
                background: statusBg,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.medication_outlined,
                  size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '${order.itemCount} ${order.itemCount == 1 ? 'medicine' : 'medicines'}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 14),
              Icon(Icons.numbers, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '${Dates.qty(order.totalUnits)} units',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (order.estimatedCost != null) ...[
                const SizedBox(width: 14),
                Icon(Icons.payments_outlined,
                    size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '≈ ${Dates.money(order.estimatedCost!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          if (order.items.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              order.items.take(3).map((i) => i.medicineName).join(', ') +
                  (order.itemCount > 3 ? ' +${order.itemCount - 3} more' : ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
