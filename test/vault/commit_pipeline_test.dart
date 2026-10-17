import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/capture/pending_capture.dart';
import 'package:hue_memory/ocr/mock_ocr_client.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
import 'package:hue_memory/symbols/symbol_models.dart';
import 'package:hue_memory/symbols/symbol_router.dart';
import 'package:hue_memory/vault/commit_pipeline.dart';
import 'package:hue_memory/vault/daily_note_path.dart';
import 'package:hue_memory/vault/fake_vault_fs.dart';
import 'package:hue_memory/writers/link_writer.dart';

Uint8List _tinyPng() {
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
        folder: 'Organising/Daily',
        format: 'YYYY-MM-DD',
      ),
    );
  });

  test('commits markdown note + raw image — no meaning.json', () async {
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
    expect(result.notePath, 'fleeting/Attention is a muscle.md');
    expect(await vault.exists(result.rawImagePath), isTrue);
    expect(await vault.exists(result.notePath!), isTrue);
    expect(
      vault.filePaths.any((p) => p.endsWith('.json')),
      isFalse,
    );

    final md = await vault.readText(result.notePath!);
    expect(md, contains('type: fleeting'));
    expect(md, contains('glyph: ∼'));
    expect(md, contains('page_id: 20261016-p7k2'));
    expect(md, contains('![[captures/raw/20261016-p7k2.png]]'));
    expect(md, contains('Practice on paper first.'));
    // Personal v2: no auto [[wikilinks]] even if CommitInput.links is set.
    expect(md, isNot(contains('[[permanent/seed-attention')));
    expect(md, isNot(contains('[[Seed]]')));
    expect(md, isNot(contains('meaning:')));
  });

  test('journal symbol writes markdown under journal/', () async {
    final capture = _capture(glyph: 'J');
    final result = await pipeline.commit(
      CommitInput(
        capture: capture,
        symbolId: 'journal',
        title: 'Morning pages',
        noteBody: 'Wrote by hand.',
      ),
    );
    expect(result.notePath, 'journal/Morning pages.md');
    expect(result.symbolId, 'journal');
    final md = await vault.readText(result.notePath!);
    expect(md, contains('type: journal'));
    expect(md, contains('glyph: J'));
  });

  test('commits canvas for visual symbol without sidecar json', () async {
    final capture = _capture(
      glyph: '△',
      regions: const [
        OcrRegion(id: 'n1', text: 'Psychology', confidence: 0.9, bbox: [0.1, 0.1, 0.3, 0.1]),
        OcrRegion(id: 'n2', text: 'Memory', confidence: 0.9, bbox: [0.5, 0.2, 0.3, 0.1]),
        OcrRegion(id: 'n3', text: 'Encoding', confidence: 0.9, bbox: [0.5, 0.4, 0.3, 0.1]),
      ],
    );
    final result = await pipeline.commit(
      CommitInput(
        capture: capture,
        symbolId: 'visual',
        title: 'Mindmap topic',
        noteBody: 'Central idea',
      ),
    );

    expect(result.canvasPath, 'mindmaps/Mindmap topic.canvas');
    expect(result.notePath, isNull);
    final json =
        jsonDecode(await vault.readText(result.canvasPath!)) as Map;
    final nodes = json['nodes'] as List;
    expect(nodes.first['type'], 'file');
    expect(nodes.first['file'], 'captures/raw/20261016-p7k2.png');
    expect(nodes.first['color'], '4');
    final tagsNode = nodes.cast<Map>().firstWhere((n) => n['id'] == 'tags');
    // Without Gemini edges, tags stay flat (no invented hub hierarchy).
    expect(tagsNode['text'], contains('#psychology'));
    expect(tagsNode['text'], contains('#memory'));
    expect(tagsNode['text'], contains('#encoding'));
    expect(nodes.length, greaterThan(1));
    expect(
      vault.filePaths.any((p) => p.endsWith('.json')),
      isFalse,
    );
  });

  test('△ commit writes .canvas + clean image + text nodes — never .md or burn-in',
      () async {
    final png = _tinyPng();
    // Mutate a copy after capture so we can prove vault got the original bytes.
    final capture = PendingCapture(
      pageId: '20261017-v1s1',
      imageBytes: Uint8List.fromList(png),
      capturedAt: DateTime.utc(2026, 10, 17, 1, 0),
      meaning: MeaningResult(
        detectedGlyph: '△',
        pageGenre: 'visual',
        regions: const [
          OcrRegion(
            id: 'n1',
            text: 'Chunking',
            confidence: 0.95,
            bbox: [0.12, 0.18, 0.4, 0.12],
          ),
          OcrRegion(
            id: 'n2',
            text: 'Working memory',
            confidence: 0.9,
            bbox: [0.45, 0.4, 0.4, 0.12],
          ),
        ],
      ),
    );

    final result = await pipeline.commit(
      CommitInput(
        capture: capture,
        symbolId: 'visual',
        title: 'Memory map',
        noteBody: 'This body must NOT become a markdown note',
      ),
    );

    // Exact Obsidian artifact paths — title is the basename (no pageId).
    expect(result.canvasPath, 'mindmaps/Memory map.canvas');
    expect(result.canvasPath!.endsWith('.canvas'), isTrue);
    expect(result.canvasPath!.contains('.json'), isFalse);
    expect(result.notePath, isNull);
    expect(result.rawImagePath, 'captures/raw/20261017-v1s1.png');
    expect(result.primaryPath, result.canvasPath);

    expect(await vault.exists('mindmaps/Memory map.canvas'), isTrue);
    expect(await vault.exists('captures/raw/20261017-v1s1.png'), isTrue);
    expect(vault.filePaths.any((p) => p.contains('20261017-v1s1-memory')), isFalse);
    expect(vault.filePaths.any((p) => p.endsWith('.md')), isFalse);
    expect(vault.filePaths.any((p) => p.contains('.json')), isFalse);

    // Clean image: byte-identical to capture (no overlay burned into pixels)
    final vaultPng = await vault.readBytes(result.rawImagePath);
    expect(vaultPng, png);

    // JSON Canvas 1.0: ink-ghost file node + separate editable text nodes
    final doc =
        jsonDecode(await vault.readText(result.canvasPath!)) as Map<String, dynamic>;
    expect(doc.containsKey('nodes'), isTrue);
    expect(doc.containsKey('edges'), isTrue);
    final nodes = (doc['nodes'] as List).cast<Map>();
    final fileNode = nodes.firstWhere((n) => n['type'] == 'file');
    expect(fileNode['file'], 'captures/raw/20261017-v1s1.png');
    final texts = nodes.where((n) => n['type'] == 'text').toList();
    expect(texts.length, greaterThanOrEqualTo(2));
    expect(texts.map((n) => n['text']), containsAll(['Chunking', 'Working memory']));
    // Photo sits above the idea graph (y=0 band), not as a center hub.
    expect(fileNode['y'], 0);
    final ideaYs = texts
        .where((n) => n['id'] != 'tags')
        .map((n) => n['y'] as int)
        .toList();
    expect(
      ideaYs.every((y) => y >= (fileNode['height'] as int)),
      isTrue,
    );
    // Labels live in JSON nodes — not burned into PNG pixels
    final pngAsLatin = String.fromCharCodes(vaultPng);
    expect(pngAsLatin.contains('Chunking'), isFalse);
    expect(pngAsLatin.contains('Working memory'), isFalse);
  });

  test('visual symbol forces .canvas even if pack output were markdown', () async {
    // Simulate a misconfigured pack that marks visual as markdown — pipeline
    // must still write .canvas, never an image-embedding .md.
    final badPack = SymbolPack(
      id: 'bad',
      libraryRef: 'ink-v1',
      label: 'Bad',
      symbols: const [
        PackSymbol(
          id: 'visual',
          draw: 'triangle',
          glyphs: ['△'],
          folder: 'mindmaps',
          output: SymbolOutput.markdown,
        ),
      ],
    );
    final badPipeline = CommitPipeline(
      vault: vault,
      router: SymbolRouter(pack: badPack),
    );
    final capture = _capture(
      glyph: '△',
      regions: MockOcrClient.defaultVisualRegions,
      pageId: '20261017-force',
    );
    final result = await badPipeline.commit(
      CommitInput(
        capture: capture,
        symbolId: 'visual',
        title: 'Forced canvas',
        noteBody: 'should not become md',
      ),
    );
    expect(result.canvasPath, 'mindmaps/Forced canvas.canvas');
    expect(result.notePath, isNull);
    expect(await vault.exists(result.canvasPath!), isTrue);
    expect(
      vault.filePaths.any((p) => p.endsWith('.md')),
      isFalse,
    );
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

    expect(result.dailyNotePath, 'Organising/Daily/2026-10-16.md');
    final body = await vault.readText(result.dailyNotePath!);
    expect(body, contains('## Tasks'));
    expect(body, contains('- [ ] Buy ink cartridges'));
    expect(body, contains('<!-- symbol-journal:p7k2 -->'));
    expect(await vault.exists('captures/raw/20261016-p7k2.png'), isTrue);
  });

  test('fileStemFromTitle keeps typed name — no pageId suffix', () {
    expect(
      CommitPipeline.fileStemFromTitle('Attention is a muscle'),
      'Attention is a muscle',
    );
    expect(CommitPipeline.fileStemFromTitle('Hello/World'), 'Hello-World');
    expect(CommitPipeline.fileStemFromTitle('note.md'), 'note');
    expect(CommitPipeline.fileStemFromTitle('   '), 'Untitled');
  });

  test('refuses overwrite when filename already exists', () async {
    await vault.writeText('fleeting/Attention is a muscle.md', 'existing');
    final capture = _capture();
    expect(
      () => pipeline.commit(
        CommitInput(
          capture: capture,
          symbolId: 'fleeting',
          title: 'Attention is a muscle',
          noteBody: 'new',
        ),
      ),
      throwsA(
        isA<VaultNameCollisionException>().having(
          (e) => e.readable,
          'readable',
          contains('already exists'),
        ),
      ),
    );
    expect(
      await vault.readText('fleeting/Attention is a muscle.md'),
      'existing',
    );
  });

  test('slugify strips punctuation', () {
    expect(CommitPipeline.slugify('Hello, World!'), 'hello-world');
    expect(CommitPipeline.slugify('   '), 'note');
  });

  test('refuses writing .json into the vault', () async {
    expect(
      () => vault.writeText('captures/raw/x.meaning.json', '{}'),
      throwsA(isA<ArgumentError>()),
    );
  });
}
