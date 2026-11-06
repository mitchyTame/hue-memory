import 'package:flutter/material.dart';

import '../theme/memory_hues.dart';

/// Simple settings list — vault + OCR + Gemini (one job each via drill-in).
///
/// When [botAgentEnabled] is true, OCR / Symbols / Paper kit / Promote are
/// hidden; Vault + Bot agent + Gemini stay so the inbox canvas path can use
/// a live key.
class SettingsHubShell extends StatelessWidget {
  const SettingsHubShell({
    super.key,
    required this.vaultLabel,
    required this.ocrModeLabel,
    required this.packLabel,
    this.geminiModeLabel = 'Gemini: off',
    this.botAgentEnabled = false,
    this.botAgentLabel = 'Bot agent: off',
    this.onOpenVault,
    this.onOpenOcr,
    this.onOpenGemini,
    this.onOpenSymbols,
    this.onOpenPaperKit,
    this.onOpenPromote,
    this.onOpenGuide,
    this.onOpenBotAgent,
    this.onBack,
  });

  final String vaultLabel;
  final String ocrModeLabel;
  final String packLabel;
  final String geminiModeLabel;
  final bool botAgentEnabled;
  final String botAgentLabel;
  final VoidCallback? onOpenVault;
  final VoidCallback? onOpenOcr;
  final VoidCallback? onOpenGemini;
  final VoidCallback? onOpenSymbols;
  final VoidCallback? onOpenPaperKit;
  final VoidCallback? onOpenPromote;
  final VoidCallback? onOpenGuide;
  final VoidCallback? onOpenBotAgent;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final botOn = botAgentEnabled;

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
            title: Text('How to use', style: textTheme.titleLarge),
            subtitle: Text(
              botOn ? 'Scan → inbox .canvas' : 'Paper → confirm → vault',
              style: textTheme.labelMedium,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenGuide,
          ),
          const Divider(height: 1),
          ListTile(
            title: Text('Vault', style: textTheme.titleLarge),
            subtitle: Text(vaultLabel, style: textTheme.labelMedium),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenVault,
          ),
          const Divider(height: 1),
          ListTile(
            title: Text('Bot agent', style: textTheme.titleLarge),
            subtitle: Text(botAgentLabel, style: textTheme.labelMedium),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenBotAgent,
          ),
          const Divider(height: 1),
          ListTile(
            title: Text('Gemini', style: textTheme.titleLarge),
            subtitle: Text(geminiModeLabel, style: textTheme.labelMedium),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenGemini,
          ),
          if (!botOn) ...[
            const Divider(height: 1),
            ListTile(
              title: Text('OCR', style: textTheme.titleLarge),
              subtitle: Text(ocrModeLabel, style: textTheme.labelMedium),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenOcr,
            ),
            const Divider(height: 1),
            ListTile(
              title: Text('Symbols', style: textTheme.titleLarge),
              subtitle: Text(packLabel, style: textTheme.labelMedium),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenSymbols,
            ),
            const Divider(height: 1),
            ListTile(
              title: Text('Paper kit', style: textTheme.titleLarge),
              subtitle: Text(
                'A6 legend + hue-dot stickers',
                style: textTheme.labelMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenPaperKit,
            ),
            const Divider(height: 1),
            ListTile(
              title: Text('Promote ritual', style: textTheme.titleLarge),
              subtitle: Text(
                '∼ fleeting → ◇ permanent',
                style: textTheme.labelMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenPromote,
            ),
          ],
        ],
      ),
    );
  }
}
