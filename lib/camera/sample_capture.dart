import 'package:flutter/services.dart';

import 'camera_capture.dart';

/// Loads the bundled sample page (Linux / no-camera demos).
///
/// TODO(camera): Prefer live CameraCapture on Android; keep this as fallback.
class SampleAssetCapture implements CameraCapture {
  SampleAssetCapture({
    this.assetPath = 'assets/sample_page.png',
  });

  final String assetPath;

  @override
  Future<CaptureResult> capturePage() async {
    final data = await rootBundle.load(assetPath);
    return CaptureResult(
      imageBytes: data.buffer.asUint8List(),
      capturedAt: DateTime.now().toUtc(),
      imageExtension: 'png',
    );
  }
}

/// In-memory bytes capture for tests (no asset bundle).
class BytesCameraCapture implements CameraCapture {
  BytesCameraCapture(this.imageBytes, {this.imageExtension = 'png'});

  final Uint8List imageBytes;
  final String imageExtension;

  @override
  Future<CaptureResult> capturePage() async {
    return CaptureResult(
      imageBytes: imageBytes,
      capturedAt: DateTime.now().toUtc(),
      imageExtension: imageExtension,
    );
  }
}
