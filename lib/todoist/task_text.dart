import 'dart:math';

import 'due_phrase.dart';

/// A `| HH:MM` time written after a task on paper.
class TaskTime {
  const TaskTime(this.hour, this.minute);

  final int hour;
  final int minute;

  /// That time on [day] (local).
  DateTime on(DateTime day) =>
      DateTime(day.year, day.month, day.day, hour, minute);
}

/// Normalising, comparing and splitting task text across captures.
///
/// Paper text and Todoist text drift apart: OCR rewords, a tick or strike
/// appears once the task is done, and a `| 16:50` suffix turns into a due
/// time (so Todoist holds just `bolt`). Matching uses [core] so none of that
/// breaks a link.
class TaskText {
  const TaskText._();

  static final RegExp _leadMarks = RegExp(
    r'^(?:[-*+·•]\s+|\[[ xX✓✔]\]\s*|[☐☑☒□■✓✔✅]\uFE0F?\s*)+',
  );
  static final RegExp _trailMarks = RegExp(r'(?:\s*[☑☒✓✔✅]\uFE0F?)+$');
  static final RegExp _doneLead = RegExp(
    r'^(?:[-*+·•]\s+)?(?:\[[xX✓✔]\]|[☑☒■✓✔✅])',
  );
  static final RegExp _doneTrail = RegExp(r'[☑☒✓✔✅]\uFE0F?\s*$');
  /// Strike-through as OCR / Gemini writes it: `~~text~~`, `~text~`,
  /// `<s>`/`<del>`/`<strike>` tags, or combining strike characters.
  static final RegExp _strikeTags =
      RegExp(r'</?(?:s|del|strike)>', caseSensitive: false);
  static final RegExp _strikeChars = RegExp('[\u0335\u0336]');
  static final RegExp _tildeStrike = RegExp(r'^~{1,2}(?=\S)(.+?)~{1,2}');

  static ({String text, bool struck}) _unstrike(String raw) {
    var t = raw.trim().replaceFirst(_leadMarks, '').trim();
    var struck = false;
    if (_strikeChars.hasMatch(t)) {
      struck = true;
      t = t.replaceAll(_strikeChars, '');
    }
    if (_strikeTags.hasMatch(t) && RegExp(r'^<(?:s|del|strike)>', caseSensitive: false).hasMatch(t)) {
      struck = true;
    }
    t = t.replaceAll(_strikeTags, '');
    final tilde = _tildeStrike.firstMatch(t);
    if (tilde != null) {
      struck = true;
      t = '${tilde.group(1)!}${t.substring(tilde.end)}';
    }
    // A word struck out mid-line is a correction, not a done mark.
    if (!struck) t = t.replaceAll(RegExp(r'\s*~~[^~]+~~'), '');
    t = t.replaceAll('~~', '');
    t = t.replaceFirst(_leadMarks, '');
    t = t.replaceFirst(_trailMarks, '');
    return (text: t.replaceAll(RegExp(r'\s+'), ' ').trim(), struck: struck);
  }

  static String normalize(String raw) => _unstrike(raw).text.toLowerCase();

  /// True when the line carries a done mark: `[x]`, a tick / ticked box
  /// before or after the text, or a strike-through (either is enough).
  static bool isTicked(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    return _doneLead.hasMatch(t) || _doneTrail.hasMatch(t) || _unstrike(t).struck;
  }

  /// The task text with done marks removed, original casing kept.
  static String withoutMarks(String raw) => _unstrike(raw).text;

  static const _sep = r'(?:\s*[|@–—-]\s*|\s+)';
  static const _months =
      r'(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?';
  static final List<RegExp> _suffixes = [
    RegExp('$_sep(?:at\\s+)?\\d{1,2}[:.h]\\d{2}\\s*(?:am|pm)?\$'),
    RegExp('$_sep(?:at\\s+)?\\d{1,2}\\s*(?:am|pm)\$'),
    RegExp('$_sep\\d{1,2}[/.-]\\d{1,2}(?:[/.-]\\d{2,4})?\$'),
    RegExp("$_sep\\d{1,2}(?:st|nd|rd|th)?\\s+$_months(?:\\s+'?\\d{2,4})?\$"),
    RegExp('$_sep$_months\\s+\\d{1,2}(?:st|nd|rd|th)?\$'),
    RegExp(r'\s*[|@]\s*(?:today|tomorrow|tonight|tmrw)$'),
  ];

  /// [normalize]d text without a trailing time / date (`bolt | 16:50`,
  /// `call mum 4pm`, `post office 28/11` → `bolt`, `call mum`,
  /// `post office`). Falls back to [normalize] when nothing would be left.
  static String core(String raw) {
    final full = normalize(raw);
    final dated = DuePhrase.extract(withoutMarks(raw), pageDate: _anyDay);
    var t = dated == null ? full : normalize(dated.content);
    if (t.isEmpty) t = full;
    var changed = true;
    while (changed) {
      changed = false;
      for (final re in _suffixes) {
        final next = t.replaceFirst(re, '').trim();
        if (next != t && next.isNotEmpty) {
          t = next;
          changed = true;
        }
      }
    }
    return t.isEmpty ? full : t;
  }

  static final DateTime _anyDay = DateTime(2000);

  static final RegExp _pipeTime = RegExp(
    r'\s*\|\s*(\d{1,2})[:.h](\d{2})\s*(am|pm)?\s*$',
    caseSensitive: false,
  );

  /// Split a trailing `| HH:MM` (also `| 4:50pm`) off a task line.
  /// Returns null when there is none or the time is not valid.
  static ({String content, TaskTime time})? splitPipeTime(String raw) {
    final m = _pipeTime.firstMatch(raw);
    if (m == null) return null;
    var hour = int.parse(m.group(1)!);
    final minute = int.parse(m.group(2)!);
    final ampm = m.group(3)?.toLowerCase();
    if (ampm != null) {
      if (hour < 1 || hour > 12) return null;
      hour = hour % 12 + (ampm == 'pm' ? 12 : 0);
    }
    if (hour > 23 || minute > 59) return null;
    final content = raw.substring(0, m.start).trim();
    if (content.isEmpty) return null;
    return (content: content, time: TaskTime(hour, minute));
  }

  /// Index of the candidate a done line refers to: the same [core] text,
  /// else one containing the other on word boundaries (`bolt` in
  /// `fix bolt`, not in `bolts`). Null when none does.
  static int? findDoneMatch(List<String> candidates, String doneText) {
    final needle = core(doneText);
    if (needle.isEmpty) return null;
    int? contains;
    for (var i = 0; i < candidates.length; i++) {
      final hay = core(candidates[i]);
      if (hay.isEmpty) continue;
      if (hay == needle) return i;
      if (contains == null &&
          (_containsWords(hay, needle) || _containsWords(needle, hay))) {
        contains = i;
      }
    }
    return contains;
  }

  static bool _containsWords(String whole, String part) {
    if (part.length > whole.length) return false;
    final re = RegExp(
      '(?:^|[^\\p{L}\\p{N}])${RegExp.escape(part)}(?:\$|[^\\p{L}\\p{N}])',
      unicode: true,
    );
    return re.hasMatch(whole);
  }

  /// 0..1 — 1 for the same task; word overlap (Jaccard) or, for OCR typos,
  /// a close edit distance. Compared on [core], so a time / date suffix or a
  /// done mark does not matter. Two different short tasks ("Call mum" /
  /// "Call dad") stay well below a 0.6 threshold.
  static double similarity(String a, String b) {
    final x = core(a);
    final y = core(b);
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
