import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/todoist/daily_todoist_parser.dart';
import 'package:hue_memory/todoist/daily_todoist_plan.dart';
import 'package:hue_memory/todoist/daily_todoist_sync.dart';
import 'package:hue_memory/todoist/todoist_client.dart';
import 'package:hue_memory/todoist/todoist_ledger.dart';
import 'package:hue_memory/todoist/todoist_retry.dart';
import 'package:hue_memory/todoist/unmatched_done_store.dart';

import 'fake_todoist_client.dart';

DailyTodoistPlan _plan(
  List<String> contents, {
  List<String> done = const [],
}) {
  return DailyTodoistPlan.fromParse(
    DailyTodoistParseResult(
      creates: [
        for (final (i, c) in contents.indexed)
          DailyTodoistCreate(
            content: c,
            label: 'high',
            nodeId: 'n$i',
            priority: 4,
          ),
      ],
      done: done,
      sectionLabels: const ['high'],
    ),
  );
}

void main() {
  late ScriptedTodoistClient client;
  late MemoryTodoistLedgerStore ledger;
  late MemoryTodoistRetryStore retry;
  late MemoryUnmatchedDoneStore unmatched;
  late DailyTodoistSync sync;

  DailyTodoistSync build() => DailyTodoistSync(
        client: client,
        unmatchedStore: unmatched,
        retryStore: retry,
        ledgerStore: ledger,
        clock: () => DateTime.utc(2026, 11, 27, 9),
      );

  setUp(() {
    client = ScriptedTodoistClient();
    ledger = MemoryTodoistLedgerStore();
    retry = MemoryTodoistRetryStore();
    unmatched = MemoryUnmatchedDoneStore();
    sync = build();
  });

  group('ledger', () {
    test('records every created task with its Todoist id and page', () async {
      final result =
          await sync.execute(_plan(['Call dentist', 'Pay rent']), pageId: 'p1');

      expect(result.createdCount, 2);
      final entries = await ledger.read();
      expect(entries.map((e) => e.todoistId), ['new-1', 'new-2']);
      expect(entries.map((e) => e.content), ['Call dentist', 'Pay rent']);
      expect(entries.every((e) => e.pageId == 'p1' && e.isOpen), isTrue);
      expect(entries.first.priority, 4);
      expect(entries.first.nodeId, 'n0');
    });

    test('each create is persisted before the next one is sent', () async {
      final seen = <List<String>>[];
      client.beforeCreate = (content) async {
        seen.add([for (final e in await ledger.read()) e.content]);
      };
      await sync.execute(_plan(['A task', 'B task', 'C task']), pageId: 'p1');
      expect(seen, [
        <String>[],
        ['A task'],
        ['A task', 'B task'],
      ]);
    });

    test('tasks created before a mid-batch failure stay in the ledger',
        () async {
      client.createErrors['B task'] = TodoistApiException(
        'Todoist token rejected (401)',
        statusCode: 401,
      );
      final result =
          await sync.execute(_plan(['A task', 'B task', 'C task']), pageId: 'p1');
      expect(result.failed.map((f) => f.content), ['B task', 'C task']);
      expect((await ledger.read()).map((e) => e.content), ['A task']);
    });

    test('a ledger write failure does not fail the send', () async {
      final result = await DailyTodoistSync(
        client: client,
        unmatchedStore: unmatched,
        ledgerStore: _ThrowingLedger(),
      ).execute(_plan(['A task']), pageId: 'p1');
      expect(result.createdCount, 1);
      expect(result.hasFailures, isFalse);
      expect(result.warnings.single, contains('task ledger'));
    });
  });

  group('re-capture linking', () {
    test('updates the earlier task instead of creating a duplicate', () async {
      await sync.execute(_plan(['Call dentist', 'Pay rent']), pageId: 'p1');
      expect(client.created, hasLength(2));

      final second = await sync.linkPlan(
        _plan(['Call dentist today', 'Pay rent', 'Buy milk']),
        pageId: 'p2',
      );
      expect(second.linkedPageId, 'p1');
      expect(second.updateCount, 2);
      expect(second.newCount, 1);

      final result = await sync.execute(second, pageId: 'p2');

      expect(client.created.map((t) => t.content), [
        'Call dentist',
        'Pay rent',
        'Buy milk',
      ]);
      expect(result.createdCount, 1);
      expect(result.updatedCount, 1);
      expect(result.unchangedCount, 1);
      expect(client.updates, [
        (id: 'new-1', content: 'Call dentist today', priority: null),
      ]);
      expect(result.snackbarMessage, contains('1 updated'));

      final entries = await ledger.read();
      expect(entries.map((e) => e.todoistId), ['new-1', 'new-2', 'new-3']);
      expect(entries.first.content, 'Call dentist today');
      expect(entries.first.pageId, 'p2');
    });

    test('a changed priority patches only the priority; clearing sends 1',
        () async {
      await sync.execute(_plan(['Call dentist']), pageId: 'p1');
      var plan = await sync.linkPlan(_plan(['Call dentist']), pageId: 'p2');
      plan = plan.setTaskPriority(0, 3);
      await sync.execute(plan, pageId: 'p2');
      expect(client.updates.last, (id: 'new-1', content: null, priority: 3));

      plan = await sync.linkPlan(_plan(['Call dentist']), pageId: 'p3');
      plan = plan.setTaskPriority(0, null);
      await sync.execute(plan, pageId: 'p3');
      expect(client.updates.last, (id: 'new-1', content: null, priority: 1));
      expect(client.created, hasLength(1));
    });

    test('an unchanged re-capture sends nothing', () async {
      await sync.execute(_plan(['Call dentist', 'Pay rent']), pageId: 'p1');
      final plan = await sync.linkPlan(
        _plan(['Call dentist', 'Pay rent']),
        pageId: 'p2',
      );
      final result = await sync.execute(plan, pageId: 'p2');
      expect(result.createdCount, 0);
      expect(result.updatedCount, 0);
      expect(result.unchangedCount, 2);
      expect(client.updates, isEmpty);
      expect(client.created, hasLength(2));
    });

    test('a new subtask under an updated parent attaches to the old task',
        () async {
      await sync.execute(_plan(['Plan trip']), pageId: 'p1');
      final parsed = DailyTodoistPlan.fromParse(
        const DailyTodoistParseResult(
          creates: [
            DailyTodoistCreate(
              content: 'Plan trip',
              label: 'home',
              nodeId: 'a',
              priority: 4,
            ),
            DailyTodoistCreate(
              content: 'Book flights',
              label: 'home',
              nodeId: 'b',
              parentNodeId: 'a',
            ),
          ],
        ),
      );
      final plan = await sync.linkPlan(parsed, pageId: 'p2');
      await sync.execute(plan, pageId: 'p2');
      expect(client.parentIds['new-2'], 'new-1');
    });

    test('a 404 on update is kept for "recreate", not a crash', () async {
      await sync.execute(_plan(['Call dentist', 'Pay rent']), pageId: 'p1');
      client.updateNotFound.add('new-1');

      final plan = await sync.linkPlan(
        _plan(['Call dentist today', 'Pay rent']),
        pageId: 'p2',
      );
      final result = await sync.execute(plan, pageId: 'p2');

      expect(result.hasMissing, isTrue);
      expect(result.hasRetryable, isFalse);
      expect(result.failed.single.kind, FailedItemKind.update);
      expect(result.failed.single.remoteMissing, isTrue);
      expect(result.failureReason, contains('deleted or completed'));
      expect((await ledger.read()).map((e) => e.todoistId), ['new-2']);

      // A plain retry leaves it alone.
      final retried = await sync.retryPending();
      expect(retried.createdCount, 0);
      expect(client.created, hasLength(2));
      expect((await retry.read()).single.items, hasLength(1));

      // Recreate makes a fresh task and clears the notice.
      final recreated = await sync.recreateMissing();
      expect(recreated.createdCount, 1);
      expect(client.created.last.content, 'Call dentist today');
      expect(await retry.read(), isEmpty);
      final entries = await ledger.read();
      expect(entries.map((e) => e.content), ['Pay rent', 'Call dentist today']);
      expect(entries.last.pageId, 'p2');
    });

    test('a failed update (not a 404) is retried as an update', () async {
      await sync.execute(_plan(['Call dentist']), pageId: 'p1');
      final plan = await sync.linkPlan(
        _plan(['Call dentist today']),
        pageId: 'p2',
      );
      client.updateNotFound.clear();
      final broken = ScriptedTodoistClient()..created.addAll(client.created);
      final failing = DailyTodoistSync(
        client: _FailingUpdateClient(broken),
        unmatchedStore: unmatched,
        retryStore: retry,
        ledgerStore: ledger,
      );
      final first = await failing.execute(plan, pageId: 'p2');
      expect(first.failed.single.kind, FailedItemKind.update);
      expect(first.failed.single.remoteMissing, isFalse);

      final retried = await sync.retryPending();
      expect(retried.updatedCount, 1);
      expect(client.updates.single.id, 'new-1');
      expect(client.created, hasLength(1));
      expect(await retry.read(), isEmpty);
    });
  });

  group('done lines', () {
    test('resolve against the ledger first and mark the entry completed',
        () async {
      await sync.execute(_plan(['Call dentist', 'Pay rent']), pageId: 'p1');
      // A live task that would fuzzy-match "dentist" better must not win.
      client.open.addAll(const [
        TodoistTask(id: 'live-1', content: 'Call dentist'),
      ]);

      final result = await sync.execute(
        _plan([], done: ['Call dentist']),
        pageId: 'p2',
      );

      expect(client.closedIds, ['new-1']);
      expect(result.completedCount, 1);
      expect(client.listCalls, 0);
      final entries = await ledger.read();
      expect(entries.first.status, LedgerStatus.completed);
      expect(entries.first.completedAt, DateTime.utc(2026, 11, 27, 9));
      expect(entries.last.isOpen, isTrue);
    });

    test('falls back to the live fuzzy match when the ledger has no match',
        () async {
      await sync.execute(_plan(['Pay rent']), pageId: 'p1');
      client.open.add(const TodoistTask(id: 'live-9', content: 'Ship release'));

      final result = await sync.execute(
        _plan([], done: ['Ship release']),
        pageId: 'p2',
      );

      expect(client.closedIds, ['live-9']);
      expect(result.completedCount, 1);
      expect(client.listCalls, 1);
      expect((await ledger.read()).single.isOpen, isTrue);
    });

    test('a ledger task already gone (404) falls through to the live match',
        () async {
      await sync.execute(_plan(['Pay rent']), pageId: 'p1');
      client.closeNotFound.add('new-1');
      client.open.add(const TodoistTask(id: 'live-2', content: 'Pay rent'));

      final result = await sync.execute(
        _plan([], done: ['Pay rent']),
        pageId: 'p2',
      );

      expect(client.closedIds, ['live-2']);
      expect(result.completedCount, 1);
      expect(result.hasFailures, isFalse);
      expect(await ledger.read(), isEmpty);
    });

    test('unmatched done lines are still recorded', () async {
      final result = await sync.execute(
        _plan([], done: ['Nothing like it']),
        pageId: 'p2',
      );
      expect(result.unmatchedDone, ['Nothing like it']);
      expect((await unmatched.read()).single.content, 'Nothing like it');
    });

    test('a done line prefers an entry from its own page', () async {
      await sync.execute(_plan(['Pay rent']), pageId: 'p1');
      await sync.execute(_plan(['Pay rent']), pageId: 'p2');
      await sync.execute(_plan([], done: ['Pay rent']), pageId: 'p2');
      expect(client.closedIds, ['new-2']);
    });
  });

  group('idempotent creates', () {
    test('every create carries its own X-Request-Id', () async {
      await sync.execute(_plan(['A task', 'B task']), pageId: 'p1');
      expect(client.requestIds, hasLength(2));
      expect(client.requestIds.every((r) => r != null && r.isNotEmpty), isTrue);
      expect(client.requestIds.toSet(), hasLength(2));
    });

    test('a retry after a lost response reuses the id: no duplicate task',
        () async {
      client.createThenTimeout.add('A task');

      final first = await sync.execute(_plan(['A task']), pageId: 'p1');
      expect(first.failed.single.error, contains('connection'));
      expect(client.created, hasLength(1));
      expect(await ledger.read(), isEmpty);

      final retried = await sync.retryPending();

      expect(retried.createdCount, 1);
      expect(client.created, hasLength(1));
      expect(client.requestIds.toSet(), hasLength(1));
      final entries = await ledger.read();
      expect(entries.single.todoistId, 'new-1');
      expect(entries.single.pageId, 'p1');
      expect(await retry.read(), isEmpty);
    });

    test('request id survives the retry store round trip', () async {
      client.createErrors['A task'] =
          TodoistApiException('Todoist error 500', statusCode: 500);
      await sync.execute(_plan(['A task']), pageId: 'p1');
      final stored = (await retry.read()).single.items.single;
      expect(stored.requestId, client.requestIds.single);
      final back = FailedTodoistItem.fromJson(stored.toJson());
      expect(back.requestId, stored.requestId);
      expect(back.toCreate().requestId, stored.requestId);
    });
  });
}

class _ThrowingLedger extends MemoryTodoistLedgerStore {
  @override
  Future<void> upsert(LedgerEntry entry) async => throw StateError('disk full');
}

class _FailingUpdateClient extends ScriptedTodoistClient {
  _FailingUpdateClient(ScriptedTodoistClient other) : super() {
    created.addAll(other.created);
  }

  @override
  Future<TodoistTask> updateTask(
    String taskId, {
    String? content,
    int? priority,
    String? description,
  }) async {
    throw TodoistApiException('Todoist error 500', statusCode: 500);
  }
}
