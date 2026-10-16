import 'package:flutter/material.dart';

import '../symbols/default_packs.dart';
import '../symbols/symbol_models.dart';
import '../theme/memory_hues.dart';

/// Confirm-on-photo shell — photo is the canvas; bottom sheet for chips + commit.
///
/// TODO(confirm): InteractiveViewer + region overlays + Link picker sheet.
class ConfirmShell extends StatefulWidget {
  const ConfirmShell({
    super.key,
    this.pack = DefaultPacks.zettelkastenInk,
    this.initialSymbolId = 'fleeting',
    this.onCommit,
    this.onInbox,
  });

  final SymbolPack pack;
  final String initialSymbolId;
  final ValueChanged<String>? onCommit;
  final VoidCallback? onInbox;

  @override
  State<ConfirmShell> createState() => _ConfirmShellState();
}

class _ConfirmShellState extends State<ConfirmShell> {
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSymbolId;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final symbols = widget.pack.symbols;

    return Scaffold(
      backgroundColor: MemoryHues.ink,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFF152033)),
                  Container(color: MemoryHues.overlayScrim),
                  Center(
                    child: Text(
                      'Photo canvas\n(stub)',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: MemoryHues.paperElevated.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: MemoryHues.paperElevated,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              elevation: 1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Divider(height: 1, thickness: 1, color: MemoryHues.rule),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Confirm meaning', style: textTheme.titleLarge),
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: symbols.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final s = symbols[index];
                        final selected = s.id == _selectedId;
                        return ChoiceChip(
                          label: Text('${s.primaryGlyph} ${s.id}'),
                          selected: selected,
                          onSelected: (_) => setState(() => _selectedId = s.id),
                          selectedColor: MemoryHues.accentSoft,
                          side: BorderSide(
                            color: selected ? MemoryHues.accent : MemoryHues.rule,
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: widget.onInbox,
                          child: const Text('Inbox'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => widget.onCommit?.call(_selectedId),
                          child: const Text('Commit'),
                        ),
                      ],
                    ),
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
