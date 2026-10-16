import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/theme/app_theme.dart';
import 'package:hue_memory/ui/capture_shell.dart';

void main() {
  testWidgets('capture shell shows preview stub and shutter', (tester) async {
    // Avoid google_fonts network/asset fetch in unit test CI.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF2A6B66),
            onPrimary: Color(0xFFFAFAF7),
            surface: Color(0xFFF1F0EC),
            onSurface: Color(0xFF1B2A4A),
          ),
          extensions: const [MemoryHuesExtension()],
        ),
        home: const CaptureShell(),
      ),
    );

    expect(find.textContaining('Camera preview'), findsOneWidget);
    expect(find.bySemanticsLabel('Shutter'), findsOneWidget);
  });
}
