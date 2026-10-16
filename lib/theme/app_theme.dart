import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'memory_hues.dart';

/// ThemeData for hue-memory. ColorScheme is locked — never ColorScheme.fromSeed.
abstract final class AppTheme {
  static ThemeData light() {
    final colorScheme = const ColorScheme.light(
      surface: MemoryHues.paper,
      onSurface: MemoryHues.ink,
      primary: MemoryHues.accent,
      onPrimary: MemoryHues.paperElevated,
      secondary: MemoryHues.recall,
      onSecondary: MemoryHues.ink,
      tertiary: MemoryHues.inkMuted,
      onTertiary: MemoryHues.paperElevated,
      error: MemoryHues.danger,
      onError: MemoryHues.paperElevated,
      outline: MemoryHues.rule,
      surfaceContainerHighest: MemoryHues.paperElevated,
    );

    final plex = GoogleFonts.ibmPlexSansTextTheme();
    final fraunces = GoogleFonts.frauncesTextTheme();
    final plexMono = GoogleFonts.ibmPlexMonoTextTheme();

    final textTheme = plex.copyWith(
      displayLarge: fraunces.displayLarge?.copyWith(
        color: MemoryHues.ink,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
      ),
      displayMedium: fraunces.displayMedium?.copyWith(
        color: MemoryHues.ink,
        fontWeight: FontWeight.w500,
      ),
      headlineLarge: fraunces.headlineLarge?.copyWith(
        color: MemoryHues.ink,
        fontSize: 32,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.4,
      ),
      headlineMedium: fraunces.headlineMedium?.copyWith(
        color: MemoryHues.ink,
        fontSize: 28,
        fontWeight: FontWeight.w500,
      ),
      titleLarge: plex.titleLarge?.copyWith(
        color: MemoryHues.ink,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: plex.bodyLarge?.copyWith(
        color: MemoryHues.ink,
        fontSize: 16,
        height: 1.45,
      ),
      bodyMedium: plex.bodyMedium?.copyWith(
        color: MemoryHues.ink,
        fontSize: 14,
        height: 1.4,
      ),
      bodySmall: plex.bodySmall?.copyWith(
        color: MemoryHues.inkMuted,
        fontSize: 13,
      ),
      labelLarge: plex.labelLarge?.copyWith(
        color: MemoryHues.ink,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: plexMono.labelMedium?.copyWith(
        color: MemoryHues.inkMuted,
        fontSize: 12,
      ),
      labelSmall: plexMono.labelSmall?.copyWith(
        color: MemoryHues.inkMuted,
        fontSize: 12,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: MemoryHues.paper,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: MemoryHues.paper,
        foregroundColor: MemoryHues.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.headlineMedium?.copyWith(fontSize: 22),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MemoryHues.accent,
          foregroundColor: MemoryHues.paperElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MemoryHues.paperElevated,
        selectedColor: MemoryHues.accentSoft,
        side: const BorderSide(color: MemoryHues.rule),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: textTheme.bodySmall,
      ),
      dividerTheme: const DividerThemeData(
        color: MemoryHues.rule,
        thickness: 1,
        space: 1,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        MemoryHuesExtension(),
      ],
    );
  }
}

/// Extra Memory hues tokens not covered by ColorScheme.
@immutable
class MemoryHuesExtension extends ThemeExtension<MemoryHuesExtension> {
  const MemoryHuesExtension({
    this.confidence = MemoryHues.confidence,
    this.recall = MemoryHues.recall,
    this.recallSoft = MemoryHues.recallSoft,
    this.rule = MemoryHues.rule,
    this.overlayScrim = MemoryHues.overlayScrim,
    this.accentSoft = MemoryHues.accentSoft,
    this.inkMuted = MemoryHues.inkMuted,
  });

  final Color confidence;
  final Color recall;
  final Color recallSoft;
  final Color rule;
  final Color overlayScrim;
  final Color accentSoft;
  final Color inkMuted;

  @override
  MemoryHuesExtension copyWith({
    Color? confidence,
    Color? recall,
    Color? recallSoft,
    Color? rule,
    Color? overlayScrim,
    Color? accentSoft,
    Color? inkMuted,
  }) {
    return MemoryHuesExtension(
      confidence: confidence ?? this.confidence,
      recall: recall ?? this.recall,
      recallSoft: recallSoft ?? this.recallSoft,
      rule: rule ?? this.rule,
      overlayScrim: overlayScrim ?? this.overlayScrim,
      accentSoft: accentSoft ?? this.accentSoft,
      inkMuted: inkMuted ?? this.inkMuted,
    );
  }

  @override
  MemoryHuesExtension lerp(ThemeExtension<MemoryHuesExtension>? other, double t) {
    if (other is! MemoryHuesExtension) return this;
    return MemoryHuesExtension(
      confidence: Color.lerp(confidence, other.confidence, t)!,
      recall: Color.lerp(recall, other.recall, t)!,
      recallSoft: Color.lerp(recallSoft, other.recallSoft, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      overlayScrim: Color.lerp(overlayScrim, other.overlayScrim, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
    );
  }
}
