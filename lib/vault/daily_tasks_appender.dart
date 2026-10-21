import 'daily_note_markdown.dart';

/// Appends OCR / confirm markdown into a dated daily note.
///
/// The handwritten page is the author — the app only titles the file
/// (`# YYYY-MM-DD`) and lightly normalizes OCR to acceptable markdown.
/// No HTML markers, no injected `## Tasks` section, no invented structure.
class DailyTasksAppender {
  const DailyTasksAppender();

  static final RegExp _legacyJournalMarker = RegExp(
    r'^[ \t]*<!--\s*/?symbol-journal:[^>]*-->[ \t]*\n?',
    multiLine: true,
  );

  /// Returns the full daily-note body after appending [markdown] (or [tasks]).
  ///
  /// [markdown] is OCR / confirm body. When only [tasks] is provided, lines
  /// are joined and interpreted the same way.
  String apply({
    required String? existingBody,
    String? markdown,
    List<String>? tasks,
    required DateTime date,
    @Deprecated('Unused — OCR owns section structure')
    String? pageId,
    @Deprecated('Unused — do not inject pack section headings')
    String sectionHeading = '## Tasks',
  }) {
    assert(
      markdown != null || tasks != null,
      'DailyTasksAppender.apply requires markdown or tasks',
    );

    final source = markdown ??
        tasks!
            .map((t) => t.trimRight())
            .where((t) => t.trim().isNotEmpty)
            .join('\n');
    final interpreted = DailyNoteMarkdown.interpret(source);

    var base = (existingBody == null || existingBody.trim().isEmpty)
        ? _dateTitle(date)
        : existingBody;
    base = _stripLegacyMarkers(base);

    if (interpreted.isEmpty) {
      return '${base.trimRight()}\n';
    }

    final trimmed = base.trimRight();
    return '$trimmed\n\n$interpreted\n';
  }

  /// Sole app-authored line: the daily file title.
  static String _dateTitle(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '# $y-$m-$d\n';
  }

  static String _stripLegacyMarkers(String body) {
    return body.replaceAll(_legacyJournalMarker, '');
  }
}
