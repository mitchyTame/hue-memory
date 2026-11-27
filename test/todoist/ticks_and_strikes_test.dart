import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/gemini/capture_coordinator.dart';
import 'package:hue_memory/gemini/gemini_client.dart';
import 'package:hue_memory/gemini/gemini_settings.dart';
import 'package:hue_memory/gemini/obsidian_canvas_from_gemini.dart';
import 'package:hue_memory/ocr/mock_ocr_client.dart';
import 'package:hue_memory/todoist/daily_todoist_parser.dart';
import 'package:hue_memory/todoist/daily_todoist_plan.dart';
import 'package:hue_memory/todoist/task_text.dart';

/// Records the diagram prompt and answers with a canvas where Gemini flagged
/// the ticked / struck tasks as done.
class _RecordingGemini extends GeminiClient {
  _RecordingGemini(this.reply) : super(apiKey: 'k');

  final String reply;
  final List<bool> dailyFlags = [];

  @override
  Future<String> diagramCanvasJson({
    required Uint8List imageBytes,
    required String mimeType,
    bool dailyTasks = false,
  }) async {
    dailyFlags.add(dailyTasks);
    return reply;
  }
}

const _dailyCanvas = '''
{"nodes":[
 {"id":"hub","type":"text","text":"27 Nov 2026","x":0,"y":0},
 {"id":"a","type":"text","text":"Errands","x":200,"y":0},
 {"id":"a1","type":"text","text":"bolt | 16:50","x":400,"y":0,"done":true},
 {"id":"a2","type":"text","text":"Post office","x":400,"y":80,"done":true},
 {"id":"a3","type":"text","text":"Pharmacy","x":400,"y":160}
],
"edges":[
 {"id":"e1","fromNode":"hub","toNode":"a"},
 {"id":"e2","fromNode":"a","toNode":"a1"},
 {"id":"e3","fromNode":"a","toNode":"a2"},
 {"id":"e4","fromNode":"a","toNode":"a3"}
]}
''';

void main() {
  group('TaskText: a tick or a strike-through is done', () {
    for (final line in [
      '~~bolt~~ | 16:50',
      '- ~~bolt | 16:50~~',
      '~bolt | 16:50~',
      '<s>bolt | 16:50</s>',
      '<del>bolt</del> | 16:50',
      'b\u0336o\u0336l\u0336t\u0336 | 16:50',
      '✓ bolt | 16:50',
      'bolt | 16:50 ✅',
      '- [x] bolt | 16:50',
      '☑ bolt | 16:50',
    ]) {
      test(line, () {
        expect(TaskText.isTicked(line), isTrue);
        expect(TaskText.core(line), 'bolt');
      });
    }

    test('an unmarked line is not done', () {
      expect(TaskText.isTicked('bolt | 16:50'), isFalse);
      expect(TaskText.isTicked('approx ~5 things'), isFalse);
    });

    test('a word struck out mid-line is a correction, not done', () {
      expect(TaskText.isTicked('Call ~~mum~~ dad'), isFalse);
      expect(TaskText.withoutMarks('Call ~~mum~~ dad'), 'Call dad');
    });
  });

  group('markdown / OCR text path', () {
    test('struck and ticked items close tasks; plain ones are created', () {
      final r = const DailyTodoistParser().parse(
        'high:\n'
        '- ~~bolt~~ | 16:50\n'
        '- [x] Call mum\n'
        '- <s>Pay rent</s>\n'
        '- Buy milk\n',
        pageDate: DateTime(2026, 11, 27),
      );
      expect(r.done, ['bolt | 16:50', 'Call mum', 'Pay rent']);
      expect(r.creates.map((c) => c.content), ['Buy milk']);
    });
  });

  group('Gemini diagram path', () {
    test('the daily addition is not part of the shared △ prompt', () {
      expect(
        GeminiClient.diagramCanvasPrompt,
        isNot(contains(GeminiClient.dailyTasksPromptAddition)),
      );
      expect(GeminiClient.diagramCanvasPrompt, isNot(contains('"done"')));
      expect(GeminiClient.dailyTasksPromptAddition, contains('"done": true'));
      expect(GeminiClient.dailyTasksPromptAddition, contains('struck'));
    });

    test('a done flag becomes a tick only when asked (daily pages)', () {
      const parser = ObsidianCanvasFromGemini(
        maxTextNodes: ObsidianCanvasFromGemini.diagramMaxTextNodes,
      );
      final plain = parser.parse(_dailyCanvas);
      expect(plain.textNodes.map((n) => n.text), [
        '27 Nov 2026',
        'Errands',
        'bolt | 16:50',
        'Post office',
        'Pharmacy',
      ]);
      final daily = parser.parse(_dailyCanvas, markDone: true);
      expect(daily.textNodes.map((n) => n.text), [
        '27 Nov 2026',
        'Errands',
        '✓ bolt | 16:50',
        '✓ Post office',
        'Pharmacy',
      ]);
    });

    Future<CoordinatedCapture> run(_RecordingGemini gemini, {required bool daily}) {
      final coord = CaptureCoordinator(
        geminiSettings: MemoryGeminiSettingsStore(
          const GeminiSettings(apiKey: 'k', consentGiven: true, useLive: true),
        ),
        ocr: MockOcrClient(),
        geminiFactory: (_) => gemini,
        prepareImage: (bytes, {imageMimeType, extensionHint, maxSide = 0}) async =>
            (bytes: bytes, mime: 'image/png'),
      );
      return coord.run(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        forceDiagram: true,
        dailyTasks: daily,
      );
    }

    test('· daily capture asks for done flags and plans ticked items as done',
        () async {
      final gemini = _RecordingGemini(_dailyCanvas);
      final captured = await run(gemini, daily: true);
      expect(gemini.dailyFlags, [true]);

      final plan = DailyTodoistPlanner(clock: () => DateTime(2026, 11, 27, 9))
          .planFromMeaning(
        meaning: captured.meaning,
        regions: captured.meaning.regions,
        markdown: '',
      );
      expect(plan.done.map((d) => d.content), ['bolt | 16:50', 'Post office']);
      expect(plan.creates.map((t) => t.content), ['Pharmacy']);
    });

    test('a △ capture keeps the shared prompt and node text', () async {
      final gemini = _RecordingGemini(_dailyCanvas);
      final captured = await run(gemini, daily: false);
      expect(gemini.dailyFlags, [false]);
      expect(
        captured.meaning.regions.map((r) => r.text),
        contains('bolt | 16:50'),
      );
    });
  });
}
