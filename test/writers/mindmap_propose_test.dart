import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/writers/mindmap_propose.dart';

void main() {
  test('structureFromOcrMarkdown yields short labels, not page dump', () {
    final md = '''
△ Hub idea

Spoke one
Spoke two
Spoke three
''';
    final structure = MindmapPropose.structureFromOcrMarkdown(md);
    expect(structure.nodes, isNotEmpty);
    expect(structure.nodes.length, lessThanOrEqualTo(MindmapPropose.maxLabels));
    expect(structure.source, 'ocr');
    for (final n in structure.nodes) {
      expect(n.label.length, lessThanOrEqualTo(MindmapPropose.maxLabelChars));
    }
    final regions = MindmapPropose.regionsFromStructure(structure);
    expect(regions.length, structure.nodes.length);
    expect(regions.first.bbox, isNotNull);
    expect(regions.first.bbox!.length, 4);
  });

  test('truncateLoopingProse cuts repeated lines', () {
    final loop = List.filled(12, 'Same long label again').join('\n');
    final cut = MindmapPropose.truncateLoopingProse(loop);
    expect(cut.split('\n').length, lessThan(12));
    expect(MindmapPropose.looksLikeLoopingProse(loop), isTrue);
  });

  test('parseJson keeps balanced object and normalized coords', () {
    const raw = '''
Here is noise {"nodes":[{"id":"a","label":"Hub","x":0.4,"y":0.3},
{"id":"b","label":"Spoke","x":70,"y":50}],"edges":[{"from":"a","to":"b"}]} trailing
''';
    final structure = MindmapStructure.parseJson(raw);
    expect(structure.nodes, hasLength(2));
    expect(structure.nodes.first.x, closeTo(0.4, 0.001));
    expect(structure.nodes.last.x, closeTo(0.7, 0.001));
    expect(structure.edges, hasLength(1));
    expect(structure.source, 'vision');
  });

  test('vision prompts prioritize handwriting and coverage', () {
    final user = MindmapPropose.visionUserPrompt(const ['Hub', 'Spoke']);
    expect(user, contains('Hub'));
    expect(user, contains('Spoke'));
    expect(MindmapPropose.visionSystemPrompt, contains('JSON'));
    expect(MindmapPropose.visionSystemPrompt, contains('handwriting'));
    expect(MindmapPropose.visionSystemPrompt, contains('EVERY major'));
    expect(MindmapPropose.visionMaxTokens, greaterThanOrEqualTo(768));
  });

  test('merge keeps vision text when OCR disagrees; keeps vision xy', () {
    final vision = MindmapStructure.parseJson('''
{"nodes":[{"id":"n1","text":"Focus loop","x":0.3,"y":0.3},
{"id":"n2","text":"Deep work","x":0.7,"y":0.2}],
"edges":[{"from":"n1","to":"n2"}]}
''');
    final merged = MindmapPropose.mergeOcrLabelsOntoVision(
      ocrLabels: const ['Central hub', 'Outer spoke'],
      vision: vision,
    );
    expect(merged.source, 'merged');
    expect(merged.nodes.first.label, 'Focus loop');
    expect(merged.nodes.first.x, closeTo(0.3, 0.001));
    expect(merged.nodes[1].label, 'Deep work');
    // Unmatched OCR labels are appended (missing-box recovery).
    expect(merged.nodes.length, greaterThanOrEqualTo(2));
    expect(
      merged.nodes.any((n) => n.label.toLowerCase().contains('central')),
      isTrue,
    );
  });

  test('placeNormBox preserves vision coords near edges', () {
    final box = MindmapPropose.placeNormBox(left: 0.85, top: 0.9);
    expect(box.left + box.width, lessThanOrEqualTo(1.0 + 1e-9));
    expect(box.top + box.height, lessThanOrEqualTo(1.0 + 1e-9));
    expect(box.left, greaterThan(0.5));
    expect(box.top, greaterThan(0.5));
  });

  test('merge fills empty vision stub from fuzzy OCR hint only', () {
    const vision = MindmapStructure(
      nodes: [
        MindmapNode(id: 'n1', label: '', x: 0.4, y: 0.4),
        MindmapNode(id: 'n2', label: 'Spoke', x: 0.7, y: 0.2),
      ],
      source: 'vision',
    );
    final merged = MindmapPropose.mergeOcrLabelsOntoVision(
      ocrLabels: const ['Hub idea', 'Spoke'],
      vision: vision,
    );
    expect(merged.nodes.first.label, 'Hub idea');
    expect(merged.nodes[1].label, 'Spoke');
  });
}
