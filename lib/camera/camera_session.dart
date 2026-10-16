import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_capture.dart';

/// Hardware session behind the live viewfinder (mockable in tests).
abstract interface class CameraSession {
  Future<void> initialize();

  bool get isInitialized;

  /// Full-bleed preview widget once [initialize] succeeds.
  Widget buildPreview();

  Future<CaptureResult> takePicture();

  Future<void> dispose();
}

typedef CameraSessionFactory = Future<CameraSession> Function();

/// Real device session via the `camera` plugin.
class PluginCameraSession implements CameraSession {
  PluginCameraSession({
    this.resolution = ResolutionPreset.veryHigh,
    List<CameraDescription>? cameras,
  }) : _camerasOverride = cameras;

  final ResolutionPreset resolution;
  final List<CameraDescription>? _camerasOverride;
  CameraController? _controller;

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  Future<void> initialize() async {
    final cameras = _camerasOverride ?? await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No cameras available');
    }
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      back,
      resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await controller.initialize();
    _controller = controller;
  }

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Color(0xFF0F1726));
    }
    return CameraPreview(controller);
  }

  @override
  Future<CaptureResult> takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Camera not ready');
    }
    if (controller.value.isTakingPicture) {
      throw StateError('Capture already in progress');
    }
    final file = await controller.takePicture();
    final bytes = await File(file.path).readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Camera returned empty image');
    }
    return CaptureResult(
      imageBytes: bytes,
      capturedAt: DateTime.now().toUtc(),
      imageExtension: 'jpg',
    );
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}

/// In-memory session for widget tests (no device camera).
class FakeCameraSession implements CameraSession {
  FakeCameraSession({
    required this.imageBytes,
    this.imageExtension = 'jpg',
    this.failInitialize = false,
  });

  final Uint8List imageBytes;
  final String imageExtension;
  final bool failInitialize;
  bool _ready = false;

  @override
  bool get isInitialized => _ready;

  @override
  Future<void> initialize() async {
    if (failInitialize) {
      throw StateError('Fake camera init failed');
    }
    _ready = true;
  }

  @override
  Widget buildPreview() {
    return const ColoredBox(
      color: Color(0xFF1B2A4A),
      child: Center(
        child: Text(
          'Fake preview',
          style: TextStyle(color: Color(0xFFF1F0EC)),
        ),
      ),
    );
  }

  @override
  Future<CaptureResult> takePicture() async {
    if (!_ready) throw StateError('Camera not ready');
    return CaptureResult(
      imageBytes: imageBytes,
      capturedAt: DateTime.now().toUtc(),
      imageExtension: imageExtension,
    );
  }

  @override
  Future<void> dispose() async {
    _ready = false;
  }
}
