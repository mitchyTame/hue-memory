import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../writers/mindmap_propose.dart';
import 'gemini_settings.dart';

/// Result of a Gemini connection / tiny probe.
class GeminiConnectionResult {
  const GeminiConnectionResult({
    required this.ok,
    required this.message,
    this.statusCode,
  });

  final bool ok;
  final String message;
  final int? statusCode;
}

/// Capture class from the cheap Gemini Flash vision coordinator.
enum CaptureClass {
  textPage,
  diagram,
  photoOnly;

  static CaptureClass parse(String raw) {
    final s = raw.trim().toLowerCase().replaceAll('-', '_');
    if (s == 'diagram' ||
        s == 'visual' ||
        s == 'visual_map' ||
        s == 'mindmap') {
      return CaptureClass.diagram;
    }
    if (s == 'photo_only' ||
        s == 'photo' ||
        s == 'drawing' ||
        s == 'image_only') {
      return CaptureClass.photoOnly;
    }
    return CaptureClass.textPage;
  }

  String get wireName {
    switch (this) {
      case CaptureClass.textPage:
        return 'text_page';
      case CaptureClass.diagram:
        return 'diagram';
      case CaptureClass.photoOnly:
        return 'photo_only';
    }
  }
}

/// Minimal Generative Language API client (AI Studio `AIza…` keys).
///
/// Classify uses [classifyModel] (lite); diagram uses [diagramModel].
/// Never logs the API key.
class GeminiClient {
  GeminiClient({
    required this.apiKey,
    this.classifyModel = GeminiSettings.defaultClassifyModel,
    this.diagramModel = GeminiSettings.defaultDiagramModel,
    http.Client? httpClient,
    this.baseUrl = 'https://generativelanguage.googleapis.com',
  }) : _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null;

  final String apiKey;
  final String classifyModel;
  final String diagramModel;
  final String baseUrl;
  final http.Client _http;
  final bool _ownsHttp;

  void close() {
    if (_ownsHttp) _http.close();
  }

  Uri _generateUri(String modelId) {
    final m = modelId.trim().isEmpty
        ? GeminiSettings.defaultClassifyModel
        : modelId;
    return Uri.parse(
      '$baseUrl/v1beta/models/$m:generateContent',
    ).replace(queryParameters: {'key': apiKey.trim()});
  }

  /// Tiny text call — pass/fail for Settings → Test Gemini (lite classify).
  Future<GeminiConnectionResult> verifyConnection() async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      return const GeminiConnectionResult(
        ok: false,
        message: 'API key is empty',
      );
    }
    final probeModel = classifyModel.trim().isEmpty
        ? GeminiSettings.defaultClassifyModel
        : classifyModel.trim();
    try {
      final text = await _generateText(
        modelId: probeModel,
        contents: [
          {
            'role': 'user',
            'parts': [
              {'text': 'Reply with exactly: ok'},
            ],
          },
        ],
        maxOutputTokens: 8,
      );
      final ok = text.toLowerCase().contains('ok');
      return GeminiConnectionResult(
        ok: ok,
        message: ok
            ? 'Connected — $probeModel responds'
            : 'Unexpected reply from Gemini',
      );
    } on GeminiException catch (e) {
      return GeminiConnectionResult(
        ok: false,
        message: e.readable,
        statusCode: e.statusCode,
      );
    } catch (e) {
      return GeminiConnectionResult(
        ok: false,
        message: _networkMessage(e),
      );
    }
  }

  /// Cheap vision classify → [CaptureClass].
  Future<CaptureClass> classifyPage({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final prompt =
        'Classify this paper photo. Reply with ONE token only:\n'
        'text_page — linear handwriting / notes\n'
        'diagram — mind map, boxed branches, visual map\n'
        'photo_only — drawing/photo with no extractable note structure\n'
        'No prose.';
    final text = await _generateText(
      modelId: classifyModel,
      contents: [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': mimeType,
                'data': base64Encode(imageBytes),
              },
            },
          ],
        },
      ],
      maxOutputTokens: 16,
    );
    return CaptureClass.parse(text);
  }

  /// Vision → Obsidian Canvas-shaped JSON (`nodes` / `edges`).
  ///
  /// Strips markdown fences; caller validates before vault write.
  Future<String> diagramCanvasJson({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    const system =
        'You read a hand-drawn mindmap PHOTO and return ONE JSON object only — '
        'no markdown fences, no prose. '
        'Schema matches Obsidian JSON Canvas: '
        '{"nodes":[{"id":"…","type":"text","text":"…","x":0,"y":0,'
        '"width":200,"height":80,"color":"1"}],'
        '"edges":[{"id":"e1","fromNode":"a","fromSide":"right",'
        '"toNode":"b","toSide":"left"}]}. '
        'Include every major labeled box (hub + branches). '
        'Edges should connect ideas (hierarchical OK). '
        'Do NOT invent a photo/file node — the app injects the page photo. '
        'Text ≤80 chars per node. Coordinates are Canvas pixels (may be '
        'negative). Prefer a clear hub near 0,0 with satellites around it.';
    return _generateText(
      modelId: diagramModel,
      contents: [
        {
          'role': 'user',
          'parts': [
            {'text': '$system\n\nReturn nodes/edges JSON only.'},
            {
              'inline_data': {
                'mime_type': mimeType,
                'data': base64Encode(imageBytes),
              },
            },
          ],
        },
      ],
      maxOutputTokens: 4096,
    );
  }

  Future<String> _generateText({
    required String modelId,
    required List<Map<String, Object?>> contents,
    int maxOutputTokens = 256,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const GeminiException(
        statusCode: 0,
        body: 'empty key',
        userMessage: 'Gemini API key is empty — add it in Settings → Gemini',
      );
    }
    final uri = _generateUri(modelId);
    final body = jsonEncode({
      'contents': contents,
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': maxOutputTokens,
      },
    });
    late final http.Response res;
    try {
      res = await _http
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              // Never put the key in logs; it is only in the query string.
            },
            body: body,
          )
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      throw GeminiException(
        statusCode: 0,
        body: '$e',
        userMessage: _networkMessage(e),
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw GeminiException(
        statusCode: res.statusCode,
        body: res.body,
        userMessage: _httpUserMessage(res.statusCode, res.body),
      );
    }
    return _extractText(res.body);
  }

  static String _extractText(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('not a map');
      }
      final candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) {
        throw const FormatException('no candidates');
      }
      final first = candidates.first;
      if (first is! Map) throw const FormatException('bad candidate');
      final content = first['content'];
      if (content is! Map) throw const FormatException('no content');
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) {
        throw const FormatException('no parts');
      }
      final buf = StringBuffer();
      for (final p in parts) {
        if (p is Map && p['text'] is String) {
          buf.write(p['text'] as String);
        }
      }
      return buf.toString().trim();
    } catch (e) {
      throw GeminiException(
        statusCode: 200,
        body: body.length > 400 ? '${body.substring(0, 400)}…' : body,
        userMessage: 'Gemini returned an unreadable response',
      );
    }
  }

  static String _httpUserMessage(int status, String body) {
    switch (status) {
      case 400:
        return 'Gemini rejected the request (HTTP 400) — check model id '
            '(classify: ${GeminiSettings.defaultClassifyModel}, '
            'diagram: ${GeminiSettings.defaultDiagramModel})';
      case 401:
      case 403:
        return 'Gemini rejected the API key (HTTP $status)';
      case 404:
        return 'Gemini model not found (HTTP 404) — try '
            '${GeminiSettings.defaultClassifyModel} or '
            '${GeminiSettings.defaultDiagramModel}';
      case 429:
        return 'Gemini rate limit — try again shortly (HTTP 429)';
      case >= 500:
        return 'Gemini server error (HTTP $status)';
      default:
        final snippet = body.length > 120 ? '${body.substring(0, 120)}…' : body;
        return 'Gemini failed (HTTP $status): $snippet';
    }
  }

  static String _networkMessage(Object e) {
    final s = '$e';
    if (s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('Network is unreachable')) {
      return 'No network — cannot reach Gemini';
    }
    if (s.contains('TimeoutException') || s.contains('timed out')) {
      return 'Gemini timed out — check connection and retry';
    }
    return 'Network error talking to Gemini: $s';
  }

  /// Strip ```json fences then return first balanced `{…}`.
  static String stripFencesAndSliceJson(String raw) {
    var t = raw.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
      t = t.replaceFirst(RegExp(r'\s*```\s*$'), '');
    }
    return MindmapPropose.sliceJsonObject(t) ?? t.trim();
  }
}

class GeminiException implements Exception {
  const GeminiException({
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
    return 'Gemini failed ($statusCode): $snippet';
  }
}
