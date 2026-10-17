import 'package:flutter/material.dart';

import '../theme/memory_hues.dart';

/// Settings → Paper kit — A6 PDFs in app files (never the Obsidian vault).
class PaperKitShell extends StatelessWidget {
  const PaperKitShell({
    super.key,
    required this.packLabel,
    this.busy = false,
    this.lastWritePath,
    this.onBack,
    this.onWriteLegend,
    this.onWriteHueDots,
  });

  final String packLabel;
  final bool busy;
  final String? lastWritePath;
  final VoidCallback? onBack;
  final VoidCallback? onWriteLegend;
  final VoidCallback? onWriteHueDots;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: MemoryHues.paper,
      appBar: AppBar(
        title: const Text('Paper kit'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: busy ? null : onBack,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Printables for the active pack',
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            packLabel,
            style: textTheme.labelMedium?.copyWith(color: MemoryHues.inkMuted),
          ),
          const SizedBox(height: 16),
          Text(
            'A6 craft sheets save to app files only — never into your '
            'Obsidian vault (no symbol-journal/ folder).',
            style: textTheme.bodyMedium?.copyWith(color: MemoryHues.inkMuted),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : onWriteLegend,
            child: const Text('Write ink legend PDF'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: busy ? null : onWriteHueDots,
            style: FilledButton.styleFrom(
              foregroundColor: MemoryHues.ink,
              backgroundColor: MemoryHues.recallSoft,
            ),
            child: const Text('Write hue-dot sticker PDF'),
          ),
          if (busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
          if (lastWritePath != null) ...[
            const SizedBox(height: 24),
            Text(
              'Last write',
              style: textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SelectableText(
              lastWritePath!,
              style: textTheme.bodySmall?.copyWith(
                fontFamily: 'IBM Plex Mono',
                color: MemoryHues.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
