import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A "done" line from paper that could not be matched to an open Todoist task.
class UnmatchedDoneItem {
  const UnmatchedDoneItem({
    required this.content,
    required this.recordedAt,
  });

  final String content;
  final DateTime recordedAt;

  Map<String, dynamic> toJson() => {
        'content': content,
        'recordedAt': recordedAt.toIso8601String(),
      };

  factory UnmatchedDoneItem.fromJson(Map<String, dynamic> json) {
    return UnmatchedDoneItem(
      content: '${json['content'] ?? ''}',
      recordedAt: DateTime.tryParse('${json['recordedAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

abstract interface class UnmatchedDoneStore {
  Future<List<UnmatchedDoneItem>> read();
  Future<void> write(List<UnmatchedDoneItem> items);
  Future<void> append(Iterable<UnmatchedDoneItem> items);
  Future<void> clear();
  Future<void> removeAt(int index);
}

class PrefsUnmatchedDoneStore implements UnmatchedDoneStore {
  PrefsUnmatchedDoneStore({SharedPreferences? prefs}) : _prefs = prefs;

  static const keyItems = 'todoist_unmatched_done';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<List<UnmatchedDoneItem>> read() async {
    final prefs = await _ensure();
    final raw = prefs.getString(keyItems);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => UnmatchedDoneItem.fromJson(e as Map<String, dynamic>))
          .where((e) => e.content.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> write(List<UnmatchedDoneItem> items) async {
    final prefs = await _ensure();
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await prefs.setString(keyItems, encoded);
  }

  @override
  Future<void> append(Iterable<UnmatchedDoneItem> items) async {
    final current = await read();
    await write([...current, ...items]);
  }

  @override
  Future<void> clear() async {
    final prefs = await _ensure();
    await prefs.remove(keyItems);
  }

  @override
  Future<void> removeAt(int index) async {
    final current = await read();
    if (index < 0 || index >= current.length) return;
    final next = [...current]..removeAt(index);
    await write(next);
  }
}

class MemoryUnmatchedDoneStore implements UnmatchedDoneStore {
  MemoryUnmatchedDoneStore([List<UnmatchedDoneItem>? seed])
      : _items = List<UnmatchedDoneItem>.from(seed ?? const []);

  List<UnmatchedDoneItem> _items;

  @override
  Future<List<UnmatchedDoneItem>> read() async => List.unmodifiable(_items);

  @override
  Future<void> write(List<UnmatchedDoneItem> items) async {
    _items = List<UnmatchedDoneItem>.from(items);
  }

  @override
  Future<void> append(Iterable<UnmatchedDoneItem> items) async {
    _items = [..._items, ...items];
  }

  @override
  Future<void> clear() async {
    _items = [];
  }

  @override
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _items.length) return;
    _items = [..._items]..removeAt(index);
  }
}
