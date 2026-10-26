import 'package:flutter/material.dart';

import '../symbols/pack_editor.dart';
import '../symbols/symbol_models.dart';
import '../theme/memory_hues.dart';
import '../vault/vault_paths.dart';
import 'ink_glyph_painter.dart';

/// Edit vault folder + capture type for each symbol in the active pack.
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

  void _cycleType(PackSymbol symbol) {
    final updated = PackEditor.cycleCaptureType(symbol);
    setState(() {
      _pack = PackEditor.updateSymbol(_pack, updated);
      final c = _controllers[symbol.id];
      if (c != null &&
          updated.folder != null &&
          (c.text.trim().isEmpty ||
              symbol.output == SymbolOutput.dailyNoteAppend)) {
        c.text = updated.folder!;
      }
    });
  }

  void _removeSymbol(PackSymbol symbol) {
    try {
      final next = PackEditor.removeSymbol(_pack, symbol.id);
      _controllers.remove(symbol.id)?.dispose();
      setState(() => _pack = next);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  Future<void> _save() async {
    final callback = widget.onSave;
    if (callback == null || widget.busy) return;
    final updated = _applyFolders();
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
            'Folder, capture type (Text ↔ Visual), and remove — per symbol. '
            'Visual uses the Canvas mindmap path; Text uses OCR / markdown. '
            'Removed symbols leave camera chips until re-added from the library. '
            'Pack config stays in the app (not the vault).',
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
                TextButton(
                  onPressed: widget.busy ? null : () => _cycleType(s),
                  style: TextButton.styleFrom(
                    foregroundColor: s.isVisualCapture
                        ? MemoryHues.recall
                        : MemoryHues.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(PackEditor.captureTypeLabel(s.captureType)),
                ),
                if (s.id != 'inbox')
                  IconButton(
                    tooltip: 'Remove from pack',
                    onPressed: widget.busy ? null : () => _removeSymbol(s),
                    icon: const Icon(Icons.remove_circle_outline),
                    color: MemoryHues.danger,
                    visualDensity: VisualDensity.compact,
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
                    : s.isVisualCapture
                        ? 'Canvas folder'
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
