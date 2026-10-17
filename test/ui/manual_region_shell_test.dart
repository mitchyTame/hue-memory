import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/ui/manual_region_shell.dart';
import 'package:hue_memory/vision/page_region.dart';
import 'package:image/image.dart' as img;

Uint8List _png() {
  final image = img.Image(width: 120, height: 160);
  img.fill(image, color: img.ColorRgb8(240, 240, 235));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  testWidgets('Use whole page pops null', (tester) async {
    PageRegion? result = PageRegion.manual(
      left: 0,
      top: 0,
      width: 1,
      height: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<PageRegion?>(
                  MaterialPageRoute(
                    builder: (_) => ManualRegionShell(imageBytes: _png()),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Frame OCR region'), findsOneWidget);
    await tester.tap(find.text('Use whole page'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('OCR this region disabled until a box is drawn', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManualRegionShell(imageBytes: _png()),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'OCR this region'),
    );
    expect(button.onPressed, isNull);
  });
}
