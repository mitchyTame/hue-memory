import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hue_memory/ocr/mistral_ocr_client.dart';
import 'package:hue_memory/ocr/ocr_image_prepare.dart';

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
  test('verifyConnection uses GET /v1/models — no OCR image upload', () async {
    http.BaseRequest? seen;
    final client = MistralOcrClient(
      apiKey: 'live-key',
      prepareImage: _identityPrepare,
      httpClient: MockClient((request) async {
        seen = request;
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/models');
        expect(request.headers['Authorization'], 'Bearer live-key');
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'mistral-ocr-latest'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await client.verifyConnection();
    expect(result.ok, isTrue);
    expect(result.message, contains('valid'));
    expect(seen!.url.path, '/v1/models');
    expect(seen!.method, 'GET');
  });

  test('verifyConnection reports auth failure from /v1/models', () async {
    final client = MistralOcrClient(
      apiKey: 'bad',
      prepareImage: _identityPrepare,
      httpClient: MockClient(
        (_) async => http.Response('unauthorized', 401),
      ),
    );
    final result = await client.verifyConnection();
    expect(result.ok, isFalse);
    expect(result.message, contains('API key'));
    expect(result.statusCode, 401);
  });

  test('extractMeaning uses jpeg mime for jpeg bytes when not re-encoded',
      () async {
    http.BaseRequest? seen;
    final client = MistralOcrClient(
      apiKey: 'k',
      prepareImage: _identityPrepare,
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
    await client.extractMeaning(jpeg, imageMimeType: 'image/jpeg');
    final body = (seen as http.Request).body;
    expect(body, contains('image/jpeg'));
    expect(body, contains('data:image/jpeg;base64,'));
  });

  test('prepareImageForMistralOcr re-encodes valid PNG to fresh PNG', () async {
    final prepared = await prepareImageForMistralOcr(kMistralProbePng);
    expect(prepared.mime, 'image/png');
    expect(prepared.bytes[0], 0x89);
    expect(prepared.bytes[1], 0x50);
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
