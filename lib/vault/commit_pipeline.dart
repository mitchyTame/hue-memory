import 'dart:typed_data';

import '../capture/pending_capture.dart';
import '../links/wikilink_suggester.dart';
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
    this.weaveSuggestedWikilinks = true,
  });

  final PendingCapture capture;
  final String symbolId;
  final String title;
  final String noteBody;
  final List<LinkPick> links;

  /// Overrides [PendingCapture.taskLines] when non-null (daily-tasks).
  final List<String>? taskLines;

  /// Visual / canvas only — page photo under editable nodes (default on).
  final bool inkGhost;

  /// Edited mindmap labels from confirm (△). Falls back to capture regions.
  final List<OcrRegion>? regions;

  /// When true, weave suggested `[[wikilinks]]` into the markdown body.
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

/// Writes raw capture + routed vault artifacts through [VaultFs].
///
/// Vault artifacts are **`.md` / `.canvas` / images only** — never `*.json`.
class CommitPipeline {
  CommitPipeline({
    required VaultFs vault,
    SymbolRouter? router,
    MarkdownWriter markdownWriter = const MarkdownWriter(),
    CanvasWriter canvasWriter = const CanvasWriter(),
    LinkWriter linkWriter = const LinkWriter(),
    TagBuilder tagBuilder = const TagBuilder(),
    WikilinkSuggester wikilinkSuggester = const WikilinkSuggester(),
    DailyNotePathResolver dailyPathResolver = const DailyNotePathResolver(),
    DailyTasksAppender dailyAppender = const DailyTasksAppender(),
    DailyNoteSettings dailyNoteSettings = const DailyNoteSettings(),
  })  : _vault = vault,
        _router = router ?? SymbolRouter(),
        _markdown = markdownWriter,
        _canvas = canvasWriter,
        _links = linkWriter,
        _tags = tagBuilder,
        _wikilinks = wikilinkSuggester,
        _dailyPaths = dailyPathResolver,
        _dailyAppender = dailyAppender,
        _dailySettings = dailyNoteSettings;

  final VaultFs _vault;
  final SymbolRouter _router;
  final MarkdownWriter _markdown;
  final CanvasWriter _canvas;
  final LinkWriter _links;
  final TagBuilder _tags;
  final WikilinkSuggester _wikilinks;
  final DailyNotePathResolver _dailyPaths;
  final DailyTasksAppender _dailyAppender;
  final DailyNoteSettings _dailySettings;

  Future<CommitResult> commit(CommitInput input) async {
    final capture = input.capture;
    final route = _router.routeById(input.symbolId);
    final rawImagePath = capture.rawImagePath;

    // △ / visual must always produce JSON Canvas — never a markdown note that
    // embeds the photo (that reads as "image with OCR text" in Obsidian).
    // Force canvas even if a custom pack mis-labels visual as markdown.
    final writeCanvas = route.isCanvas || route.symbol.id == 'visual';

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
    await _vault.writeBytes(rawImagePath, capture.imageBytes);
    final slug = slugify(input.title);
    final notePath = joinVaultRelative(
      _router.noteRelativeDir(route),
      '${capture.pageId}-$slug.md',
    );
    final fmLinks = _links.frontmatterLinks(input.links);
    final linked = _links.linkedSection(input.links);
    var noteBody = input.noteBody;
    if (input.weaveSuggestedWikilinks && input.links.isNotEmpty) {
      noteBody = _wikilinks.insertIntoBody(noteBody, input.links);
    }
    final body = linked.isEmpty ? noteBody : '${noteBody.trim()}\n\n$linked';

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
          links: fmLinks,
          threadTick: capture.meaning.threadTick,
        ),
        noteBody: body,
        ocrDraft: capture.ocrDraft,
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

  /// △ commit: `.canvas` (JSON Canvas 1.0) + unaltered raw photo.
  ///
  /// - Primary artifact is `mindmaps/<pageId>-<slug>.canvas` (never `.json.canvas`)
  /// - Ink-ghost: file node → [rawImagePath]; labels are separate text nodes
  /// - Vault image bytes are exactly [PendingCapture.imageBytes] (no burn-in)
  /// - No companion `.md` for the page
  Future<CommitResult> _commitVisualCanvas({
    required CommitInput input,
    required RouteResult route,
    required String rawImagePath,
  }) async {
    final capture = input.capture;
    final folder = route.folder?.trim().isNotEmpty == true
        ? route.folder!
        : 'mindmaps';
    final slug = slugify(input.title);
    final canvasPath = joinVaultRelative(
      normalizeVaultFolder(folder) ?? 'mindmaps',
      '${capture.pageId}-$slug.canvas',
    );
    _assertCanvasPath(canvasPath);

    final regionList = input.regions ?? capture.meaning.regions;
    var textNodes = CanvasWriter.nodesFromRegions(regionList);
    if (textNodes.isEmpty) {
      // Still ship a real Canvas with an editable card — never PNG burn-in.
      final label = input.title.trim().isEmpty ? 'Untitled' : input.title.trim();
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
    final edges = CanvasWriter.heuristicEdges(textNodes);
    final nested = _tags.fromCanvasNodes(textNodes, edges: edges);
    final doc = _canvas.buildVisualCanvas(
      sourceImage: rawImagePath,
      textNodes: textNodes,
      edges: edges,
      inkGhost: input.inkGhost,
      hierarchicalTags: _tags.tagLine(nested),
    );
    _assertInkGhostDocument(doc, rawImagePath: rawImagePath);

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
    if (textNodes.isEmpty) {
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
