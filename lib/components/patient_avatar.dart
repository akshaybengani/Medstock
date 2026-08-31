import 'package:flutter/material.dart';

import '../models/patient.dart';
import '../theme/pallete.dart';

/// Circular initials avatar tinted with the patient's stable accent colour.
class PatientAvatar extends StatelessWidget {
  const PatientAvatar({
    super.key,
    required this.patient,
    this.size = 40,
  });

  final Patient patient;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = Pallete.accentFor(patient.colorIndex);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Text(
        patient.initials,
        style: TextStyle(
          color: accent,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
