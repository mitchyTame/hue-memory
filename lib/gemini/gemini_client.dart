import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';
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

/// Builds a [GenerativeModel] for a model id (tests may inject).
typedef GeminiModelFactory = GenerativeModel Function({
  required String model,
  required String apiKey,
  GenerationConfig? generationConfig,
  http.Client? httpClient,
});

/// Gemini client via [google_generative_ai] (AI Studio `AIza…` keys).
///
/// [model] is shared for classify, diagram, and Test Gemini.
/// Never logs the API key. No hand-rolled generateContent JSON.
class GeminiClient {
  GeminiClient({
    required this.apiKey,
    this.model = GeminiSettings.defaultModel,
    String? classifyModel,
    String? diagramModel,
    http.Client? httpClient,
    GeminiModelFactory? modelFactory,
  })  : classifyModel = classifyModel ?? model,
        diagramModel = diagramModel ?? model,
        _http = httpClient,
        _modelFactory = modelFactory ?? _defaultModelFactory;

  final String apiKey;
  final String model;
  final String classifyModel;
  final String diagramModel;
  final http.Client? _http;
  final GeminiModelFactory _modelFactory;

  static GenerativeModel _defaultModelFactory({
    required String model,
    required String apiKey,
    GenerationConfig? generationConfig,
    http.Client? httpClient,
  }) {
    return GenerativeModel(
      model: model,
      apiKey: apiKey,
      generationConfig: generationConfig,
      httpClient: httpClient,
    );
  }

  void close() {
    // Package creates per-model clients; nothing to dispose here.
  }

  GenerativeModel _modelFor(String modelId, {int? maxOutputTokens}) {
    final id = modelId.trim().isEmpty ? GeminiSettings.defaultModel : modelId;
    return _modelFactory(
      model: id,
      apiKey: apiKey.trim(),
      generationConfig: GenerationConfig(
        temperature: 0.2,
        maxOutputTokens: maxOutputTokens,
      ),
      httpClient: _http,
    );
  }

  /// Tiny text call — pass/fail for Settings → Test Gemini.
  Future<GeminiConnectionResult> verifyConnection() async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      return const GeminiConnectionResult(
        ok: false,
        message: 'API key is empty',
      );
    }
    final probeModel =
        model.trim().isEmpty ? GeminiSettings.defaultModel : model.trim();
    try {
      final text = await _generate(
        modelId: probeModel,
        contents: [Content.text('Reply with exactly: ok')],
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
        message: _mapError(e),
      );
    }
  }

  /// Cheap vision classify → [CaptureClass].
  Future<CaptureClass> classifyPage({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    const prompt =
        'Classify this paper photo. Reply with ONE token only:\n'
        'text_page — linear handwriting / notes\n'
        'diagram — mind map, boxed branches, visual map\n'
        'photo_only — drawing/photo with no extractable note structure\n'
        'No prose.';
    final text = await _generate(
      modelId: classifyModel,
      contents: [
        Content.multi([
          TextPart(prompt),
          DataPart(mimeType, imageBytes),
        ]),
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
    const prompt =
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
        'negative). Prefer a clear hub near 0,0 with satellites around it.\n\n'
        'Return nodes/edges JSON only.';
    return _generate(
      modelId: diagramModel,
      contents: [
        Content.multi([
          TextPart(prompt),
          DataPart(mimeType, imageBytes),
        ]),
      ],
      maxOutputTokens: 4096,
    );
  }

  Future<String> _generate({
    required String modelId,
    required Iterable<Content> contents,
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
    try {
      final generative = _modelFor(modelId, maxOutputTokens: maxOutputTokens);
      final response = await generative.generateContent(contents);
      final text = response.text?.trim() ?? '';
      if (text.isEmpty) {
        throw const GeminiException(
          statusCode: 200,
          body: 'empty text',
          userMessage: 'Gemini returned an empty response',
        );
      }
      return text;
    } on GeminiException {
      rethrow;
    } on InvalidApiKey catch (e) {
      throw GeminiException(
        statusCode: 401,
        body: e.message,
        userMessage: 'Gemini rejected the API key',
      );
    } on UnsupportedUserLocation {
      throw const GeminiException(
        statusCode: 403,
        body: 'unsupported location',
        userMessage: 'Gemini is not available in this location',
      );
    } on ServerException catch (e) {
      throw GeminiException(
        statusCode: 500,
        body: e.message,
        userMessage: _serverUserMessage(e.message),
      );
    } on GenerativeAIException catch (e) {
      throw GeminiException(
        statusCode: 0,
        body: e.message,
        userMessage: _mapError(e),
      );
    } catch (e) {
      throw GeminiException(
        statusCode: 0,
        body: '$e',
        userMessage: _mapError(e),
      );
    }
  }

  static String _serverUserMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('not found') || lower.contains('404')) {
      return 'Gemini model not found — try ${GeminiSettings.defaultModel} '
          'or ${GeminiSettings.flash36Model}';
    }
    if (lower.contains('rate') || lower.contains('429')) {
      return 'Gemini rate limit — try again shortly';
    }
    if (lower.contains('api key') || lower.contains('permission')) {
      return 'Gemini rejected the API key';
    }
    return 'Gemini server error: $message';
  }

  static String _mapError(Object e) {
    final s = '$e';
    if (s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('Network is unreachable')) {
      return 'No network — cannot reach Gemini';
    }
    if (s.contains('TimeoutException') || s.contains('timed out')) {
      return 'Gemini timed out — check connection and retry';
    }
    // SDK may FormatException-decode a large HTML/error body ("line N, char M").
    if (e is FormatException || s.contains('FormatException')) {
      return 'Gemini returned unreadable data — check API key, model, and network';
    }
    if (e is GenerativeAIException) return e.message;
    return 'Gemini error: $s';
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
