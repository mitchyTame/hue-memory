import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../theme/memory_hues.dart';
import '../vault/local_vault_fs.dart';
import '../vault/vault_fs.dart';

/// Vault path screen — trust the folder link (Memory hues §3.5).
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
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'hue-memory writes plain Obsidian files into this folder.',
              style: textTheme.bodyMedium?.copyWith(color: MemoryHues.inkMuted),
            ),
            const SizedBox(height: 20),
            Text('Vault root', style: textTheme.labelLarge),
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
            const Spacer(),
            Text(
              'TODO(saf): On Android this becomes a Storage Access Framework '
              'tree URI — not a dart:io path.',
              style: textTheme.bodySmall?.copyWith(color: MemoryHues.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Writes a tiny probe note to prove the vault root is writable.
Future<String> writeVaultProbe(VaultFs vault) async {
  const relative = 'hue-memory/probe.md';
  final stamp = DateTime.now().toUtc().toIso8601String();
  await vault.writeText(
    relative,
    '# hue-memory probe\n\nWritten at $stamp\n',
  );
  if (vault is LocalVaultFs) {
    return p.join(vault.rootPath, relative);
  }
  return relative;
}
