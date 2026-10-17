import 'dart:typed_data';

import '../capture/pending_capture.dart';
import '../gemini/capture_coordinator.dart';
import '../gemini/obsidian_canvas_from_gemini.dart';
import '../ocr/ocr_client.dart';
import '../symbols/symbol_router.dart';
import '../writers/canvas_writer.dart';
import '../writers/link_writer.dart';
import '../writers/markdown_writer.dart';
import '../writers/tag_builder.dart';
import 'daily_note_path.dart';
import 'daily_tasks_appender.dart';
import 'vault_fs.dart';
import 'vault_paths.dart';

/// Inputs confirmed on the photo before vault write.
class CommitInput {
  const CommitInput({
    required this.capture,
    required this.symbolId,
    required this.title,
    required this.noteBody,
    this.links = const [],
    this.taskLines,
    this.inkGhost = true,
    this.regions,
    @Deprecated('Personal v2: Mitch links in Obsidian — ignored on commit')
    this.weaveSuggestedWikilinks = false,
  });

  final PendingCapture capture;
  final String symbolId;
  final String title;
  final String noteBody;

  /// Unused on commit (kept for API compat). Links are not written to vault.
  final List<LinkPick> links;

  /// Overrides [PendingCapture.taskLines] when non-null (daily-tasks).
  final List<String>? taskLines;

  /// Visual / canvas only — page photo under editable nodes (default on).
  final bool inkGhost;

  /// Edited mindmap labels from confirm (△). Falls back to capture regions.
  final List<OcrRegion>? regions;

  /// Ignored — personal v2 never auto-weaves `[[wikilinks]]`.
  @Deprecated('Personal v2: Mitch links in Obsidian')
  final bool weaveSuggestedWikilinks;
}

class CommitResult {
  const CommitResult({
    required this.pageId,
    required this.rawImagePath,
    required this.symbolId,
    this.notePath,
    this.canvasPath,
    this.dailyNotePath,
  });

  final String pageId;
  final String rawImagePath;
  final String symbolId;
  final String? notePath;
  final String? canvasPath;
  final String? dailyNotePath;

  String get primaryPath =>
      notePath ?? canvasPath ?? dailyNotePath ?? rawImagePath;
}

/// Note/canvas basename already exists — Mitch must rename (no auto-suffix).
class VaultNameCollisionException implements Exception {
  const VaultNameCollisionException(this.path);

  final String path;

  String get readable => 'Filename already exists, please adjust';

  @override
  String toString() => readable;
}

/// Writes raw capture + routed vault artifacts through [VaultFs].
///
/// Vault artifacts are **`.md` / `.canvas` / images only** — never `*.json`.
class CommitPipeline {
  CommitPipeline({
    required VaultFs vault,
    SymbolRouter? router,
    MarkdownWriter markdownWriter = const MarkdownWriter(),
    CanvasWriter canvasWriter = const CanvasWriter(),
    TagBuilder tagBuilder = const TagBuilder(),
    DailyNotePathResolver dailyPathResolver = const DailyNotePathResolver(),
    DailyTasksAppender dailyAppender = const DailyTasksAppender(),
    DailyNoteSettings dailyNoteSettings = const DailyNoteSettings(),
  })  : _vault = vault,
        _router = router ?? SymbolRouter(),
        _markdown = markdownWriter,
        _canvas = canvasWriter,
        _tags = tagBuilder,
        _dailyPaths = dailyPathResolver,
        _dailyAppender = dailyAppender,
        _dailySettings = dailyNoteSettings;

  final VaultFs _vault;
  final SymbolRouter _router;
  final MarkdownWriter _markdown;
  final CanvasWriter _canvas;
  final TagBuilder _tags;
  final DailyNotePathResolver _dailyPaths;
  final DailyTasksAppender _dailyAppender;
  final DailyNoteSettings _dailySettings;

  Future<CommitResult> commit(CommitInput input) async {
    final capture = input.capture;
    final route = _router.routeById(input.symbolId);
    final rawImagePath = capture.rawImagePath;

    // △ / visual / photo_only must always produce JSON Canvas — never a
    // markdown note that embeds the photo (reads as OCR dump in Obsidian).
    final genre = capture.meaning.pageGenre;
    final writeCanvas = route.isCanvas ||
        route.symbol.id == 'visual' ||
        genre == 'visual' ||
        genre == 'photo_only';

    if (route.isDailyTasks) {
      await _vault.writeBytes(rawImagePath, capture.imageBytes);
      final dailyPath = _dailyPaths.resolve(
        _dailySettings,
        date: capture.capturedAt,
      );
      final existing =
          await _vault.exists(dailyPath) ? await _vault.readText(dailyPath) : null;
      final tasks = input.taskLines ?? capture.taskLines;
      final body = _dailyAppender.apply(
        existingBody: existing,
        pageId: capture.pageId,
        tasks: tasks,
        date: capture.capturedAt,
        sectionHeading: route.section ?? '## Tasks',
      );
      await _vault.writeText(dailyPath, body);
      return CommitResult(
        pageId: capture.pageId,
        rawImagePath: rawImagePath,
        symbolId: route.symbol.id,
        dailyNotePath: dailyPath,
      );
    }

    if (writeCanvas) {
      return _commitVisualCanvas(
        input: input,
        route: route,
        rawImagePath: rawImagePath,
      );
    }

    // markdown / inbox — never taken for visual / △
    // Basename is exactly Mitch's title (sanitized) — no pageId/date suffix.
    final notePath = joinVaultRelative(
      _router.noteRelativeDir(route),
      '${fileStemFromTitle(input.title)}.md',
    );
    await _assertNameAvailable(notePath);
    await _vault.writeBytes(rawImagePath, capture.imageBytes);
    // Personal v2: no auto/suggested [[wikilinks]] — Mitch links in Obsidian.
    final md = _markdown.write(
      MarkdownNoteDraft(
        frontmatter: NoteFrontmatter(
          type: route.symbol.id,
          symbol: route.symbol.id,
          glyph: route.symbol.primaryGlyph,
          pageId: capture.pageId,
          capturedAt: capture.capturedAt,
          sourceImage: rawImagePath,
          ocrConfidence: _avgConfidence(capture.meaning.regions),
          links: const [],
          threadTick: capture.meaning.threadTick,
        ),
        noteBody: input.noteBody,
      ),
    );
    await _vault.writeText(notePath, md);

    return CommitResult(
      pageId: capture.pageId,
      rawImagePath: rawImagePath,
      symbolId: route.symbol.id,
      notePath: notePath,
    );
  }

  /// △ / photo_only commit: `.canvas` (JSON Canvas 1.0) + unaltered raw photo.
  ///
  /// - Primary artifact is `{folder}/{title}.canvas` (never `.json.canvas`)
  /// - Ink-ghost: file node → [rawImagePath] **above** the idea graph
  /// - Vault image bytes are exactly [PendingCapture.imageBytes] (no burn-in)
  /// - No companion `.md` for the page
  /// - No `*.json` sidecars
  Future<CommitResult> _commitVisualCanvas({
    required CommitInput input,
    required RouteResult route,
    required String rawImagePath,
  }) async {
    final capture = input.capture;
    final folder = route.folder?.trim().isNotEmpty == true
        ? route.folder!
        : 'mindmaps';
    final canvasPath = joinVaultRelative(
      normalizeVaultFolder(folder) ?? 'mindmaps',
      '${fileStemFromTitle(input.title)}.canvas',
    );
    _assertCanvasPath(canvasPath);
    await _assertNameAvailable(canvasPath);

    final photoOnly = capture.meaning.pageGenre == 'photo_only' ||
        capture.meaning.rawJson['ghost_only'] == true;

    late final CanvasDocument doc;
    if (photoOnly) {
      doc = _canvas.buildVisualCanvas(
        sourceImage: rawImagePath,
        textNodes: const [],
        edges: const [],
        inkGhost: input.inkGhost,
        allowEmptyText: true,
      );
      _assertInkGhostDocument(
        doc,
        rawImagePath: rawImagePath,
        allowEmptyText: true,
      );
    } else {
      final regionList = input.regions ?? capture.meaning.regions;
      // Prefer Gemini Obsidian-shaped nodes/edges when present.
      final fromGemini = CaptureCoordinator.canvasFromMeaning(
        MeaningResult(
          detectedGlyph: capture.meaning.detectedGlyph,
          regions: regionList,
          pageGenre: capture.meaning.pageGenre,
          threadTick: capture.meaning.threadTick,
          rawJson: capture.meaning.rawJson,
        ),
      );

      List<CanvasNode> textNodes;
      List<CanvasEdge> edges;
      if (fromGemini != null) {
        textNodes = ObsidianCanvasFromGemini.applyLabelEdits(
          textNodes: fromGemini.nodes,
          edited: regionList,
        );
        // Keep Gemini edges as-is — no ensureConnected / ring tidy.
        edges = fromGemini.edges;
        doc = _canvas.buildDiagramCanvas(
          sourceImage: rawImagePath,
          textNodes: textNodes,
          edges: edges,
          inkGhost: input.inkGhost,
          hierarchicalTags: _tags.tagLine(
            _tags.fromCanvasNodes(textNodes, edges: edges),
          ),
        );
      } else {
        textNodes = CanvasWriter.nodesFromRegions(regionList);
        if (textNodes.isEmpty) {
          final label =
              input.title.trim().isEmpty ? 'Untitled' : input.title.trim();
          textNodes = [
            CanvasNode(
              id: 'n1',
              type: 'text',
              text: label,
              x: CanvasWriter.defaultImageX + 24,
              y: CanvasWriter.defaultImageY + 24,
              width: 220,
              height: 64,
            ),
          ];
        }
        // No invented hub–spoke layout — Obsidian owns further arrange.
        edges = const <CanvasEdge>[];
        final nested = _tags.fromCanvasNodes(textNodes, edges: edges);
        doc = _canvas.buildDiagramCanvas(
          sourceImage: rawImagePath,
          textNodes: textNodes,
          edges: edges,
          inkGhost: input.inkGhost,
          hierarchicalTags: _tags.tagLine(nested),
        );
      }
      _assertInkGhostDocument(doc, rawImagePath: rawImagePath);
    }

    // Write canvas first so the vault always gets the real Obsidian artifact
    // even if a later image write fails mid-flight.
    final canvasJson = _canvas.writeJson(doc);
    await _vault.writeText(canvasPath, canvasJson);

    // Unaltered capture — confirm UI overlays never reach disk.
    final original = Uint8List.fromList(capture.imageBytes);
    await _vault.writeBytes(rawImagePath, original);
    final written = await _vault.readBytes(rawImagePath);
    if (!_bytesEqual(written, original)) {
      throw StateError(
        'Vault image was altered on write — △ requires a clean capture under '
        '$rawImagePath (no burned-in text)',
      );
    }

    return CommitResult(
      pageId: capture.pageId,
      rawImagePath: rawImagePath,
      symbolId: route.symbol.id,
      canvasPath: canvasPath,
      // notePath intentionally null — △ never writes companion .md
    );
  }

  Future<void> _assertNameAvailable(String relativePath) async {
    if (await _vault.exists(relativePath)) {
      throw VaultNameCollisionException(relativePath);
    }
  }

  static void _assertCanvasPath(String canvasPath) {
    final base = canvasPath.split('/').last.toLowerCase();
    if (!base.endsWith('.canvas') ||
        base.endsWith('.json.canvas') ||
        base.endsWith('.canvas.json') ||
        base.contains('.json.')) {
      throw ArgumentError(
        '△ canvas path must end with .canvas only (got $canvasPath)',
      );
    }
    assertVaultWriteAllowed(canvasPath);
  }

  static void _assertInkGhostDocument(
    CanvasDocument doc, {
    required String rawImagePath,
    bool allowEmptyText = false,
  }) {
    final fileNodes = doc.nodes.where((n) => n.type == 'file').toList();
    final textNodes = doc.nodes.where((n) => n.type == 'text').toList();
    if (fileNodes.isEmpty) {
      throw StateError('△ canvas missing ink-ghost file node');
    }
    if (fileNodes.first.file != rawImagePath) {
      throw StateError(
        '△ file node must point at $rawImagePath (got ${fileNodes.first.file})',
      );
    }
    if (!allowEmptyText && textNodes.isEmpty) {
      throw StateError(
        '△ canvas needs at least one editable text node (not burned into PNG)',
      );
    }
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Basename stem from Mitch's typed title — casing/spaces kept; no pageId.
  ///
  /// Strips a trailing `.md` / `.canvas` if typed; replaces path-illegal chars.
  static String fileStemFromTitle(String title) {
    var s = title.trim();
    if (s.isEmpty) return 'Untitled';
    s = s.replaceFirst(RegExp(r'\.(md|canvas)$', caseSensitive: false), '');
    s = s.trim();
    s = s.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]+'), '-');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
    if (s.isEmpty) return 'Untitled';
    return s.length <= 120 ? s : s.substring(0, 120).trim();
  }

  /// Lowercase kebab slug (legacy / promote helpers). Prefer [fileStemFromTitle]
  /// for vault note/canvas basenames.
  static String slugify(String title) {
    final lower = title.toLowerCase().trim();
    final replaced = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final collapsed = replaced.replaceAll(RegExp(r'-+'), '-');
    final trimmed = collapsed.replaceAll(RegExp(r'^-|-$'), '');
    if (trimmed.isEmpty) return 'note';
    return trimmed.length <= 48 ? trimmed : trimmed.substring(0, 48);
  }

  static double? _avgConfidence(List<OcrRegion> regions) {
    if (regions.isEmpty) return null;
    final sum = regions.fold<double>(0, (a, r) => a + r.confidence);
    return sum / regions.length;
  }
}
