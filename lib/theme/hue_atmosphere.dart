import 'package:flutter/material.dart';

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
