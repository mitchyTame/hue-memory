import '../vault/daily_note_markdown.dart';

/// One Inbox create from a daily section.
class DailyTodoistCreate {
  const DailyTodoistCreate({
    required this.content,
    required this.label,
    this.priority,
  });

  final String content;

  /// Todoist personal label name: `high` | `medium` | `low` | `events` | `reminders`.
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

/// Maps daily markdown sections → Todoist labels / done list.
///
/// Drops Logs, Notes, and plain checkboxes outside sync sections.
class DailyTodoistParser {
  const DailyTodoistParser();

  static const createLabels = <String>{
    'high',
    'medium',
    'low',
    'events',
    'reminders',
  };

  /// Section heading → sync kind (`high`…`reminders`, `done`, or null = drop).
  static String? mapSection(String rawLabel) {
    final key = _normalizeSectionKey(rawLabel);
    switch (key) {
      case 'high':
      case 'important':
      case 'priority':
        return 'high';
      case 'medium':
      case 'med':
        return 'medium';
      case 'low':
        return 'low';
      case 'events':
      case 'event':
        return 'events';
      case 'reminders':
      case 'reminder':
        return 'reminders';
      case 'done':
      case 'completed':
      case 'complete':
        return 'done';
      case 'logs':
      case 'log':
      case 'notes':
      case 'note':
        return null;
      default:
        return null;
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

  DailyTodoistParseResult parse(String source) {
    final md = DailyNoteMarkdown.interpret(source);
    if (md.trim().isEmpty) {
      return const DailyTodoistParseResult();
    }

    final creates = <DailyTodoistCreate>[];
    final done = <String>[];
    String? active; // sync kind or '' for dropped / unknown

    for (final raw in md.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;

      final section = _sectionName(line);
      if (section != null) {
        active = mapSection(section) ?? '';
        continue;
      }

      // Outside a sync section: ignore (incl. plain checkboxes / prose).
      if (active == null || active.isEmpty) continue;

      final content = _itemContent(line);
      if (content == null || content.isEmpty) continue;

      if (active == 'done') {
        done.add(content);
        continue;
      }

      if (createLabels.contains(active)) {
        creates.add(
          DailyTodoistCreate(
            content: content,
            label: active,
            priority: priorityForLabel(active),
          ),
        );
      }
    }

    return DailyTodoistParseResult(creates: creates, done: done);
  }

  static String _normalizeSectionKey(String raw) {
    var t = raw.trim();
    if (t.startsWith('**') && t.endsWith('**')) {
      t = t.substring(2, t.length - 2).trim();
    }
    if (t.endsWith(':')) t = t.substring(0, t.length - 1).trim();
    return t.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String? _sectionName(String line) {
    final trimmed = line.trim();
    final bold = RegExp(r'^\*\*([^*].*?)\*\*:?\s*$').firstMatch(trimmed);
    if (bold != null) return bold.group(1);

    final plain = RegExp(r'^([A-Za-z][\w\s/&-]{0,48}):\s*$').firstMatch(trimmed);
    if (plain != null) return plain.group(1);

    final heading = RegExp(r'^#{1,3}\s+(.+?)\s*$').firstMatch(trimmed);
    if (heading != null) {
      var h = heading.group(1)!.trim();
      if (h.endsWith(':')) h = h.substring(0, h.length - 1).trim();
      return h;
    }
    return null;
  }

  /// Extract task text from a bullet / checkbox / plain line under a section.
  static String? _itemContent(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    if (_sectionName(trimmed) != null) return null;

    // Dates / lone glyphs are not tasks.
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

    // Plain prose under a sync section counts as a task line.
    return _cleanContent(trimmed);
  }

  static String _cleanContent(String raw) {
    var t = raw.trim();
    // Strip nested bullet leftovers.
    t = t.replaceFirst(RegExp(r'^[-*+·•]\s+'), '');
    return t.trim();
  }
}
