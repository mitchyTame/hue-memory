import 'package:flutter/material.dart';

import '../symbols/default_packs.dart';
import '../symbols/symbol_models.dart';
import '../theme/memory_hues.dart';
import 'camera_capture.dart';
import 'camera_session.dart';
import 'live_camera_shell.dart';
import 'symbol_box.dart';

/// Opens [LiveCameraShell] via a navigator push and returns the frozen frame.
class LiveCameraCapture implements CameraCapture {
  LiveCameraCapture({
    required this.navigatorKey,
    this.sessionFactory,
    this.pack = DefaultPacks.zettelkastenInk,
    CaptureSessionPrefs? sessionPrefs,
    this.botAgentMode = false,
  }) : sessionPrefs = sessionPrefs ?? CaptureSessionPrefs();

  final GlobalKey<NavigatorState> navigatorKey;
  final CameraSessionFactory? sessionFactory;

  /// Updated when the active pack changes.
  SymbolPack pack;
  final CaptureSessionPrefs sessionPrefs;

  /// Hide symbol chips / pack routing on the viewfinder.
  bool botAgentMode;

  @override
  Future<CaptureResult> capturePage() async {
    final nav = navigatorKey.currentState;
    if (nav == null) {
      throw StateError('Navigator not ready for live camera');
    }
    final result = await nav.push<CaptureResult>(
      MaterialPageRoute(
        // Opaque route so the paper-colored navigator surface never shows
        // through the camera scaffold.
        fullscreenDialog: true,
        builder: (_) => Material(
          color: MemoryHues.fieldDeep,
          child: LiveCameraShell(
            sessionFactory: sessionFactory,
            pack: pack,
            initialSymbolId: botAgentMode ? '' : sessionPrefs.symbolId,
            initialSymbolBox: sessionPrefs.symbolBox,
            botAgentMode: botAgentMode,
          ),
        ),
      ),
    );
    if (result == null) throw CaptureCancelled();
    // Persist box + chip for the next shot in this session (full mode only).
    if (!botAgentMode) {
      sessionPrefs.symbolId = result.symbolId;
      if (result.symbolBox != null) {
        sessionPrefs.symbolBox = result.symbolBox!;
      }
    }
    return result;
  }
}
