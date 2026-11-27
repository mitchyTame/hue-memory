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

  bool get hasWork => sync.hasWork;
}

/// Turns a · daily **mindmap** into Todoist creates / done.
///
/// Ink layout (same linking as △ canvas):
/// - Center hub: calendar day → due date on root tasks
/// - First ring: section headings / names → Todoist labels (created even
///   when nothing hangs off them yet)
/// - Next ring: tasks under a section
/// - Further links **from** a task → Todoist **subtasks** (`parent_id`)
/// - Extra links **to** an already-seen task node → same Todoist task
///   (recorded as [DailyTodoistCreate.extraParentNodeIds])
///
/// Hand-drawn lines have no arrowheads, so Gemini's `fromNode` / `toNode`
/// order is arbitrary (left-side branches often point *at* the hub). Edges
/// are therefore re-oriented outward from the hub by ring distance before
/// the tree is walked.
class DailyMindmapParser {
  const DailyMindmapParser();

  DailyMindmapParseResult parse({
    required List<OcrRegion> regions,
    List<CanvasEdge> edges = const [],
    DateTime? referenceDate,
  }) {
    final labels = <String, String>{};
    for (final r in regions) {
      final t = r.text.trim();
      if (t.isEmpty) continue;
      labels[r.id] = t;
    }
    if (labels.isEmpty) {
      return const DailyMindmapParseResult(sync: DailyTodoistParseResult());
    }

    final validEdges = <CanvasEdge>[
      for (final e in edges)
        if (labels.containsKey(e.fromNode) &&
            labels.containsKey(e.toNode) &&
            e.fromNode != e.toNode)
          e,
    ];

    final neighbours = <String, List<String>>{};
    void link(String a, String b) {
      final list = neighbours.putIfAbsent(a, () => []);
      if (!list.contains(b)) list.add(b);
    }

    final drawnChildren = <String, List<String>>{};
    final drawnIncoming = <String, List<String>>{};
    for (final e in validEdges) {
      link(e.fromNode, e.toNode);
      link(e.toNode, e.fromNode);
      drawnChildren.putIfAbsent(e.fromNode, () => []).add(e.toNode);
      drawnIncoming.putIfAbsent(e.toNode, () => []).add(e.fromNode);
    }

    final dates = <String, DateTime>{};
    for (final entry in labels.entries) {
      final d = DailyNoteDate.tryParseLoose(
        entry.value,
        reference: referenceDate,
      );
      if (d != null) dates[entry.key] = d;
    }

    final hubId = _pickHub(
      labels: labels,
      dates: dates,
      neighbours: neighbours,
      drawnChildren: drawnChildren,
      drawnIncoming: drawnIncoming,
    );
    if (hubId == null) {
      return const DailyMindmapParseResult(sync: DailyTodoistParseResult());
    }
    final hubDate = dates[hubId];

    final ring = _ringDistances(hubId, neighbours);
    final children = <String, List<String>>{};
    final incoming = <String, List<String>>{};
    for (final e in validEdges) {
      final df = ring[e.fromNode];
      final dt = ring[e.toNode];
      if (df == null || dt == null) continue;
      String from;
      String to;
      if (df < dt) {
        from = e.fromNode;
        to = e.toNode;
      } else if (dt < df) {
        from = e.toNode;
        to = e.fromNode;
      } else {
        // Same ring: a line between two section names (or hub-level noise)
        // is not a parent/child relation; deeper task↔task links keep the
        // drawn direction.
        if (df <= 1) continue;
        from = e.fromNode;
        to = e.toNode;
      }
      final kids = children.putIfAbsent(from, () => []);
      if (kids.contains(to)) continue;
      kids.add(to);
      incoming.putIfAbsent(to, () => []).add(from);
    }

    final creates = <DailyTodoistCreate>[];
    final done = <String>[];
    final sectionLabels = <String>[];
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
      final branchText = labels[branchId];
      if (branchText == null || branchText.trim().isEmpty) continue;
      final split = splitBranchText(branchText);
      if (split.heading.isEmpty) continue;
      final action = DailyTodoistParser.classifySection(split.heading);
      if (action.isSkip) continue;

      final kids = children[branchId] ?? const <String>[];

      if (action.isDone) {
        if (kids.isEmpty && split.items.isEmpty) continue;
        if (md.isNotEmpty) md.writeln();
        md.writeln('**Done:**');
        for (final item in split.items) {
          done.add(item);
          md.writeln('- $item');
        }
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
      if (!sectionLabels.contains(label)) sectionLabels.add(label);
      final priority =
          action.priority ?? DailyTodoistParser.priorityForLabel(label);
      if (md.isNotEmpty) md.writeln();
      md.writeln('**${_displayHeading(label, split.heading)}:**');

      for (var i = 0; i < split.items.length; i++) {
        final item = split.items[i];
        md.writeln('- $item');
        creates.add(
          DailyTodoistCreate(
            content: item,
            label: label,
            priority: priority,
            nodeId: '$branchId#${i + 1}',
            dueDate: hubDate,
          ),
        );
      }

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
      sync: DailyTodoistParseResult(
        creates: creates,
        done: done,
        sectionLabels: sectionLabels,
      ),
      hubDate: hubDate,
      structuredMarkdown: md.toString().trimRight(),
    );
  }

  /// A branch node may hold just a name (`Deshan`), a heading with its items
  /// written inside the same box (`Errands\n- Post office\n- Pharmacy`), or
  /// an inline `Shopping: milk`.
  static ({String heading, List<String> items}) splitBranchText(String raw) {
    final lines = raw
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return (heading: '', items: const <String>[]);

    var heading = lines.first;
    final items = <String>[
      for (final l in lines.skip(1))
        if (DailyTodoistParser.cleanItemLine(l).isNotEmpty)
          DailyTodoistParser.cleanItemLine(l),
    ];

    if (items.isEmpty) {
      final inline = DailyTodoistParser.inlineSectionLine.firstMatch(heading);
      if (inline != null) {
        final rest = heading.substring(inline.group(0)!.length - 1).trim();
        final item = DailyTodoistParser.cleanItemLine(rest);
        heading = inline.group(1)!.trim();
        if (item.isNotEmpty) items.add(item);
      }
    }
    return (heading: heading, items: items);
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

  /// Hub choice, in order:
  /// 1. A node that reads as a date (most links wins — a dated task leaf
  ///    has one).
  /// 2. The drawn root with most children, when following the drawn
  ///    direction from it reaches its whole cluster (consistently drawn).
  /// 3. The centre of the largest cluster ignoring direction.
  static String? _pickHub({
    required Map<String, String> labels,
    required Map<String, DateTime> dates,
    required Map<String, List<String>> neighbours,
    required Map<String, List<String>> drawnChildren,
    required Map<String, List<String>> drawnIncoming,
  }) {
    if (labels.isEmpty) return null;
    final order = labels.keys.toList();
    int degree(String id) => neighbours[id]?.length ?? 0;
    bool isRoot(String id) => !(drawnIncoming[id]?.isNotEmpty ?? false);

    if (dates.isNotEmpty) {
      final ids = dates.keys.toList()
        ..sort((a, b) {
          final byDegree = degree(b).compareTo(degree(a));
          if (byDegree != 0) return byDegree;
          final byRoot = (isRoot(b) ? 1 : 0).compareTo(isRoot(a) ? 1 : 0);
          if (byRoot != 0) return byRoot;
          return order.indexOf(a).compareTo(order.indexOf(b));
        });
      return ids.first;
    }

    if (neighbours.isEmpty) return order.first;

    final roots =
        order
            .where(
              (id) => isRoot(id) && (drawnChildren[id]?.isNotEmpty ?? false),
            )
            .toList()
          ..sort((a, b) {
            final ca = drawnChildren[a]?.length ?? 0;
            final cb = drawnChildren[b]?.length ?? 0;
            if (ca != cb) return cb.compareTo(ca);
            return a.compareTo(b);
          });
    if (roots.isNotEmpty) {
      final candidate = roots.first;
      final reach = _reachable(candidate, drawnChildren);
      final cluster = _ringDistances(candidate, neighbours);
      if (reach.length == cluster.length) return candidate;
    }

    // Largest cluster, then the node with the smallest eccentricity in it.
    final seen = <String>{};
    Map<String, int>? largest;
    for (final id in order) {
      if (seen.contains(id) || !neighbours.containsKey(id)) continue;
      final cluster = _ringDistances(id, neighbours);
      seen.addAll(cluster.keys);
      if (largest == null || cluster.length > largest.length) {
        largest = cluster;
      }
    }
    if (largest == null) return order.first;

    String? best;
    var bestEcc = 1 << 30;
    for (final id in order) {
      if (!largest.containsKey(id)) continue;
      final ecc = _ringDistances(
        id,
        neighbours,
      ).values.fold<int>(0, (m, v) => v > m ? v : m);
      if (best == null ||
          ecc < bestEcc ||
          (ecc == bestEcc && degree(id) > degree(best))) {
        best = id;
        bestEcc = ecc;
      }
    }
    return best;
  }

  /// Breadth-first ring distance from [start], ignoring edge direction.
  static Map<String, int> _ringDistances(
    String start,
    Map<String, List<String>> neighbours,
  ) {
    final dist = <String, int>{start: 0};
    final queue = <String>[start];
    for (var i = 0; i < queue.length; i++) {
      final id = queue[i];
      final d = dist[id]!;
      for (final n in neighbours[id] ?? const <String>[]) {
        if (dist.containsKey(n)) continue;
        dist[n] = d + 1;
        queue.add(n);
      }
    }
    return dist;
  }

  static Set<String> _reachable(
    String start,
    Map<String, List<String>> children,
  ) {
    final seen = <String>{start};
    final stack = <String>[start];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      for (final c in children[id] ?? const <String>[]) {
        if (seen.add(c)) stack.add(c);
      }
    }
    return seen;
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
