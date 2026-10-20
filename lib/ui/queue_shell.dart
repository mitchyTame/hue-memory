import 'package:flutter/material.dart';

import '../queue/capture_queue.dart';
import '../theme/memory_hues.dart';

/// Offline capture queue — retry coordinator path or commit inbox-only.
class QueueShell extends StatelessWidget {
  const QueueShell({
    super.key,
    required this.jobs,
    this.busy = false,
    this.onBack,
    this.onRetryOcr,
    this.onInboxOnly,
    this.onDiscard,
  });

  final List<QueueJob> jobs;
  final bool busy;
  final VoidCallback? onBack;
  final Future<void> Function(QueueJob job)? onRetryOcr;
  final Future<void> Function(QueueJob job)? onInboxOnly;
  final Future<void> Function(QueueJob job)? onDiscard;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: MemoryHues.paper,
      appBar: AppBar(
        title: const Text('Capture queue'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: busy ? null : onBack,
        ),
      ),
      body: jobs.isEmpty
          ? Center(
              child: Text(
                'Queue empty.\nFailed captures land here for retry.',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(
                  color: MemoryHues.inkMuted,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: jobs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final job = jobs[i];
                return Material(
                  color: MemoryHues.paperElevated,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: MemoryHues.rule),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.id,
                          style: textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            job.status.name,
                            if (job.forcedSymbolId != null)
                              'chip:${job.forcedSymbolId}',
                            '${job.capturedAt.toLocal()}',
                          ].join(' · '),
                          style: textTheme.bodySmall?.copyWith(
                            color: MemoryHues.inkMuted,
                          ),
                        ),
                        if (job.lastError != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            job.lastError!,
                            style: textTheme.bodySmall?.copyWith(
                              color: MemoryHues.danger,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed: busy || onRetryOcr == null
                                  ? null
                                  : () => onRetryOcr!(job),
                              child: const Text('Retry'),
                            ),
                            FilledButton.tonal(
                              onPressed: busy || onInboxOnly == null
                                  ? null
                                  : () => onInboxOnly!(job),
                              child: const Text('Inbox only'),
                            ),
                            TextButton(
                              onPressed: busy || onDiscard == null
                                  ? null
                                  : () => onDiscard!(job),
                              child: const Text('Discard'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
