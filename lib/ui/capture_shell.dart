import 'package:flutter/material.dart';

import '../capture/last_commit_summary.dart';
import '../theme/hue_atmosphere.dart';
import '../theme/memory_hues.dart';
import 'last_commit_card.dart';

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
    this.lastCommit,
    this.statusMessage,
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
  final LastCommitSummary? lastCommit;

  /// Live OCR / capture status line (loading, success, failure).
  final String? statusMessage;
  final bool busy;
  final String shutterHint;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return HueFieldScaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final short = constraints.maxHeight < 420;
            final shutterSize = short ? 56.0 : 72.0;
            final bottomPad = short ? 10.0 : 20.0;
            final topPad = short ? 4.0 : 8.0;

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: topPad,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          vaultLabel,
                          style: textTheme.labelMedium?.copyWith(
                            color: MemoryHues.paperElevated
                                .withValues(alpha: 0.75),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Promote ritual',
                        onPressed: busy ? null : onOpenPromote,
                        icon: Icon(
                          Icons.auto_awesome_outlined,
                          color: MemoryHues.recall.withValues(alpha: 0.9),
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
                      const CustomPaint(painter: _CornerBracketPainter()),
                      Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'hue-memory',
                                style: textTheme.headlineLarge?.copyWith(
                                  color: MemoryHues.paperElevated,
                                  fontSize: short ? 28 : 34,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                busy
                                    ? (statusMessage ?? 'Working…')
                                    : shutterHint,
                                textAlign: TextAlign.center,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: MemoryHues.paperElevated
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                              if (statusMessage != null && !busy) ...[
                                const SizedBox(height: 12),
                                Text(
                                  statusMessage!,
                                  textAlign: TextAlign.center,
                                  style: textTheme.labelMedium?.copyWith(
                                    color: MemoryHues.accentSoft
                                        .withValues(alpha: 0.9),
                                  ),
                                ),
                              ],
                              if (lastCommit != null) ...[
                                const SizedBox(height: 16),
                                LastCommitCard(summary: lastCommit!),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    short ? 8 : 12,
                    24,
                    bottomPad,
                  ),
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
                            width: shutterSize,
                            height: shutterSize,
                            decoration: BoxDecoration(
                              color: busy
                                  ? MemoryHues.accent.withValues(alpha: 0.5)
                                  : MemoryHues.accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: MemoryHues.paperElevated
                                    .withValues(alpha: 0.9),
                                width: 3,
                              ),
                            ),
                            child: busy
                                ? Padding(
                                    padding: EdgeInsets.all(
                                      shutterSize * 0.28,
                                    ),
                                    child: const CircularProgressIndicator(
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
                                  ? MemoryHues.recall.withValues(alpha: 0.95)
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
                                    color: MemoryHues.fieldDeep,
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
            );
          },
        ),
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  const _CornerBracketPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MemoryHues.paperElevated.withValues(alpha: 0.4)
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
