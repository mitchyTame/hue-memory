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
    this.maxListed = 6,
  });

  final List<TodoistRetryBatch> batches;
  final bool busy;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;
  final int maxListed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final items = [for (final b in batches) ...b.items];
    if (items.isEmpty) return const SizedBox.shrink();
    final reasons = <String>{for (final i in items) i.error}.toList();
    final listed = items.take(maxListed).toList();

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
                '${item.kind == FailedItemKind.done ? '✓ ' : '• '}'
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
          const SizedBox(height: 8),
          Row(
            children: [
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
              const SizedBox(width: 8),
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
