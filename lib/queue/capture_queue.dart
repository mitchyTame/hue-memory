import 'dart:typed_data';

/// Status of a photo waiting for OCR / confirm.
enum QueueJobStatus {
  pending,
  failed,
  done,
}

/// One queued page capture (bytes live outside the vault until commit).
class QueueJob {
  const QueueJob({
    required this.id,
    required this.enqueuedAt,
    required this.capturedAt,
    required this.imageExtension,
    this.status = QueueJobStatus.pending,
    this.lastError,
  });

  final String id;
  final DateTime enqueuedAt;
  final DateTime capturedAt;
  final String imageExtension;
  final QueueJobStatus status;
  final String? lastError;

  QueueJob copyWith({
    QueueJobStatus? status,
    String? lastError,
    bool clearError = false,
  }) {
    return QueueJob(
      id: id,
      enqueuedAt: enqueuedAt,
      capturedAt: capturedAt,
      imageExtension: imageExtension,
      status: status ?? this.status,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'enqueued_at': enqueuedAt.toUtc().toIso8601String(),
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'image_extension': imageExtension,
        'status': status.name,
        if (lastError != null) 'last_error': lastError,
      };

  static QueueJob fromJson(Map<String, Object?> json) {
    final statusName = json['status']?.toString() ?? 'pending';
    final status = QueueJobStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => QueueJobStatus.pending,
    );
    return QueueJob(
      id: json['id']!.toString(),
      enqueuedAt: DateTime.parse(json['enqueued_at']!.toString()),
      capturedAt: DateTime.parse(json['captured_at']!.toString()),
      imageExtension: json['image_extension']?.toString() ?? 'jpg',
      status: status,
      lastError: json['last_error']?.toString(),
    );
  }
}

/// App-private offline capture queue (photos until OCR / inbox commit).
abstract interface class CaptureQueue {
  Future<QueueJob> enqueue({
    required Uint8List imageBytes,
    required DateTime capturedAt,
    String imageExtension = 'jpg',
    String? id,
  });

  Future<List<QueueJob>> list({bool openOnly = true});

  Future<int> pendingCount();

  Future<Uint8List> readImage(String id);

  Future<void> markFailed(String id, String error);

  Future<void> markDone(String id);

  Future<void> remove(String id);
}
