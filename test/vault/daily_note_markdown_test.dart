import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/vault/daily_note_markdown.dart';

void main() {
  group('DailyNoteMarkdown.interpret', () {
    test('preserves Important / nested bullets / Notes prose / Log', () {
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

      final md = DailyNoteMarkdown.interpret(sample);

      expect(md, contains("19 Oct '26"));
      expect(md, contains('**Important:**'));
      expect(md, contains('- Seeing shanolin'));
      expect(md, contains('- License Management'));
      expect(md, contains('- Audit logs'));
      expect(md, contains('**Notes:**'));
      expect(
        md,
        contains(
          'Worked on setting up the bare bare sewers. Did inventory review on all 3 platform sewers.',
        ),
      );
      expect(md, contains('**Log:**'));
      expect(md, contains('☉'));

      // Must not force every line into a checkbox.
      expect(md, isNot(contains('- [ ] Important')));
      expect(md, isNot(contains('- [ ] - Seeing')));
      expect(md, isNot(contains('- [ ] Notes')));
      expect(md, isNot(contains('- [ ] Worked on')));
      expect(md, isNot(contains('- [ ] Log')));
      expect(md, isNot(contains('- [ ] ☉')));
      expect(md, isNot(contains("- [ ] 19 Oct")));
    });

    test('recovers from forced-checkbox OCR dump', () {
      const bad = '''
- [ ] 19 Oct '26
- [ ] Important:
- [ ] - Seeing shanolin
- [ ] - License Management
- [ ] - Audit logs
- [ ] Notes:
- [ ] Worked on setting up the bare bare sewers. Did inventory review on all 3 platform sewers.
- [ ] Log:
- [ ] ☉
- [ ] 19 Oct '26
''';

      final md = DailyNoteMarkdown.interpret(bad);

      expect(md, contains('**Important:**'));
      expect(md, contains('- Seeing shanolin'));
      expect(md, contains('- License Management'));
      expect(md, contains('**Notes:**'));
      expect(md, contains('Worked on setting up the bare bare sewers'));
      expect(md, contains('**Log:**'));
      expect(md, isNot(contains('- [ ] Important')));
      expect(md, isNot(contains('- [ ] - Seeing')));
    });

    test('keeps real checkboxes and OCR box glyphs', () {
      const sample = '''
☐ Buy ink cartridges
☑ Review fleeting notes
- [ ] Ship release
- [x] Already done
''';

      final md = DailyNoteMarkdown.interpret(sample);

      expect(md, contains('- [ ] Buy ink cartridges'));
      expect(md, contains('- [x] Review fleeting notes'));
      expect(md, contains('- [ ] Ship release'));
      expect(md, contains('- [x] Already done'));
    });

    test('does not turn plain unmarked lines into checkboxes', () {
      final md = DailyNoteMarkdown.interpret(
        'Buy ink cartridges\nReview fleeting notes',
      );
      expect(md, 'Buy ink cartridges\nReview fleeting notes');
      expect(md, isNot(contains('- [ ]')));
    });
  });
}
