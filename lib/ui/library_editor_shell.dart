import 'package:flutter/material.dart';

import '../symbols/ink_library.dart';
import '../symbols/pack_editor.dart';
import '../symbols/symbol_models.dart';
import '../theme/memory_hues.dart';
import '../vault/vault_paths.dart';
import 'ink_glyph_painter.dart';

/// Settings → Symbols → Library — pick glyphs, extend the active pack.
///
/// Defaults stay intact; user extras are additive and editable.
class LibraryEditorShell extends StatefulWidget {
  const LibraryEditorShell({
    super.key,
    required this.pack,
    required this.basePack,
    this.busy = false,
    this.onBack,
    this.onSave,
  });

  /// Active pack (defaults + any extras already merged).
  final SymbolPack pack;

  /// Bundled/base pack without user extras (for lock / remove rules).
  final SymbolPack basePack;

  final bool busy;
  final VoidCallback? onBack;
  final Future<void> Function(SymbolPack pack)? onSave;

  @override
  State<LibraryEditorShell> createState() => _LibraryEditorShellState();
}

class _LibraryEditorShellState extends State<LibraryEditorShell> {
  late SymbolPack _pack;
  String? _editingId;
  late final TextEditingController _label;
  late final TextEditingController _folder;
  SymbolOutput _output = SymbolOutput.markdown;
  String? _message;
  String? _pendingDrawId;

  @override
  void initState() {
    super.initState();
    _pack = widget.pack;
    _label = TextEditingController();
    _folder = TextEditingController();
  }

  @override
  void dispose() {
    _label.dispose();
    _folder.dispose();
    super.dispose();
  }

  bool _isExtra(String symbolId) =>
      !PackEditor.isBaseSymbol(widget.basePack, symbolId);

  void _startAdd(DrawGlyph glyph) {
    final suggested = InkLibrary.suggestedSymbol(glyph.id);
    setState(() {
      _pendingDrawId = glyph.id;
      _editingId = null;
      _label.text = suggested.id;
      _folder.text = suggested.folder ?? '';
      _output = SymbolOutput.markdown;
      _message = null;
    });
  }

  void _confirmAdd() {
    final drawId = _pendingDrawId;
    if (drawId == null) return;
    try {
      final folderNorm = normalizeVaultFolder(_folder.text);
      final extra = PackEditor.extraFromLibrary(
        drawId: drawId,
        label: _label.text,
        folder: folderNorm ?? _folder.text.trim(),
        output: _output,
      );
      setState(() {
        _pack = PackEditor.addSymbol(_pack, extra);
        _editingId = extra.id;
        _pendingDrawId = null;
        _message = PackSizeGuide.sizeMessage(_pack.symbols.length);
      });
    } catch (e) {
      setState(() => _message = '$e');
    }
  }

  void _startEdit(PackSymbol symbol) {
    setState(() {
      _pendingDrawId = null;
      _editingId = symbol.id;
      _label.text = symbol.id;
      _folder.text = symbol.folder ?? '';
      _output = symbol.output;
      _message = null;
    });
  }

  void _applyEdit() {
    final id = _editingId;
    if (id == null) return;
    final current = _pack.byId(id);
    if (current == null) return;
    // Base symbols: folder/output only. Extras: same (id stays stable).
    final folderNorm = normalizeVaultFolder(_folder.text);
    final folder = folderNorm ?? _folder.text.trim();
    final updated = current.copyWith(
      folder: folder.isEmpty ? null : folder,
      clearFolder: folder.isEmpty && _output != SymbolOutput.dailyNoteAppend,
      output: _output,
      section: _output == SymbolOutput.dailyNoteAppend
          ? (current.section ?? '## Tasks')
          : null,
      clearSection: _output != SymbolOutput.dailyNoteAppend,
    );
    setState(() {
      _pack = PackEditor.updateSymbol(_pack, updated);
      _message = PackSizeGuide.sizeMessage(_pack.symbols.length);
    });
  }

  void _removeCurrent() {
    final id = _editingId;
    if (id == null) return;
    try {
      setState(() {
        _pack = PackEditor.removeSymbol(
          _pack,
          id,
          base: widget.basePack,
        );
        _editingId = null;
        _message = PackSizeGuide.sizeMessage(_pack.symbols.length);
      });
    } catch (e) {
      setState(() => _message = '$e');
    }
  }

  Future<void> _save() async {
    final callback = widget.onSave;
    if (callback == null || widget.busy) return;
    await callback(_pack);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final available = PackEditor.availableLibraryGlyphs(_pack);
    final editing = _editingId == null ? null : _pack.byId(_editingId!);
    final adding = _pendingDrawId != null;
    final extras = PackEditor.extrasOf(_pack, widget.basePack);

    return Scaffold(
      backgroundColor: MemoryHues.paper,
      appBar: AppBar(
        title: const Text('Symbol library'),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Extend ${_pack.displayName} with glyphs from the library. '
            'Defaults stay; extras get a label and vault folder '
            '(e.g. Organising/Misc) and show on the camera chip row.',
            style: textTheme.bodyMedium?.copyWith(color: MemoryHues.inkMuted),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: textTheme.bodySmall?.copyWith(color: MemoryHues.recall),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Active set (${_pack.symbols.length})',
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _pack.symbols)
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CustomPaint(
                          painter: InkGlyphPainter(drawId: s.draw),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isExtra(s.id) ? '${s.id} · extra' : s.id,
                      ),
                    ],
                  ),
                  selected: _editingId == s.id,
                  onSelected: widget.busy ? null : (_) => _startEdit(s),
                  selectedColor: MemoryHues.accentSoft,
                  side: BorderSide(
                    color: _editingId == s.id
                        ? MemoryHues.accent
                        : MemoryHues.rule,
                  ),
                ),
            ],
          ),
          if (extras.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${extras.length} custom · reusable until removed',
              style: textTheme.labelMedium?.copyWith(
                color: MemoryHues.inkMuted,
              ),
            ),
          ],
          if (adding) ...[
            const SizedBox(height: 16),
            Text('Add from library', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _label,
              enabled: !widget.busy,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'e.g. misc or waiting',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _folder,
              enabled: !widget.busy,
              decoration: const InputDecoration(
                labelText: 'Vault folder',
                hintText: 'e.g. Organising/Misc',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<SymbolOutput>(
              key: ValueKey('add-output-$_pendingDrawId'),
              initialValue: _output,
              decoration: const InputDecoration(
                labelText: 'Output',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final o in SymbolOutput.values)
                  DropdownMenuItem(value: o, child: Text(o.name)),
              ],
              onChanged: widget.busy
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _output = v);
                    },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: widget.busy ? null : _confirmAdd,
                  child: const Text('Add to active pack'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: widget.busy
                      ? null
                      : () => setState(() {
                            _pendingDrawId = null;
                            _message = null;
                          }),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
          if (editing != null && !adding) ...[
            const SizedBox(height: 16),
            Text(
              _isExtra(editing.id)
                  ? 'Edit extra ${editing.id}'
                  : 'Edit ${editing.id} (default)',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _folder,
              enabled: !widget.busy && editing.id != 'inbox',
              decoration: const InputDecoration(
                labelText: 'Vault folder',
                hintText: 'e.g. Organising/Misc',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => _applyEdit(),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<SymbolOutput>(
              key: ValueKey('output-$_editingId-$_output'),
              initialValue: _output,
              decoration: const InputDecoration(
                labelText: 'Output',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final o in SymbolOutput.values)
                  DropdownMenuItem(value: o, child: Text(o.name)),
              ],
              onChanged: widget.busy || editing.id == 'inbox'
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _output = v);
                      _applyEdit();
                    },
            ),
            if (_isExtra(editing.id))
              TextButton(
                onPressed: widget.busy ? null : _removeCurrent,
                child: const Text('Remove from active pack'),
              ),
          ],
          const SizedBox(height: 24),
          Text('Library — tap to add', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: available.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (context, i) {
              final g = available[i];
              final selected = _pendingDrawId == g.id;
              return Material(
                color: selected
                    ? MemoryHues.accentSoft
                    : MemoryHues.paperElevated,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: selected ? MemoryHues.accent : MemoryHues.rule,
                  ),
                ),
                child: InkWell(
                  onTap: widget.busy ? null : () => _startAdd(g),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: CustomPaint(
                            painter: InkGlyphPainter(drawId: g.id),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          g.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
