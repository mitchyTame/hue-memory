import '../capture/page_id.dart';

/// Appends (or replaces) a page_id-scoped task block under a daily-note section.
class DailyTasksAppender {
  const DailyTasksAppender();

  /// Returns the full daily-note body after applying [tasks] for [pageId].
  String apply({
    required String? existingBody,
    required String pageId,
    required List<String> tasks,
    required DateTime date,
    String sectionHeading = '## Tasks',
  }) {
    final stem = PageId.shortStem(pageId);
    final startMarker = '<!-- symbol-journal:$stem -->';
    final endMarker = '<!-- /symbol-journal:$stem -->';

    final taskBlock = StringBuffer()
      ..writeln(startMarker);
    for (final task in tasks) {
      final text = task.trim();
      if (text.isEmpty) continue;
      taskBlock.writeln('- [ ] $text');
    }
    taskBlock.write(endMarker);

    final base = (existingBody == null || existingBody.trim().isEmpty)
        ? _minimalStub(date, sectionHeading)
        : existingBody;

    // Replace existing block for this page_id if present.
    final replaced = _replaceBlock(base, startMarker, endMarker, taskBlock.toString());
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
