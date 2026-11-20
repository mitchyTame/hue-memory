import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/todoist/daily_todoist_parser.dart';

void main() {
  const parser = DailyTodoistParser();

  group('section → label mapping', () {
    test('maps high/medium/low/events/reminders and drops logs/notes', () {
      const sample = '''
19 Oct '26
high:
- Call dentist
medium:
- License Management
low:
- Tidy desk
events:
- Team standup
reminders:
- Pay rent
Notes:
Worked on setting up sewers. Long prose stays out of Todoist.
Log:
☉
done:
- Ship release
''';

      final result = parser.parse(sample);

      expect(
        result.creates.map((c) => '${c.label}:${c.content}').toList(),
        [
          'high:Call dentist',
          'medium:License Management',
          'low:Tidy desk',
          'events:Team standup',
          'reminders:Pay rent',
        ],
      );
      expect(result.done, ['Ship release']);
      expect(
        result.creates.any((c) => c.content.contains('sewers')),
        isFalse,
      );
      expect(result.creates.any((c) => c.content == '☉'), isFalse);
    });

    test('aliases Important → high and ignores plain checkboxes outside sections', () {
      const sample = '''
☐ Orphan checkbox ignored
Important:
- Seeing shanolin
- [ ] License Management
☐ Audit logs
''';

      final result = parser.parse(sample);
      expect(result.creates, hasLength(3));
      expect(result.creates.every((c) => c.label == 'high'), isTrue);
      expect(
        result.creates.map((c) => c.content).toList(),
        ['Seeing shanolin', 'License Management', 'Audit logs'],
      );
    });

    test('sets optional Todoist priorities for high/medium/low', () {
      final result = parser.parse('''
high:
- A
medium:
- B
low:
- C
events:
- D
''');
      expect(result.creates[0].priority, 4);
      expect(result.creates[1].priority, 3);
      expect(result.creates[2].priority, 2);
      expect(result.creates[3].priority, isNull);
    });
  });

  group('done-match failure path (parser + sync helper)', () {
    test('done section lines are collected for matching', () {
      final result = parser.parse('''
done:
- Already done
- Mystery task
high:
- New work
''');
      expect(result.done, ['Already done', 'Mystery task']);
      expect(result.creates.single.content, 'New work');
    });
  });
}
