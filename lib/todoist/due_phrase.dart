/// A due date read from a task line on paper.
///
/// Either resolved here to an absolute value ([date], with or without a
/// time), or — for recurrence and anything this parser cannot pin down —
/// handed to Todoist as [dueString] so its own English parser reads it.
class TaskDue {
  const TaskDue._({
    required this.phrase,
    this.date,
    this.hasTime = false,
    this.dueString,
  });

  factory TaskDue.at(String phrase, DateTime date, {required bool hasTime}) {
    return TaskDue._(phrase: phrase, date: date, hasTime: hasTime);
  }

  factory TaskDue.todoist(String phrase) {
    final s = DuePhrase.cleanPhrase(phrase);
    return TaskDue._(phrase: s, dueString: s);
  }

  /// The date words as written (without `@` / `|`), for display and editing.
  final String phrase;
  final DateTime? date;
  final bool hasTime;

  /// Sent as Todoist `due_string` (`due_lang: en`) when not resolved here.
  final String? dueString;

  bool get isResolved => date != null;
}

/// Finds and resolves English date phrases on task lines:
/// `Sunday @ 07:30`, `call mum tomorrow @ 4pm`, `bolt | 16:50`, `submit Fri`,
/// `Dec 3`, `27 Nov`, `next Monday`, `pay rent every 1st`.
///
/// Relative words resolve against the page date. `@` and `|` are only
/// separators on paper — never part of what is sent.
class DuePhrase {
  const DuePhrase._();

  static const _weekdays = {
    'monday': 1, 'mon': 1,
    'tuesday': 2, 'tue': 2, 'tues': 2,
    'wednesday': 3, 'wed': 3,
    'thursday': 4, 'thu': 4, 'thur': 4, 'thurs': 4,
    'friday': 5, 'fri': 5,
    'saturday': 6, 'sat': 6,
    'sunday': 7, 'sun': 7,
  };

  /// Weekday abbreviations that are also ordinary words: only dates when
  /// capitalised or after `@` / `on` / `next` / `this` / `every` / `by`.
  static const _ambiguousWeekdays = {'sun', 'sat', 'wed'};

  static const _months = {
    'january': 1, 'jan': 1,
    'february': 2, 'feb': 2,
    'march': 3, 'mar': 3,
    'april': 4, 'apr': 4,
    'may': 5,
    'june': 6, 'jun': 6,
    'july': 7, 'jul': 7,
    'august': 8, 'aug': 8,
    'september': 9, 'sep': 9, 'sept': 9,
    'october': 10, 'oct': 10,
    'november': 11, 'nov': 11,
    'december': 12, 'dec': 12,
  };

  static const _connectors = {'at', 'on', 'by', 'due'};

  static const _recurringStarts = {
    'every', 'daily', 'weekly', 'monthly', 'yearly', 'annually',
    'weekdays', 'everyday',
  };

  static const _recurringWords = {
    'every', 'other', 'day', 'days', 'week', 'weeks', 'month', 'months',
    'year', 'years', 'weekday', 'weekdays', 'weekend', 'weekends',
    'workday', 'workdays', 'morning', 'afternoon', 'evening', 'night',
    'and', 'at', 'on', 'the', 'last', 'first', 'daily', 'weekly',
    'monthly', 'yearly', 'annually', 'everyday', 'starting', 'from',
    'until', 'for', 'noon', 'midnight',
  };

  /// `@` / `|` removed, whitespace tidied (what is shown and sent).
  static String cleanPhrase(String raw) {
    return raw
        .replaceAll(RegExp(r'\s*[@|]\s*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Split a task line into its text and a due. Null when there is no date
  /// phrase. A line that is only a date keeps it as its text too.
  static ({String content, TaskDue due})? extract(
    String text, {
    required DateTime pageDate,
  }) {
    var body = text.trim();
    if (body.isEmpty) return null;

    // Text after the last `@` / `|` separator is where dates are written.
    String? tail;
    final sep = RegExp(r'(?:^|\s)[@|]\s*|\s*[@|](?=\s|\d)').allMatches(body);
    if (sep.isNotEmpty) {
      final m = sep.last;
      final after = body.substring(m.end).trim();
      if (after.isNotEmpty && _parseTokens(_tokens(after), pageDate, afterMarker: true) != null) {
        tail = after;
        body = body.substring(0, m.start).trim();
      }
    }

    // Longest trailing run of words that reads as a date.
    final words = _tokens(body);
    var lead = <_Tok>[];
    for (var n = words.length; n >= 1; n--) {
      final suffix = words.sublist(words.length - n);
      final prev = words.length - n - 1 >= 0 ? words[words.length - n - 1] : null;
      final marked =
          tail != null || (prev != null && _connectors.contains(prev.lower));
      if (_parseTokens(suffix, pageDate, afterMarker: marked) != null) {
        lead = suffix;
        break;
      }
    }

    final phraseTokens = [...lead, if (tail != null) ..._tokens(tail)];
    if (phraseTokens.isEmpty) return null;
    final due = _parseTokens(phraseTokens, pageDate, afterMarker: true);
    if (due == null) return null;

    var content = words.sublist(0, words.length - lead.length).map((t) => t.raw).join(' ');
    // A connector left dangling: "submit by Fri" → "submit".
    content = content.replaceFirst(RegExp(r'\s+(?:at|on|by|due)$', caseSensitive: false), '');
    content = content.replaceAll(RegExp(r'\s*[@|]\s*$'), '').trim();
    if (content.isEmpty) content = due.phrase;
    return (content: content, due: due);
  }

  /// Read a phrase typed in the review checklist. Unknown phrases still go
  /// to Todoist as written (shown as "Todoist will read: …").
  static TaskDue? parsePhrase(String phrase, {required DateTime pageDate}) {
    final clean = cleanPhrase(phrase);
    if (clean.isEmpty) return null;
    return _parseTokens(_tokens(clean), pageDate, afterMarker: true) ??
        TaskDue.todoist(clean);
  }

  static List<_Tok> _tokens(String s) => [
        for (final w in s.split(RegExp(r'\s+')))
          if (w.replaceAll(RegExp(r'[,;.]+$'), '').isNotEmpty)
            _Tok(w.replaceAll(RegExp(r'[,;]+$'), '').replaceAll(RegExp(r'(?<=[a-zA-Z])\.$'), '')),
      ];

  static TaskDue? _parseTokens(
    List<_Tok> tokens,
    DateTime pageDate, {
    required bool afterMarker,
  }) {
    final toks = [
      for (final t in tokens)
        if (t.lower != '@' && t.lower != '|') t,
    ];
    if (toks.isEmpty) return null;
    final phrase = toks.map((t) => t.raw).join(' ');
    final words = toks.map((t) => t.lower).toList();

    if (_recurringStarts.contains(words.first)) {
      if (!_isRecurring(words)) return null;
      final out = <String>[];
      for (var k = 0; k < toks.length; k++) {
        final isTime = _time(words, k) != null;
        if (isTime && (k == 0 || words[k - 1] != 'at')) out.add('at');
        out.add(toks[k].raw);
      }
      return TaskDue.todoist(out.join(' '));
    }

    final day = DateTime(pageDate.year, pageDate.month, pageDate.day);
    DateTime? date;
    ({int h, int m})? time;
    var i = 0;
    var sawMarker = afterMarker;
    while (i < words.length) {
      final w = words[i];
      if (_connectors.contains(w)) {
        sawMarker = true;
        i++;
        continue;
      }
      // Time of day.
      final t = _time(words, i);
      if (t != null) {
        if (time != null) return null;
        time = t.value;
        i += t.used;
        continue;
      }
      if (date != null) return null;
      final d = _date(toks, words, i, day, sawMarker);
      if (d == null) return null;
      date = d.value;
      i += d.used;
    }
    if (date == null && time == null) return null;
    final base = date ?? day;
    if (time == null) return TaskDue.at(phrase, base, hasTime: false);
    return TaskDue.at(
      phrase,
      DateTime(base.year, base.month, base.day, time.h, time.m),
      hasTime: true,
    );
  }

  static bool _isRecurring(List<String> words) {
    for (final w in words) {
      if (_recurringWords.contains(w) ||
          _weekdays.containsKey(w) ||
          _months.containsKey(w) ||
          RegExp(r'^\d{1,2}(st|nd|rd|th)?$').hasMatch(w) ||
          RegExp(r'^\d{1,2}([:.h]\d{2})?(am|pm)?$').hasMatch(w) ||
          w == 'am' ||
          w == 'pm') {
        continue;
      }
      return false;
    }
    return true;
  }

  static ({({int h, int m}) value, int used})? _time(List<String> w, int i) {
    final s = w[i];
    if (s == 'noon' || s == 'midday') return (value: (h: 12, m: 0), used: 1);
    if (s == 'midnight') return (value: (h: 0, m: 0), used: 1);
    var m = RegExp(r'^(\d{1,2})(?:[:.h](\d{2}))?(am|pm)?$').firstMatch(s);
    if (m == null) return null;
    var used = 1;
    var ampm = m.group(3);
    if (ampm == null && i + 1 < w.length && (w[i + 1] == 'am' || w[i + 1] == 'pm')) {
      ampm = w[i + 1];
      used = 2;
    }
    final hasMinutes = m.group(2) != null;
    if (!hasMinutes && ampm == null) return null;
    var h = int.parse(m.group(1)!);
    final min = hasMinutes ? int.parse(m.group(2)!) : 0;
    if (ampm != null) {
      if (h < 1 || h > 12) return null;
      h = h % 12 + (ampm == 'pm' ? 12 : 0);
    }
    if (h > 23 || min > 59) return null;
    return (value: (h: h, m: min), used: used);
  }

  static ({DateTime value, int used})? _date(
    List<_Tok> toks,
    List<String> w,
    int i,
    DateTime day,
    bool marked,
  ) {
    final s = w[i];
    switch (s) {
      case 'today':
      case 'tod':
      case 'tonight':
        return (value: day, used: 1);
      case 'tomorrow':
      case 'tmrw':
      case 'tmr':
        return (value: day.add(const Duration(days: 1)), used: 1);
    }
    if (s == 'next' || s == 'this') {
      if (i + 1 >= w.length) return null;
      final n = w[i + 1];
      if (s == 'next' && n == 'week') {
        return (value: _weekStart(day).add(const Duration(days: 7)), used: 2);
      }
      final wd = _weekdays[n];
      if (wd == null) return null;
      if (s == 'this') return (value: _onOrAfter(day, wd), used: 2);
      // Todoist's reading: that weekday in next calendar week (Mon–Sun).
      final nextWeek = _weekStart(day).add(const Duration(days: 7));
      return (value: nextWeek.add(Duration(days: wd - 1)), used: 2);
    }
    if (s == 'in' && i + 2 < w.length) {
      final n = int.tryParse(w[i + 1]);
      final unit = w[i + 2];
      if (n != null) {
        if (unit.startsWith('day')) {
          return (value: day.add(Duration(days: n)), used: 3);
        }
        if (unit.startsWith('week')) {
          return (value: day.add(Duration(days: 7 * n)), used: 3);
        }
      }
      return null;
    }
    final wd = _weekdays[s];
    if (wd != null) {
      if (_ambiguousWeekdays.contains(s) && !marked && !toks[i].capitalised) {
        return null;
      }
      return (value: _onOrAfter(day, wd), used: 1);
    }

    // 27/11, 27/11/26, 2026-11-27
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
    if (iso != null) {
      final d = _valid(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
      return d == null ? null : (value: d, used: 1);
    }
    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?$').firstMatch(s);
    if (slash != null) {
      final dd = int.parse(slash.group(1)!);
      final mm = int.parse(slash.group(2)!);
      final yy = slash.group(3);
      final d = yy == null
          ? _upcoming(day, mm, dd)
          : _valid(_year(yy), mm, dd);
      return d == null ? null : (value: d, used: 1);
    }

    // 27 Nov [2026], 3rd Dec
    final dayNum = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?$').firstMatch(s);
    if (dayNum != null && i + 1 < w.length) {
      final mm = _months[w[i + 1]];
      if (mm != null) {
        final dd = int.parse(dayNum.group(1)!);
        if (i + 2 < w.length && RegExp(r"^'?\d{2,4}$").hasMatch(w[i + 2])) {
          final d = _valid(_year(w[i + 2]), mm, dd);
          return d == null ? null : (value: d, used: 3);
        }
        final d = _upcoming(day, mm, dd);
        return d == null ? null : (value: d, used: 2);
      }
    }
    // Dec 3 [2026]
    final mm = _months[s];
    if (mm != null && i + 1 < w.length) {
      final dn = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?$').firstMatch(w[i + 1]);
      if (dn != null) {
        final dd = int.parse(dn.group(1)!);
        if (i + 2 < w.length && RegExp(r"^'?\d{4}$").hasMatch(w[i + 2])) {
          final d = _valid(_year(w[i + 2]), mm, dd);
          return d == null ? null : (value: d, used: 3);
        }
        final d = _upcoming(day, mm, dd);
        return d == null ? null : (value: d, used: 2);
      }
    }
    return null;
  }

  static int _year(String raw) {
    final y = int.parse(raw.replaceAll("'", ''));
    return y < 100 ? 2000 + y : y;
  }

  static DateTime? _valid(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    return dt.month == m ? dt : null;
  }

  /// This year's date, or next year's when it has already passed.
  static DateTime? _upcoming(DateTime day, int m, int d) {
    final dt = _valid(day.year, m, d);
    if (dt == null) return null;
    return dt.isBefore(day) ? _valid(day.year + 1, m, d) : dt;
  }

  static DateTime _onOrAfter(DateTime day, int weekday) {
    final diff = (weekday - day.weekday) % 7;
    return day.add(Duration(days: diff));
  }

  static DateTime _weekStart(DateTime day) =>
      day.subtract(Duration(days: day.weekday - 1));

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// How the checklist shows a due: `Sun 30 Nov 07:30`, or
  /// `Todoist will read: every 1st`.
  static String describe(TaskDue due) {
    final d = due.date;
    if (d == null) return 'Todoist will read: ${due.dueString ?? due.phrase}';
    final day = '${_dayNames[d.weekday - 1]} ${d.day} ${_monthNames[d.month - 1]}';
    if (!due.hasTime) return day;
    return '$day ${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}

class _Tok {
  _Tok(this.raw) : lower = raw.toLowerCase();

  final String raw;
  final String lower;

  bool get capitalised =>
      raw.isNotEmpty && raw[0] != raw[0].toLowerCase();
}
