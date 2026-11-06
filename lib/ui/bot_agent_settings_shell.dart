import 'package:flutter/material.dart';

import '../settings/bot_agent_settings.dart';
import '../theme/memory_hues.dart';

/// Bot agent mode — enable scan-to-inbox canvases and set the vault folder.
class BotAgentSettingsShell extends StatefulWidget {
  const BotAgentSettingsShell({
    super.key,
    required this.initial,
    required this.onSave,
    this.onBack,
  });

  final BotAgentSettings initial;
  final Future<void> Function(BotAgentSettings settings) onSave;
  final VoidCallback? onBack;

  @override
  State<BotAgentSettingsShell> createState() => _BotAgentSettingsShellState();
}

class _BotAgentSettingsShellState extends State<BotAgentSettingsShell> {
  late bool _enabled;
  late final TextEditingController _folderController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initial.enabled;
    _folderController = TextEditingController(text: widget.initial.inboxFolder);
  }

  @override
  void dispose() {
    _folderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final folder = _folderController.text.trim().isEmpty
        ? BotAgentSettings.defaultInboxFolder
        : _folderController.text.trim();
    final next = BotAgentSettings(enabled: _enabled, inboxFolder: folder);
    try {
      await widget.onSave(next);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _enabled
                ? 'Bot agent on — canvases go to $folder'
                : 'Bot agent off — full hue-memory restored',
          ),
          backgroundColor: MemoryHues.accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: MemoryHues.paper,
      appBar: AppBar(
        title: const Text('Bot agent'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _saving ? null : widget.onBack,
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Bot agent mode', style: textTheme.titleLarge),
            subtitle: Text(
              'Scan → Gemini typed canvas in the inbox folder. '
              'No OCR, symbols, or confirm.',
              style: textTheme.labelMedium,
            ),
            value: _enabled,
            activeThumbColor: MemoryHues.paperElevated,
            activeTrackColor: MemoryHues.accent,
            onChanged: _saving
                ? null
                : (v) => setState(() => _enabled = v),
          ),
          const Divider(height: 24),
          Text('Inbox folder', style: textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Nested vault path where .canvas files are written '
            '(e.g. inbox or Bot/Inbox). Needs Gemini live.',
            style: textTheme.labelMedium?.copyWith(
              color: MemoryHues.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _folderController,
            enabled: !_saving,
            decoration: const InputDecoration(
              hintText: 'inbox',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          if (_enabled) ...[
            const SizedBox(height: 16),
            Text(
              'Each capture writes YYYY-MM-DD.canvas here, with the photo '
              'under captures/raw/. Downstream bots read the typed canvas.',
              style: textTheme.bodyMedium?.copyWith(
                color: MemoryHues.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
