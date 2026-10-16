import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/ocr/image_mime.dart';

void main() {
  test('detects jpeg magic bytes', () {
    final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00]);
    expect(imageMimeTypeOf(bytes), 'image/jpeg');
  });

  test('detects png magic bytes', () {
    final bytes = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ]);
    expect(imageMimeTypeOf(bytes), 'image/png');
  });

  test('falls back to extension hint', () {
    expect(
      imageMimeTypeOf(Uint8List(0), extensionHint: 'png'),
      'image/png',
    );
  });
}
