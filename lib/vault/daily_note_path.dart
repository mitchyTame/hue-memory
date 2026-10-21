import 'package:intl/intl.dart';

import 'vault_paths.dart';

/// Parse / format the calendar day that titles a daily note file.
class DailyNoteDate {
  const DailyNoteDate._();

  static final RegExp _iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final RegExp _dayMonYear = RegExp(
    r"^(\d{1,2})\s+([A-Za-z]{3,9})\s+'?(\d{2,4})$",
  );

  /// `YYYY-MM-DD` for the title field / file stem.
  static String formatIso(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Calendar day from title text, or null if not a date.
  ///
  /// Accepts `YYYY-MM-DD` and `D Mon YY` / `D Mon 'YY` / `D Mon YYYY`
  /// (e.g. `19 Oct '26`).
  static DateTime? tryParse(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;

    final iso = _iso.firstMatch(t);
    if (iso != null) {
      final y = int.parse(iso.group(1)!);
      final m = int.parse(iso.group(2)!);
      final d = int.parse(iso.group(3)!);
      return _validDay(y, m, d);
    }

    final soft = _dayMonYear.firstMatch(t);
    if (soft != null) {
      final d = int.parse(soft.group(1)!);
      final mon = soft.group(2)!;
      var y = int.parse(soft.group(3)!);
      if (y < 100) y += 2000;
      final m = _monthNumber(mon);
      if (m == null) return null;
      return _validDay(y, m, d);
    }

    return null;
  }

  static DateTime? _validDay(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final dt = DateTime(year, month, day);
    if (dt.year != year || dt.month != month || dt.day != day) return null;
    return dt;
  }

  static int? _monthNumber(String name) {
    const months = <String, int>{
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };
    return months[name.toLowerCase()];
  }
}

/// Settings mirrored from Obsidian Daily notes (folder + Moment-style format).
class DailyNoteSettings {
  const DailyNoteSettings({
    this.folder = 'Organising/Daily',
    this.format = 'YYYY-MM-DD',
  });

  /// New file location (may be empty string for vault root).
  final String folder;

  /// Moment-style tokens: YYYY MM DD MMMM MMM M D and `[literals]`.
  final String format;
}

/// Resolves today's daily note path from folder + Moment-compatible format.
class DailyNotePathResolver {
  const DailyNotePathResolver();

  /// Vault-relative path for [date] (defaults to "now").
  String resolve(DailyNoteSettings settings, {DateTime? date}) {
    final when = date ?? DateTime.now();
    final expanded = expandMomentFormat(settings.format, when);
    final fileName = expanded.toLowerCase().endsWith('.md')
        ? expanded
        : '$expanded.md';

    return joinVaultRelative(settings.folder, fileName);
  }

  /// Expand a Moment-compatible subset used by Obsidian Daily notes.
  ///
  /// Supported tokens: `YYYY`, `MMMM`, `MMM`, `MM`, `DD`, `M`, `D`,
  /// and escaped literals in `[brackets]`.
  String expandMomentFormat(String format, DateTime date) {
    final buffer = StringBuffer();
    var i = 0;
    while (i < format.length) {
      if (format[i] == '[') {
        final end = format.indexOf(']', i + 1);
        if (end == -1) {
          buffer.write(format[i]);
          i++;
          continue;
        }
        buffer.write(format.substring(i + 1, end));
        i = end + 1;
        continue;
      }

      final rest = format.substring(i);
      if (rest.startsWith('YYYY')) {
        buffer.write(DateFormat('yyyy').format(date));
        i += 4;
      } else if (rest.startsWith('MMMM')) {
        buffer.write(DateFormat('MMMM').format(date));
        i += 4;
      } else if (rest.startsWith('MMM')) {
        buffer.write(DateFormat('MMM').format(date));
        i += 3;
      } else if (rest.startsWith('MM')) {
        buffer.write(DateFormat('MM').format(date));
        i += 2;
      } else if (rest.startsWith('DD')) {
        buffer.write(DateFormat('dd').format(date));
        i += 2;
      } else if (rest.startsWith('M')) {
        buffer.write(DateFormat('M').format(date));
        i += 1;
      } else if (rest.startsWith('D')) {
        buffer.write(DateFormat('d').format(date));
        i += 1;
      } else {
        buffer.write(format[i]);
        i++;
      }
    }
    return buffer.toString();
  }
}
