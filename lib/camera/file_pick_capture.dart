import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'camera_capture.dart';

/// Picks an image from the filesystem / gallery (Linux desktop + Android).
///
/// TODO(camera): Prefer live CameraCapture on Android when available.
class FilePickCapture implements CameraCapture {
  @override
  Future<CaptureResult> capturePage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      throw CaptureCancelled();
    }
    final file = result.files.single;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Could not read selected image');
    }
    return CaptureResult(
      imageBytes: bytes,
      capturedAt: DateTime.now().toUtc(),
      imageExtension: _extensionOf(file.name, file.path),
    );
  }

  static String _extensionOf(String name, String? path) {
    final source = path ?? name;
    final dot = source.lastIndexOf('.');
    if (dot == -1 || dot == source.length - 1) return 'jpg';
    final ext = source.substring(dot + 1).toLowerCase();
    if (ext == 'jpeg') return 'jpg';
    if (ext == 'png' || ext == 'jpg' || ext == 'webp') return ext;
    return 'jpg';
  }
}

class CaptureCancelled implements Exception {
  @override
  String toString() => 'Capture cancelled';
}
