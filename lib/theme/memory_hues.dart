import 'package:flutter/material.dart';

/// Memory hues design tokens (§3.5). Light-first; no purple Material seed.
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
}
