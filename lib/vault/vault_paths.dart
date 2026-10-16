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
/// - drop accidental leading junk segments (`hue-memory`, `pack`, `packs`)
///   that are app/product names, not Mitch-configured note folders
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

/// Vault must only hold `.md`, `.canvas`, images, yaml printables — never `*.json`.
///
/// Canvas **content** is JSON inside a `.canvas` file; the extension must not
/// be `.json`.
void assertVaultWriteAllowed(String relativePath) {
  final cleaned =
      relativePath.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
  final lower = cleaned.toLowerCase();
  if (lower.endsWith('.json')) {
    throw ArgumentError(
      'Vault must not contain .json files (got $relativePath). '
      'Use .md or .canvas only.',
    );
  }
  if (cleaned.split('/').any((e) => e == '..')) {
    throw ArgumentError('Path escapes vault root: $relativePath');
  }
}
