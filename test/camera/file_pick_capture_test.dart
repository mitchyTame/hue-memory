import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/camera/file_pick_capture.dart';

void main() {
  test('imageExtensionOf normalizes jpeg and unknowns', () {
    expect(imageExtensionOf('a.JPEG', null), 'jpg');
    expect(imageExtensionOf('shot.png', '/tmp/shot.png'), 'png');
    expect(imageExtensionOf('x.webp', null), 'webp');
    expect(imageExtensionOf('noext', null), 'jpg');
    expect(imageExtensionOf('doc.pdf', null), 'jpg');
  });
}
