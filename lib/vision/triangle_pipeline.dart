import 'dart:typed_data';

import 'package:mistralai_dart/mistralai_dart.dart';

import '../ocr/mistral_sdk.dart';
import '../ocr/ocr_client.dart';
import '../writers/canvas_writer.dart';
import '../writers/mindmap_propose.dart';
import 'deskew.dart';
import 'image_crop.dart';
import 'region_proposals.dart';

/// Assembled △ mindmap ready for confirm / canvas commit.
class TrianglePipelineResult {
  const TrianglePipelineResult({
    required this.regions,
    required this.edges,
    required this.meta,
  });

  final List<OcrRegion> regions;
  final List<CanvasEdge> edges;
  final Map<String, Object?> meta;
}

/// △-only pipeline: deskew → OCR blocks → micro-crop OCR → in-app canvas.
///
/// Node placement uses real `{x,y,w,h}` from OCR blocks / contours — the LLM
/// is **not** required to place nodes. Optional [guessEdges] may call
/// [kDefaultVisionModel] (`mistral-large-2512`) for edge guesses only.
class TrianglePipeline {
  TrianglePipeline({
    required MistralSdk sdk,
    this.ocrModel = 'mistral-ocr-latest',
    this.visionModel = 'mistral-large-2512',
    this.deskew = const ImageDeskew(),
    this.proposals = const RegionProposals(),
    this.cropper = const ImageCrop(),
    this.maxMicroCrops = 8,
    this.guessEdges = true,
  }) : _sdk = sdk;

  final MistralSdk _sdk;
  final String ocrModel;
  final String visionModel;
  final ImageDeskew deskew;
  final RegionProposals proposals;
  final ImageCrop cropper;
  final int maxMicroCrops;
  final bool guessEdges;

  /// Run on an already-prepared full-page image (PNG preferred).
  Future<TrianglePipelineResult> run({
    required Uint8List preparedBytes,
    required String mime,
    required Future<OcrResponse> Function({
      required Uint8List bytes,
      required String mimeType,
      bool includeBlocks,
    }) ocrCall,
    Future<String> Function({
      required Uint8List bytes,
      required String mimeType,
      required List<String> nodeSummaries,
    })? edgeCall,
  }) async {
    final skewed = deskew.deskewPng(preparedBytes, mime: mime);
    final pageBytes = skewed.bytes;
    final pageMime = skewed.mime;

    final pageOcr = await ocrCall(
      bytes: pageBytes,
      mimeType: pageMime,
      includeBlocks: true,
    );

    var regions = proposals.fromOcrResponse(
      pageOcr,
      imageBytesForContourFallback: pageBytes,
    );

    // Fallback: markdown labels with radial layout when no boxes found.
    if (regions.isEmpty) {
      final md = pageOcr.pages.map((p) => p.markdown).join('\n');
      final structure = MindmapPropose.structureFromOcrMarkdown(md);
      final laid = MindmapPropose.regionsFromStructure(structure);
      return TrianglePipelineResult(
        regions: laid,
        edges: CanvasWriter.heuristicEdges(
          CanvasWriter.nodesFromRegions(laid),
        ),
        meta: {
          'pipeline': 'triangle_v1',
          'deskew_deg': skewed.angleDegrees,
          'deskew_applied': skewed.applied,
          'proposal_source': 'heuristic',
          'micro_ocr_count': 0,
          'edges_source': 'heuristic',
        },
      );
    }

    // Micro-crop OCR for accurate handwriting on each box.
    final refined = <OcrRegion>[];
    var microCount = 0;
    for (var i = 0; i < regions.length && i < maxMicroCrops; i++) {
      final p = regions[i];
      var text = p.hintText;
      final cropBytes = cropper.cropNorm(pageBytes, bbox: p.bbox);
      if (cropBytes != null) {
        try {
          final cropOcr = await ocrCall(
            bytes: cropBytes,
            mimeType: 'image/png',
            includeBlocks: false,
          );
          final cropText = cropOcr.pages
              .map((pg) => pg.markdown.trim())
              .where((t) => t.isNotEmpty)
              .join(' ');
          final clipped = MindmapPropose.clipLabel(
            cropText.replaceAll(RegExp(r'\s+'), ' '),
          );
          if (clipped.isNotEmpty) {
            text = clipped;
            microCount++;
          }
        } catch (_) {
          // Keep hint text.
        }
      }
      if (text.trim().isEmpty) continue;
      refined.add(
        OcrRegion(
          id: p.id,
          text: text,
          confidence: p.source == 'ocr_block' ? 0.9 : 0.75,
          bbox: p.bbox,
        ),
      );
    }

    // Any leftover proposals beyond micro-crop budget keep hint text.
    for (var i = maxMicroCrops; i < regions.length; i++) {
      final p = regions[i];
      if (p.hintText.trim().isEmpty) continue;
      refined.add(
        OcrRegion(
          id: p.id,
          text: p.hintText,
          confidence: 0.7,
          bbox: p.bbox,
        ),
      );
    }

    if (refined.isEmpty) {
      final md = pageOcr.pages.map((p) => p.markdown).join('\n');
      final structure = MindmapPropose.structureFromOcrMarkdown(md);
      return TrianglePipelineResult(
        regions: MindmapPropose.regionsFromStructure(structure),
        edges: const [],
        meta: {
          'pipeline': 'triangle_v1',
          'deskew_deg': skewed.angleDegrees,
          'proposal_source': regions.first.source,
          'micro_ocr_count': microCount,
          'edges_source': 'none',
        },
      );
    }

    var edges = CanvasWriter.heuristicEdges(
      CanvasWriter.nodesFromRegions(refined),
    );
    var edgesSource = 'heuristic';

    if (guessEdges && edgeCall != null && refined.length >= 2) {
      try {
        final summaries = [
          for (final r in refined) '${r.id}:${r.text}',
        ];
        final raw = await edgeCall(
          bytes: pageBytes,
          mimeType: pageMime,
          nodeSummaries: summaries,
        );
        final parsed = MindmapStructure.parseJson(raw);
        final ids = refined.map((r) => r.id).toSet();
        final guessed = <CanvasEdge>[];
        for (var i = 0; i < parsed.edges.length; i++) {
          final e = parsed.edges[i];
          if (!ids.contains(e.from) || !ids.contains(e.to)) continue;
          guessed.add(
            CanvasEdge(id: 'e${i + 1}', fromNode: e.from, toNode: e.to),
          );
        }
        if (guessed.isNotEmpty) {
          edges = guessed;
          edgesSource = 'vision_edges';
        }
      } catch (_) {
        // Keep heuristic edges.
      }
    }

    return TrianglePipelineResult(
      regions: refined,
      edges: edges,
      meta: {
        'pipeline': 'triangle_v1',
        'deskew_deg': skewed.angleDegrees,
        'deskew_applied': skewed.applied,
        'proposal_source': regions.first.source,
        'proposal_count': regions.length,
        'micro_ocr_count': microCount,
        'edges_source': edgesSource,
        'vision_model': visionModel,
        'ocr_model': ocrModel,
      },
    );
  }

  /// System prompt for optional edge-only vision (nodes already placed).
  static const edgeSystemPrompt =
      'You connect mindmap nodes. Reply with ONE JSON object only. '
      'Schema: {"nodes":[],"edges":[{"from":"id","to":"id"}]}. '
      'Use only the given node ids. Add an edge only when a clear ink line '
      'connects two boxes. Omit uncertain edges. No prose.';

  static String edgeUserPrompt(List<String> nodeSummaries) =>
      'Nodes (id:label):\n${nodeSummaries.join('\n')}\n'
      'Return edges JSON only.';
}
