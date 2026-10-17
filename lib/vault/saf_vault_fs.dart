import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'saf_documents.dart';
import 'vault_fs.dart';
import 'vault_paths.dart';

/// Whether [value] looks like an Android SAF tree URI (not a filesystem path).
bool isSafTreeUri(String? value) =>
    value != null && value.startsWith('content:');

/// Bare `content://…/tree/<id>` form Android actually persists.
///
/// `saf` pickDirectory returns the normalized
/// `tree/<id>/document/<id>` document URI, but
/// [ContentResolver.takePersistableUriPermission] stores the bare tree URI.
/// Prefs must keep the bare form so restore can match [persistedPermissions].
///
/// String-slices (does not re-encode) so `%3A` stays `%3A`.
String safBareTreeUri(String uri) {
  if (!uri.startsWith('content:')) return uri;
  const treeSeg = '/tree/';
  const docSeg = '/document/';
  final treeAt = uri.indexOf(treeSeg);
  if (treeAt < 0) return uri;
  final idStart = treeAt + treeSeg.length;
  final docAt = uri.indexOf(docSeg, idStart);
  if (docAt < 0) return uri; // already bare tree (or other shape)
  final treeId = uri.substring(idStart, docAt);
  final docIdStart = docAt + docSeg.length;
  var docIdEnd = uri.length;
  for (final stop in ['/', '?', '#']) {
    final i = uri.indexOf(stop, docIdStart);
    if (i >= 0 && i < docIdEnd) docIdEnd = i;
  }
  final docId = uri.substring(docIdStart, docIdEnd);
  if (treeId != docId) return uri;
  return uri.substring(0, docAt);
}

/// True when [a] and [b] name the same SAF tree (bare or document-normalized).
bool safSameTreeUri(String a, String b) {
  if (a == b) return true;
  final bareA = safBareTreeUri(a);
  final bareB = safBareTreeUri(b);
  if (bareA == bareB) return true;
  return Uri.decodeFull(bareA) == Uri.decodeFull(bareB);
}

/// Short label for Settings / capture chrome (no framework jargon).
String safVaultLabel(String treeUri) {
  // Prefer the last path segment of the document id when present.
  final decoded = Uri.decodeFull(treeUri);
  final slash = decoded.lastIndexOf('/');
  if (slash >= 0 && slash < decoded.length - 1) {
    final tail = decoded.substring(slash + 1);
    // Document ids often look like `primary:Documents/VaultName`.
    final colon = tail.lastIndexOf(':');
    final name = colon >= 0 && colon < tail.length - 1
        ? tail.substring(colon + 1)
        : tail;
    final leaf = name.contains('/') ? name.split('/').last : name;
    if (leaf.isNotEmpty) return leaf;
  }
  if (decoded.length <= 48) return decoded;
  return '…${decoded.substring(decoded.length - 40)}';
}

/// MIME for SAF [DocumentsContract.createDocument].
///
/// **`.canvas` must not use `application/json`.** Android External Storage
/// Provider maps that MIME to a `.json` extension and rewrites
/// `note.canvas` → `note.canvas.json` (or `note.json.canvas`). Obsidian needs
/// the literal `.canvas` suffix — use octet-stream so the display name is kept.
String mimeForVaultPath(String relativePath) {
  final ext = p.extension(relativePath).toLowerCase();
  return switch (ext) {
    '.md' => 'text/markdown',
    '.txt' => 'text/plain',
    '.json' => 'application/json',
    '.canvas' => 'application/octet-stream',
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
    assertVaultWriteAllowed(relativePath);
    final parts = _segments(relativePath);
    if (parts.isEmpty) {
      throw ArgumentError('Cannot write vault root as a file');
    }
    final name = parts.last;
    final parentUri = await _ensureParentDir(relativePath);
    final created = await _docs.writeFileBytes(
      parentUri,
      name,
      mimeForVaultPath(relativePath),
      bytes,
      overwrite: true,
    );
    // Android DocumentsProvider may append a MIME-preferred extension
    // (e.g. application/json → *.canvas.json). Obsidian needs the literal
    // `.canvas` basename — refuse silently-wrong names.
    _assertSafDisplayName(requested: name, created: created.name);
  }

  static void _assertSafDisplayName({
    required String requested,
    required String created,
  }) {
    if (created == requested) return;
    final reqLower = requested.toLowerCase();
    final createdLower = created.toLowerCase();
    if (reqLower.endsWith('.canvas') &&
        (createdLower.endsWith('.json.canvas') ||
            createdLower.endsWith('.canvas.json') ||
            createdLower.contains('.json.'))) {
      throw StateError(
        'SAF renamed .canvas to $created (MIME must keep literal .canvas). '
        'Refusing write — Obsidian would not open a Canvas.',
      );
    }
    if (created != requested) {
      throw StateError(
        'SAF renamed vault file "$requested" → "$created" — refusing write',
      );
    }
  }

  @override
  Future<void> writeText(String relativePath, String contents) async {
    await writeBytes(
      relativePath,
      Uint8List.fromList(utf8.encode(contents)),
    );
  }
}
