import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mistralai_dart/mistralai_dart.dart';

import 'mistral_ocr_request.dart';

/// Narrow seam over [MistralClient] for hue-memory OCR.
///
/// Production uses [LiveMistralSdk]; tests use [FakeMistralSdk].
abstract interface class MistralSdk {
  /// `GET /v1/models` — proves the API key without uploading an image.
  Future<void> verifyApiKey();

  /// Run OCR on prepared image bytes (library owns transport/errors).
  Future<OcrResponse> ocrImage({
    required String model,
    required Uint8List bytes,
    required String mimeType,
  });

  void close();
}

/// Real [mistralai_dart] client — key check via SDK; OCR uses ImageURLChunk.
///
/// `OcrRequest.fromBase64` in mistralai_dart 8.1.0 serializes as
/// `{type: base64, data, mime_type}`, which Mistral rejects with HTTP 422.
/// Photos must be `type: image_url` with a `data:image/…;base64,…` string.
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
      request: ImageUrlOcrRequest(
        model: model,
        imageDataUrl: mistralImageDataUrl(bytes, mimeType),
      ),
    );
  }

  @override
  void close() => _client.close();
}

/// [OcrRequest] that emits Mistral's ImageURLChunk wire shape.
///
/// Subclasses [OcrRequest] so [OcrResource.process] still uses SDK auth,
/// retries, and error mapping — only the JSON document differs.
class ImageUrlOcrRequest extends OcrRequest {
  ImageUrlOcrRequest({
    required super.model,
    required this.imageDataUrl,
  }) : super(
          // Placeholder for the sealed document field; [toJson] ignores it.
          document: OcrDocument.url(imageDataUrl),
        );

  final String imageDataUrl;

  @override
  Map<String, dynamic> toJson() => {
        'model': model,
        'document': {
          'type': 'image_url',
          'image_url': imageDataUrl,
        },
      };
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
