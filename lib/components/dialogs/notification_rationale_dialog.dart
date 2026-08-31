import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../services/notification_service.dart';
import '../../services/settings_service.dart';

/// Explains what refill reminders do *before* Android's system prompt appears.
///
/// Asking cold on first launch gets denied by reflex, and on Android a denial
/// is close to permanent — the system stops showing the prompt. So the
/// explainer waits until the user has actually added a medicine, at which
/// point the feature has obvious value.
class NotificationRationaleDialog extends StatelessWidget {
  const NotificationRationaleDialog({super.key});

  /// Shows the explainer if it is still worth asking, and returns whether
  /// permission ended up granted.
  ///
  /// Skipped when permission is already granted, when the OS will no longer
  /// show its prompt, or when the user has said "not now".
  static Future<bool> maybeAsk(BuildContext context) async {
    final notifications = NotificationService.instance;

    if (await notifications.areNotificationsEnabled()) return true;
    if (await SettingsService.instance.readNotificationPromptDismissed()) {
      return false;
    }
    if (!context.mounted) return false;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NotificationRationaleDialog(),
    );

    if (proceed != true) {
      await SettingsService.instance.writeNotificationPromptDismissed(true);
      return false;
    }

    // Now hand over to the system prompt, which the user is expecting.
    return notifications.requestPermission();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AlertDialog(
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.notifications_active_outlined,
          color: scheme.onPrimaryContainer,
        ),
      ),
      title: const Text('Get told before you run out'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Medstock can work out the exact day each medicine runs out and '
            'remind you ${K.defaultLowStockDays} days beforehand, at '
            '${K.reminderHour} a.m.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          _Point(
            icon: Icons.wifi_off,
            text: 'Reminders are generated on this phone. Nothing is sent '
                'anywhere and there is no internet connection.',
          ),
          _Point(
            icon: Icons.lock_outline,
            text: 'Medicine names stay hidden on your lock screen until you '
                'unlock the phone.',
          ),
          _Point(
            icon: Icons.tune,
            text: 'You can switch reminders off per medicine, or change how '
                'many days of warning you want.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Allow reminders'),
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
