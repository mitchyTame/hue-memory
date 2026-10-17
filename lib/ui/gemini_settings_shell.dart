import 'package:flutter/material.dart';

import '../gemini/gemini_client.dart';
import '../gemini/gemini_settings.dart';
import '../theme/memory_hues.dart';

/// Gemini Flash settings — AI Studio key, model picker, Test Gemini.
class GeminiSettingsShell extends StatefulWidget {
  const GeminiSettingsShell({
    super.key,
    required this.initial,
    required this.onSave,
    this.onVerifyKey,
    this.onBack,
  });

  final GeminiSettings initial;
  final Future<void> Function(GeminiSettings settings) onSave;

  /// Tiny Flash text probe (shared model). Pass/fail message.
  final Future<GeminiConnectionResult> Function(
    String apiKey,
    String model,
  )? onVerifyKey;
  final VoidCallback? onBack;

  @override
  State<GeminiSettingsShell> createState() => _GeminiSettingsShellState();
}

class _GeminiSettingsShellState extends State<GeminiSettingsShell> {
  late final TextEditingController _keyController;
  late String _model;
  late bool _consent;
  late bool _useLive;
  bool _saving = false;
  bool _testing = false;
  bool _obscure = true;
  String? _status;
  bool _statusOk = false;

  static const _labels = <String, String>{
    GeminiSettings.defaultModel: '3.5 Flash-lite (default)',
    GeminiSettings.flash36Model: '3.6 Flash',
  };

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.initial.apiKey);
    _model = GeminiSettings.resolveModel(widget.initial.model);
    // If Mitch typed something else earlier, keep it selectable.
    if (!GeminiSettings.selectableModels.contains(_model)) {
      _model = GeminiSettings.defaultModel;
    }
    _consent = widget.initial.consentGiven;
    _useLive = widget.initial.useLive;
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<GeminiConnectionResult?> _runVerify() async {
    final verify = widget.onVerifyKey;
    final key = _keyController.text.trim();
    if (verify == null) return null;
    if (key.isEmpty) {
      return const GeminiConnectionResult(
        ok: false,
        message: 'Enter a Gemini API key first',
      );
    }
    setState(() {
      _testing = true;
      _status = 'Testing $_model…';
      _statusOk = false;
    });
    try {
      final result = await verify(key, _model);
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
      return GeminiConnectionResult(ok: false, message: '$e');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final next = GeminiSettings(
      apiKey: _keyController.text.trim(),
      consentGiven: _consent,
      useLive: _useLive,
      model: _model,
    );

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
              ? 'Live Gemini on — ${next.model}'
              : 'Gemini off — classify/diagram skipped',
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
        title: const Text('Gemini'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'One Flash model for classify and mindmap .canvas '
            '(never OCR-first for △). Text pages still use Mistral OCR.',
            style: textTheme.bodyMedium?.copyWith(color: MemoryHues.inkMuted),
          ),
          const SizedBox(height: 12),
          Text(
            'Paste an AI Studio key (starts with AIza…). Default is '
            '${GeminiSettings.defaultModel}. Switch to '
            '${GeminiSettings.flash36Model} when you want. No Pro.',
            style: textTheme.bodySmall?.copyWith(color: MemoryHues.inkMuted),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _keyController,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Gemini API key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Key is stored in the platform secure store. Never logged.',
            style: textTheme.bodySmall?.copyWith(color: MemoryHues.inkMuted),
          ),
          const SizedBox(height: 20),
          Text('Model', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          ...GeminiSettings.selectableModels.map((id) {
            final selected = _model == id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: selected
                    ? MemoryHues.accentSoft
                    : MemoryHues.paperElevated,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: busy ? null : () => setState(() => _model = id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected
                              ? MemoryHues.accent
                              : MemoryHues.inkMuted,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _labels[id] ?? id,
                                style: textTheme.titleMedium,
                              ),
                              Text(
                                id,
                                style: textTheme.bodySmall?.copyWith(
                                  color: MemoryHues.inkMuted,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _consent,
            activeColor: MemoryHues.accent,
            title: Text(
              'I consent to uploading page photos to Google Gemini',
              style: textTheme.bodyMedium,
            ),
            onChanged:
                busy ? null : (v) => setState(() => _consent = v ?? false),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _useLive,
            activeThumbColor: MemoryHues.accent,
            title: Text('Use live Gemini Flash', style: textTheme.bodyMedium),
            subtitle: Text(
              _useLive
                  ? 'Classify + diagram photos leave the device'
                  : 'Coordinator skips Gemini (text path / mock)',
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
                : const Text('Test Gemini'),
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
                : const Text('Save Gemini settings'),
          ),
        ],
      ),
    );
  }
}
