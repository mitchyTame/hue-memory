import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/ocr/configurable_ocr_client.dart';
import 'package:hue_memory/ocr/mistral_ocr_client.dart';
import 'package:hue_memory/ocr/mistral_sdk.dart';
import 'package:hue_memory/ocr/mock_ocr_client.dart';
import 'package:hue_memory/ocr/ocr_settings.dart';
import 'package:hue_memory/writers/mindmap_propose.dart';
import 'package:mistralai_dart/mistralai_dart.dart';

Future<({Uint8List bytes, String mime})> _identityPrepare(
  Uint8List bytes, {
  String? imageMimeType,
  String? extensionHint,
  int maxSide = 2048,
}) async {
  // Encode maxSide into payload length so tests can tell OCR vs vision prepare.
  final pad = maxSide >= 3000 ? 2 : 0;
  return (
    bytes: Uint8List.fromList([...bytes, ...List.filled(pad, 0)]),
    mime: imageMimeType ?? 'image/png',
  );
}

void main() {
  test('MistralOcrClient uses SDK OCR and parses MeaningResult', () async {
    final fake = FakeMistralSdk(
      ocrResponse: const OcrResponse(
        model: 'mistral-ocr-latest',
        pages: [
          OcrPage(index: 0, markdown: '∼ Fleeting thought\n\nMore text'),
        ],
      ),
    );
    final client = MistralOcrClient(
      apiKey: 'test-key',
      prepareImage: _identityPrepare,
      sdk: fake,
    );

    final result = await client.extractMeaning(
      Uint8List.fromList([1, 2, 3]),
      imageMimeType: 'image/png',
    );
    expect(fake.ocrCalls, 1);
    expect(fake.lastOcrMime, 'image/png');
    expect(result.detectedGlyph, '∼');
    expect(result.regions.first.text, contains('Fleeting'));
  });

  test('MistralOcrClient surfaces SDK ApiException message', () async {
    final fake = FakeMistralSdk(
      ocrError: const ApiException(
        statusCode: 400,
        message: 'Invalid base64 image data',
      ),
    );
    final client = MistralOcrClient(
      apiKey: 'k',
      prepareImage: _identityPrepare,
      sdk: fake,
    );
    try {
      await client.extractMeaning(Uint8List.fromList([9]));
      fail('expected MistralOcrException');
    } on MistralOcrException catch (e) {
      expect(e.readable, contains('Invalid base64 image data'));
      expect(e.statusCode, 400);
    }
  });

  test('MistralOcrClient surfaces 422 with concrete detail when present', () async {
    final fake = FakeMistralSdk(
      ocrError: const ApiException(
        statusCode: 422,
        message: 'Validation error',
        details: [
          {
            'detail': [
              {'msg': 'Input should be a valid dictionary or string'},
            ],
          },
        ],
      ),
    );
    final client = MistralOcrClient(
      apiKey: 'k',
      prepareImage: _identityPrepare,
      sdk: fake,
    );
    try {
      await client.extractMeaning(Uint8List.fromList([9]));
      fail('expected MistralOcrException');
    } on MistralOcrException catch (e) {
      expect(e.statusCode, 422);
      expect(e.readable, contains('Input should be a valid dictionary'));
    }
  });

  test('MistralOcrClient maps auth failure', () async {
    final fake = FakeMistralSdk(
      ocrError: const AuthenticationException(message: 'Unauthorized'),
    );
    final client = MistralOcrClient(
      apiKey: 'bad',
      prepareImage: _identityPrepare,
      sdk: fake,
    );
    expect(
      () => client.extractMeaning(Uint8List.fromList([9])),
      throwsA(
        isA<MistralOcrException>().having(
          (e) => e.readable,
          'readable',
          contains('API key'),
        ),
      ),
    );
  });

  test('visual OCR triggers vision structure and merges coords', () async {
    final fake = FakeMistralSdk(
      ocrResponse: const OcrResponse(
        model: 'mistral-ocr-latest',
        pages: [
          OcrPage(
            index: 0,
            markdown: '△ Hub idea\n\nSpoke A\n\nSpoke B',
          ),
        ],
      ),
      visionJson: '''
{"nodes":[
  {"id":"n1","label":"hub","x":0.42,"y":0.38},
  {"id":"n2","label":"spoke a","x":0.12,"y":0.18},
  {"id":"n3","label":"spoke b","x":0.70,"y":0.20}
],"edges":[{"from":"n1","to":"n2"},{"from":"n1","to":"n3"}]}
''',
    );
    final client = MistralOcrClient(
      apiKey: 'test-key',
      prepareImage: _identityPrepare,
      sdk: fake,
      visionModel: kDefaultVisionModel,
    );

    final result = await client.extractMeaning(
      Uint8List.fromList([1, 2, 3]),
      imageMimeType: 'image/png',
    );

    expect(fake.ocrCalls, 1);
    expect(fake.visionCalls, 1);
    expect(fake.lastVisionModel, kDefaultVisionModel);
    expect(fake.lastVisionMaxTokens, MindmapPropose.visionMaxTokens);
    expect(MindmapPropose.visionMaxTokens, greaterThanOrEqualTo(768));
    expect(fake.lastVisionOcrLabels, isNotEmpty);
    // Vision prepare uses a higher maxSide than OCR (padded identity prepare).
    expect(fake.lastVisionBytes!.length, greaterThan(fake.lastOcrBytes!.length));
    expect(result.pageGenre, 'visual');
    expect(result.rawJson['vision_used'], isTrue);
    expect(result.rawJson['hybrid_mindmap'], isTrue);
    expect(result.regions, hasLength(3));
    // Vision x,y kept as region bbox left/top.
    expect(result.regions.first.bbox![0], closeTo(0.42, 0.001));
    expect(result.regions.first.bbox![1], closeTo(0.38, 0.001));
    final mindmap = result.rawJson['mindmap'] as Map;
    expect(mindmap['source'], 'merged');
    expect((mindmap['edges'] as List), hasLength(2));
  });

  test('non-visual OCR skips vision structure call', () async {
    final fake = FakeMistralSdk(
      ocrResponse: const OcrResponse(
        model: 'mistral-ocr-latest',
        pages: [
          OcrPage(index: 0, markdown: '∼ Fleeting only'),
        ],
      ),
    );
    final client = MistralOcrClient(
      apiKey: 'test-key',
      prepareImage: _identityPrepare,
      sdk: fake,
    );

    await client.extractMeaning(Uint8List.fromList([1]));
    expect(fake.ocrCalls, 1);
    expect(fake.visionCalls, 0);
  });

  test('vision failure soft-falls back to OCR mindmap structure', () async {
    final fake = FakeMistralSdk(
      ocrResponse: const OcrResponse(
        model: 'mistral-ocr-latest',
        pages: [
          OcrPage(index: 0, markdown: '△ Central\n\nLeaf'),
        ],
      ),
      visionError: const ApiException(statusCode: 500, message: 'vision down'),
    );
    final client = MistralOcrClient(
      apiKey: 'test-key',
      prepareImage: _identityPrepare,
      sdk: fake,
    );

    final result = await client.extractMeaning(Uint8List.fromList([1]));
    expect(fake.visionCalls, 1);
    expect(result.pageGenre, 'visual');
    expect(result.rawJson['vision_used'], isFalse);
    expect(result.rawJson['vision_error'], contains('vision down'));
    expect(result.regions, isNotEmpty);
  });

  test('ConfigurableOcrClient uses mock until live+consent+key', () async {
    final store = MemoryOcrSettingsStore(
      const OcrSettings(apiKey: 'k', consentGiven: false, useLive: true),
    );
    final mock = MockOcrClient(glyph: '∼');
    var liveCalls = 0;
    final ocr = ConfigurableOcrClient(
      settings: store,
      mock: mock,
      mistralFactory: (key) {
        liveCalls++;
        return MistralOcrClient(
          apiKey: key,
          prepareImage: _identityPrepare,
          sdk: FakeMistralSdk(
            ocrError: const ApiException(statusCode: 500, message: 'boom'),
          ),
        );
      },
    );

    await ocr.extractMeaning(Uint8List.fromList([1]));
    expect(mock.callCount, 1);
    expect(liveCalls, 0);

    await store.write(
      const OcrSettings(apiKey: 'k', consentGiven: true, useLive: true),
    );
    liveCalls = 0;
    mock.callCount = 0;

    await expectLater(
      ocr.extractMeaning(Uint8List.fromList([1])),
      throwsA(isA<MistralOcrException>()),
    );
    expect(mock.callCount, 0);
    expect(liveCalls, 1);
  });
}
