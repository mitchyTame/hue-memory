import 'package:flutter/material.dart';

import '../theme/memory_hues.dart';

/// Capture home — shutter (live / sample) + gallery pick.
class CaptureShell extends StatelessWidget {
  const CaptureShell({
    super.key,
    this.onShutter,
    this.onPickImage,
    this.onOpenSettings,
    this.onOpenPromote,
    this.onOpenQueue,
    this.queueCount = 0,
    this.vaultLabel = 'In-memory vault (FakeVaultFs)',
    this.lastCommitPath,
    this.busy = false,
    this.shutterHint =
        'Shutter = sample page\nGallery = pick a photo',
  });

  final VoidCallback? onShutter;
  final VoidCallback? onPickImage;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenPromote;
  final VoidCallback? onOpenQueue;
  final int queueCount;
  final String vaultLabel;
  final String? lastCommitPath;
  final bool busy;
  final String shutterHint;

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
                    tooltip: 'Promote ritual',
                    onPressed: busy ? null : onOpenPromote,
                    icon: const Icon(
                      Icons.auto_awesome_outlined,
                      color: MemoryHues.recall,
                      size: 22,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Vault settings',
                    onPressed: busy ? null : onOpenSettings,
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
                            busy ? 'Working…' : shutterHint,
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Pick image',
                    onPressed: busy ? null : onPickImage,
                    icon: const Icon(
                      Icons.photo_library_outlined,
                      color: MemoryHues.paperElevated,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 28),
                  Semantics(
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
                  const SizedBox(width: 28),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        tooltip: 'Capture queue',
                        onPressed: busy ? null : onOpenQueue,
                        icon: Icon(
                          Icons.inbox_outlined,
                          color: queueCount > 0
                              ? MemoryHues.recall
                              : MemoryHues.paperElevated,
                          size: 28,
                        ),
                      ),
                      if (queueCount > 0)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: MemoryHues.recall,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$queueCount',
                              style: textTheme.labelSmall?.copyWith(
                                color: MemoryHues.ink,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
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
