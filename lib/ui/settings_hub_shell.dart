import 'package:flutter/material.dart';

import '../theme/memory_hues.dart';

/// Simple settings list — vault + OCR (one job each via drill-in).
class SettingsHubShell extends StatelessWidget {
  const SettingsHubShell({
    super.key,
    required this.vaultLabel,
    required this.ocrModeLabel,
    this.onOpenVault,
    this.onOpenOcr,
    this.onBack,
  });

  final String vaultLabel;
  final String ocrModeLabel;
  final VoidCallback? onOpenVault;
  final VoidCallback? onOpenOcr;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: MemoryHues.paper,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text('Vault', style: textTheme.titleLarge),
            subtitle: Text(vaultLabel, style: textTheme.labelMedium),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenVault,
          ),
          const Divider(height: 1),
          ListTile(
            title: Text('OCR', style: textTheme.titleLarge),
            subtitle: Text(ocrModeLabel, style: textTheme.labelMedium),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenOcr,
          ),
        ],
      ),
    );
  }
}
