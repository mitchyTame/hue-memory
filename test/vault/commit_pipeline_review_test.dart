import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/capture/pending_capture.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
import 'package:hue_memory/todoist/daily_todoist_sync.dart';
import 'package:hue_memory/todoist/todoist_client.dart';
import 'package:hue_memory/todoist/todoist_retry.dart';
import 'package:hue_memory/todoist/unmatched_done_store.dart';
import 'package:hue_memory/vault/commit_pipeline.dart';
import 'package:hue_memory/vault/fake_vault_fs.dart';

import '../todoist/fake_todoist_client.dart';

PendingCapture _dailyCapture() {
  return PendingCapture(
    pageId: '20261127-p7k2',
    imageBytes: Uint8List.fromList([1, 2, 3, 4]),
    capturedAt: DateTime.utc(2026, 11, 27, 8),
    meaning: const MeaningResult(
      detectedGlyph: '·',
      regions: [],
      pageGenre: 'task_list',
    ),
  );
}

const _body = '''
high:
- Call dentist
- Pay rent
shopping:
- Milk
''';

void main() {
  late FakeVaultFs vault;
  late ScriptedTodoistClient todoist;
  late MemoryTodoistRetryStore retry;
  late DailyTodoistSync sync;
  late CommitPipeline pipeline;

  setUp(() {
    vault = FakeVaultFs();
    todoist = ScriptedTodoistClient();
    retry = MemoryTodoistRetryStore();
    sync = DailyTodoistSync(
      client: todoist,
      unmatchedStore: MemoryUnmatchedDoneStore(),
      retryStore: retry,
    );
    pipeline = CommitPipeline(vault: vault, dailyTodoistSync: sync);
  });

  test('sends exactly the reviewed plan, not a re-parse of the body', () async {
    final plan = sync.plan(markdown: _body)
        .setTaskIncluded(1, false)
        .setTaskContent(0, 'Call the dentist')
        .setTaskPriority(2, 4);

    final result = await pipeline.commit(
      CommitInput(
        capture: _dailyCapture(),
        symbolId: 'daily-tasks',
        title: '2026-11-27',
        noteBody: _body,
        dailyMarkdown: _body,
        todoistPlan: plan,
      ),
    );

    expect(result.todoistSync?.createdCount, 2);
    expect(todoist.created.map((t) => t.content), ['Call the dentist', 'Milk']);
    expect(todoist.priorities['new-2'], 4);
  });

  test('without a reviewed plan the capture is planned and sent as before',
      () async {
    final result = await pipeline.commit(
      CommitInput(
        capture: _dailyCapture(),
        symbolId: 'daily-tasks',
        title: '2026-11-27',
        noteBody: _body,
        dailyMarkdown: _body,
      ),
    );
    expect(result.todoistSync?.createdCount, 3);
  });

  test('partial Todoist failure still commits: raw photo kept, no Obsidian note',
      () async {
    todoist.createErrors['Pay rent'] =
        TodoistApiException('Todoist error 500', statusCode: 500);

    final result = await pipeline.commit(
      CommitInput(
        capture: _dailyCapture(),
        symbolId: 'daily-tasks',
        title: '2026-11-27',
        noteBody: _body,
        todoistPlan: sync.plan(markdown: _body),
      ),
    );

    expect(result.todoistSync?.createdCount, 2);
    expect(result.todoistSync?.failed.map((f) => f.content), ['Pay rent']);
    expect(result.notePath, isNull);
    expect(result.canvasPath, isNull);
    expect(result.dailyNotePath, isNull);
    expect(await vault.exists('captures/raw/20261127-p7k2.png'), isTrue);
    expect(vault.filePaths, hasLength(1));
    expect((await retry.read()).single.items.single.content, 'Pay rent');
  });

  test('markdown notes are unchanged by the review plan', () async {
    final result = await pipeline.commit(
      CommitInput(
        capture: PendingCapture(
          pageId: '20261127-aaaa',
          imageBytes: Uint8List.fromList([9, 9]),
          capturedAt: DateTime.utc(2026, 11, 27, 8),
          meaning: const MeaningResult(
            detectedGlyph: '∼',
            regions: [],
            pageGenre: 'text',
          ),
        ),
        symbolId: 'fleeting',
        title: 'A thought',
        noteBody: 'Body',
      ),
    );
    expect(result.notePath, 'fleeting/A thought.md');
    expect(result.todoistSync, isNull);
    expect(todoist.created, isEmpty);
  });
}
