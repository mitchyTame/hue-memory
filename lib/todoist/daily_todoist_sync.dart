import 'daily_todoist_parser.dart';
import 'todoist_client.dart';
import 'unmatched_done_store.dart';

/// Outcome of syncing one · daily capture to Todoist Inbox.
class DailyTodoistSyncResult {
  const DailyTodoistSyncResult({
    this.createdCount = 0,
    this.completedCount = 0,
    this.unmatchedDone = const [],
  });

  final int createdCount;
  final int completedCount;
  final List<String> unmatchedDone;

  bool get hasUnmatched => unmatchedDone.isNotEmpty;

  String get snackbarMessage {
    final parts = <String>[];
    if (createdCount > 0) {
      parts.add(
        createdCount == 1
            ? '1 task → Todoist Inbox'
            : '$createdCount tasks → Todoist Inbox',
      );
    }
    if (completedCount > 0) {
      parts.add(
        completedCount == 1
            ? '1 completed'
            : '$completedCount completed',
      );
    }
    if (hasUnmatched) {
      parts.add(
        unmatchedDone.length == 1
            ? '1 done item not found'
            : '${unmatchedDone.length} done items not found',
      );
    }
    if (parts.isEmpty) return 'Nothing to sync to Todoist';
    return parts.join(' · ');
  }
}

/// Parses daily markdown and syncs creates / done matches via [TodoistClient].
class DailyTodoistSync {
  DailyTodoistSync({
    required TodoistClient client,
    required UnmatchedDoneStore unmatchedStore,
    DailyTodoistParser parser = const DailyTodoistParser(),
    DateTime Function()? clock,
  })  : _client = client,
        _unmatched = unmatchedStore,
        _parser = parser,
        _clock = clock ?? DateTime.now;

  final TodoistClient _client;
  final UnmatchedDoneStore _unmatched;
  final DailyTodoistParser _parser;
  final DateTime Function() _clock;

  Future<DailyTodoistSyncResult> syncMarkdown(String source) async {
    final parsed = _parser.parse(source);
    if (parsed.creates.isEmpty && parsed.done.isEmpty) {
      return const DailyTodoistSyncResult();
    }

    final labelNames = <String>{
      for (final c in parsed.creates) c.label,
    };
    if (labelNames.isNotEmpty) {
      await _client.ensureLabels(labelNames);
    }

    var created = 0;
    for (final item in parsed.creates) {
      await _client.createInboxTask(
        content: item.content,
        labels: [item.label],
        priority: item.priority,
      );
      created++;
    }

    var completed = 0;
    final unmatched = <String>[];
    if (parsed.done.isNotEmpty) {
      final open = await _client.listOpenTasks();
      final remaining = List<TodoistTask>.from(open);
      for (final doneText in parsed.done) {
        final match = findMatchingOpenTask(remaining, doneText);
        if (match == null) {
          unmatched.add(doneText);
          continue;
        }
        await _client.closeTask(match.id);
        remaining.removeWhere((t) => t.id == match.id);
        completed++;
      }
    }

    if (unmatched.isNotEmpty) {
      final now = _clock();
      await _unmatched.append([
        for (final c in unmatched)
          UnmatchedDoneItem(content: c, recordedAt: now),
      ]);
    }

    return DailyTodoistSyncResult(
      createdCount: created,
      completedCount: completed,
      unmatchedDone: unmatched,
    );
  }

  /// Best-effort match of a paper "done" line to an open Todoist task.
  ///
  /// Returns null when no open task matches (caller records unmatched UI).
  static TodoistTask? findMatchingOpenTask(
    List<TodoistTask> openTasks,
    String doneText,
  ) {
    final needle = normalizeTaskText(doneText);
    if (needle.isEmpty) return null;

    TodoistTask? exact;
    TodoistTask? contains;
    for (final task in openTasks) {
      final hay = normalizeTaskText(task.content);
      if (hay.isEmpty) continue;
      if (hay == needle) {
        exact = task;
        break;
      }
      if (hay.contains(needle) || needle.contains(hay)) {
        // Prefer longer overlap; keep first reasonable contains.
        contains ??= task;
      }
    }
    return exact ?? contains;
  }

  static String normalizeTaskText(String raw) {
    var t = raw.trim().toLowerCase();
    t = t.replaceFirst(RegExp(r'^[-*+·•]\s+'), '');
    t = t.replaceFirst(RegExp(r'^\[([ xX])\]\s*'), '');
    t = t.replaceFirst(RegExp(r'^(☐|☑|☒|□|■)\s*'), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }
}
