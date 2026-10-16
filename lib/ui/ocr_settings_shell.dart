import 'package:flutter/material.dart';

import '../ocr/ocr_settings.dart';
import '../theme/memory_hues.dart';

/// OCR settings — Mistral key, consent, mock vs live.
class OcrSettingsShell extends StatefulWidget {
  const OcrSettingsShell({
    super.key,
    required this.initial,
    required this.onSave,
    this.onBack,
  });

  final OcrSettings initial;
  final Future<void> Function(OcrSettings settings) onSave;
  final VoidCallback? onBack;

  @override
  State<OcrSettingsShell> createState() => _OcrSettingsShellState();
}

class _OcrSettingsShellState extends State<OcrSettingsShell> {
  late final TextEditingController _keyController;
  late bool _consent;
  late bool _useLive;
  bool _saving = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.initial.apiKey);
    _consent = widget.initial.consentGiven;
    _useLive = widget.initial.useLive;
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final next = OcrSettings(
      apiKey: _keyController.text.trim(),
      consentGiven: _consent,
      useLive: _useLive,
    );
    await widget.onSave(next);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next.shouldUseLive
              ? 'Live Mistral OCR enabled'
              : 'Using mock OCR (offline stub)',
        ),
        backgroundColor: MemoryHues.accent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: MemoryHues.paper,
      appBar: AppBar(
        title: const Text('OCR'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Meaning pass runs after capture. Mock stays default until you '
            'consent and enable live Mistral OCR.',
            style: textTheme.bodyMedium?.copyWith(color: MemoryHues.inkMuted),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _keyController,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Mistral API key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Or set env MISTRAL_API_KEY (overrides empty field on next launch). '
            'Key is stored in the platform secure store (Keystore / Keychain).',
            style: textTheme.bodySmall?.copyWith(color: MemoryHues.inkMuted),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _consent,
            activeColor: MemoryHues.accent,
            title: Text(
              'I consent to uploading page photos to Mistral for OCR',
              style: textTheme.bodyMedium,
            ),
            onChanged: (v) => setState(() => _consent = v ?? false),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _useLive,
            activeThumbColor: MemoryHues.accent,
            title: Text('Use live Mistral OCR', style: textTheme.bodyMedium),
            subtitle: Text(
              _useLive
                  ? 'Photos leave the device when you confirm capture'
                  : 'Mock OCR only (no network)',
              style: textTheme.bodySmall,
            ),
            onChanged: (v) => setState(() => _useLive = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save OCR settings'),
          ),
        ],
      ),
    );
  }
}
