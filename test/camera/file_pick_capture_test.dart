import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
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

  test('readPickedImageBytes prefers in-memory bytes', () async {
    final file = PlatformFile(
      name: 'page.png',
      size: 3,
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    expect(await readPickedImageBytes(file), [1, 2, 3]);
  });

  test('readPickedImageBytes falls back to path', () async {
    final temp = await File(
      '${Directory.systemTemp.path}/hue_pick_${DateTime.now().microsecondsSinceEpoch}.bin',
    ).create();
    await temp.writeAsBytes([9, 8, 7]);
    addTearDown(() => temp.deleteSync());

    final file = PlatformFile(
      name: 'page.jpg',
      size: 3,
      path: temp.path,
    );
    expect(await readPickedImageBytes(file), [9, 8, 7]);
  });

  test('readPickedImageBytes throws when empty', () async {
    final file = PlatformFile(name: 'empty.png', size: 0, bytes: Uint8List(0));
    expect(() => readPickedImageBytes(file), throwsStateError);
  });
}
