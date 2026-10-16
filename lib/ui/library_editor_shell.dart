import 'package:flutter/material.dart';

import '../symbols/ink_library.dart';
import '../symbols/pack_editor.dart';
import '../symbols/symbol_models.dart';
import '../theme/memory_hues.dart';
import 'ink_glyph_painter.dart';

/// Settings → Symbols → Library — browse 18 glyphs, edit custom pack.
class LibraryEditorShell extends StatefulWidget {
  const LibraryEditorShell({
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
  State<LibraryEditorShell> createState() => _LibraryEditorShellState();
}

class _LibraryEditorShellState extends State<LibraryEditorShell> {
  late SymbolPack _pack;
  String? _editingId;
  late final TextEditingController _folder;
  SymbolOutput _output = SymbolOutput.markdown;
  String? _message;

  @override
  void initState() {
    super.initState();
    _pack = widget.pack.copyWith(id: PackEditor.customPackId);
    _folder = TextEditingController();
  }

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  void _startAdd(DrawGlyph glyph) {
    final suggested = InkLibrary.suggestedSymbol(glyph.id);
    setState(() {
      _editingId = null;
      _folder.text = suggested.folder ?? '';
      _output = suggested.output;
      _message = null;
      try {
        _pack = PackEditor.addSymbol(_pack, suggested);
        _editingId = suggested.id;
        _message = PackSizeGuide.sizeMessage(_pack.symbols.length);
      } catch (e) {
        _message = '$e';
      }
    });
  }

  void _startEdit(PackSymbol symbol) {
    setState(() {
      _editingId = symbol.id;
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
    final folder = _folder.text.trim();
    final updated = current.copyWith(
      // Keep stable id once added; name field edits folder role label via id only for new.
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
        _pack = PackEditor.removeSymbol(_pack, id);
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

    return Scaffold(
      backgroundColor: MemoryHues.paper,
      appBar: AppBar(
        title: const Text('Ink library'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.busy ? null : widget.onBack,
        ),
        actions: [
          TextButton(
            onPressed: widget.busy ? null : _save,
            child: const Text('Save pack'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Active custom pack picks from the 18-glyph ink library. '
            'Capture chips show only this pack.',
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
          Text('In pack (${_pack.symbols.length})', style: textTheme.titleLarge),
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
                      Text(s.id),
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
          if (editing != null) ...[
            const SizedBox(height: 16),
            Text('Edit ${editing.id}', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _folder,
              enabled: !widget.busy && editing.id != 'inbox',
              decoration: const InputDecoration(
                labelText: 'Vault folder',
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
            if (editing.id != 'inbox')
              TextButton(
                onPressed: widget.busy ? null : _removeCurrent,
                child: const Text('Remove from pack'),
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
              return Material(
                color: MemoryHues.paperElevated,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: MemoryHues.rule),
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
