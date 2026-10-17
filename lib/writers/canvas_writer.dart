import 'dart:convert';
import 'dart:math' as math;

import '../ocr/ocr_client.dart';

/// A JSON Canvas 1.0 node (subset used by hue-memory).
class CanvasNode {
  const CanvasNode({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.file,
    this.text,
    this.color,
  });

  final String id;
  final String type; // file | text | …
  final int x;
  final int y;
  final int width;
  final int height;
  final String? file;
  final String? text;

  /// Optional JSON Canvas color (hex without `#`, or Obsidian preset `"1"`…`"6"`).
  final String? color;

  Map<String, Object?> toJson() {
    final map = <String, Object?>{
      'id': id,
      'type': type,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
    if (file != null) map['file'] = file;
    if (text != null) map['text'] = text;
    if (color != null) map['color'] = color;
    return map;
  }
}

class CanvasEdge {
  const CanvasEdge({
    required this.id,
    required this.fromNode,
    required this.toNode,
    this.toEnd = 'arrow',
    this.fromSide,
    this.toSide,
  });

  final String id;
  final String fromNode;
  final String toNode;
  final String toEnd;

  /// Optional Obsidian side: top | right | bottom | left.
  final String? fromSide;
  final String? toSide;

  Map<String, Object?> toJson() {
    final map = <String, Object?>{
      'id': id,
      'fromNode': fromNode,
      'toNode': toNode,
      'toEnd': toEnd,
    };
    if (fromSide != null) map['fromSide'] = fromSide;
    if (toSide != null) map['toSide'] = toSide;
    return map;
  }
}

class CanvasDocument {
  const CanvasDocument({
    required this.nodes,
    this.edges = const [],
  });

  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;

  Map<String, Object?> toJson() => {
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
      };
}

/// Pure-Dart JSON Canvas 1.0 writer with ink-ghost layout helpers.
class CanvasWriter {
  const CanvasWriter();

  /// Default canvas frame for the page photo file node.
  static const int defaultImageWidth = 480;
  static const int defaultImageHeight = 640;
  static const int defaultImageX = 0;
  static const int defaultImageY = 0;

  /// Soft paper-tint preset so the ghost reads quieter than text cards.
  static const String ghostImageColor = '4';

  /// Build a canvas with the page photo as a file node (ink-ghost base)
  /// plus optional text nodes / edges from meaning extract.
  ///
  /// When [inkGhost] is true (default), the image node is listed first so
  /// editable text sits above the paper in Obsidian Canvas. JSON Canvas has
  /// no opacity field — the ghost effect is dual-coding (photo under nodes)
  /// plus the in-app confirm toggle.
  CanvasDocument buildVisualCanvas({
    required String sourceImage,
    required List<CanvasNode> textNodes,
    List<CanvasEdge> edges = const [],
    int imageWidth = defaultImageWidth,
    int imageHeight = defaultImageHeight,
    int imageX = defaultImageX,
    int imageY = defaultImageY,
    bool inkGhost = true,
    String? hierarchicalTags,
    bool allowEmptyText = false,
  }) {
    final imageNode = CanvasNode(
      id: 'img',
      type: 'file',
      file: sourceImage,
      x: imageX,
      y: imageY,
      width: imageWidth,
      height: imageHeight,
      color: inkGhost ? ghostImageColor : null,
    );
    final tagsNode = allowEmptyText
        ? null
        : _tagsNode(
            hierarchicalTags,
            imageX: imageX,
            imageY: imageY,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
          );
    final text = tagsNode == null ? textNodes : [...textNodes, tagsNode];
    // Image first = under; ghost off still keeps the photo for dual coding,
    // but appends it after text so cards read as primary in Obsidian.
    final nodes = inkGhost
        ? <CanvasNode>[imageNode, ...text]
        : <CanvasNode>[...text, imageNode];
    return CanvasDocument(nodes: nodes, edges: edges);
  }

  /// Diagram layout: center ink-ghost file node + satellite text nodes.
  ///
  /// Places the photo at the centroid of [textNodes] (or 0,0) so Gemini
  /// absolute Canvas coords stay meaningful.
  CanvasDocument buildDiagramCanvas({
    required String sourceImage,
    required List<CanvasNode> textNodes,
    List<CanvasEdge> edges = const [],
    bool inkGhost = true,
    String? hierarchicalTags,
    int imageWidth = defaultImageWidth,
    int imageHeight = defaultImageHeight,
  }) {
    var cx = 0;
    var cy = 0;
    if (textNodes.isNotEmpty) {
      var sx = 0;
      var sy = 0;
      for (final n in textNodes) {
        sx += n.x + n.width ~/ 2;
        sy += n.y + n.height ~/ 2;
      }
      cx = sx ~/ textNodes.length;
      cy = sy ~/ textNodes.length;
    }
    final imageX = cx - imageWidth ~/ 2;
    final imageY = cy - imageHeight ~/ 2;
    return buildVisualCanvas(
      sourceImage: sourceImage,
      textNodes: textNodes,
      edges: edges,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      imageX: imageX,
      imageY: imageY,
      inkGhost: inkGhost,
      hierarchicalTags: hierarchicalTags,
      allowEmptyText: textNodes.isEmpty,
    );
  }

  /// Optional tags card below the image frame (△ has no companion `.md`).
  static CanvasNode? _tagsNode(
    String? hierarchicalTags, {
    required int imageX,
    required int imageY,
    required int imageWidth,
    required int imageHeight,
  }) {
    final line = hierarchicalTags?.trim() ?? '';
    if (line.isEmpty) return null;
    return CanvasNode(
      id: 'tags',
      type: 'text',
      text: line,
      x: imageX,
      y: imageY + imageHeight + 16,
      width: math.max(220, imageWidth),
      height: 64,
      color: '5',
    );
  }

  /// Map normalized OCR bboxes `[left, top, width, height]` (0–1) onto the
  /// image file-node frame so paper topology survives into `.canvas`.
  static List<CanvasNode> nodesFromRegions(
    List<OcrRegion> regions, {
    int imageWidth = defaultImageWidth,
    int imageHeight = defaultImageHeight,
    int imageX = defaultImageX,
    int imageY = defaultImageY,
    int minWidth = 120,
    int minHeight = 48,
  }) {
    final nodes = <CanvasNode>[];
    for (var i = 0; i < regions.length; i++) {
      final r = regions[i];
      final bbox = r.bbox;
      final left = bbox != null && bbox.length >= 4 ? bbox[0] : 0.1;
      final top = bbox != null && bbox.length >= 4
          ? bbox[1]
          : 0.12 + i * 0.14;
      final w = bbox != null && bbox.length >= 4 ? bbox[2] : 0.5;
      final h = bbox != null && bbox.length >= 4 ? bbox[3] : 0.1;
      final id = r.id.isNotEmpty ? r.id : 'n${i + 1}';
      nodes.add(
        CanvasNode(
          id: id,
          type: 'text',
          text: r.text,
          x: imageX + (left * imageWidth).round(),
          y: imageY + (top * imageHeight).round(),
          width: math
              .max(minWidth, (w * imageWidth).round())
              .clamp(minWidth, imageWidth),
          height: math
              .max(minHeight, (h * imageHeight).round())
              .clamp(minHeight, imageHeight),
        ),
      );
    }
    return nodes;
  }

  /// Conservative hub→spoke edges for hybrid mindmaps.
  ///
  /// Skips when fewer than two text nodes (uncertain / single label). Mitch
  /// can fix links in Obsidian — we do not invent arrow OCR.
  static List<CanvasEdge> heuristicEdges(List<CanvasNode> textNodes) {
    final usable = textNodes
        .where((n) => (n.text ?? '').trim().isNotEmpty)
        .toList();
    if (usable.length < 2) return const [];
    final hub = usable.first;
    final edges = <CanvasEdge>[];
    for (var i = 1; i < usable.length; i++) {
      edges.add(
        CanvasEdge(
          id: 'e$i',
          fromNode: hub.id,
          toNode: usable[i].id,
        ),
      );
    }
    return edges;
  }

  String writeJson(CanvasDocument doc, {bool pretty = true}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(doc.toJson());
  }
}
