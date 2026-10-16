import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/capture/pending_capture.dart';
import 'package:hue_memory/ocr/mock_ocr_client.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
import 'package:hue_memory/vault/commit_pipeline.dart';
import 'package:hue_memory/vault/daily_note_path.dart';
import 'package:hue_memory/vault/fake_vault_fs.dart';
import 'package:hue_memory/writers/link_writer.dart';

Uint8List _tinyPng() {
  // Minimal 1x1 PNG
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
    0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
}

PendingCapture _capture({
  String glyph = '∼',
  List<OcrRegion>? regions,
  String pageId = '20261016-p7k2',
}) {
  final meaning = MeaningResult(
    detectedGlyph: glyph,
    regions: regions ?? MockOcrClient.defaultFleetingRegions,
    pageGenre: glyph == '·' ? 'task_list' : glyph == '△' ? 'visual' : 'text',
  );
  return PendingCapture(
    pageId: pageId,
    imageBytes: _tinyPng(),
    capturedAt: DateTime.utc(2026, 10, 16, 12, 5),
    meaning: meaning,
  );
}

void main() {
  late FakeVaultFs vault;
  late CommitPipeline pipeline;

  setUp(() {
    vault = FakeVaultFs();
    pipeline = CommitPipeline(
      vault: vault,
      dailyNoteSettings: const DailyNoteSettings(
        folder: 'Daily Notes',
        format: 'YYYY-MM-DD',
      ),
    );
  });

  test('commits markdown note + raw image + meaning.json', () async {
    final capture = _capture();
    final result = await pipeline.commit(
      CommitInput(
        capture: capture,
        symbolId: 'fleeting',
        title: 'Attention is a muscle',
        noteBody: 'Practice on paper first.',
        links: const [
          LinkPick(
            targetPath: 'permanent/seed-attention',
            displayTitle: 'Seed',
          ),
        ],
      ),
    );

    expect(result.rawImagePath, 'captures/raw/20261016-p7k2.png');
    expect(result.meaningPath, 'captures/raw/20261016-p7k2.meaning.json');
    expect(
      result.notePath,
      'fleeting/20261016-p7k2-attention-is-a-muscle.md',
    );
    expect(await vault.exists(result.rawImagePath), isTrue);
    expect(await vault.exists(result.meaningPath), isTrue);

    final md = await vault.readText(result.notePath!);
    expect(md, contains('type: fleeting'));
    expect(md, contains('glyph: ∼'));
    expect(md, contains('page_id: 20261016-p7k2'));
    expect(md, contains('![[captures/raw/20261016-p7k2.png]]'));
    expect(md, contains('Practice on paper first.'));
    expect(md, contains('[[permanent/seed-attention|Seed]]'));

    final meaning =
        jsonDecode(await vault.readText(result.meaningPath)) as Map;
    expect(meaning['page_id'], '20261016-p7k2');
    expect(meaning['symbol'], 'fleeting');
  });

  test('commits canvas for visual symbol', () async {
    final capture = _capture(
      glyph: '△',
      regions: MockOcrClient.defaultVisualRegions,
    );
    final result = await pipeline.commit(
      CommitInput(
        capture: capture,
        symbolId: 'visual',
        title: 'Mindmap topic',
        noteBody: 'Central idea',
      ),
    );

    expect(
      result.canvasPath,
      'mindmaps/20261016-p7k2-mindmap-topic.canvas',
    );
    final json =
        jsonDecode(await vault.readText(result.canvasPath!)) as Map;
    final nodes = json['nodes'] as List;
    expect(nodes.first['type'], 'file');
    expect(nodes.first['file'], 'captures/raw/20261016-p7k2.png');
    expect(nodes.first['color'], '4');
    expect(nodes.length, greaterThan(1));
    // bbox-scaled: n1 at ~0.35*480, 0.28*640
    final n1 = nodes[1] as Map;
    expect(n1['id'], 'n1');
    expect(n1['x'], (0.35 * 480).round());
    final edges = json['edges'] as List;
    expect(edges, isNotEmpty);

    final meaning =
        jsonDecode(await vault.readText(result.meaningPath)) as Map;
    expect(meaning['ink_ghost'], isTrue);
  });

  test('canvas inkGhost false still embeds photo after text nodes', () async {
    final capture = _capture(
      glyph: '△',
      regions: MockOcrClient.defaultVisualRegions,
    );
    final result = await pipeline.commit(
      CommitInput(
        capture: capture,
        symbolId: 'visual',
        title: 'Mindmap topic',
        noteBody: 'Central idea',
        inkGhost: false,
      ),
    );
    final json =
        jsonDecode(await vault.readText(result.canvasPath!)) as Map;
    final nodes = json['nodes'] as List;
    expect(nodes.last['type'], 'file');
    expect(nodes.first['type'], 'text');
    final meaning =
        jsonDecode(await vault.readText(result.meaningPath)) as Map;
    expect(meaning['ink_ghost'], isFalse);
  });

  test('daily-tasks appends checkboxes under ## Tasks', () async {
    final capture = _capture(
      glyph: '·',
      regions: MockOcrClient.defaultTaskRegions,
    );
    final result = await pipeline.commit(
      CommitInput(
        capture: capture,
        symbolId: 'daily-tasks',
        title: 'Tasks',
        noteBody: 'ignored for path',
        taskLines: const ['Buy ink cartridges', 'Review fleeting notes'],
      ),
    );

    expect(result.dailyNotePath, 'Daily Notes/2026-10-16.md');
    final body = await vault.readText(result.dailyNotePath!);
    expect(body, contains('## Tasks'));
    expect(body, contains('- [ ] Buy ink cartridges'));
    expect(body, contains('<!-- symbol-journal:p7k2 -->'));
    expect(await vault.exists('captures/raw/20261016-p7k2.png'), isTrue);
  });

  test('slugify strips punctuation', () {
    expect(CommitPipeline.slugify('Hello, World!'), 'hello-world');
    expect(CommitPipeline.slugify('   '), 'note');
  });
}
