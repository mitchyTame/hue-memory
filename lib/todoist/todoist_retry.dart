import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'daily_todoist_parser.dart';

enum FailedItemKind { create, update, done }

/// One planned Todoist item that did not go through (kept for retry).
///
/// [FailedItemKind.update] is a re-capture update of an earlier task; when
/// that task is gone from Todoist ([remoteMissing]) it waits for the user to
/// choose to recreate it.
class FailedTodoistItem {
  const FailedTodoistItem({
    required this.kind,
    required this.content,
    required this.error,
    this.label = '',
    this.priority,
    this.nodeId,
    this.parentNodeId,
    this.dueDate,
    this.dueHasTime = false,
    this.dueString,
    this.duePhrase,
    this.reopen = false,
    this.extraParentNodeIds = const [],
    this.requestId,
    this.updateTodoistId,
    this.previousContent,
    this.previousPriority,
    this.previousDue,
    this.remoteMissing = false,
  });

  factory FailedTodoistItem.forCreate(
    DailyTodoistCreate create,
    String error,
  ) {
    return FailedTodoistItem._from(FailedItemKind.create, create, error);
  }

  factory FailedTodoistItem.forUpdate(
    DailyTodoistCreate create,
    String error, {
    bool remoteMissing = false,
  }) {
    return FailedTodoistItem._from(
      FailedItemKind.update,
      create,
      error,
      remoteMissing: remoteMissing,
    );
  }

  factory FailedTodoistItem._from(
    FailedItemKind kind,
    DailyTodoistCreate create,
    String error, {
    bool remoteMissing = false,
  }) {
    return FailedTodoistItem(
      kind: kind,
      content: create.content,
      error: error,
      label: create.label,
      priority: create.priority,
      nodeId: create.nodeId,
      parentNodeId: create.parentNodeId,
      dueDate: create.dueDate,
      dueHasTime: create.dueHasTime,
      dueString: create.dueString,
      duePhrase: create.duePhrase,
      reopen: create.reopen,
      extraParentNodeIds: create.extraParentNodeIds,
      requestId: create.requestId,
      updateTodoistId: create.updateTodoistId,
      previousContent: create.previousContent,
      previousPriority: create.previousPriority,
      previousDue: create.previousDue,
      remoteMissing: remoteMissing,
    );
  }

  /// [todoistId]: the task the review linked this done line to.
  factory FailedTodoistItem.forDone(
    String content,
    String error, {
    String? todoistId,
  }) {
    return FailedTodoistItem(
      kind: FailedItemKind.done,
      content: content,
      error: error,
      updateTodoistId: todoistId,
    );
  }

  final FailedItemKind kind;
  final String content;
  final String error;
  final String label;
  final int? priority;
  final String? nodeId;
  final String? parentNodeId;
  final DateTime? dueDate;
  final bool dueHasTime;
  final String? dueString;
  final String? duePhrase;
  final bool reopen;
  final List<String> extraParentNodeIds;
  final String? requestId;
  final String? updateTodoistId;
  final String? previousContent;
  final int? previousPriority;
  final String? previousDue;

  /// The task this item would update no longer exists in Todoist.
  final bool remoteMissing;

  /// Back into a send item. [recreate] turns a failed update into a brand-new
  /// task (fresh request ID, no link to the missing one).
  DailyTodoistCreate toCreate({bool recreate = false}) {
    final create = DailyTodoistCreate(
      content: content,
      label: label,
      priority: priority,
      nodeId: nodeId,
      parentNodeId: parentNodeId,
      dueDate: dueDate,
      dueHasTime: dueHasTime,
      dueString: dueString,
      duePhrase: duePhrase,
      reopen: reopen,
      extraParentNodeIds: extraParentNodeIds,
      requestId: requestId,
      updateTodoistId: updateTodoistId,
      previousContent: previousContent,
      previousPriority: previousPriority,
      previousDue: previousDue,
    );
    return recreate ? create.copyWith(clearUpdate: true) : create;
  }

  FailedTodoistItem withError(String next) {
    return FailedTodoistItem(
      kind: kind,
      content: content,
      error: next,
      label: label,
      priority: priority,
      nodeId: nodeId,
      parentNodeId: parentNodeId,
      dueDate: dueDate,
      dueHasTime: dueHasTime,
      dueString: dueString,
      duePhrase: duePhrase,
      reopen: reopen,
      extraParentNodeIds: extraParentNodeIds,
      requestId: requestId,
      updateTodoistId: updateTodoistId,
      previousContent: previousContent,
      previousPriority: previousPriority,
      previousDue: previousDue,
      remoteMissing: remoteMissing,
    );
  }

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'content': content,
        'error': error,
        'label': label,
        'priority': ?priority,
        'nodeId': ?nodeId,
        'parentNodeId': ?parentNodeId,
        if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
        if (dueHasTime) 'dueTime': true,
        'dueString': ?dueString,
        'duePhrase': ?duePhrase,
        if (reopen) 'reopen': true,
        if (extraParentNodeIds.isNotEmpty) 'extra': extraParentNodeIds,
        'requestId': ?requestId,
        'updateId': ?updateTodoistId,
        'prevContent': ?previousContent,
        'prevPriority': ?previousPriority,
        'prevDue': ?previousDue,
        if (remoteMissing) 'missing': true,
      };

  factory FailedTodoistItem.fromJson(Map<String, dynamic> json) {
    final extra = json['extra'];
    return FailedTodoistItem(
      kind: switch (json['kind']) {
        'done' => FailedItemKind.done,
        'update' => FailedItemKind.update,
        _ => FailedItemKind.create,
      },
      content: '${json['content'] ?? ''}',
      error: '${json['error'] ?? ''}',
      label: '${json['label'] ?? ''}',
      priority: json['priority'] is int ? json['priority'] as int : null,
      nodeId: json['nodeId'] as String?,
      parentNodeId: json['parentNodeId'] as String?,
      dueDate: DateTime.tryParse('${json['dueDate'] ?? ''}'),
      dueHasTime: json['dueTime'] == true,
      dueString: json['dueString'] as String?,
      duePhrase: json['duePhrase'] as String?,
      reopen: json['reopen'] == true,
      extraParentNodeIds: extra is List ? [for (final e in extra) '$e'] : const [],
      requestId: json['requestId'] as String?,
      updateTodoistId: json['updateId'] as String?,
      previousContent: json['prevContent'] as String?,
      previousPriority:
          json['prevPriority'] is int ? json['prevPriority'] as int : null,
      previousDue: json['prevDue'] as String?,
      remoteMissing: json['missing'] == true,
    );
  }
}

/// Failures from one send, plus the Todoist IDs of what *did* go through
/// (so a retried subtask can still attach to its already-created parent).
class TodoistRetryBatch {
  const TodoistRetryBatch({
    required this.createdAt,
    required this.items,
    this.todoistIdByNode = const {},
    this.pageId,
  });

  final DateTime createdAt;
  final List<FailedTodoistItem> items;
  final Map<String, String> todoistIdByNode;

  /// Capture page the items came from (recorded in the ledger on retry).
  final String? pageId;

  Map<String, Object?> toJson() => {
        'createdAt': createdAt.toIso8601String(),
        'items': [for (final i in items) i.toJson()],
        'ids': todoistIdByNode,
        'pageId': ?pageId,
      };

  factory TodoistRetryBatch.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawIds = json['ids'];
    return TodoistRetryBatch(
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      items: rawItems is List
          ? [
              for (final e in rawItems)
                FailedTodoistItem.fromJson(e as Map<String, dynamic>),
            ]
          : const [],
      todoistIdByNode: rawIds is Map
          ? {for (final e in rawIds.entries) '${e.key}': '${e.value}'}
          : const {},
      pageId: json['pageId'] as String?,
    );
  }
}

/// Failed Todoist sends waiting for "retry failed".
abstract interface class TodoistRetryStore {
  Future<List<TodoistRetryBatch>> read();
  Future<void> write(List<TodoistRetryBatch> batches);
  Future<void> add(TodoistRetryBatch batch);
  Future<void> clear();
}

class PrefsTodoistRetryStore implements TodoistRetryStore {
  PrefsTodoistRetryStore({SharedPreferences? prefs}) : _prefs = prefs;

  static const keyBatches = 'todoist_retry_batches';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<List<TodoistRetryBatch>> read() async {
    final prefs = await _ensure();
    final raw = prefs.getString(keyBatches);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in list)
          TodoistRetryBatch.fromJson(e as Map<String, dynamic>),
      ].where((b) => b.items.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> write(List<TodoistRetryBatch> batches) async {
    final prefs = await _ensure();
    final keep = batches.where((b) => b.items.isNotEmpty).toList();
    if (keep.isEmpty) {
      await prefs.remove(keyBatches);
      return;
    }
    await prefs.setString(
      keyBatches,
      jsonEncode([for (final b in keep) b.toJson()]),
    );
  }

  @override
  Future<void> add(TodoistRetryBatch batch) async {
    final current = await read();
    await write([...current, batch]);
  }

  @override
  Future<void> clear() async {
    final prefs = await _ensure();
    await prefs.remove(keyBatches);
  }
}

class MemoryTodoistRetryStore implements TodoistRetryStore {
  MemoryTodoistRetryStore([List<TodoistRetryBatch>? seed])
      : _batches = List<TodoistRetryBatch>.from(seed ?? const []);

  List<TodoistRetryBatch> _batches;

  @override
  Future<List<TodoistRetryBatch>> read() async => List.unmodifiable(_batches);

  @override
  Future<void> write(List<TodoistRetryBatch> batches) async {
    _batches = batches.where((b) => b.items.isNotEmpty).toList();
  }

  @override
  Future<void> add(TodoistRetryBatch batch) async {
    _batches = [..._batches, batch];
  }

  @override
  Future<void> clear() async {
    _batches = [];
  }
}
