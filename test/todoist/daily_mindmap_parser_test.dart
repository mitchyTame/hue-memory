import 'package:flutter_test/flutter_test.dart';
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
}
