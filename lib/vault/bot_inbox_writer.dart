import 'dart:typed_data';

import '../capture/page_id.dart';
import '../writers/canvas_writer.dart';
import 'daily_note_path.dart';
import 'vault_fs.dart';
import 'vault_paths.dart';

/// Result of writing an Enhanced Bot Mode canvas (+ raw photo) into the inbox.
class BotInboxWriteResult {
  const BotInboxWriteResult({
    required this.relativePath,
    required this.fileName,
    required this.folder,
    required this.rawImagePath,
    required this.pageId,
  });

  /// Vault-relative `.canvas` path under the inbox folder.
  final String relativePath;
  final String fileName;
  final String folder;

  /// Vault-relative raw capture path (`captures/raw/…`).
  final String rawImagePath;
  final String pageId;
}

/// Writes Enhanced Bot Mode canvases into a vault inbox folder.
///
/// Primary artifact is `YYYY-MM-DD[-n].canvas` with the page photo under
/// `captures/raw/` (file node injected via [CanvasWriter.buildDiagramCanvas]).
/// Collision-safe rename (`-2`…`-99`), never refuse.
class BotInboxWriter {
  BotInboxWriter({
    PageId? pageIds,
    CanvasWriter? canvas,
  })  : _pageIds = pageIds ?? PageId(),
        _canvas = canvas ?? const CanvasWriter();

  final PageId _pageIds;
  final CanvasWriter _canvas;

  static const String defaultFolder = 'inbox';

  /// Write [imageBytes] + Gemini text nodes as one inbox `.canvas`.
  Future<BotInboxWriteResult> writeCanvas({
    required VaultFs vault,
    required String inboxFolder,
    required Uint8List imageBytes,
    required DateTime capturedAt,
    required List<CanvasNode> textNodes,
    List<CanvasEdge> edges = const [],
    String imageExtension = 'jpg',
  }) async {
    final folder =
        normalizeVaultFolder(inboxFolder) ?? BotInboxWriter.defaultFolder;
    final ext = _sanitizeExtension(imageExtension);
    final localAt = capturedAt.toLocal();
    final pageId = _pageIds.generate(at: localAt);
    final rawImagePath = joinVaultRelative('captures/raw', '$pageId.$ext');
    final stem = DailyNoteDate.formatIso(localAt);
    final canvasPath = await uniqueRelativePath(
      vault: vault,
      folder: folder,
      stem: stem,
      extension: 'canvas',
    );

    final doc = _canvas.buildDiagramCanvas(
      sourceImage: rawImagePath,
      textNodes: textNodes,
      edges: edges,
    );
    final canvasJson = _canvas.writeJson(doc);

    assertVaultWriteAllowed(canvasPath);
    assertVaultWriteAllowed(rawImagePath);
    await vault.ensureDir(folder);
    await vault.ensureDir('captures/raw');
    // Canvas first so the vault gets the Obsidian artifact even if image fails.
    await vault.writeText(canvasPath, canvasJson);
    await vault.writeBytes(rawImagePath, imageBytes);

    final slash = canvasPath.lastIndexOf('/');
    final fileName =
        slash == -1 ? canvasPath : canvasPath.substring(slash + 1);
    return BotInboxWriteResult(
      relativePath: canvasPath,
      fileName: fileName,
      folder: folder,
      rawImagePath: rawImagePath,
      pageId: pageId,
    );
  }

  /// Collision-safe vault-relative path: `folder/stem.ext`, then `stem-2`…
  static Future<String> uniqueRelativePath({
    required VaultFs vault,
    required String folder,
    required String stem,
    required String extension,
  }) async {
    final dir = normalizeVaultFolder(folder) ?? defaultFolder;
    final ext = _sanitizeExtension(extension);
    var candidate = joinVaultRelative(dir, '$stem.$ext');
    if (!await vault.exists(candidate)) return candidate;
    for (var n = 2; n <= 99; n++) {
      candidate = joinVaultRelative(dir, '$stem-$n.$ext');
      if (!await vault.exists(candidate)) return candidate;
    }
    throw StateError(
      'Could not find a free filename for $stem.$ext in $dir',
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
