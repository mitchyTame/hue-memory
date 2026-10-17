import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/queue/capture_queue.dart';
import 'package:hue_memory/queue/file_capture_queue.dart';
import 'package:hue_memory/queue/inbox_only_commit.dart';
import 'package:hue_memory/queue/memory_capture_queue.dart';
import 'package:hue_memory/vault/commit_pipeline.dart';
import 'package:hue_memory/vault/fake_vault_fs.dart';

void main() {
  group('MemoryCaptureQueue', () {
    test('enqueue, list, markDone cycle', () async {
      final q = MemoryCaptureQueue();
      final job = await q.enqueue(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        capturedAt: DateTime.utc(2026, 10, 16),
        imageExtension: 'png',
      );
      expect(await q.pendingCount(), 1);
      expect((await q.list()).single.id, job.id);
      expect(await q.readImage(job.id), [1, 2, 3]);

      await q.markFailed(job.id, 'offline');
      expect((await q.list()).single.status.name, 'failed');
      expect((await q.list()).single.lastError, 'offline');

      await q.markDone(job.id);
      expect(await q.pendingCount(), 0);
    });

    test('persists forcedSymbolId for △ retry', () async {
      final q = MemoryCaptureQueue();
      final job = await q.enqueue(
        imageBytes: Uint8List.fromList([1]),
        capturedAt: DateTime.utc(2026, 10, 16),
        forcedSymbolId: 'visual',
      );
      expect(job.forcedSymbolId, 'visual');
      expect((await q.list()).single.forcedSymbolId, 'visual');
      final roundTrip = QueueJob.fromJson(job.toJson());
      expect(roundTrip.forcedSymbolId, 'visual');
    });
  });

  group('FileCaptureQueue', () {
    test('persists index + image bytes on disk', () async {
      final dir = await Directory.systemTemp.createTemp('hue-q-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final q = FileCaptureQueue(root: dir);
      final job = await q.enqueue(
        imageBytes: Uint8List.fromList([9, 8, 7]),
        capturedAt: DateTime.utc(2026, 10, 16, 12),
        forcedSymbolId: 'visual',
      );
      expect(File('${dir.path}/index.json').existsSync(), isTrue);
      expect(await q.readImage(job.id), [9, 8, 7]);

      final reopened = FileCaptureQueue(root: dir);
      expect(await reopened.pendingCount(), 1);
      expect((await reopened.list()).single.forcedSymbolId, 'visual');
      await reopened.remove(job.id);
      expect(await reopened.pendingCount(), 0);
    });
  });

  test('inboxOnlyCapture commits via pipeline', () async {
    final vault = FakeVaultFs();
    final pipeline = CommitPipeline(vault: vault);
    final capture = inboxOnlyCapture(
      pageId: '20261016-qzzz',
      imageBytes: Uint8List.fromList([1]),
      capturedAt: DateTime.utc(2026, 10, 16),
      imageExtension: 'png',
    );
    final result = await commitInboxOnly(pipeline: pipeline, capture: capture);
    expect(result.notePath, startsWith('inbox/'));
    expect(result.symbolId, 'inbox');
    final md = await vault.readText(result.notePath!);
    expect(md, contains('Needs sorting'));
  });
}
