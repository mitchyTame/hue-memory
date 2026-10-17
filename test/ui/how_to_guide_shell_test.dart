import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/theme/app_theme.dart';
import 'package:hue_memory/ui/how_to_guide_shell.dart';
import 'package:hue_memory/ui/settings_hub_shell.dart';

void main() {
  setUp(() => AppTheme.skipGoogleFonts = true);
  tearDown(() => AppTheme.skipGoogleFonts = false);

  testWidgets('guide shows brand and core steps', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const HowToGuideShell(),
      ),
    );
    expect(find.text('hue-memory'), findsOneWidget);
    expect(find.text('Mark the page'), findsOneWidget);
    expect(find.text('Shoot & frame (optional)'), findsOneWidget);
    expect(find.text('OCR region'), findsOneWidget);
    expect(find.text('Links in Obsidian'), findsOneWidget);
    expect(find.text('Your folders'), findsOneWidget);
    expect(find.textContaining('journal'), findsWidgets);
    expect(find.text('Hierarchical tags'), findsOneWidget);
    expect(find.textContaining('L-corner'), findsNothing);
    expect(find.textContaining('L-corners'), findsNothing);
  });

  testWidgets('settings hub opens How to use entry', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsHubShell(
          vaultLabel: 'vault',
          ocrModeLabel: 'OCR: mock',
          packLabel: 'Zettelkasten ink',
          onOpenGuide: () => opened = true,
        ),
      ),
    );
    await tester.tap(find.text('How to use'));
    await tester.pump();
    expect(opened, isTrue);
  });
}
