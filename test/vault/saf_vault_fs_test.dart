import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/vault/saf_documents.dart';
import 'package:hue_memory/vault/saf_vault_fs.dart';
import 'package:saf/saf.dart';

void main() {
  late MemorySafDocuments docs;
  late SafVaultFs vault;

  setUp(() {
    docs = MemorySafDocuments();
    docs.grantRoot();
    vault = SafVaultFs(treeUri: docs.rootUri, documents: docs);
  });

  test('isSafTreeUri detects content URIs', () {
    expect(isSafTreeUri('content://com.android.externalstorage.documents/tree/primary%3AObsidian'), isTrue);
    expect(isSafTreeUri('/home/user/vault'), isFalse);
    expect(isSafTreeUri(null), isFalse);
  });

  test('safBareTreeUri strips document-normalized pick URI', () {
    const bare =
        'content://com.android.externalstorage.documents/tree/primary%3AVault';
    const document =
        'content://com.android.externalstorage.documents/tree/primary%3AVault/document/primary%3AVault';
    expect(safBareTreeUri(document), bare);
    expect(safBareTreeUri(bare), bare);
    expect(safSameTreeUri(document, bare), isTrue);
    expect(
      safSameTreeUri(document, 'content://other/tree/primary%3AVault'),
      isFalse,
    );
  });

  test('mimeForVaultPath covers note + image + canvas', () {
    expect(mimeForVaultPath('a/b.md'), 'text/markdown');
    // .canvas must NOT be application/json — SAF would rename to *.json.canvas
    // or *.canvas.json. Octet-stream keeps the literal .canvas display name.
    expect(mimeForVaultPath('x.canvas'), 'application/octet-stream');
    expect(mimeForVaultPath('x.canvas'), isNot(equals('application/json')));
    expect(mimeForVaultPath('raw/page.png'), 'image/png');
    expect(mimeForVaultPath('raw/page.weird'), 'application/octet-stream');
  });

  test('canvas write keeps .canvas basename (not .json.canvas)', () async {
    await vault.writeText(
      'mindmaps/20261016-p7k2-topic.canvas',
      '{"nodes":[],"edges":[]}',
    );
    final names = await vault.list('mindmaps');
    expect(names, ['20261016-p7k2-topic.canvas']);
    expect(names.any((n) => n.contains('.json')), isFalse);
  });

  test('SAF refuses write when provider renames .canvas to .canvas.json', () async {
    final renaming = _RenamingSafDocuments(docs, rename: (name) {
      if (name.endsWith('.canvas')) return '$name.json';
      return name;
    });
    final badVault = SafVaultFs(treeUri: docs.rootUri, documents: renaming);
    expect(
      () => badVault.writeText(
        'mindmaps/topic.canvas',
        '{"nodes":[],"edges":[]}',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('SAF renamed'),
        ),
      ),
    );
  });

  test('writeText / readText / exists / list round-trip', () async {
    await vault.writeText('fleeting/note.md', '# hello\n');
    expect(await vault.exists('fleeting/note.md'), isTrue);
    expect(await vault.exists('fleeting'), isTrue);
    expect(await vault.readText('fleeting/note.md'), '# hello\n');

    final top = await vault.list('');
    expect(top, contains('fleeting'));
    final nested = await vault.list('fleeting');
    expect(nested, ['note.md']);
  });

  test('writeBytes overwrites and mkdirp parents', () async {
    final png = Uint8List.fromList([1, 2, 3, 4]);
    await vault.writeBytes('captures/raw/page.png', png);
    expect(await vault.readBytes('captures/raw/page.png'), png);

    final again = Uint8List.fromList([9, 9]);
    await vault.writeBytes('captures/raw/page.png', again);
    expect(await vault.readBytes('captures/raw/page.png'), again);
  });

  test('ensureDir creates nested folders', () async {
    await vault.ensureDir('daily/2026');
    expect(await vault.exists('daily/2026'), isTrue);
    expect(await vault.list('daily'), ['2026']);
  });

  test('path escape with .. is rejected', () async {
    expect(() => vault.exists('../outside'), throwsArgumentError);
  });

  test('missing read throws', () async {
    expect(() => vault.readText('nope.md'), throwsStateError);
  });

  test('pickDirectory records persistable grant', () async {
    docs.lastPicked = SafDocumentFile(
      uri: docs.rootUri,
      name: 'primary',
      isDir: true,
      length: 0,
      lastModified: 0,
    );
    final picked = await docs.pickDirectory(writePermission: true);
    expect(picked?.uri, docs.rootUri);
    final grants = await docs.persistedPermissions();
    expect(grants.any((g) => g.uri == docs.rootUri && g.write), isTrue);
  });

  test('utf8 text survives writeBytes path', () async {
    await vault.writeText('permanent/ü.md', 'café');
    final bytes = await vault.readBytes('permanent/ü.md');
    expect(utf8.decode(bytes), 'café');
  });
}

/// Test double: returns a renamed display name from [writeFileBytes].
class _RenamingSafDocuments implements SafDocuments {
  _RenamingSafDocuments(this._inner, {required this.rename});

  final SafDocuments _inner;
  final String Function(String name) rename;

  @override
  Future<SafDocumentFile?> child(String dirUri, List<String> names) =>
      _inner.child(dirUri, names);

  @override
  Future<bool> exists(String uri) => _inner.exists(uri);

  @override
  Future<List<SafDocumentFile>> list(String dirUri) => _inner.list(dirUri);

  @override
  Future<SafDocumentFile> mkdirp(String dirUri, List<String> names) =>
      _inner.mkdirp(dirUri, names);

  @override
  Future<SafDocumentFile?> pickDirectory({
    String? initialUri,
    bool writePermission = true,
    bool persistablePermission = true,
  }) =>
      _inner.pickDirectory(
        initialUri: initialUri,
        writePermission: writePermission,
        persistablePermission: persistablePermission,
      );

  @override
  Future<List<SafPersistedPermission>> persistedPermissions() =>
      _inner.persistedPermissions();

  @override
  Future<Uint8List> readFileBytes(String uri) => _inner.readFileBytes(uri);

  @override
  Future<SafDocumentFile> writeFileBytes(
    String dirUri,
    String name,
    String mime,
    Uint8List data, {
    bool overwrite = false,
  }) async {
    final created = await _inner.writeFileBytes(
      dirUri,
      name,
      mime,
      data,
      overwrite: overwrite,
    );
    final renamed = rename(name);
    if (renamed == name) return created;
    return SafDocumentFile(
      uri: created.uri,
      name: renamed,
      isDir: false,
      length: created.length,
      lastModified: created.lastModified,
    );
  }
}
