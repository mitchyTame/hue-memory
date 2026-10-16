import 'package:flutter/material.dart';

import '../theme/memory_hues.dart';

/// Capture home shell — camera is the home screen.
///
/// TODO(camera): Replace placeholder plane with real CameraPreview + shutter.
class CaptureShell extends StatelessWidget {
  const CaptureShell({
    super.key,
    this.onShutter,
    this.onOpenConfirm,
    this.vaultLabel = 'No vault selected',
  });

  final VoidCallback? onShutter;
  final VoidCallback? onOpenConfirm;
  final String vaultLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: MemoryHues.ink,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      vaultLabel,
                      style: textTheme.labelMedium?.copyWith(
                        color: MemoryHues.paperElevated.withValues(alpha: 0.85),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () {
                      // TODO(settings): vault path + symbol pack screens.
                    },
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: MemoryHues.paperElevated,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFF0F1726)),
                  CustomPaint(painter: _CornerBracketPainter()),
                  Center(
                    child: Text(
                      'Camera preview\n(stub)',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: MemoryHues.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: onOpenConfirm,
                    child: Text(
                      'Confirm shell',
                      style: textTheme.bodySmall?.copyWith(
                        color: MemoryHues.paperElevated,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Semantics(
                    button: true,
                    label: 'Shutter',
                    child: GestureDetector(
                      onTap: onShutter,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: MemoryHues.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: MemoryHues.paperElevated,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 72),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MemoryHues.paperElevated.withValues(alpha: 0.55)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    const inset = 28.0;
    const arm = 28.0;
    final left = inset;
    final top = inset;
    final right = size.width - inset;
    final bottom = size.height - inset;

    // Top-left
    canvas.drawLine(Offset(left, top + arm), Offset(left, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left + arm, top), paint);
    // Top-right
    canvas.drawLine(Offset(right - arm, top), Offset(right, top), paint);
    canvas.drawLine(Offset(right, top), Offset(right, top + arm), paint);
    // Bottom-left
    canvas.drawLine(Offset(left, bottom - arm), Offset(left, bottom), paint);
    canvas.drawLine(Offset(left, bottom), Offset(left + arm, bottom), paint);
    // Bottom-right
    canvas.drawLine(Offset(right - arm, bottom), Offset(right, bottom), paint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - arm), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
