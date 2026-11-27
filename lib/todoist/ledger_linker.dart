import 'dart:math';

import 'daily_todoist_plan.dart';
import 'task_text.dart';
import 'todoist_client.dart';
import 'todoist_ledger.dart';

export 'task_text.dart';

/// Recognises a re-captured page: its items are matched to the Todoist tasks
/// an earlier capture created, so sending updates them instead of duplicating.
///
/// Pure — reads only the ledger entries it is given.
class LedgerLinker {
  const LedgerLinker._();

  /// Minimum [TaskText.similarity] for an item to match a task of the
  /// earlier page it was recognised as.
  static const double threshold = 0.6;

  /// Stricter bar for matching a single item to any open task (another
  /// page's ledger entry, or a live Todoist task) — near-identical only.
  static const double strictThreshold = 0.8;

  static DailyTodoistPlan link(
    DailyTodoistPlan plan,
    List<LedgerEntry> entries, {
    String? pageId,
  }) {
    final open = [for (final e in entries) if (e.isOpen) e];
    final day = plan.pageDay;
    // A completed task counts only for the same page (same page ID or the
    // same day's page): shown as already done instead of created again.
    bool samePage(LedgerEntry e) =>
        (pageId != null && e.pageId == pageId) ||
        (day != null && e.pageDay == day);
    final eligible = [
      for (final e in entries)
        if (e.isOpen || samePage(e)) e,
    ];
    final byPage = <String, List<LedgerEntry>>{};
    for (final e in eligible) {
      final page = e.pageId;
      if (page == null || page.isEmpty) continue;
      (byPage[page] ??= []).add(e);
    }
    final candidates = [
      for (var i = 0; i < plan.creates.length; i++)
        if (plan.creates[i].content.trim().isNotEmpty) i,
    ];
    final doneMatches = _linkDone(plan, entries, samePage);
    if (eligible.isEmpty || candidates.isEmpty) {
      return plan.withLinks(
        matches: const {},
        doneMatches: doneMatches,
        rememberedCount: open.length,
      );
    }

    String? chosen;
    var byId = false;
    if (pageId != null && byPage.containsKey(pageId)) {
      chosen = pageId;
      byId = true;
    } else {
      // At least half of the page's items must match one earlier page, so one
      // recurring task ("Buy milk") does not drag a new page onto an old one.
      final need = max(1, (candidates.length / 2).ceil());
      var bestCount = 0;
      DateTime? bestAt;
      for (final page in byPage.entries) {
        final count = _assign(plan, page.value, threshold, const {}).length;
        if (count < need) continue;
        final at = page.value
            .map((e) => e.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        if (count > bestCount || (count == bestCount && at.isAfter(bestAt!))) {
          chosen = page.key;
          bestCount = count;
          bestAt = at;
        }
      }
    }

    final matches = <int, LedgerMatch>{
      if (chosen != null) ..._assign(plan, byPage[chosen]!, threshold, const {}),
    };
    // Items the page link left over can still be the same open task.
    final taken = {for (final m in matches.values) m.todoistId};
    final rest = [for (final e in open) if (!taken.contains(e.todoistId)) e];
    matches.addAll(_assign(plan, rest, strictThreshold, matches.keys.toSet()));

    return plan.withLinks(
      matches: matches,
      doneMatches: doneMatches,
      linkedPageId: chosen,
      linkedByPageId: byId,
      rememberedCount: open.length,
    );
  }

  /// Ticked items → the task each closes: an open entry from this page,
  /// then any open entry, then a completed one from this page (shown as
  /// already completed). Never a completed task from another day's page.
  static Map<int, LedgerMatch> _linkDone(
    DailyTodoistPlan plan,
    List<LedgerEntry> entries,
    bool Function(LedgerEntry) samePage,
  ) {
    final out = <int, LedgerMatch>{};
    final taken = <String>{
      for (final t in plan.creates)
        if (t.match != null) t.match!.todoistId,
    };
    for (var i = 0; i < plan.done.length; i++) {
      final text = plan.done[i].content;
      if (text.trim().isEmpty) continue;
      final pools = [
        [for (final e in entries) if (e.isOpen && samePage(e)) e],
        [for (final e in entries) if (e.isOpen) e],
        [for (final e in entries) if (!e.isOpen && samePage(e)) e],
      ];
      for (final pool in pools) {
        final free = [for (final e in pool) if (!taken.contains(e.todoistId)) e];
        final j = TaskText.findDoneMatch([for (final e in free) e.content], text);
        if (j == null) continue;
        final e = free[j];
        taken.add(e.todoistId);
        out[i] = _matchOf(
          e,
          remote: e.isOpen ? RemoteState.unknown : RemoteState.completed,
        );
        break;
      }
    }
    return out;
  }

  static LedgerMatch _matchOf(
    LedgerEntry e, {
    bool fromLive = false,
    RemoteState remote = RemoteState.unknown,
  }) {
    return LedgerMatch(
      todoistId: e.todoistId,
      content: e.content,
      priority: e.priority,
      pageId: e.pageId,
      due: e.due,
      fromLive: fromLive,
      remote: remote,
    );
  }

  /// Match the items still unmatched against the open Todoist tasks, so tasks
  /// the ledger does not know (created before it existed, on another device,
  /// or by hand) are updated instead of duplicated.
  static DailyTodoistPlan linkLive(
    DailyTodoistPlan plan,
    List<TodoistTask> openTasks,
  ) {
    final taken = {
      for (final t in plan.creates)
        if (t.match != null) t.match!.todoistId,
    };
    final done = {
      for (var i = 0; i < plan.creates.length; i++)
        if (plan.creates[i].match != null) i,
    };
    final pool = [
      for (final t in openTasks)
        if (!taken.contains(t.id))
          LedgerEntry(
            todoistId: t.id,
            content: t.content,
            priority: t.priority,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
    ];
    final found = _assign(plan, pool, strictThreshold, done, fromLive: true);
    final used = {...taken, for (final m in found.values) m.todoistId};
    for (final d in plan.done) {
      if (d.match != null) used.add(d.match!.todoistId);
    }
    final doneFound = <int, LedgerMatch>{};
    for (var i = 0; i < plan.done.length; i++) {
      final d = plan.done[i];
      if (d.match != null || d.content.trim().isEmpty) continue;
      final free = [for (final t in openTasks) if (!used.contains(t.id)) t];
      final j = TaskText.findDoneMatch([for (final t in free) t.content], d.content);
      if (j == null) continue;
      final t = free[j];
      used.add(t.id);
      doneFound[i] = LedgerMatch(
        todoistId: t.id,
        content: t.content,
        priority: t.priority,
        fromLive: true,
        remote: RemoteState.open,
      );
    }
    return plan.withLinks(
      matches: found,
      doneMatches: doneFound,
      liveChecked: true,
    );
  }

  /// One-to-one best matches at or above [min], highest similarity first.
  static Map<int, LedgerMatch> _assign(
    DailyTodoistPlan plan,
    List<LedgerEntry> entries,
    double min,
    Set<int> skip, {
    bool fromLive = false,
  }) {
    final pairs = <({int index, int entry, double score})>[];
    for (var i = 0; i < plan.creates.length; i++) {
      if (skip.contains(i)) continue;
      final content = plan.creates[i].content;
      if (content.trim().isEmpty) continue;
      for (var j = 0; j < entries.length; j++) {
        final score = TaskText.similarity(content, entries[j].content);
        if (score >= min) pairs.add((index: i, entry: j, score: score));
      }
    }
    pairs.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });
    final out = <int, LedgerMatch>{};
    final taken = <int>{};
    for (final p in pairs) {
      if (out.containsKey(p.index) || taken.contains(p.entry)) continue;
      taken.add(p.entry);
      final e = entries[p.entry];
      out[p.index] = _matchOf(
        e,
        fromLive: fromLive,
        remote: fromLive
            ? RemoteState.open
            : (e.isOpen ? RemoteState.unknown : RemoteState.completed),
      );
    }
    return out;
  }
}
