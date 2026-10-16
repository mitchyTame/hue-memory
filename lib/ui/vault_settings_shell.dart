import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../theme/memory_hues.dart';
import '../vault/local_vault_fs.dart';
import '../vault/vault_fs.dart';
import '../vault/vault_paths.dart';

/// Vault path screen — pick Obsidian vault folder; keep Obsidian open.
class VaultSettingsShell extends StatelessWidget {
  const VaultSettingsShell({
    super.key,
    required this.vaultRootLabel,
    required this.onChooseFolder,
    required this.onWriteTestNote,
    required this.onUseDefault,
    this.onBack,
    this.busy = false,
    this.lastProbePath,
  });

  final String vaultRootLabel;
  final VoidCallback? onChooseFolder;
  final VoidCallback? onWriteTestNote;
  final VoidCallback? onUseDefault;
  final VoidCallback? onBack;
  final bool busy;
  final String? lastProbePath;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: MemoryHues.paper,
      appBar: AppBar(
        title: const Text('Vault'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Choose the Obsidian vault folder on this device. hue-memory writes '
            'plain notes and canvases there. You can leave Obsidian open.',
            style: textTheme.bodyMedium?.copyWith(color: MemoryHues.inkMuted),
          ),
          const SizedBox(height: 20),
          Text('Vault folder', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MemoryHues.paperElevated,
              border: Border.all(color: MemoryHues.rule),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              vaultRootLabel,
              style: textTheme.labelMedium?.copyWith(color: MemoryHues.ink),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : onChooseFolder,
            child: const Text('Choose vault folder'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: busy ? null : onUseDefault,
            child: const Text('Use app default folder'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy ? null : onWriteTestNote,
            child: const Text('Write test note'),
          ),
          if (lastProbePath != null) ...[
            const SizedBox(height: 16),
            Text(
              'Wrote $lastProbePath',
              style: textTheme.bodySmall?.copyWith(color: MemoryHues.accent),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Tip: pick the same folder Obsidian opens as your vault. '
            'Obsidian can stay open — you do not need to close it. '
            'The app default folder works for a quick try without picking.',
            style: textTheme.bodySmall?.copyWith(color: MemoryHues.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// Writes a tiny probe note at vault **root** (no nested `hue-memory/` folder).
Future<String> writeVaultProbe(VaultFs vault) async {
  final stamp = DateTime.now().toUtc().toIso8601String();
  await vault.writeText(
    kVaultProbeRelative,
    '# hue-memory probe\n\nWritten at $stamp\n',
  );
  if (vault is LocalVaultFs) {
    return p.join(vault.rootPath, kVaultProbeRelative);
  }
  return kVaultProbeRelative;
}
