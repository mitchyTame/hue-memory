import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
import 'package:hue_memory/todoist/daily_todoist_parser.dart';
import 'package:hue_memory/todoist/daily_todoist_plan.dart';
import 'package:hue_memory/todoist/due_phrase.dart';
import 'package:hue_memory/todoist/todoist_client.dart';
import 'package:hue_memory/writers/canvas_writer.dart';

void main() {
  // A Friday.
  final page = DateTime(2026, 11, 27);

  ({String content, TaskDue due})? read(String text) =>
      DuePhrase.extract(text, pageDate: page);

  group('DuePhrase.extract — strings as written on paper', () {
    test('"Sunday @ 07:30": the "@" is a separator, never sent', () {
      final r = read('Deshan walk Sunday @ 07:30')!;
      expect(r.content, 'Deshan walk');
      expect(r.due.date, DateTime(2026, 11, 29, 7, 30));
      expect(r.due.hasTime, isTrue);
      expect(r.due.phrase, 'Sunday 07:30');
      expect(r.due.phrase, isNot(contains('@')));
    });

    test('a line that is only "Sunday @ 07:30" keeps its words as text', () {
      final r = read('Sunday @ 07:30')!;
      expect(r.content, 'Sunday 07:30');
      expect(r.due.date, DateTime(2026, 11, 29, 7, 30));
    });

    test('"call mum tomorrow @ 4pm" → tomorrow of the page, 16:00', () {
      final r = read('call mum tomorrow @ 4pm')!;
      expect(r.content, 'call mum');
      expect(r.due.date, DateTime(2026, 11, 28, 16));
      expect(r.due.hasTime, isTrue);
      expect(DuePhrase.describe(r.due), 'Sat 28 Nov 16:00');
    });

    test('"bolt | 16:50" → the page date at 16:50, "|" removed', () {
      final r = read('bolt | 16:50')!;
      expect(r.content, 'bolt');
      expect(r.due.date, DateTime(2026, 11, 27, 16, 50));
      expect(r.due.hasTime, isTrue);
    });

    test('"pay rent every 1st" → left to Todoist as a recurring due string', () {
      final r = read('pay rent every 1st')!;
      expect(r.content, 'pay rent');
      expect(r.due.isResolved, isFalse);
      expect(r.due.dueString, 'every 1st');
      expect(DuePhrase.describe(r.due), 'Todoist will read: every 1st');
    });

    test('"submit Fri" → that Friday (the page day itself)', () {
      final r = read('submit Fri')!;
      expect(r.content, 'submit');
      expect(r.due.date, DateTime(2026, 11, 27));
      expect(r.due.hasTime, isFalse);
    });

    test('no date phrase → no due at all', () {
      expect(read('Buy milk'), isNull);
      expect(read('Read chapter 3'), isNull);
      expect(read('Buy milk | urgent'), isNull);
      expect(read('Email a@b.com'), isNull);
      expect(read('Lunch with sat team'), isNull);
    });

    test('other Todoist-style phrases', () {
      expect(read('Dentist Dec 3')!.due.date, DateTime(2026, 12, 3));
      expect(read('Gym 27 Nov')!.due.date, DateTime(2026, 11, 27));
      expect(read('Gym 3/12')!.due.date, DateTime(2026, 12, 3));
      expect(read('meet next Monday')!.due.date, DateTime(2026, 11, 30));
      expect(read('walk at 4pm')!.due.date, DateTime(2026, 11, 27, 16));
      expect(read('Call bank by Fri')!.content, 'Call bank');
      expect(read('tomorrow 9am')!.due.date, DateTime(2026, 11, 28, 9));
      final weekly = read('Standup every Monday @ 9am')!;
      expect(weekly.content, 'Standup');
      expect(weekly.due.dueString, 'every Monday at 9am');
    });

    test('a date already past this year rolls to next year', () {
      expect(read('Renew licence 20 Nov')!.due.date, DateTime(2027, 11, 20));
    });
  });

  group('DuePhrase.parsePhrase — typed in review', () {
    test('resolvable words resolve against the page date', () {
      final due = DuePhrase.parsePhrase('tomorrow @ 9am', pageDate: page)!;
      expect(due.date, DateTime(2026, 11, 28, 9));
    });

    test('anything else is sent as written and shown as Todoist will read', () {
      final due = DuePhrase.parsePhrase('in two weeks', pageDate: page)!;
      expect(due.isResolved, isFalse);
      expect(DuePhrase.describe(due), 'Todoist will read: in two weeks');
    });

    test('empty clears the due', () {
      expect(DuePhrase.parsePhrase('  @ ', pageDate: page), isNull);
    });
  });

  group('tasks from text', () {
    test('taskFromText strips the phrase and sets the due', () {
      final c = DailyTodoistParser.taskFromText(
        text: 'call mum tomorrow @ 4pm',
        label: 'family',
        pageDate: page,
      );
      expect(c.content, 'call mum');
      expect(c.dueDate, DateTime(2026, 11, 28, 16));
      expect(c.dueHasTime, isTrue);
      expect(c.dueLabel, 'Sat 28 Nov 16:00');
    });

    test('a recurring task carries a due string, not a date', () {
      final c = DailyTodoistParser.taskFromText(
        text: 'pay rent every 1st',
        label: 'home',
        pageDate: page,
      );
      expect(c.content, 'pay rent');
      expect(c.dueDate, isNull);
      expect(c.dueString, 'every 1st');
      expect(c.dueKey, 'every 1st');
    });

    test('markdown path: relative words use the page date; undated stays undated',
        () {
      final plan = DailyTodoistPlanner(clock: () => DateTime(2026, 11, 27, 9))
          .plan(
        markdown: 'high:\n'
            '- call mum tomorrow @ 4pm\n'
            '- submit Fri\n'
            '- pay rent every 1st\n'
            '- Buy milk\n',
      );
      final byText = {for (final t in plan.creates) t.content: t.create};
      expect(byText.keys, ['call mum', 'submit', 'pay rent', 'Buy milk']);
      expect(byText['call mum']!.dueDate, DateTime(2026, 11, 28, 16));
      expect(byText['submit']!.dueDate, DateTime(2026, 11, 27));
      expect(byText['pay rent']!.dueString, 'every 1st');
      expect(byText['Buy milk']!.hasDue, isFalse);
    });

    test('mindmap path: "tomorrow" is the day after the hub date, not today',
        () {
      final plan = DailyTodoistPlanner(clock: () => DateTime(2026, 12, 2, 9))
          .plan(
        markdown: '',
        regions: [
          for (final (id, text) in [
            ('hub', '20 Nov 2026'),
            ('a', 'Family'),
            ('a1', 'call mum tomorrow @ 4pm'),
            ('a2', 'Buy milk'),
          ])
            OcrRegion(
              id: id,
              text: text,
              confidence: 0.9,
              bbox: const [0.1, 0.1, 0.2, 0.08],
            ),
        ],
        edges: const [
          CanvasEdge(id: 'e1', fromNode: 'hub', toNode: 'a'),
          CanvasEdge(id: 'e2', fromNode: 'a', toNode: 'a1'),
          CanvasEdge(id: 'e3', fromNode: 'a', toNode: 'a2'),
        ],
      );
      expect(plan.pageDate, DateTime(2026, 11, 20));
      final byText = {for (final t in plan.creates) t.content: t.create};
      expect(byText['call mum']!.dueDate, DateTime(2026, 11, 21, 16));
      expect(byText['Buy milk']!.hasDue, isFalse);
    });
  });

  group('TodoistClient.dueFields', () {
    test('due string goes with due_lang en and no "@"', () {
      expect(
        TodoistClient.dueFields(null, hasTime: false, dueString: 'every Monday @ 9am'),
        {'due_string': 'every Monday 9am', 'due_lang': 'en'},
      );
    });

    test('absolute values keep due_date / due_datetime', () {
      expect(
        TodoistClient.dueFields(DateTime(2026, 11, 28), hasTime: false),
        {'due_date': '2026-11-28'},
      );
      expect(
        TodoistClient.dueFields(
          DateTime.utc(2026, 11, 28, 14),
          hasTime: true,
        ),
        {'due_datetime': '2026-11-28T14:00:00Z'},
      );
    });

    test('nothing when there is no due', () {
      expect(TodoistClient.dueFields(null, hasTime: false), isEmpty);
    });
  });
}
