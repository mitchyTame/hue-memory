import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/todoist/daily_todoist_parser.dart';
import 'package:hue_memory/todoist/daily_todoist_plan.dart';
import 'package:hue_memory/todoist/daily_todoist_sync.dart';
import 'package:hue_memory/todoist/todoist_client.dart';
import 'package:hue_memory/todoist/todoist_retry.dart';
import 'package:hue_memory/todoist/unmatched_done_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_todoist_client.dart';

DailyTodoistPlan _plan() {
  return DailyTodoistPlan.fromParse(
    const DailyTodoistParseResult(
      creates: [
        DailyTodoistCreate(content: 'Plan trip', label: 'home', nodeId: 'a'),
        DailyTodoistCreate(
          content: 'Book flights',
          label: 'home',
          nodeId: 'b',
          parentNodeId: 'a',
        ),
        DailyTodoistCreate(content: 'Buy milk', label: 'shopping', nodeId: 'd'),
        DailyTodoistCreate(content: 'Pay rent', label: 'home', nodeId: 'e'),
      ],
      done: ['Ship release'],
      sectionLabels: ['home', 'shopping'],
    ),
  );
}

void main() {
  late ScriptedTodoistClient client;
  late MemoryTodoistRetryStore retry;
  late MemoryUnmatchedDoneStore unmatched;
  late DailyTodoistSync sync;

  setUp(() {
    client = ScriptedTodoistClient(
      openTasks: const [TodoistTask(id: 'old-1', content: 'Ship release')],
    );
    retry = MemoryTodoistRetryStore();
    unmatched = MemoryUnmatchedDoneStore();
    sync = DailyTodoistSync(
      client: client,
      unmatchedStore: unmatched,
      retryStore: retry,
      clock: () => DateTime.utc(2026, 11, 27, 9),
    );
  });

  test('planning sends nothing; execute sends only what is included', () async {
    final plan = _plan()
        .setTaskIncluded(2, false)
        .setTaskContent(3, 'Pay rent today')
        .setTaskPriority(3, 4);
    expect(client.created, isEmpty);

    final result = await sync.execute(plan);

    expect(result.createdCount, 3);
    expect(result.completedCount, 1);
    expect(result.hasFailures, isFalse);
    expect(client.created.map((t) => t.content), [
      'Plan trip',
      'Book flights',
      'Pay rent today',
    ]);
    expect(client.parentIds['new-2'], 'new-1');
    expect(client.priorities['new-3'], 4);
    expect(client.closedIds, ['old-1']);
    expect(await retry.read(), isEmpty);
  });

  test('skipped everything sends nothing', () async {
    var plan = _plan();
    for (var i = 0; i < plan.creates.length; i++) {
      plan = plan.setTaskIncluded(i, false);
    }
    plan = plan.setDoneIncluded(0, false);
    final result = await sync.execute(plan);
    expect(result.createdCount, 0);
    expect(client.created, isEmpty);
    expect(client.closedIds, isEmpty);
  });

  test('one failed item does not stop the rest; failures are kept', () async {
    client.createErrors['Buy milk'] =
        TodoistApiException('Todoist error 400: bad', statusCode: 400);

    final result = await sync.execute(_plan());

    expect(result.createdCount, 3);
    expect(result.completedCount, 1);
    expect(result.failed.map((f) => f.content), ['Buy milk']);
    expect(result.failureReason, 'Todoist error 400: bad');
    expect(result.snackbarMessage, contains('1 item did not send'));
    expect(client.created.map((t) => t.content), [
      'Plan trip',
      'Book flights',
      'Pay rent',
    ]);
    final stored = await retry.read();
    expect(stored.single.items.single.content, 'Buy milk');
    expect(stored.single.todoistIdByNode['a'], 'new-1');
  });

  test('a failed parent fails its subtask without hitting the API', () async {
    client.createErrors['Plan trip'] =
        TodoistApiException('Todoist error 400', statusCode: 400);

    final result = await sync.execute(_plan());

    expect(result.failed.map((f) => f.content), ['Plan trip', 'Book flights']);
    expect(result.failed.last.error, contains("parent task didn't send"));
    expect(client.created.map((t) => t.content), ['Buy milk', 'Pay rent']);
  });

  test('rejected token aborts the remaining items as failed', () async {
    client.createErrors['Book flights'] =
        TodoistApiException('Todoist token rejected (401)', statusCode: 401);

    final result = await sync.execute(_plan());

    expect(result.createdCount, 1);
    expect(result.failed.map((f) => f.content), [
      'Book flights',
      'Buy milk',
      'Pay rent',
      'Ship release',
    ]);
    expect(result.failed.map((f) => f.error).toSet(), {
      'Todoist token rejected (401)',
    });
    expect(client.closedIds, isEmpty);
  });

  test('offline errors read as a connection problem', () async {
    client.createErrors['Plan trip'] = const SocketException('no route');

    final result = await sync.execute(_plan());

    expect(result.createdCount, 0);
    expect(result.failureReason, contains('check your connection'));
    expect(result.failed, hasLength(5));
  });

  test('label failure keeps every item for retry', () async {
    client.labelError = TodoistApiException('Todoist error 500', statusCode: 500);

    final result = await sync.execute(_plan());

    expect(result.createdCount, 0);
    expect(result.failed, hasLength(5));
    expect((await retry.read()).single.items, hasLength(5));
  });

  test('done lines fail individually without losing created tasks', () async {
    client.closeErrors.add('old-1');

    final result = await sync.execute(_plan());

    expect(result.createdCount, 4);
    expect(result.completedCount, 0);
    expect(result.failed.single.kind, FailedItemKind.done);
    expect(result.failed.single.content, 'Ship release');
  });

  test('retryPending sends only failed items and attaches to old parents',
      () async {
    client.createErrors['Book flights'] =
        TodoistApiException('Todoist error 503', statusCode: 503);
    client.createErrors['Pay rent'] =
        TodoistApiException('Todoist error 503', statusCode: 503);
    await sync.execute(_plan());
    expect(client.created.map((t) => t.content), ['Plan trip', 'Buy milk']);

    client.createErrors.remove('Book flights');
    final result = await sync.retryPending();

    expect(result.createdCount, 1);
    expect(result.failed.map((f) => f.content), ['Pay rent']);
    // Subtask lands under the parent created in the first attempt.
    final flights = client.created.firstWhere((t) => t.content == 'Book flights');
    expect(client.parentIds[flights.id], 'new-1');
    // Nothing that already went through is created twice.
    expect(
      client.created.where((t) => t.content == 'Plan trip'),
      hasLength(1),
    );
    expect(client.closedIds, ['old-1']);

    client.createErrors.clear();
    final again = await sync.retryPending();
    expect(again.createdCount, 1);
    expect(again.hasFailures, isFalse);
    expect(await retry.read(), isEmpty);
    expect(
      client.created.where((t) => t.content == 'Pay rent'),
      hasLength(1),
    );
  });

  test('retryPending with nothing stored is a no-op', () async {
    final result = await sync.retryPending();
    expect(result.createdCount, 0);
    expect(client.created, isEmpty);
  });

  test('retry batches survive a prefs round trip', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsTodoistRetryStore();
    final batch = TodoistRetryBatch(
      createdAt: DateTime.utc(2026, 11, 27, 9),
      items: [
        FailedTodoistItem.forCreate(
          DailyTodoistCreate(
            content: 'Book flights',
            label: 'home',
            priority: 3,
            nodeId: 'b',
            parentNodeId: 'a',
            dueDate: DateTime(2026, 11, 28),
          ),
          'Todoist error 503',
        ),
        FailedTodoistItem.forDone('Ship release', 'No connection'),
      ],
      todoistIdByNode: const {'a': 'new-1'},
    );
    await store.add(batch);

    final loaded = (await PrefsTodoistRetryStore().read()).single;
    expect(loaded.todoistIdByNode, {'a': 'new-1'});
    final create = loaded.items.first.toCreate();
    expect(create.content, 'Book flights');
    expect(create.priority, 3);
    expect(create.parentNodeId, 'a');
    expect(create.dueDate, DateTime(2026, 11, 28));
    expect(loaded.items.last.kind, FailedItemKind.done);

    await store.clear();
    expect(await store.read(), isEmpty);
  });
}
