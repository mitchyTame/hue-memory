import 'dart:convert';
import 'dart:math' as math;

import '../ocr/ocr_client.dart';
import '../writers/canvas_writer.dart';
import 'gemini_client.dart';

/// Parsed Gemini diagram → Obsidian Canvas with center ink-ghost file node.
class GeminiCanvasDraft {
  const GeminiCanvasDraft({
    required this.textNodes,
    required this.edges,
    required this.regions,
    this.suggestedTitle = '',
  });

  final List<CanvasNode> textNodes;
  final List<CanvasEdge> edges;

  /// Label list for confirm UI (bbox optional / ring-derived).
  final List<OcrRegion> regions;
  final String suggestedTitle;
}

/// Build / validate Obsidian-shaped Canvas from Gemini Flash JSON.
class ObsidianCanvasFromGemini {
  const ObsidianCanvasFromGemini();

  /// Parse model JSON; commit injects the real photo file node path.
  GeminiCanvasDraft parse(String raw) {
    final sliced = GeminiClient.stripFencesAndSliceJson(raw);
    if (sliced.trim().isEmpty) {
      throw const FormatException('Gemini canvas JSON empty');
    }
    final decoded = jsonDecode(sliced);
    if (decoded is! Map) {
      throw const FormatException('Gemini canvas JSON must be an object');
    }
    final map = Map<String, dynamic>.from(decoded);
    final nodesRaw = map['nodes'];
    final edgesRaw = map['edges'];
    if (nodesRaw is! List || nodesRaw.isEmpty) {
      throw const FormatException('Gemini canvas needs a non-empty nodes list');
    }

    final parsed = <({CanvasNode node, bool hasCoords})>[];
    final seen = <String>{};
    for (var i = 0; i < nodesRaw.length && parsed.length < 24; i++) {
      final item = nodesRaw[i];
      if (item is! Map) continue;
      final type = '${item['type'] ?? 'text'}'.toLowerCase();
      // Skip any file nodes — app owns the ink-ghost photo.
      if (type == 'file') continue;
      final text = '${item['text'] ?? item['label'] ?? ''}'.trim();
      if (text.isEmpty) continue;
      var id = '${item['id'] ?? 'n${parsed.length + 1}'}'.trim();
      if (id.isEmpty || id == 'img' || id == 'ghost') {
        id = 'n${parsed.length + 1}';
      }
      if (!seen.add(id)) {
        id = '${id}_${parsed.length + 1}';
        seen.add(id);
      }
      final hasCoords = item['x'] is num || item['y'] is num;
      parsed.add((
        node: CanvasNode(
          id: id,
          type: 'text',
          text: text,
          x: item['x'] is num ? (item['x'] as num).round() : 0,
          y: item['y'] is num ? (item['y'] as num).round() : 0,
          width: _dim(item['width'], fallback: 200, min: 120, max: 420),
          height: _dim(item['height'], fallback: 80, min: 48, max: 280),
          color: item['color']?.toString(),
        ),
        hasCoords: hasCoords,
      ));
    }
    if (parsed.isEmpty) {
      throw const FormatException('No text nodes in Gemini canvas JSON');
    }

    final needsLayout = parsed.every((p) => !p.hasCoords) ||
        parsed.every((p) => p.node.x == 0 && p.node.y == 0);
    final textNodes = needsLayout
        ? ringLayout(parsed.map((p) => p.node).toList())
        : parsed.map((p) => p.node).toList();

    final edges = _parseEdges(edgesRaw, textNodes.map((n) => n.id).toSet());
    final connected = ensureConnected(textNodes, edges);

    final regions = <OcrRegion>[
      for (var i = 0; i < textNodes.length; i++)
        OcrRegion(
          id: textNodes[i].id,
          text: textNodes[i].text ?? '',
          confidence: 0.85,
          bbox: _bboxHint(i, textNodes.length),
        ),
    ];

    final title = (textNodes.first.text ?? '').trim();
    final suggested =
        title.length <= 48 ? title : '${title.substring(0, 45)}…';

    return GeminiCanvasDraft(
      textNodes: textNodes,
      edges: connected,
      regions: regions,
      suggestedTitle: suggested,
    );
  }

  /// Merge confirm label edits onto draft text nodes; keep geometry.
  static List<CanvasNode> applyLabelEdits({
    required List<CanvasNode> textNodes,
    required List<OcrRegion> edited,
  }) {
    final byId = {for (final r in edited) r.id: r.text};
    return [
      for (final n in textNodes)
        CanvasNode(
          id: n.id,
          type: n.type,
          text: byId.containsKey(n.id) ? byId[n.id] : n.text,
          x: n.x,
          y: n.y,
          width: n.width,
          height: n.height,
          color: n.color,
        ),
    ];
  }

  /// Hub-ring layout when the model returns ordered nodes without coords.
  static List<CanvasNode> ringLayout(List<CanvasNode> nodes) {
    if (nodes.isEmpty) return nodes;
    final hub = nodes.first;
    final placed = <CanvasNode>[
      CanvasNode(
        id: hub.id,
        type: 'text',
        text: hub.text,
        x: -hub.width ~/ 2,
        y: -hub.height ~/ 2,
        width: hub.width,
        height: hub.height,
        color: hub.color ?? '1',
      ),
    ];
    if (nodes.length == 1) return placed;

    const radius = 420.0;
    final spokes = nodes.length - 1;
    for (var i = 1; i < nodes.length; i++) {
      final n = nodes[i];
      final angle = -math.pi / 2 + (2 * math.pi * (i - 1) / spokes);
      final cx = (radius * math.cos(angle)).round();
      final cy = (radius * math.sin(angle)).round();
      placed.add(
        CanvasNode(
          id: n.id,
          type: 'text',
          text: n.text,
          x: cx - n.width ~/ 2,
          y: cy - n.height ~/ 2,
          width: n.width,
          height: n.height,
          color: n.color,
        ),
      );
    }
    return placed;
  }

  /// Ensure every non-hub text node is linked; add hub→orphan edges.
  static List<CanvasEdge> ensureConnected(
    List<CanvasNode> textNodes,
    List<CanvasEdge> edges,
  ) {
    if (textNodes.length < 2) return edges;
    final hubId = textNodes.first.id;
    final ids = textNodes.map((n) => n.id).toSet();
    final linked = <String>{hubId};
    for (final e in edges) {
      if (ids.contains(e.fromNode) && ids.contains(e.toNode)) {
        linked.add(e.fromNode);
        linked.add(e.toNode);
      }
    }
    final out = List<CanvasEdge>.from(edges);
    var i = out.length;
    for (final n in textNodes.skip(1)) {
      if (linked.contains(n.id)) continue;
      i++;
      out.add(
        CanvasEdge(
          id: 'e_hub_$i',
          fromNode: hubId,
          toNode: n.id,
        ),
      );
      linked.add(n.id);
    }
    if (out.isEmpty) {
      for (var k = 1; k < textNodes.length; k++) {
        out.add(
          CanvasEdge(
            id: 'e$k',
            fromNode: hubId,
            toNode: textNodes[k].id,
          ),
        );
      }
    }
    return out;
  }

  static List<CanvasEdge> _parseEdges(Object? edgesRaw, Set<String> ids) {
    final edges = <CanvasEdge>[];
    if (edgesRaw is! List) return edges;
    for (var i = 0; i < edgesRaw.length; i++) {
      final item = edgesRaw[i];
      if (item is! Map) continue;
      final from = '${item['fromNode'] ?? item['from'] ?? ''}'.trim();
      final to = '${item['toNode'] ?? item['to'] ?? ''}'.trim();
      if (from.isEmpty || to.isEmpty || from == to) continue;
      if (!ids.contains(from) || !ids.contains(to)) continue;
      edges.add(
        CanvasEdge(
          id: '${item['id'] ?? 'e${i + 1}'}',
          fromNode: from,
          toNode: to,
          fromSide: item['fromSide']?.toString(),
          toSide: item['toSide']?.toString(),
        ),
      );
    }
    return edges;
  }

  static int _dim(
    Object? v, {
    required int fallback,
    required int min,
    required int max,
  }) {
    if (v is num) {
      return v.round().clamp(min, max);
    }
    return fallback;
  }

  static List<double> _bboxHint(int index, int total) {
    final slot = index / math.max(1, total);
    return [0.12, 0.10 + slot * 0.7, 0.36, 0.08];
  }
}
