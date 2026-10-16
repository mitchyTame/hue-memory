import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hue_memory/ocr/mistral_ocr_client.dart';

void main() {
  test('verifyConnection succeeds on 200 OCR response', () async {
    final client = MistralOcrClient(
      apiKey: 'live-key',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/ocr');
        expect(request.headers['Authorization'], 'Bearer live-key');
        return http.Response(
          jsonEncode({
            'model': 'mistral-ocr-latest',
            'pages': [
              {'markdown': ''},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await client.verifyConnection();
    expect(result.ok, isTrue);
    expect(result.message, contains('works'));
  });

  test('verifyConnection reports auth failure', () async {
    final client = MistralOcrClient(
      apiKey: 'bad',
      httpClient: MockClient(
        (_) async => http.Response('unauthorized', 401),
      ),
    );
    final result = await client.verifyConnection();
    expect(result.ok, isFalse);
    expect(result.message, contains('API key'));
  });

  test('extractMeaning uses jpeg mime for jpeg bytes', () async {
    http.BaseRequest? seen;
    final client = MistralOcrClient(
      apiKey: 'k',
      httpClient: MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'pages': [
              {'markdown': 'F hello'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    await client.extractMeaning(jpeg);
    final body = (seen as http.Request).body;
    expect(body, contains('image/jpeg'));
  });
}
