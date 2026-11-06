import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/gemini/gemini_client.dart';
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

  test('strips markdown fences; keeps Gemini edges without ring tidy', () {
    const raw = '''
```json
{"nodes":[{"id":"a","type":"text","text":"Hub"},{"id":"b","type":"text","text":"Spoke"}],"edges":[{"id":"e1","fromNode":"a","toNode":"b"}]}
```
''';
    final draft = parser.parse(raw);
    expect(draft.textNodes, hasLength(2));
    // No ringLayout — coords stay as model left them (here 0,0).
    expect(draft.textNodes[0].x, 0);
    expect(draft.textNodes[1].x, 0);
    // Model edges kept; no invented hub spokes when edges empty.
    expect(draft.edges, hasLength(1));
    expect(draft.edges.first.fromNode, 'a');
    expect(draft.edges.first.toNode, 'b');
  });

  test('invalid JSON throws GeminiException not FormatException', () {
    expect(
      () => parser.parse('not-json-at-all {{{'),
      throwsA(
        isA<GeminiException>().having(
          (e) => e.readable.toLowerCase(),
          'readable',
          contains('invalid'),
        ),
      ),
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

  test('keeps Enhanced Bot typed prefixes on text nodes; skips file nodes', () {
    final draft = parser.parse(
      jsonEncode({
        'nodes': [
          {
            'id': 'meta',
            'type': 'text',
            'text': '[META] scrap · 6 Nov',
            'x': -40,
            'y': -200,
            'width': 200,
            'height': 64,
          },
          {
            'id': 'sum',
            'type': 'text',
            'text': '[SUMMARY] dentist + email follow-ups',
            'x': 180,
            'y': -200,
            'width': 240,
            'height': 64,
          },
          {
            'id': 'evt',
            'type': 'text',
            'text': '[EVENT] Dentist Thu 10:00',
            'x': -40,
            'y': 0,
            'width': 220,
            'height': 72,
          },
          {
            'id': 'task',
            'type': 'text',
            'text': '[TASK] Book taxi',
            'x': 220,
            'y': 0,
            'width': 180,
            'height': 64,
          },
          {
            'id': 'q',
            'type': 'text',
            'text': '[QUESTION] Insurance covers?',
            'x': -40,
            'y': 120,
            'width': 220,
            'height': 64,
          },
          {
            'id': 'img',
            'type': 'file',
            'file': 'captures/raw/ignore.jpg',
            'x': 0,
            'y': 0,
            'width': 100,
            'height': 100,
          },
        ],
        'edges': [
          {'id': 'e1', 'fromNode': 'sum', 'toNode': 'evt'},
          {'id': 'e2', 'fromNode': 'sum', 'toNode': 'task'},
        ],
      }),
    );

    expect(draft.textNodes, hasLength(5));
    expect(draft.textNodes.any((n) => n.type == 'file'), isFalse);
    expect(
      draft.textNodes.map((n) => n.text),
      everyElement(startsWith('[')),
    );
    expect(
      draft.textNodes.map((n) => n.text),
      containsAll([
        '[META] scrap · 6 Nov',
        '[SUMMARY] dentist + email follow-ups',
        '[EVENT] Dentist Thu 10:00',
        '[TASK] Book taxi',
        '[QUESTION] Insurance covers?',
      ]),
    );
    expect(draft.edges, hasLength(2));
  });

  test('buildDiagramCanvas places ghost photo above the idea graph', () {
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
    expect(files.first.y, 0);
    final texts = doc.nodes.where((n) => n.type == 'text').toList();
    final minTextY = texts.map((n) => n.y).reduce((a, b) => a < b ? a : b);
    expect(
      minTextY,
      greaterThanOrEqualTo(
        files.first.height + CanvasWriter.photoAboveGap,
      ),
    );
    expect(doc.edges.first.fromSide, 'right');
  });
}
