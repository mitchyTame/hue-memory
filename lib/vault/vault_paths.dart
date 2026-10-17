import 'package:path/path.dart' as p;

/// Soft probe / write-check at vault **root** (a file — never a `hue-memory/` dir).
const String kVaultWriteCheckRelative = '.hue-memory-write-check';

/// Probe note at vault root (`.md` only — no nested app-name folder).
const String kVaultProbeRelative = 'hue-memory-probe.md';

/// Normalize a vault-relative folder from pack settings.
///
/// - trim whitespace
/// - strip leading/trailing `/`
/// - collapse duplicate `/`
/// - reject `..` escapes
/// - drop accidental leading junk segments (`hue-memory`, `pack`, `packs`,
///   `symbol-journal`) that are app scaffolding, not Mitch-configured folders
String? normalizeVaultFolder(String? raw) {
  if (raw == null) return null;
  var s = raw.trim().replaceAll('\\', '/');
  if (s.isEmpty) return null;
  s = s.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
  s = s.replaceAll(RegExp(r'/+'), '/');
  if (s.isEmpty || s == '.') return null;
  final parts = s.split('/').where((e) => e.isNotEmpty).toList();
  if (parts.any((e) => e == '..')) {
    throw ArgumentError('Folder escapes vault root: $raw');
  }
  // Strip accidental app / product name prefixes — not symbol folders.
  while (parts.isNotEmpty && _junkLeadingSegment(parts.first)) {
    parts.removeAt(0);
  }
  if (parts.isEmpty) return null;
  return parts.join('/');
}

bool _junkLeadingSegment(String segment) {
  final lower = segment.toLowerCase();
  return lower == 'hue-memory' ||
      lower == 'hue-memory-vault' ||
      lower == 'symbol-journal' ||
      lower == 'pack' ||
      lower == 'packs';
}

/// Join vault-relative segments safely (posix). Empty folder → file at root.
String joinVaultRelative(String? folder, String fileName) {
  final name = fileName.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
  if (name.isEmpty || name.contains('..')) {
    throw ArgumentError('Bad vault file name: $fileName');
  }
  final dir = normalizeVaultFolder(folder);
  if (dir == null || dir.isEmpty) return name;
  return p.posix.normalize(p.posix.join(dir, name));
}

/// Refuse app scaffolding paths (`symbol-journal/`, pack YAML under `packs/`).
void assertNoVaultScaffoldPath(String relativePath) {
  final cleaned =
      relativePath.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
  final segments = cleaned.split('/').where((e) => e.isNotEmpty).toList();
  if (segments.any((e) => e == '..')) {
    throw ArgumentError('Path escapes vault root: $relativePath');
  }
  if (segments.any((e) => e.toLowerCase() == 'symbol-journal')) {
    throw ArgumentError(
      'Vault must not contain symbol-journal/ (got $relativePath). '
      'Pack config stays in the app; notes use your symbol folders only.',
    );
  }
  if (segments.any((e) => e.toLowerCase() == 'packs')) {
    throw ArgumentError(
      'Vault must not contain packs/ scaffolding (got $relativePath).',
    );
  }
}

/// Vault must only hold capture photos + `.md` / `.canvas` notes.
///
/// Never pack YAML, `symbol-journal/` scaffolding, or `*.json` sidecars.
/// Canvas **content** is JSON inside a `.canvas` file; the extension must be
/// exactly `.canvas` (not `.json`, `.json.canvas`, or `.canvas.json`).
void assertVaultWriteAllowed(String relativePath) {
  assertNoVaultScaffoldPath(relativePath);
  final cleaned =
      relativePath.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
  final lower = cleaned.toLowerCase();
  final base = lower.split('/').last;

  if (lower.endsWith('.json') ||
      base.endsWith('.json.canvas') ||
      base.endsWith('.canvas.json') ||
      base.contains('.json.')) {
    throw ArgumentError(
      'Vault must not contain .json files (got $relativePath). '
      'Use .md or .canvas only.',
    );
  }
}
