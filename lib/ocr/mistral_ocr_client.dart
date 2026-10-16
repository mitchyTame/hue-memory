import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'image_mime.dart';
import 'mistral_ocr_parser.dart';
import 'ocr_client.dart';

/// Minimal 1×1 PNG — cheap probe for auth + `/v1/ocr` reachability.
final Uint8List kMistralProbePng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0x02, 0xFE, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Cloud OCR via Mistral (`POST /v1/ocr` with image data URL).
///
/// Requires API key + user consent (enforced by [ConfigurableOcrClient]).
class MistralOcrClient implements OcrClient {
  MistralOcrClient({
    required this.apiKey,
    http.Client? httpClient,
    this.baseUrl = 'https://api.mistral.ai',
    this.model = 'mistral-ocr-latest',
    this.parser = const MistralOcrParser(),
  }) : _http = httpClient ?? http.Client();

  final String apiKey;
  final String baseUrl;
  final String model;
  final MistralOcrParser parser;
  final http.Client _http;

  /// Live check: auth + OCR endpoint with a tiny PNG.
  Future<MistralConnectionResult> verifyConnection() async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      return const MistralConnectionResult(
        ok: false,
        message: 'API key is empty',
      );
    }
    try {
      await extractMeaning(
        kMistralProbePng,
        imageMimeType: 'image/png',
        allowEmpty: true,
      );
      return const MistralConnectionResult(
        ok: true,
        message: 'Connected — Mistral OCR key works',
      );
    } on MistralOcrException catch (e) {
      return MistralConnectionResult(
        ok: false,
        message: e.readable,
        statusCode: e.statusCode,
      );
    } on FormatException catch (e) {
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

    final mime = imageMimeType ??
        imageMimeTypeOf(imageBytes, extensionHint: extensionHint);
    final dataUrl = 'data:$mime;base64,${base64Encode(imageBytes)}';
    final uri = Uri.parse('$baseUrl/v1/ocr');
    final body = jsonEncode({
      'model': model,
      'document': {
        'type': 'image_url',
        'image_url': dataUrl,
      },
    });

    late final http.Response response;
    try {
      response = await _http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      );
    } catch (e) {
      throw MistralOcrException(
        statusCode: 0,
        body: '$e',
        userMessage: _networkMessage(e),
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MistralOcrException(
        statusCode: response.statusCode,
        body: response.body,
        userMessage: _httpUserMessage(response.statusCode, response.body),
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Mistral OCR response was not a JSON object');
    }
    final result = parser.parse(decoded);
    if (!allowEmpty && _isBlankMeaning(result)) {
      throw const MistralOcrException(
        statusCode: 200,
        body: 'empty OCR',
        userMessage:
            'Mistral returned no readable text — try a clearer photo or queue for later',
      );
    }
    return result;
  }

  static bool _isBlankMeaning(MeaningResult result) {
    final text = result.regions.map((r) => r.text.trim()).join();
    return text.isEmpty &&
        (result.rawJson['pages'] == null || result.rawJson['pages'] == 0);
  }

  static String _httpUserMessage(int status, String body) {
    switch (status) {
      case 401:
      case 403:
        return 'Mistral rejected the API key (HTTP $status)';
      case 404:
        return 'Mistral OCR endpoint not found (HTTP 404)';
      case 429:
        return 'Mistral rate limit — try again shortly (HTTP 429)';
      case >= 500:
        return 'Mistral server error (HTTP $status)';
      default:
        final snippet =
            body.length > 120 ? '${body.substring(0, 120)}…' : body;
        return 'Mistral OCR failed (HTTP $status)${snippet.isEmpty ? '' : ': $snippet'}';
    }
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
