import 'dart:typed_data';

import '../capture/page_id.dart';
import '../capture/pending_capture.dart';
import '../ocr/ocr_client.dart';
import '../vault/commit_pipeline.dart';

/// Build a pending capture for offline inbox-only commit (no OCR meaning).
PendingCapture inboxOnlyCapture({
  required String pageId,
  required Uint8List imageBytes,
  required DateTime capturedAt,
  String imageExtension = 'jpg',
}) {
  return PendingCapture(
    pageId: pageId,
    imageBytes: imageBytes,
    capturedAt: capturedAt,
    imageExtension: imageExtension,
    symbolId: 'inbox',
    title: 'Queued page ${PageId.shortStem(pageId)}',
    noteBody: 'Needs sorting — captured offline / OCR deferred.',
    meaning: MeaningResult(
      detectedGlyph: '○',
      pageGenre: 'inbox',
      regions: const [
        OcrRegion(
          id: 'offline',
          text: 'Needs sorting — captured offline / OCR deferred.',
          confidence: 0,
        ),
      ],
      rawJson: const {'offline_inbox_only': true},
    ),
  );
}

/// Commit queued bytes straight to inbox without an OCR pass.
Future<CommitResult> commitInboxOnly({
  required CommitPipeline pipeline,
  required PendingCapture capture,
}) {
  return pipeline.commit(
    CommitInput(
      capture: capture,
      symbolId: 'inbox',
      title: capture.title,
      noteBody: capture.noteBody,
    ),
  );
}
