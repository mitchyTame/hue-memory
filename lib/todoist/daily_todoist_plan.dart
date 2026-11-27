import '../gemini/capture_coordinator.dart';
import '../gemini/obsidian_canvas_from_gemini.dart';
import '../ocr/ocr_client.dart';
import '../writers/canvas_writer.dart';
import 'daily_mindmap_parser.dart';
import 'daily_todoist_parser.dart';
import 'due_phrase.dart';

/// What Todoist says about a matched task right now.
enum RemoteState {
  /// Not checked (offline / no token).
  unknown,
  open,
  completed,

  /// Deleted, or no longer returned by Todoist.
  gone,
}

/// An earlier Todoist task (from the ledger) that a re-captured item matches.
class LedgerMatch {
  const LedgerMatch({
    required this.todoistId,
    required this.content,
    this.priority,
    this.pageId,
    this.due,
    this.fromLive = false,
    this.remote = RemoteState.unknown,
  });

  final String todoistId;
  final String content;
  final int? priority;
  final String? pageId;

  /// [DailyTodoistCreate.dueKey] the task already has, when known.
  final String? due;

  /// Matched against the open Todoist tasks rather than the local ledger.
  final bool fromLive;

  final RemoteState remote;

  bool get isCompleted => remote == RemoteState.completed;
  bool get isGone => remote == RemoteState.gone;

  LedgerMatch withRemote(RemoteState state) => LedgerMatch(
        todoistId: todoistId,
        content: content,
        priority: priority,
        pageId: pageId,
        due: due,
        fromLive: fromLive,
        remote: state,
      );
}

/// One reviewable Todoist create (checkbox + editable text + priority).
///
/// When a re-capture matched an earlier task, [match] is set and — unless the
/// user switched it off ([useMatch]) — sending updates that task instead of
/// creating a duplicate.
class PlannedTask {
  const PlannedTask({
    required this.key,
    required this.create,
    this.included = true,
    this.match,
    this.useMatch = true,
  });

  /// Stable within one plan (`c0`, `c1`, …) — survives edits.
  final String key;
  final DailyTodoistCreate create;
  final bool included;
  final LedgerMatch? match;
  final bool useMatch;

  String get content => create.content;
  int? get priority => create.priority;

  /// Sending will update an existing Todoist task (a gone task cannot be).
  bool get isUpdate => match != null && useMatch && !match!.isGone;

  /// Sending reopens the matched task first — only when the user ticked an
  /// item whose Todoist task is already completed.
  bool get reopens => isUpdate && match!.isCompleted;

  PlannedTask copyWith({
    DailyTodoistCreate? create,
    bool? included,
    LedgerMatch? match,
    bool? useMatch,
  }) {
    return PlannedTask(
      key: key,
      create: create ?? this.create,
      included: included ?? this.included,
      match: match ?? this.match,
      useMatch: useMatch ?? this.useMatch,
    );
  }
}

/// One reviewable "done" line (ticked or struck through on paper): closes
/// the matching Todoist task.
///
/// [match] is the task it was linked to before review. A match that is
/// already completed or gone in Todoist is shown as such and not sent.
class PlannedDone {
  const PlannedDone({
    required this.key,
    required this.content,
    this.included = true,
    this.match,
  });

  final String key;
  final String content;
  final bool included;
  final LedgerMatch? match;

  /// Nothing left to close in Todoist.
  bool get alreadySettled =>
      match != null && (match!.isCompleted || match!.isGone);

  bool get sendable =>
      included && content.trim().isNotEmpty && !alreadySettled;

  PlannedDone copyWith({
    String? content,
    bool? included,
    LedgerMatch? match,
    bool clearMatch = false,
  }) {
    return PlannedDone(
      key: key,
      content: content ?? this.content,
      included: included ?? this.included,
      match: clearMatch ? null : (match ?? this.match),
    );
  }
}

/// A done line as sent: close [todoistId] when the review linked one,
/// otherwise find the task by [content].
class DoneTarget {
  const DoneTarget(this.content, {this.todoistId});

  final String content;
  final String? todoistId;
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
    this.linkedPageId,
    this.linkedByPageId = false,
    this.rememberedCount,
    this.liveChecked = false,
    this.remoteChecked = false,
    this.pageDate,
  });

  factory DailyTodoistPlan.fromParse(
    DailyTodoistParseResult parsed, {
    DateTime? pageDate,
  }) {
    return DailyTodoistPlan(
      pageDate: pageDate,
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

  /// Earlier capture this page was recognised as a re-capture of (set by
  /// [LedgerLinker]); null for a page seen for the first time.
  final String? linkedPageId;

  /// True when [linkedPageId] is this very page ID, not just similar text.
  final bool linkedByPageId;

  bool get hasLinkedPage => linkedPageId != null;

  /// Open ledger entries the linker compared against (null = not linked).
  final int? rememberedCount;

  /// The open Todoist tasks were also checked for matches.
  final bool liveChecked;

  /// Matched tasks' live Todoist state (open / completed / gone) is known.
  final bool remoteChecked;

  /// The day the page is for (hub date, else the capture day): what
  /// relative words in an edited due ("tomorrow") resolve against.
  final DateTime? pageDate;

  /// [pageDate] as `YYYY-MM-DD` (ledger key).
  String? get pageDay => DailyTodoistCreate.dueKeyOf(pageDate, hasTime: false);

  /// At least one item matched an earlier task (ledger or live).
  bool get hasLinks =>
      creates.any((t) => t.match != null) || done.any((d) => d.match != null);

  int get updateCount =>
      creates.where((t) => _taskSendable(t) && t.isUpdate).length;
  int get newCount =>
      creates.where((t) => _taskSendable(t) && !t.isUpdate).length;

  /// Anything to review on screen (items, done lines or label-only sections).
  bool get hasItems =>
      creates.isNotEmpty || done.isNotEmpty || sectionLabels.isNotEmpty;

  int get includedCount =>
      creates.where((t) => _taskSendable(t)).length +
      done.where((d) => d.sendable).length;

  /// Ticked items that will close a task.
  int get completeCount => done.where((d) => d.sendable).length;

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
        _normalized(_forSend(t), nodeIds),
    ];
  }

  static DailyTodoistCreate _forSend(PlannedTask t) {
    final base = t.create.copyWith(content: t.content.trim());
    final m = t.match;
    if (m == null || !t.isUpdate) return base.copyWith(clearUpdate: true);
    return base.copyWith(
      updateTodoistId: m.todoistId,
      previousContent: m.content,
      previousPriority: m.priority,
      previousDue: m.due,
      reopen: t.reopens,
    );
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
        for (final d in effectiveDoneTargets) d.content,
      ];

  List<DoneTarget> get effectiveDoneTargets => [
        for (final d in done)
          if (d.sendable)
            DoneTarget(d.content.trim(), todoistId: d.match?.todoistId),
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

  /// Switch a matched item between "update the earlier task" and "new task".
  DailyTodoistPlan setTaskUpdate(int index, bool update) {
    if (creates[index].match == null) return this;
    final next = List<PlannedTask>.from(creates);
    next[index] = next[index].copyWith(useMatch: update);
    return _with(creates: next);
  }

  /// Record which earlier task each item matches (see [LedgerLinker]).
  /// [doneMatches] links ticked items to the task they close.
  DailyTodoistPlan withLinks({
    required Map<int, LedgerMatch> matches,
    Map<int, LedgerMatch> doneMatches = const {},
    String? linkedPageId,
    bool linkedByPageId = false,
    int? rememberedCount,
    bool? liveChecked,
  }) {
    final next = [
      for (var i = 0; i < creates.length; i++)
        matches.containsKey(i)
            ? _settle(creates[i].copyWith(match: matches[i], useMatch: true))
            : creates[i],
    ];
    final nextDone = [
      for (var i = 0; i < done.length; i++)
        doneMatches.containsKey(i)
            ? _settleDone(done[i].copyWith(match: doneMatches[i]))
            : done[i],
    ];
    return DailyTodoistPlan(
      creates: next,
      done: nextDone,
      sectionLabels: sectionLabels,
      linkedPageId: linkedPageId ?? this.linkedPageId,
      linkedByPageId: linkedByPageId || this.linkedByPageId,
      rememberedCount: rememberedCount ?? this.rememberedCount,
      liveChecked: liveChecked ?? this.liveChecked,
      remoteChecked: remoteChecked,
      pageDate: pageDate,
    );
  }

  /// Every Todoist task id the review linked to (creates and done lines).
  Set<String> get linkedTodoistIds => {
        for (final t in creates)
          if (t.match != null) t.match!.todoistId,
        for (final d in done)
          if (d.match != null) d.match!.todoistId,
      };

  /// Apply Todoist's live state to every match. A completed or gone task is
  /// not sent again by default: its item starts unticked (a ticked item on
  /// paper has nothing left to close).
  DailyTodoistPlan withRemoteStates(Map<String, RemoteState> states) {
    LedgerMatch? apply(LedgerMatch? m) {
      if (m == null) return null;
      final s = states[m.todoistId];
      return s == null ? m : m.withRemote(s);
    }

    return DailyTodoistPlan(
      creates: [
        for (final t in creates)
          t.match == null ? t : _settle(t.copyWith(match: apply(t.match))),
      ],
      done: [
        for (final d in done)
          d.match == null ? d : _settleDone(d.copyWith(match: apply(d.match))),
      ],
      sectionLabels: sectionLabels,
      linkedPageId: linkedPageId,
      linkedByPageId: linkedByPageId,
      rememberedCount: rememberedCount,
      liveChecked: liveChecked,
      remoteChecked: true,
      pageDate: pageDate,
    );
  }

  static PlannedTask _settle(PlannedTask t) {
    final m = t.match;
    if (m == null) return t;
    if (m.isCompleted || m.isGone) return t.copyWith(included: false);
    return t;
  }

  static PlannedDone _settleDone(PlannedDone d) {
    final m = d.match;
    if (m == null) return d;
    if (m.isCompleted || m.isGone) return d.copyWith(included: false);
    return d;
  }

  /// Remove a task's due date before sending.
  DailyTodoistPlan clearTaskDue(int index) => setTaskDue(index, null);

  /// Replace a task's due (from an edit in review); null removes it.
  DailyTodoistPlan setTaskDue(int index, TaskDue? due) {
    final next = List<PlannedTask>.from(creates);
    next[index] = next[index].copyWith(
      create: next[index].create.withDue(due),
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
      linkedPageId: linkedPageId,
      linkedByPageId: linkedByPageId,
      rememberedCount: rememberedCount,
      liveChecked: liveChecked,
      remoteChecked: remoteChecked,
      pageDate: pageDate,
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
    final today = _clock();
    if (regions.isNotEmpty) {
      final mind = _mindmap.parse(
        regions: regions,
        edges: edges,
        referenceDate: today,
      );
      if (mind.hasWork) {
        return DailyTodoistPlan.fromParse(
          mind.sync,
          pageDate: mind.hubDate ?? today,
        );
      }
    }
    return DailyTodoistPlan.fromParse(
      _parser.parse(markdown, pageDate: today),
      pageDate: today,
    );
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
