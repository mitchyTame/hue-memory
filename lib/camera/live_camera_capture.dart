import 'package:flutter/material.dart';

import 'camera_capture.dart';
import 'camera_session.dart';
import 'live_camera_shell.dart';

/// Opens [LiveCameraShell] via a navigator push and returns the frozen frame.
class LiveCameraCapture implements CameraCapture {
  LiveCameraCapture({
    required this.navigatorKey,
    this.sessionFactory,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final CameraSessionFactory? sessionFactory;

  @override
  Future<CaptureResult> capturePage() async {
    final nav = navigatorKey.currentState;
    if (nav == null) {
      throw StateError('Navigator not ready for live camera');
    }
    final result = await nav.push<CaptureResult>(
      MaterialPageRoute(
        builder: (_) => LiveCameraShell(sessionFactory: sessionFactory),
      ),
    );
    if (result == null) throw CaptureCancelled();
    return result;
  }
}
