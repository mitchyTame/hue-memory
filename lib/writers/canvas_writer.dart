import 'dart:convert';

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
  });

  final String id;
  final String type; // file | text | …
  final int x;
  final int y;
  final int width;
  final int height;
  final String? file;
  final String? text;

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
    return map;
  }
}

class CanvasEdge {
  const CanvasEdge({
    required this.id,
    required this.fromNode,
    required this.toNode,
    this.toEnd = 'arrow',
  });

  final String id;
  final String fromNode;
  final String toNode;
  final String toEnd;

  Map<String, Object?> toJson() => {
        'id': id,
        'fromNode': fromNode,
        'toNode': toNode,
        'toEnd': toEnd,
      };
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

/// Pure-Dart JSON Canvas 1.0 writer.
class CanvasWriter {
  const CanvasWriter();

  /// Build a canvas with the page photo as a file node (ink-ghost base)
  /// plus optional text nodes / edges from meaning extract.
  CanvasDocument buildVisualCanvas({
    required String sourceImage,
    required List<CanvasNode> textNodes,
    List<CanvasEdge> edges = const [],
    int imageWidth = 480,
    int imageHeight = 640,
  }) {
    final imageNode = CanvasNode(
      id: 'img',
      type: 'file',
      file: sourceImage,
      x: -800,
      y: -200,
      width: imageWidth,
      height: imageHeight,
    );
    return CanvasDocument(
      nodes: [imageNode, ...textNodes],
      edges: edges,
    );
  }

  String writeJson(CanvasDocument doc, {bool pretty = true}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(doc.toJson());
  }
}
