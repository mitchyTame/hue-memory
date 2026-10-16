import 'package:flutter/material.dart';

import '../theme/memory_hues.dart';
import 'camera_capture.dart';
import 'camera_session.dart';

/// Full-bleed live viewfinder — Memory hues dark paper plane + teal shutter.
class LiveCameraShell extends StatefulWidget {
  const LiveCameraShell({
    super.key,
    this.sessionFactory,
  });

  /// Defaults to [PluginCameraSession]. Inject [FakeCameraSession] in tests.
  final CameraSessionFactory? sessionFactory;

  @override
  State<LiveCameraShell> createState() => _LiveCameraShellState();
}

class _LiveCameraShellState extends State<LiveCameraShell> {
  CameraSession? _session;
  Object? _error;
  bool _snapping = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final factory =
        widget.sessionFactory ?? () async => PluginCameraSession();
    try {
      final session = await factory();
      await session.initialize();
      if (!mounted) {
        await session.dispose();
        return;
      }
      setState(() => _session = session);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  Future<void> _shutter() async {
    final session = _session;
    if (session == null || !session.isInitialized || _snapping) return;
    setState(() => _snapping = true);
    try {
      final shot = await session.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop<CaptureResult>(shot);
    } catch (e) {
      if (!mounted) return;
      setState(() => _snapping = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Capture failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  void _cancel() {
    Navigator.of(context).pop<CaptureResult>();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final session = _session;
    final error = _error;

    return Scaffold(
      backgroundColor: MemoryHues.ink,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Landscape phones often leave ~360–400px after SafeArea;
            // fixed 72 + 16+28 padding was overflowing by ~39px.
            final short = constraints.maxHeight < 420;
            final shutterSize = short ? 56.0 : 72.0;
            final bottomPad = short ? 8.0 : 16.0;
            final topPad = short ? 2.0 : 4.0;

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: topPad),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Cancel',
                        onPressed: _snapping ? null : _cancel,
                        icon: const Icon(
                          Icons.close,
                          color: MemoryHues.paperElevated,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Frame the page',
                          textAlign: TextAlign.center,
                          style: textTheme.labelLarge?.copyWith(
                            color: MemoryHues.paperElevated,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (error != null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Camera unavailable:\n$error',
                              textAlign: TextAlign.center,
                              style: textTheme.bodyMedium?.copyWith(
                                color: MemoryHues.paperElevated,
                              ),
                            ),
                          ),
                        )
                      else if (session == null || !session.isInitialized)
                        const Center(
                          child: CircularProgressIndicator(
                            color: MemoryHues.accent,
                          ),
                        )
                      else
                        Positioned.fill(child: session.buildPreview()),
                      const CustomPaint(painter: _MetaZoneGuidePainter()),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, short ? 8 : 12, 24, bottomPad),
                  child: Semantics(
                    button: true,
                    label: 'Shutter',
                    child: GestureDetector(
                      onTap: (session == null ||
                              !session.isInitialized ||
                              _snapping ||
                              error != null)
                          ? null
                          : _shutter,
                      child: Container(
                        width: shutterSize,
                        height: shutterSize,
                        decoration: BoxDecoration(
                          color: _snapping
                              ? MemoryHues.accent.withValues(alpha: 0.5)
                              : MemoryHues.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: MemoryHues.paperElevated,
                            width: 3,
                          ),
                        ),
                        child: _snapping
                            ? Padding(
                                padding: EdgeInsets.all(shutterSize * 0.28),
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: MemoryHues.paperElevated,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Subtle corner meta-zone hint (top-left ink-icon habit from the brief).
class _MetaZoneGuidePainter extends CustomPainter {
  const _MetaZoneGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MemoryHues.paperElevated.withValues(alpha: 0.45)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const inset = 24.0;
    const arm = 36.0;
    // Top-left meta zone box.
    final left = inset;
    final top = inset;
    canvas.drawRect(
      Rect.fromLTWH(left, top, size.width * 0.22, size.height * 0.12),
      paint..color = MemoryHues.recall.withValues(alpha: 0.55),
    );

    // Outer page brackets.
    final right = size.width - inset;
    final bottom = size.height - inset;
    final bracket = Paint()
      ..color = MemoryHues.paperElevated.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(left, top + arm), Offset(left, top), bracket);
    canvas.drawLine(Offset(left, top), Offset(left + arm, top), bracket);
    canvas.drawLine(Offset(right - arm, top), Offset(right, top), bracket);
    canvas.drawLine(Offset(right, top), Offset(right, top + arm), bracket);
    canvas.drawLine(Offset(left, bottom - arm), Offset(left, bottom), bracket);
    canvas.drawLine(Offset(left, bottom), Offset(left + arm, bottom), bracket);
    canvas.drawLine(Offset(right - arm, bottom), Offset(right, bottom), bracket);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - arm), bracket);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
