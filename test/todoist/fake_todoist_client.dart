import 'package:http/http.dart' as http;
import 'package:hue_memory/todoist/todoist_client.dart';

/// In-memory Todoist client that can be told to fail specific calls.
class ScriptedTodoistClient extends TodoistClient {
  ScriptedTodoistClient({List<TodoistTask> openTasks = const []})
      : open = List<TodoistTask>.from(openTasks),
        super(apiToken: 'test-token', httpClient: _UnusedHttp());

  final List<TodoistTask> open;
  final List<TodoistTask> created = [];
  final Map<String, String?> parentIds = {};
  final Map<String, int?> priorities = {};
  final List<String> closedIds = [];

  /// Task content → error thrown by [createInboxTask] while set.
  final Map<String, Object> createErrors = {};
  Object? listError;
  Object? labelError;
  final Set<String> closeErrors = {};

  @override
  Future<Map<String, TodoistLabel>> ensureLabels(Iterable<String> names) async {
    if (labelError != null) throw labelError!;
    return {for (final n in names) n: TodoistLabel(id: 'id-$n', name: n)};
  }

  @override
  Future<List<TodoistTask>> listOpenTasks() async {
    if (listError != null) throw listError!;
    return List.unmodifiable(open);
  }

  @override
  Future<TodoistTask> createInboxTask({
    required String content,
    List<String> labels = const [],
    int? priority,
    String? parentId,
    DateTime? dueDate,
    String? description,
  }) async {
    final error = createErrors[content];
    if (error != null) throw error;
    final task = TodoistTask(
      id: 'new-${created.length + 1}',
      content: content,
      labels: labels,
    );
    created.add(task);
    parentIds[task.id] = parentId;
    priorities[task.id] = priority;
    return task;
  }

  @override
  Future<TodoistTask> updateTask(String taskId, {String? description}) async {
    return created.firstWhere((t) => t.id == taskId);
  }

  @override
  Future<void> closeTask(String taskId) async {
    if (closeErrors.contains(taskId)) {
      throw TodoistApiException('Todoist error 500', statusCode: 500);
    }
    closedIds.add(taskId);
    open.removeWhere((t) => t.id == taskId);
  }
}

class _UnusedHttp extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw StateError('Fake Todoist client must not hit the network');
  }
}
