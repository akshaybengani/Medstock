import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../components/atom/button_atom.dart';
import '../../constants.dart';
import '../../helpers/date_helpers.dart';
import '../../models/order.dart';
import '../../models/pharmacy.dart';
import '../../providers/app_provider.dart';
import '../../services/whatsapp_service.dart';
import '../pharmacy/pharmacies_screen.dart';

/// A created order: the line items, the WhatsApp message that will be sent,
/// and the actions that move it along.
class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final order = provider.orderById(orderId);

    if (order == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This order is no longer here.')),
      );
    }

    final message = WhatsappService.instance.formatOrder(
      order,
      header: WhatsappService.instance.defaultHeader(order),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete order',
            onPressed: () => _confirmDelete(context, provider, order),
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: () => _share(context, provider, order),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Send on WhatsApp'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _StatusCard(order: order, provider: provider),
          const SizedBox(height: 20),
          SectionLabel('${order.itemCount} '
              '${order.itemCount == 1 ? 'medicine' : 'medicines'}'),
          _ItemsCard(order: order),
          const SizedBox(height: 20),
          SectionLabel(
            'Message preview',
            trailing: IconButton(
              icon: const Icon(Icons.copy_outlined, size: 18),
              tooltip: 'Copy message',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: message));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Message copied')),
                );
              },
            ),
          ),
          _MessagePreview(message: message),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ share

  Future<void> _share(
    BuildContext context,
    AppProvider provider,
    Order order,
  ) async {
    Pharmacy? target = provider.defaultPharmacy;

    // More than one saved contact, or none: let the user decide where it goes.
    if (provider.pharmacies.length > 1 || provider.pharmacies.isEmpty) {
      final choice = await showModalBottomSheet<_ShareChoice>(
        context: context,
        builder: (_) => _ShareTargetSheet(pharmacies: provider.pharmacies),
      );
      if (choice == null || !context.mounted) return;

      if (choice.openContacts) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PharmaciesScreen()),
        );
        return;
      }
      target = choice.pharmacy;
    }

    final launched = await WhatsappService.instance.shareOrder(
      order,
      phoneNumber: target?.sanitizedNumber,
      header: WhatsappService.instance.defaultHeader(order),
    );

    if (!context.mounted) return;

    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp. Is it installed?'),
        ),
      );
      return;
    }

    // Handing the message off is the moment the order stops being a draft.
    if (order.status == OrderStatus.draft) {
      await provider.markOrderStatus(
        order.copyWith(
          pharmacyId: target?.id,
          pharmacyName: target?.name,
        ),
        OrderStatus.ordered,
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppProvider provider,
    Order order,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this order?'),
        content: const Text(
          'The order and its lines are removed. Medicine stock is not '
          'changed.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await provider.deleteOrder(order.id!);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.order, required this.provider});

  final Order order;
  final AppProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
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
                      Dates.pretty(order.targetDate),
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              PillTag(
                label: order.status.label,
                icon: order.status.icon,
                color: scheme.onSecondaryContainer,
                background: scheme.secondaryContainer,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            [
              'Created ${Dates.pretty(order.createdAt)}',
              if (order.pharmacyName != null) order.pharmacyName!,
              if (order.receivedAt != null)
                'Received ${Dates.pretty(order.receivedAt!)}',
            ].join(' · '),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (order.status != OrderStatus.received) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _confirmReceive(context),
              icon: const Icon(Icons.inventory_outlined, size: 18),
              label: const Text('Mark received & add to stock'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Receiving an order tops up every medicine on it, which is what keeps the
  /// stock book honest without any manual counting.
  Future<void> _confirmReceive(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Order received?'),
        content: Text(
          'The quantities on this order are added to what is currently left '
          'of each medicine, counted from today. '
          '${order.itemCount} ${order.itemCount == 1 ? 'medicine' : 'medicines'} '
          'will be topped up.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Add to stock'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await provider.receiveOrder(order);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stock updated')),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (var i = 0; i < order.items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 18,
                endIndent: 18,
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 14,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      order.items[i].medicineName,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        order.items[i].qtyLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                      if (order.items[i].lineCost != null)
                        Text(
                          Dates.money(order.items[i].lineCost!),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (order.estimatedCost != null) ...[
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estimated total',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (order.unpricedCount > 0)
                          Text(
                            'excludes ${order.unpricedCount} without a price',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '≈ ${Dates.money(order.estimatedCost!)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows the message exactly as it will arrive in the chat.
class _MessagePreview extends StatelessWidget {
  const _MessagePreview({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
    );
  }
}

/// Result of the share-target sheet.
class _ShareChoice {
  const _ShareChoice({this.pharmacy, this.openContacts = false});
  final Pharmacy? pharmacy;
  final bool openContacts;
}

class _ShareTargetSheet extends StatelessWidget {
  const _ShareTargetSheet({required this.pharmacies});
  final List<Pharmacy> pharmacies;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Send to',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          for (final pharmacy in pharmacies)
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(pharmacy.name),
              subtitle: Text(pharmacy.whatsappNumber),
              onTap: () => Navigator.of(context)
                  .pop(_ShareChoice(pharmacy: pharmacy)),
            ),
          ListTile(
            leading: const Icon(Icons.person_search_outlined),
            title: const Text('Pick a chat in WhatsApp'),
            subtitle: const Text('Opens WhatsApp with the message ready'),
            onTap: () => Navigator.of(context).pop(const _ShareChoice()),
          ),
          ListTile(
            leading: const Icon(Icons.add_business_outlined),
            title: const Text('Save a pharmacy contact'),
            onTap: () => Navigator.of(context)
                .pop(const _ShareChoice(openContacts: true)),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
