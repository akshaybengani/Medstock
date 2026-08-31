import 'package:flutter/material.dart';

/// Colour palette for Medstock. A single seed drives the Material 3 scheme;
/// the accent list is used to give each patient a stable identity colour.
class Pallete {
  Pallete._();

  /// Seed for the Material 3 colour scheme — a calm medical teal.
  static const Color seed = Color(0xFF00696D);

  /// Semantic colours for stock health.
  static const Color danger = Color(0xFFB3261E);
  static const Color warning = Color(0xFFB26A00);
  static const Color healthy = Color(0xFF1B6B3A);

  /// Stable per-patient accent colours, indexed by `Patient.colorIndex`.
  static const List<Color> patientAccents = [
    Color(0xFF00696D), // teal
    Color(0xFF6750A4), // violet
    Color(0xFFA13F6B), // rose
    Color(0xFF1F6B4A), // green
    Color(0xFF8A5000), // amber
    Color(0xFF3F5DA1), // indigo
    Color(0xFF7A4E2D), // brown
    Color(0xFF4A6572), // slate
  ];

  static Color accentFor(int index) =>
      patientAccents[index.abs() % patientAccents.length];
}
