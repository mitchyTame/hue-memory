/// Builds Obsidian wikilinks from confirm-UI link picks (no paper `[[…]]`).
class LinkPick {
  const LinkPick({
    required this.targetPath,
    this.displayTitle,
  });

  /// Vault-relative path or note name (without mandatory .md).
  final String targetPath;
  final String? displayTitle;
}

class LinkWriter {
  const LinkWriter();

  /// `[[path]]` or `[[path|title]]`.
  String wikilink(LinkPick pick) {
    final path = _stripMd(pick.targetPath);
    final title = pick.displayTitle?.trim();
    if (title == null || title.isEmpty) {
      return '[[$path]]';
    }
    return '[[$path|$title]]';
  }

  List<String> wikilinks(Iterable<LinkPick> picks) =>
      picks.map(wikilink).toList(growable: false);

  /// YAML-ready list for frontmatter `links:` field.
  List<String> frontmatterLinks(Iterable<LinkPick> picks) => wikilinks(picks);

  /// Optional short body section.
  String linkedSection(Iterable<LinkPick> picks) {
    final links = wikilinks(picks);
    if (links.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('## Linked')
      ..writeln();
    for (final link in links) {
      buffer.writeln('- $link');
    }
    return buffer.toString();
  }

  static String _stripMd(String path) {
    final trimmed = path.trim();
    if (trimmed.toLowerCase().endsWith('.md')) {
      return trimmed.substring(0, trimmed.length - 3);
    }
    return trimmed;
  }
}
