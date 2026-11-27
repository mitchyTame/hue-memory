import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/capture/pending_capture.dart';
import 'package:hue_memory/ocr/mock_ocr_client.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
import 'package:hue_memory/symbols/symbol_models.dart';
import 'package:hue_memory/symbols/symbol_router.dart';
import 'package:http/http.dart' as http;
import 'package:hue_memory/todoist/daily_todoist_sync.dart';
import 'package:hue_memory/todoist/todoist_client.dart';
import 'package:hue_memory/todoist/unmatched_done_store.dart';
import 'package:hue_memory/vault/commit_pipeline.dart';
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
  late _FakeTodoistClient todoist;
  late MemoryUnmatchedDoneStore unmatched;
  late CommitPipeline pipeline;

  setUp(() {
    vault = FakeVaultFs();
    todoist = _FakeTodoistClient();
    unmatched = MemoryUnmatchedDoneStore();
    pipeline = CommitPipeline(
      vault: vault,
      dailyTodoistSync: DailyTodoistSync(
        client: todoist,
        unmatchedStore: unmatched,
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

  test('daily-tasks syncs sections to Todoist — not Obsidian Daily', () async {
    final capture = _capture(
      glyph: '·',
      regions: MockOcrClient.defaultTaskRegions,
    );
    const noteBody = '''
high:
- Buy ink cartridges
medium:
- Review fleeting notes
Notes:
Ignore this prose
''';
    final result = await pipeline.commit(
      CommitInput(
        capture: capture,
        symbolId: 'daily-tasks',
        title: '2026-10-16',
        noteBody: noteBody,
        dailyMarkdown: noteBody,
      ),
    );

    expect(result.dailyNotePath, isNull);
    expect(result.todoistSync?.createdCount, 2);
    expect(todoist.created.map((t) => t.content).toList(), [
      'Buy ink cartridges',
      'Review fleeting notes',
    ]);
    expect(todoist.created.map((t) => t.labels.single).toList(), [
      'high',
      'medium',
    ]);
    expect(await vault.exists('captures/raw/20261016-p7k2.png'), isTrue);
    expect(await vault.exists('Organising/Daily/2026-10-16.md'), isFalse);
  });

  test('daily-tasks mindmap hub→branch→leaf syncs labeled Inbox tasks', () async {
    final regions = [
      const OcrRegion(id: 'hub', text: "20 Nov '26", confidence: 0.9, bbox: [0.3, 0.4, 0.2, 0.08]),
      const OcrRegion(id: 'high', text: 'High', confidence: 0.9, bbox: [0.6, 0.2, 0.2, 0.08]),
      const OcrRegion(id: 'hue', text: 'Hue', confidence: 0.9, bbox: [0.75, 0.15, 0.2, 0.08]),
      const OcrRegion(id: 'shop', text: 'shopping', confidence: 0.9, bbox: [0.2, 0.15, 0.2, 0.08]),
      const OcrRegion(id: 'blend', text: 'portable blender', confidence: 0.9, bbox: [0.05, 0.1, 0.25, 0.08]),
    ];
    final capture = PendingCapture(
      pageId: '20261120-p7k2',
      imageBytes: _tinyPng(),
      capturedAt: DateTime.utc(2026, 11, 20, 12),
      meaning: MeaningResult(
        detectedGlyph: '·',
        regions: regions,
        pageGenre: 'visual',
        rawJson: {
          'canvas_nodes': [
            for (final r in regions)
              {'id': r.id, 'type': 'text', 'text': r.text, 'x': 0, 'y': 0, 'width': 120, 'height': 48},
          ],
          'canvas_edges': [
            {'id': 'e1', 'fromNode': 'hub', 'toNode': 'high'},
            {'id': 'e2', 'fromNode': 'high', 'toNode': 'hue'},
            {'id': 'e3', 'fromNode': 'hub', 'toNode': 'shop'},
            {'id': 'e4', 'fromNode': 'shop', 'toNode': 'blend'},
          ],
        },
      ),
    );

    final result = await pipeline.commit(
      CommitInput(
        capture: capture,
        symbolId: 'daily-tasks',
        title: '2026-11-20',
        noteBody: '', // flat dump would fail — mindmap edges must win
        regions: regions,
      ),
    );

    expect(result.todoistSync?.createdCount, 2);
    expect(
      todoist.created.map((t) => '${t.labels.single}:${t.content}').toList(),
      ['high:Hue', 'shopping:portable blender'],
    );
    expect(await vault.exists('Organising/Daily/2026-11-20.md'), isFalse);
  });

  test(
    'daily-tasks mindmap with inward-drawn edges labels every name',
    () async {
      final regions = [
        const OcrRegion(
          id: 'hub',
          text: "Fri 27 Nov '26",
          confidence: 0.9,
          bbox: [0.4, 0.4, 0.2, 0.08],
        ),
        const OcrRegion(
          id: 'zoe',
          text: 'Zoë',
          confidence: 0.9,
          bbox: [0.1, 0.2, 0.2, 0.08],
        ),
        const OcrRegion(
          id: 'piano',
          text: 'Book piano lesson',
          confidence: 0.9,
          bbox: [0.05, 0.1, 0.2, 0.08],
        ),
        const OcrRegion(
          id: 'deshan',
          text: 'Deshan',
          confidence: 0.9,
          bbox: [0.7, 0.2, 0.2, 0.08],
        ),
        const OcrRegion(
          id: 'walk',
          text: 'Walk Sunday @ 07:30',
          confidence: 0.9,
          bbox: [0.8, 0.1, 0.2, 0.08],
        ),
        const OcrRegion(
          id: 'thabo',
          text: 'Thabo',
          confidence: 0.9,
          bbox: [0.4, 0.8, 0.2, 0.08],
        ),
      ];
      final capture = PendingCapture(
        pageId: '20261127-p7k2',
        imageBytes: _tinyPng(),
        capturedAt: DateTime.utc(2026, 11, 27, 8),
        meaning: MeaningResult(
          detectedGlyph: '·',
          regions: regions,
          pageGenre: 'visual',
          rawJson: {
            'canvas_nodes': [
              for (final r in regions)
                {
                  'id': r.id,
                  'type': 'text',
                  'text': r.text,
                  'x': 0,
                  'y': 0,
                  'width': 120,
                  'height': 48,
                },
            ],
            'canvas_edges': [
              {'id': 'e1', 'fromNode': 'zoe', 'toNode': 'hub'},
              {'id': 'e2', 'fromNode': 'piano', 'toNode': 'zoe'},
              {'id': 'e3', 'fromNode': 'hub', 'toNode': 'deshan'},
              {'id': 'e4', 'fromNode': 'deshan', 'toNode': 'walk'},
              {'id': 'e5', 'fromNode': 'hub', 'toNode': 'thabo'},
            ],
          },
        ),
      );

      final result = await pipeline.commit(
        CommitInput(
          capture: capture,
          symbolId: 'daily-tasks',
          title: '2026-11-27',
          noteBody: '',
          regions: regions,
        ),
      );

      expect(result.todoistSync?.labels, ['zoë', 'deshan', 'thabo']);
      expect(
        todoist.created.map((t) => '${t.labels.single}:${t.content}').toList(),
        ['zoë:Book piano lesson', 'deshan:Walk'],
      );
    },
  );

  test('daily-tasks unmatched done is recorded for Settings UI', () async {
    todoist.openTasks = [
      const TodoistTask(id: '1', content: 'Known task'),
    ];
    final capture = _capture(
      glyph: '·',
      regions: MockOcrClient.defaultTaskRegions,
    );
    const noteBody = '''
done:
- Known task
- Missing from Todoist
''';
    final result = await pipeline.commit(
      CommitInput(
        capture: capture,
        symbolId: 'daily-tasks',
        title: '2026-10-16',
        noteBody: noteBody,
        dailyMarkdown: noteBody,
      ),
    );

    expect(result.todoistSync?.completedCount, 1);
    expect(result.todoistSync?.unmatchedDone, ['Missing from Todoist']);
    final stored = await unmatched.read();
    expect(stored.single.content, 'Missing from Todoist');
  });

  test('daily-tasks without Todoist sync throws', () async {
    final bare = CommitPipeline(vault: vault);
    final capture = _capture(
      glyph: '·',
      regions: MockOcrClient.defaultTaskRegions,
    );
    expect(
      () => bare.commit(
        CommitInput(
          capture: capture,
          symbolId: 'daily-tasks',
          title: '2026-10-16',
          noteBody: 'high:\n- A',
        ),
      ),
      throwsA(isA<TodoistNotConfiguredException>()),
    );
  });

  test('fileStemFromTitle keeps typed name — no pageId suffix', () {
    expect(
      CommitPipeline.fileStemFromTitle('Attention is a muscle'),
      'Attention is a muscle',
    );
    expect(CommitPipeline.fileStemFromTitle('Hello/World'), 'Hello-World');
    expect(CommitPipeline.fileStemFromTitle('note.md'), 'note');
    expect(CommitPipeline.fileStemFromTitle('   '), 'Untitled');
    expect(
      CommitPipeline.fileStemFromTitle('Topic["image}]'),
      'Topic',
    );
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

class _FakeTodoistClient extends TodoistClient {
  _FakeTodoistClient({List<TodoistTask>? openTasks})
      : openTasks = List<TodoistTask>.from(openTasks ?? const []),
        super(apiToken: 'test-token', httpClient: _UnusedHttp());

  List<TodoistTask> openTasks;
  final List<TodoistTask> created = [];
  final List<String> closedIds = [];

  @override
  Future<Map<String, TodoistLabel>> ensureLabels(Iterable<String> names) async {
    return {for (final n in names) n: TodoistLabel(id: 'id-$n', name: n)};
  }

  @override
  Future<List<TodoistTask>> listOpenTasks() async =>
      List.unmodifiable(openTasks);

  @override
  Future<TodoistTask> createInboxTask({
    required String content,
    List<String> labels = const [],
    int? priority,
    String? parentId,
    DateTime? dueDate,
    bool dueHasTime = false,
    String? dueString,
    String? description,
    String? requestId,
  }) async {
    final task = TodoistTask(
      id: 'new-${created.length + 1}',
      content: content,
      labels: labels,
    );
    created.add(task);
    return task;
  }

  @override
  Future<TodoistTask> updateTask(
    String taskId, {
    String? content,
    int? priority,
    String? description,
    DateTime? dueDate,
    bool dueHasTime = false,
    String? dueString,
  }) async {
    return created.firstWhere((t) => t.id == taskId);
  }

  @override
  Future<void> closeTask(String taskId) async {
    closedIds.add(taskId);
    openTasks.removeWhere((t) => t.id == taskId);
  }
}

class _UnusedHttp extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw StateError('Fake Todoist client must not hit the network');
  }
}
