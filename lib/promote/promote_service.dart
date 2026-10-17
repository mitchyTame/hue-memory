import '../symbols/symbol_models.dart';
import '../vault/commit_pipeline.dart';
import '../vault/vault_fs.dart';
import '../vault/vault_paths.dart';
import '../writers/markdown_writer.dart';
import 'own_words_gate.dart';

/// A fleeting note waiting for the weekly promote ritual.
class PromoteCandidate {
  const PromoteCandidate({
    required this.path,
    required this.title,
    required this.body,
    required this.pageId,
    this.sourceImage,
    this.glyph = '∼',
    this.capturedAt,
  });

  final String path;
  final String title;
  final String body;
  final String pageId;
  final String? sourceImage;
  final String glyph;
  final DateTime? capturedAt;
}

class PromoteResult {
  const PromoteResult({
    required this.permanentPath,
    required this.fleetingPath,
  });

  final String permanentPath;
  final String fleetingPath;
}

/// Lists fleeting notes and promotes them to permanents with an own-words gate.
///
/// Folder names come from the active pack (∼ fleeting / ◇ permanent symbols).
class PromoteService {
  PromoteService({
    MarkdownWriter markdownWriter = const MarkdownWriter(),
    this.fleetingFolder = defaultFleetingFolder,
    this.permanentFolder = defaultPermanentFolder,
  }) : _markdown = markdownWriter;

  static const defaultFleetingFolder = 'fleeting';
  static const defaultPermanentFolder = 'permanent';

  final MarkdownWriter _markdown;

  /// Vault-relative folder for ∼ fleeting notes.
  final String fleetingFolder;

  /// Vault-relative folder for ◇ permanents.
  final String permanentFolder;

  /// Resolve folders from an active [SymbolPack] (falls back to ZK defaults).
  factory PromoteService.forPack(
    SymbolPack pack, {
    MarkdownWriter markdownWriter = const MarkdownWriter(),
  }) {
    final fleeting = normalizeVaultFolder(pack.byId('fleeting')?.folder);
    final permanent = normalizeVaultFolder(pack.byId('permanent')?.folder);
    return PromoteService(
      markdownWriter: markdownWriter,
      fleetingFolder: fleeting ?? defaultFleetingFolder,
      permanentFolder: permanent ?? defaultPermanentFolder,
    );
  }

  /// Immediate children of [fleetingFolder] that look like notes.
  Future<List<PromoteCandidate>> listFleeting(VaultFs vault) async {
    if (!await vault.exists(fleetingFolder)) return const [];
    final names = await vault.list(fleetingFolder);
    final out = <PromoteCandidate>[];
    for (final name in names) {
      if (!name.endsWith('.md')) continue;
      final path = '$fleetingFolder/$name';
      final text = await vault.readText(path);
      final parsed = parseFleetingNote(path, text);
      if (parsed != null) out.add(parsed);
    }
    out.sort((a, b) => b.path.compareTo(a.path));
    return out;
  }

  /// Promote [source] → [permanentFolder] with own-words body.
  Future<PromoteResult> promote({
    required VaultFs vault,
    required PromoteCandidate source,
    required String title,
    required String ownWords,
    bool keepOcrShallow = false,
    DateTime? now,
  }) async {
    final gate = OwnWordsGate.validate(
      ownWords: ownWords,
      sourceBody: source.body,
      keepOcrShallow: keepOcrShallow,
    );
    if (gate != null) {
      throw StateError(gate);
    }

    final when = now ?? DateTime.now().toUtc();
    final permanentPath = joinVaultRelative(
      permanentFolder,
      '${CommitPipeline.fileStemFromTitle(title)}.md',
    );
    if (await vault.exists(permanentPath)) {
      throw VaultNameCollisionException(permanentPath);
    }
    final body = keepOcrShallow && ownWords.trim().isEmpty
        ? source.body.trim()
        : ownWords.trim();

    final md = _markdown.write(
      MarkdownNoteDraft(
        frontmatter: NoteFrontmatter(
          type: 'permanent',
          symbol: 'permanent',
          glyph: '◇',
          pageId: source.pageId,
          capturedAt: source.capturedAt ?? when,
          sourceImage: source.sourceImage ?? '',
          status: keepOcrShallow ? 'promoted_shallow' : 'promoted',
          links: ['[[${_wikilinkTarget(source.path)}]]'],
        ),
        noteBody: body,
        ocrDraft: keepOcrShallow ? '' : source.body,
      ),
    );
    await vault.writeText(permanentPath, md);

    // Stamp the fleeting note so the ritual does not re-offer it blindly.
    final stamped = _stampFleetingPromoted(
      await vault.readText(source.path),
      permanentPath: permanentPath,
    );
    await vault.writeText(source.path, stamped);

    return PromoteResult(
      permanentPath: permanentPath,
      fleetingPath: source.path,
    );
  }

  /// Parse a fleeting markdown file into a candidate (best-effort YAML).
  static PromoteCandidate? parseFleetingNote(String path, String text) {
    final fm = _frontmatter(text);
    if (fm != null) {
      final status = fm['status'] ?? '';
      if (status.contains('promoted')) return null;
      final type = fm['type'] ?? fm['symbol'] ?? '';
      if (type.isNotEmpty && type != 'fleeting') return null;
    }

    final pageId = fm?['page_id'] ?? _pageIdFromPath(path);
    if (pageId == null || pageId.isEmpty) return null;

    final body = _noteSection(text);
    final title = _titleFrom(path, body, fm?['title']);
    DateTime? captured;
    final rawAt = fm?['captured_at'];
    if (rawAt != null) {
      captured = DateTime.tryParse(rawAt);
    }

    return PromoteCandidate(
      path: path,
      title: title,
      body: body,
      pageId: pageId,
      sourceImage: fm?['source_image'],
      glyph: fm?['glyph'] ?? '∼',
      capturedAt: captured,
    );
  }

  static String _stampFleetingPromoted(
    String text, {
    required String permanentPath,
  }) {
    final link = '[[${_wikilinkTarget(permanentPath)}]]';
    if (text.startsWith('---')) {
      final end = text.indexOf('\n---', 3);
      if (end != -1) {
        final head = text.substring(0, end);
        final rest = text.substring(end);
        var patched = head;
        if (RegExp(r'^status:\s*.+$', multiLine: true).hasMatch(head)) {
          patched = head.replaceFirst(
            RegExp(r'^status:\s*.+$', multiLine: true),
            'status: promoted',
          );
        } else {
          patched = '$head\nstatus: promoted';
        }
        if (!patched.contains('promoted_to:')) {
          patched = '$patched\npromoted_to: "$link"';
        }
        return '$patched$rest';
      }
    }
    return '$text\n\n<!-- promoted_to: $link -->\n';
  }

  static String _wikilinkTarget(String path) {
    var t = path;
    if (t.endsWith('.md')) t = t.substring(0, t.length - 3);
    return t;
  }

  static String? _pageIdFromPath(String path) {
    final base = path.split('/').last;
    final m = RegExp(r'^(\d{8}-[a-z0-9]+)').firstMatch(base);
    return m?.group(1);
  }

  static String _titleFrom(String path, String body, String? fmTitle) {
    if (fmTitle != null && fmTitle.trim().isNotEmpty) return fmTitle.trim();
    final first = body
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (first.isNotEmpty) {
      return first.length <= 48 ? first : '${first.substring(0, 45)}…';
    }
    final base = path.split('/').last.replaceAll('.md', '');
    final dash = base.indexOf('-', 9); // after YYYYMMDD-
    if (dash != -1 && dash < base.length - 1) {
      return base.substring(dash + 1).replaceAll('-', ' ');
    }
    return base;
  }

  static Map<String, String>? _frontmatter(String text) {
    if (!text.startsWith('---')) return null;
    final end = text.indexOf('\n---', 3);
    if (end == -1) return null;
    final block = text.substring(4, end).trim();
    final map = <String, String>{};
    for (final line in block.split('\n')) {
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final key = line.substring(0, i).trim();
      var val = line.substring(i + 1).trim();
      if (val.startsWith('"') && val.endsWith('"') && val.length >= 2) {
        val = val.substring(1, val.length - 1);
      }
      map[key] = val;
    }
    return map;
  }

  static String _noteSection(String text) {
    final noteIdx = text.indexOf('## Note');
    if (noteIdx != -1) {
      var body = text.substring(noteIdx + '## Note'.length).trimLeft();
      final next = RegExp(r'^##\s', multiLine: true).firstMatch(body);
      if (next != null) {
        body = body.substring(0, next.start).trim();
      }
      // Drop leading image embed.
      body = body.replaceFirst(RegExp(r'^!\[\[[^\]]+\]\]\s*'), '').trim();
      return body;
    }
    if (text.startsWith('---')) {
      final end = text.indexOf('\n---', 3);
      if (end != -1) {
        var body = text.substring(end + 4).trim();
        body = body.replaceFirst(RegExp(r'^!\[\[[^\]]+\]\]\s*'), '').trim();
        return body;
      }
    }
    return text.trim();
  }
}
