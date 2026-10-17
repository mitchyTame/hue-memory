import 'package:flutter/material.dart';

import '../capture/last_commit_summary.dart';
import '../theme/memory_hues.dart';
import 'ink_glyph_painter.dart';

/// Compact last-commit strip: glyph icon + file · folder · date.
class LastCommitCard extends StatelessWidget {
  const LastCommitCard({super.key, required this.summary});

  final LastCommitSummary summary;

  static String? drawIdForSymbol(String symbolId) {
    switch (symbolId) {
      case 'inbox':
        return 'circle-open';
      case 'fleeting':
        return 'wave';
      case 'literature':
        return 'triple-bar';
      case 'permanent':
        return 'diamond';
      case 'visual':
        return 'triangle';
      case 'journal':
        return 'bar';
      case 'daily-tasks':
        return 'dot';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final drawId = drawIdForSymbol(summary.symbolId);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: MemoryHues.ink.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MemoryHues.rule.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: MemoryHues.accentSoft.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: drawId != null
                ? SizedBox(
                    width: 26,
                    height: 26,
                    child: CustomPaint(
                      painter: InkGlyphPainter(
                        drawId: drawId,
                        color: MemoryHues.accentSoft,
                      ),
                    ),
                  )
                : Text(
                    summary.glyph,
                    style: textTheme.titleMedium?.copyWith(
                      color: MemoryHues.accentSoft,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last commit',
                  style: textTheme.labelSmall?.copyWith(
                    color: MemoryHues.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary.fileName,
                  style: textTheme.titleMedium?.copyWith(
                    color: MemoryHues.paperElevated,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${summary.folderLabel} · ${summary.dateLabel}',
                  style: textTheme.bodySmall?.copyWith(
                    color: MemoryHues.accentSoft,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
