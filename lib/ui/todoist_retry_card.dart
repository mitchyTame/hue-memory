import 'package:material_ui/material_ui.dart';

import '../theme/memory_hues.dart';
import '../todoist/todoist_retry.dart';

/// In-app notice: which Todoist items did not send, why, and a retry.
class TodoistRetryCard extends StatelessWidget {
  const TodoistRetryCard({
    super.key,
    required this.batches,
    this.busy = false,
    this.onRetry,
    this.onDiscard,
    this.onRecreate,
    this.maxListed = 6,
  });

  final List<TodoistRetryBatch> batches;
  final bool busy;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  /// Recreate updates whose earlier Todoist task no longer exists.
  final VoidCallback? onRecreate;
  final int maxListed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final items = [for (final b in batches) ...b.items];
    if (items.isEmpty) return const SizedBox.shrink();
    final reasons = <String>{for (final i in items) i.error}.toList();
    final listed = items.take(maxListed).toList();
    final missing = items.where((i) => i.remoteMissing).toList();
    final retryable = items.length - missing.length;

    return Container(
      key: const ValueKey('todoist-retry-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MemoryHues.ink.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MemoryHues.danger.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            items.length == 1
                ? '1 Todoist item did not send'
                : '${items.length} Todoist items did not send',
            style: textTheme.titleSmall?.copyWith(
              color: MemoryHues.paperElevated,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            reasons.join(' · '),
            style: textTheme.labelMedium?.copyWith(
              color: MemoryHues.paperElevated.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in listed)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${switch (item.kind) {
                  FailedItemKind.done => '✓ ',
                  FailedItemKind.update => '↻ ',
                  FailedItemKind.create => '• ',
                }}'
                '${item.content}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: MemoryHues.paperElevated.withValues(alpha: 0.9),
                ),
              ),
            ),
          if (items.length > listed.length)
            Text(
              '+ ${items.length - listed.length} more',
              style: textTheme.labelSmall?.copyWith(
                color: MemoryHues.paperElevated.withValues(alpha: 0.6),
              ),
            ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              missing.length == 1
                  ? '↻ 1 earlier task is gone from Todoist (deleted or '
                      'completed). Recreate it as a new task?'
                  : '↻ ${missing.length} earlier tasks are gone from Todoist '
                      '(deleted or completed). Recreate them as new tasks?',
              key: const ValueKey('todoist-missing-note'),
              style: textTheme.labelMedium?.copyWith(
                color: MemoryHues.paperElevated,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (retryable > 0)
                FilledButton(
                  key: const ValueKey('todoist-retry-button'),
                  onPressed: busy ? null : onRetry,
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Retry failed'),
                ),
              if (missing.isNotEmpty)
                FilledButton(
                  key: const ValueKey('todoist-recreate-button'),
                  onPressed: busy ? null : onRecreate,
                  child: const Text('Recreate'),
                ),
              TextButton(
                key: const ValueKey('todoist-discard-button'),
                onPressed: busy ? null : onDiscard,
                child: Text(
                  'Discard',
                  style: TextStyle(
                    color: MemoryHues.paperElevated.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
