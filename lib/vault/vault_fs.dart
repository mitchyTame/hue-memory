import 'dart:typed_data';

/// Vault-relative filesystem. All vault I/O must go through this interface.
///
/// On Android, Obsidian vaults use [SafVaultFs] with a persistable tree URI —
/// never `dart:io` [File] against `/storage/emulated/…` (scoped storage
/// returns errno 13). Desktop / app-private defaults use [LocalVaultFs].
abstract interface class VaultFs {
  /// Whether a vault-relative path exists.
  Future<bool> exists(String relativePath);

  /// Read UTF-8 text at [relativePath]. Throws if missing.
  Future<String> readText(String relativePath);

  /// Write UTF-8 text, creating parent directories as needed.
  Future<void> writeText(String relativePath, String contents);

  /// Write bytes (images, etc.), creating parent directories as needed.
  Future<void> writeBytes(String relativePath, Uint8List bytes);

  /// Read bytes. Throws if missing.
  Future<Uint8List> readBytes(String relativePath);

  /// Ensure directory exists (mkdir -p semantics).
  Future<void> ensureDir(String relativePath);

  /// List immediate children (file/dir names only) under [relativePath].
  Future<List<String>> list(String relativePath);
}
