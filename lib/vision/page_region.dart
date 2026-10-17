/// Normalized `[left, top, width, height]` (0–1) crop on a capture photo.
class PageRegion {
  const PageRegion({
    required this.id,
    required this.bbox,
  });

  final String id;

  /// `[left, top, width, height]` in normalized image space.
  final List<double> bbox;

  double get left => bbox[0];
  double get top => bbox[1];
  double get width => bbox[2];
  double get height => bbox[3];

  /// Manual OCR frame from the optional post-shutter picker.
  factory PageRegion.manual({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    return PageRegion(
      id: 'manual',
      bbox: [left, top, width, height],
    );
  }
}
