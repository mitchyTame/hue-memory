import '../ocr/ocr_client.dart';
import 'canvas_writer.dart';

/// Builds nested Obsidian tags from mindmap hub→spoke structure.
///
/// Example: hub "Psychology" → "Memory" → "Encoding" yields
/// `#psychology`, `#psychology/memory`, `#psychology/memory/encoding`.
class TagBuilder {
  const TagBuilder();

  static const int maxTags = 24;
  static const int maxDepth = 6;

  /// Nested tags from canvas text nodes + edges (hub→spoke or deeper trees).
  List<String> fromCanvasNodes(
    List<CanvasNode> textNodes, {
    List<CanvasEdge> edges = const [],
  }) {
    final labels = <String, String>{};
    for (final n in textNodes) {
      final t = (n.text ?? '').trim();
      if (t.isEmpty) continue;
      if (n.id == 'tags' || n.id == 'img') continue;
      labels[n.id] = t;
    }
    if (labels.isEmpty) return const [];

    final children = <String, List<String>>{};
    final incoming = <String>{};
    for (final e in edges) {
      if (!labels.containsKey(e.fromNode) || !labels.containsKey(e.toNode)) {
        continue;
      }
      children.putIfAbsent(e.fromNode, () => []).add(e.toNode);
      incoming.add(e.toNode);
    }

    // Roots = no incoming edge; fall back to first text node (hub).
    var roots = labels.keys.where((id) => !incoming.contains(id)).toList();
    if (roots.isEmpty) roots = [labels.keys.first];

    final tags = <String>{};
    for (final root in roots) {
      _walk(
        id: root,
        path: [labels[root]!],
        children: children,
        labels: labels,
        tags: tags,
        depth: 1,
      );
    }

    final sorted = tags.toList()
      ..sort((a, b) {
        final depth = a.split('/').length.compareTo(b.split('/').length);
        if (depth != 0) return depth;
        return a.compareTo(b);
      });
    if (sorted.length <= maxTags) return sorted;
    return sorted.sublist(0, maxTags);
  }

  /// Convenience for confirm/commit regions + heuristic edges.
  List<String> fromRegions(
    List<OcrRegion> regions, {
    List<CanvasEdge>? edges,
  }) {
    final nodes = CanvasWriter.nodesFromRegions(regions);
    final e = edges ?? CanvasWriter.heuristicEdges(nodes);
    return fromCanvasNodes(nodes, edges: e);
  }

  /// Space-joined tag line for a canvas text node or markdown body.
  String tagLine(Iterable<String> tags) {
    final cleaned = tags
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .map((t) => t.startsWith('#') ? t : '#$t')
        .toList();
    return cleaned.join(' ');
  }

  /// YAML-ready tag names without leading `#`.
  List<String> frontmatterTags(Iterable<String> tags) {
    return tags
        .map((t) {
          var s = t.trim();
          if (s.startsWith('#')) s = s.substring(1);
          return s;
        })
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
  }

  /// Slug one mindmap label into an Obsidian tag segment.
  static String segment(String label) {
    final lower = label.toLowerCase().trim();
    final replaced = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final collapsed = replaced.replaceAll(RegExp(r'-+'), '-');
    final trimmed = collapsed.replaceAll(RegExp(r'^-|-$'), '');
    if (trimmed.isEmpty) return 'note';
    return trimmed.length <= 48 ? trimmed : trimmed.substring(0, 48);
  }

  void _walk({
    required String id,
    required List<String> path,
    required Map<String, List<String>> children,
    required Map<String, String> labels,
    required Set<String> tags,
    required int depth,
  }) {
    final segments = path.map(segment).where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty) {
      tags.add('#${segments.join('/')}');
    }
    if (depth >= maxDepth) return;
    final kids = children[id];
    if (kids == null || kids.isEmpty) return;
    for (final child in kids) {
      final label = labels[child];
      if (label == null) continue;
      _walk(
        id: child,
        path: [...path, label],
        children: children,
        labels: labels,
        tags: tags,
        depth: depth + 1,
      );
    }
  }
}
