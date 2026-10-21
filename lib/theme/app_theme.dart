import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'memory_hues.dart';

/// ThemeData for hue-memory. ColorScheme is locked — never ColorScheme.fromSeed.
abstract final class AppTheme {
  /// When true, skip runtime Google Fonts (widget tests / offline CI).
  static bool skipGoogleFonts = false;

  static ThemeData light() {
    final colorScheme = const ColorScheme.light(
      surface: MemoryHues.paper,
      onSurface: MemoryHues.ink,
      primary: MemoryHues.accent,
      onPrimary: MemoryHues.paperElevated,
      primaryContainer: MemoryHues.accentSoft,
      onPrimaryContainer: MemoryHues.ink,
      secondary: MemoryHues.recall,
      onSecondary: MemoryHues.ink,
      secondaryContainer: MemoryHues.recallSoft,
      onSecondaryContainer: MemoryHues.ink,
      tertiary: MemoryHues.inkMuted,
      onTertiary: MemoryHues.paperElevated,
      error: MemoryHues.danger,
      onError: MemoryHues.paperElevated,
      outline: MemoryHues.rule,
      surfaceContainerHighest: MemoryHues.paperElevated,
      surfaceTint: MemoryHues.paper,
    );

    final TextTheme plex;
    final TextTheme fraunces;
    final TextTheme plexMono;
    if (skipGoogleFonts) {
      final base = ThemeData(brightness: Brightness.light).textTheme;
      plex = base;
      fraunces = base;
      plexMono = base;
    } else {
      plex = GoogleFonts.ibmPlexSansTextTheme();
      fraunces = GoogleFonts.frauncesTextTheme();
      plexMono = GoogleFonts.ibmPlexMonoTextTheme();
    }

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
      // Kill Material 3 surface-tint so AppBars / sheets stay paper, not blue.
      applyElevationOverlayColor: false,
      appBarTheme: AppBarTheme(
        backgroundColor: MemoryHues.paper,
        foregroundColor: MemoryHues.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.headlineMedium?.copyWith(fontSize: 22),
        iconTheme: const IconThemeData(color: MemoryHues.ink),
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
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MemoryHues.accent,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: MemoryHues.accent),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MemoryHues.accent,
          side: const BorderSide(color: MemoryHues.rule),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MemoryHues.paperElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MemoryHues.rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MemoryHues.rule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MemoryHues.accent, width: 1.5),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: MemoryHues.inkMuted),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: MemoryHues.paperElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: MemoryHues.paperElevated,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: MemoryHues.paperElevated,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: MemoryHues.ink,
        contentTextStyle: TextStyle(color: MemoryHues.paperElevated),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return MemoryHues.accent;
          }
          return MemoryHues.inkMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return MemoryHues.accentSoft;
          }
          return MemoryHues.rule;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return MemoryHues.accent;
          }
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(MemoryHues.paperElevated),
        side: const BorderSide(color: MemoryHues.rule, width: 1.5),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: MemoryHues.inkMuted,
        textColor: MemoryHues.ink,
      ),
      iconTheme: const IconThemeData(color: MemoryHues.ink),
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
