import '../ocr/ocr_client.dart';
import '../vault/daily_note_path.dart';
import '../writers/canvas_writer.dart';
import 'daily_todoist_parser.dart';

/// One parsed daily mindmap: Todoist sync payload + optional hub date.
class DailyMindmapParseResult {
  const DailyMindmapParseResult({
    required this.sync,
    this.hubDate,
    this.structuredMarkdown = '',
  });

  final DailyTodoistParseResult sync;
  final DateTime? hubDate;

  /// Section markdown mirroring the tree (confirm / fallback / debug).
  final String structuredMarkdown;

  bool get hasWork =>
      sync.creates.isNotEmpty || sync.done.isNotEmpty;
}

/// Turns a · daily **mindmap** (date hub → branch labels → task leaves)
/// into Todoist creates / done — the same hub→spoke linking used for △ canvas.
///
/// Expected ink layout:
/// - Center hub: calendar day (`19 Oct '26` / `2026-10-19`)
/// - First ring: section headings → Todoist labels (`Important`, `Errands`, …)
/// - Leaves under each heading → Inbox tasks (or `done:` closes)
class DailyMindmapParser {
  const DailyMindmapParser();

  /// Parse edited confirm regions + canvas edges (Gemini / hybrid mindmap).
  DailyMindmapParseResult parse({
    required List<OcrRegion> regions,
    List<CanvasEdge> edges = const [],
  }) {
    final labels = <String, String>{};
    for (final r in regions) {
      final t = r.text.trim();
      if (t.isEmpty) continue;
      labels[r.id] = t;
    }
    if (labels.isEmpty) {
      return const DailyMindmapParseResult(
        sync: DailyTodoistParseResult(),
      );
    }

    final children = <String, List<String>>{};
    final incoming = <String>{};
    for (final e in edges) {
      if (!labels.containsKey(e.fromNode) || !labels.containsKey(e.toNode)) {
        continue;
      }
      if (e.fromNode == e.toNode) continue;
      children.putIfAbsent(e.fromNode, () => []).add(e.toNode);
      incoming.add(e.toNode);
    }

    final roots = labels.keys.where((id) => !incoming.contains(id)).toList();
    final hubId = _pickHub(labels: labels, roots: roots, children: children);
    if (hubId == null) {
      return const DailyMindmapParseResult(
        sync: DailyTodoistParseResult(),
      );
    }

    final hubDate = DailyNoteDate.tryParse(labels[hubId] ?? '');
    final creates = <DailyTodoistCreate>[];
    final done = <String>[];
    final md = StringBuffer();

    final branches = children[hubId] ?? const <String>[];
    if (branches.isEmpty) {
      // Flat map: every non-hub node is a spoke with no grandchildren —
      // cannot invent section structure; return empty for Todoist.
      return DailyMindmapParseResult(
        sync: const DailyTodoistParseResult(),
        hubDate: hubDate,
      );
    }

    for (final branchId in branches) {
      final branchLabel = labels[branchId];
      if (branchLabel == null || branchLabel.trim().isEmpty) continue;
      final action = DailyTodoistParser.classifySection(branchLabel);
      final leaves = _collectLeaves(
        root: branchId,
        children: children,
        labels: labels,
      );

      if (action.isSkip) continue;

      if (action.isDone) {
        if (leaves.isEmpty) continue;
        if (md.isNotEmpty) md.writeln();
        md.writeln('**Done:**');
        for (final leaf in leaves) {
          done.add(leaf);
          md.writeln('- $leaf');
        }
        continue;
      }

      final label = action.label!;
      if (leaves.isEmpty) continue;
      if (md.isNotEmpty) md.writeln();
      md.writeln('**${_displayHeading(label, branchLabel)}:**');
      for (final leaf in leaves) {
        creates.add(
          DailyTodoistCreate(
            content: leaf,
            label: label,
            priority: action.priority ??
                DailyTodoistParser.priorityForLabel(label),
          ),
        );
        md.writeln('- $leaf');
      }
    }

    return DailyMindmapParseResult(
      sync: DailyTodoistParseResult(creates: creates, done: done),
      hubDate: hubDate,
      structuredMarkdown: md.toString().trimRight(),
    );
  }

  /// Prefer a date-like hub; else the root with the most children; else first root.
  static String? _pickHub({
    required Map<String, String> labels,
    required List<String> roots,
    required Map<String, List<String>> children,
  }) {
    if (labels.isEmpty) return null;

    String? dateHub;
    for (final id in labels.keys) {
      if (DailyNoteDate.tryParse(labels[id]!) != null) {
        dateHub = id;
        // Prefer a date that is also a graph root when possible.
        if (roots.contains(id)) return id;
      }
    }
    if (dateHub != null) return dateHub;

    if (roots.isEmpty) return labels.keys.first;

    roots.sort((a, b) {
      final ca = children[a]?.length ?? 0;
      final cb = children[b]?.length ?? 0;
      if (ca != cb) return cb.compareTo(ca);
      return a.compareTo(b);
    });
    return roots.first;
  }

  /// Task texts = leaf descendants under [root]. If [root] itself is a leaf
  /// (no children), it is not a task — branches without leaves yield nothing.
  static List<String> _collectLeaves({
    required String root,
    required Map<String, List<String>> children,
    required Map<String, String> labels,
  }) {
    final kids = children[root];
    if (kids == null || kids.isEmpty) return const [];

    // BFS so sibling order follows edge insertion (stable for confirm → Todoist).
    final out = <String>[];
    final queue = List<String>.from(kids);
    final seen = <String>{root};
    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      if (!seen.add(id)) continue;
      final text = labels[id];
      if (text == null || text.trim().isEmpty) continue;
      final grand = children[id];
      if (grand == null || grand.isEmpty) {
        out.add(text.trim());
      } else {
        queue.addAll(grand);
      }
    }
    return out;
  }

  static String _displayHeading(String normalizedLabel, String raw) {
    // Keep familiar Title Case for known aliases in markdown mirror.
    switch (normalizedLabel) {
      case 'high':
        return 'Important';
      case 'medium':
        return 'Medium';
      case 'low':
        return 'Low';
      case 'events':
        return 'Events';
      case 'reminders':
        return 'Reminders';
      default:
        return raw.trim();
    }
  }
}
