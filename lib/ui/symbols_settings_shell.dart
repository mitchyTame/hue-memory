import 'package:flutter/material.dart';

import '../symbols/symbol_models.dart';
import '../theme/memory_hues.dart';

/// Settings → Symbols — pick active pack (YAML-backed).
class SymbolsSettingsShell extends StatelessWidget {
  const SymbolsSettingsShell({
    super.key,
    required this.packs,
    required this.activePackId,
    required this.onSelect,
    this.onBack,
    this.busy = false,
  });

  final List<SymbolPack> packs;
  final String activePackId;
  final ValueChanged<SymbolPack> onSelect;
  final VoidCallback? onBack;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: MemoryHues.paper,
      appBar: AppBar(
        title: const Text('Symbols'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Active pack maps circled ink icons to vault folders. '
            'Packs load from assets/packs/*.yaml.',
            style: textTheme.bodyMedium?.copyWith(color: MemoryHues.inkMuted),
          ),
          const SizedBox(height: 16),
          for (final pack in packs) ...[
            Material(
              color: pack.id == activePackId
                  ? MemoryHues.accentSoft
                  : MemoryHues.paperElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: pack.id == activePackId
                      ? MemoryHues.accent
                      : MemoryHues.rule,
                ),
              ),
              child: InkWell(
                onTap: busy ? null : () => onSelect(pack),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              pack.displayName,
                              style: textTheme.titleLarge,
                            ),
                          ),
                          if (pack.id == activePackId)
                            Text(
                              'Active',
                              style: textTheme.labelMedium?.copyWith(
                                color: MemoryHues.accent,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pack.id,
                        style: textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        pack.symbols
                            .map((s) => '${s.primaryGlyph} ${s.id}')
                            .join(' · '),
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
