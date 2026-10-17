import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/capture/region_feedback.dart';
import 'package:hue_memory/vision/page_region.dart';

void main() {
  final region = PageRegion.manual(
    left: 0.1,
    top: 0.1,
    width: 0.4,
    height: 0.3,
  );

  test('empty feedback means whole-page OCR', () {
    const feedback = CaptureRegionFeedback();
    expect(feedback.hasRegion, isFalse);
    expect(feedback.usedWholePage, isTrue);
    expect(feedback.ocrRegion, isNull);
  });

  test('manual ocrRegion is region OCR', () {
    final feedback = CaptureRegionFeedback(ocrRegion: region);
    expect(feedback.hasRegion, isTrue);
    expect(feedback.usedWholePage, isFalse);
    expect(feedback.ocrRegion?.id, 'manual');
  });

  test('diagram skip is neither whole-page nor region', () {
    expect(CaptureRegionFeedback.diagramSkip.skippedForDiagram, isTrue);
    expect(CaptureRegionFeedback.diagramSkip.hasRegion, isFalse);
    expect(CaptureRegionFeedback.diagramSkip.usedWholePage, isFalse);
  });
}
