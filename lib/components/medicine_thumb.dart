import 'dart:io';

import 'package:flutter/material.dart';

import '../constants.dart';

/// Square thumbnail for a medicine — its photo when one was attached, or a
/// tinted icon for its type.
class MedicineThumb extends StatelessWidget {
  const MedicineThumb({
    super.key,
    required this.type,
    this.imagePath,
    this.size = 52,
    this.radius = 16,
  });

  final MedicineType type;
  final String? imagePath;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = BorderRadius.circular(radius);

    final path = imagePath;
    if (path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: border,
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          // A file can vanish (cleared cache, restored backup) — fall back
          // rather than throwing inside the list.
          errorBuilder: (context, _, _) => _placeholder(scheme, border),
        ),
      );
    }

    return _placeholder(scheme, border);
  }

  Widget _placeholder(ColorScheme scheme, BorderRadius border) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: border,
        ),
        child: Icon(
          type.icon,
          size: size * 0.46,
          color: scheme.onPrimaryContainer,
        ),
      );
}
