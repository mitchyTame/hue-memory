import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mistralai_dart/mistralai_dart.dart';

/// Narrow seam over [MistralClient] for hue-memory OCR.
///
/// Production uses [LiveMistralSdk]; tests use [FakeMistralSdk].
abstract interface class MistralSdk {
  /// `GET /v1/models` — proves the API key without uploading an image.
  Future<void> verifyApiKey();

  /// Run OCR on prepared image bytes (library owns request encoding).
  Future<OcrResponse> ocrImage({
    required String model,
    required Uint8List bytes,
    required String mimeType,
  });

  void close();
}

/// Real [mistralai_dart] client — pure Dart, typed models, retries/errors.
class LiveMistralSdk implements MistralSdk {
  LiveMistralSdk({
    required String apiKey,
    String baseUrl = 'https://api.mistral.ai',
    http.Client? httpClient,
  }) : _client = MistralClient.withApiKey(
          apiKey,
          baseUrl: baseUrl,
          httpClient: httpClient,
        );

  LiveMistralSdk.withClient(this._client);

  final MistralClient _client;

  @override
  Future<void> verifyApiKey() async {
    await _client.models.list();
  }

  @override
  Future<OcrResponse> ocrImage({
    required String model,
    required Uint8List bytes,
    required String mimeType,
  }) {
    return _client.ocr.process(
      request: OcrRequest.fromBase64(
        model: model,
        data: base64Encode(bytes),
        mimeType: mimeType,
      ),
    );
  }

  @override
  void close() => _client.close();
}

/// In-memory double for unit tests.
class FakeMistralSdk implements MistralSdk {
  FakeMistralSdk({
    this.verifyError,
    this.ocrResponse,
    this.ocrError,
  });

  Object? verifyError;
  OcrResponse? ocrResponse;
  Object? ocrError;

  int verifyCalls = 0;
  int ocrCalls = 0;
  Uint8List? lastOcrBytes;
  String? lastOcrMime;
  String? lastOcrModel;

  @override
  Future<void> verifyApiKey() async {
    verifyCalls++;
    final err = verifyError;
    if (err != null) {
      if (err is Exception) throw err;
      throw Exception('$err');
    }
  }

  @override
  Future<OcrResponse> ocrImage({
    required String model,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    ocrCalls++;
    lastOcrModel = model;
    lastOcrBytes = Uint8List.fromList(bytes);
    lastOcrMime = mimeType;
    final err = ocrError;
    if (err != null) {
      if (err is Exception) throw err;
      throw Exception('$err');
    }
    return ocrResponse ??
        const OcrResponse(
          model: 'mistral-ocr-latest',
          pages: [
            OcrPage(index: 0, markdown: '∼ Fake OCR'),
          ],
        );
  }

  @override
  void close() {}
}
