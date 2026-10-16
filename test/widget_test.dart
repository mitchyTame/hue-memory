import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/app.dart';
import 'package:hue_memory/camera/sample_capture.dart';
import 'package:hue_memory/capture/page_id.dart';
import 'package:hue_memory/ocr/mock_ocr_client.dart';
import 'package:hue_memory/theme/app_theme.dart';
import 'package:hue_memory/vault/fake_vault_fs.dart';

Uint8List _tinyPng() {
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
    0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
}

void main() {
  setUp(() => AppTheme.skipGoogleFonts = true);
  tearDown(() => AppTheme.skipGoogleFonts = false);

  testWidgets('shutter → confirm → commit writes vault files', (tester) async {
    final vault = FakeVaultFs();
    final ocr = MockOcrClient();

    await tester.pumpWidget(
      HueMemoryApp(
        vault: vault,
        camera: BytesCameraCapture(_tinyPng()),
        ocr: ocr,
        pageIds: PageId(random: _FixedRandom()),
      ),
    );
    await tester.pump();

    expect(find.text('hue-memory'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Shutter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Confirm meaning'), findsOneWidget);
    expect(ocr.callCount, 1);

    await tester.tap(find.text('Commit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('hue-memory'), findsOneWidget);
    expect(find.textContaining('Last commit:'), findsOneWidget);

    final paths = vault.filePaths;
    expect(paths.any((k) => k.contains('/fleeting/') && k.endsWith('.md')), isTrue);
    expect(
      paths.any((k) => k.contains('/captures/raw/') && k.endsWith('.png')),
      isTrue,
    );
    expect(paths.any((k) => k.endsWith('.meaning.json')), isTrue);

    final noteKey = paths.firstWhere((k) => k.contains('/fleeting/'));
    final md = await vault.readText(noteKey.substring(1)); // strip leading /
    expect(md, contains('type: fleeting'));
    expect(md, contains('Attention is a muscle'));
  });
}

class _FixedRandom implements Random {
  @override
  int nextInt(int max) => 1;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.1;
}
