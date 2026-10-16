import 'dart:convert';

import '../capture/page_id.dart';
import '../capture/pending_capture.dart';
import '../ocr/ocr_client.dart';
import '../symbols/symbol_models.dart';
import '../symbols/symbol_router.dart';
import '../writers/canvas_writer.dart';
import '../writers/link_writer.dart';
import '../writers/markdown_writer.dart';
import 'daily_note_path.dart';
import 'daily_tasks_appender.dart';
import 'vault_fs.dart';

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
}

class CommitResult {
  const CommitResult({
    required this.pageId,
    required this.rawImagePath,
    required this.meaningPath,
    required this.symbolId,
    this.notePath,
    this.canvasPath,
    this.dailyNotePath,
  });

  final String pageId;
  final String rawImagePath;
  final String meaningPath;
  final String symbolId;
  final String? notePath;
  final String? canvasPath;
  final String? dailyNotePath;

  String get primaryPath =>
      notePath ?? canvasPath ?? dailyNotePath ?? rawImagePath;
}

/// Writes raw capture + routed vault artifacts through [VaultFs].
class CommitPipeline {
  CommitPipeline({
    required VaultFs vault,
    SymbolRouter? router,
    MarkdownWriter markdownWriter = const MarkdownWriter(),
    CanvasWriter canvasWriter = const CanvasWriter(),
    LinkWriter linkWriter = const LinkWriter(),
    DailyNotePathResolver dailyPathResolver = const DailyNotePathResolver(),
    DailyTasksAppender dailyAppender = const DailyTasksAppender(),
    DailyNoteSettings dailyNoteSettings = const DailyNoteSettings(),
  })  : _vault = vault,
        _router = router ?? SymbolRouter(),
        _markdown = markdownWriter,
        _canvas = canvasWriter,
        _links = linkWriter,
        _dailyPaths = dailyPathResolver,
        _dailyAppender = dailyAppender,
        _dailySettings = dailyNoteSettings;

  final VaultFs _vault;
  final SymbolRouter _router;
  final MarkdownWriter _markdown;
  final CanvasWriter _canvas;
  final LinkWriter _links;
  final DailyNotePathResolver _dailyPaths;
  final DailyTasksAppender _dailyAppender;
  final DailyNoteSettings _dailySettings;

  Future<CommitResult> commit(CommitInput input) async {
    final capture = input.capture;
    final route = _router.routeById(input.symbolId);
    final rawImagePath = capture.rawImagePath;
    final meaningPath = capture.meaningPath;

    await _vault.writeBytes(rawImagePath, capture.imageBytes);
    await _vault.writeText(
      meaningPath,
      _meaningJson(capture.meaning, route.symbol, capture.pageId),
    );

    if (route.isDailyTasks) {
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
        meaningPath: meaningPath,
        symbolId: route.symbol.id,
        dailyNotePath: dailyPath,
      );
    }

    if (route.isCanvas) {
      final slug = slugify(input.title);
      final canvasPath =
          '${_router.noteRelativeDir(route)}/${capture.pageId}-$slug.canvas';
      final textNodes =
          CanvasWriter.nodesFromRegions(capture.meaning.regions);
      final edges = CanvasWriter.heuristicEdges(textNodes);
      final doc = _canvas.buildVisualCanvas(
        sourceImage: rawImagePath,
        textNodes: textNodes,
        edges: edges,
        inkGhost: input.inkGhost,
      );
      await _vault.writeText(canvasPath, _canvas.writeJson(doc));
      // Re-write meaning with ink_ghost flag once we know the route.
      await _vault.writeText(
        meaningPath,
        _meaningJson(
          capture.meaning,
          route.symbol,
          capture.pageId,
          inkGhost: input.inkGhost,
        ),
      );
      return CommitResult(
        pageId: capture.pageId,
        rawImagePath: rawImagePath,
        meaningPath: meaningPath,
        symbolId: route.symbol.id,
        canvasPath: canvasPath,
      );
    }

    // markdown / inbox
    final slug = slugify(input.title);
    final notePath =
        '${_router.noteRelativeDir(route)}/${capture.pageId}-$slug.md';
    final fmLinks = _links.frontmatterLinks(input.links);
    final linked = _links.linkedSection(input.links);
    final body = linked.isEmpty
        ? input.noteBody
        : '${input.noteBody.trim()}\n\n$linked';

    final md = _markdown.write(
      MarkdownNoteDraft(
        frontmatter: NoteFrontmatter(
          type: route.symbol.id,
          symbol: route.symbol.id,
          glyph: route.symbol.primaryGlyph,
          pageId: capture.pageId,
          capturedAt: capture.capturedAt,
          sourceImage: rawImagePath,
          meaning: meaningPath,
          ocrConfidence: _avgConfidence(capture.meaning.regions),
          links: fmLinks,
        ),
        noteBody: body,
        ocrDraft: capture.ocrDraft,
      ),
    );
    await _vault.writeText(notePath, md);

    return CommitResult(
      pageId: capture.pageId,
      rawImagePath: rawImagePath,
      meaningPath: meaningPath,
      symbolId: route.symbol.id,
      notePath: notePath,
    );
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

  static String _meaningJson(
    MeaningResult meaning,
    PackSymbol symbol,
    String pageId, {
    bool? inkGhost,
  }) {
    final map = <String, Object?>{
      'page_id': pageId,
      'symbol': symbol.id,
      'glyph': meaning.detectedGlyph,
      'page_genre': meaning.pageGenre,
      'regions': [
        for (final r in meaning.regions)
          {
            'id': r.id,
            'text': r.text,
            'confidence': r.confidence,
            if (r.bbox != null) 'bbox': r.bbox,
          },
      ],
      'raw': meaning.rawJson,
      'stem': PageId.shortStem(pageId),
      if (inkGhost != null) 'ink_ghost': inkGhost,
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }
}
