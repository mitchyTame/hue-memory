import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
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
    expect(img['color'], CanvasWriter.ghostImageColor);

    final edges = decoded['edges'] as List<dynamic>;
    expect(edges, hasLength(1));
    final e1 = edges.first as Map<String, dynamic>;
    expect(e1['fromNode'], 'n1');
    expect(e1['toNode'], 'n2');
    expect(e1['toEnd'], 'arrow');
  });

  test('inkGhost false puts text nodes before the image file node', () {
    final doc = writer.buildVisualCanvas(
      sourceImage: 'captures/raw/page.jpg',
      textNodes: const [
        CanvasNode(
          id: 'n1',
          type: 'text',
          text: 'Idea',
          x: 10,
          y: 10,
          width: 100,
          height: 40,
        ),
      ],
      inkGhost: false,
    );
    final nodes = doc.toJson()['nodes'] as List<dynamic>;
    expect(nodes.first['id'], 'n1');
    expect(nodes.last['id'], 'img');
    expect((nodes.last as Map)['color'], isNull);
  });

  test('nodesFromRegions scales normalized bboxes onto image frame', () {
    const regions = [
      OcrRegion(
        id: 'n1',
        text: 'Central idea',
        confidence: 0.9,
        bbox: [0.35, 0.28, 0.30, 0.10],
      ),
      OcrRegion(
        id: 'n2',
        text: 'Branch',
        confidence: 0.8,
        bbox: [0.55, 0.48, 0.28, 0.09],
      ),
    ];
    final nodes = CanvasWriter.nodesFromRegions(
      regions,
      imageWidth: 480,
      imageHeight: 640,
    );
    expect(nodes, hasLength(2));
    expect(nodes[0].id, 'n1');
    expect(nodes[0].x, (0.35 * 480).round());
    expect(nodes[0].y, (0.28 * 640).round());
    expect(nodes[0].width, greaterThanOrEqualTo(120));
    expect(nodes[1].text, 'Branch');

    final edges = CanvasWriter.heuristicEdges(nodes);
    expect(edges, hasLength(1));
    expect(edges.first.fromNode, 'n1');
    expect(edges.first.toNode, 'n2');
  });
}
