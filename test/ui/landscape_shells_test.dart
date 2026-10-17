import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/camera/camera_session.dart';
import 'package:hue_memory/camera/live_camera_shell.dart';
import 'package:hue_memory/capture/last_commit_summary.dart';
import 'package:hue_memory/capture/pending_capture.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
import 'package:hue_memory/theme/app_theme.dart';
import 'package:hue_memory/ui/capture_shell.dart';
import 'package:hue_memory/ui/confirm_shell.dart';
import 'package:hue_memory/ui/vault_settings_shell.dart';

void main() {
  setUp(() => AppTheme.skipGoogleFonts = true);
  tearDown(() => AppTheme.skipGoogleFonts = false);

  Future<void> pumpLandscape(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: home),
    );
    await tester.pump();
  }

  testWidgets('CaptureShell fits tight landscape without overflow', (tester) async {
    await pumpLandscape(
      tester,
      CaptureShell(
        lastCommit: LastCommitSummary(
          fileName: 'note.md',
          folder: 'fleeting',
          at: DateTime(2026, 10, 16, 12, 0),
          symbolId: 'fleeting',
          glyph: '∼',
        ),
        onShutter: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('hue-memory'), findsOneWidget);
    expect(find.text('Last commit'), findsOneWidget);
  });

  testWidgets('LiveCameraShell fits tight landscape without overflow', (tester) async {
    await pumpLandscape(
      tester,
      LiveCameraShell(
        sessionFactory: () async => FakeCameraSession(
          imageBytes: Uint8List.fromList([1, 2, 3]),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    // Landscape uses the shorter hint; preview letterboxes (no overflow).
    expect(find.textContaining('Frame page'), findsOneWidget);
    expect(find.bySemanticsLabel('Shutter'), findsOneWidget);
  });

  testWidgets('ConfirmShell fits tight landscape without overflow', (tester) async {
    final capture = PendingCapture(
      pageId: '20261016T120000',
      imageBytes: Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
        0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
        0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0x02, 0xFE, 0x00, 0x00,
        0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
      ]),
      capturedAt: DateTime.utc(2026, 10, 16),
      meaning: const MeaningResult(
        detectedGlyph: '∼',
        regions: [
          OcrRegion(id: 'r1', text: 'Hello', confidence: 0.9),
        ],
      ),
      imageExtension: 'png',
      symbolId: 'fleeting',
    );

    await pumpLandscape(
      tester,
      ConfirmShell(capture: capture),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('VaultSettingsShell has no SAF jargon', (tester) async {
    await pumpLandscape(
      tester,
      VaultSettingsShell(
        vaultRootLabel: '/tmp/vault',
        onChooseFolder: () {},
        onWriteTestNote: () {},
        onUseDefault: () {},
      ),
    );
    expect(find.textContaining('SAF'), findsNothing);
    expect(find.textContaining('content://'), findsNothing);
    expect(find.text('Choose vault folder'), findsOneWidget);
    expect(find.textContaining('leave Obsidian open'), findsOneWidget);
  });
}
