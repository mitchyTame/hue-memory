import '../vault/daily_note_markdown.dart';
import 'due_phrase.dart';
import 'task_text.dart';

/// One Inbox create from a daily section / mindmap node.
class DailyTodoistCreate {
  const DailyTodoistCreate({
    required this.content,
    required this.label,
    this.priority,
    this.nodeId,
    this.parentNodeId,
    this.dueDate,
    this.dueHasTime = false,
    this.dueString,
    this.duePhrase,
    this.extraParentNodeIds = const [],
    this.requestId,
    this.updateTodoistId,
    this.previousContent,
    this.previousPriority,
    this.previousDue,
    this.reopen = false,
  });

  final String content;

  /// Todoist personal label — section name (normalized), created if missing.
  final String label;

  /// Todoist priority 1–4 (4 = urgent). Null = API default.
  final int? priority;

  /// Mindmap node id (for parent/subtask wiring + dedupe).
  final String? nodeId;

  /// Mindmap parent **task** node id → Todoist `parent_id` subtask.
  final String? parentNodeId;

  /// Due date, only when the page wrote one for this task (relative words
  /// and a bare time resolve against the page date). No date on paper → no
  /// due date.
  final DateTime? dueDate;

  /// [dueDate] carries a time of day (Todoist `due_datetime`).
  final bool dueHasTime;

  /// Sent as Todoist `due_string` when the phrase is left to Todoist to read
  /// (recurrence such as `every 1st`). Mutually exclusive with [dueDate].
  final String? dueString;

  /// The date words as written on paper (without `@` / `|`).
  final String? duePhrase;

  bool get hasDue => dueDate != null || dueString != null;

  /// `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM` (local) or the Todoist due string, for
  /// comparing captures.
  String? get dueKey =>
      dueString ?? dueKeyOf(dueDate, hasTime: dueHasTime);

  /// What the review checklist shows for this due, or null.
  String? get dueLabel {
    if (dueString != null) {
      return DuePhrase.describe(TaskDue.todoist(dueString!));
    }
    final d = dueDate;
    if (d == null) return null;
    return DuePhrase.describe(
      TaskDue.at(duePhrase ?? '', d, hasTime: dueHasTime),
    );
  }

  /// This create with [due] (or no due when null).
  DailyTodoistCreate withDue(TaskDue? due) {
    final cleared = copyWith(clearDue: true);
    if (due == null) return cleared;
    return DailyTodoistCreate(
      content: content,
      label: label,
      priority: priority,
      nodeId: nodeId,
      parentNodeId: parentNodeId,
      dueDate: due.date,
      dueHasTime: due.date != null && due.hasTime,
      dueString: due.date == null ? due.dueString : null,
      duePhrase: due.phrase,
      extraParentNodeIds: extraParentNodeIds,
      requestId: requestId,
      updateTodoistId: updateTodoistId,
      previousContent: previousContent,
      previousPriority: previousPriority,
      previousDue: previousDue,
      reopen: reopen,
    );
  }

  static String? dueKeyOf(DateTime? due, {required bool hasTime}) {
    if (due == null) return null;
    String two(int v) => v.toString().padLeft(2, '0');
    final day = '${due.year.toString().padLeft(4, '0')}-${two(due.month)}-'
        '${two(due.day)}';
    return hasTime ? '${day}T${two(due.hour)}:${two(due.minute)}' : day;
  }

  /// Extra mindmap parents that also link here (same Todoist task; linked
  /// via description after create — Todoist allows one `parent_id` only).
  final List<String> extraParentNodeIds;

  /// Todoist `X-Request-Id` for this create, fixed on the first attempt so a
  /// retry cannot create the task twice.
  final String? requestId;

  /// Set when a re-capture matched a task from the ledger: this item then
  /// updates that Todoist task instead of creating a new one.
  final String? updateTodoistId;

  /// What the ledger recorded for [updateTodoistId] (to skip no-op updates).
  final String? previousContent;
  final int? previousPriority;

  /// [dueKey] the matched task already has, when known.
  final String? previousDue;

  bool get isUpdate => updateTodoistId != null;

  /// The matched task is completed in Todoist and the user chose to send it
  /// again: reopen it before updating.
  final bool reopen;

  DailyTodoistCreate copyWith({
    String? content,
    int? priority,
    bool clearPriority = false,
    String? parentNodeId,
    bool clearParent = false,
    List<String>? extraParentNodeIds,
    String? requestId,
    String? updateTodoistId,
    String? previousContent,
    int? previousPriority,
    String? previousDue,
    bool? reopen,
    bool clearUpdate = false,
    DateTime? dueDate,
    bool? dueHasTime,
    bool clearDue = false,
  }) {
    return DailyTodoistCreate(
      content: content ?? this.content,
      label: label,
      priority: clearPriority ? null : (priority ?? this.priority),
      nodeId: nodeId,
      parentNodeId: clearParent ? null : (parentNodeId ?? this.parentNodeId),
      dueDate: clearDue ? null : (dueDate ?? this.dueDate),
      dueHasTime: clearDue ? false : (dueHasTime ?? this.dueHasTime),
      dueString: clearDue ? null : dueString,
      duePhrase: clearDue ? null : duePhrase,
      extraParentNodeIds: extraParentNodeIds ?? this.extraParentNodeIds,
      requestId: clearUpdate ? null : (requestId ?? this.requestId),
      updateTodoistId:
          clearUpdate ? null : (updateTodoistId ?? this.updateTodoistId),
      previousContent:
          clearUpdate ? null : (previousContent ?? this.previousContent),
      previousPriority:
          clearUpdate ? null : (previousPriority ?? this.previousPriority),
      previousDue: clearUpdate ? null : (previousDue ?? this.previousDue),
      reopen: clearUpdate ? false : (reopen ?? this.reopen),
    );
  }
}

/// Structured parse of a · daily OCR / confirm body for Todoist sync.
class DailyTodoistParseResult {
  const DailyTodoistParseResult({
    this.creates = const [],
    this.done = const [],
    this.sectionLabels = const [],
  });

  final List<DailyTodoistCreate> creates;
  final List<String> done;

  /// Every create-section label seen (including sections with no tasks yet),
  /// so each name on the page exists as a Todoist label.
  final List<String> sectionLabels;

  bool get hasWork =>
      creates.isNotEmpty || done.isNotEmpty || sectionLabels.isNotEmpty;
}

/// How a section heading should drive Todoist sync.
enum DailySectionKind { create, done, skip }

/// Result of classifying a daily section heading.
class DailySectionAction {
  const DailySectionAction.create(this.label, {this.priority})
      : kind = DailySectionKind.create;
  const DailySectionAction.done()
      : kind = DailySectionKind.done,
        label = null,
        priority = null;
  const DailySectionAction.skip()
      : kind = DailySectionKind.skip,
        label = null,
        priority = null;

  final DailySectionKind kind;
  final String? label;
  final int? priority;

  bool get isCreate => kind == DailySectionKind.create;
  bool get isDone => kind == DailySectionKind.done;
  bool get isSkip => kind == DailySectionKind.skip;
}

/// Maps daily markdown sections → Todoist labels / done list.
///
/// Any heading becomes a Todoist label (created on demand). Known aliases
/// (`Important` → `high`, etc.) keep priority mapping. Journal noise
/// (`Notes` / `Log`) and empty lines are skipped — not unknown headings.
class DailyTodoistParser {
  const DailyTodoistParser();

  /// Classify a raw section heading for sync (markdown or mindmap branch).
  static DailySectionAction classifySection(String rawLabel) {
    final key = normalizeSectionKey(rawLabel);
    switch (key) {
      case 'done':
      case 'completed':
      case 'complete':
        return const DailySectionAction.done();
      case 'logs':
      case 'log':
      case 'notes':
      case 'note':
        return const DailySectionAction.skip();
      case 'high':
      case 'important':
      case 'priority':
        return const DailySectionAction.create('high', priority: 4);
      case 'medium':
      case 'med':
        return const DailySectionAction.create('medium', priority: 3);
      case 'low':
        return const DailySectionAction.create('low', priority: 2);
      case 'events':
      case 'event':
        return const DailySectionAction.create('events');
      case 'reminders':
      case 'reminder':
        return const DailySectionAction.create('reminders');
      default:
        if (key.isEmpty) return const DailySectionAction.skip();
        return DailySectionAction.create(key);
    }
  }

  /// Optional Todoist priority for a create label (4 = urgent).
  static int? priorityForLabel(String label) {
    switch (label) {
      case 'high':
        return 4;
      case 'medium':
        return 3;
      case 'low':
        return 2;
      default:
        return null;
    }
  }

  /// Public normalize used for labels + tests.
  ///
  /// Strips heading / bullet / checkbox / `@` prefixes and icon glyphs drawn
  /// next to a section name so `🛒 Shopping:` and `## shopping` share a label.
  static String normalizeSectionKey(String raw) {
    var t = raw.trim();
    if (t.startsWith('**') && t.endsWith('**') && t.length >= 4) {
      t = t.substring(2, t.length - 2).trim();
    }
    t = t.replaceFirst(_sectionPrefixNoise, '');
    t = t.replaceFirst(_sectionSuffixNoise, '');
    if (t.endsWith(':')) t = t.substring(0, t.length - 1).trim();
    return t.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static final RegExp _sectionPrefixNoise = RegExp(
    r'^(?:[\s#*+\-·•☐☑☒□■@:]|\p{So}|\p{Sk}|\p{Cf}|\u{FE0F})+',
    unicode: true,
  );
  static final RegExp _sectionSuffixNoise = RegExp(
    r'(?:[\s*:]|\p{So}|\p{Sk}|\p{Cf}|\u{FE0F})+$',
    unicode: true,
  );

  /// Heading shapes that may end with `:` on their own line (any script —
  /// `Zoë:`, `Thandiwé:`, `Mum's:`).
  static final RegExp plainSectionLine = RegExp(
    r"^([\p{L}][\p{L}\p{M}\p{N}_\s/&'’.\-]{0,48}):\s*$",
    unicode: true,
  );

  /// `Heading: item` on one line. Narrower than [plainSectionLine] so prose
  /// such as `Don't forget: milk` stays a task.
  static final RegExp inlineSectionLine = RegExp(
    r'^([\p{L}][\p{L}\p{M}\p{N}_\s/&\-]{0,48}):\s+\S',
    unicode: true,
  );

  /// A task line under a create section. A date phrase (`tomorrow @ 4pm`,
  /// `| 16:50`, `every 1st`) becomes the due and is removed from the text;
  /// relative words resolve against [pageDate] (today when the page has no
  /// date). With no date written there is no due date at all.
  static DailyTodoistCreate taskFromText({
    required String text,
    required String label,
    int? priority,
    String? nodeId,
    String? parentNodeId,
    DateTime? pageDate,
  }) {
    final found = DuePhrase.extract(text, pageDate: pageDate ?? DateTime.now());
    return DailyTodoistCreate(
      content: found?.content ?? text,
      label: label,
      priority: priority,
      nodeId: nodeId,
      parentNodeId: parentNodeId,
    ).withDue(found?.due);
  }

  /// [pageDate] is the day the page is for; it only matters for `| HH:MM`.
  DailyTodoistParseResult parse(String source, {DateTime? pageDate}) {
    final md = DailyNoteMarkdown.interpret(source);
    if (md.trim().isEmpty) {
      return const DailyTodoistParseResult();
    }

    final creates = <DailyTodoistCreate>[];
    final done = <String>[];
    final sectionLabels = <String>[];
    DailySectionAction? active;

    for (final raw in md.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;

      final section = _sectionName(line);
      if (section != null) {
        final action = classifySection(section);
        active = action;
        final label = action.label;
        if (action.isCreate &&
            label != null &&
            label.isNotEmpty &&
            !sectionLabels.contains(label)) {
          sectionLabels.add(label);
        }
        final inlineItem = _inlineSectionItem(line, section);
        if (inlineItem != null && inlineItem.isNotEmpty) {
          _absorbItem(
            action,
            TaskText.withoutMarks(inlineItem),
            creates,
            done,
            ticked: TaskText.isTicked(inlineItem),
            pageDate: pageDate,
          );
        }
        continue;
      }

      if (active == null || active.kind == DailySectionKind.skip) continue;

      final item = _itemContent(line);
      if (item == null || item.isEmpty) continue;
      final content = TaskText.withoutMarks(item);
      if (content.isEmpty) continue;
      _absorbItem(
        active,
        content,
        creates,
        done,
        ticked: TaskText.isTicked(line) || TaskText.isTicked(item),
        pageDate: pageDate,
      );
    }

    return DailyTodoistParseResult(
      creates: creates,
      done: done,
      sectionLabels: sectionLabels,
    );
  }

  static void _absorbItem(
    DailySectionAction active,
    String content,
    List<DailyTodoistCreate> creates,
    List<String> done, {
    bool ticked = false,
    DateTime? pageDate,
  }) {
    switch (active.kind) {
      case DailySectionKind.done:
        done.add(content);
      case DailySectionKind.create:
        final label = active.label;
        if (label == null || label.isEmpty) return;
        // Ticked off on paper: close the existing task, don't create it.
        if (ticked) {
          done.add(content);
          return;
        }
        creates.add(
          taskFromText(
            text: content,
            label: label,
            priority: active.priority ?? priorityForLabel(label),
            pageDate: pageDate,
          ),
        );
      case DailySectionKind.skip:
        return;
    }
  }

  static String? _inlineSectionItem(String line, String sectionName) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#') || trimmed.startsWith('**')) return null;
    final escaped = RegExp.escape(sectionName.trim());
    final m = RegExp(
      '^$escaped:\\s+(.+)\$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (m == null) return null;
    return _cleanContent(m.group(1) ?? '');
  }

  static String? _sectionName(String line) {
    final trimmed = line.trim();
    final bold = RegExp(r'^\*\*([^*].*?)\*\*:?\s*$').firstMatch(trimmed);
    if (bold != null) return bold.group(1);

    final plain = plainSectionLine.firstMatch(trimmed);
    if (plain != null) return plain.group(1);

    final inline = inlineSectionLine.firstMatch(trimmed);
    if (inline != null) return inline.group(1);

    final heading = RegExp(r'^#{1,3}\s+(.+?)\s*$').firstMatch(trimmed);
    if (heading != null) {
      var h = heading.group(1)!.trim();
      if (h.endsWith(':')) h = h.substring(0, h.length - 1).trim();
      return h;
    }
    return null;
  }

  static String? _itemContent(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    if (_sectionName(trimmed) != null) return null;

    if (RegExp(
      r"^(\d{1,2}\s+[A-Za-z]{3,9}\s+'?\d{2,4}|\d{4}-\d{2}-\d{2})\s*$",
    ).hasMatch(trimmed)) {
      return null;
    }
    if (RegExp(r'^[\u2600-\u26FF\u2700-\u27BF☉○·•△◇∼≡]+$').hasMatch(trimmed)) {
      return null;
    }

    final checkbox = RegExp(
      r'^(?:[-*+]\s+)?\[([ xX])\]\s*(.*)$',
    ).firstMatch(trimmed);
    if (checkbox != null) {
      return _cleanContent(checkbox.group(2) ?? '');
    }

    final ocrBox = RegExp(
      r'^(?:☐|☑|☒|□|■)\s*(.*)$',
    ).firstMatch(trimmed);
    if (ocrBox != null) {
      return _cleanContent(ocrBox.group(1) ?? '');
    }

    final bullet = RegExp(r'^[-*+·•]\s+(.*)$').firstMatch(trimmed);
    if (bullet != null) {
      return _cleanContent(bullet.group(1) ?? '');
    }

    return _cleanContent(trimmed);
  }

  /// Strip bullet / checkbox / OCR box prefixes from one item line.
  static String cleanItemLine(String raw) {
    final trimmed = raw.trim();
    final checkbox = RegExp(
      r'^(?:[-*+]\s+)?\[([ xX])\]\s*(.*)$',
    ).firstMatch(trimmed);
    if (checkbox != null) return _cleanContent(checkbox.group(2) ?? '');
    final ocrBox = RegExp(r'^(?:☐|☑|☒|□|■)\s*(.*)$').firstMatch(trimmed);
    if (ocrBox != null) return _cleanContent(ocrBox.group(1) ?? '');
    return _cleanContent(trimmed);
  }

  static String _cleanContent(String raw) {
    var t = raw.trim();
    t = t.replaceFirst(RegExp(r'^[-*+·•]\s+'), '');
    return t.trim();
  }
}
