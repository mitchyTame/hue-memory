import '../capture/page_id.dart';
import 'daily_note_markdown.dart';

/// Appends (or replaces) a page_id-scoped block under a daily-note section.
///
/// Content is interpreted into Obsidian-ready markdown (checkboxes only for
/// real tasks). Symbol-journal HTML markers keep updates idempotent.
class DailyTasksAppender {
  const DailyTasksAppender();

  /// Returns the full daily-note body after applying [markdown] for [pageId].
  ///
  /// [markdown] is OCR / confirm body (structured or flat). Prefer this over
  /// [tasks]. When [tasks] is provided without [markdown], lines are joined
  /// and interpreted the same way.
  String apply({
    required String? existingBody,
    required String pageId,
    String? markdown,
    List<String>? tasks,
    required DateTime date,
    String sectionHeading = '## Tasks',
  }) {
    assert(
      markdown != null || tasks != null,
      'DailyTasksAppender.apply requires markdown or tasks',
    );

    final stem = PageId.shortStem(pageId);
    final startMarker = '<!-- symbol-journal:$stem -->';
    final endMarker = '<!-- /symbol-journal:$stem -->';

    final source = markdown ??
        tasks!
            .map((t) => t.trimRight())
            .where((t) => t.trim().isNotEmpty)
            .join('\n');
    final interpreted = DailyNoteMarkdown.interpret(source);

    final taskBlock = StringBuffer()
      ..writeln(startMarker);
    if (interpreted.isNotEmpty) {
      taskBlock.writeln(interpreted);
    }
    taskBlock.write(endMarker);

    final base = (existingBody == null || existingBody.trim().isEmpty)
        ? _minimalStub(date, sectionHeading)
        : existingBody;

    // Replace existing block for this page_id if present.
    final replaced =
        _replaceBlock(base, startMarker, endMarker, taskBlock.toString());
    if (replaced != null) return replaced;

    return _insertUnderSection(base, sectionHeading, taskBlock.toString());
  }

  static String _minimalStub(DateTime date, String sectionHeading) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '# $y-$m-$d\n\n$sectionHeading\n';
  }

  static String? _replaceBlock(
    String body,
    String startMarker,
    String endMarker,
    String newBlock,
  ) {
    final start = body.indexOf(startMarker);
    if (start == -1) return null;
    final end = body.indexOf(endMarker, start);
    if (end == -1) return null;
    final endOfBlock = end + endMarker.length;
    return body.replaceRange(start, endOfBlock, newBlock);
  }

  static String _insertUnderSection(
    String body,
    String sectionHeading,
    String block,
  ) {
    final headingIndex = body.indexOf(sectionHeading);
    if (headingIndex == -1) {
      final trimmed = body.trimRight();
      final sep = trimmed.isEmpty ? '' : '\n\n';
      return '$trimmed$sep$sectionHeading\n$block\n';
    }

    final afterHeading = headingIndex + sectionHeading.length;
    // Find next markdown H2 after this section, else EOF.
    final nextHeading = body.indexOf('\n## ', afterHeading);
    final insertAt = nextHeading == -1 ? body.length : nextHeading;

    final before = body.substring(0, insertAt).trimRight();
    final after = body.substring(insertAt);
    final mid = '\n$block';
    if (after.isEmpty) {
      return '$before$mid\n';
    }
    return '$before$mid\n$after';
  }
}
