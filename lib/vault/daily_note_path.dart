import 'package:intl/intl.dart';

import 'vault_paths.dart';

/// Settings mirrored from Obsidian Daily notes (folder + Moment-style format).
class DailyNoteSettings {
  const DailyNoteSettings({
    this.folder = 'Daily Notes',
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
