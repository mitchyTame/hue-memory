import '../vault/daily_note_markdown.dart';

/// One Inbox create from a daily section.
class DailyTodoistCreate {
  const DailyTodoistCreate({
    required this.content,
    required this.label,
    this.priority,
  });

  final String content;

  /// Todoist personal label — section name (normalized), created if missing.
  final String label;

  /// Todoist priority 1–4 (4 = urgent). Null = API default.
  final int? priority;
}

/// Structured parse of a · daily OCR / confirm body for Todoist sync.
class DailyTodoistParseResult {
  const DailyTodoistParseResult({
    this.creates = const [],
    this.done = const [],
  });

  final List<DailyTodoistCreate> creates;
  final List<String> done;
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
  static String normalizeSectionKey(String raw) {
    var t = raw.trim();
    if (t.startsWith('**') && t.endsWith('**')) {
      t = t.substring(2, t.length - 2).trim();
    }
    if (t.endsWith(':')) t = t.substring(0, t.length - 1).trim();
    return t.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  DailyTodoistParseResult parse(String source) {
    final md = DailyNoteMarkdown.interpret(source);
    if (md.trim().isEmpty) {
      return const DailyTodoistParseResult();
    }

    final creates = <DailyTodoistCreate>[];
    final done = <String>[];
    DailySectionAction? active;

    for (final raw in md.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;

      final section = _sectionName(line);
      if (section != null) {
        final action = classifySection(section);
        active = action;
        final inlineItem = _inlineSectionItem(line, section);
        if (inlineItem != null && inlineItem.isNotEmpty) {
          _absorbItem(action, inlineItem, creates, done);
        }
        continue;
      }

      if (active == null || active.kind == DailySectionKind.skip) continue;

      final content = _itemContent(line);
      if (content == null || content.isEmpty) continue;
      _absorbItem(active, content, creates, done);
    }

    return DailyTodoistParseResult(creates: creates, done: done);
  }

  static void _absorbItem(
    DailySectionAction active,
    String content,
    List<DailyTodoistCreate> creates,
    List<String> done,
  ) {
    switch (active.kind) {
      case DailySectionKind.done:
        done.add(content);
      case DailySectionKind.create:
        final label = active.label;
        if (label == null || label.isEmpty) return;
        creates.add(
          DailyTodoistCreate(
            content: content,
            label: label,
            priority: active.priority ?? priorityForLabel(label),
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

    final plain = RegExp(r'^([A-Za-z][\w\s/&-]{0,48}):\s*$').firstMatch(trimmed);
    if (plain != null) return plain.group(1);

    final inline = RegExp(
      r'^([A-Za-z][\w\s/&-]{0,48}):\s+\S',
    ).firstMatch(trimmed);
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

  static String _cleanContent(String raw) {
    var t = raw.trim();
    t = t.replaceFirst(RegExp(r'^[-*+·•]\s+'), '');
    return t.trim();
  }
}
