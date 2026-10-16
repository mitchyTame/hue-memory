import 'dart:typed_data';

/// Result of a page capture (frozen frame bytes).
class CaptureResult {
  const CaptureResult({
    required this.imageBytes,
    required this.capturedAt,
    this.imageExtension = 'png',
  });

  final Uint8List imageBytes;
  final DateTime capturedAt;
  final String imageExtension;
}

/// Camera capture boundary.
///
/// TODO(camera): Wire `camera` / `camerawesome` — full-bleed viewfinder,
/// shutter breath motion, optional meta-zone guide. This stub only exists so
/// the confirm shell and queue can be developed without device hardware.
abstract interface class CameraCapture {
  Future<CaptureResult> capturePage();
}

/// No-op capture that returns empty bytes. Does not pretend to open a camera.
class StubCameraCapture implements CameraCapture {
  StubCameraCapture({Uint8List? imageBytes, this.imageExtension = 'png'})
      : _imageBytes = imageBytes ?? Uint8List(0);

  final Uint8List _imageBytes;
  final String imageExtension;

  @override
  Future<CaptureResult> capturePage() async {
    return CaptureResult(
      imageBytes: _imageBytes,
      capturedAt: DateTime.now().toUtc(),
      imageExtension: imageExtension,
    );
  }
}
