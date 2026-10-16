import 'dart:typed_data';

import 'package:saf/saf.dart';

/// Minimal document-tree operations [SafVaultFs] needs.
///
/// Production uses [PluginSafDocuments] (Android SAF). Tests use
/// [MemorySafDocuments]. Never touch vault paths with `dart:io` File.
abstract interface class SafDocuments {
  Future<bool> exists(String uri);

  Future<SafDocumentFile?> child(String dirUri, List<String> names);

  Future<SafDocumentFile> mkdirp(String dirUri, List<String> names);

  Future<List<SafDocumentFile>> list(String dirUri);

  Future<Uint8List> readFileBytes(String uri);

  Future<SafDocumentFile> writeFileBytes(
    String dirUri,
    String name,
    String mime,
    Uint8List data, {
    bool overwrite = false,
  });

  Future<SafDocumentFile?> pickDirectory({
    String? initialUri,
    bool writePermission = true,
    bool persistablePermission = true,
  });

  Future<List<SafPersistedPermission>> persistedPermissions();
}

/// Real Android SAF via the `saf` plugin.
class PluginSafDocuments implements SafDocuments {
  PluginSafDocuments([Saf? saf]) : _saf = saf ?? Saf();

  final Saf _saf;

  @override
  Future<SafDocumentFile?> child(String dirUri, List<String> names) =>
      _saf.child(dirUri, names);

  @override
  Future<bool> exists(String uri) => _saf.exists(uri);

  @override
  Future<List<SafDocumentFile>> list(String dirUri) => _saf.list(dirUri);

  @override
  Future<SafDocumentFile> mkdirp(String dirUri, List<String> names) =>
      _saf.mkdirp(dirUri, names);

  @override
  Future<List<SafPersistedPermission>> persistedPermissions() =>
      _saf.persistedPermissions();

  @override
  Future<SafDocumentFile?> pickDirectory({
    String? initialUri,
    bool writePermission = true,
    bool persistablePermission = true,
  }) =>
      _saf.pickDirectory(
        initialUri: initialUri,
        writePermission: writePermission,
        persistablePermission: persistablePermission,
      );

  @override
  Future<Uint8List> readFileBytes(String uri) => _saf.readFileBytes(uri);

  @override
  Future<SafDocumentFile> writeFileBytes(
    String dirUri,
    String name,
    String mime,
    Uint8List data, {
    bool overwrite = false,
  }) =>
      _saf.writeFileBytes(dirUri, name, mime, data, overwrite: overwrite);
}

/// In-memory SAF tree for unit tests (content:// URIs, no Android).
class MemorySafDocuments implements SafDocuments {
  MemorySafDocuments({this.rootUri = 'content://hue.test/tree/primary'}) {
    _nodes[rootUri] = _Node.dir(uri: rootUri, name: 'primary');
  }

  final String rootUri;
  final Map<String, _Node> _nodes = {};
  final List<SafPersistedPermission> grants = [];

  SafDocumentFile? lastPicked;

  String _childUri(String parentUri, String name) => '$parentUri/$name';

  @override
  Future<SafDocumentFile?> child(String dirUri, List<String> names) async {
    if (names.isEmpty) return _nodes[dirUri]?.toDoc();
    var uri = dirUri;
    for (final name in names) {
      uri = _childUri(uri, name);
      if (!_nodes.containsKey(uri)) return null;
    }
    return _nodes[uri]!.toDoc();
  }

  @override
  Future<bool> exists(String uri) async => _nodes.containsKey(uri);

  @override
  Future<List<SafDocumentFile>> list(String dirUri) async {
    final parent = _nodes[dirUri];
    if (parent == null || !parent.isDir) return const [];
    final prefix = '$dirUri/';
    final out = <SafDocumentFile>[];
    for (final entry in _nodes.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final rest = entry.key.substring(prefix.length);
      if (rest.contains('/')) continue;
      out.add(entry.value.toDoc());
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  @override
  Future<SafDocumentFile> mkdirp(String dirUri, List<String> names) async {
    if (!_nodes.containsKey(dirUri) || !_nodes[dirUri]!.isDir) {
      throw StateError('Missing directory: $dirUri');
    }
    var uri = dirUri;
    for (final name in names) {
      if (name.isEmpty || name.contains('/')) {
        throw ArgumentError('Bad segment: $name');
      }
      uri = _childUri(uri, name);
      final existing = _nodes[uri];
      if (existing == null) {
        _nodes[uri] = _Node.dir(uri: uri, name: name);
      } else if (!existing.isDir) {
        throw StateError('Not a directory: $uri');
      }
    }
    return _nodes[uri]!.toDoc();
  }

  @override
  Future<List<SafPersistedPermission>> persistedPermissions() async =>
      List.unmodifiable(grants);

  @override
  Future<SafDocumentFile?> pickDirectory({
    String? initialUri,
    bool writePermission = true,
    bool persistablePermission = true,
  }) async {
    final picked = lastPicked;
    if (picked == null) return null;
    if (persistablePermission) {
      grants.removeWhere((g) => g.uri == picked.uri);
      grants.add(
        SafPersistedPermission(
          uri: picked.uri,
          read: true,
          write: writePermission,
          persistedTime: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    return picked;
  }

  @override
  Future<Uint8List> readFileBytes(String uri) async {
    final node = _nodes[uri];
    if (node == null || node.isDir || node.bytes == null) {
      throw StateError('Missing file: $uri');
    }
    return Uint8List.fromList(node.bytes!);
  }

  @override
  Future<SafDocumentFile> writeFileBytes(
    String dirUri,
    String name,
    String mime,
    Uint8List data, {
    bool overwrite = false,
  }) async {
    final parent = _nodes[dirUri];
    if (parent == null || !parent.isDir) {
      throw StateError('Missing directory: $dirUri');
    }
    final uri = _childUri(dirUri, name);
    final existing = _nodes[uri];
    if (existing != null && !overwrite) {
      throw StateError('Already exists: $uri');
    }
    if (existing != null && existing.isDir) {
      throw StateError('Is a directory: $uri');
    }
    final node = _Node.file(
      uri: uri,
      name: name,
      bytes: Uint8List.fromList(data),
      mimeType: mime,
    );
    _nodes[uri] = node;
    return node.toDoc();
  }

  /// Test helper: ensure [rootUri] is listed as a writable persisted grant.
  void grantRoot({bool write = true}) {
    grants.removeWhere((g) => g.uri == rootUri);
    grants.add(
      SafPersistedPermission(
        uri: rootUri,
        read: true,
        write: write,
        persistedTime: 1,
      ),
    );
  }
}

class _Node {
  _Node.dir({required this.uri, required this.name})
      : isDir = true,
        bytes = null,
        mimeType = null;

  _Node.file({
    required this.uri,
    required this.name,
    required this.bytes,
    required this.mimeType,
  }) : isDir = false;

  final String uri;
  final String name;
  final bool isDir;
  final Uint8List? bytes;
  final String? mimeType;

  SafDocumentFile toDoc() => SafDocumentFile(
        uri: uri,
        name: name,
        isDir: isDir,
        length: bytes?.length ?? 0,
        lastModified: 0,
        mimeType: mimeType,
      );
}
