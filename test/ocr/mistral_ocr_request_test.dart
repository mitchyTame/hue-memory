import 'dart:convert';
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

  test('buildMistralOcrRequestBody uses data URL image_url string', () {
    final body = buildMistralOcrRequestBody(
      model: 'mistral-ocr-latest',
      imageBytes: jpeg,
      mime: 'image/jpeg',
    );
    expect(body['model'], 'mistral-ocr-latest');
    final doc = body['document'] as Map<String, Object?>;
    expect(doc['type'], 'image_url');
    final url = doc['image_url'] as String;
    expect(url.startsWith('data:image/jpeg;base64,'), isTrue);
    expect(url.contains(base64Encode(jpeg)), isTrue);
    // Must not be nested {url:…} only — flat string per current SDK docs.
    expect(doc['image_url'], isA<String>());
  });

  test('mistralImageDataUrl never emits image/jpg', () {
    final url = mistralImageDataUrl(jpeg, 'image/jpg');
    expect(url.startsWith('data:image/jpeg;base64,'), isTrue);
  });

  test('mistralApiErrorMessage extracts message from object/error body', () {
    const body =
        '{"object":"error","message":"Invalid base64 image data","type":"invalid_request_error","param":null,"code":"1210"}';
    expect(mistralApiErrorMessage(body), 'Invalid base64 image data');
  });

  test('mistralHttpUserMessage surfaces API message not raw object dump', () {
    const body =
        '{"object":"error","message":"Provide the image as a base64 data URL","type":"invalid_request_error"}';
    final msg = mistralHttpUserMessage(400, body);
    expect(msg, contains('Provide the image as a base64 data URL'));
    expect(msg, isNot(contains('"object"')));
  });

  test('mistralHttpUserMessage falls back for non-JSON bodies', () {
    expect(
      mistralHttpUserMessage(400, 'nope'),
      'Mistral OCR failed (HTTP 400): nope',
    );
  });
}
