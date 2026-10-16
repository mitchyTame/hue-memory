import 'package:flutter/material.dart';

import '../capture/pending_capture.dart';
import '../links/thread_tick.dart';
import '../ocr/ocr_client.dart';
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
  bool inkGhost,
});

/// Confirm-on-photo — photo hero, chips, edit title/body, Link picker, Commit.
///
/// For △ visual: ink-ghost toggle dims the page under editable region cards.
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
  bool _inkGhost = true;
  late bool _threadFromLast;

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
    _threadFromLast = widget.capture.meaning.threadTick || _links.isNotEmpty;
  }

  LinkPick? get _previousCandidate =>
      widget.linkCandidates.isEmpty ? null : widget.linkCandidates.first;

  void _setThreadFromLast(bool on) {
    final prev = _previousCandidate;
    setState(() {
      _threadFromLast = on;
      if (on) {
        _links = ThreadTick.mergePrevious(previous: prev, existing: _links);
      } else if (prev != null) {
        final norm = prev.targetPath.replaceAll(RegExp(r'\.md$'), '');
        _links = _links
            .where(
              (l) => l.targetPath.replaceAll(RegExp(r'\.md$'), '') != norm,
            )
            .toList();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  bool get _isDaily => _router.routeById(_selectedId).isDailyTasks;
  bool get _isCanvas => _router.routeById(_selectedId).isCanvas;

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
      inkGhost: _isCanvas ? _inkGhost : true,
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Opacity(
                          opacity: _isCanvas && _inkGhost ? 0.36 : 1,
                          child: Image.memory(
                            widget.capture.imageBytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                        if (_isCanvas)
                          _InkGhostNodeLayer(
                            regions: widget.capture.meaning.regions,
                            parentSize: Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            ),
                          )
                        else
                          CustomPaint(
                            painter: RegionOverlayPainter(
                              regions: widget.capture.meaning.regions,
                            ),
                          ),
                      ],
                    );
                  },
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
                    if (!_isDaily && _previousCandidate != null)
                      SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        title: Text(
                          'Thread › from last',
                          style: textTheme.titleMedium,
                        ),
                        subtitle: Text(
                          _previousCandidate!.displayTitle ??
                              _previousCandidate!.targetPath,
                          style: textTheme.bodySmall?.copyWith(
                            color: MemoryHues.inkMuted,
                          ),
                        ),
                        value: _threadFromLast,
                        activeThumbColor: MemoryHues.accent,
                        activeTrackColor: MemoryHues.accentSoft,
                        onChanged: widget.committing || _isDaily
                            ? null
                            : _setThreadFromLast,
                      ),
                    if (_isCanvas)
                      SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        title: Text(
                          'Ink ghost',
                          style: textTheme.titleMedium,
                        ),
                        subtitle: Text(
                          'Page photo under editable nodes',
                          style: textTheme.bodySmall?.copyWith(
                            color: MemoryHues.inkMuted,
                          ),
                        ),
                        value: _inkGhost,
                        activeThumbColor: MemoryHues.accent,
                        activeTrackColor: MemoryHues.accentSoft,
                        onChanged: widget.committing
                            ? null
                            : (v) => setState(() => _inkGhost = v),
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
                                    ? '→ ${route.folder}/ (.canvas'
                                        '${_inkGhost ? ', ink-ghost' : ''})'
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

/// Editable-looking region cards laid over the (optionally ghosted) page photo.
class _InkGhostNodeLayer extends StatelessWidget {
  const _InkGhostNodeLayer({
    required this.regions,
    required this.parentSize,
  });

  final List<OcrRegion> regions;
  final Size parentSize;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Stack(
      children: [
        for (var i = 0; i < regions.length; i++)
          _positionedCard(
            region: regions[i],
            index: i,
            textTheme: textTheme,
          ),
      ],
    );
  }

  Widget _positionedCard({
    required OcrRegion region,
    required int index,
    required TextTheme textTheme,
  }) {
    final bbox = region.bbox;
    final left = (bbox != null && bbox.length >= 4 ? bbox[0] : 0.12) *
        parentSize.width;
    final top = (bbox != null && bbox.length >= 4
            ? bbox[1]
            : 0.18 + index * 0.14) *
        parentSize.height;
    final width = (bbox != null && bbox.length >= 4 ? bbox[2] : 0.5) *
        parentSize.width;
    final height = (bbox != null && bbox.length >= 4 ? bbox[3] : 0.1) *
        parentSize.height;

    return Positioned(
      left: left.clamp(0, parentSize.width - 48),
      top: top.clamp(0, parentSize.height - 32),
      width: width.clamp(96, parentSize.width),
      height: height.clamp(36, parentSize.height),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MemoryHues.paperElevated.withValues(alpha: 0.92),
          border: Border.all(color: MemoryHues.accent, width: 1.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            region.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium?.copyWith(color: MemoryHues.ink),
          ),
        ),
      ),
    );
  }
}
