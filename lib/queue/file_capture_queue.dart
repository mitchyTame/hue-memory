import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'capture_queue.dart';

/// Disk-backed queue under app documents `hue-memory-queue/`.
class FileCaptureQueue implements CaptureQueue {
  FileCaptureQueue({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;
  Directory? _root;
  int _seq = 0;

  Future<Directory> _ensureRoot() async {
    final existing = _root;
    if (existing != null) return existing;
    final override = _rootOverride;
    final Directory root;
    if (override != null) {
      root = override;
    } else {
      final docs = await getApplicationDocumentsDirectory();
      root = Directory(p.join(docs.path, 'hue-memory-queue'));
    }
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    return _root = root;
  }

  File get _indexFile => File(p.join(_root!.path, 'index.json'));

  Future<List<QueueJob>> _readIndex() async {
    await _ensureRoot();
    if (!_indexFile.existsSync()) return [];
    final raw = jsonDecode(await _indexFile.readAsString());
    if (raw is! List) return [];
    return [
      for (final item in raw)
        if (item is Map)
          QueueJob.fromJson(Map<String, Object?>.from(item)),
    ];
  }

  Future<void> _writeIndex(List<QueueJob> jobs) async {
    await _ensureRoot();
    final encoded = const JsonEncoder.withIndent('  ').convert(
      jobs.map((j) => j.toJson()).toList(),
    );
    await _indexFile.writeAsString(encoded);
  }

  String _imagePath(String id, String ext) =>
      p.join(_root!.path, '$id.$ext');

  @override
  Future<QueueJob> enqueue({
    required Uint8List imageBytes,
    required DateTime capturedAt,
    String imageExtension = 'jpg',
    String? id,
  }) async {
    await _ensureRoot();
    final jobId = id ??
        'q${DateTime.now().toUtc().millisecondsSinceEpoch}-${_seq++}';
    final ext = imageExtension.replaceAll('.', '');
    final job = QueueJob(
      id: jobId,
      enqueuedAt: DateTime.now().toUtc(),
      capturedAt: capturedAt.toUtc(),
      imageExtension: ext,
    );
    await File(_imagePath(jobId, ext)).writeAsBytes(imageBytes, flush: true);
    final jobs = await _readIndex();
    jobs.add(job);
    await _writeIndex(jobs);
    return job;
  }

  @override
  Future<List<QueueJob>> list({bool openOnly = true}) async {
    final all = await _readIndex();
    if (!openOnly) return all;
    return all
        .where(
          (j) =>
              j.status == QueueJobStatus.pending ||
              j.status == QueueJobStatus.failed,
        )
        .toList();
  }

  @override
  Future<int> pendingCount() async => (await list()).length;

  @override
  Future<Uint8List> readImage(String id) async {
    final jobs = await _readIndex();
    QueueJob? job;
    for (final j in jobs) {
      if (j.id == id) {
        job = j;
        break;
      }
    }
    if (job == null) throw StateError('Unknown queue job: $id');
    final file = File(_imagePath(id, job.imageExtension));
    if (!file.existsSync()) throw StateError('Missing queue image: $id');
    return file.readAsBytes();
  }

  @override
  Future<void> markFailed(String id, String error) async {
    final jobs = await _readIndex();
    final i = jobs.indexWhere((j) => j.id == id);
    if (i < 0) throw StateError('Unknown queue job: $id');
    jobs[i] = jobs[i].copyWith(status: QueueJobStatus.failed, lastError: error);
    await _writeIndex(jobs);
  }

  @override
  Future<void> markDone(String id) async {
    final jobs = await _readIndex();
    final i = jobs.indexWhere((j) => j.id == id);
    if (i < 0) throw StateError('Unknown queue job: $id');
    jobs[i] = jobs[i].copyWith(status: QueueJobStatus.done, clearError: true);
    await _writeIndex(jobs);
  }

  @override
  Future<void> remove(String id) async {
    final jobs = await _readIndex();
    QueueJob? job;
    for (final j in jobs) {
      if (j.id == id) {
        job = j;
        break;
      }
    }
    jobs.removeWhere((j) => j.id == id);
    await _writeIndex(jobs);
    if (job != null) {
      final file = File(_imagePath(id, job.imageExtension));
      if (file.existsSync()) file.deleteSync();
    }
  }
}
