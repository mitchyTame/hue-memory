import 'dart:math';

import 'daily_todoist_plan.dart';
import 'todoist_ledger.dart';

/// Normalising and comparing task text across captures.
class TaskText {
  const TaskText._();

  static String normalize(String raw) {
    var t = raw.trim().toLowerCase();
    t = t.replaceFirst(RegExp(r'^[-*+·•]\s+'), '');
    t = t.replaceFirst(RegExp(r'^\[([ xX])\]\s*'), '');
    t = t.replaceFirst(RegExp(r'^(☐|☑|☒|□|■)\s*'), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  /// 0..1 — 1 for the same text; word overlap (Jaccard) or, for OCR typos,
  /// a close edit distance. Two different short tasks ("Call mum" /
  /// "Call dad") stay well below [LedgerLinker.threshold].
  static double similarity(String a, String b) {
    final x = normalize(a);
    final y = normalize(b);
    if (x.isEmpty || y.isEmpty) return 0;
    if (x == y) return 1;
    final tx = _tokens(x);
    final ty = _tokens(y);
    final union = {...tx, ...ty}.length;
    final jaccard = union == 0 ? 0.0 : tx.intersection(ty).length / union;
    final longest = max(x.length, y.length);
    final typo = 1 - _editDistance(x, y) / longest;
    return max(jaccard, typo >= 0.85 ? typo : 0.0);
  }

  static Set<String> _tokens(String s) => {
        for (final t in s.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)))
          if (t.isNotEmpty) t,
      };

  static int _editDistance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = min(min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      }
      prev = cur;
    }
    return prev[b.length];
  }
}

/// Recognises a re-captured page: its items are matched to the Todoist tasks
/// an earlier capture created, so sending updates them instead of duplicating.
///
/// Pure — reads only the ledger entries it is given.
class LedgerLinker {
  const LedgerLinker._();

  /// Minimum [TaskText.similarity] for an item to match an earlier task.
  static const double threshold = 0.6;

  static DailyTodoistPlan link(
    DailyTodoistPlan plan,
    List<LedgerEntry> entries, {
    String? pageId,
  }) {
    final byPage = <String, List<LedgerEntry>>{};
    for (final e in entries) {
      final page = e.pageId;
      if (!e.isOpen || page == null || page.isEmpty) continue;
      (byPage[page] ??= []).add(e);
    }
    final candidates = [
      for (var i = 0; i < plan.creates.length; i++)
        if (plan.creates[i].content.trim().isNotEmpty) i,
    ];
    if (byPage.isEmpty || candidates.isEmpty) return plan;

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
        final count = _assign(plan, page.value).length;
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
    if (chosen == null) return plan;

    return plan.withLinks(
      matches: _assign(plan, byPage[chosen]!),
      linkedPageId: chosen,
      linkedByPageId: byId,
    );
  }

  /// One-to-one best matches, highest similarity first.
  static Map<int, LedgerMatch> _assign(
    DailyTodoistPlan plan,
    List<LedgerEntry> entries,
  ) {
    final pairs = <({int index, int entry, double score})>[];
    for (var i = 0; i < plan.creates.length; i++) {
      final content = plan.creates[i].content;
      if (content.trim().isEmpty) continue;
      for (var j = 0; j < entries.length; j++) {
        final score = TaskText.similarity(content, entries[j].content);
        if (score >= threshold) pairs.add((index: i, entry: j, score: score));
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
      out[p.index] = LedgerMatch(
        todoistId: e.todoistId,
        content: e.content,
        priority: e.priority,
        pageId: e.pageId,
      );
    }
    return out;
  }
}
