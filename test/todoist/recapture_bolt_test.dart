import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
import 'package:hue_memory/todoist/daily_todoist_parser.dart';
import 'package:hue_memory/todoist/daily_todoist_plan.dart';
import 'package:hue_memory/todoist/daily_todoist_sync.dart';
import 'package:hue_memory/todoist/ledger_linker.dart';
import 'package:hue_memory/todoist/todoist_client.dart';
import 'package:hue_memory/todoist/todoist_ledger.dart';
import 'package:hue_memory/todoist/unmatched_done_store.dart';
import 'package:hue_memory/writers/canvas_writer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_todoist_client.dart';

/// Reproduces the device report: the · daily page with "bolt | 16:50",
/// captured, then re-captured (new page ID, Gemini node ids and OCR wording
/// drift), then re-captured again with "bolt | 16:50" ticked off.
void main() {
  late ScriptedTodoistClient client;
  late PrefsTodoistLedgerStore ledger;
  late DailyTodoistSync sync;

  final pageDay = DateTime(2026, 11, 27);

  List<OcrRegion> nodes(Map<String, String> labels) => [
        for (final e in labels.entries)
          OcrRegion(
            id: e.key,
            text: e.value,
            confidence: 0.9,
            bbox: const [0.1, 0.1, 0.2, 0.08],
          ),
      ];

  List<CanvasEdge> links(List<(String, String)> pairs) => [
        for (var i = 0; i < pairs.length; i++)
          CanvasEdge(id: 'e$i', fromNode: pairs[i].$1, toNode: pairs[i].$2),
      ];

  /// One capture of the page: hub, High (bolt + audit), Reminders, Done.
  DailyTodoistPlan capture({
    required String prefix,
    required String hub,
    required String bolt,
    required String audit,
    required String car,
  }) {
    String id(String k) => '$prefix$k';
    return sync.planner.plan(
      markdown: '',
      regions: nodes({
        id('hub'): hub,
        id('high'): 'High',
        id('bolt'): bolt,
        id('audit'): audit,
        id('rem'): 'Reminders',
        id('car'): car,
        id('done'): 'Done',
      }),
      edges: links([
        (id('hub'), id('high')),
        (id('high'), id('bolt')),
        (id('high'), id('audit')),
        (id('hub'), id('rem')),
        (id('rem'), id('car')),
        (id('hub'), id('done')),
      ]),
    );
  }

  DailyTodoistPlan first() => capture(
        prefix: 'n',
        hub: "27 Nov '26",
        bolt: 'bolt | 16:50',
        audit: 'Audit audio logs',
        car: 'Book Car Service',
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    client = ScriptedTodoistClient();
    ledger = PrefsTodoistLedgerStore();
    sync = DailyTodoistSync(
      client: client,
      unmatchedStore: MemoryUnmatchedDoneStore(),
      ledgerStore: ledger,
      clock: () => DateTime(2026, 11, 27, 9),
    );
  });

  test('"bolt | 16:50" becomes "bolt" due today 16:50; others get no due',
      () async {
    final plan = first();
    final bolt = plan.creates.firstWhere((t) => t.content == 'bolt');
    expect(bolt.create.dueDate, DateTime(2026, 11, 27, 16, 50));
    expect(bolt.create.dueHasTime, isTrue);

    // No date or time on the page → no due date at all (not the page date).
    final others = plan.creates.where((t) => t.content != 'bolt').toList();
    expect(others.map((t) => t.content), ['Audit audio logs', 'Book Car Service']);
    expect(others.every((t) => t.create.dueDate == null), isTrue);

    await sync.execute(plan, pageId: '20261127-aaaa');
    expect(client.created.first.content, 'bolt');
    expect(client.dues['new-1'], (due: DateTime(2026, 11, 27, 16, 50), hasTime: true));
    expect(client.dues['new-2'], (due: null, hasTime: false));
    expect(client.dues['new-3'], (due: null, hasTime: false));
    expect((await ledger.read()).first.due, '2026-11-27T16:50');
  });

  test('re-capture (new page ID, new node ids, OCR drift) updates, no copies',
      () async {
    await sync.execute(first(), pageId: '20261127-aaaa');
    expect(client.created, hasLength(3));

    final again = await sync.linkPlan(
      capture(
        prefix: 'g',
        hub: '27 Nov 26',
        bolt: 'Bolt | 16.50',
        audit: 'Audit audio log',
        car: 'Book car service.',
      ),
      pageId: '20261127-bbbb',
    );

    expect(again.linkedPageId, '20261127-aaaa');
    expect(again.updateCount, 3);
    expect(again.newCount, 0);

    final result = await sync.execute(again, pageId: '20261127-bbbb');
    expect(result.createdCount, 0);
    expect(client.created, hasLength(3));
    expect(result.updatedCount + result.unchangedCount, 3);
  });

  for (final ticked in [
    '✓ bolt | 16:50',
    'bolt | 16:50 ✓',
    '~~bolt | 16:50~~',
    '[x] bolt | 16:50',
    '☑ bolt | 16:50',
  ]) {
    test('ticked "$ticked" on a re-capture completes the existing task',
        () async {
      await sync.execute(first(), pageId: '20261127-aaaa');

      final plan = await sync.linkPlan(
        capture(
          prefix: 'g',
          hub: '27 Nov 26',
          bolt: ticked,
          audit: 'Audit audio logs',
          car: 'Book Car Service',
        ),
        pageId: '20261127-cccc',
      );
      expect(plan.creates.map((t) => t.content), isNot(contains('bolt')));
      expect(plan.done.map((d) => d.content), ['bolt | 16:50']);

      final result = await sync.execute(plan, pageId: '20261127-cccc');

      expect(client.closedIds, ['new-1']);
      expect(result.completedCount, 1);
      expect(result.createdCount, 0);
      expect(client.listCalls, 0);
      final bolt = (await ledger.read()).firstWhere((e) => e.todoistId == 'new-1');
      expect(bolt.status, LedgerStatus.completed);
    });
  }

  test('a done line "bolt | 16:50" closes the Todoist task "bolt" (live)',
      () async {
    client.open.add(const TodoistTask(id: 'live-1', content: 'bolt'));
    final result = await sync.execute(
      DailyTodoistPlan.fromParse(
        const DailyTodoistParseResult(done: ['bolt | 16:50']),
      ),
      pageId: '20261127-dddd',
    );
    expect(client.closedIds, ['live-1']);
    expect(result.completedCount, 1);
  });

  test('an empty ledger (tasks made before it existed) links via live tasks',
      () async {
    client.open.addAll(const [
      TodoistTask(id: 'old-1', content: 'bolt | 16:50'),
      TodoistTask(id: 'old-2', content: 'Audit audio logs', priority: 4),
      TodoistTask(id: 'old-3', content: 'Book Car Service'),
    ]);

    final plan = await sync.linkPlan(
      first(),
      pageId: '20261127-eeee',
      includeLive: true,
    );
    expect(plan.liveChecked, isTrue);
    expect(plan.rememberedCount, 0);
    expect(
      [for (final t in plan.creates) t.match?.todoistId],
      ['old-1', 'old-2', 'old-3'],
    );

    final result = await sync.execute(plan, pageId: '20261127-eeee');
    expect(result.createdCount, 0);
    expect(client.created, isEmpty);
    // The time moved from the text into a due datetime.
    final boltUpdate = client.updates.firstWhere((u) => u.id == 'old-1');
    expect(boltUpdate.content, 'bolt');
    expect(
      client.updatedDues['old-1'],
      (due: DateTime(2026, 11, 27, 16, 50), hasTime: true),
    );
    expect((await ledger.read()).map((e) => e.todoistId).toSet(), {
      'old-1',
      'old-2',
      'old-3',
    });
  });

  test('live matching skips tasks the ledger already matched', () async {
    await sync.execute(first(), pageId: '20261127-aaaa');
    client.open.add(const TodoistTask(id: 'other', content: 'bolt'));
    final plan = await sync.linkPlan(
      first(),
      pageId: '20261127-ffff',
      includeLive: true,
    );
    expect(plan.creates.first.match?.todoistId, 'new-1');
    expect(client.listCalls, 0);
  });

  test('the markdown path ticks, times and leaves undated tasks undated', () {
    final plan = DailyTodoistPlanner(clock: () => pageDay).plan(
      markdown: 'high:\n- [x] bolt | 16:50\n- Pay rent | 9:15\n- Call mum\n',
    );
    expect(plan.done.map((d) => d.content), ['bolt | 16:50']);
    expect(plan.creates.map((t) => t.content), ['Pay rent', 'Call mum']);
    expect(plan.creates[0].create.dueDate, DateTime(2026, 11, 27, 9, 15));
    expect(plan.creates[1].create.dueDate, isNull);
  });

  test('a task with no date or time is sent with no due date at all',
      () async {
    final plan = DailyTodoistPlanner(clock: () => pageDay).plan(
      markdown: 'high:\n- Call mum\n',
      regions: nodes({'h': "27 Nov '26", 'b': 'High', 'c': 'Call mum'}),
      edges: links([('h', 'b'), ('b', 'c')]),
    );
    expect(plan.creates.single.create.dueDate, isNull);
    await sync.execute(plan, pageId: 'p');
    expect(client.dues['new-1'], (due: null, hasTime: false));
    expect(TodoistClient.dueFields(null, hasTime: false), isEmpty);
  });

  group('TaskText', () {
    test('core drops a time / date suffix and done marks', () {
      expect(TaskText.core('bolt | 16:50'), 'bolt');
      expect(TaskText.core('Bolt | 16.50'), 'bolt');
      expect(TaskText.core('✓ bolt | 16:50'), 'bolt');
      expect(TaskText.core('~~bolt | 16:50~~'), 'bolt');
      expect(TaskText.core('Call mum 4pm'), 'call mum');
      expect(TaskText.core('Post office 28/11'), 'post office');
      expect(TaskText.core('Dentist | 27 Nov'), 'dentist');
      expect(TaskText.core('bolt'), 'bolt');
      expect(TaskText.core('Room 101'), 'room 101');
      expect(TaskText.core('16:50'), '16:50');
    });

    test('paper and Todoist text after the due move are the same task', () {
      expect(TaskText.similarity('bolt | 16:50', 'bolt'), 1);
      expect(TaskText.similarity('bolt | 16:50', 'bolt | 17:30'), 1);
    });

    test('splitPipeTime', () {
      final s = TaskText.splitPipeTime('bolt | 16:50')!;
      expect(s.content, 'bolt');
      expect((s.time.hour, s.time.minute), (16, 50));
      expect(TaskText.splitPipeTime('bolt | 4:50pm')!.time.hour, 16);
      expect(TaskText.splitPipeTime('bolt | 25:00'), isNull);
      expect(TaskText.splitPipeTime('bolt 16:50'), isNull);
      expect(TaskText.splitPipeTime('| 16:50'), isNull);
    });

    test('isTicked', () {
      expect(TaskText.isTicked('✓ bolt'), isTrue);
      expect(TaskText.isTicked('bolt ✔'), isTrue);
      expect(TaskText.isTicked('- [x] bolt'), isTrue);
      expect(TaskText.isTicked('~~bolt~~'), isTrue);
      expect(TaskText.isTicked('bolt | 16:50'), isFalse);
      expect(TaskText.isTicked('- [ ] bolt'), isFalse);
      expect(TaskText.withoutMarks('~~bolt | 16:50~~'), 'bolt | 16:50');
    });
  });
}
