import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/capture/pending_capture.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
import 'package:hue_memory/theme/app_theme.dart';
import 'package:hue_memory/theme/hue_atmosphere.dart';
import 'package:hue_memory/theme/memory_hues.dart';
import 'package:hue_memory/ui/confirm_shell.dart';
import 'package:hue_memory/ui/manual_region_shell.dart';
import 'package:image/image.dart' as img;

Uint8List _png() {
  final image = img.Image(width: 80, height: 100);
  img.fill(image, color: img.ColorRgb8(240, 240, 235));
  return Uint8List.fromList(img.encodePng(image));
}

bool _hasAtmosphereGradient(WidgetTester tester) {
  final gradients = tester
      .widgetList<DecoratedBox>(find.byType(DecoratedBox))
      .map((w) => w.decoration)
      .whereType<BoxDecoration>()
      .map((d) => d.gradient)
      .whereType<LinearGradient>()
      .toList();
  return gradients.any(
    (g) =>
        g.colors.contains(MemoryHues.fieldDeep) &&
        g.colors.contains(MemoryHues.fieldTeal),
  );
}

void main() {
  testWidgets('HueFieldScaffold paints shared ink→teal atmosphere',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const HueFieldScaffold(
          body: Center(child: Text('field')),
        ),
      ),
    );
    expect(find.text('field'), findsOneWidget);
    expect(find.byType(HueAtmosphere), findsOneWidget);
    expect(_hasAtmosphereGradient(tester), isTrue);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, MemoryHues.fieldDeep);
  });

  testWidgets('ConfirmShell uses field atmosphere behind photo', (tester) async {
    final bytes = Uint8List.fromList(
      File('test/fixtures/pixel.png').readAsBytesSync(),
    );
    final capture = PendingCapture(
      pageId: '20261021-theme',
      imageBytes: bytes,
      capturedAt: DateTime.utc(2026, 10, 21, 12),
      meaning: const MeaningResult(
        detectedGlyph: '·',
        regions: [],
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
        home: ConfirmShell(capture: capture),
      ),
    );
    await tester.pump();

    expect(find.byType(HueFieldScaffold), findsOneWidget);
    expect(find.byType(HueAtmosphere), findsOneWidget);
    expect(_hasAtmosphereGradient(tester), isTrue);
    expect(find.text('Confirm'), findsOneWidget);
  });

  testWidgets('ManualRegionShell uses field atmosphere', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ManualRegionShell(imageBytes: _png()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HueFieldScaffold), findsOneWidget);
    expect(_hasAtmosphereGradient(tester), isTrue);
    expect(find.text('Frame OCR region'), findsOneWidget);
  });
}
