import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'vault_fs.dart';

/// In-memory [VaultFs] for unit tests. Paths use POSIX `/` separators.
class FakeVaultFs implements VaultFs {
  FakeVaultFs({Map<String, Object>? seed}) {
    if (seed != null) {
      for (final entry in seed.entries) {
        final key = _norm(entry.key);
        final value = entry.value;
        if (value is String) {
          _files[key] = Uint8List.fromList(utf8.encode(value));
        } else if (value is Uint8List) {
          _files[key] = value;
        } else if (value is List<int>) {
          _files[key] = Uint8List.fromList(value);
        } else {
          throw ArgumentError('Unsupported seed value for $key');
        }
      }
    }
  }

  final Map<String, Uint8List> _files = {};
  final Set<String> _dirs = {'/'};

  static String _norm(String path) {
    var s = path.replaceAll('\\', '/');
    if (s.isEmpty || s == '.') return '/';
    if (!s.startsWith('/')) s = '/$s';
    // Collapse duplicate slashes; strip trailing slash except root.
    final parts = s.split('/').where((e) => e.isNotEmpty).toList();
    return '/${parts.join('/')}';
  }

  void _ensureParent(String relativePath) {
    final parent = p.posix.dirname(relativePath);
    if (parent == '/' || parent == '.') {
      _dirs.add('/');
      return;
    }
    ensureDirSync(parent);
  }

  /// Synchronous helper for seeding directories in tests.
  void ensureDirSync(String relativePath) {
    final n = _norm(relativePath);
    if (n == '/') {
      _dirs.add('/');
      return;
    }
    final parts = n.split('/').where((e) => e.isNotEmpty).toList();
    var acc = '';
    for (final part in parts) {
      acc = '$acc/$part';
      _dirs.add(acc);
    }
  }

  @override
  Future<void> ensureDir(String relativePath) async {
    ensureDirSync(relativePath);
  }

  @override
  Future<bool> exists(String relativePath) async {
    final n = _norm(relativePath);
    return _files.containsKey(n) || _dirs.contains(n);
  }

  @override
  Future<List<String>> list(String relativePath) async {
    final n = _norm(relativePath);
    final prefix = n == '/' ? '/' : '$n/';
    final names = <String>{};
    for (final dir in _dirs) {
      if (dir == n) continue;
      if (dir.startsWith(prefix)) {
        final rest = dir.substring(prefix.length);
        if (!rest.contains('/')) names.add(rest);
      }
    }
    for (final file in _files.keys) {
      if (file.startsWith(prefix)) {
        final rest = file.substring(prefix.length);
        if (!rest.contains('/')) names.add(rest);
      }
    }
    final sorted = names.toList()..sort();
    return sorted;
  }

  @override
  Future<Uint8List> readBytes(String relativePath) async {
    final n = _norm(relativePath);
    final data = _files[n];
    if (data == null) {
      throw StateError('Missing file: $relativePath');
    }
    return Uint8List.fromList(data);
  }

  @override
  Future<String> readText(String relativePath) async {
    final bytes = await readBytes(relativePath);
    return utf8.decode(bytes);
  }

  @override
  Future<void> writeBytes(String relativePath, Uint8List bytes) async {
    final n = _norm(relativePath);
    _ensureParent(n);
    _files[n] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeText(String relativePath, String contents) async {
    await writeBytes(
      relativePath,
      Uint8List.fromList(utf8.encode(contents)),
    );
  }

  /// Test helper: snapshot of stored text files (path → content).
  Map<String, String> textSnapshot() {
    return {
      for (final e in _files.entries) e.key: utf8.decode(e.value),
    };
  }
}
