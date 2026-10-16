import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'saf_documents.dart';
import 'vault_fs.dart';

/// Whether [value] looks like an Android SAF tree URI (not a filesystem path).
bool isSafTreeUri(String? value) =>
    value != null && value.startsWith('content:');

/// Short label for Settings / capture chrome.
String safVaultLabel(String treeUri) {
  // Prefer the last path segment of the document id when present.
  final decoded = Uri.decodeFull(treeUri);
  final slash = decoded.lastIndexOf('/');
  if (slash >= 0 && slash < decoded.length - 1) {
    final tail = decoded.substring(slash + 1);
    if (tail.isNotEmpty && !tail.contains(':')) return 'SAF: $tail';
  }
  if (decoded.length <= 48) return 'SAF: $decoded';
  return 'SAF: …${decoded.substring(decoded.length - 40)}';
}

String mimeForVaultPath(String relativePath) {
  final ext = p.extension(relativePath).toLowerCase();
  return switch (ext) {
    '.md' => 'text/markdown',
    '.txt' => 'text/plain',
    '.json' || '.canvas' => 'application/json',
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.webp' => 'image/webp',
    '.gif' => 'image/gif',
    _ => 'application/octet-stream',
  };
}

/// SAF-backed [VaultFs] — all I/O through document URIs, never `dart:io`.
class SafVaultFs implements VaultFs {
  SafVaultFs({
    required this.treeUri,
    SafDocuments? documents,
  }) : _docs = documents ?? PluginSafDocuments();

  /// Persistable tree URI from [SafDocuments.pickDirectory].
  final String treeUri;

  final SafDocuments _docs;

  List<String> _segments(String relativePath) {
    final cleaned =
        relativePath.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    if (cleaned.isEmpty || cleaned == '.') return const [];
    final parts = cleaned.split('/').where((e) => e.isNotEmpty).toList();
    if (parts.any((e) => e == '..')) {
      throw ArgumentError('Path escapes vault root: $relativePath');
    }
    return parts;
  }

  Future<String?> _resolveUri(String relativePath) async {
    final parts = _segments(relativePath);
    if (parts.isEmpty) return treeUri;
    final doc = await _docs.child(treeUri, parts);
    return doc?.uri;
  }

  Future<String> _ensureParentDir(String relativePath) async {
    final parts = _segments(relativePath);
    if (parts.isEmpty) {
      throw ArgumentError('Cannot write vault root as a file');
    }
    if (parts.length == 1) return treeUri;
    final parent = parts.sublist(0, parts.length - 1);
    final dir = await _docs.mkdirp(treeUri, parent);
    return dir.uri;
  }

  @override
  Future<void> ensureDir(String relativePath) async {
    final parts = _segments(relativePath);
    if (parts.isEmpty) return;
    await _docs.mkdirp(treeUri, parts);
  }

  @override
  Future<bool> exists(String relativePath) async {
    final parts = _segments(relativePath);
    if (parts.isEmpty) return true;
    final doc = await _docs.child(treeUri, parts);
    return doc != null;
  }

  @override
  Future<List<String>> list(String relativePath) async {
    final parts = _segments(relativePath);
    final dirUri = parts.isEmpty
        ? treeUri
        : (await _docs.child(treeUri, parts))?.uri;
    if (dirUri == null) return const [];
    final children = await _docs.list(dirUri);
    final names = children.map((c) => c.name).toList()..sort();
    return names;
  }

  @override
  Future<Uint8List> readBytes(String relativePath) async {
    final uri = await _resolveUri(relativePath);
    if (uri == null) {
      throw StateError('Missing file: $relativePath');
    }
    return _docs.readFileBytes(uri);
  }

  @override
  Future<String> readText(String relativePath) async {
    final bytes = await readBytes(relativePath);
    return utf8.decode(bytes);
  }

  @override
  Future<void> writeBytes(String relativePath, Uint8List bytes) async {
    final parts = _segments(relativePath);
    if (parts.isEmpty) {
      throw ArgumentError('Cannot write vault root as a file');
    }
    final name = parts.last;
    final parentUri = await _ensureParentDir(relativePath);
    await _docs.writeFileBytes(
      parentUri,
      name,
      mimeForVaultPath(relativePath),
      bytes,
      overwrite: true,
    );
  }

  @override
  Future<void> writeText(String relativePath, String contents) async {
    await writeBytes(
      relativePath,
      Uint8List.fromList(utf8.encode(contents)),
    );
  }
}
