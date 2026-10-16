import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/settings/vault_settings_store.dart';
import 'package:hue_memory/vault/local_vault_fs.dart';
import 'package:hue_memory/vault/saf_documents.dart';
import 'package:hue_memory/vault/saf_vault_fs.dart';
import 'package:hue_memory/vault/vault_bind.dart';
import 'package:hue_memory/vault/vault_paths.dart';
import 'package:saf/saf.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late MemorySafDocuments docs;
  late Directory temp;

  setUp(() {
    docs = MemorySafDocuments();
    docs.grantRoot();
    temp = Directory.systemTemp.createTempSync('hue-vault-bind-');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('looksLikeAndroidSharedStorage detects emulated paths', () {
    expect(
      looksLikeAndroidSharedStorage(
        '/storage/emulated/Documents/mgtroaming remote',
      ),
      isTrue,
    );
    expect(
      looksLikeAndroidSharedStorage('/storage/emulated/0/Documents/Vault'),
      isTrue,
    );
    expect(looksLikeAndroidSharedStorage('/sdcard/Obsidian'), isTrue);
    expect(looksLikeAndroidSharedStorage(temp.path), isFalse);
    expect(
      looksLikeAndroidSharedStorage(
        'content://com.android.externalstorage.documents/tree/primary%3ADocs',
      ),
      isFalse,
    );
  });

  test('bindVaultRoot rejects Android shared-storage paths calmly', () {
    expect(
      () => bindVaultRoot(
        rootRef: '/storage/emulated/Documents/mgtroaming remote',
        documents: docs,
      ),
      throwsA(
        isA<VaultBindException>().having(
          (e) => e.userMessage,
          'message',
          contains('Choose the Obsidian vault folder again'),
        ),
      ),
    );
  });

  test('bindVaultRoot accepts content tree URI as SafVaultFs', () {
    final bound = bindVaultRoot(rootRef: docs.rootUri, documents: docs);
    expect(bound.vault, isA<SafVaultFs>());
    expect(bound.persist, docs.rootUri);
    expect(bound.label, isNot(contains('SAF')));
  });

  test('bindVaultRoot accepts local temp path as LocalVaultFs', () {
    final bound = bindVaultRoot(rootRef: temp.path, documents: docs);
    expect(bound.vault, isA<LocalVaultFs>());
    expect(bound.persist, temp.path);
  });

  test('bindVaultRoot rejects empty and content-looking junk', () {
    expect(
      () => bindVaultRoot(rootRef: '  ', documents: docs),
      throwsA(isA<VaultBindException>()),
    );
    expect(
      () => bindVaultRoot(rootRef: 'http://example.com/vault', documents: docs),
      throwsA(isA<VaultBindException>()),
    );
  });

  test('vaultPickFailedMessage maps PathAccessException copy', () {
    final err = PathAccessException(
      '/storage/emulated/Documents/v/packs/active.yaml',
      const OSError('Permission denied', 13),
      'Cannot open file',
    );
    final msg = vaultPickFailedMessage(err);
    expect(msg, contains('Choose the Obsidian vault folder again'));
    expect(msg, isNot(contains('PathAccessException')));
  });

  test('resolvePersistedVaultRoot restores granted tree URI', () async {
    final resolved = await resolvePersistedVaultRoot(
      saved: docs.rootUri,
      documents: docs,
      fallbackDirectory: () async => temp,
    );
    expect(resolved.restoredFromPrefs, isTrue);
    expect(resolved.repickHint, isNull);
    expect(resolved.bound.vault, isA<SafVaultFs>());
    expect(resolved.bound.persist, docs.rootUri);
  });

  test(
    'resolvePersistedVaultRoot matches document URI to bare tree grant',
    () async {
      // Real Android: pick returns tree/<id>/document/<id>; grant is tree/<id>.
      const bare =
          'content://com.android.externalstorage.documents/tree/primary%3AVault';
      const document =
          'content://com.android.externalstorage.documents/tree/primary%3AVault/document/primary%3AVault';
      final mem = MemorySafDocuments(rootUri: bare)..grantRoot();
      final resolved = await resolvePersistedVaultRoot(
        saved: document,
        documents: mem,
        fallbackDirectory: () async => temp,
      );
      expect(resolved.restoredFromPrefs, isTrue);
      expect(resolved.bound.vault, isA<SafVaultFs>());
      expect(resolved.bound.persist, bare);
      expect(safSameTreeUri(resolved.bound.persist, document), isTrue);
    },
  );

  test('bindVaultRoot persists bare tree URI from document form', () {
    const document =
        'content://com.android.externalstorage.documents/tree/primary%3AVault/document/primary%3AVault';
    const bare =
        'content://com.android.externalstorage.documents/tree/primary%3AVault';
    final mem = MemorySafDocuments(rootUri: bare)..grantRoot();
    final bound = bindVaultRoot(rootRef: document, documents: mem);
    expect(bound.persist, bare);
    expect((bound.vault as SafVaultFs).treeUri, bare);
  });

  test('resolvePersistedVaultRoot skips unwritable shared-storage prefs',
      () async {
    final resolved = await resolvePersistedVaultRoot(
      saved: '/storage/emulated/0/Documents/ObsidianVault',
      documents: docs,
      fallbackDirectory: () async => temp,
    );
    expect(resolved.bound.vault, isA<LocalVaultFs>());
    expect(resolved.bound.persist, temp.path);
    expect(resolved.restoredFromPrefs, isFalse);
    expect(resolved.repickHint, kVaultRepickHint);
  });

  test('cold start: pick → prefs → reopen still bound (no re-pick)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = PrefsVaultSettingsStore(prefs: prefs);

    const bare =
        'content://com.android.externalstorage.documents/tree/primary%3AVault';
    const document =
        'content://com.android.externalstorage.documents/tree/primary%3AVault/document/primary%3AVault';
    final mem = MemorySafDocuments(rootUri: bare)..grantRoot();

    // Session: pick document-form URI, bind, save prefs (bare tree).
    final picked = bindVaultRoot(rootRef: document, documents: mem);
    await verifyVaultWritable(picked.vault);
    await store.writeVaultRoot(picked.persist);
    expect(await store.readVaultRoot(), bare);

    // Process death: new resolve with same prefs + OS grants.
    final saved = await store.readVaultRoot();
    final resolved = await resolvePersistedVaultRoot(
      saved: saved,
      documents: mem,
      fallbackDirectory: () async => temp,
    );
    expect(resolved.restoredFromPrefs, isTrue);
    expect(resolved.repickHint, isNull);
    expect(resolved.bound.vault, isA<SafVaultFs>());
    expect(resolved.bound.persist, bare);
  });

  test('cold start: revoked grant asks to choose folder again', () async {
    const bare =
        'content://com.android.externalstorage.documents/tree/primary%3AVault';
    // Unrelated tree — no grant and no nodes for [bare] → write check fails.
    final mem = MemorySafDocuments(
      rootUri: 'content://hue.test/tree/unrelated',
    );
    final resolved = await resolvePersistedVaultRoot(
      saved: bare,
      documents: mem,
      fallbackDirectory: () async => temp,
    );
    expect(resolved.restoredFromPrefs, isFalse);
    expect(resolved.repickHint, kVaultRepickHint);
    expect(resolved.bound.persist, temp.path);
  });

  test('verifyVaultWritable succeeds on memory SAF vault', () async {
    final vault = SafVaultFs(treeUri: docs.rootUri, documents: docs);
    await verifyVaultWritable(vault);
    expect(await vault.exists(kVaultWriteCheckRelative), isTrue);
    expect(await vault.exists('hue-memory/.write-check'), isFalse);
  });

  test('verifyVaultWritable succeeds on local vault', () async {
    final vault = LocalVaultFs(temp);
    await verifyVaultWritable(vault);
    expect(await vault.exists(kVaultWriteCheckRelative), isTrue);
  });

  test('pickDirectory + bind round-trip for Obsidian coexistence', () async {
    docs.lastPicked = SafDocumentFile(
      uri: docs.rootUri,
      name: 'primary',
      isDir: true,
      length: 0,
      lastModified: 0,
    );
    final picked = await docs.pickDirectory(
      writePermission: true,
      persistablePermission: true,
    );
    expect(picked, isNotNull);
    final bound = bindVaultRoot(rootRef: picked!.uri, documents: docs);
    await verifyVaultWritable(bound.vault);
    await bound.vault.writeText('fleeting/note.md', '# ok\n');
    expect(await bound.vault.readText('fleeting/note.md'), '# ok\n');
  });

  test('safVaultLabel has no SAF jargon', () {
    final label = safVaultLabel(
      'content://com.android.externalstorage.documents/tree/primary%3ADocuments%2Fmgtroaming',
    );
    expect(label.toLowerCase(), isNot(contains('saf')));
    expect(label, isNotEmpty);
  });
}
