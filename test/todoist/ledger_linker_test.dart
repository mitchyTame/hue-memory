import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/todoist/daily_todoist_parser.dart';
import 'package:hue_memory/todoist/daily_todoist_plan.dart';
import 'package:hue_memory/todoist/ledger_linker.dart';
import 'package:hue_memory/todoist/todoist_ledger.dart';

LedgerEntry _e(
  String id,
  String content, {
  String page = 'p1',
  LedgerStatus status = LedgerStatus.open,
  DateTime? at,
}) {
  return LedgerEntry(
    todoistId: id,
    content: content,
    pageId: page,
    createdAt: at ?? DateTime.utc(2026, 11, 26),
    status: status,
  );
}

DailyTodoistPlan _plan(List<String> contents) {
  return DailyTodoistPlan.fromParse(
    DailyTodoistParseResult(
      creates: [
        for (final (i, c) in contents.indexed)
          DailyTodoistCreate(content: c, label: 'high', nodeId: 'n$i'),
      ],
    ),
  );
}

void main() {
  group('TaskText.similarity', () {
    test('same text, bullets and case ignored', () {
      expect(TaskText.similarity('- Call dentist', 'call  Dentist'), 1);
    });

    test('reworded and OCR-typo variants match', () {
      expect(
        TaskText.similarity('Call dentist', 'Call the dentist'),
        greaterThanOrEqualTo(LedgerLinker.threshold),
      );
      expect(
        TaskText.similarity('Pay rent', 'Pay rant'),
        greaterThanOrEqualTo(LedgerLinker.threshold),
      );
    });

    test('different short tasks do not match', () {
      expect(
        TaskText.similarity('Call mum', 'Call dad'),
        lessThan(LedgerLinker.threshold),
      );
      expect(
        TaskText.similarity('Buy milk', 'Book flights'),
        lessThan(LedgerLinker.threshold),
      );
    });
  });

  group('LedgerLinker', () {
    final earlier = [
      _e('t1', 'Call dentist'),
      _e('t2', 'Pay rent'),
      _e('t3', 'Book flights'),
    ];

    test('a re-capture links to the earlier page by text overlap', () {
      final linked = LedgerLinker.link(
        _plan(['Call dentist', 'Pay rent', 'Buy milk']),
        earlier,
        pageId: 'new-page',
      );
      expect(linked.linkedPageId, 'p1');
      expect(linked.linkedByPageId, isFalse);
      expect(linked.creates[0].match?.todoistId, 't1');
      expect(linked.creates[1].match?.todoistId, 't2');
      expect(linked.creates[2].match, isNull);
      expect(linked.updateCount, 2);
      expect(linked.newCount, 1);
      expect(linked.creates[0].isUpdate, isTrue);
      expect(linked.creates[2].isUpdate, isFalse);
    });

    test('the same page ID links even when the text changed a lot', () {
      final linked = LedgerLinker.link(
        _plan(['Totally different']),
        earlier,
        pageId: 'p1',
      );
      expect(linked.linkedPageId, 'p1');
      expect(linked.linkedByPageId, isTrue);
      expect(linked.updateCount, 0);
      expect(linked.newCount, 1);
    });

    test('one carried-over task links on its own, not the whole page', () {
      final linked = LedgerLinker.link(
        _plan(['Call dentist', 'Buy milk', 'Water plants', 'Gym']),
        earlier,
        pageId: 'new-page',
      );
      expect(linked.hasLinkedPage, isFalse);
      expect(linked.creates[0].match?.todoistId, 't1');
      expect(linked.creates.skip(1).every((t) => t.match == null), isTrue);
      expect(linked.rememberedCount, 3);
    });

    test('a loosely similar task on an unrelated page is not linked', () {
      final linked = LedgerLinker.link(
        _plan(['Call the dentist today', 'Buy milk', 'Water plants', 'Gym']),
        earlier,
        pageId: 'new-page',
      );
      expect(linked.hasLinks, isFalse);
    });

    test('a single-item page matching exactly is treated as a re-capture', () {
      final linked = LedgerLinker.link(_plan(['Pay rent']), earlier);
      expect(linked.creates.single.match?.todoistId, 't2');
    });

    test('completed entries are not matched', () {
      final linked = LedgerLinker.link(
        _plan(['Call dentist', 'Pay rent']),
        [
          _e('t1', 'Call dentist', status: LedgerStatus.completed),
          _e('t2', 'Pay rent', status: LedgerStatus.completed),
        ],
      );
      expect(linked.hasLinkedPage, isFalse);
    });

    test('matching is one-to-one', () {
      final linked = LedgerLinker.link(
        _plan(['Pay rent', 'Pay rent']),
        [_e('t2', 'Pay rent')],
      );
      final ids = [for (final t in linked.creates) t.match?.todoistId];
      expect(ids.where((i) => i == 't2'), hasLength(1));
    });

    test('picks the page with the most matches, then the most recent', () {
      final linked = LedgerLinker.link(
        _plan(['Call dentist', 'Pay rent']),
        [
          _e('a1', 'Call dentist', page: 'old', at: DateTime.utc(2026, 11, 1)),
          _e('a2', 'Pay rent', page: 'old', at: DateTime.utc(2026, 11, 1)),
          _e('b1', 'Call dentist', page: 'newer', at: DateTime.utc(2026, 11, 20)),
          _e('b2', 'Pay rent', page: 'newer', at: DateTime.utc(2026, 11, 20)),
        ],
      );
      expect(linked.linkedPageId, 'newer');
    });

    test('flipping a badge sends the item as a new task', () {
      var plan = LedgerLinker.link(_plan(['Call dentist', 'Pay rent']), earlier);
      expect(plan.effectiveCreates.map((c) => c.updateTodoistId), ['t1', 't2']);
      expect(plan.effectiveCreates.first.previousContent, 'Call dentist');

      plan = plan.setTaskUpdate(0, false);
      expect(plan.creates[0].isUpdate, isFalse);
      expect(plan.effectiveCreates.map((c) => c.updateTodoistId), [null, 't2']);
      expect(plan.setTaskUpdate(0, true).creates[0].isUpdate, isTrue);
    });

    test('an unmatched item cannot be switched to update', () {
      final plan = LedgerLinker.link(_plan(['Call dentist', 'Gym']), earlier);
      expect(plan.setTaskUpdate(1, true).creates[1].isUpdate, isFalse);
    });
  });
}
