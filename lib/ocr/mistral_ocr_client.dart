import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mistralai_dart/mistralai_dart.dart';

import '../writers/mindmap_propose.dart';
import 'mistral_ocr_parser.dart';
import 'mistral_sdk.dart';
import 'ocr_client.dart';
import 'ocr_image_prepare.dart';

/// Valid 1×1 RGB PNG (CRC-checked) — fixtures / prepare smoke only.
final Uint8List kMistralProbePng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x78, 0xDA, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x03, 0x01, 0x01, 0x00, 0xF7, 0x03, 0x41, 0x43, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Prepares capture bytes before OCR (decode / scale / PNG).
typedef MistralOcrImagePreparer = Future<PreparedOcrImage> Function(
  Uint8List bytes, {
  String? imageMimeType,
  String? extensionHint,
});

/// Cloud OCR via [mistralai_dart] — key check + OCR; △ also runs vision structure.
///
/// Hybrid mindmap: OCR labels + separate vision JSON (nodes/edges + x,y),
/// merged in [MindmapPropose.mergeOcrLabelsOntoVision]. Consent / live toggle
/// stay in [ConfigurableOcrClient].
class MistralOcrClient implements OcrClient {
  MistralOcrClient({
    required this.apiKey,
    http.Client? httpClient,
    this.baseUrl = 'https://api.mistral.ai',
    this.model = 'mistral-ocr-latest',
    this.visionModel = 'pixtral-12b-2409',
    this.parser = const MistralOcrParser(),
    MistralOcrImagePreparer? prepareImage,
    MistralSdk? sdk,
  })  : prepareImage = prepareImage ?? prepareImageForMistralOcr,
        _sdk = sdk ??
            LiveMistralSdk(
              apiKey: apiKey,
              baseUrl: baseUrl,
              httpClient: httpClient,
            ),
        _ownsSdk = sdk == null;

  final String apiKey;
  final String baseUrl;
  final String model;

  /// Vision model for △ structure (coords) — separate from [model] OCR.
  final String visionModel;
  final MistralOcrParser parser;
  final MistralOcrImagePreparer prepareImage;
  final MistralSdk _sdk;
  final bool _ownsSdk;

  /// Key-only check via SDK `models.list` — no image upload.
  Future<MistralConnectionResult> verifyConnection() async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      return const MistralConnectionResult(
        ok: false,
        message: 'API key is empty',
      );
    }

    try {
      await _sdk.verifyApiKey();
      return const MistralConnectionResult(
        ok: true,
        message: 'Connected — API key is valid',
      );
    } on AuthenticationException catch (e) {
      return MistralConnectionResult(
        ok: false,
        message: 'Mistral rejected the API key: ${e.message}',
        statusCode: e.statusCode,
      );
    } on ApiException catch (e) {
      return MistralConnectionResult(
        ok: false,
        message: _apiUserMessage(e),
        statusCode: e.statusCode,
      );
    } on MistralException catch (e) {
      return MistralConnectionResult(
        ok: false,
        message: e.message,
      );
    } catch (e) {
      return MistralConnectionResult(
        ok: false,
        message: _networkMessage(e),
      );
    }
  }

  @override
  Future<MeaningResult> extractMeaning(
    Uint8List imageBytes, {
    String? imageMimeType,
    String? extensionHint,
    bool allowEmpty = false,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const MistralOcrException(
        statusCode: 0,
        body: 'Mistral API key is empty',
        userMessage: 'Mistral API key is empty — add it in Settings → OCR',
      );
    }
    if (imageBytes.isEmpty) {
      throw const MistralOcrException(
        statusCode: 0,
        body: 'empty image',
        userMessage: 'Capture has no image bytes',
      );
    }

    late final PreparedOcrImage prepared;
    try {
      prepared = await prepareImage(
        imageBytes,
        imageMimeType: imageMimeType,
        extensionHint: extensionHint,
      );
    } catch (e) {
      throw MistralOcrException(
        statusCode: 0,
        body: '$e',
        userMessage:
            'Could not prepare the photo for OCR — try another shot or gallery image',
      );
    }

    try {
      final response = await _sdk.ocrImage(
        model: model,
        bytes: prepared.bytes,
        mimeType: prepared.mime,
      );
      var result = parser.parseResponse(response);
      if (!allowEmpty && _isBlankMeaning(result)) {
        throw const MistralOcrException(
          statusCode: 200,
          body: 'empty OCR',
          userMessage:
              'Mistral returned no readable text — try a clearer photo or queue for later',
        );
      }
      if (result.pageGenre == 'visual') {
        result = await _enrichVisualWithVision(result, prepared);
      }
      return result;
    } on MistralOcrException {
      rethrow;
    } on AuthenticationException catch (e) {
      throw MistralOcrException(
        statusCode: e.statusCode,
        body: e.message,
        userMessage: 'Mistral rejected the API key: ${e.message}',
      );
    } on ApiException catch (e) {
      throw MistralOcrException(
        statusCode: e.statusCode,
        body: e.message,
        userMessage: _apiUserMessage(e),
      );
    } on MistralException catch (e) {
      throw MistralOcrException(
        statusCode: 0,
        body: e.message,
        userMessage: e.message,
      );
    } catch (e) {
      throw MistralOcrException(
        statusCode: 0,
        body: '$e',
        userMessage: _networkMessage(e),
      );
    }
  }

  void close() {
    if (_ownsSdk) _sdk.close();
  }

  /// Second pass for △: vision JSON (coords) + OCR label merge.
  ///
  /// Soft-fails to OCR-only structure if vision errors or returns empty nodes.
  Future<MeaningResult> _enrichVisualWithVision(
    MeaningResult ocrResult,
    PreparedOcrImage prepared,
  ) async {
    final ocrLabels = ocrResult.regions
        .map((r) => r.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    try {
      final raw = await _sdk.chatVisionStructure(
        model: visionModel,
        bytes: prepared.bytes,
        mimeType: prepared.mime,
        ocrLabels: ocrLabels,
        maxTokens: MindmapPropose.visionMaxTokens,
      );
      final vision = MindmapStructure.parseJson(raw);
      final merged = MindmapPropose.mergeOcrLabelsOntoVision(
        ocrLabels: ocrLabels,
        vision: vision,
      );
      if (merged.nodes.isEmpty) {
        return MeaningResult(
          detectedGlyph: ocrResult.detectedGlyph,
          regions: ocrResult.regions,
          pageGenre: ocrResult.pageGenre,
          threadTick: ocrResult.threadTick,
          rawJson: {
            ...ocrResult.rawJson,
            'vision_used': false,
            'vision_model': visionModel,
            'vision_empty': true,
          },
        );
      }
      return MeaningResult(
        detectedGlyph: ocrResult.detectedGlyph,
        regions: MindmapPropose.regionsFromStructure(merged),
        pageGenre: ocrResult.pageGenre,
        threadTick: ocrResult.threadTick,
        rawJson: {
          ...ocrResult.rawJson,
          'hybrid_mindmap': true,
          'mindmap': merged.toJson(),
          'vision_used': true,
          'vision_model': visionModel,
          'vision_max_tokens': MindmapPropose.visionMaxTokens,
        },
      );
    } catch (e) {
      return MeaningResult(
        detectedGlyph: ocrResult.detectedGlyph,
        regions: ocrResult.regions,
        pageGenre: ocrResult.pageGenre,
        threadTick: ocrResult.threadTick,
        rawJson: {
          ...ocrResult.rawJson,
          'vision_used': false,
          'vision_model': visionModel,
          'vision_error': '$e',
        },
      );
    }
  }

  static bool _isBlankMeaning(MeaningResult result) {
    final text = result.regions.map((r) => r.text.trim()).join();
    return text.isEmpty &&
        (result.rawJson['pages'] == null || result.rawJson['pages'] == 0);
  }

  static String _apiUserMessage(ApiException e) {
    switch (e.statusCode) {
      case 401:
      case 403:
        return 'Mistral rejected the API key (HTTP ${e.statusCode})';
      case 404:
        return 'Mistral OCR endpoint not found (HTTP 404)';
      case 422:
        final detail = _validationDetail(e);
        if (detail != null) {
          return 'Mistral rejected the photo (HTTP 422): $detail';
        }
        return 'Mistral rejected the photo format (HTTP 422) — try another shot';
      case 429:
        return 'Mistral rate limit — try again shortly (HTTP 429)';
      case >= 500:
        return 'Mistral server error (HTTP ${e.statusCode}): ${e.message}';
      default:
        return 'Mistral OCR failed (HTTP ${e.statusCode}): ${e.message}';
    }
  }

  /// Prefer a concrete field error over the SDK's generic "Validation error".
  static String? _validationDetail(ApiException e) {
    final msg = e.message.trim();
    if (msg.isNotEmpty && msg.toLowerCase() != 'validation error') {
      return msg;
    }
    for (final detail in e.details) {
      if (detail is Map) {
        final list = detail['detail'];
        if (list is List && list.isNotEmpty) {
          final first = list.first;
          if (first is Map) {
            final m = first['msg'] ?? first['message'];
            if (m is String && m.trim().isNotEmpty) return m.trim();
          }
          if (first is String && first.trim().isNotEmpty) return first.trim();
        }
        final nested = detail['message'];
        if (nested is String &&
            nested.trim().isNotEmpty &&
            nested.toLowerCase() != 'validation error') {
          return nested.trim();
        }
      }
    }
    return null;
  }

  static String _networkMessage(Object e) {
    final s = '$e';
    if (s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('Network is unreachable')) {
      return 'No network — OCR queued offline when possible';
    }
    if (s.contains('TimeoutException') || s.contains('timed out')) {
      return 'Mistral timed out — check connection and retry';
    }
    return 'Network error talking to Mistral: $s';
  }
}

class MistralConnectionResult {
  const MistralConnectionResult({
    required this.ok,
    required this.message,
    this.statusCode,
  });

  final bool ok;
  final String message;
  final int? statusCode;
}

class MistralOcrException implements Exception {
  const MistralOcrException({
    required this.statusCode,
    required this.body,
    this.userMessage,
  });

  final int statusCode;
  final String body;
  final String? userMessage;

  String get readable => userMessage ?? toString();

  @override
  String toString() {
    if (userMessage != null) return userMessage!;
    final snippet = body.length > 200 ? '${body.substring(0, 200)}…' : body;
    return 'Mistral OCR failed ($statusCode): $snippet';
  }
}
