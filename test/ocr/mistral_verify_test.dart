import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/ocr/mistral_ocr_client.dart';
import 'package:hue_memory/ocr/mistral_sdk.dart';
import 'package:hue_memory/ocr/ocr_image_prepare.dart';
import 'package:mistralai_dart/mistralai_dart.dart';

Future<({Uint8List bytes, String mime})> _identityPrepare(
  Uint8List bytes, {
  String? imageMimeType,
  String? extensionHint,
  int maxSide = 2048,
}) async {
  return (
    bytes: bytes,
    mime: imageMimeType ?? 'image/png',
  );
}

void main() {
  test('verifyConnection uses SDK models.list — no OCR upload', () async {
    final fake = FakeMistralSdk();
    final client = MistralOcrClient(
      apiKey: 'live-key',
      prepareImage: _identityPrepare,
      sdk: fake,
    );

    final result = await client.verifyConnection();
    expect(result.ok, isTrue);
    expect(result.message, contains('valid'));
    expect(fake.verifyCalls, 1);
    expect(fake.ocrCalls, 0);
  });

  test('verifyConnection reports auth failure from SDK', () async {
    final fake = FakeMistralSdk(
      verifyError: const AuthenticationException(message: 'bad key'),
    );
    final client = MistralOcrClient(
      apiKey: 'bad',
      prepareImage: _identityPrepare,
      sdk: fake,
    );
    final result = await client.verifyConnection();
    expect(result.ok, isFalse);
    expect(result.message, contains('API key'));
    expect(result.statusCode, 401);
  });

  test('extractMeaning passes prepared mime to SDK', () async {
    final fake = FakeMistralSdk(
      ocrResponse: const OcrResponse(
        model: 'mistral-ocr-latest',
        pages: [OcrPage(index: 0, markdown: 'F hello')],
      ),
    );
    final client = MistralOcrClient(
      apiKey: 'k',
      prepareImage: _identityPrepare,
      sdk: fake,
    );
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    await client.extractMeaning(jpeg, imageMimeType: 'image/jpeg');
    expect(fake.lastOcrMime, 'image/jpeg');
    expect(fake.lastOcrBytes, jpeg);
  });

  test('prepareImageForMistralOcr re-encodes valid PNG to fresh PNG', () async {
    final prepared = await prepareImageForMistralOcr(kMistralProbePng);
    expect(prepared.mime, 'image/png');
    expect(prepared.bytes[0], 0x89);
    expect(prepared.bytes.length, greaterThan(8));
  });

  test('prepareImageForMistralOcr rejects undecodable junk', () async {
    final junkJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00, 1, 2, 3]);
    expect(
      () => prepareImageForMistralOcr(junkJpeg),
      throwsA(isA<StateError>()),
    );
  });
}
