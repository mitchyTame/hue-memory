import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hue_memory/ocr/configurable_ocr_client.dart';
import 'package:hue_memory/ocr/mistral_ocr_client.dart';
import 'package:hue_memory/ocr/mock_ocr_client.dart';
import 'package:hue_memory/ocr/ocr_settings.dart';

void main() {
  test('MistralOcrClient posts image_url and parses response', () async {
    http.BaseRequest? seen;
    final client = MistralOcrClient(
      apiKey: 'test-key',
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

    final result = await client.extractMeaning(Uint8List.fromList([1, 2, 3]));
    expect(seen!.url.path, '/v1/ocr');
    expect(seen!.headers['Authorization'], 'Bearer test-key');
    expect(result.detectedGlyph, '∼');
    expect(result.regions.first.text, contains('Fleeting'));
  });

  test('MistralOcrClient throws on non-2xx', () async {
    final client = MistralOcrClient(
      apiKey: 'bad',
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
          httpClient: MockClient(
            (_) async => http.Response('{}', 500),
          ),
        );
      },
    );

    await ocr.extractMeaning(Uint8List(0));
    expect(mock.callCount, 1);
    expect(liveCalls, 0);

    await store.write(
      const OcrSettings(apiKey: 'k', consentGiven: true, useLive: true),
    );
    liveCalls = 0;
    mock.callCount = 0;

    // Live path is selected; mock HTTP returns 500 → exception, not mock.
    expect(
      () => ocr.extractMeaning(Uint8List(0)),
      throwsA(isA<MistralOcrException>()),
    );
    expect(mock.callCount, 0);
  });
}
