import 'dart:typed_data';

import '../capture/page_id.dart';
import 'vault_fs.dart';
import 'vault_paths.dart';

/// Result of dropping a capture photo into the bot inbox folder.
class BotInboxWriteResult {
  const BotInboxWriteResult({
    required this.relativePath,
    required this.fileName,
    required this.folder,
  });

  final String relativePath;
  final String fileName;
  final String folder;
}

/// Writes capture bytes into a vault-relative inbox folder (image only).
///
/// No OCR, Gemini, Canvas, or markdown. Collision-safe unique filenames.
class BotInboxWriter {
  BotInboxWriter({
    PageId? pageIds,
  }) : _pageIds = pageIds ?? PageId();

  final PageId _pageIds;

  /// Write [imageBytes] under [inboxFolder] with a unique timestamp-ish name.
  Future<BotInboxWriteResult> writeImage({
    required VaultFs vault,
    required String inboxFolder,
    required Uint8List imageBytes,
    required DateTime capturedAt,
    String imageExtension = 'jpg',
  }) async {
    final folder =
        normalizeVaultFolder(inboxFolder) ?? BotInboxWriter.defaultFolder;
    final ext = _sanitizeExtension(imageExtension);
    final pageId = _pageIds.generate(at: capturedAt.toLocal());
    final relativePath = await _uniqueRelativePath(
      vault: vault,
      folder: folder,
      stem: pageId,
      extension: ext,
    );
    assertVaultWriteAllowed(relativePath);
    await vault.ensureDir(folder);
    await vault.writeBytes(relativePath, imageBytes);
    final slash = relativePath.lastIndexOf('/');
    final fileName =
        slash == -1 ? relativePath : relativePath.substring(slash + 1);
    return BotInboxWriteResult(
      relativePath: relativePath,
      fileName: fileName,
      folder: folder,
    );
  }

  static const String defaultFolder = 'inbox';

  Future<String> _uniqueRelativePath({
    required VaultFs vault,
    required String folder,
    required String stem,
    required String extension,
  }) async {
    var candidate = joinVaultRelative(folder, '$stem.$extension');
    if (!await vault.exists(candidate)) return candidate;
    for (var n = 2; n <= 99; n++) {
      candidate = joinVaultRelative(folder, '$stem-$n.$extension');
      if (!await vault.exists(candidate)) return candidate;
    }
    throw StateError(
      'Could not find a free filename for $stem.$extension in $folder',
    );
  }

  static String _sanitizeExtension(String raw) {
    var e = raw.trim().toLowerCase().replaceAll(RegExp(r'^\.+'), '');
    if (e.isEmpty) return 'jpg';
    e = e.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (e.isEmpty) return 'jpg';
    return e.length <= 8 ? e : e.substring(0, 8);
  }
}
