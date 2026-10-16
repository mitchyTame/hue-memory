import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/ocr/configurable_ocr_client.dart';
import 'package:hue_memory/ocr/mistral_ocr_client.dart';
import 'package:hue_memory/ocr/mistral_sdk.dart';
import 'package:hue_memory/ocr/mock_ocr_client.dart';
import 'package:hue_memory/ocr/ocr_settings.dart';
import 'package:mistralai_dart/mistralai_dart.dart';

Future<({Uint8List bytes, String mime})> _identityPrepare(
  Uint8List bytes, {
  String? imageMimeType,
  String? extensionHint,
}) async {
  return (
    bytes: bytes,
    mime: imageMimeType ?? 'image/png',
  );
}

void main() {
  test('MistralOcrClient uses SDK OCR and parses MeaningResult', () async {
    final fake = FakeMistralSdk(
      ocrResponse: const OcrResponse(
        model: 'mistral-ocr-latest',
        pages: [
          OcrPage(index: 0, markdown: '∼ Fleeting thought\n\nMore text'),
        ],
      ),
    );
    final client = MistralOcrClient(
      apiKey: 'test-key',
      prepareImage: _identityPrepare,
      sdk: fake,
    );

    final result = await client.extractMeaning(
      Uint8List.fromList([1, 2, 3]),
      imageMimeType: 'image/png',
    );
    expect(fake.ocrCalls, 1);
    expect(fake.lastOcrMime, 'image/png');
    expect(result.detectedGlyph, '∼');
    expect(result.regions.first.text, contains('Fleeting'));
  });

  test('MistralOcrClient surfaces SDK ApiException message', () async {
    final fake = FakeMistralSdk(
      ocrError: const ApiException(
        statusCode: 400,
        message: 'Invalid base64 image data',
      ),
    );
    final client = MistralOcrClient(
      apiKey: 'k',
      prepareImage: _identityPrepare,
      sdk: fake,
    );
    try {
      await client.extractMeaning(Uint8List.fromList([9]));
      fail('expected MistralOcrException');
    } on MistralOcrException catch (e) {
      expect(e.readable, contains('Invalid base64 image data'));
      expect(e.statusCode, 400);
    }
  });

  test('MistralOcrClient maps auth failure', () async {
    final fake = FakeMistralSdk(
      ocrError: const AuthenticationException(message: 'Unauthorized'),
    );
    final client = MistralOcrClient(
      apiKey: 'bad',
      prepareImage: _identityPrepare,
      sdk: fake,
    );
    expect(
      () => client.extractMeaning(Uint8List.fromList([9])),
      throwsA(
        isA<MistralOcrException>().having(
          (e) => e.readable,
          'readable',
          contains('API key'),
        ),
      ),
    );
  });

  test('ConfigurableOcrClient uses mock until live+consent+key', () async {
    final store = MemoryOcrSettingsStore(
      const OcrSettings(apiKey: 'k', consentGiven: false, useLive: true),
    );
    final mock = MockOcrClient(glyph: '∼');
    var liveCalls = 0;
    final ocr = ConfigurableOcrClient(
      settings: store,
      mock: mock,
      mistralFactory: (key) {
        liveCalls++;
        return MistralOcrClient(
          apiKey: key,
          prepareImage: _identityPrepare,
          sdk: FakeMistralSdk(
            ocrError: const ApiException(statusCode: 500, message: 'boom'),
          ),
        );
      },
    );

    await ocr.extractMeaning(Uint8List.fromList([1]));
    expect(mock.callCount, 1);
    expect(liveCalls, 0);

    await store.write(
      const OcrSettings(apiKey: 'k', consentGiven: true, useLive: true),
    );
    liveCalls = 0;
    mock.callCount = 0;

    await expectLater(
      ocr.extractMeaning(Uint8List.fromList([1])),
      throwsA(isA<MistralOcrException>()),
    );
    expect(mock.callCount, 0);
    expect(liveCalls, 1);
  });
}
