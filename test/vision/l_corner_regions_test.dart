import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/vision/l_corner_regions.dart';
import 'package:image/image.dart' as img;

Uint8List _blankPng({int w = 200, int h = 280}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(245, 245, 240));
  return Uint8List.fromList(img.encodePng(image));
}

/// Draw a thick L-corner (two arms) in dark ink.
void _drawL(
  img.Image image, {
  required int x,
  required int y,
  required int hArm,
  required int vArm,
  required bool right,
  required bool down,
}) {
  final ink = img.ColorRgb8(10, 10, 10);
  final dx = right ? 1 : -1;
  final dy = down ? 1 : -1;
  for (var i = 0; i <= hArm; i++) {
    final px = x + dx * i;
    if (px < 0 || px >= image.width) continue;
    for (var t = 0; t < 4; t++) {
      final py = y + (down ? t : -t);
      if (py >= 0 && py < image.height) image.setPixel(px, py, ink);
    }
  }
  for (var i = 0; i <= vArm; i++) {
    final py = y + dy * i;
    if (py < 0 || py >= image.height) continue;
    for (var t = 0; t < 4; t++) {
      final px = x + (right ? t : -t);
      if (px >= 0 && px < image.width) image.setPixel(px, py, ink);
    }
  }
}

void main() {
  test('blank page yields no L-corner regions', () {
    final regions = const LCornerRegionDetector().detect(_blankPng());
    expect(regions, isEmpty);
  });

  test('four L-corners form one page region', () {
    final image = img.Image(width: 320, height: 420);
    img.fill(image, color: img.ColorRgb8(245, 245, 240));
    const arm = 40;
    // TL TR
    // BL BR
    _drawL(image, x: 40, y: 50, hArm: arm, vArm: arm, right: true, down: true);
    _drawL(
      image,
      x: 260,
      y: 50,
      hArm: arm,
      vArm: arm,
      right: false,
      down: true,
    );
    _drawL(
      image,
      x: 40,
      y: 340,
      hArm: arm,
      vArm: arm,
      right: true,
      down: false,
    );
    _drawL(
      image,
      x: 260,
      y: 340,
      hArm: arm,
      vArm: arm,
      right: false,
      down: false,
    );
    final bytes = Uint8List.fromList(img.encodePng(image));
    final regions = const LCornerRegionDetector().detect(bytes);
    expect(regions, isNotEmpty);
    expect(regions.first.width, greaterThan(0.4));
    expect(regions.first.height, greaterThan(0.4));
  });
}
