import 'package:flutter/material.dart';

import '../symbols/pack_editor.dart';
import '../symbols/symbol_models.dart';
import '../theme/memory_hues.dart';
import '../vault/vault_paths.dart';
import 'ink_glyph_painter.dart';

/// Edit vault folder paths for each symbol in the active pack.
class FolderMapShell extends StatefulWidget {
  const FolderMapShell({
    super.key,
    required this.pack,
    this.busy = false,
    this.onBack,
    this.onSave,
  });

  final SymbolPack pack;
  final bool busy;
  final VoidCallback? onBack;
  final Future<void> Function(SymbolPack pack)? onSave;

  @override
  State<FolderMapShell> createState() => _FolderMapShellState();
}

class _FolderMapShellState extends State<FolderMapShell> {
  late SymbolPack _pack;
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _pack = widget.pack;
    _controllers = {
      for (final s in _pack.symbols)
        s.id: TextEditingController(
          text: s.output == SymbolOutput.dailyNoteAppend
              ? (s.folder ?? 'Organising/Daily')
              : (s.folder ?? ''),
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  SymbolPack _applyFolders() {
    final next = <PackSymbol>[];
    for (final s in _pack.symbols) {
      final text = _controllers[s.id]?.text.trim() ?? '';
      final normalized = normalizeVaultFolder(text);
      if (s.output == SymbolOutput.dailyNoteAppend) {
        // Daily notes: folder is where the daily file lives.
        next.add(
          s.copyWith(
            folder: normalized ?? 'Organising/Daily',
          ),
        );
      } else {
        next.add(
          s.copyWith(
            folder: normalized,
            clearFolder: normalized == null,
          ),
        );
      }
    }
    return _pack.copyWith(symbols: next);
  }

  Future<void> _save() async {
    final callback = widget.onSave;
    if (callback == null || widget.busy) return;
    final updated = _applyFolders();
    // Validate markdown/canvas symbols have folders.
    for (final s in updated.symbols) {
      if (s.output == SymbolOutput.dailyNoteAppend) continue;
      if (s.folder == null || s.folder!.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${s.id} needs a vault folder'),
            backgroundColor: MemoryHues.danger,
          ),
        );
        return;
      }
    }
    await callback(updated);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: MemoryHues.paper,
      appBar: AppBar(
        title: const Text('Vault folders'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.busy ? null : widget.onBack,
        ),
        actions: [
          TextButton(
            onPressed: widget.busy ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Type a vault-relative folder per symbol — nested paths are fine '
            '(e.g. Organising/Daily, journal). Defaults: inbox, fleeting, '
            'literature, permanent, mindmaps, Journal → journal, '
            'Organising/Daily.',
            style: textTheme.bodyMedium?.copyWith(color: MemoryHues.inkMuted),
          ),
          const SizedBox(height: 16),
          for (final s in _pack.symbols) ...[
            Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CustomPaint(
                    painter: InkGlyphPainter(drawId: s.draw),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${s.primaryGlyph}  ${s.id}',
                    style: textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controllers[s.id],
              enabled: !widget.busy,
              decoration: InputDecoration(
                labelText: s.output == SymbolOutput.dailyNoteAppend
                    ? 'Daily notes folder'
                    : 'Vault folder',
                hintText: s.output == SymbolOutput.dailyNoteAppend
                    ? 'Organising/Daily'
                    : 'e.g. fleeting or Organising/monthly',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
