import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hue_memory/todoist/daily_todoist_parser.dart';
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

  test('sync ensures dynamic section labels and creates Inbox tasks', () async {
    final client = _FakeTodoistClient();
    final sync = DailyTodoistSync(
      client: client,
      unmatchedStore: MemoryUnmatchedDoneStore(),
    );

    final result = await sync.syncMarkdown('''
Important:
- Call dentist
Weekend Plans:
- Hike
## Errands
- Milk
''');

    expect(result.createdCount, 3);
    expect(client.ensuredLabels.toSet(), containsAll(['high', 'weekend plans', 'errands']));
    expect(
      client.created.map((t) => '${t.labels.single}:${t.content}').toList(),
      [
        'high:Call dentist',
        'weekend plans:Hike',
        'errands:Milk',
      ],
    );
  });

  test('sync ensures labels for names with no tasks and reuses existing '
      'Todoist spelling on tasks', () async {
    final client = _FakeTodoistClient()..existingNames['deshan'] = 'Deshan';
    final sync = DailyTodoistSync(
      client: client,
      unmatchedStore: MemoryUnmatchedDoneStore(),
    );

    final result = await sync.syncParsed(
      const DailyTodoistParseResult(
        creates: [DailyTodoistCreate(content: 'Walk Sunday', label: 'deshan')],
        sectionLabels: ['deshan', 'thabo'],
      ),
    );

    expect(client.ensuredLabels.toSet(), {'deshan', 'thabo'});
    expect(client.created.single.labels, ['Deshan']);
    expect(result.labels, ['Deshan', 'thabo']);
    expect(result.snackbarMessage, '1 task → Todoist Inbox · 2 labels');
  });

  test('label-only page still syncs labels', () async {
    final client = _FakeTodoistClient();
    final sync = DailyTodoistSync(
      client: client,
      unmatchedStore: MemoryUnmatchedDoneStore(),
    );
    final result = await sync.syncParsed(
      const DailyTodoistParseResult(sectionLabels: ['thabo']),
    );
    expect(client.ensuredLabels, ['thabo']);
    expect(client.created, isEmpty);
    expect(result.snackbarMessage, '1 label');
  });

  test('sync creates subtasks with parent_id from mindmap links', () async {
    final client = _FakeTodoistClient();
    final sync = DailyTodoistSync(
      client: client,
      unmatchedStore: MemoryUnmatchedDoneStore(),
    );

    final result = await sync.syncParsed(
      const DailyTodoistParseResult(
        creates: [
          DailyTodoistCreate(
            content: 'Hue',
            label: 'high',
            priority: 4,
            nodeId: 'hue',
          ),
          DailyTodoistCreate(
            content: 'Wire subtasks',
            label: 'high',
            nodeId: 'a',
            parentNodeId: 'hue',
          ),
          DailyTodoistCreate(
            content: 'Shared',
            label: 'high',
            nodeId: 's',
            parentNodeId: 'hue',
            extraParentNodeIds: ['other'],
          ),
          DailyTodoistCreate(
            content: 'Other parent',
            label: 'high',
            nodeId: 'other',
          ),
        ],
      ),
    );

    expect(result.createdCount, 4);
    expect(client.parentIds['new-1'], isNull); // Hue root
    expect(client.parentIds['new-2'], 'new-1'); // sub under Hue
    expect(client.parentIds['new-3'], 'new-1');
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
  Future<Map<String, TodoistLabel>> ensureLabels(Iterable<String> names) async {
    ensuredLabels.addAll(names);
    return {
      for (final n in names)
        n: TodoistLabel(id: 'id-$n', name: existingNames[n] ?? n),
    };
  }

  /// Lowercase key → label as the user already spelled it in Todoist.
  final Map<String, String> existingNames = {};

  @override
  Future<List<TodoistTask>> listOpenTasks() async => List.unmodifiable(_open);

  @override
  Future<TodoistTask> createInboxTask({
    required String content,
    List<String> labels = const [],
    int? priority,
    String? parentId,
    DateTime? dueDate,
    String? description,
  }) async {
    final task = TodoistTask(
      id: 'new-${created.length + 1}',
      content: content,
      labels: labels,
    );
    created.add(task);
    parentIds[task.id] = parentId;
    return task;
  }

  final Map<String, String?> parentIds = {};

  @override
  Future<TodoistTask> updateTask(
    String taskId, {
    String? description,
  }) async {
    return created.firstWhere((t) => t.id == taskId);
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
