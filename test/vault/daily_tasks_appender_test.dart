import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/vault/daily_tasks_appender.dart';

void main() {
  const appender = DailyTasksAppender();
  final date = DateTime(2026, 10, 16);

  test('creates dated stub and appends OCR markdown — no markers or ## Tasks', () {
    final body = appender.apply(
      existingBody: null,
      markdown: '- [ ] Buy ink cartridges\n- [ ] Review fleeting notes',
      date: date,
    );

    expect(body, startsWith('# 2026-10-16\n'));
    expect(body, contains('- [ ] Buy ink cartridges'));
    expect(body, contains('- [ ] Review fleeting notes'));
    expect(body, isNot(contains('## Tasks')));
    expect(body, isNot(contains('symbol-journal')));
  });

  test('interprets Mitch sample without checkbox-forcing or app wrappers', () {
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
      markdown: sample,
      date: DateTime(2026, 10, 20),
    );

    expect(body, startsWith('# 2026-10-20\n'));
    expect(body, contains('**Important:**'));
    expect(body, contains('- Seeing shanolin'));
    expect(body, contains('**Notes:**'));
    expect(body, contains('Worked on setting up the bare bare sewers'));
    expect(body, contains('**Log:**'));
    expect(body, isNot(contains('## Tasks')));
    expect(body, isNot(contains('symbol-journal')));
    expect(body, isNot(contains('- [ ] Important')));
    expect(body, isNot(contains('- [ ] - Seeing')));
  });

  test('appends without removing existing user content', () {
    const existing = '# 2026-10-16\n\n- [ ] Existing user task\n';
    final body = appender.apply(
      existingBody: existing,
      markdown: '- [ ] From paper',
      date: date,
    );

    expect(body, contains('- [ ] Existing user task'));
    expect(body, contains('- [ ] From paper'));
    expect(body, isNot(contains('symbol-journal')));
  });

  test('strips legacy symbol-journal markers from existing body', () {
    const existing = '''
# 2026-10-16

## Tasks
<!-- symbol-journal:old1 -->
- [ ] Old capture
<!-- /symbol-journal:old1 -->
''';
    final body = appender.apply(
      existingBody: existing,
      markdown: 'Fresh OCR line',
      date: date,
    );

    expect(body, contains('Fresh OCR line'));
    expect(body, contains('- [ ] Old capture'));
    expect(body, isNot(contains('symbol-journal')));
  });

  test('legacy tasks list is interpreted, not force-checkboxed', () {
    final body = appender.apply(
      existingBody: null,
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
