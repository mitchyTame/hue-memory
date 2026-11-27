import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/gemini/obsidian_canvas_from_gemini.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
import 'package:hue_memory/todoist/daily_mindmap_parser.dart';
import 'package:hue_memory/writers/canvas_writer.dart';

void main() {
  const parser = DailyMindmapParser();

  List<OcrRegion> nodes(Map<String, String> labels) => [
        for (final e in labels.entries)
          OcrRegion(
            id: e.key,
            text: e.value,
            confidence: 0.9,
            bbox: const [0.1, 0.1, 0.2, 0.08],
          ),
      ];

  List<CanvasEdge> links(List<(String, String)> pairs) => [
        for (var i = 0; i < pairs.length; i++)
          CanvasEdge(
            id: 'e$i',
            fromNode: pairs[i].$1,
            toNode: pairs[i].$2,
          ),
      ];

  test('date hub → branches → leaves become labeled Todoist creates', () {
    // Matches Mitch’s · daily ink: center date, section icons, task leaves.
    final result = parser.parse(
      regions: nodes({
        'hub': "20 Nov '26",
        'shopping': 'shopping',
        'blender': 'portable blender',
        'done': 'Done',
        'high': 'High',
        'hue': 'Hue',
        'audit': 'Audit audio logs',
        'paused': 'Paused',
        'play': 'Playbour',
        'events': 'Events',
        'walk': 'Deshan walk Sunday @ 07:30',
        'reminders': 'Reminders',
        'car': 'Book Car Service',
        'screen': 'prostate screening',
      }),
      edges: links([
        ('hub', 'shopping'),
        ('shopping', 'blender'),
        ('hub', 'done'),
        ('hub', 'high'),
        ('high', 'hue'),
        ('high', 'audit'),
        ('hub', 'paused'),
        ('paused', 'play'),
        ('hub', 'events'),
        ('events', 'walk'),
        ('hub', 'reminders'),
        ('reminders', 'car'),
        ('reminders', 'screen'),
      ]),
    );

    expect(result.hubDate, isNotNull);
    expect(result.hubDate!.year, 2026);
    expect(result.hubDate!.month, 11);
    expect(result.hubDate!.day, 20);

    expect(
      result.sync.creates.map((c) => '${c.label}:${c.content}').toList(),
      [
        'shopping:portable blender',
        'high:Hue',
        'high:Audit audio logs',
        'paused:Playbour',
        'events:Deshan walk Sunday @ 07:30',
        'reminders:Book Car Service',
        'reminders:prostate screening',
      ],
    );
    expect(result.sync.done, isEmpty); // Done branch has no leaves
    expect(result.sync.creates.where((c) => c.label == 'high').first.priority, 4);
    expect(result.hasWork, isTrue);
    expect(result.structuredMarkdown, contains('**Important:**'));
    expect(result.structuredMarkdown, contains('- portable blender'));
  });

  test('done branch leaves go to close-list, not creates', () {
    final result = parser.parse(
      regions: nodes({
        'hub': '2026-11-20',
        'done': 'done',
        'a': 'Ship release',
        'high': 'high',
        'b': 'New work',
      }),
      edges: links([
        ('hub', 'done'),
        ('done', 'a'),
        ('hub', 'high'),
        ('high', 'b'),
      ]),
    );
    expect(result.sync.done, ['Ship release']);
    expect(result.sync.creates.single.content, 'New work');
  });

  test('flat OCR dump without edges yields no invented tasks', () {
    final result = parser.parse(
      regions: nodes({
        'n1': "20 Nov '26",
        'n2': 'shopping',
        'n3': 'portable blender',
        'n4': 'High',
        'n5': 'Hue',
      }),
      edges: const [],
    );
    expect(result.hasWork, isFalse);
  });

  test('links from a task become nested subtasks (parentNodeId)', () {
    final result = parser.parse(
      regions: nodes({
        'hub': '2026-11-20',
        'high': 'High',
        'hue': 'Hue',
        'a': 'Wire subtasks',
        'b': 'Link shared nodes',
      }),
      edges: links([
        ('hub', 'high'),
        ('high', 'hue'),
        ('hue', 'a'),
        ('hue', 'b'),
      ]),
    );

    expect(result.sync.creates, hasLength(3));
    final root = result.sync.creates.first;
    expect(root.content, 'Hue');
    expect(root.nodeId, 'hue');
    expect(root.parentNodeId, isNull);
    expect(root.dueDate, isNotNull);

    final subs = result.sync.creates.skip(1).toList();
    expect(subs.every((c) => c.parentNodeId == 'hue'), isTrue);
    expect(subs.map((c) => c.content).toList(), [
      'Wire subtasks',
      'Link shared nodes',
    ]);
  });

  test('multiple links to the same node keep one create + extra parents', () {
    final result = parser.parse(
      regions: nodes({
        'hub': '2026-11-20',
        'high': 'High',
        'shop': 'shopping',
        'a': 'Parent A',
        'b': 'Parent B',
        'shared': 'Shared follow-up',
      }),
      edges: links([
        ('hub', 'high'),
        ('hub', 'shop'),
        ('high', 'a'),
        ('shop', 'b'),
        ('a', 'shared'),
        ('b', 'shared'),
      ]),
    );

    final shared = result.sync.creates.where((c) => c.nodeId == 'shared');
    expect(shared, hasLength(1));
    expect(shared.single.parentNodeId, 'a');
    expect(shared.single.extraParentNodeIds, ['b']);
  });

  group('names off the day', () {
    // Gemini JSON shaped like a real hand-drawn daily: ink lines have no
    // arrowheads, so left-side branches come back pointing *at* the hub, one
    // box holds a heading plus its items, and one name has no tasks yet.
    const geminiDaily = '''
{"nodes":[
 {"id":"hub","type":"text","text":"Fri 27 Nov '26","x":0,"y":0},
 {"id":"b1","type":"text","text":"Deshan","x":300,"y":-200},
 {"id":"t1","type":"text","text":"Walk Sunday @ 07:30","x":520,"y":-260},
 {"id":"t2","type":"text","text":"Send braai list","x":520,"y":-160},
 {"id":"b2","type":"text","text":"Zoë","x":-300,"y":-200},
 {"id":"t3","type":"text","text":"Book piano lesson","x":-560,"y":-240},
 {"id":"b3","type":"text","text":"Shanolin","x":-300,"y":150},
 {"id":"t4","type":"text","text":"License Management","x":-560,"y":180},
 {"id":"b4","type":"text","text":"Errands\\n- Post office\\n- Pharmacy","x":300,"y":200},
 {"id":"b5","type":"text","text":"Thabo","x":0,"y":300},
 {"id":"b6","type":"text","text":"Notes","x":0,"y":-300},
 {"id":"t6","type":"text","text":"Long journal line","x":0,"y":-420}
],
"edges":[
 {"id":"e1","fromNode":"hub","fromSide":"right","toNode":"b1","toSide":"left"},
 {"id":"e2","fromNode":"b1","fromSide":"right","toNode":"t1","toSide":"left"},
 {"id":"e3","fromNode":"b1","fromSide":"right","toNode":"t2","toSide":"left"},
 {"id":"e4","fromNode":"b2","fromSide":"right","toNode":"hub","toSide":"left"},
 {"id":"e5","fromNode":"t3","fromSide":"right","toNode":"b2","toSide":"left"},
 {"id":"e6","fromNode":"b3","fromSide":"right","toNode":"hub","toSide":"left"},
 {"id":"e7","fromNode":"t4","fromSide":"right","toNode":"b3","toSide":"left"},
 {"id":"e8","fromNode":"hub","fromSide":"right","toNode":"b4","toSide":"left"},
 {"id":"e9","fromNode":"hub","fromSide":"bottom","toNode":"b5","toSide":"top"},
 {"id":"e10","fromNode":"b6","fromSide":"bottom","toNode":"hub","toSide":"top"},
 {"id":"e11","fromNode":"t6","fromSide":"bottom","toNode":"b6","toSide":"top"}
]}''';

    DailyMindmapParseResult parseGemini(String raw) {
      final draft = const ObsidianCanvasFromGemini(
        maxTextNodes: ObsidianCanvasFromGemini.diagramMaxTextNodes,
      ).parse(raw);
      return parser.parse(
        regions: draft.regions,
        edges: draft.edges,
        referenceDate: DateTime(2026, 11, 27),
      );
    }

    test('every name becomes a label; tasks keep their name', () {
      final result = parseGemini(geminiDaily);

      expect(result.hubDate, DateTime(2026, 11, 27));
      expect(result.sync.sectionLabels, [
        'deshan',
        'zoë',
        'shanolin',
        'errands',
        'thabo',
      ]);
      expect(
        result.sync.creates.map((c) => '${c.label}:${c.content}').toList(),
        [
          'deshan:Walk Sunday @ 07:30',
          'deshan:Send braai list',
          'zoë:Book piano lesson',
          'shanolin:License Management',
          'errands:Post office',
          'errands:Pharmacy',
        ],
      );
      expect(result.sync.creates.every((c) => c.parentNodeId == null), isTrue);
      expect(
        result.sync.creates.every((c) => c.dueDate == DateTime(2026, 11, 27)),
        isTrue,
      );
      expect(
        result.sync.creates.any((c) => c.content.contains('journal')),
        isFalse,
      );
    });

    test('every edge drawn inward still walks hub → name → task', () {
      final result = parser.parse(
        regions: nodes({
          'hub': "27 Nov '26",
          'a': 'Deshan',
          'a1': 'Walk Sunday',
          'a2': 'Braai',
          'b': 'Shanolin',
          'b1': 'Audit logs',
        }),
        edges: links([
          ('a1', 'a'),
          ('a2', 'a'),
          ('a', 'hub'),
          ('b1', 'b'),
          ('b', 'hub'),
        ]),
      );
      expect(
        result.sync.creates.map((c) => '${c.label}:${c.content}').toList(),
        ['deshan:Walk Sunday', 'deshan:Braai', 'shanolin:Audit logs'],
      );
    });

    test('undated hub with inward edges is found as the centre', () {
      final result = parser.parse(
        regions: nodes({
          'hub': 'Today',
          'a': 'Deshan',
          'a1': 'Walk',
          'a2': 'Braai',
          'a3': 'Call',
          'b': 'Zoë',
          'b1': 'Piano',
          'c': 'Thabo',
        }),
        edges: links([
          ('a1', 'a'),
          ('a2', 'a'),
          ('a3', 'a'),
          ('a', 'hub'),
          ('b1', 'b'),
          ('b', 'hub'),
          ('c', 'hub'),
        ]),
      );
      expect(result.sync.sectionLabels, ['deshan', 'zoë', 'thabo']);
      expect(result.sync.creates, hasLength(4));
    });

    test('undated single-branch drawing keeps the drawn root as hub', () {
      final result = parser.parse(
        regions: nodes({
          'hub': 'Today',
          'a': 'Deshan',
          'a1': 'Walk',
          'a2': 'Braai',
        }),
        edges: links([('hub', 'a'), ('a', 'a1'), ('a', 'a2')]),
      );
      expect(result.sync.sectionLabels, ['deshan']);
      expect(result.sync.creates.map((c) => c.content).toList(), [
        'Walk',
        'Braai',
      ]);
    });

    test('lines between two names do not nest one name under another', () {
      final result = parser.parse(
        regions: nodes({
          'hub': '2026-11-27',
          'a': 'Deshan',
          'a1': 'Walk',
          'b': 'Zoë',
          'b1': 'Piano',
        }),
        edges: links([
          ('hub', 'a'),
          ('hub', 'b'),
          ('a', 'b'),
          ('a', 'a1'),
          ('b', 'b1'),
        ]),
      );
      expect(
        result.sync.creates.map((c) => '${c.label}:${c.content}').toList(),
        ['deshan:Walk', 'zoë:Piano'],
      );
    });

    test('edges listed both ways do not duplicate tasks', () {
      final result = parser.parse(
        regions: nodes({'hub': '2026-11-27', 'a': 'Deshan', 'a1': 'Walk'}),
        edges: links([('hub', 'a'), ('a', 'hub'), ('a', 'a1'), ('a1', 'a')]),
      );
      expect(result.sync.creates.single.content, 'Walk');
      expect(result.sync.sectionLabels, ['deshan']);
    });

    test('icon, colon and inline-item names normalise to one label', () {
      final result = parser.parse(
        regions: nodes({
          'hub': '2026-11-27',
          'a': '🛒 Shopping:',
          'a1': 'Milk',
          'b': 'Thandiwé: call about lift club',
          'c': '**High**',
          'c1': 'Hue',
        }),
        edges: links([
          ('hub', 'a'),
          ('a', 'a1'),
          ('hub', 'b'),
          ('hub', 'c'),
          ('c', 'c1'),
        ]),
      );
      expect(result.sync.sectionLabels, ['shopping', 'thandiwé', 'high']);
      expect(
        result.sync.creates.map((c) => '${c.label}:${c.content}').toList(),
        ['shopping:Milk', 'thandiwé:call about lift club', 'high:Hue'],
      );
      expect(result.sync.creates.last.priority, 4);
    });

    test('a name with no tasks still counts as work (label only)', () {
      final result = parser.parse(
        regions: nodes({'hub': '2026-11-27', 'a': 'Thabo'}),
        edges: links([('hub', 'a')]),
      );
      expect(result.hasWork, isTrue);
      expect(result.sync.creates, isEmpty);
      expect(result.sync.sectionLabels, ['thabo']);
    });

    test('busy daily past the old 24-node cap keeps every name', () {
      final buffer = StringBuffer('{"nodes":[')
        ..write('{"id":"hub","type":"text","text":"27 Nov \'26"}');
      final edges = <String>[];
      for (var b = 1; b <= 8; b++) {
        buffer.write(',{"id":"b$b","type":"text","text":"Name $b"}');
        edges.add('{"fromNode":"hub","toNode":"b$b"}');
        for (var t = 1; t <= 3; t++) {
          buffer.write(',{"id":"b${b}t$t","type":"text","text":"Task $b.$t"}');
          edges.add('{"fromNode":"b$b","toNode":"b${b}t$t"}');
        }
      }
      buffer.write('],"edges":[${edges.join(',')}]}');

      final result = parseGemini(buffer.toString());
      expect(result.sync.sectionLabels, hasLength(8));
      expect(result.sync.creates, hasLength(24));
    });
  });
}
