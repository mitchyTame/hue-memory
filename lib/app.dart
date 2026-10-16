import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'ui/capture_shell.dart';
import 'ui/confirm_shell.dart';

class HueMemoryApp extends StatelessWidget {
  const HueMemoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'hue-memory',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const _HomeNavigator(),
    );
  }
}

class _HomeNavigator extends StatefulWidget {
  const _HomeNavigator();

  @override
  State<_HomeNavigator> createState() => _HomeNavigatorState();
}

class _HomeNavigatorState extends State<_HomeNavigator> {
  bool _showConfirm = false;

  @override
  Widget build(BuildContext context) {
    if (_showConfirm) {
      return ConfirmShell(
        onInbox: () => setState(() => _showConfirm = false),
        onCommit: (_) => setState(() => _showConfirm = false),
      );
    }
    return CaptureShell(
      onShutter: () {
        // TODO(camera): capture frame, enqueue, open confirm with photo.
        setState(() => _showConfirm = true);
      },
      onOpenConfirm: () => setState(() => _showConfirm = true),
    );
  }
}
