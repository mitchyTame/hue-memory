import 'dart:convert';
import 'dart:math' as math;

import '../ocr/ocr_client.dart';
import '../writers/canvas_writer.dart';

/// Structured mindmap proposal for △ hybrid Canvas (JSON-shaped, not prose).
///
/// Coordinate system: [MindmapNode.x] / [MindmapNode.y] are **normalized
/// image space 0–1** (origin top-left). [regionsFromStructure] maps them to
/// OCR-style `[left, top, width, height]` bboxes; [CanvasWriter.nodesFromRegions]
/// then scales onto the Obsidian Canvas image frame (default 480×640).
class MindmapStructure {
  const MindmapStructure({
    required this.nodes,
    this.edges = const [],
    this.truncated = false,
    this.source = 'heuristic',
  });

  final List<MindmapNode> nodes;
  final List<MindmapEdge> edges;

  /// True when OCR/model text was truncated due to loops or length caps.
  final bool truncated;

  /// `ocr` | `vision` | `heuristic` | `merged`
  final String source;

  Map<String, Object?> toJson() => {
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
        if (truncated) 'truncated': true,
        'source': source,
        'coord_space': 'normalized_0_1',
      };

  /// Parse vision/model JSON. Never treats freeform prose as structure.
  ///
  /// Truncates looping text, cuts at the first balanced closing `}`, and keeps
  /// partial nodes when the payload is incomplete.
  factory MindmapStructure.parseJson(
    String raw, {
    int maxNodes = MindmapPropose.maxLabels,
    String source = 'vision',
  }) {
    final sliced = MindmapPropose.sliceJsonObject(raw);
    if (sliced == null || sliced.trim().isEmpty) {
      return MindmapStructure(
        nodes: const [],
        truncated: true,
        source: source,
      );
    }
    try {
      final decoded = jsonDecode(sliced);
      if (decoded is! Map) {
        return MindmapStructure(
          nodes: const [],
          truncated: true,
          source: source,
        );
      }
      final map = Map<String, dynamic>.from(decoded);
      final nodesRaw = map['nodes'];
      final edgesRaw = map['edges'];
      final nodes = <MindmapNode>[];
      final seen = <String>{};
      if (nodesRaw is List) {
        for (var i = 0; i < nodesRaw.length && nodes.length < maxNodes; i++) {
          final item = nodesRaw[i];
          if (item is! Map) continue;
          final label = '${item['label'] ?? item['text'] ?? ''}'.trim();
          if (label.isEmpty) continue;
          final clipped = MindmapPropose.clipLabel(label);
          final key = clipped.toLowerCase();
          if (seen.contains(key)) continue;
          seen.add(key);
          final id = '${item['id'] ?? 'n${nodes.length + 1}'}';
          nodes.add(
            MindmapNode(
              id: id,
              label: clipped,
              x: MindmapPropose.readNorm(item['x']),
              y: MindmapPropose.readNorm(item['y']),
            ),
          );
        }
      }
      final edges = <MindmapEdge>[];
      if (edgesRaw is List && nodes.length >= 2) {
        final ids = nodes.map((n) => n.id).toSet();
        for (var i = 0; i < edgesRaw.length && edges.length < maxNodes; i++) {
          final item = edgesRaw[i];
          if (item is! Map) continue;
          final from = '${item['from'] ?? item['fromNode'] ?? ''}';
          final to = '${item['to'] ?? item['toNode'] ?? ''}';
          if (from.isEmpty || to.isEmpty || from == to) continue;
          if (!ids.contains(from) || !ids.contains(to)) continue;
          edges.add(MindmapEdge(from: from, to: to));
        }
      }
      final truncatedFlag = map['truncated'] == true ||
          MindmapPropose.looksLikeLoopingProse(raw) ||
          raw.length > sliced.length + 8;
      return MindmapStructure(
        nodes: nodes,
        edges: edges,
        truncated: truncatedFlag,
        source: source,
      );
    } catch (_) {
      return MindmapStructure(
        nodes: const [],
        truncated: true,
        source: source,
      );
    }
  }
}

class MindmapNode {
  const MindmapNode({
    required this.id,
    required this.label,
    this.x,
    this.y,
  });

  final String id;
  final String label;

  /// Normalized image X in 0–1 (top-left origin). Null → layout heuristic.
  final double? x;

  /// Normalized image Y in 0–1 (top-left origin). Null → layout heuristic.
  final double? y;

  Map<String, Object?> toJson() => {
        'id': id,
        'text': label,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
      };
}

class MindmapEdge {
  const MindmapEdge({required this.from, required this.to});

  final String from;
  final String to;

  Map<String, Object?> toJson() => {'from': from, 'to': to};
}

/// OCR labels → JSON mindmap structure for △ hybrid (ink-ghost + nodes).
///
/// Hard rules:
/// - No freeform prose dump into confirm / Canvas
/// - Structure is JSON-shaped (`nodes` / `edges`)
/// - Looping OCR/model text is truncated; photo stays source of truth
class MindmapPropose {
  const MindmapPropose();

  static const int maxLabels = 12;
  static const int maxOcrChars = 2400;
  static const int maxLabelChars = 64;

  /// Chat completion budget for △ vision JSON (still capped; `json_object`).
  /// Raised above 384 so major boxes are not truncated mid-list.
  static const int visionMaxTokens = 768;

  /// Default node size in normalized image space when vision gives only x,y.
  /// Slightly compact so clamped layouts stay closer to vision coords.
  static const double defaultNodeW = 0.24;
  static const double defaultNodeH = 0.08;

  /// System prompt for Mistral vision structure (JSON only, tight).
  ///
  /// Priority: (1) accurate handwriting `text`, (2) every major labeled box,
  /// (3) normalized x,y layout. Edges are lowest priority.
  static const String visionSystemPrompt =
      'You read a hand-drawn mindmap PHOTO and return ONE JSON object only — '
      'no markdown fences, no prose, no repetition. '
      'Schema: {"nodes":[{"id":"n1","text":"exact words","x":0.0,"y":0.0}],'
      '"edges":[{"from":"n1","to":"n2"}]}. '
      'PRIORITY 1 — WORDS: Carefully read handwriting inside each box/bubble. '
      'Copy letters as written; fix only clear misspellings from context. '
      'Never invent labels. Never leave "text" empty. '
      'PRIORITY 2 — COVERAGE: Include EVERY major labeled box you can see '
      '(hub + all branch labels), up to $maxLabels nodes. Do not skip spokes. '
      'PRIORITY 3 — LAYOUT: x,y are normalized 0–1 image coords, origin '
      'top-left, for the TOP-LEFT of each box (not center). '
      'Text ≤$maxLabelChars chars. '
      'OCR hints may be wrong — when they disagree, trust the image. '
      'Edges only when a clear ink line connects two boxes; omit if unsure. '
      'Never loop or repeat nodes.';

  /// User text beside the image for the vision structure call.
  static String visionUserPrompt(List<String> ocrLabels) {
    final labels = ocrLabels
        .map(clipLabel)
        .where((s) => s.isNotEmpty)
        .take(maxLabels)
        .toList();
    final hint = labels.isEmpty
        ? 'No OCR hints — read every labeled box from the drawing.'
        : 'OCR hints (may be wrong — image wins): ${labels.join(' | ')}';
    return 'Hand-drawn mindmap photo. Return nodes/edges JSON. '
        'Read the actual handwriting for each "text". '
        'Cover all major boxes. Put accurate x,y (0–1, top-left).\n$hint';
  }

  static double? readNorm(Object? v) {
    if (v is num) {
      final d = v.toDouble();
      if (d.isNaN) return null;
      // Allow 0–100 percent or 0–1.
      final n = d > 1.0 && d <= 100.0 ? d / 100.0 : d;
      return n.clamp(0.0, 1.0);
    }
    if (v is String) {
      final d = double.tryParse(v.trim());
      return d == null ? null : readNorm(d);
    }
    return null;
  }

  /// Cut repeating / runaway OCR or model text before any UI use.
  static String truncateLoopingProse(String input) {
    var text = input.trim();
    if (text.isEmpty) return text;
    if (text.length > maxOcrChars) {
      text = text.substring(0, maxOcrChars);
    }

    final lines = text.split('\n');
    final kept = <String>[];
    final seen = <String>{};
    var repeatHits = 0;
    for (final line in lines) {
      final norm = line.trim().toLowerCase();
      if (norm.isEmpty) {
        kept.add(line);
        continue;
      }
      if (norm.length >= 12 && seen.contains(norm)) {
        repeatHits++;
        if (repeatHits >= 2) break;
        continue;
      }
      seen.add(norm);
      kept.add(line);
      if (kept.length > 80) break;
    }
    text = kept.join('\n').trim();

    if (text.length >= 120) {
      const window = 40;
      for (var i = 0; i + window * 2 <= text.length; i++) {
        final a = text.substring(i, i + window);
        final b = text.substring(i + window, i + window * 2);
        if (a == b) {
          text = text.substring(0, i + window).trim();
          break;
        }
      }
    }
    return text;
  }

  static bool looksLikeLoopingProse(String input) {
    final t = input.trim();
    if (t.length < 80) return false;
    final lines = t
        .split('\n')
        .map((l) => l.trim().toLowerCase())
        .where((l) => l.length >= 12)
        .toList();
    if (lines.length >= 4) {
      final counts = <String, int>{};
      for (final l in lines) {
        counts[l] = (counts[l] ?? 0) + 1;
        if (counts[l]! >= 3) return true;
      }
    }
    if (t.length >= 120) {
      const window = 40;
      for (var i = 0; i + window * 2 <= t.length; i += 8) {
        if (t.substring(i, i + window) ==
            t.substring(i + window, i + window * 2)) {
          return true;
        }
      }
    }
    return false;
  }

  /// First balanced `{…}` slice (stops when schema closes — no trailing prose).
  static String? sliceJsonObject(String raw) {
    final start = raw.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < raw.length; i++) {
      final c = raw[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (c == '\\') {
          escape = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) return raw.substring(start, i + 1);
      }
    }
    return raw.substring(start);
  }

  static String clipLabel(String s) {
    final t = s.trim();
    if (t.length <= maxLabelChars) return t;
    return '${t.substring(0, maxLabelChars - 1)}…';
  }

  static String _normKey(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  /// Split truncated OCR markdown into short unique labels (not a page dump).
  static List<String> labelsFromMarkdown(String markdown) {
    final raw = truncateLoopingProse(markdown);
    if (raw.isEmpty) return const [];

    final chunks = <String>[];
    for (final block in raw.split(RegExp(r'\n+'))) {
      var line = block.trim();
      if (line.isEmpty) continue;
      line = line
          .replaceFirst(RegExp(r'^#{1,6}\s*'), '')
          .replaceFirst(RegExp(r'^[-*•·○◇△≡∼›>]+\s*'), '')
          .trim();
      if (line.isEmpty) continue;
      if (RegExp(r'^[◇△≡∼○·•V]$').hasMatch(line)) continue;
      if (line.length > 120 && !line.contains(RegExp(r'\s[-–—]\s'))) continue;
      chunks.add(line);
    }

    if (chunks.isEmpty) {
      final words = raw.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      final head = words.take(8).join(' ');
      if (head.isNotEmpty) chunks.add(head);
    }

    final labels = <String>[];
    final seen = <String>{};
    for (final c in chunks) {
      final parts = c.length > 56 && c.contains(RegExp(r'\s[-–—]\s'))
          ? c.split(RegExp(r'\s[-–—]\s'))
          : [c];
      for (final part in parts) {
        final t = clipLabel(part);
        if (t.isEmpty) continue;
        final key = t.toLowerCase();
        if (seen.contains(key)) continue;
        seen.add(key);
        labels.add(t);
        if (labels.length >= maxLabels) return labels;
      }
    }
    return labels;
  }

  /// Heuristic JSON structure from OCR labels only (no vision).
  static MindmapStructure structureFromOcrMarkdown(String markdown) {
    final truncated = looksLikeLoopingProse(markdown) ||
        markdown.trim().length > maxOcrChars;
    final labels = labelsFromMarkdown(markdown);
    if (labels.isEmpty) {
      return MindmapStructure(
        nodes: const [],
        truncated: truncated,
        source: 'ocr',
      );
    }
    final laid = layoutRadial(labels);
    final nodes = <MindmapNode>[
      for (var i = 0; i < laid.length; i++)
        MindmapNode(
          id: laid[i].id,
          label: laid[i].text,
          x: laid[i].bbox?[0],
          y: laid[i].bbox?[1],
        ),
    ];
    final edges = nodes.length < 2
        ? const <MindmapEdge>[]
        : [
            for (var i = 1; i < nodes.length; i++)
              MindmapEdge(from: nodes.first.id, to: nodes[i].id),
          ];
    return MindmapStructure(
      nodes: nodes,
      edges: edges,
      truncated: truncated,
      source: 'ocr',
    );
  }

  /// Merge OCR hints onto vision nodes — **vision text wins**.
  ///
  /// - Non-empty vision `text`/`label` is kept (OCR never overrides).
  /// - Empty vision stubs may be filled from a fuzzy-matched OCR hint.
  /// - Unmatched OCR labels are **appended** (missing-box recovery) with
  ///   heuristic positions so spokes vision skipped still appear for edit.
  /// - Vision x,y and edges kept when endpoints survive.
  static MindmapStructure mergeOcrLabelsOntoVision({
    required List<String> ocrLabels,
    required MindmapStructure vision,
  }) {
    if (vision.nodes.isEmpty) {
      if (ocrLabels.isEmpty) {
        return MindmapStructure(
          nodes: const [],
          truncated: vision.truncated,
          source: 'merged',
        );
      }
      return structureFromOcrMarkdown(ocrLabels.join('\n')).copyWith(
        truncated: vision.truncated,
        source: 'merged',
      );
    }

    final unusedOcr = List<String>.from(ocrLabels);
    final mergedNodes = <MindmapNode>[];
    final seenKeys = <String>{};
    for (final vn in vision.nodes) {
      var label = clipLabel(vn.label);
      final vKey = _normKey(label);
      var matchedAt = -1;
      for (var i = 0; i < unusedOcr.length; i++) {
        final oKey = _normKey(unusedOcr[i]);
        if (oKey.isEmpty) continue;
        if (vKey.isEmpty ||
            oKey == vKey ||
            oKey.contains(vKey) ||
            vKey.contains(oKey)) {
          matchedAt = i;
          break;
        }
      }
      if (matchedAt >= 0) {
        final ocrHint = clipLabel(unusedOcr.removeAt(matchedAt));
        // Vision primary — only fill empty stubs from OCR.
        if (label.isEmpty && ocrHint.isNotEmpty) {
          label = ocrHint;
        }
      }
      if (label.isEmpty) continue;
      final key = _normKey(label);
      if (key.isNotEmpty && !seenKeys.add(key)) continue;
      mergedNodes.add(
        MindmapNode(id: vn.id, label: label, x: vn.x, y: vn.y),
      );
      if (mergedNodes.length >= maxLabels) break;
    }

    // Missing-box recovery: keep unmatched OCR spokes vision skipped.
    if (mergedNodes.length < maxLabels) {
      for (final leftover in unusedOcr) {
        if (mergedNodes.length >= maxLabels) break;
        final label = clipLabel(leftover);
        final key = _normKey(label);
        if (label.isEmpty || key.isEmpty || seenKeys.contains(key)) continue;
        seenKeys.add(key);
        final i = mergedNodes.length;
        mergedNodes.add(
          MindmapNode(
            id: 'ocr$i',
            label: label,
            x: 0.10 + (i % 3) * 0.30,
            y: 0.72 + (i ~/ 3) * 0.08,
          ),
        );
      }
    }

    if (mergedNodes.isEmpty) {
      return structureFromOcrMarkdown(ocrLabels.join('\n')).copyWith(
        truncated: vision.truncated,
        source: 'merged',
      );
    }

    final ids = mergedNodes.map((n) => n.id).toSet();
    var edges = vision.edges
        .where((e) => ids.contains(e.from) && ids.contains(e.to))
        .toList();
    if (edges.isEmpty && mergedNodes.length >= 2) {
      edges = [
        for (var i = 1; i < mergedNodes.length; i++)
          MindmapEdge(from: mergedNodes.first.id, to: mergedNodes[i].id),
      ];
    }

    return MindmapStructure(
      nodes: mergedNodes,
      edges: edges,
      truncated: vision.truncated,
      source: 'merged',
    );
  }

  /// Map structure → [OcrRegion] bboxes in normalized 0–1 image space.
  ///
  /// Vision x,y are treated as box **top-left**. We size the card compactly and
  /// only nudge inward when the default width/height would overflow the frame
  /// (avoids stacking every edge node at the same clamp wall).
  static List<OcrRegion> regionsFromStructure(MindmapStructure structure) {
    if (structure.nodes.isEmpty) {
      return const [
        OcrRegion(
          id: 'n1',
          text: '',
          confidence: 0.4,
          bbox: [0.30, 0.30, 0.40, 0.12],
        ),
      ];
    }
    final regions = <OcrRegion>[];
    for (var i = 0; i < structure.nodes.length; i++) {
      final n = structure.nodes[i];
      final rawLeft = n.x ?? (0.12 + (i % 3) * 0.28);
      final rawTop = n.y ?? (0.12 + (i ~/ 3) * 0.18);
      final placed = placeNormBox(left: rawLeft, top: rawTop);
      regions.add(
        OcrRegion(
          id: n.id,
          text: n.label,
          confidence: 0.8,
          bbox: [placed.left, placed.top, placed.width, placed.height],
        ),
      );
    }
    return regions;
  }

  /// Fit a default-sized node into 0–1 without crushing vision coords.
  static ({double left, double top, double width, double height}) placeNormBox({
    required double left,
    required double top,
    double width = defaultNodeW,
    double height = defaultNodeH,
  }) {
    var w = width.clamp(0.08, 0.55);
    var h = height.clamp(0.05, 0.25);
    var x = left.isNaN ? 0.1 : left;
    var y = top.isNaN ? 0.1 : top;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x + w > 1.0) x = (1.0 - w).clamp(0.0, 1.0);
    if (y + h > 1.0) y = (1.0 - h).clamp(0.0, 1.0);
    if (x + w > 1.0) w = (1.0 - x).clamp(0.08, 0.55);
    if (y + h > 1.0) h = (1.0 - y).clamp(0.05, 0.25);
    return (left: x, top: y, width: w, height: h);
  }

  static List<OcrRegion> regionsFromMarkdown(String markdown) {
    return regionsFromStructure(structureFromOcrMarkdown(markdown));
  }

  /// Canvas pixel positions from normalized [x,y] (for tests / docs).
  static ({int x, int y, int w, int h}) canvasRectFromNorm({
    required double left,
    required double top,
    double width = defaultNodeW,
    double height = defaultNodeH,
    int imageWidth = CanvasWriter.defaultImageWidth,
    int imageHeight = CanvasWriter.defaultImageHeight,
    int imageX = CanvasWriter.defaultImageX,
    int imageY = CanvasWriter.defaultImageY,
  }) {
    return (
      x: imageX + (left.clamp(0.0, 1.0) * imageWidth).round(),
      y: imageY + (top.clamp(0.0, 1.0) * imageHeight).round(),
      w: math.max(120, (width.clamp(0.05, 1.0) * imageWidth).round()),
      h: math.max(48, (height.clamp(0.05, 1.0) * imageHeight).round()),
    );
  }

  static List<OcrRegion> layoutRadial(
    List<String> labels, {
    List<String>? ids,
  }) {
    if (labels.isEmpty) return const [];
    final regions = <OcrRegion>[
      OcrRegion(
        id: ids != null && ids.isNotEmpty ? ids.first : 'n1',
        text: labels.first,
        confidence: 0.82,
        bbox: const [0.30, 0.34, 0.40, 0.11],
      ),
    ];
    if (labels.length == 1) return regions;

    const slots = <List<double>>[
      [0.08, 0.12, 0.34, 0.09],
      [0.58, 0.10, 0.34, 0.09],
      [0.62, 0.42, 0.32, 0.09],
      [0.55, 0.68, 0.34, 0.09],
      [0.10, 0.68, 0.34, 0.09],
      [0.05, 0.40, 0.30, 0.09],
      [0.32, 0.08, 0.36, 0.08],
      [0.32, 0.78, 0.36, 0.08],
      [0.18, 0.22, 0.28, 0.08],
      [0.54, 0.24, 0.28, 0.08],
      [0.20, 0.54, 0.28, 0.08],
    ];

    for (var i = 1; i < labels.length; i++) {
      final slot = slots[(i - 1) % slots.length];
      regions.add(
        OcrRegion(
          id: ids != null && i < ids.length ? ids[i] : 'n${i + 1}',
          text: labels[i],
          confidence: 0.75,
          bbox: List<double>.from(slot),
        ),
      );
    }
    return regions;
  }
}

extension on MindmapStructure {
  MindmapStructure copyWith({
    List<MindmapNode>? nodes,
    List<MindmapEdge>? edges,
    bool? truncated,
    String? source,
  }) {
    return MindmapStructure(
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      truncated: truncated ?? this.truncated,
      source: source ?? this.source,
    );
  }
}
