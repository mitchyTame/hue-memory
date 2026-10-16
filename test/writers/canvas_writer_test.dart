import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/writers/canvas_writer.dart';

void main() {
  const writer = CanvasWriter();

  test('JSON Canvas shape includes image file node and edges', () {
    final doc = writer.buildVisualCanvas(
      sourceImage: 'captures/raw/20261016-p7k2.jpg',
      textNodes: const [
        CanvasNode(
          id: 'n1',
          type: 'text',
          text: 'Central idea',
          x: 0,
          y: 0,
          width: 260,
          height: 80,
        ),
        CanvasNode(
          id: 'n2',
          type: 'text',
          text: 'Branch',
          x: 320,
          y: -40,
          width: 220,
          height: 80,
        ),
      ],
      edges: const [
        CanvasEdge(id: 'e1', fromNode: 'n1', toNode: 'n2'),
      ],
    );

    final json = writer.writeJson(doc);
    final decoded = jsonDecode(json) as Map<String, dynamic>;

    expect(decoded.keys, containsAll(['nodes', 'edges']));
    final nodes = decoded['nodes'] as List<dynamic>;
    expect(nodes.length, 3);

    final img = nodes.first as Map<String, dynamic>;
    expect(img['id'], 'img');
    expect(img['type'], 'file');
    expect(img['file'], 'captures/raw/20261016-p7k2.jpg');
    expect(img['width'], 480);
    expect(img['height'], 640);

    final edges = decoded['edges'] as List<dynamic>;
    expect(edges, hasLength(1));
    final e1 = edges.first as Map<String, dynamic>;
    expect(e1['fromNode'], 'n1');
    expect(e1['toNode'], 'n2');
    expect(e1['toEnd'], 'arrow');
  });
}
