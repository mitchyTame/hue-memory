import '../gemini/capture_coordinator.dart';
import '../gemini/obsidian_canvas_from_gemini.dart';
import '../ocr/ocr_client.dart';
import '../writers/canvas_writer.dart';
import 'daily_mindmap_parser.dart';
import 'daily_todoist_parser.dart';

/// One reviewable Todoist create (checkbox + editable text + priority).
class PlannedTask {
  const PlannedTask({
    required this.key,
    required this.create,
    this.included = true,
  });

  /// Stable within one plan (`c0`, `c1`, …) — survives edits.
  final String key;
  final DailyTodoistCreate create;
  final bool included;

  String get content => create.content;
  int? get priority => create.priority;

  PlannedTask copyWith({DailyTodoistCreate? create, bool? included}) {
    return PlannedTask(
      key: key,
      create: create ?? this.create,
      included: included ?? this.included,
    );
  }
}

/// One reviewable "done" line (closes a matching open Todoist task).
class PlannedDone {
  const PlannedDone({
    required this.key,
    required this.content,
    this.included = true,
  });

  final String key;
  final String content;
  final bool included;

  PlannedDone copyWith({String? content, bool? included}) {
    return PlannedDone(
      key: key,
      content: content ?? this.content,
      included: included ?? this.included,
    );
  }
}

/// What a · daily page *would* send to Todoist, before anything is sent.
///
/// The confirm screen edits this (include / skip, text, priority);
/// [DailyTodoistSync.execute] then sends only what is still included.
class DailyTodoistPlan {
  const DailyTodoistPlan({
    this.creates = const [],
    this.done = const [],
    this.sectionLabels = const [],
  });

  factory DailyTodoistPlan.fromParse(DailyTodoistParseResult parsed) {
    return DailyTodoistPlan(
      creates: [
        for (var i = 0; i < parsed.creates.length; i++)
          PlannedTask(key: 'c$i', create: parsed.creates[i]),
      ],
      done: [
        for (var i = 0; i < parsed.done.length; i++)
          PlannedDone(key: 'd$i', content: parsed.done[i]),
      ],
      sectionLabels: parsed.sectionLabels,
    );
  }

  final List<PlannedTask> creates;
  final List<PlannedDone> done;
  final List<String> sectionLabels;

  /// Anything to review on screen (items, done lines or label-only sections).
  bool get hasItems =>
      creates.isNotEmpty || done.isNotEmpty || sectionLabels.isNotEmpty;

  int get includedCount =>
      creates.where((t) => _taskSendable(t)).length +
      done.where((d) => d.included && d.content.trim().isNotEmpty).length;

  /// True when sending would do something.
  bool get hasWork => includedCount > 0 || effectiveSectionLabels.isNotEmpty;

  static bool _taskSendable(PlannedTask t) =>
      t.included && t.content.trim().isNotEmpty;

  /// Labels that exist only because of a heading with nothing hanging off it
  /// (shown to the user so the label creation is not a surprise).
  List<String> get labelOnlySections => [
        for (final l in sectionLabels)
          if (!creates.any((t) => t.create.label == l)) l,
      ];

  /// Section labels to ensure: label-only headings, plus headings that still
  /// have at least one included task.
  List<String> get effectiveSectionLabels => [
        for (final l in sectionLabels)
          if (labelOnlySections.contains(l) ||
              creates.any((t) => _taskSendable(t) && t.create.label == l))
            l,
      ];

  /// Included creates in send order. A subtask whose parent was skipped is
  /// promoted to a top-level task (so it still gets its label).
  List<DailyTodoistCreate> get effectiveCreates {
    final sendable = [for (final t in creates) if (_taskSendable(t)) t];
    final nodeIds = <String>{
      for (final t in sendable)
        if (t.create.nodeId != null) t.create.nodeId!,
    };
    return [
      for (final t in sendable)
        _normalized(t.create.copyWith(content: t.content.trim()), nodeIds),
    ];
  }

  static DailyTodoistCreate _normalized(
    DailyTodoistCreate c,
    Set<String> sendableNodeIds,
  ) {
    final parent = c.parentNodeId;
    final orphan = parent != null && !sendableNodeIds.contains(parent);
    final extras = [
      for (final e in c.extraParentNodeIds)
        if (sendableNodeIds.contains(e)) e,
    ];
    if (!orphan && extras.length == c.extraParentNodeIds.length) return c;
    return c.copyWith(clearParent: orphan, extraParentNodeIds: extras);
  }

  List<String> get effectiveDone => [
        for (final d in done)
          if (d.included && d.content.trim().isNotEmpty) d.content.trim(),
      ];

  /// Nesting depth for indenting subtasks in the checklist.
  int depthOf(int index) {
    final byNode = <String, int>{
      for (var i = 0; i < creates.length; i++)
        if (creates[i].create.nodeId != null) creates[i].create.nodeId!: i,
    };
    var depth = 0;
    var current = creates[index].create.parentNodeId;
    final seen = <String>{};
    while (current != null && seen.add(current)) {
      final parentIndex = byNode[current];
      if (parentIndex == null) break;
      depth++;
      current = creates[parentIndex].create.parentNodeId;
    }
    return depth;
  }

  /// Skipping a task also skips its subtasks; re-including touches only it.
  DailyTodoistPlan setTaskIncluded(int index, bool included) {
    final next = List<PlannedTask>.from(creates);
    next[index] = next[index].copyWith(included: included);
    final rootNode = creates[index].create.nodeId;
    if (!included && rootNode != null) {
      final skipped = <String>{rootNode};
      var changed = true;
      while (changed) {
        changed = false;
        for (var i = 0; i < next.length; i++) {
          final c = next[i].create;
          if (c.parentNodeId == null || !skipped.contains(c.parentNodeId)) {
            continue;
          }
          if (next[i].included) {
            next[i] = next[i].copyWith(included: false);
            changed = true;
          }
          if (c.nodeId != null && skipped.add(c.nodeId!)) changed = true;
        }
      }
    }
    return _with(creates: next);
  }

  DailyTodoistPlan setTaskContent(int index, String content) {
    final next = List<PlannedTask>.from(creates);
    next[index] = next[index].copyWith(
      create: next[index].create.copyWith(content: content),
    );
    return _with(creates: next);
  }

  /// [priority] is the Todoist API value (4 = urgent … 2 = low); null clears.
  DailyTodoistPlan setTaskPriority(int index, int? priority) {
    final next = List<PlannedTask>.from(creates);
    next[index] = next[index].copyWith(
      create: next[index].create.copyWith(
            priority: priority,
            clearPriority: priority == null,
          ),
    );
    return _with(creates: next);
  }

  DailyTodoistPlan setDoneIncluded(int index, bool included) {
    final next = List<PlannedDone>.from(done);
    next[index] = next[index].copyWith(included: included);
    return _with(done: next);
  }

  DailyTodoistPlan setDoneContent(int index, String content) {
    final next = List<PlannedDone>.from(done);
    next[index] = next[index].copyWith(content: content);
    return _with(done: next);
  }

  DailyTodoistPlan _with({
    List<PlannedTask>? creates,
    List<PlannedDone>? done,
  }) {
    return DailyTodoistPlan(
      creates: creates ?? this.creates,
      done: done ?? this.done,
      sectionLabels: sectionLabels,
    );
  }
}

/// Parses a · daily capture into a [DailyTodoistPlan] — no network.
class DailyTodoistPlanner {
  DailyTodoistPlanner({
    DailyTodoistParser parser = const DailyTodoistParser(),
    DailyMindmapParser mindmapParser = const DailyMindmapParser(),
    DateTime Function()? clock,
  })  : _parser = parser,
        _mindmap = mindmapParser,
        _clock = clock ?? DateTime.now;

  final DailyTodoistParser _parser;
  final DailyMindmapParser _mindmap;
  final DateTime Function() _clock;

  /// Mindmap hub→branch→leaf when [regions] parse; section markdown otherwise.
  DailyTodoistPlan plan({
    required String markdown,
    List<OcrRegion> regions = const [],
    List<CanvasEdge> edges = const [],
  }) {
    if (regions.isNotEmpty) {
      final mind = _mindmap.parse(
        regions: regions,
        edges: edges,
        referenceDate: _clock(),
      );
      if (mind.hasWork) return DailyTodoistPlan.fromParse(mind.sync);
    }
    return DailyTodoistPlan.fromParse(_parser.parse(markdown));
  }

  /// Same, deriving the mindmap edges from the capture's Gemini canvas so the
  /// confirm screen and the commit pipeline plan identically.
  DailyTodoistPlan planFromMeaning({
    required MeaningResult meaning,
    required List<OcrRegion> regions,
    required String markdown,
  }) {
    final fromGemini = CaptureCoordinator.canvasFromMeaning(
      MeaningResult(
        detectedGlyph: meaning.detectedGlyph,
        regions: regions,
        pageGenre: meaning.pageGenre,
        threadTick: meaning.threadTick,
        rawJson: meaning.rawJson,
      ),
    );

    var planRegions = regions;
    var edges = const <CanvasEdge>[];
    if (fromGemini != null) {
      final edited = ObsidianCanvasFromGemini.applyLabelEdits(
        textNodes: fromGemini.nodes,
        edited: regions,
      );
      planRegions = [
        for (final n in edited)
          OcrRegion(
            id: n.id,
            text: (n.text ?? '').trim(),
            confidence: 0.85,
            bbox: const [0.1, 0.1, 0.3, 0.08],
          ),
      ];
      edges = fromGemini.edges;
    }
    return plan(markdown: markdown, regions: planRegions, edges: edges);
  }
}
