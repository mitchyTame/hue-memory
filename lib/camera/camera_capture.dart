import 'dart:typed_data';

import 'symbol_box.dart';

/// Result of a page capture (frozen frame bytes).
class CaptureResult {
  const CaptureResult({
    required this.imageBytes,
    required this.capturedAt,
    this.imageExtension = 'png',
    this.symbolId = '',
    this.symbolBox,
  });

  final Uint8List imageBytes;
  final DateTime capturedAt;
  final String imageExtension;

  /// Camera symbol chip (empty → coordinator / OCR seeds confirm).
  final String symbolId;

  /// Movable box over the paper ink glyph (session).
  final SymbolBoxRect? symbolBox;
}

/// Camera capture boundary (live viewfinder, gallery pick, or sample asset).
abstract interface class CameraCapture {
  Future<CaptureResult> capturePage();
}

/// User dismissed the picker / viewfinder without a frame.
class CaptureCancelled implements Exception {
  @override
  String toString() => 'Capture cancelled';
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
