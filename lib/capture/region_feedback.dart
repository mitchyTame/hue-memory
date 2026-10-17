import '../vision/page_region.dart';

/// UI-only feedback about the OCR crop for confirm overlays.
///
/// Never burned into the vault photo — confirm paints this on top of the preview.
class CaptureRegionFeedback {
  const CaptureRegionFeedback({
    this.ocrRegion,
    this.skippedForDiagram = false,
  });

  /// Manual region used for OCR crop, or null when OCR ran on the whole page.
  final PageRegion? ocrRegion;

  /// Diagram / △ path skipped the region picker.
  final bool skippedForDiagram;

  /// True when Mitch framed a crop for OCR.
  bool get hasRegion => ocrRegion != null;

  /// Whole-page OCR (skipped region picker or chose Use whole page).
  bool get usedWholePage => ocrRegion == null && !skippedForDiagram;

  static const none = CaptureRegionFeedback();
  static const diagramSkip = CaptureRegionFeedback(skippedForDiagram: true);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CaptureRegionFeedback &&
        other.skippedForDiagram == skippedForDiagram &&
        other.ocrRegion?.id == ocrRegion?.id &&
        _sameBbox(other.ocrRegion?.bbox, ocrRegion?.bbox);
  }

  @override
  int get hashCode => Object.hash(
        skippedForDiagram,
        ocrRegion?.id,
        ocrRegion == null ? null : Object.hashAll(ocrRegion!.bbox),
      );

  static bool _sameBbox(List<double>? a, List<double>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
