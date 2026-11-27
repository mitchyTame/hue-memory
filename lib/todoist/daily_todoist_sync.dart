import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../ocr/ocr_client.dart';
import '../writers/canvas_writer.dart';
import 'daily_mindmap_parser.dart';
import 'daily_todoist_parser.dart';
import 'daily_todoist_plan.dart';
import 'todoist_client.dart';
import 'todoist_retry.dart';
import 'unmatched_done_store.dart';

/// Outcome of syncing one · daily capture to Todoist Inbox.
class DailyTodoistSyncResult {
  const DailyTodoistSyncResult({
    this.createdCount = 0,
    this.completedCount = 0,
    this.unmatchedDone = const [],
    this.labels = const [],
    this.failed = const [],
    this.todoistIdByNode = const {},
    this.warnings = const [],
  });

  final int createdCount;
  final int completedCount;
  final List<String> unmatchedDone;

  /// Todoist label names ensured for this page (one per section / name).
  final List<String> labels;

  /// Items that did not go through (kept for "retry failed").
  final List<FailedTodoistItem> failed;

  /// Mindmap node id → Todoist task id for everything created this run.
  final Map<String, String> todoistIdByNode;

  /// Non-fatal problems (e.g. a "Also linked" note that could not be added).
  final List<String> warnings;

  bool get hasUnmatched => unmatchedDone.isNotEmpty;
  bool get hasFailures => failed.isNotEmpty;

  /// First distinct failure reason, for the in-app notification.
  String? get failureReason => failed.isEmpty ? null : failed.first.error;

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
    if (labels.isNotEmpty) {
      parts.add(labels.length == 1 ? '1 label' : '${labels.length} labels');
    }
    if (hasFailures) {
      parts.add(
        failed.length == 1
            ? '1 item did not send'
            : '${failed.length} items did not send',
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

/// Plans, then sends, · daily captures via [TodoistClient].
///
/// Planning ([plan] / [planner]) never touches the network. [execute] sends a
/// reviewed [DailyTodoistPlan]; a failure on one item does not stop the rest,
/// and failures are kept (see [TodoistRetryStore]) for [retryPending].
class DailyTodoistSync {
  DailyTodoistSync({
    required TodoistClient client,
    required UnmatchedDoneStore unmatchedStore,
    TodoistRetryStore? retryStore,
    DailyTodoistParser parser = const DailyTodoistParser(),
    DailyMindmapParser mindmapParser = const DailyMindmapParser(),
    DateTime Function()? clock,
  })  : _client = client,
        _unmatched = unmatchedStore,
        _retry = retryStore,
        _clock = clock ?? DateTime.now,
        planner = DailyTodoistPlanner(
          parser: parser,
          mindmapParser: mindmapParser,
          clock: clock,
        );

  final TodoistClient _client;
  final UnmatchedDoneStore _unmatched;
  final TodoistRetryStore? _retry;
  final DateTime Function() _clock;
  final DailyTodoistPlanner planner;

  /// Prefer mindmap hub→branch→leaf; fall back to section markdown.
  DailyTodoistPlan plan({
    required String markdown,
    List<OcrRegion> regions = const [],
    List<CanvasEdge> edges = const [],
  }) {
    return planner.plan(markdown: markdown, regions: regions, edges: edges);
  }

  /// Plan and send in one step (no review) — kept for non-UI callers.
  Future<DailyTodoistSyncResult> syncDaily({
    required String markdown,
    List<OcrRegion> regions = const [],
    List<CanvasEdge> edges = const [],
  }) {
    return execute(plan(markdown: markdown, regions: regions, edges: edges));
  }

  Future<DailyTodoistSyncResult> syncMarkdown(String source) {
    return execute(planner.plan(markdown: source));
  }

  Future<DailyTodoistSyncResult> syncParsed(DailyTodoistParseResult parsed) {
    return execute(DailyTodoistPlan.fromParse(parsed));
  }

  /// Send what is still included in [plan]. Never throws for Todoist / network
  /// errors: those become [DailyTodoistSyncResult.failed] and are persisted.
  Future<DailyTodoistSyncResult> execute(DailyTodoistPlan plan) async {
    if (!plan.hasWork) return const DailyTodoistSyncResult();
    final result = await _run(
      creates: plan.effectiveCreates,
      done: plan.effectiveDone,
      sectionLabels: plan.effectiveSectionLabels,
    );
    await _persistFailures(result, createdAt: _clock());
    return result;
  }

  /// Retry only the items that failed earlier, across every stored batch.
  /// Items that go through are removed; the rest stay stored.
  Future<DailyTodoistSyncResult> retryPending() async {
    final store = _retry;
    if (store == null) return const DailyTodoistSyncResult();
    final batches = await store.read();
    if (batches.isEmpty) return const DailyTodoistSyncResult();

    var created = 0;
    var completed = 0;
    final unmatched = <String>[];
    final labels = <String>{};
    final failed = <FailedTodoistItem>[];
    final warnings = <String>[];
    final remaining = <TodoistRetryBatch>[];
    final allIds = <String, String>{};

    for (final batch in batches) {
      final r = await _run(
        creates: [
          for (final i in batch.items)
            if (i.kind == FailedItemKind.create) i.toCreate(),
        ],
        done: [
          for (final i in batch.items)
            if (i.kind == FailedItemKind.done) i.content,
        ],
        sectionLabels: const [],
        knownIds: batch.todoistIdByNode,
      );
      created += r.createdCount;
      completed += r.completedCount;
      unmatched.addAll(r.unmatchedDone);
      labels.addAll(r.labels);
      warnings.addAll(r.warnings);
      failed.addAll(r.failed);
      allIds.addAll(r.todoistIdByNode);
      if (r.failed.isNotEmpty) {
        remaining.add(
          TodoistRetryBatch(
            createdAt: batch.createdAt,
            items: r.failed,
            todoistIdByNode: {...batch.todoistIdByNode, ...r.todoistIdByNode},
          ),
        );
      }
    }
    await store.write(remaining);
    return DailyTodoistSyncResult(
      createdCount: created,
      completedCount: completed,
      unmatchedDone: unmatched,
      labels: labels.toList(),
      failed: failed,
      todoistIdByNode: allIds,
      warnings: warnings,
    );
  }

  Future<void> _persistFailures(
    DailyTodoistSyncResult result, {
    required DateTime createdAt,
  }) async {
    final store = _retry;
    if (store == null || !result.hasFailures) return;
    await store.add(
      TodoistRetryBatch(
        createdAt: createdAt,
        items: result.failed,
        todoistIdByNode: result.todoistIdByNode,
      ),
    );
  }

  Future<DailyTodoistSyncResult> _run({
    required List<DailyTodoistCreate> creates,
    required List<String> done,
    required Iterable<String> sectionLabels,
    Map<String, String> knownIds = const {},
  }) async {
    final labelNames = <String>{
      ...sectionLabels,
      for (final c in creates) c.label,
    }..removeWhere((l) => l.trim().isEmpty);

    final failed = <FailedTodoistItem>[];
    final warnings = <String>[];

    Map<String, TodoistLabel> ensured = const {};
    if (labelNames.isNotEmpty) {
      try {
        ensured = await _client.ensureLabels(labelNames);
      } catch (e) {
        final reason = describeError(e);
        return DailyTodoistSyncResult(
          failed: [
            for (final c in creates) FailedTodoistItem.forCreate(c, reason),
            for (final d in done) FailedTodoistItem.forDone(d, reason),
          ],
          todoistIdByNode: knownIds,
        );
      }
    }
    String todoistLabel(String label) {
      final name = ensured[label]?.name.trim() ?? '';
      return name.isEmpty ? label : name;
    }

    // nodeId → Todoist task id (parents before children in [creates]).
    final todoistIdByNode = <String, String>{...knownIds};
    final newIds = <String, String>{};
    var created = 0;
    String? abortReason;

    for (final item in creates) {
      if (abortReason != null) {
        failed.add(FailedTodoistItem.forCreate(item, abortReason));
        continue;
      }
      String? parentId;
      if (item.parentNodeId != null) {
        parentId = todoistIdByNode[item.parentNodeId!];
        if (parentId == null) {
          failed.add(
            FailedTodoistItem.forCreate(
              item,
              "Its parent task didn't send",
            ),
          );
          continue;
        }
      }
      try {
        final task = await _client.createInboxTask(
          content: item.content,
          labels: item.parentNodeId == null
              ? [todoistLabel(item.label)]
              : const [],
          priority: item.priority,
          parentId: parentId,
          dueDate: item.dueDate,
        );
        if (item.nodeId != null && item.nodeId!.isNotEmpty) {
          todoistIdByNode[item.nodeId!] = task.id;
          newIds[item.nodeId!] = task.id;
        }
        created++;
      } catch (e) {
        final reason = describeError(e);
        failed.add(FailedTodoistItem.forCreate(item, reason));
        if (_isFatal(e)) abortReason = reason;
      }
    }

    // Extra mindmap parents that also linked to a shared child: annotate
    // those parents with a Todoist task URL (one parent_id only in API).
    for (final item in creates) {
      if (item.nodeId == null || item.extraParentNodeIds.isEmpty) continue;
      if (!newIds.containsKey(item.nodeId!)) continue;
      final childId = newIds[item.nodeId!]!;
      final link = 'https://app.todoist.com/app/task/$childId';
      for (final parentNode in item.extraParentNodeIds) {
        final parentId = todoistIdByNode[parentNode];
        if (parentId == null) continue;
        try {
          await _client.updateTask(parentId, description: 'Also linked: $link');
        } catch (e) {
          warnings.add(
            'Could not link "${item.content}" to its extra parent: '
            '${describeError(e)}',
          );
        }
      }
    }

    var completed = 0;
    final unmatched = <String>[];
    if (done.isNotEmpty) {
      if (abortReason != null) {
        for (final d in done) {
          failed.add(FailedTodoistItem.forDone(d, abortReason));
        }
      } else {
        List<TodoistTask>? open;
        try {
          open = await _client.listOpenTasks();
        } catch (e) {
          final reason = describeError(e);
          for (final d in done) {
            failed.add(FailedTodoistItem.forDone(d, reason));
          }
        }
        if (open != null) {
          final remaining = List<TodoistTask>.from(open);
          for (final doneText in done) {
            final match = findMatchingOpenTask(remaining, doneText);
            if (match == null) {
              unmatched.add(doneText);
              continue;
            }
            try {
              await _client.closeTask(match.id);
              remaining.removeWhere((t) => t.id == match.id);
              completed++;
            } catch (e) {
              failed.add(
                FailedTodoistItem.forDone(doneText, describeError(e)),
              );
            }
          }
        }
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
      labels: {for (final l in labelNames) todoistLabel(l)}.toList(),
      failed: failed,
      todoistIdByNode: todoistIdByNode,
      warnings: warnings,
    );
  }

  /// Auth / rate-limit / offline errors mean every later item would fail too.
  static bool _isFatal(Object e) {
    if (e is TodoistApiException) {
      final code = e.statusCode;
      return code == 401 || code == 403 || code == 429;
    }
    return true;
  }

  /// Short, user-facing reason for a failed Todoist call.
  static String describeError(Object e) {
    if (e is TodoistApiException) return e.message;
    if (e is SocketException ||
        e is http.ClientException ||
        e is TimeoutException) {
      return "Couldn't reach Todoist (check your connection)";
    }
    return 'Unexpected error: $e';
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
