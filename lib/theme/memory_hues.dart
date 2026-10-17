import 'package:flutter/material.dart';

/// Memory hues design tokens (§3.5). Light-first surfaces; dark capture field.
///
/// Capture home + camera share [atmosphere] — calm ink with a soft teal drift.
/// No carnival amber/coral ribbons; accents stay muted ([accent], [recall]).
abstract final class MemoryHues {
  static const Color paper = Color(0xFFF1F0EC);
  static const Color paperElevated = Color(0xFFFAFAF7);
  static const Color ink = Color(0xFF1B2A4A);
  static const Color inkMuted = Color(0xFF5A6B86);
  static const Color rule = Color(0xFFD4D2CB);
  static const Color accent = Color(0xFF2A6B66);
  static const Color accentSoft = Color(0xFFD5E8E6);
  static const Color recall = Color(0xFFC4923A);
  static const Color recallSoft = Color(0xFFF3E6CC);
  static const Color confidence = Color(0xFFA67C2D);
  static const Color danger = Color(0xFF8B3A3A);
  static const Color overlayScrim = Color(0x6B1B2A4A); // ~42% navy
  static const Color focusRing = accent;

  // ── Shared capture / camera atmosphere (low-contrast ink family) ─────────
  static const Color fieldDeep = Color(0xFF121A28);
  static const Color field = ink; // #1B2A4A
  static const Color fieldTeal = Color(0xFF1A3040);
  static const Color fieldLift = Color(0xFF24344A);

  /// Gentle multi-stop wash for home + camera letterbox. Same family throughout.
  static const LinearGradient atmosphere = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      fieldDeep,
      field,
      fieldTeal,
      fieldLift,
    ],
    stops: [0.0, 0.38, 0.72, 1.0],
  );

  static const BoxDecoration atmosphereDecoration = BoxDecoration(
    gradient: atmosphere,
  );
}
