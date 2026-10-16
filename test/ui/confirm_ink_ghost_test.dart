import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/capture/pending_capture.dart';
import 'package:hue_memory/ocr/mock_ocr_client.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
import 'package:hue_memory/theme/app_theme.dart';
import 'package:hue_memory/ui/confirm_shell.dart';

void main() {
  testWidgets('visual chip shows ink-ghost toggle; commit passes flag',
      (tester) async {
    bool? committedGhost;
    final bytes = Uint8List.fromList(
      File('test/fixtures/pixel.png').readAsBytesSync(),
    );
    final capture = PendingCapture(
      pageId: '20261016-p7k2',
      imageBytes: bytes,
      capturedAt: DateTime.utc(2026, 10, 16, 12),
      meaning: MeaningResult(
        detectedGlyph: '△',
        regions: MockOcrClient.defaultVisualRegions,
        pageGenre: 'visual',
      ),
      imageExtension: 'png',
      symbolId: 'visual',
      title: 'Mindmap',
      noteBody: 'Central idea',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConfirmShell(
          capture: capture,
          onCommit: ({
            required symbolId,
            required title,
            required noteBody,
            required links,
            inkGhost = true,
          }) async {
            committedGhost = inkGhost;
          },
        ),
      ),
    );
    await tester.pump(); // allow image decode

    expect(find.text('Ink ghost'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();

    expect(committedGhost, isFalse);
  });
}
