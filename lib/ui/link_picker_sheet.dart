import 'package:flutter/material.dart';

import '../theme/memory_hues.dart';
import '../writers/link_writer.dart';

/// Simple confirm Link picker — recent pages / stub list (no paper `[[…]]`).
Future<List<LinkPick>?> showLinkPickerSheet({
  required BuildContext context,
  required List<LinkPick> candidates,
  required List<LinkPick> initiallySelected,
}) {
  return showModalBottomSheet<List<LinkPick>>(
    context: context,
    backgroundColor: MemoryHues.paperElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return _LinkPickerBody(
        candidates: candidates,
        initiallySelected: initiallySelected,
      );
    },
  );
}

class _LinkPickerBody extends StatefulWidget {
  const _LinkPickerBody({
    required this.candidates,
    required this.initiallySelected,
  });

  final List<LinkPick> candidates;
  final List<LinkPick> initiallySelected;

  @override
  State<_LinkPickerBody> createState() => _LinkPickerBodyState();
}

class _LinkPickerBodyState extends State<_LinkPickerBody> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {
      for (final p in widget.initiallySelected) p.targetPath,
    };
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, color: MemoryHues.rule),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Link pages', style: textTheme.titleLarge),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Suggested + recent vault notes — no wiki syntax on paper.',
                style: textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (widget.candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No recent pages yet. Commit a note first.',
                style: textTheme.bodyMedium?.copyWith(color: MemoryHues.inkMuted),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in widget.candidates)
                    CheckboxListTile(
                      value: _selected.contains(c.targetPath),
                      activeColor: MemoryHues.accent,
                      title: Text(
                        c.displayTitle ?? c.targetPath,
                        style: textTheme.bodyMedium,
                      ),
                      subtitle: Text(
                        c.targetPath,
                        style: textTheme.labelMedium,
                      ),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(c.targetPath);
                          } else {
                            _selected.remove(c.targetPath);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    final picks = widget.candidates
                        .where((c) => _selected.contains(c.targetPath))
                        .toList(growable: false);
                    Navigator.pop(context, picks);
                  },
                  child: const Text('Apply links'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
