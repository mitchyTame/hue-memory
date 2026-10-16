import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hue_memory/ocr/configurable_ocr_client.dart';
import 'package:hue_memory/ocr/mistral_ocr_client.dart';
import 'package:hue_memory/ocr/mock_ocr_client.dart';
import 'package:hue_memory/ocr/ocr_settings.dart';

Future<({Uint8List bytes, String mime})> _identityPrepare(
  Uint8List bytes, {
  String? imageMimeType,
  String? extensionHint,
}) async {
  return (
    bytes: bytes,
    mime: imageMimeType ?? 'image/jpeg',
  );
}

void main() {
  test('MistralOcrClient posts image_url data URL and parses response', () async {
    http.BaseRequest? seen;
    final client = MistralOcrClient(
      apiKey: 'test-key',
      prepareImage: _identityPrepare,
      httpClient: MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'model': 'mistral-ocr-latest',
            'pages': [
              {'markdown': '∼ Fleeting thought\n\nMore text'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await client.extractMeaning(
      Uint8List.fromList([1, 2, 3]),
      imageMimeType: 'image/jpeg',
    );
    expect(seen!.url.path, '/v1/ocr');
    expect(seen!.headers['Authorization'], 'Bearer test-key');
    final body = jsonDecode((seen as http.Request).body) as Map<String, dynamic>;
    final doc = body['document'] as Map<String, dynamic>;
    expect(doc['type'], 'image_url');
    expect(doc['image_url'], startsWith('data:image/jpeg;base64,'));
    expect(result.detectedGlyph, '∼');
    expect(result.regions.first.text, contains('Fleeting'));
  });

  test('MistralOcrClient surfaces API error message on 400', () async {
    final client = MistralOcrClient(
      apiKey: 'k',
      prepareImage: _identityPrepare,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'object': 'error',
            'message': 'Invalid base64 image data',
            'type': 'invalid_request_error',
          }),
          400,
        ),
      ),
    );
    try {
      await client.extractMeaning(Uint8List.fromList([9]));
      fail('expected MistralOcrException');
    } on MistralOcrException catch (e) {
      expect(e.readable, contains('Invalid base64 image data'));
      expect(e.readable, isNot(contains('"object"')));
    }
  });

  test('MistralOcrClient throws on non-2xx', () async {
    final client = MistralOcrClient(
      apiKey: 'bad',
      prepareImage: _identityPrepare,
      httpClient: MockClient(
        (_) async => http.Response('nope', 401),
      ),
    );
    expect(
      () => client.extractMeaning(Uint8List.fromList([9])),
      throwsA(isA<MistralOcrException>()),
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
          httpClient: MockClient(
            (_) async => http.Response('{}', 500),
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

    // Live path is selected; mock HTTP returns 500 → exception, not mock.
    expect(
      () => ocr.extractMeaning(Uint8List.fromList([1])),
      throwsA(isA<MistralOcrException>()),
    );
    expect(mock.callCount, 0);
  });
}
