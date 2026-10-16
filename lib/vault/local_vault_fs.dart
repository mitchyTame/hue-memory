import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'vault_fs.dart';
import 'vault_paths.dart';

/// File-backed [VaultFs] for desktop / WSL demos (and Android app-private
/// fallback). Never point this at a SAF `content://` tree URI — use
/// [SafVaultFs] for Obsidian vault folders on device.
class LocalVaultFs implements VaultFs {
  LocalVaultFs(this.rootDirectory) {
    final path = rootDirectory.path;
    if (path.startsWith('content:') || path.contains('://')) {
      throw ArgumentError(
        'LocalVaultFs cannot open "$path"; use SafVaultFs for tree URIs',
      );
    }
    if (!rootDirectory.existsSync()) {
      rootDirectory.createSync(recursive: true);
    }
  }

  /// Absolute vault root on disk.
  final Directory rootDirectory;

  String get rootPath => rootDirectory.path;

  File _file(String relativePath) {
    final resolved = _resolve(relativePath);
    return File(resolved);
  }

  Directory _dir(String relativePath) {
    final resolved = _resolve(relativePath);
    return Directory(resolved);
  }

  String _resolve(String relativePath) {
    final cleaned = relativePath.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    final joined = p.normalize(p.join(rootDirectory.path, cleaned));
    final root = p.normalize(rootDirectory.path);
    if (joined != root && !joined.startsWith('$root${p.separator}')) {
      throw ArgumentError('Path escapes vault root: $relativePath');
    }
    return joined;
  }

  /// Write via temp file + rename so Obsidian (and other watchers) can keep
  /// the vault open without exclusive-lock failures on the final path.
  Future<void> _writeAtomically(File file, Future<void> Function(File tmp) write) async {
    await file.parent.create(recursive: true);
    final tmp = File(
      '${file.path}.hue-tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await write(tmp);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {
          // Best-effort; rename may still replace on this platform.
        }
      }
      await tmp.rename(file.path);
    } catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      // Fallback: direct write (non-atomic) if rename is unsupported.
      await write(file);
    }
  }

  @override
  Future<void> ensureDir(String relativePath) async {
    final dir = _dir(relativePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  @override
  Future<bool> exists(String relativePath) async {
    final path = _resolve(relativePath);
    return File(path).existsSync() || Directory(path).existsSync();
  }

  @override
  Future<List<String>> list(String relativePath) async {
    final dir = _dir(relativePath.isEmpty ? '.' : relativePath);
    if (!await dir.exists()) return const [];
    final names = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      names.add(p.basename(entity.path));
    }
    names.sort();
    return names;
  }

  @override
  Future<Uint8List> readBytes(String relativePath) async {
    final file = _file(relativePath);
    if (!await file.exists()) {
      throw StateError('Missing file: $relativePath');
    }
    return file.readAsBytes();
  }

  @override
  Future<String> readText(String relativePath) async {
    final file = _file(relativePath);
    if (!await file.exists()) {
      throw StateError('Missing file: $relativePath');
    }
    return file.readAsString();
  }

  @override
  Future<void> writeBytes(String relativePath, Uint8List bytes) async {
    assertVaultWriteAllowed(relativePath);
    final file = _file(relativePath);
    await _writeAtomically(file, (tmp) => tmp.writeAsBytes(bytes, flush: true));
  }

  @override
  Future<void> writeText(String relativePath, String contents) async {
    assertVaultWriteAllowed(relativePath);
    final file = _file(relativePath);
    await _writeAtomically(
      file,
      (tmp) => tmp.writeAsString(contents, flush: true),
    );
  }
}
