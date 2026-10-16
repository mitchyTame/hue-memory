import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/ocr/mistral_ocr_request.dart';

void main() {
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  test('resolveOcrMime prefers magic bytes over wrong caller mime', () {
    expect(
      resolveOcrMime(jpeg, imageMimeType: 'image/png'),
      'image/jpeg',
    );
    expect(
      resolveOcrMime(png, imageMimeType: 'image/jpeg'),
      'image/png',
    );
  });

  test('resolveOcrMime normalizes image/jpg', () {
    expect(
      resolveOcrMime(Uint8List(0), imageMimeType: 'image/jpg'),
      'image/jpeg',
    );
  });
}
