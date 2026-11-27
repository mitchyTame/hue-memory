import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../ocr/ocr_client.dart';
import '../writers/canvas_writer.dart';
import 'daily_mindmap_parser.dart';
import 'daily_todoist_parser.dart';
import 'daily_todoist_plan.dart';
import 'ledger_linker.dart';
import 'todoist_client.dart';
import 'todoist_ledger.dart';
import 'todoist_retry.dart';
import 'unmatched_done_store.dart';

/// Outcome of syncing one · daily capture to Todoist Inbox.
class DailyTodoistSyncResult {
  const DailyTodoistSyncResult({
    this.createdCount = 0,
    this.updatedCount = 0,
    this.unchangedCount = 0,
    this.completedCount = 0,
    this.unmatchedDone = const [],
    this.labels = const [],
    this.failed = const [],
    this.todoistIdByNode = const {},
    this.warnings = const [],
  });

  final int createdCount;

  /// Existing tasks (from an earlier capture of this page) that were patched.
  final int updatedCount;

  /// Matched tasks that already said the same thing — nothing was sent.
  final int unchangedCount;
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

  /// Updates whose task was deleted or completed in Todoist — offered as
  /// "recreate" rather than retried.
  bool get hasMissing => failed.any((f) => f.remoteMissing);

  /// Failures a plain "retry" can fix (everything except [hasMissing]).
  bool get hasRetryable => failed.any((f) => !f.remoteMissing);

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
    if (updatedCount > 0) {
      parts.add(updatedCount == 1 ? '1 updated' : '$updatedCount updated');
    }
    if (unchangedCount > 0) {
      parts.add(
        unchangedCount == 1 ? '1 unchanged' : '$unchangedCount unchanged',
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
    TodoistLedgerStore? ledgerStore,
    DailyTodoistParser parser = const DailyTodoistParser(),
    DailyMindmapParser mindmapParser = const DailyMindmapParser(),
    DateTime Function()? clock,
  })  : _client = client,
        _unmatched = unmatchedStore,
        _retry = retryStore,
        _ledger = ledgerStore,
        _clock = clock ?? DateTime.now,
        planner = DailyTodoistPlanner(
          parser: parser,
          mindmapParser: mindmapParser,
          clock: clock,
        );

  final TodoistClient _client;
  final UnmatchedDoneStore _unmatched;
  final TodoistRetryStore? _retry;
  final TodoistLedgerStore? _ledger;
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

  /// Match [plan]'s items against tasks an earlier capture created, so a
  /// re-captured page updates them (see [LedgerLinker]). No network.
  Future<DailyTodoistPlan> linkPlan(
    DailyTodoistPlan plan, {
    String? pageId,
  }) async {
    final ledger = _ledger;
    if (ledger == null) return plan;
    return LedgerLinker.link(plan, await ledger.read(), pageId: pageId);
  }

  /// Send what is still included in [plan]. Never throws for Todoist / network
  /// errors: those become [DailyTodoistSyncResult.failed] and are persisted.
  ///
  /// [pageId] ties the created tasks to this capture in the ledger.
  Future<DailyTodoistSyncResult> execute(
    DailyTodoistPlan plan, {
    String? pageId,
  }) async {
    if (!plan.hasWork) return const DailyTodoistSyncResult();
    final result = await _run(
      creates: plan.effectiveCreates,
      done: plan.effectiveDone,
      sectionLabels: plan.effectiveSectionLabels,
      pageId: pageId,
    );
    await _persistFailures(result, createdAt: _clock(), pageId: pageId);
    return result;
  }

  /// Retry only the items that failed earlier, across every stored batch.
  /// Items that go through are removed; the rest stay stored. Updates whose
  /// task is gone stay put until [recreateMissing].
  Future<DailyTodoistSyncResult> retryPending() {
    return _replay(recreate: false);
  }

  /// Create brand-new tasks for updates whose earlier task was deleted or
  /// completed in Todoist.
  Future<DailyTodoistSyncResult> recreateMissing() {
    return _replay(recreate: true);
  }

  Future<DailyTodoistSyncResult> _replay({required bool recreate}) async {
    final store = _retry;
    if (store == null) return const DailyTodoistSyncResult();
    final batches = await store.read();
    if (batches.isEmpty) return const DailyTodoistSyncResult();

    var created = 0;
    var updated = 0;
    var unchanged = 0;
    var completed = 0;
    final unmatched = <String>[];
    final labels = <String>{};
    final failed = <FailedTodoistItem>[];
    final warnings = <String>[];
    final remaining = <TodoistRetryBatch>[];
    final allIds = <String, String>{};

    for (final batch in batches) {
      bool selected(FailedTodoistItem i) =>
          recreate ? i.remoteMissing : !i.remoteMissing;
      final todo = [for (final i in batch.items) if (selected(i)) i];
      final untouched = [for (final i in batch.items) if (!selected(i)) i];

      final r = await _run(
        creates: [
          for (final i in todo)
            if (i.kind != FailedItemKind.done)
              i.toCreate(recreate: recreate),
        ],
        done: [
          for (final i in todo)
            if (i.kind == FailedItemKind.done) i.content,
        ],
        sectionLabels: const [],
        knownIds: batch.todoistIdByNode,
        pageId: batch.pageId,
      );
      created += r.createdCount;
      updated += r.updatedCount;
      unchanged += r.unchangedCount;
      completed += r.completedCount;
      unmatched.addAll(r.unmatchedDone);
      labels.addAll(r.labels);
      warnings.addAll(r.warnings);
      failed.addAll(r.failed);
      allIds.addAll(r.todoistIdByNode);
      final left = [...r.failed, ...untouched];
      if (left.isNotEmpty) {
        remaining.add(
          TodoistRetryBatch(
            createdAt: batch.createdAt,
            items: left,
            todoistIdByNode: {...batch.todoistIdByNode, ...r.todoistIdByNode},
            pageId: batch.pageId,
          ),
        );
      }
    }
    await store.write(remaining);
    return DailyTodoistSyncResult(
      createdCount: created,
      updatedCount: updated,
      unchangedCount: unchanged,
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
    String? pageId,
  }) async {
    final store = _retry;
    if (store == null || !result.hasFailures) return;
    await store.add(
      TodoistRetryBatch(
        createdAt: createdAt,
        items: result.failed,
        todoistIdByNode: result.todoistIdByNode,
        pageId: pageId,
      ),
    );
  }

  Future<DailyTodoistSyncResult> _run({
    required List<DailyTodoistCreate> creates,
    required List<String> done,
    required Iterable<String> sectionLabels,
    Map<String, String> knownIds = const {},
    String? pageId,
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
            for (final c in creates)
              c.isUpdate
                  ? FailedTodoistItem.forUpdate(c, reason)
                  : FailedTodoistItem.forCreate(c, reason),
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
    var updated = 0;
    var unchanged = 0;
    String? abortReason;

    for (final planned in creates) {
      final isUpdate = planned.isUpdate;
      FailedTodoistItem failure(String reason, {bool missing = false}) =>
          isUpdate
              ? FailedTodoistItem.forUpdate(
                  planned,
                  reason,
                  remoteMissing: missing,
                )
              : FailedTodoistItem.forCreate(planned, reason);

      if (abortReason != null) {
        failed.add(failure(abortReason));
        continue;
      }

      if (isUpdate) {
        final id = planned.updateTodoistId!;
        final same = planned.content == planned.previousContent &&
            planned.priority == planned.previousPriority;
        if (same) {
          unchanged++;
          if (planned.nodeId != null) todoistIdByNode[planned.nodeId!] = id;
          await _ledgerSeen(id, planned, pageId, warnings);
          continue;
        }
        try {
          await _client.updateTask(
            id,
            content: planned.content == planned.previousContent
                ? null
                : planned.content,
            // Todoist has no "unset": plain priority is 1.
            priority: planned.priority == planned.previousPriority
                ? null
                : (planned.priority ?? 1),
          );
          updated++;
          if (planned.nodeId != null) todoistIdByNode[planned.nodeId!] = id;
          await _ledgerSeen(id, planned, pageId, warnings);
        } catch (e) {
          if (e is TodoistApiException && e.isNotFound) {
            await _ledgerRemove(id, warnings);
            failed.add(
              failure(
                'Task was deleted or completed in Todoist',
                missing: true,
              ),
            );
            continue;
          }
          final reason = describeError(e);
          failed.add(failure(reason));
          if (_isFatal(e)) abortReason = reason;
        }
        continue;
      }

      String? parentId;
      if (planned.parentNodeId != null) {
        parentId = todoistIdByNode[planned.parentNodeId!];
        if (parentId == null) {
          failed.add(failure("Its parent task didn't send"));
          continue;
        }
      }
      // Fixed before the first attempt and kept on failure, so a retry of a
      // request that actually went through returns the same task.
      final item = planned.requestId == null
          ? planned.copyWith(requestId: TodoistClient.newRequestId())
          : planned;
      try {
        final task = await _client.createInboxTask(
          content: item.content,
          labels: item.parentNodeId == null
              ? [todoistLabel(item.label)]
              : const [],
          priority: item.priority,
          parentId: parentId,
          dueDate: item.dueDate,
          requestId: item.requestId,
        );
        if (item.nodeId != null && item.nodeId!.isNotEmpty) {
          todoistIdByNode[item.nodeId!] = task.id;
          newIds[item.nodeId!] = task.id;
        }
        created++;
        await _ledgerAdd(task.id, item, pageId, warnings);
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
        final outcome = await _resolveDone(done, pageId, warnings);
        completed = outcome.completed;
        unmatched.addAll(outcome.unmatched);
        failed.addAll(outcome.failed);
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
      updatedCount: updated,
      unchangedCount: unchanged,
      completedCount: completed,
      unmatchedDone: unmatched,
      labels: {for (final l in labelNames) todoistLabel(l)}.toList(),
      failed: failed,
      todoistIdByNode: todoistIdByNode,
      warnings: warnings,
    );
  }

  /// Close each done line: the ledger first (tasks this app created, so the
  /// right one even when the wording drifted), then the live fuzzy match
  /// against every open task.
  Future<({int completed, List<String> unmatched, List<FailedTodoistItem> failed})>
      _resolveDone(
    List<String> done,
    String? pageId,
    List<String> warnings,
  ) async {
    var completed = 0;
    final unmatched = <String>[];
    final failed = <FailedTodoistItem>[];

    final ledgerOpen = <LedgerEntry>[
      if (_ledger != null)
        for (final e in await _readLedger(warnings))
          if (e.isOpen) e,
    ];
    List<TodoistTask>? live;
    String? liveError;
    String? abortReason;

    for (final text in done) {
      if (abortReason != null) {
        failed.add(FailedTodoistItem.forDone(text, abortReason));
        continue;
      }

      var handled = false;
      while (!handled) {
        final entry = _ledgerMatch(ledgerOpen, text, pageId);
        if (entry == null) break;
        ledgerOpen.remove(entry);
        try {
          await _client.closeTask(entry.todoistId);
          live?.removeWhere((t) => t.id == entry.todoistId);
          await _ledgerComplete(entry.todoistId, warnings);
          completed++;
          handled = true;
        } catch (e) {
          if (e is TodoistApiException && e.isNotFound) {
            // Gone remotely: forget it and try the next candidate / live list.
            await _ledgerRemove(entry.todoistId, warnings);
            continue;
          }
          final reason = describeError(e);
          failed.add(FailedTodoistItem.forDone(text, reason));
          if (_isFatal(e)) abortReason = reason;
          handled = true;
        }
      }
      if (handled) continue;

      if (live == null && liveError == null) {
        try {
          live = List<TodoistTask>.from(await _client.listOpenTasks());
        } catch (e) {
          liveError = describeError(e);
        }
      }
      if (liveError != null) {
        failed.add(FailedTodoistItem.forDone(text, liveError));
        continue;
      }
      final match = findMatchingOpenTask(live!, text);
      if (match == null) {
        unmatched.add(text);
        continue;
      }
      try {
        await _client.closeTask(match.id);
        live.removeWhere((t) => t.id == match.id);
        await _ledgerComplete(match.id, warnings);
        completed++;
      } catch (e) {
        final reason = describeError(e);
        failed.add(FailedTodoistItem.forDone(text, reason));
        if (_isFatal(e)) abortReason = reason;
      }
    }
    return (completed: completed, unmatched: unmatched, failed: failed);
  }

  /// Prefer an entry from the same page, then any open ledger entry.
  static LedgerEntry? _ledgerMatch(
    List<LedgerEntry> open,
    String text,
    String? pageId,
  ) {
    LedgerEntry? pick(List<LedgerEntry> pool) {
      final task = findMatchingOpenTask([
        for (final e in pool) TodoistTask(id: e.todoistId, content: e.content),
      ], text);
      if (task == null) return null;
      return pool.firstWhere((e) => e.todoistId == task.id);
    }

    if (pageId != null) {
      final same = pick([
        for (final e in open)
          if (e.pageId == pageId) e,
      ]);
      if (same != null) return same;
    }
    return pick(open);
  }

  Future<List<LedgerEntry>> _readLedger(List<String> warnings) async {
    try {
      return await _ledger!.read();
    } catch (e) {
      warnings.add('Could not read the task ledger: $e');
      return const [];
    }
  }

  /// Persisted right after each create — a crash later in the batch must not
  /// lose the IDs of tasks that already exist.
  Future<void> _ledgerAdd(
    String todoistId,
    DailyTodoistCreate item,
    String? pageId,
    List<String> warnings,
  ) async {
    final ledger = _ledger;
    if (ledger == null) return;
    try {
      await ledger.upsert(
        LedgerEntry(
          todoistId: todoistId,
          content: item.content,
          label: item.label,
          priority: item.priority,
          pageId: pageId,
          nodeId: item.nodeId,
          createdAt: _clock(),
        ),
      );
    } catch (e) {
      warnings.add('Could not record "${item.content}" in the task ledger: $e');
    }
  }

  /// A matched task was updated (or already matched): keep the ledger on the
  /// latest wording / priority / page.
  Future<void> _ledgerSeen(
    String todoistId,
    DailyTodoistCreate item,
    String? pageId,
    List<String> warnings,
  ) async {
    final ledger = _ledger;
    if (ledger == null) return;
    try {
      final existing = [
        for (final e in await ledger.read())
          if (e.todoistId == todoistId) e,
      ];
      final base = existing.isEmpty
          ? LedgerEntry(
              todoistId: todoistId,
              content: item.content,
              label: item.label,
              nodeId: item.nodeId,
              createdAt: _clock(),
            )
          : existing.first;
      await ledger.upsert(
        base.copyWith(
          content: item.content,
          priority: item.priority,
          clearPriority: item.priority == null,
          pageId: pageId,
        ),
      );
    } catch (e) {
      warnings.add('Could not update the task ledger: $e');
    }
  }

  Future<void> _ledgerComplete(String todoistId, List<String> warnings) async {
    final ledger = _ledger;
    if (ledger == null) return;
    try {
      await ledger.markCompleted(todoistId, _clock());
    } catch (e) {
      warnings.add('Could not update the task ledger: $e');
    }
  }

  Future<void> _ledgerRemove(String todoistId, List<String> warnings) async {
    final ledger = _ledger;
    if (ledger == null) return;
    try {
      await ledger.remove(todoistId);
    } catch (e) {
      warnings.add('Could not update the task ledger: $e');
    }
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

  static String normalizeTaskText(String raw) => TaskText.normalize(raw);
}
