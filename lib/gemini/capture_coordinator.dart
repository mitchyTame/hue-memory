import 'dart:convert';
import 'dart:typed_data';

import '../capture/title_suggestion.dart';
import '../ocr/mistral_ocr_client.dart';
import '../ocr/ocr_client.dart';
import '../ocr/ocr_image_prepare.dart';
import '../writers/canvas_writer.dart';
import 'gemini_client.dart';
import 'gemini_settings.dart';
import 'obsidian_canvas_from_gemini.dart';

/// Routed capture ready for confirm UI.
class CoordinatedCapture {
  const CoordinatedCapture({
    required this.classification,
    required this.meaning,
    this.canvasTextNodes = const [],
    this.canvasEdges = const [],
    this.draftTitleSuggestion = '',
  });

  final CaptureClass classification;
  final MeaningResult meaning;
  final List<CanvasNode> canvasTextNodes;
  final List<CanvasEdge> canvasEdges;

  /// Optional draft — confirm still requires a manual title.
  final String draftTitleSuggestion;

  bool get isDiagram => classification == CaptureClass.diagram;
  bool get isPhotoOnly => classification == CaptureClass.photoOnly;
  bool get isTextPage => classification == CaptureClass.textPage;
}

/// Coordinator → specialists (Gemini Flash classify / diagram, Mistral OCR).
///
/// Symbol override: when [forceDiagram] is true (or legacy chip id `visual`),
/// never OCR-first — always take the diagram path. Prefer passing
/// [forceDiagram] from the pack symbol's capture type.
class CaptureCoordinator {
  CaptureCoordinator({
    required this.geminiSettings,
    required this.ocr,
    GeminiClient Function(GeminiSettings settings)? geminiFactory,
    ObsidianCanvasFromGemini canvasParser = const ObsidianCanvasFromGemini(),
    this.prepareImage,
  })  : _geminiFactory = geminiFactory ??
            ((s) => GeminiClient(apiKey: s.apiKey, model: s.model)),
        _canvasParser = canvasParser;

  final GeminiSettingsStore geminiSettings;
  final OcrClient ocr;
  final GeminiClient Function(GeminiSettings settings) _geminiFactory;
  final ObsidianCanvasFromGemini _canvasParser;
  final MistralOcrImagePreparer? prepareImage;

  /// [forceDiagram] from pack capture type / chip — skips OCR text path.
  ///
  /// Legacy: [forcedSymbolId] `visual` still forces diagram when
  /// [forceDiagram] is omitted.
  Future<CoordinatedCapture> run({
    required Uint8List imageBytes,
    String? imageMimeType,
    String? extensionHint,
    String? forcedSymbolId,
    bool? forceDiagram,
  }) async {
    final force = forceDiagram ?? (forcedSymbolId == 'visual');
    final geminiCfg = await geminiSettings.read();

    CaptureClass classification;
    if (force) {
      classification = CaptureClass.diagram;
    } else if (geminiCfg.shouldUseLive) {
      final client = _geminiFactory(geminiCfg);
      try {
        final prepared = await _prepare(
          imageBytes,
          imageMimeType: imageMimeType,
          extensionHint: extensionHint,
          maxSide: 1280,
        );
        classification = await client.classifyPage(
          imageBytes: prepared.bytes,
          mimeType: prepared.mime,
        );
      } finally {
        client.close();
      }
    } else {
      // Offline / no Gemini: OCR path (mock or Mistral) — never invent diagram.
      classification = CaptureClass.textPage;
    }

    switch (classification) {
      case CaptureClass.diagram:
        return _diagramPath(
          imageBytes: imageBytes,
          imageMimeType: imageMimeType,
          extensionHint: extensionHint,
          geminiCfg: geminiCfg,
          forced: force,
        );
      case CaptureClass.photoOnly:
        return _photoOnlyPath();
      case CaptureClass.textPage:
        return _textPath(
          imageBytes: imageBytes,
          imageMimeType: imageMimeType,
          extensionHint: extensionHint,
        );
    }
  }

  Future<CoordinatedCapture> _textPath({
    required Uint8List imageBytes,
    String? imageMimeType,
    String? extensionHint,
  }) async {
    final meaning = await ocr.extractMeaning(
      imageBytes,
      imageMimeType: imageMimeType,
      extensionHint: extensionHint,
    );
    // Coordinator owns genre for routing; keep OCR glyph for symbol seed.
    final normalized = MeaningResult(
      detectedGlyph: meaning.detectedGlyph,
      regions: meaning.regions,
      pageGenre: 'text',
      threadTick: meaning.threadTick,
      rawJson: {
        ...meaning.rawJson,
        'route': CaptureClass.textPage.wireName,
        'coordinator': 'v2',
      },
    );
    final full = normalized.rawJson['full_markdown'];
    final suggestion = full is String
        ? TitleSuggestion.fromOcrMarkdown(full)
        : '';
    return CoordinatedCapture(
      classification: CaptureClass.textPage,
      meaning: normalized,
      draftTitleSuggestion: suggestion,
    );
  }

  Future<CoordinatedCapture> _photoOnlyPath() async {
    const meaning = MeaningResult(
      detectedGlyph: '○',
      regions: [],
      pageGenre: 'photo_only',
      rawJson: {
        'route': 'photo_only',
        'coordinator': 'v2',
        'ghost_only': true,
      },
    );
    return const CoordinatedCapture(
      classification: CaptureClass.photoOnly,
      meaning: meaning,
    );
  }

  Future<CoordinatedCapture> _diagramPath({
    required Uint8List imageBytes,
    String? imageMimeType,
    String? extensionHint,
    required GeminiSettings geminiCfg,
    required bool forced,
  }) async {
    if (!geminiCfg.shouldUseLive) {
      // No Gemini: empty editable nodes — confirm can still save ghost + labels.
      return CoordinatedCapture(
        classification: CaptureClass.diagram,
        meaning: MeaningResult(
          detectedGlyph: '△',
          regions: const [
            OcrRegion(
              id: 'n1',
              text: '',
              confidence: 0.4,
              bbox: [0.3, 0.3, 0.4, 0.12],
            ),
          ],
          pageGenre: 'visual',
          rawJson: {
            'route': 'diagram',
            'coordinator': 'v2',
            'gemini_used': false,
            'forced_symbol': forced,
            'hint': 'Add Gemini key for Flash diagram structure',
          },
        ),
        draftTitleSuggestion: '',
      );
    }

    final client = _geminiFactory(geminiCfg);
    try {
      final prepared = await _prepare(
        imageBytes,
        imageMimeType: imageMimeType,
        extensionHint: extensionHint,
        maxSide: kVisionMaxImageSide,
      );
      final raw = await client.diagramCanvasJson(
        imageBytes: prepared.bytes,
        mimeType: prepared.mime,
      );
      final draft = _canvasParser.parse(raw);
      final meaning = MeaningResult(
        detectedGlyph: '△',
        regions: draft.regions,
        pageGenre: 'visual',
        rawJson: {
          'route': 'diagram',
          'coordinator': 'v2',
          'gemini_used': true,
          'gemini_model': geminiCfg.model,
          'forced_symbol': forced,
          'canvas_nodes': [
            for (final n in draft.textNodes) n.toJson(),
          ],
          'canvas_edges': [
            for (final e in draft.edges) e.toJson(),
          ],
        },
      );
      return CoordinatedCapture(
        classification: CaptureClass.diagram,
        meaning: meaning,
        canvasTextNodes: draft.textNodes,
        canvasEdges: draft.edges,
        draftTitleSuggestion: TitleSuggestion.sanitize(draft.suggestedTitle),
      );
    } finally {
      client.close();
    }
  }

  Future<PreparedOcrImage> _prepare(
    Uint8List bytes, {
    String? imageMimeType,
    String? extensionHint,
    int maxSide = kOcrMaxImageSide,
  }) {
    final prep = prepareImage ?? prepareImageForMistralOcr;
    return prep(
      bytes,
      imageMimeType: imageMimeType,
      extensionHint: extensionHint,
      maxSide: maxSide,
    );
  }

  /// Re-hydrate canvas nodes/edges from [MeaningResult.rawJson] after edits.
  static ({List<CanvasNode> nodes, List<CanvasEdge> edges})?
      canvasFromMeaning(MeaningResult meaning) {
    final nodesRaw = meaning.rawJson['canvas_nodes'];
    final edgesRaw = meaning.rawJson['canvas_edges'];
    if (nodesRaw is! List || nodesRaw.isEmpty) return null;
    final nodes = <CanvasNode>[];
    for (final item in nodesRaw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final id = '${m['id'] ?? ''}'.trim();
      final text = '${m['text'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      nodes.add(
        CanvasNode(
          id: id,
          type: '${m['type'] ?? 'text'}',
          text: text,
          x: m['x'] is num ? (m['x'] as num).round() : 0,
          y: m['y'] is num ? (m['y'] as num).round() : 0,
          width: m['width'] is num ? (m['width'] as num).round() : 200,
          height: m['height'] is num ? (m['height'] as num).round() : 80,
          color: m['color']?.toString(),
          file: m['file']?.toString(),
        ),
      );
    }
    if (nodes.isEmpty) return null;
    final edges = <CanvasEdge>[];
    if (edgesRaw is List) {
      for (var i = 0; i < edgesRaw.length; i++) {
        final item = edgesRaw[i];
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final from = '${m['fromNode'] ?? ''}'.trim();
        final to = '${m['toNode'] ?? ''}'.trim();
        if (from.isEmpty || to.isEmpty) continue;
        edges.add(
          CanvasEdge(
            id: '${m['id'] ?? 'e${i + 1}'}',
            fromNode: from,
            toNode: to,
            fromSide: m['fromSide']?.toString(),
            toSide: m['toSide']?.toString(),
            toEnd: '${m['toEnd'] ?? 'arrow'}',
          ),
        );
      }
    }
    final edited = ObsidianCanvasFromGemini.applyLabelEdits(
      textNodes: nodes,
      edited: meaning.regions,
    );
    // Edges as stored from Gemini — no heuristic / ensureConnected tidy.
    return (nodes: edited, edges: edges);
  }

  /// Debug helper — never call with real keys in tests that print.
  static String describeRoute(CoordinatedCapture c) =>
      jsonEncode({
        'class': c.classification.wireName,
        'genre': c.meaning.pageGenre,
        'nodes': c.meaning.regions.length,
      });
}
