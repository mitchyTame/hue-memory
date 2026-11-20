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

/// Turns a · daily **mindmap** into Todoist creates / done.
///
/// Ink layout (same linking as △ canvas):
/// - Center hub: calendar day → due date on root tasks
/// - First ring: section headings → Todoist labels
/// - Next ring: tasks under a section
/// - Further links **from** a task → Todoist **subtasks** (`parent_id`)
/// - Extra links **to** an already-seen task node → same Todoist task
///   (recorded as [DailyTodoistCreate.extraParentNodeIds])
class DailyMindmapParser {
  const DailyMindmapParser();

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
    final incoming = <String, List<String>>{};
    for (final e in edges) {
      if (!labels.containsKey(e.fromNode) || !labels.containsKey(e.toNode)) {
        continue;
      }
      if (e.fromNode == e.toNode) continue;
      children.putIfAbsent(e.fromNode, () => []).add(e.toNode);
      incoming.putIfAbsent(e.toNode, () => []).add(e.fromNode);
    }

    final roots = labels.keys
        .where((id) => !(incoming[id]?.isNotEmpty ?? false))
        .toList();
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
    final emitted = <String>{}; // node ids already queued as creates
    // nodeId → index in [creates] for attaching extra parents
    final createIndex = <String, int>{};

    final branches = children[hubId] ?? const <String>[];
    if (branches.isEmpty) {
      return DailyMindmapParseResult(
        sync: const DailyTodoistParseResult(),
        hubDate: hubDate,
      );
    }

    for (final branchId in branches) {
      final branchLabel = labels[branchId];
      if (branchLabel == null || branchLabel.trim().isEmpty) continue;
      final action = DailyTodoistParser.classifySection(branchLabel);
      if (action.isSkip) continue;

      final kids = children[branchId] ?? const <String>[];
      if (kids.isEmpty) continue;

      if (action.isDone) {
        if (md.isNotEmpty) md.writeln();
        md.writeln('**Done:**');
        for (final leafId in kids) {
          _collectDoneLeaves(
            id: leafId,
            children: children,
            labels: labels,
            done: done,
            md: md,
          );
        }
        continue;
      }

      final label = action.label!;
      final priority =
          action.priority ?? DailyTodoistParser.priorityForLabel(label);
      if (md.isNotEmpty) md.writeln();
      md.writeln('**${_displayHeading(label, branchLabel)}:**');

      for (final taskId in kids) {
        _emitTaskTree(
          nodeId: taskId,
          parentTaskNodeId: null,
          sectionLabel: label,
          priority: priority,
          dueDate: hubDate,
          labels: labels,
          children: children,
          incoming: incoming,
          creates: creates,
          emitted: emitted,
          createIndex: createIndex,
          md: md,
          depth: 0,
        );
      }
    }

    return DailyMindmapParseResult(
      sync: DailyTodoistParseResult(creates: creates, done: done),
      hubDate: hubDate,
      structuredMarkdown: md.toString().trimRight(),
    );
  }

  void _emitTaskTree({
    required String nodeId,
    required String? parentTaskNodeId,
    required String sectionLabel,
    required int? priority,
    required DateTime? dueDate,
    required Map<String, String> labels,
    required Map<String, List<String>> children,
    required Map<String, List<String>> incoming,
    required List<DailyTodoistCreate> creates,
    required Set<String> emitted,
    required Map<String, int> createIndex,
    required StringBuffer md,
    required int depth,
  }) {
    final text = labels[nodeId]?.trim();
    if (text == null || text.isEmpty) return;

    if (emitted.contains(nodeId)) {
      // Extra link into an already-emitted task (multi-parent mindmap).
      if (parentTaskNodeId != null) {
        final idx = createIndex[nodeId];
        if (idx != null) {
          final existing = creates[idx];
          if (existing.parentNodeId != parentTaskNodeId &&
              !existing.extraParentNodeIds.contains(parentTaskNodeId)) {
            creates[idx] = DailyTodoistCreate(
              content: existing.content,
              label: existing.label,
              priority: existing.priority,
              nodeId: existing.nodeId,
              parentNodeId: existing.parentNodeId,
              dueDate: existing.dueDate,
              extraParentNodeIds: [
                ...existing.extraParentNodeIds,
                parentTaskNodeId,
              ],
            );
          }
        }
      }
      return;
    }

    emitted.add(nodeId);
    final indent = '  ' * depth;
    md.writeln('$indent- $text');

    creates.add(
      DailyTodoistCreate(
        content: text,
        label: sectionLabel,
        priority: parentTaskNodeId == null ? priority : null,
        nodeId: nodeId,
        parentNodeId: parentTaskNodeId,
        // Due date only on root tasks under a section (not nested subtasks).
        dueDate: parentTaskNodeId == null ? dueDate : null,
      ),
    );
    createIndex[nodeId] = creates.length - 1;

    final kids = children[nodeId] ?? const <String>[];
    for (final childId in kids) {
      _emitTaskTree(
        nodeId: childId,
        parentTaskNodeId: nodeId,
        sectionLabel: sectionLabel,
        priority: priority,
        dueDate: dueDate,
        labels: labels,
        children: children,
        incoming: incoming,
        creates: creates,
        emitted: emitted,
        createIndex: createIndex,
        md: md,
        depth: depth + 1,
      );
    }
  }

  static void _collectDoneLeaves({
    required String id,
    required Map<String, List<String>> children,
    required Map<String, String> labels,
    required List<String> done,
    required StringBuffer md,
  }) {
    final text = labels[id]?.trim();
    if (text == null || text.isEmpty) return;
    final kids = children[id];
    if (kids == null || kids.isEmpty) {
      done.add(text);
      md.writeln('- $text');
      return;
    }
    for (final child in kids) {
      _collectDoneLeaves(
        id: child,
        children: children,
        labels: labels,
        done: done,
        md: md,
      );
    }
  }

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

  static String _displayHeading(String normalizedLabel, String raw) {
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
