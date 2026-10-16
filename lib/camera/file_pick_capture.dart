import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'camera_capture.dart';

/// Picks an image from the filesystem / gallery (Linux desktop + Android).
class FilePickCapture implements CameraCapture {
  const FilePickCapture();

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
    final bytes = await readPickedImageBytes(file);
    return CaptureResult(
      imageBytes: bytes,
      capturedAt: DateTime.now().toUtc(),
      imageExtension: imageExtensionOf(file.name, file.path),
    );
  }
}

/// Reads image bytes from a [PlatformFile], preferring in-memory data then path.
Future<Uint8List> readPickedImageBytes(PlatformFile file) async {
  final memory = file.bytes;
  if (memory != null && memory.isNotEmpty) {
    return Uint8List.fromList(memory);
  }
  final path = file.path;
  if (path == null || path.isEmpty) {
    throw StateError('Could not read selected image (no bytes or path)');
  }
  final disk = await File(path).readAsBytes();
  if (disk.isEmpty) {
    throw StateError('Selected image is empty: $path');
  }
  return disk;
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
