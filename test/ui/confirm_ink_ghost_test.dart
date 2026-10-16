import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/capture/pending_capture.dart';
import 'package:hue_memory/ocr/mock_ocr_client.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
import 'package:hue_memory/theme/app_theme.dart';
import 'package:hue_memory/ui/confirm_shell.dart';
import 'package:hue_memory/ui/region_overlay_painter.dart';

Finder _regionOverlayPaints() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is RegionOverlayPainter,
    );

void main() {
  testWidgets('visual confirm shows node editors and Save; ink-ghost toggle',
      (tester) async {
    bool? committedGhost;
    List<OcrRegion>? committedRegions;
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
            regions,
          }) async {
            committedGhost = inkGhost;
            committedRegions = regions;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Fix mindmap words'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(_regionOverlayPaints(), findsNothing);
    expect(kDebugRegionOverlay, isFalse);

    final sheet = find.byType(ListView).last;
    await tester.dragUntilVisible(
      find.text('Dim photo under nodes'),
      sheet,
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dim photo under nodes'));
    await tester.pump();

    await tester.dragUntilVisible(
      find.text('Add node'),
      sheet,
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add node'), findsOneWidget);

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(committedGhost, isFalse);
    expect(committedRegions, isNotNull);
    expect(committedRegions, isNotEmpty);
  });

  testWidgets('non-visual confirm uses simple note body, no mindmap chrome',
      (tester) async {
    final bytes = Uint8List.fromList(
      File('test/fixtures/pixel.png').readAsBytesSync(),
    );
    final capture = PendingCapture(
      pageId: '20261016-p7k2',
      imageBytes: bytes,
      capturedAt: DateTime.utc(2026, 10, 16, 12),
      meaning: MeaningResult(
        detectedGlyph: '∼',
        regions: MockOcrClient.defaultFleetingRegions,
        pageGenre: 'text',
      ),
      imageExtension: 'png',
      symbolId: 'fleeting',
      title: 'Note',
      noteBody: 'Body',
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
            regions,
          }) async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Fix mindmap words'), findsNothing);
    expect(find.text('Add node'), findsNothing);
    expect(find.text('Note'), findsWidgets);
    expect(_regionOverlayPaints(), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });
}
