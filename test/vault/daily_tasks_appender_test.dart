import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/vault/daily_tasks_appender.dart';

void main() {
  const appender = DailyTasksAppender();
  final date = DateTime(2026, 10, 16);

  test('creates stub daily note with structured block', () {
    final body = appender.apply(
      existingBody: null,
      pageId: '20261016-p7k2',
      markdown: '- [ ] Buy ink cartridges\n- [ ] Review fleeting notes',
      date: date,
    );

    expect(body, contains('# 2026-10-16'));
    expect(body, contains('## Tasks'));
    expect(body, contains('<!-- symbol-journal:p7k2 -->'));
    expect(body, contains('- [ ] Buy ink cartridges'));
    expect(body, contains('- [ ] Review fleeting notes'));
    expect(body, contains('<!-- /symbol-journal:p7k2 -->'));
  });

  test('interprets Mitch sample without checkbox-forcing', () {
    const sample = '''
19 Oct '26
Important:
- Seeing shanolin
- License Management
- Audit logs
Notes:
Worked on setting up the bare bare sewers. Did inventory review on all 3 platform sewers.
Log:
☉
19 Oct '26
''';
    final body = appender.apply(
      existingBody: null,
      pageId: '20261020-ktt5',
      markdown: sample,
      date: DateTime(2026, 10, 20),
    );

    expect(body, contains('# 2026-10-20'));
    expect(body, contains('## Tasks'));
    expect(body, contains('<!-- symbol-journal:ktt5 -->'));
    expect(body, contains('**Important:**'));
    expect(body, contains('- Seeing shanolin'));
    expect(body, contains('**Notes:**'));
    expect(body, contains('Worked on setting up the bare bare sewers'));
    expect(body, contains('**Log:**'));
    expect(body, contains('<!-- /symbol-journal:ktt5 -->'));
    expect(body, isNot(contains('- [ ] Important')));
    expect(body, isNot(contains('- [ ] - Seeing')));
  });

  test('replaces same page_id block on re-commit', () {
    final first = appender.apply(
      existingBody: null,
      pageId: '20261016-p7k2',
      tasks: const ['- [ ] Old task'],
      date: date,
    );
    final second = appender.apply(
      existingBody: first,
      pageId: '20261016-p7k2',
      tasks: const ['- [ ] New task'],
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
      markdown: '- [ ] From paper',
      date: date,
    );

    expect(body, contains('- [ ] Existing user task'));
    expect(body, contains('- [ ] From paper'));
    expect(body, contains('<!-- symbol-journal:abcd -->'));
  });

  test('legacy tasks list is interpreted, not force-checkboxed', () {
    final body = appender.apply(
      existingBody: null,
      pageId: '20261016-p7k2',
      tasks: const ['Important:', '- Nested item', 'Short note line'],
      date: date,
    );

    expect(body, contains('**Important:**'));
    expect(body, contains('- Nested item'));
    expect(body, contains('Short note line'));
    expect(body, isNot(contains('- [ ] Important')));
    expect(body, isNot(contains('- [ ] - Nested')));
  });
}
