/// Glanceable summary of the most recent vault write.
class LastCommitSummary {
  const LastCommitSummary({
    required this.fileName,
    required this.folder,
    required this.at,
    required this.symbolId,
    required this.glyph,
  });

  /// Basename only (e.g. `20261016-note.md`).
  final String fileName;

  /// Vault-relative folder (e.g. `fleeting`, `Daily Notes`).
  final String folder;

  final DateTime at;
  final String symbolId;

  /// Ink glyph for the symbol (○ ∼ ≡ ◇ △ ·).
  final String glyph;

  String get folderLabel => folder.trim().isEmpty ? 'vault root' : folder;

  String get dateLabel {
    final local = at.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}
