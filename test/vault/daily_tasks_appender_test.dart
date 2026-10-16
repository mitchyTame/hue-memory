import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/vault/daily_tasks_appender.dart';

void main() {
  const appender = DailyTasksAppender();
  final date = DateTime(2026, 10, 16);

  test('creates stub daily note with task block', () {
    final body = appender.apply(
      existingBody: null,
      pageId: '20261016-p7k2',
      tasks: const ['Buy ink cartridges', 'Review fleeting notes'],
      date: date,
    );

    expect(body, contains('# 2026-10-16'));
    expect(body, contains('## Tasks'));
    expect(body, contains('<!-- symbol-journal:p7k2 -->'));
    expect(body, contains('- [ ] Buy ink cartridges'));
    expect(body, contains('- [ ] Review fleeting notes'));
    expect(body, contains('<!-- /symbol-journal:p7k2 -->'));
  });

  test('replaces same page_id block on re-commit', () {
    final first = appender.apply(
      existingBody: null,
      pageId: '20261016-p7k2',
      tasks: const ['Old task'],
      date: date,
    );
    final second = appender.apply(
      existingBody: first,
      pageId: '20261016-p7k2',
      tasks: const ['New task'],
      date: date,
    );

    expect(second, contains('- [ ] New task'));
    expect(second, isNot(contains('Old task')));
    expect('<!-- symbol-journal:p7k2 -->'.allMatches(second), hasLength(1));
  });

  test('appends new block without removing user tasks', () {
    const existing = '# 2026-10-16\n\n## Tasks\n- [ ] Existing user task\n';
    final body = appender.apply(
      existingBody: existing,
      pageId: '20261016-abcd',
      tasks: const ['From paper'],
      date: date,
    );

    expect(body, contains('- [ ] Existing user task'));
    expect(body, contains('- [ ] From paper'));
    expect(body, contains('<!-- symbol-journal:abcd -->'));
  });
}
