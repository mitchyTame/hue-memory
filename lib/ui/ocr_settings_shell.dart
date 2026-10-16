import 'package:flutter/material.dart';

import '../ocr/mistral_ocr_client.dart';
import '../ocr/ocr_settings.dart';
import '../theme/memory_hues.dart';

/// OCR settings — Mistral key, consent, mock vs live, live connection test.
class OcrSettingsShell extends StatefulWidget {
  const OcrSettingsShell({
    super.key,
    required this.initial,
    required this.onSave,
    this.onVerifyKey,
    this.onBack,
  });

  final OcrSettings initial;
  final Future<void> Function(OcrSettings settings) onSave;

  /// Live Mistral OCR probe. Returns readable success/failure message.
  final Future<MistralConnectionResult> Function(String apiKey)? onVerifyKey;
  final VoidCallback? onBack;

  @override
  State<OcrSettingsShell> createState() => _OcrSettingsShellState();
}

class _OcrSettingsShellState extends State<OcrSettingsShell> {
  late final TextEditingController _keyController;
  late bool _consent;
  late bool _useLive;
  bool _saving = false;
  bool _testing = false;
  bool _obscure = true;
  String? _status;
  bool _statusOk = false;

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

  Future<MistralConnectionResult?> _runVerify() async {
    final verify = widget.onVerifyKey;
    final key = _keyController.text.trim();
    if (verify == null) return null;
    if (key.isEmpty) {
      return const MistralConnectionResult(
        ok: false,
        message: 'Enter a Mistral API key first',
      );
    }
    setState(() {
      _testing = true;
      _status = 'Testing Mistral OCR…';
      _statusOk = false;
    });
    try {
      final result = await verify(key);
      if (!mounted) return result;
      setState(() {
        _testing = false;
        _status = result.message;
        _statusOk = result.ok;
      });
      return result;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _testing = false;
        _status = 'Test failed: $e';
        _statusOk = false;
      });
      return MistralConnectionResult(ok: false, message: '$e');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final next = OcrSettings(
      apiKey: _keyController.text.trim(),
      consentGiven: _consent,
      useLive: _useLive,
    );

    // When enabling live OCR with a key, verify against the real endpoint.
    if (next.shouldUseLive && widget.onVerifyKey != null) {
      final result = await _runVerify();
      if (result != null && !result.ok) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: MemoryHues.danger,
          ),
        );
        return;
      }
    }

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
    final busy = _saving || _testing;

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
            'After you shoot a page, hue-memory reads the ink (OCR) and '
            'suggests a symbol. Mock stays default until you consent, add a '
            'key, and turn on live Mistral.',
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
            onChanged: busy ? null : (v) => setState(() => _consent = v ?? false),
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
            onChanged: busy ? null : (v) => setState(() => _useLive = v),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(
              _status!,
              style: textTheme.bodyMedium?.copyWith(
                color: _statusOk ? MemoryHues.accent : MemoryHues.danger,
              ),
            ),
          ],
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: busy || widget.onVerifyKey == null ? null : _runVerify,
            child: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Test connection'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : _save,
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
