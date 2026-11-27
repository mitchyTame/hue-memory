import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum LedgerStatus { open, completed }

/// One Todoist task this app created from a paper page.
///
/// The ledger is how a later capture finds "the task I made earlier": done
/// lines close it by ID, and a re-captured page updates it instead of
/// creating a duplicate.
class LedgerEntry {
  const LedgerEntry({
    required this.todoistId,
    required this.content,
    required this.createdAt,
    this.label = '',
    this.priority,
    this.pageId,
    this.pageDay,
    this.nodeId,
    this.due,
    this.status = LedgerStatus.open,
    this.completedAt,
  });

  final String todoistId;

  /// Text as last sent to Todoist.
  final String content;
  final String label;

  /// Todoist API priority as last sent (4 = urgent, null = none).
  final int? priority;

  /// Capture page ID the task last came from.
  final String? pageId;

  /// `YYYY-MM-DD` the page was for (its hub date, else the capture day).
  /// A completed task is only recognised again on a page for the same day,
  /// so a task written daily is not taken as already done.
  final String? pageDay;
  final String? nodeId;

  /// Due as last sent (`YYYY-MM-DD` or `YYYY-MM-DDTHH:MM`), null for none.
  final String? due;
  final DateTime createdAt;
  final LedgerStatus status;
  final DateTime? completedAt;

  bool get isOpen => status == LedgerStatus.open;

  LedgerEntry copyWith({
    String? content,
    int? priority,
    bool clearPriority = false,
    String? pageId,
    String? pageDay,
    String? due,
    LedgerStatus? status,
    DateTime? completedAt,
  }) {
    return LedgerEntry(
      todoistId: todoistId,
      content: content ?? this.content,
      createdAt: createdAt,
      label: label,
      priority: clearPriority ? null : (priority ?? this.priority),
      pageId: pageId ?? this.pageId,
      pageDay: pageDay ?? this.pageDay,
      nodeId: nodeId,
      due: due ?? this.due,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': todoistId,
        'content': content,
        'label': label,
        'priority': ?priority,
        'pageId': ?pageId,
        'pageDay': ?pageDay,
        'nodeId': ?nodeId,
        'due': ?due,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      };

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    return LedgerEntry(
      todoistId: '${json['id'] ?? ''}',
      content: '${json['content'] ?? ''}',
      label: '${json['label'] ?? ''}',
      priority: json['priority'] is int ? json['priority'] as int : null,
      pageId: json['pageId'] as String?,
      pageDay: json['pageDay'] as String?,
      nodeId: json['nodeId'] as String?,
      due: json['due'] as String?,
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      status: json['status'] == 'completed'
          ? LedgerStatus.completed
          : LedgerStatus.open,
      completedAt: DateTime.tryParse('${json['completedAt'] ?? ''}'),
    );
  }
}

/// Local record of created Todoist tasks (mirrors [UnmatchedDoneStore]).
abstract interface class TodoistLedgerStore {
  Future<List<LedgerEntry>> read();
  Future<void> write(List<LedgerEntry> entries);

  /// Insert, or replace the entry with the same Todoist ID. Persists at once.
  Future<void> upsert(LedgerEntry entry);
  Future<void> markCompleted(String todoistId, DateTime at);
  Future<void> remove(String todoistId);
  Future<void> clear();
}

/// Keeps the ledger bounded: oldest completed entries go first.
List<LedgerEntry> pruneLedger(List<LedgerEntry> entries, {int max = 1000}) {
  if (entries.length <= max) return entries;
  var excess = entries.length - max;
  final drop = <int>{};
  for (var i = 0; i < entries.length && excess > 0; i++) {
    if (!entries[i].isOpen) {
      drop.add(i);
      excess--;
    }
  }
  for (var i = 0; i < entries.length && excess > 0; i++) {
    if (drop.add(i)) excess--;
  }
  return [
    for (var i = 0; i < entries.length; i++)
      if (!drop.contains(i)) entries[i],
  ];
}

List<LedgerEntry> _upserted(List<LedgerEntry> current, LedgerEntry entry) {
  final i = current.indexWhere((e) => e.todoistId == entry.todoistId);
  if (i == -1) return [...current, entry];
  return [...current]..[i] = entry;
}

List<LedgerEntry> _completed(
  List<LedgerEntry> current,
  String id,
  DateTime at,
) {
  return [
    for (final e in current)
      e.todoistId == id
          ? e.copyWith(status: LedgerStatus.completed, completedAt: at)
          : e,
  ];
}

class PrefsTodoistLedgerStore implements TodoistLedgerStore {
  PrefsTodoistLedgerStore({SharedPreferences? prefs}) : _prefs = prefs;

  static const keyEntries = 'todoist_task_ledger';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<List<LedgerEntry>> read() async {
    final prefs = await _ensure();
    final raw = prefs.getString(keyEntries);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in list) LedgerEntry.fromJson(e as Map<String, dynamic>),
      ].where((e) => e.todoistId.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> write(List<LedgerEntry> entries) async {
    final prefs = await _ensure();
    final keep = pruneLedger(entries);
    if (keep.isEmpty) {
      await prefs.remove(keyEntries);
      return;
    }
    await prefs.setString(
      keyEntries,
      jsonEncode([for (final e in keep) e.toJson()]),
    );
  }

  @override
  Future<void> upsert(LedgerEntry entry) async {
    await write(_upserted(await read(), entry));
  }

  @override
  Future<void> markCompleted(String todoistId, DateTime at) async {
    await write(_completed(await read(), todoistId, at));
  }

  @override
  Future<void> remove(String todoistId) async {
    final current = await read();
    await write([
      for (final e in current)
        if (e.todoistId != todoistId) e,
    ]);
  }

  @override
  Future<void> clear() async {
    final prefs = await _ensure();
    await prefs.remove(keyEntries);
  }
}

class MemoryTodoistLedgerStore implements TodoistLedgerStore {
  MemoryTodoistLedgerStore([List<LedgerEntry>? seed])
      : _entries = List<LedgerEntry>.from(seed ?? const []);

  List<LedgerEntry> _entries;

  @override
  Future<List<LedgerEntry>> read() async => List.unmodifiable(_entries);

  @override
  Future<void> write(List<LedgerEntry> entries) async {
    _entries = pruneLedger(List<LedgerEntry>.from(entries));
  }

  @override
  Future<void> upsert(LedgerEntry entry) async {
    _entries = _upserted(_entries, entry);
  }

  @override
  Future<void> markCompleted(String todoistId, DateTime at) async {
    _entries = _completed(_entries, todoistId, at);
  }

  @override
  Future<void> remove(String todoistId) async {
    _entries = [
      for (final e in _entries)
        if (e.todoistId != todoistId) e,
    ];
  }

  @override
  Future<void> clear() async {
    _entries = [];
  }
}
