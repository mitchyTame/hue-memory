import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
import 'package:hue_memory/writers/canvas_writer.dart';
import 'package:hue_memory/writers/tag_builder.dart';

void main() {
  const builder = TagBuilder();

  test('builds nested tags along hub→spoke paths', () {
    const nodes = [
      CanvasNode(
        id: 'n1',
        type: 'text',
        text: 'Psychology',
        x: 0,
        y: 0,
        width: 100,
        height: 40,
      ),
      CanvasNode(
        id: 'n2',
        type: 'text',
        text: 'Memory',
        x: 100,
        y: 0,
        width: 100,
        height: 40,
      ),
      CanvasNode(
        id: 'n3',
        type: 'text',
        text: 'Encoding',
        x: 200,
        y: 0,
        width: 100,
        height: 40,
      ),
    ];
    const edges = [
      CanvasEdge(id: 'e1', fromNode: 'n1', toNode: 'n2'),
      CanvasEdge(id: 'e2', fromNode: 'n2', toNode: 'n3'),
    ];

    final tags = builder.fromCanvasNodes(nodes, edges: edges);
    expect(tags, contains('#psychology'));
    expect(tags, contains('#psychology/memory'));
    expect(tags, contains('#psychology/memory/encoding'));
    expect(builder.tagLine(tags), contains('#psychology/memory/encoding'));
    expect(
      builder.frontmatterTags(tags),
      contains('psychology/memory/encoding'),
    );
  });

  test('hub→spoke heuristic yields depth-2 tags', () {
    final regions = [
      const OcrRegion(id: 'n1', text: 'Psychology', confidence: 0.9),
      const OcrRegion(id: 'n2', text: 'Memory', confidence: 0.9),
      const OcrRegion(id: 'n3', text: 'Attention', confidence: 0.9),
    ];
    final tags = builder.fromRegions(regions);
    expect(tags, contains('#psychology'));
    expect(tags, contains('#psychology/memory'));
    expect(tags, contains('#psychology/attention'));
  });

  test('segment slugifies labels', () {
    expect(TagBuilder.segment('Working Memory'), 'working-memory');
    expect(TagBuilder.segment('  Encoding!! '), 'encoding');
  });
}
