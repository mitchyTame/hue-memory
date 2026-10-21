import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'memory_hues.dart';

/// Full-bleed calm ink→teal wash shared by capture home and camera chrome.
class HueAtmosphere extends StatelessWidget {
  const HueAtmosphere({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: MemoryHues.atmosphereDecoration,
      child: child,
    );
  }
}

/// Dark field scaffold — same ink→teal atmosphere as home / camera.
///
/// Use for capture-adjacent screens (confirm letterbox, manual OCR frame)
/// so they never fall back to flat navy / Material blue.
class HueFieldScaffold extends StatelessWidget {
  const HueFieldScaffold({
    super.key,
    required this.body,
    this.annotateSystemUi = true,
  });

  final Widget body;
  final bool annotateSystemUi;

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: MemoryHues.fieldDeep,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const HueAtmosphere(),
          body,
        ],
      ),
    );

    if (!annotateSystemUi) return scaffold;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: MemoryHues.fieldDeep,
        systemNavigationBarColor: MemoryHues.fieldDeep,
      ),
      child: scaffold,
    );
  }
}
