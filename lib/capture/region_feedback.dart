import '../vision/l_corner_regions.dart';

/// UI-only feedback about L-corner detection for confirm overlays.
///
/// Never burned into the vault photo — confirm paints this on top of the preview.
class CaptureRegionFeedback {
  const CaptureRegionFeedback({
    this.detected = const [],
    this.ocrRegion,
    this.skippedForDiagram = false,
  });

  /// All L-corner quads found on the full capture.
  final List<PageRegion> detected;

  /// Region used for OCR crop, or null when OCR ran on the whole page.
  final PageRegion? ocrRegion;

  /// Diagram / △ path skipped L-corner detection.
  final bool skippedForDiagram;

  /// True when at least one L-corner region was found (optional marks).
  bool get lCornersDetected => detected.isNotEmpty;

  /// Whole-page OCR because no L-corners (or user chose Whole page).
  bool get usedWholePage => ocrRegion == null && !skippedForDiagram;

  static const none = CaptureRegionFeedback();
  static const diagramSkip = CaptureRegionFeedback(skippedForDiagram: true);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CaptureRegionFeedback &&
        other.skippedForDiagram == skippedForDiagram &&
        other.ocrRegion?.id == ocrRegion?.id &&
        _sameRegions(other.detected, detected);
  }

  @override
  int get hashCode => Object.hash(
        skippedForDiagram,
        ocrRegion?.id,
        Object.hashAll(detected.map((r) => r.id)),
      );

  static bool _sameRegions(List<PageRegion> a, List<PageRegion> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
      final ab = a[i].bbox;
      final bb = b[i].bbox;
      if (ab.length != bb.length) return false;
      for (var j = 0; j < ab.length; j++) {
        if (ab[j] != bb[j]) return false;
      }
    }
    return true;
  }
}
