import 'package:flutter/material.dart';

import '../theme/memory_hues.dart';

/// Capture home — sample shutter for Linux; camera later on Android.
class CaptureShell extends StatelessWidget {
  const CaptureShell({
    super.key,
    this.onShutter,
    this.vaultLabel = 'In-memory vault (FakeVaultFs)',
    this.lastCommitPath,
    this.busy = false,
  });

  final VoidCallback? onShutter;
  final String vaultLabel;
  final String? lastCommitPath;
  final bool busy;

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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'hue-memory',
                            style: textTheme.headlineMedium?.copyWith(
                              color: MemoryHues.paperElevated,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            busy
                                ? 'Reading sample page…'
                                : 'Tap shutter for sample page\n(camera on Android later)',
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(
                              color: MemoryHues.inkMuted,
                            ),
                          ),
                          if (lastCommitPath != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Last commit:\n$lastCommitPath',
                              textAlign: TextAlign.center,
                              style: textTheme.labelMedium?.copyWith(
                                color: MemoryHues.accentSoft,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: Semantics(
                button: true,
                label: 'Shutter',
                child: GestureDetector(
                  onTap: busy ? null : onShutter,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: busy
                          ? MemoryHues.accent.withValues(alpha: 0.5)
                          : MemoryHues.accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: MemoryHues.paperElevated,
                        width: 3,
                      ),
                    ),
                    child: busy
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(
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

    canvas.drawLine(Offset(left, top + arm), Offset(left, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left + arm, top), paint);
    canvas.drawLine(Offset(right - arm, top), Offset(right, top), paint);
    canvas.drawLine(Offset(right, top), Offset(right, top + arm), paint);
    canvas.drawLine(Offset(left, bottom - arm), Offset(left, bottom), paint);
    canvas.drawLine(Offset(left, bottom), Offset(left + arm, bottom), paint);
    canvas.drawLine(Offset(right - arm, bottom), Offset(right, bottom), paint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - arm), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
