import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/todoist/daily_todoist_plan.dart';
import 'package:hue_memory/todoist/daily_todoist_sync.dart';
import 'package:hue_memory/todoist/todoist_client.dart';
import 'package:hue_memory/todoist/todoist_ledger.dart';
import 'package:hue_memory/todoist/todoist_retry.dart';
import 'package:hue_memory/todoist/unmatched_done_store.dart';

import 'fake_todoist_client.dart';

/// Before the review is shown, matched tasks are checked against Todoist so
/// a ticked or struck item closes the right task, and an item already
/// completed or deleted in Todoist shows that instead of being sent again.
void main() {
  late ScriptedTodoistClient client;
  late MemoryTodoistLedgerStore ledger;
  late MemoryTodoistRetryStore retry;
  late DailyTodoistSync sync;
  late MemoryUnmatchedDoneStore unmatched;

  setUp(() {
    client = ScriptedTodoistClient();
    ledger = MemoryTodoistLedgerStore();
    retry = MemoryTodoistRetryStore();
    unmatched = MemoryUnmatchedDoneStore();
    sync = DailyTodoistSync(
      client: client,
      unmatchedStore: unmatched,
      retryStore: retry,
      ledgerStore: ledger,
      clock: () => DateTime(2026, 11, 27, 9),
    );
  });

  DailyTodoistPlan page(String body) => sync.planner.plan(markdown: body);

  Future<DailyTodoistPlan> review(String body, {String pageId = 'p2'}) =>
      sync.linkPlan(page(body), pageId: pageId, includeLive: true);

  /// First capture of the page: three tasks created and in the ledger.
  Future<void> sendFirst() async {
    final r = await sync.execute(
      page('errands:\n- bolt | 16:50\n- Post office\n- Pharmacy\n'),
      pageId: 'p1',
    );
    expect(r.createdCount, 3);
  }

  test('a struck item with an open task will complete it — by its id',
      () async {
    await sendFirst();
    final plan = await review(
      'errands:\n- ~~bolt~~ | 16:50\n- Post office\n- Pharmacy\n',
    );
    final done = plan.done.single;
    expect(done.content, 'bolt | 16:50');
    expect(done.match?.todoistId, 'new-1');
    expect(done.match?.remote, RemoteState.open);
    expect(done.sendable, isTrue);
    expect(plan.completeCount, 1);

    final r = await sync.execute(plan, pageId: 'p2');
    expect(client.closedIds, ['new-1']);
    expect(r.completedCount, 1);
    expect(r.createdCount, 0);
    expect(client.created, hasLength(3));
    final entry = (await ledger.read()).firstWhere((e) => e.todoistId == 'new-1');
    expect(entry.status, LedgerStatus.completed);
  });

  test('a ticked item already completed in Todoist is shown, not sent',
      () async {
    await sendFirst();
    // Completed by hand in the Todoist app.
    client.completed['new-1'] =
        const TodoistTask(id: 'new-1', content: 'bolt', completed: true);
    final plan = await review(
      'errands:\n- ✓ bolt | 16:50\n- Post office\n- Pharmacy\n',
    );
    final done = plan.done.single;
    expect(done.match?.remote, RemoteState.completed);
    expect(done.alreadySettled, isTrue);
    expect(done.sendable, isFalse);
    expect(plan.completeCount, 0);

    await sync.execute(plan, pageId: 'p2');
    expect(client.closedIds, isEmpty);
    expect(await unmatched.read(), isEmpty);
  });

  test('a ticked item whose task was deleted is shown as gone, not sent',
      () async {
    await sendFirst();
    client.deletedIds.add('new-1');
    final plan = await review(
      'errands:\n- [x] bolt | 16:50\n- Post office\n- Pharmacy\n',
    );
    expect(plan.done.single.match?.remote, RemoteState.gone);
    expect(plan.done.single.sendable, isFalse);
    await sync.execute(plan, pageId: 'p2');
    expect(client.closedIds, isEmpty);
    expect(
      (await ledger.read()).map((e) => e.todoistId),
      isNot(contains('new-1')),
    );
  });

  test('an unticked item already completed in Todoist is shown, not recreated',
      () async {
    await sendFirst();
    client.completed['new-2'] =
        const TodoistTask(id: 'new-2', content: 'Post office', completed: true);
    final plan = await review(
      'errands:\n- bolt | 16:50\n- Post office\n- Pharmacy\n',
    );
    final post = plan.creates.firstWhere((t) => t.content == 'Post office');
    expect(post.match?.todoistId, 'new-2');
    expect(post.match?.remote, RemoteState.completed);
    expect(post.included, isFalse);

    final r = await sync.execute(plan, pageId: 'p2');
    expect(r.createdCount, 0);
    expect(client.created, hasLength(3));
    expect(client.reopenedIds, isEmpty);
  });

  test('…and choosing to send it reopens the same task instead', () async {
    await sendFirst();
    client.completed['new-2'] =
        const TodoistTask(id: 'new-2', content: 'Post office', completed: true);
    var plan = await review(
      'errands:\n- bolt | 16:50\n- Post office\n- Pharmacy\n',
    );
    final i = plan.creates.indexWhere((t) => t.content == 'Post office');
    plan = plan.setTaskIncluded(i, true);
    expect(plan.creates[i].reopens, isTrue);

    final r = await sync.execute(plan, pageId: 'p2');
    expect(client.reopenedIds, ['new-2']);
    expect(r.createdCount, 0);
    expect(client.created, hasLength(3));
    final entry = (await ledger.read()).firstWhere((e) => e.todoistId == 'new-2');
    expect(entry.status, LedgerStatus.open);
  });

  test('an item whose task was deleted is offered as new, off by default',
      () async {
    await sendFirst();
    client.deletedIds.add('new-3');
    var plan = await review(
      'errands:\n- bolt | 16:50\n- Post office\n- Pharmacy\n',
    );
    final i = plan.creates.indexWhere((t) => t.content == 'Pharmacy');
    expect(plan.creates[i].match?.remote, RemoteState.gone);
    expect(plan.creates[i].included, isFalse);
    expect(plan.creates[i].isUpdate, isFalse);

    plan = plan.setTaskIncluded(i, true);
    final r = await sync.execute(plan, pageId: 'p2');
    expect(r.createdCount, 1);
    expect(client.created.last.content, 'Pharmacy');
  });

  test('a struck item the ledger does not know closes the open Todoist task',
      () async {
    client.open.add(const TodoistTask(id: 'live-9', content: 'Pay rent'));
    final plan = await review('home:\n- ~~Pay rent~~\n- Buy milk\n');
    expect(plan.done.single.match?.todoistId, 'live-9');
    expect(plan.done.single.match?.fromLive, isTrue);
    await sync.execute(plan, pageId: 'p2');
    expect(client.closedIds, ['live-9']);
  });

  test('a struck item with no task anywhere is still listed as not found',
      () async {
    final plan = await review('home:\n- ~~Pay rent~~\n');
    expect(plan.done.single.match, isNull);
    expect(plan.done.single.sendable, isTrue);
    final r = await sync.execute(plan, pageId: 'p2');
    expect(r.unmatchedDone, ['Pay rent']);
  });

  test('a task written every day is not taken as already done from yesterday',
      () async {
    await ledger.upsert(
      LedgerEntry(
        todoistId: 'old-gym',
        content: 'Gym',
        createdAt: DateTime(2026, 11, 26),
        pageId: 'yesterday',
        pageDay: '2026-11-26',
        status: LedgerStatus.completed,
      ),
    );
    final plan = await review('health:\n- Gym\n');
    expect(plan.creates.single.match, isNull);
    expect(plan.creates.single.included, isTrue);
  });

  test('a done target deleted between review and send is not a failure',
      () async {
    await sendFirst();
    final plan = await review(
      'errands:\n- ~~bolt~~ | 16:50\n- Post office\n- Pharmacy\n',
    );
    client.closeNotFound.add('new-1');
    final r = await sync.execute(plan, pageId: 'p2');
    expect(r.failed, isEmpty);
    expect(r.completedCount, 0);
    expect(r.warnings.single, contains('already gone'));
  });

  test('a failed close keeps its target task id for retry', () async {
    await sendFirst();
    final plan = await review(
      'errands:\n- ~~bolt~~ | 16:50\n- Post office\n- Pharmacy\n',
    );
    client.closeErrors.add('new-1');
    final r = await sync.execute(plan, pageId: 'p2');
    expect(r.failed.single.kind, FailedItemKind.done);
    expect(r.failed.single.updateTodoistId, 'new-1');

    client.closeErrors.clear();
    final again = await sync.retryPending();
    expect(again.completedCount, 1);
    expect(client.closedIds, ['new-1']);
  });

  test('without a network the review still opens from the ledger', () async {
    await sendFirst();
    client.listError = Exception('offline');
    final plan = await review(
      'errands:\n- ~~bolt~~ | 16:50\n- Post office\n- Pharmacy\n',
    );
    expect(plan.remoteChecked, isFalse);
    expect(plan.done.single.match?.todoistId, 'new-1');
    expect(plan.done.single.match?.remote, RemoteState.unknown);
    expect(plan.done.single.sendable, isTrue);
  });

  test('the page day is recorded in the ledger', () async {
    await sendFirst();
    expect(
      (await ledger.read()).map((e) => e.pageDay).toSet(),
      {'2026-11-27'},
    );
  });
}
