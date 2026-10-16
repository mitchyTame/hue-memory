import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mistralai_dart/mistralai_dart.dart';

import '../writers/mindmap_propose.dart';
import 'mistral_ocr_request.dart';

/// Narrow seam over [MistralClient] for hue-memory OCR + vision structure.
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

  /// Vision chat → raw JSON text for mindmap nodes/edges (tight max tokens).
  ///
  /// Separate from OCR: coords come from the image; OCR labels merge later.
  Future<String> chatVisionStructure({
    required String model,
    required Uint8List bytes,
    required String mimeType,
    List<String> ocrLabels = const [],
    int maxTokens = MindmapPropose.visionMaxTokens,
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
  Future<String> chatVisionStructure({
    required String model,
    required Uint8List bytes,
    required String mimeType,
    List<String> ocrLabels = const [],
    int maxTokens = MindmapPropose.visionMaxTokens,
  }) async {
    final dataUrl = mistralImageDataUrl(bytes, mimeType);
    final response = await _client.chat.create(
      request: ChatCompletionRequest(
        model: model,
        temperature: 0,
        maxTokens: maxTokens,
        responseFormat: ResponseFormat.jsonObject,
        messages: [
          ChatMessage.system(MindmapPropose.visionSystemPrompt),
          ChatMessage.userMultimodal([
            ContentPart.text(MindmapPropose.visionUserPrompt(ocrLabels)),
            ContentPart.imageUrl(dataUrl),
          ]),
        ],
      ),
    );
    return response.text?.trim() ?? '';
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
    this.visionJson,
    this.visionError,
  });

  Object? verifyError;
  OcrResponse? ocrResponse;
  Object? ocrError;
  String? visionJson;
  Object? visionError;

  int verifyCalls = 0;
  int ocrCalls = 0;
  int visionCalls = 0;
  Uint8List? lastOcrBytes;
  String? lastOcrMime;
  String? lastOcrModel;
  String? lastVisionModel;
  List<String>? lastVisionOcrLabels;
  int? lastVisionMaxTokens;

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
  Future<String> chatVisionStructure({
    required String model,
    required Uint8List bytes,
    required String mimeType,
    List<String> ocrLabels = const [],
    int maxTokens = MindmapPropose.visionMaxTokens,
  }) async {
    visionCalls++;
    lastVisionModel = model;
    lastVisionOcrLabels = List<String>.from(ocrLabels);
    lastVisionMaxTokens = maxTokens;
    final err = visionError;
    if (err != null) {
      if (err is Exception) throw err;
      throw Exception('$err');
    }
    return visionJson ??
        '{"nodes":[{"id":"n1","label":"Hub","x":0.4,"y":0.35}],"edges":[]}';
  }

  @override
  void close() {}
}
