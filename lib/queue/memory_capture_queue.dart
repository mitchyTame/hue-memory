import 'dart:typed_data';

import 'capture_queue.dart';

/// In-memory [CaptureQueue] for unit / widget tests.
class MemoryCaptureQueue implements CaptureQueue {
  MemoryCaptureQueue({Map<String, Uint8List>? seedImages})
      : _images = Map<String, Uint8List>.from(seedImages ?? const {});

  final List<QueueJob> _jobs = [];
  final Map<String, Uint8List> _images;
  int _seq = 0;

  @override
  Future<QueueJob> enqueue({
    required Uint8List imageBytes,
    required DateTime capturedAt,
    String imageExtension = 'jpg',
    String? id,
  }) async {
    final jobId = id ??
        'q${DateTime.now().toUtc().millisecondsSinceEpoch}-${_seq++}';
    final job = QueueJob(
      id: jobId,
      enqueuedAt: DateTime.now().toUtc(),
      capturedAt: capturedAt.toUtc(),
      imageExtension: imageExtension,
    );
    _jobs.add(job);
    _images[jobId] = Uint8List.fromList(imageBytes);
    return job;
  }

  @override
  Future<List<QueueJob>> list({bool openOnly = true}) async {
    final all = List<QueueJob>.from(_jobs);
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
    final bytes = _images[id];
    if (bytes == null) throw StateError('Missing queue image: $id');
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> markFailed(String id, String error) async {
    _replace(id, (j) => j.copyWith(status: QueueJobStatus.failed, lastError: error));
  }

  @override
  Future<void> markDone(String id) async {
    _replace(id, (j) => j.copyWith(status: QueueJobStatus.done, clearError: true));
  }

  @override
  Future<void> remove(String id) async {
    _jobs.removeWhere((j) => j.id == id);
    _images.remove(id);
  }

  void _replace(String id, QueueJob Function(QueueJob) map) {
    final i = _jobs.indexWhere((j) => j.id == id);
    if (i < 0) throw StateError('Unknown queue job: $id');
    _jobs[i] = map(_jobs[i]);
  }
}
