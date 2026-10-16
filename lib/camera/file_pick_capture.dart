import 'package:file_picker/file_picker.dart';

import 'camera_capture.dart';

/// Picks an image from the filesystem / gallery (Linux desktop + Android).
class FilePickCapture implements CameraCapture {
  const FilePickCapture();

  @override
  Future<CaptureResult> capturePage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) {
      throw CaptureCancelled();
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Selected image is empty');
    }
    return CaptureResult(
      imageBytes: bytes,
      capturedAt: DateTime.now().toUtc(),
      imageExtension: imageExtensionOf(file.name, file.path),
    );
  }
}

/// Normalizes a file name/path to a vault-friendly image extension.
String imageExtensionOf(String name, String? path) {
  final source = path ?? name;
  final dot = source.lastIndexOf('.');
  if (dot == -1 || dot == source.length - 1) return 'jpg';
  final ext = source.substring(dot + 1).toLowerCase();
  if (ext == 'jpeg') return 'jpg';
  if (ext == 'png' || ext == 'jpg' || ext == 'webp' || ext == 'gif') {
    return ext;
  }
  return 'jpg';
}
