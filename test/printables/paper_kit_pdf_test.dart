import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/printables/hue_code.dart';
import 'package:hue_memory/printables/paper_kit_pdf.dart';
import 'package:hue_memory/symbols/default_packs.dart';

void main() {
  const kit = PaperKitPdf();

  test('legend PDF is non-empty and starts with %PDF', () async {
    final bytes = await kit.buildLegend(pack: DefaultPacks.zettelkastenInk);
    expect(bytes.length, greaterThan(200));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('hue-dot sheet is a non-empty PDF for a code batch', () async {
    final codes = HueCode(random: Random(3)).batch(8);
    final bytes = await kit.buildHueDotSheet(codes: codes);
    expect(bytes.length, greaterThan(400));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // Compressed content streams — size scales with twin-pair count.
    final tiny = await kit.buildHueDotSheet(codes: codes.take(2).toList());
    expect(bytes.length, greaterThan(tiny.length));
  });

  test('rejects invalid hue codes', () async {
    expect(
      () => kit.buildHueDotSheet(codes: const ['bad!']),
      throwsA(isA<ArgumentError>()),
    );
  });
}
