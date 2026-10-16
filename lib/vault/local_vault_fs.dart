import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'vault_fs.dart';

/// File-backed [VaultFs] for desktop / WSL demos (and Android app-private
/// fallback). Never point this at a SAF `content://` tree URI — use
/// [SafVaultFs] for Obsidian vault folders on device.
class LocalVaultFs implements VaultFs {
  LocalVaultFs(this.rootDirectory) {
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
    final file = _file(relativePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> writeText(String relativePath, String contents) async {
    final file = _file(relativePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(contents, flush: true);
  }
}
