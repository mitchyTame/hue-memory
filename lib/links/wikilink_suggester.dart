import '../vault/vault_fs.dart';
import '../writers/link_writer.dart' show LinkPick;

/// A vault markdown note that can be suggested as a wikilink target.
class VaultNoteRef {
  const VaultNoteRef({
    required this.path,
    required this.title,
    this.snippet = '',
  });

  /// Vault-relative path without mandatory `.md`.
  final String path;

  /// Human title (basename / heading).
  final String title;

  /// Short body excerpt used for lexical matching.
  final String snippet;

  LinkPick toPick() => LinkPick(targetPath: path, displayTitle: title);
}

/// Lexical vault index → suggested `[[wikilinks]]` for a new note.
///
/// No extra AI call — matches tokens from the new note against existing note
/// titles and short snippets (e.g. "Chunking" ↔ a note that mentions it).
class WikilinkSuggester {
  const WikilinkSuggester();

  static const int defaultMaxSuggestions = 5;
  static const int maxIndexPerFolder = 80;
  static const int snippetChars = 480;

  /// Walk [folders] one level deep and index `.md` notes.
  Future<List<VaultNoteRef>> indexVault(
    VaultFs vault, {
    required List<String> folders,
  }) async {
    final out = <VaultNoteRef>[];
    final seen = <String>{};
    for (final folder in folders) {
      final root = folder.trim().replaceAll(RegExp(r'^/+|/+$'), '');
      if (root.isEmpty) continue;
      if (!await vault.exists(root)) continue;
      final names = await vault.list(root);
      var counted = 0;
      for (final name in names) {
        if (!name.toLowerCase().endsWith('.md')) continue;
        if (counted >= maxIndexPerFolder) break;
        final relative = '$root/$name';
        final pathKey = _stripMd(relative);
        if (!seen.add(pathKey)) continue;
        try {
          final text = await vault.readText(relative);
          out.add(_refFromNote(pathKey, name, text));
          counted++;
        } catch (_) {
          // Skip unreadable notes.
        }
      }
    }
    return out;
  }

  /// Rank vault notes that lexically match [haystack] (title + body + OCR).
  List<LinkPick> suggest({
    required String haystack,
    required List<VaultNoteRef> index,
    List<LinkPick> existing = const [],
    int maxSuggestions = defaultMaxSuggestions,
  }) {
    final tokens = _tokens(haystack);
    if (tokens.isEmpty || index.isEmpty) {
      return List<LinkPick>.from(existing);
    }

    final existingNorm = {
      for (final e in existing) _stripMd(e.targetPath),
    };

    final scored = <({VaultNoteRef note, int score})>[];
    for (final note in index) {
      final path = _stripMd(note.path);
      if (existingNorm.contains(path)) continue;
      final score = _score(tokens, note);
      if (score <= 0) continue;
      scored.add((note: note, score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.note.title.compareTo(b.note.title);
    });

    final picks = <LinkPick>[
      ...existing,
      for (final s in scored.take(maxSuggestions)) s.note.toPick(),
    ];
    return picks;
  }

  /// Merge suggestions into [body]: weave `[[Title]]` after the first matching
  /// token when possible; otherwise append a short Related line.
  String insertIntoBody(String body, Iterable<LinkPick> picks) {
    var text = body;
    final related = <String>[];
    for (final pick in picks) {
      final title = (pick.displayTitle ?? _titleFromPath(pick.targetPath))
          .trim();
      if (title.isEmpty) continue;
      final pathKey = _stripMd(pick.targetPath);
      // Prefer bare title link when display matches Obsidian note name.
      final link = '[[$title]]';
      final pathLink = '[[$pathKey]]';
      if (text.contains(link) || text.contains(pathLink)) continue;

      // Weave after a significant title/snippet token already in the body.
      final weaveTokens = _tokens(title)
          .where((t) => t.length >= 5)
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      var wove = false;
      for (final token in weaveTokens) {
        final pattern = RegExp(
          '\\b(${RegExp.escape(token)})\\b',
          caseSensitive: false,
        );
        if (!pattern.hasMatch(text)) continue;
        text = text.replaceFirstMapped(pattern, (m) => '${m[0]} $link');
        wove = true;
        break;
      }
      if (!wove) related.add(link);
    }
    if (related.isEmpty) return text.trimRight();

    final buffer = StringBuffer(text.trimRight())
      ..writeln()
      ..writeln()
      ..writeln('Related: ${related.join(' · ')}');
    return buffer.toString();
  }

  static VaultNoteRef _refFromNote(String path, String fileName, String text) {
    final heading = _firstHeading(text);
    final title = heading ?? _humanizeFileName(fileName);
    final snippet = _snippet(text);
    return VaultNoteRef(path: path, title: title, snippet: snippet);
  }

  static String? _firstHeading(String text) {
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.startsWith('#')) {
        final h = t.replaceFirst(RegExp(r'^#{1,6}\s*'), '').trim();
        if (h.isNotEmpty) return h;
      }
    }
    return null;
  }

  static String _humanizeFileName(String fileName) {
    var base = fileName;
    if (base.toLowerCase().endsWith('.md')) {
      base = base.substring(0, base.length - 3);
    }
    // Strip page-id prefix like 20261016-p7k2-
    base = base.replaceFirst(RegExp(r'^\d{8}[Tt-]?\w*-'), '');
    final words = base.replaceAll(RegExp(r'[-_]+'), ' ').trim();
    if (words.isEmpty) return fileName;
    return words
        .split(RegExp(r'\s+'))
        .map((w) {
          if (w.isEmpty) return w;
          return '${w[0].toUpperCase()}${w.substring(1)}';
        })
        .join(' ');
  }

  static String _snippet(String text) {
    // Drop YAML frontmatter for matching.
    var body = text;
    if (body.startsWith('---')) {
      final end = body.indexOf('\n---', 3);
      if (end > 0) {
        body = body.substring(end + 4);
      }
    }
    body = body.replaceAll(RegExp(r'!\[\[.*?\]\]'), ' ');
    body = body.trim();
    if (body.length <= snippetChars) return body;
    return body.substring(0, snippetChars);
  }

  static int _score(Set<String> haystackTokens, VaultNoteRef note) {
    final titleTokens = _tokens(note.title);
    final snippetTokens = _tokens(note.snippet);
    var score = 0;

    for (final t in titleTokens) {
      if (t.length < 4) continue;
      if (haystackTokens.contains(t)) {
        score += t.length >= 7 ? 12 : 8;
      }
    }
    // Snippet tokens: new note mentions a term that already lives in an
    // older note (e.g. "Chunking" inside [[Working Memory Capacity]]).
    for (final t in snippetTokens) {
      if (t.length < 5) continue;
      if (haystackTokens.contains(t)) {
        score += 3;
      }
    }
    // Bonus when several title tokens hit.
    final titleHits =
        titleTokens.where((t) => t.length >= 4 && haystackTokens.contains(t));
    if (titleHits.length >= 2) score += 15;
    return score;
  }

  static Set<String> _tokens(String raw) {
    final out = <String>{};
    for (final m in RegExp(r"[a-z0-9']{3,}", caseSensitive: false)
        .allMatches(raw.toLowerCase())) {
      final t = m.group(0)!;
      if (_stop.contains(t)) continue;
      out.add(t);
    }
    return out;
  }

  static const Set<String> _stop = {
    'the',
    'and',
    'for',
    'are',
    'but',
    'not',
    'you',
    'all',
    'can',
    'had',
    'her',
    'was',
    'one',
    'our',
    'out',
    'has',
    'his',
    'how',
    'its',
    'may',
    'new',
    'now',
    'old',
    'see',
    'way',
    'who',
    'did',
    'get',
    'let',
    'put',
    'say',
    'she',
    'too',
    'use',
    'from',
    'that',
    'this',
    'with',
    'have',
    'been',
    'were',
    'they',
    'note',
    'page',
    'draft',
    'ocr',
    'type',
    'status',
  };

  static String _stripMd(String path) {
    final trimmed = path.trim();
    if (trimmed.toLowerCase().endsWith('.md')) {
      return trimmed.substring(0, trimmed.length - 3);
    }
    return trimmed;
  }

  static String _titleFromPath(String path) {
    final base = _stripMd(path).split('/').last;
    return _humanizeFileName('$base.md');
  }
}
