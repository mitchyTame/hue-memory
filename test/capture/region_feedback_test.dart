import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/capture/region_feedback.dart';
import 'package:hue_memory/vision/l_corner_regions.dart';

void main() {
  const region = PageRegion(id: 'r0', bbox: [0.1, 0.1, 0.4, 0.3]);

  test('empty feedback means whole-page OCR, not an error', () {
    const feedback = CaptureRegionFeedback();
    expect(feedback.lCornersDetected, isFalse);
    expect(feedback.usedWholePage, isTrue);
    expect(feedback.ocrRegion, isNull);
  });

  test('detected region with ocrRegion is region OCR', () {
    const feedback = CaptureRegionFeedback(
      detected: [region],
      ocrRegion: region,
    );
    expect(feedback.lCornersDetected, isTrue);
    expect(feedback.usedWholePage, isFalse);
    expect(feedback.ocrRegion?.id, 'r0');
  });

  test('detected but null ocrRegion is whole-page with L boxes', () {
    const feedback = CaptureRegionFeedback(detected: [region]);
    expect(feedback.lCornersDetected, isTrue);
    expect(feedback.usedWholePage, isTrue);
  });

  test('diagram skip is neither whole-page feedback nor L-corners', () {
    expect(CaptureRegionFeedback.diagramSkip.skippedForDiagram, isTrue);
    expect(CaptureRegionFeedback.diagramSkip.lCornersDetected, isFalse);
    expect(CaptureRegionFeedback.diagramSkip.usedWholePage, isFalse);
  });
}
