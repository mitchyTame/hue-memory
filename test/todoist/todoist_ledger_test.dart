import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/todoist/todoist_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

LedgerEntry _entry(
  String id, {
  String content = 'Call dentist',
  String? pageId = 'p1',
  LedgerStatus status = LedgerStatus.open,
}) {
  return LedgerEntry(
    todoistId: id,
    content: content,
    label: 'high',
    priority: 4,
    pageId: pageId,
    nodeId: 'n-$id',
    createdAt: DateTime.utc(2026, 11, 27, 8),
    status: status,
  );
}

void main() {
  test('entries round-trip through json', () {
    final e = _entry('t1').copyWith(
      status: LedgerStatus.completed,
      completedAt: DateTime.utc(2026, 11, 28),
    );
    final back = LedgerEntry.fromJson(e.toJson());
    expect(back.todoistId, 't1');
    expect(back.content, 'Call dentist');
    expect(back.priority, 4);
    expect(back.pageId, 'p1');
    expect(back.nodeId, 'n-t1');
    expect(back.status, LedgerStatus.completed);
    expect(back.completedAt, DateTime.utc(2026, 11, 28));
  });

  for (final kind in ['memory', 'prefs']) {
    group('$kind store', () {
      late TodoistLedgerStore store;

      setUp(() {
        SharedPreferences.setMockInitialValues({});
        store = kind == 'memory'
            ? MemoryTodoistLedgerStore()
            : PrefsTodoistLedgerStore();
      });

      test('upsert inserts, then replaces by Todoist id', () async {
        await store.upsert(_entry('t1'));
        await store.upsert(_entry('t2', content: 'Pay rent'));
        await store.upsert(_entry('t1', content: 'Call the dentist'));
        final all = await store.read();
        expect(all.map((e) => e.todoistId), ['t1', 't2']);
        expect(all.first.content, 'Call the dentist');
      });

      test('markCompleted keeps the entry, remove drops it', () async {
        await store.upsert(_entry('t1'));
        await store.upsert(_entry('t2'));
        await store.markCompleted('t1', DateTime.utc(2026, 11, 28));
        await store.remove('t2');
        final all = await store.read();
        expect(all.single.todoistId, 't1');
        expect(all.single.status, LedgerStatus.completed);
        expect(all.single.completedAt, DateTime.utc(2026, 11, 28));
      });

      test('clear empties it', () async {
        await store.upsert(_entry('t1'));
        await store.clear();
        expect(await store.read(), isEmpty);
      });
    });
  }

  test('prefs store survives a new instance (persisted)', () async {
    SharedPreferences.setMockInitialValues({});
    await PrefsTodoistLedgerStore().upsert(_entry('t1'));
    final again = await PrefsTodoistLedgerStore().read();
    expect(again.single.todoistId, 't1');
  });

  test('pruning drops the oldest completed entries first', () {
    final entries = [
      _entry('done-old', status: LedgerStatus.completed),
      _entry('open-old'),
      _entry('done-new', status: LedgerStatus.completed),
      _entry('open-new'),
    ];
    final kept = pruneLedger(entries, max: 3);
    expect(kept.map((e) => e.todoistId), ['open-old', 'done-new', 'open-new']);
    final tighter = pruneLedger(entries, max: 2);
    expect(tighter.map((e) => e.todoistId), ['open-old', 'open-new']);
  });
}
