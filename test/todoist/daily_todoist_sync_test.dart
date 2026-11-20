import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hue_memory/todoist/daily_todoist_sync.dart';
import 'package:hue_memory/todoist/todoist_client.dart';
import 'package:hue_memory/todoist/unmatched_done_store.dart';

void main() {
  group('findMatchingOpenTask', () {
    test('matches exact normalized content', () {
      final open = [
        const TodoistTask(id: '1', content: 'Ship release'),
        const TodoistTask(id: '2', content: 'Other'),
      ];
      final match = DailyTodoistSync.findMatchingOpenTask(open, 'Ship release');
      expect(match?.id, '1');
    });

    test('returns null when no open task matches (failure path)', () {
      final open = [
        const TodoistTask(id: '1', content: 'Ship release'),
      ];
      final match =
          DailyTodoistSync.findMatchingOpenTask(open, 'Totally unknown');
      expect(match, isNull);
    });
  });

  test('sync records unmatched done items and creates labeled tasks', () async {
    final client = _FakeTodoistClient(
      openTasks: [
        const TodoistTask(id: '10', content: 'Ship release'),
      ],
    );
    final unmatched = MemoryUnmatchedDoneStore();
    final sync = DailyTodoistSync(
      client: client,
      unmatchedStore: unmatched,
      clock: () => DateTime.utc(2026, 11, 20, 12),
    );

    final result = await sync.syncMarkdown('''
high:
- Call dentist
done:
- Ship release
- Mystery paper task
''');

    expect(result.createdCount, 1);
    expect(result.completedCount, 1);
    expect(result.unmatchedDone, ['Mystery paper task']);
    expect(result.hasUnmatched, isTrue);
    expect(client.created.single.content, 'Call dentist');
    expect(client.created.single.labels, ['high']);
    expect(client.closedIds, ['10']);
    expect(client.ensuredLabels, contains('high'));

    final stored = await unmatched.read();
    expect(stored, hasLength(1));
    expect(stored.single.content, 'Mystery paper task');
    expect(result.snackbarMessage, contains('done item not found'));
  });
}

class _FakeTodoistClient extends TodoistClient {
  _FakeTodoistClient({List<TodoistTask> openTasks = const []})
      : _open = List<TodoistTask>.from(openTasks),
        super(apiToken: 'test-token', httpClient: _UnusedHttp());

  final List<TodoistTask> _open;
  final List<TodoistTask> created = [];
  final List<String> closedIds = [];
  final List<String> ensuredLabels = [];

  @override
  Future<Map<String, String>> ensureLabels(Iterable<String> names) async {
    ensuredLabels.addAll(names);
    return {for (final n in names) n: 'id-$n'};
  }

  @override
  Future<List<TodoistTask>> listOpenTasks() async => List.unmodifiable(_open);

  @override
  Future<TodoistTask> createInboxTask({
    required String content,
    List<String> labels = const [],
    int? priority,
  }) async {
    final task = TodoistTask(
      id: 'new-${created.length + 1}',
      content: content,
      labels: labels,
    );
    created.add(task);
    return task;
  }

  @override
  Future<void> closeTask(String taskId) async {
    closedIds.add(taskId);
    _open.removeWhere((t) => t.id == taskId);
  }
}

class _UnusedHttp extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw StateError('Fake Todoist client must not hit the network');
  }
}
