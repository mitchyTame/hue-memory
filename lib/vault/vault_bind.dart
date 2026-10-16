import 'dart:io';

import 'local_vault_fs.dart';
import 'saf_documents.dart';
import 'saf_vault_fs.dart';
import 'vault_fs.dart';
import 'vault_paths.dart';

/// Result of binding a chosen vault root (path or durable tree URI).
class VaultBindResult {
  const VaultBindResult({
    required this.vault,
    required this.persist,
    required this.label,
  });

  final VaultFs vault;
  final String persist;
  final String label;
}

/// Cold-start restore of a previously saved vault root.
class VaultResolveResult {
  const VaultResolveResult({
    required this.bound,
    this.repickHint,
    this.restoredFromPrefs = false,
  });

  final VaultBindResult bound;

  /// Set when a saved vault could not be restored (grant revoked / unwritable).
  /// Calm UI copy — never silent empty.
  final String? repickHint;

  /// True when [bound] came from the saved prefs root (not the app default).
  final bool restoredFromPrefs;
}

/// Shown when a previously chosen vault folder is no longer writable.
const String kVaultRepickHint =
    'Choose vault folder again — the previous folder permission expired.';

/// User-visible bind / pick failure — never an unhandled crash.
class VaultBindException implements Exception {
  VaultBindException(this.userMessage, {this.cause});

  final String userMessage;
  final Object? cause;

  @override
  String toString() => userMessage;
}

/// Paths under shared storage that scoped Android cannot write via dart:io.
bool looksLikeAndroidSharedStorage(String path) {
  final n = path.replaceAll('\\', '/');
  return n.startsWith('/storage/') || n.startsWith('/sdcard/');
}

/// Calm copy when folder pick or bind fails.
String vaultPickFailedMessage(Object error) {
  if (error is VaultBindException) return error.userMessage;
  final raw = error.toString();
  if (raw.contains('PathAccessException') ||
      raw.contains('Permission denied') ||
      raw.contains('errno = 13') ||
      raw.contains('EACCES') ||
      looksLikeAndroidSharedStorage(raw)) {
    return 'Android cannot write that folder by path. '
        'Choose the Obsidian vault folder again so hue-memory can write '
        'while Obsidian stays open.';
  }
  if (raw.contains('Failed to retrieve') ||
      raw.contains('unknown_path') ||
      raw.contains('FileSystemException') ||
      raw.contains('OS Error')) {
    return 'Could not open that folder. Try Choose vault folder again, '
        'or use the app default folder.';
  }
  return 'Could not use that folder. Try again, or use the app default folder.';
}

/// Whether [rootRef] is safe to open with [LocalVaultFs] (not a content URI).
bool isLocalFilesystemPath(String? rootRef) {
  if (rootRef == null || rootRef.isEmpty) return false;
  if (isSafTreeUri(rootRef)) return false;
  if (rootRef.contains('://')) return false;
  return rootRef.startsWith('/') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(rootRef);
}

/// Bind a picked vault root.
///
/// Prefer durable tree URIs (`content://…`) so Obsidian vaults on Android
/// shared storage stay writable. Plain `/storage/emulated/…` paths are rejected.
VaultBindResult bindVaultRoot({
  required String rootRef,
  required SafDocuments documents,
  bool rejectAndroidSharedStorage = true,
}) {
  final trimmed = rootRef.trim();
  if (trimmed.isEmpty) {
    throw VaultBindException(
      'No folder selected. Choose an Obsidian vault folder, or cancel.',
    );
  }

  if (isSafTreeUri(trimmed)) {
    // Persist the bare tree URI — matches Android's takePersistable grant.
    // pickDirectory often returns tree/<id>/document/<id>; grants list the bare
    // tree/<id>, so storing the document form made restore fail every launch.
    final bare = safBareTreeUri(trimmed);
    return VaultBindResult(
      vault: SafVaultFs(treeUri: bare, documents: documents),
      persist: bare,
      label: safVaultLabel(bare),
    );
  }

  if (!isLocalFilesystemPath(trimmed)) {
    throw VaultBindException(
      'That folder path is not usable. Choose the Obsidian vault folder again, '
      'or use the app default folder.',
      cause: trimmed,
    );
  }

  if (rejectAndroidSharedStorage && looksLikeAndroidSharedStorage(trimmed)) {
    throw VaultBindException(
      'Android cannot write that folder by path. '
      'Choose the Obsidian vault folder again so hue-memory can write '
      'while Obsidian stays open.',
      cause: trimmed,
    );
  }

  try {
    final vault = LocalVaultFs(Directory(trimmed));
    return VaultBindResult(
      vault: vault,
      persist: vault.rootPath,
      label: vault.rootPath,
    );
  } on ArgumentError catch (e) {
    throw VaultBindException(vaultPickFailedMessage(e), cause: e);
  } on FileSystemException catch (e) {
    throw VaultBindException(vaultPickFailedMessage(e), cause: e);
  } catch (e) {
    throw VaultBindException(vaultPickFailedMessage(e), cause: e);
  }
}

/// Resolve a previously persisted root, or fall back to [fallbackDirectory].
///
/// On Android, [saved] must be the durable tree URI string (bare `tree/<id>`)
/// and the OS persistable grant must still be valid. Document-normalized pick
/// URIs are matched via [safSameTreeUri].
Future<VaultResolveResult> resolvePersistedVaultRoot({
  required String? saved,
  required SafDocuments documents,
  required Future<Directory> Function() fallbackDirectory,
}) async {
  if (isSafTreeUri(saved)) {
    try {
      final grants = await documents.persistedPermissions();
      // Match bare tree ↔ document-normalized forms (see [safSameTreeUri]).
      for (final g in grants) {
        if (g.write && safSameTreeUri(g.uri, saved!)) {
          return VaultResolveResult(
            bound: bindVaultRoot(rootRef: g.uri, documents: documents),
            restoredFromPrefs: true,
          );
        }
      }
      // Grant list may lag or use a different encoding — try the saved URI.
      final bound = bindVaultRoot(rootRef: saved!, documents: documents);
      await verifyVaultWritable(bound.vault);
      return VaultResolveResult(bound: bound, restoredFromPrefs: true);
    } catch (_) {
      // Grant revoked or unwritable — fall through with a calm re-pick hint.
      final root = await fallbackDirectory();
      return VaultResolveResult(
        bound: bindVaultRoot(rootRef: root.path, documents: documents),
        repickHint: kVaultRepickHint,
      );
    }
  } else if (saved != null &&
      isLocalFilesystemPath(saved) &&
      !looksLikeAndroidSharedStorage(saved) &&
      Directory(saved).existsSync()) {
    try {
      return VaultResolveResult(
        bound: bindVaultRoot(rootRef: saved, documents: documents),
        restoredFromPrefs: true,
      );
    } catch (_) {
      // Fall through to default.
    }
  }

  final root = await fallbackDirectory();
  final savedTrimmed = saved?.trim() ?? '';
  final hadUnusableSaved = savedTrimmed.isNotEmpty;
  return VaultResolveResult(
    bound: bindVaultRoot(rootRef: root.path, documents: documents),
    repickHint: hadUnusableSaved && looksLikeAndroidSharedStorage(savedTrimmed)
        ? kVaultRepickHint
        : null,
  );
}

/// Smoke-write to confirm the bound vault is writable.
///
/// Writes a **root file** — never a nested `hue-memory/` folder.
Future<void> verifyVaultWritable(VaultFs vault) async {
  final stamp = DateTime.now().toUtc().toIso8601String();
  try {
    await vault.writeText(kVaultWriteCheckRelative, stamp);
  } on FileSystemException catch (e) {
    throw VaultBindException(vaultPickFailedMessage(e), cause: e);
  } catch (e) {
    throw VaultBindException(vaultPickFailedMessage(e), cause: e);
  }
}
