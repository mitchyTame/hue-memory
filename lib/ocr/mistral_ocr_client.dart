import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'mistral_ocr_parser.dart';
import 'ocr_client.dart';

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
    this.imageMimeType = 'image/png',
  }) : _http = httpClient ?? http.Client();

  final String apiKey;
  final String baseUrl;
  final String model;
  final MistralOcrParser parser;
  final String imageMimeType;
  final http.Client _http;

  @override
  Future<MeaningResult> extractMeaning(Uint8List imageBytes) async {
    if (apiKey.trim().isEmpty) {
      throw StateError('Mistral API key is empty');
    }

    final dataUrl =
        'data:$imageMimeType;base64,${base64Encode(imageBytes)}';
    final uri = Uri.parse('$baseUrl/v1/ocr');
    final body = jsonEncode({
      'model': model,
      'document': {
        'type': 'image_url',
        'image_url': dataUrl,
      },
    });

    final response = await _http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: body,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MistralOcrException(
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Mistral OCR response was not a JSON object');
    }
    return parser.parse(decoded);
  }
}

class MistralOcrException implements Exception {
  const MistralOcrException({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;

  @override
  String toString() {
    final snippet = body.length > 200 ? '${body.substring(0, 200)}…' : body;
    return 'Mistral OCR failed ($statusCode): $snippet';
  }
}
