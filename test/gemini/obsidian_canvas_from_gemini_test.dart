import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/gemini/obsidian_canvas_from_gemini.dart';
import 'package:hue_memory/writers/canvas_writer.dart';

void main() {
  const parser = ObsidianCanvasFromGemini();

  test('parses Chapter 1 smoke JSON — connected edges, no file node from model',
      () {
    final raw = File(
      'test/fixtures/gemini-chapter1-canvas-smoke.json',
    ).readAsStringSync();
    final draft = parser.parse(raw);

    expect(draft.textNodes, isNotEmpty);
    expect(draft.textNodes.any((n) => n.type == 'file'), isFalse);
    expect(draft.edges, isNotEmpty);
    expect(draft.regions.length, draft.textNodes.length);

    final ids = draft.textNodes.map((n) => n.id).toSet();
    for (final e in draft.edges) {
      expect(ids.contains(e.fromNode), isTrue);
      expect(ids.contains(e.toNode), isTrue);
    }

    // Hub connectivity: every node appears in at least one edge (or is alone).
    final linked = <String>{};
    for (final e in draft.edges) {
      linked.add(e.fromNode);
      linked.add(e.toNode);
    }
    expect(linked.length, greaterThanOrEqualTo(draft.textNodes.length - 0));
  });

  test('strips markdown fences and ring-layouts when coords missing', () {
    const raw = '''
```json
{"nodes":[{"id":"a","type":"text","text":"Hub"},{"id":"b","type":"text","text":"Spoke"}],"edges":[]}
```
''';
    final draft = parser.parse(raw);
    expect(draft.textNodes, hasLength(2));
    expect(draft.edges, isNotEmpty);
    expect(draft.edges.first.fromNode, 'a');
    expect(draft.edges.first.toNode, 'b');
    // Ring layout should move spoke off origin.
    expect(
      draft.textNodes[1].x != 0 || draft.textNodes[1].y != 0,
      isTrue,
    );
  });

  test('ensureConnected adds hub edges for orphans', () {
    final nodes = [
      const CanvasNode(
        id: 'h',
        type: 'text',
        text: 'Hub',
        x: 0,
        y: 0,
        width: 100,
        height: 40,
      ),
      const CanvasNode(
        id: 'o',
        type: 'text',
        text: 'Orphan',
        x: 200,
        y: 0,
        width: 100,
        height: 40,
      ),
    ];
    final edges = ObsidianCanvasFromGemini.ensureConnected(nodes, const []);
    expect(edges, hasLength(1));
    expect(edges.first.fromNode, 'h');
    expect(edges.first.toNode, 'o');
  });

  test('buildDiagramCanvas injects centered ghost file node', () {
    const writer = CanvasWriter();
    final draft = parser.parse(
      jsonEncode({
        'nodes': [
          {
            'id': 'center',
            'type': 'text',
            'text': 'Topic',
            'x': 0,
            'y': 0,
            'width': 200,
            'height': 80,
          },
          {
            'id': 's1',
            'type': 'text',
            'text': 'Branch',
            'x': 300,
            'y': 0,
            'width': 180,
            'height': 70,
          },
        ],
        'edges': [
          {
            'id': 'e1',
            'fromNode': 'center',
            'toNode': 's1',
            'fromSide': 'right',
            'toSide': 'left',
          },
        ],
      }),
    );
    final doc = writer.buildDiagramCanvas(
      sourceImage: 'captures/raw/p1.png',
      textNodes: draft.textNodes,
      edges: draft.edges,
    );
    final files = doc.nodes.where((n) => n.type == 'file').toList();
    expect(files, hasLength(1));
    expect(files.first.file, 'captures/raw/p1.png');
    expect(doc.edges.first.fromSide, 'right');
  });
}
