import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/ocr/mistral_ocr_request.dart';
import 'package:hue_memory/ocr/mistral_sdk.dart';

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

  test('buildMistralOcrDocument uses image_url data URL (not type base64)', () {
    final doc = buildMistralOcrDocument(imageBytes: png, mime: 'image/png');
    expect(doc['type'], 'image_url');
    final url = doc['image_url'] as String;
    expect(url.startsWith('data:image/png;base64,'), isTrue);
    expect(url.contains(base64Encode(png)), isTrue);
    expect(doc.containsKey('data'), isFalse);
    expect(doc.containsKey('mime_type'), isFalse);
  });

  test('ImageUrlOcrRequest.toJson matches ImageURLChunk wire shape', () {
    final req = ImageUrlOcrRequest(
      model: 'mistral-ocr-latest',
      imageDataUrl: mistralImageDataUrl(png, 'image/png'),
    );
    final json = req.toJson();
    expect(json['model'], 'mistral-ocr-latest');
    final document = json['document'] as Map<String, dynamic>;
    expect(document['type'], 'image_url');
    expect(document['image_url'], startsWith('data:image/png;base64,'));
    // Must not emit the broken fromBase64 shape
    expect(document['type'], isNot('base64'));
    expect(document.containsKey('data'), isFalse);
  });
}
