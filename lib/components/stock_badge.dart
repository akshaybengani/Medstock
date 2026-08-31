import 'package:flutter/material.dart';

import '../helpers/stock_math.dart';
import '../theme/pallete.dart';
import 'atom/button_atom.dart';

/// Colour mapping for a stock level, shared by badges and progress bars.
class StockPalette {
  StockPalette._();

  static Color colorFor(StockLevel level, ColorScheme scheme) {
    switch (level) {
      case StockLevel.out:
        return Pallete.danger;
      case StockLevel.low:
        return Pallete.warning;
      case StockLevel.healthy:
        return Pallete.healthy;
      case StockLevel.untracked:
        return scheme.onSurfaceVariant;
    }
  }

  static IconData iconFor(StockLevel level) {
    switch (level) {
      case StockLevel.out:
        return Icons.error_outline;
      case StockLevel.low:
        return Icons.warning_amber_rounded;
      case StockLevel.healthy:
        return Icons.check_circle_outline;
      case StockLevel.untracked:
        return Icons.inventory_2_outlined;
    }
  }
}

/// "12 days left" pill, tinted by how urgent the situation is.
class StockBadge extends StatelessWidget {
  const StockBadge({super.key, required this.status, this.dense = false});

  final StockStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = StockPalette.colorFor(status.level, scheme);

    return PillTag(
      label: status.coverageLabel,
      icon: StockPalette.iconFor(status.level),
      color: color,
      background: color.withValues(alpha: 0.12),
      dense: dense,
    );
  }
}

/// Thin bar showing how much of the low-stock window is left. Full and green
/// when there is comfortable cover, short and red when nearly out.
class CoverageBar extends StatelessWidget {
  const CoverageBar({super.key, required this.status, required this.horizonDays});

  final StockStatus status;

  /// Days of cover treated as "a full bar".
  final int horizonDays;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = StockPalette.colorFor(status.level, scheme);

    final days = status.daysLeft ?? horizonDays;
    final fraction =
        horizonDays <= 0 ? 1.0 : (days / horizonDays).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: status.isTracked ? fraction : 1,
        minHeight: 6,
        backgroundColor: scheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation(
          status.isTracked ? color : scheme.outlineVariant,
        ),
      ),
    );
  }
}
