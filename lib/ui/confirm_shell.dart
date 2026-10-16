import 'package:flutter/material.dart';

import '../capture/pending_capture.dart';
import '../symbols/default_packs.dart';
import '../symbols/symbol_models.dart';
import '../symbols/symbol_router.dart';
import '../theme/memory_hues.dart';
import '../writers/link_writer.dart';
import 'link_picker_sheet.dart';
import 'region_overlay_painter.dart';

typedef ConfirmCommitCallback = Future<void> Function({
  required String symbolId,
  required String title,
  required String noteBody,
  required List<LinkPick> links,
});

/// Confirm-on-photo — photo hero, chips, edit title/body, Link picker, Commit.
class ConfirmShell extends StatefulWidget {
  const ConfirmShell({
    super.key,
    required this.capture,
    this.pack = DefaultPacks.zettelkastenInk,
    this.linkCandidates = const [],
    this.onCommit,
    this.onCancel,
    this.committing = false,
  });

  final PendingCapture capture;
  final SymbolPack pack;
  final List<LinkPick> linkCandidates;
  final ConfirmCommitCallback? onCommit;
  final VoidCallback? onCancel;
  final bool committing;

  @override
  State<ConfirmShell> createState() => _ConfirmShellState();
}

class _ConfirmShellState extends State<ConfirmShell> {
  late String _selectedId;
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late List<LinkPick> _links;
  late final SymbolRouter _router;

  @override
  void initState() {
    super.initState();
    _router = SymbolRouter(pack: widget.pack);
    final routed = widget.capture.symbolId.isNotEmpty
        ? _router.routeById(widget.capture.symbolId)
        : _router.route(widget.capture.meaning.detectedGlyph);
    _selectedId = routed.symbol.id;
    _titleController = TextEditingController(text: widget.capture.title);
    _bodyController = TextEditingController(text: widget.capture.noteBody);
    _links = List<LinkPick>.from(widget.capture.links);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  bool get _isDaily => _router.routeById(_selectedId).isDailyTasks;

  Future<void> _openLinks() async {
    final result = await showLinkPickerSheet(
      context: context,
      candidates: widget.linkCandidates,
      initiallySelected: _links,
    );
    if (result != null) {
      setState(() => _links = result);
    }
  }

  Future<void> _commit() async {
    final callback = widget.onCommit;
    if (callback == null || widget.committing) return;
    await callback(
      symbolId: _selectedId,
      title: _titleController.text.trim().isEmpty
          ? 'Untitled page'
          : _titleController.text.trim(),
      noteBody: _bodyController.text,
      links: _links,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final symbols = widget.pack.symbols;
    final route = _router.routeById(_selectedId);

    return Scaffold(
      backgroundColor: MemoryHues.ink,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      widget.capture.imageBytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                    CustomPaint(
                      painter: RegionOverlayPainter(
                        regions: widget.capture.meaning.regions,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Material(
              color: MemoryHues.paperElevated,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              elevation: 1,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: MemoryHues.rule,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Confirm meaning',
                              style: textTheme.titleLarge,
                            ),
                          ),
                          Text(
                            widget.capture.pageId,
                            style: textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 48,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: symbols.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final s = symbols[index];
                          final selected = s.id == _selectedId;
                          return ChoiceChip(
                            label: Text('${s.primaryGlyph} ${s.id}'),
                            selected: selected,
                            onSelected: widget.committing
                                ? null
                                : (_) => setState(() => _selectedId = s.id),
                            selectedColor: MemoryHues.accentSoft,
                            side: BorderSide(
                              color: selected
                                  ? MemoryHues.accent
                                  : MemoryHues.rule,
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: TextField(
                        controller: _titleController,
                        enabled: !widget.committing && !_isDaily,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: TextField(
                        controller: _bodyController,
                        enabled: !widget.committing,
                        minLines: _isDaily ? 2 : 3,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText: _isDaily ? 'Tasks (one per line)' : 'Note',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    if (route.folder != null || route.isDailyTasks)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            route.isDailyTasks
                                ? '→ Daily Notes (## Tasks)'
                                : route.isCanvas
                                    ? '→ ${route.folder}/ (.canvas)'
                                    : '→ ${route.folder}/',
                            style: textTheme.labelMedium,
                          ),
                        ),
                      ),
                    if (_links.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Links: ${_links.map((l) => l.displayTitle ?? l.targetPath).join(', ')}',
                            style: textTheme.bodySmall,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed:
                                widget.committing ? null : widget.onCancel,
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: widget.committing || _isDaily
                                ? null
                                : _openLinks,
                            child: Text(
                              'Link${_links.isEmpty ? '' : ' (${_links.length})'}',
                            ),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: widget.committing ? null : _commit,
                            child: widget.committing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Commit'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
