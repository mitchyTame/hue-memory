import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/camera/camera_session.dart';
import 'package:hue_memory/camera/live_camera_shell.dart';
import 'package:hue_memory/symbols/default_packs.dart';
import 'package:hue_memory/theme/app_theme.dart';
import 'package:hue_memory/ui/capture_shell.dart';
import 'package:hue_memory/ui/settings_hub_shell.dart';

void main() {
  setUp(() => AppTheme.skipGoogleFonts = true);
  tearDown(() => AppTheme.skipGoogleFonts = false);

  testWidgets('settings hub hides OCR Gemini Symbols when bot agent on',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const SettingsHubShell(
          vaultLabel: 'vault',
          ocrModeLabel: 'OCR: mock',
          packLabel: 'Zettelkasten ink',
          geminiModeLabel: 'Gemini: off',
          botAgentEnabled: true,
          botAgentLabel: 'Bot agent: inbox',
        ),
      ),
    );

    expect(find.text('Vault'), findsOneWidget);
    expect(find.text('Bot agent'), findsOneWidget);
    expect(find.text('How to use'), findsOneWidget);
    expect(find.text('OCR'), findsNothing);
    expect(find.text('Gemini'), findsNothing);
    expect(find.text('Symbols'), findsNothing);
    expect(find.text('Paper kit'), findsNothing);
    expect(find.text('Promote ritual'), findsNothing);
    expect(find.text('Scan → inbox folder'), findsOneWidget);
  });

  testWidgets('settings hub shows full options when bot agent off',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const SettingsHubShell(
          vaultLabel: 'vault',
          ocrModeLabel: 'OCR: mock',
          packLabel: 'Zettelkasten ink',
          geminiModeLabel: 'Gemini: off',
          botAgentEnabled: false,
          botAgentLabel: 'Bot agent: off',
        ),
      ),
    );

    expect(find.text('Bot agent'), findsOneWidget);
    expect(find.text('OCR'), findsOneWidget);
    expect(find.text('Gemini'), findsOneWidget);
    expect(find.text('Symbols'), findsOneWidget);
    expect(find.text('Paper kit'), findsOneWidget);
    expect(find.text('Promote ritual'), findsOneWidget);
  });

  testWidgets('capture shell hides promote and queue in bot mode',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const CaptureShell(
          botAgentMode: true,
          queueCount: 3,
          vaultLabel: 'vault · inbox inbox',
        ),
      ),
    );

    expect(find.byTooltip('Promote ritual'), findsNothing);
    expect(find.byTooltip('Capture queue'), findsNothing);
    expect(find.byTooltip('Vault settings'), findsOneWidget);
  });

  testWidgets('live camera hides symbol chips in bot agent mode',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LiveCameraShell(
          pack: DefaultPacks.zettelkastenInk,
          botAgentMode: true,
          sessionFactory: () async => FakeCameraSession(
            imageBytes: Uint8List.fromList([1, 2, 3]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('scan to inbox'), findsOneWidget);
    expect(find.text('glyph'), findsNothing);
    // Pack chip glyphs should not appear as selectable chips.
    for (final s in DefaultPacks.zettelkastenInk.symbols.take(3)) {
      expect(find.text(s.primaryGlyph), findsNothing);
    }
  });
}
