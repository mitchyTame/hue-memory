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

typedef ConfirmCommitCallback = Future<void> Function({
  required String symbolId,
  required String title,
  required String noteBody,
  required List<LinkPick> links,
  bool inkGhost,
  List<OcrRegion>? regions,
});

/// Confirm-on-photo — photo hero, symbol chips, edits, Commit.
///
/// - **△ / visual:** ink-ghost photo + tap markers; large node fields in the
///   sheet (vision-primary text). Add / remove nodes. No tiny overlays fighting
///   the photo.
/// - **Everything else:** title + note body from OCR — no vision pass.
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
  late List<OcrRegion> _regions;
  late List<TextEditingController> _nodeControllers;
  int? _focusedNode;

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
    _regions = List<OcrRegion>.from(widget.capture.meaning.regions);
    _nodeControllers = [
      for (final r in _regions) TextEditingController(text: r.text),
    ];
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
    for (final c in _nodeControllers) {
      c.dispose();
    }
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

  void _syncNodeText(int index, String text) {
    if (index < 0 || index >= _regions.length) return;
    final r = _regions[index];
    setState(() {
      _regions[index] = OcrRegion(
        id: r.id,
        text: text,
        confidence: r.confidence,
        bbox: r.bbox,
      );
    });
  }

  void _focusNode(int index) {
    if (widget.committing) return;
    setState(() => _focusedNode = index);
  }

  void _addNode() {
    if (widget.committing || _regions.length >= 12) return;
    final i = _regions.length;
    final top = (0.18 + (i % 6) * 0.12).clamp(0.05, 0.85);
    final left = i < 6 ? 0.12 : 0.52;
    setState(() {
      _regions.add(
        OcrRegion(
          id: 'n${i + 1}',
          text: '',
          confidence: 0.5,
          bbox: [left, top, 0.36, 0.1],
        ),
      );
      _nodeControllers.add(TextEditingController());
      _focusedNode = i;
    });
  }

  void _removeNode(int index) {
    if (widget.committing || index < 0 || index >= _regions.length) return;
    setState(() {
      _nodeControllers[index].dispose();
      _nodeControllers.removeAt(index);
      _regions.removeAt(index);
      if (_focusedNode == index) {
        _focusedNode = null;
      } else if (_focusedNode != null && _focusedNode! > index) {
        _focusedNode = _focusedNode! - 1;
      }
    });
  }

  Future<void> _commit() async {
    final callback = widget.onCommit;
    if (callback == null || widget.committing) return;
    // Pull latest text from controllers for canvas nodes.
    if (_isCanvas) {
      for (var i = 0; i < _regions.length && i < _nodeControllers.length; i++) {
        final t = _nodeControllers[i].text;
        final r = _regions[i];
        if (r.text != t) {
          _regions[i] = OcrRegion(
            id: r.id,
            text: t,
            confidence: r.confidence,
            bbox: r.bbox,
          );
        }
      }
    }
    await callback(
      symbolId: _selectedId,
      title: _titleController.text.trim().isEmpty
          ? 'Untitled page'
          : _titleController.text.trim(),
      noteBody: _bodyController.text,
      links: _links,
      inkGhost: _isCanvas ? _inkGhost : true,
      regions: _isCanvas ? List<OcrRegion>.from(_regions) : null,
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final short = constraints.maxHeight < 480;
            final sheetFlex = short ? 3 : 2;
            final photoFlex = short ? 2 : 3;

            return Column(
              children: [
                Expanded(
                  flex: photoFlex,
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: LayoutBuilder(
                      builder: (context, photoConstraints) {
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
                              _MindmapMarkerLayer(
                                regions: _regions,
                                parentSize: Size(
                                  photoConstraints.maxWidth,
                                  photoConstraints.maxHeight,
                                ),
                                focusedIndex: _focusedNode,
                                enabled: !widget.committing,
                                onTap: _focusNode,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                Flexible(
                  flex: sheetFlex,
                  child: Material(
                    color: MemoryHues.paperElevated,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    elevation: 1,
                    child: Column(
                      children: [
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: MemoryHues.rule,
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            children: [
                              Text(
                                _isCanvas ? 'Fix mindmap words' : 'Confirm',
                                style: textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isCanvas
                                    ? 'Tap a marker on the photo, then edit below. '
                                        'Words come from vision — change anything wrong.'
                                    : 'Check the title and note, then save.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: MemoryHues.inkMuted,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text('Symbol', style: textTheme.labelLarge),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 44,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: symbols.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    final s = symbols[index];
                                    final selected = s.id == _selectedId;
                                    return ChoiceChip(
                                      label: Text('${s.primaryGlyph} ${s.id}'),
                                      selected: selected,
                                      onSelected: widget.committing
                                          ? null
                                          : (_) => setState(
                                                () => _selectedId = s.id,
                                              ),
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
                              if (route.folder != null || route.isDailyTasks)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    route.isDailyTasks
                                        ? 'Saves to ${route.folder ?? 'Daily Notes'}'
                                        : route.isCanvas
                                            ? 'Saves to ${route.folder}/ as .canvas'
                                            : 'Saves to ${route.folder}/',
                                    style: textTheme.labelMedium?.copyWith(
                                      color: MemoryHues.inkMuted,
                                    ),
                                  ),
                                ),
                              if (!_isDaily && _previousCandidate != null)
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    'Link from last page',
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
                              if (_isCanvas) ...[
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    'Dim photo under nodes',
                                    style: textTheme.titleMedium,
                                  ),
                                  value: _inkGhost,
                                  activeThumbColor: MemoryHues.accent,
                                  activeTrackColor: MemoryHues.accentSoft,
                                  onChanged: widget.committing
                                      ? null
                                      : (v) => setState(() => _inkGhost = v),
                                ),
                                const SizedBox(height: 4),
                                for (var i = 0; i < _regions.length; i++)
                                  _NodeEditTile(
                                    index: i,
                                    controller: _nodeControllers[i],
                                    focused: _focusedNode == i,
                                    enabled: !widget.committing,
                                    onChanged: (t) => _syncNodeText(i, t),
                                    onFocus: () => _focusNode(i),
                                    onRemove: () => _removeNode(i),
                                  ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: widget.committing ||
                                            _regions.length >= 12
                                        ? null
                                        : _addNode,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add node'),
                                  ),
                                ),
                              ],
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: TextField(
                                  controller: _titleController,
                                  enabled:
                                      !widget.committing && !_isDaily,
                                  style: textTheme.titleMedium,
                                  decoration: const InputDecoration(
                                    labelText: 'Title',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              if (!_isCanvas)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: TextField(
                                    controller: _bodyController,
                                    enabled: !widget.committing,
                                    minLines: _isDaily ? 2 : 4,
                                    maxLines: 8,
                                    style: textTheme.bodyLarge,
                                    decoration: InputDecoration(
                                      labelText: _isDaily
                                          ? 'Tasks (one per line)'
                                          : 'Note',
                                      border: const OutlineInputBorder(),
                                      alignLabelWithHint: true,
                                    ),
                                  ),
                                ),
                              if (_links.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Links: ${_links.map((l) => l.displayTitle ?? l.targetPath).join(', ')}',
                                    style: textTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          child: Row(
                            children: [
                              TextButton(
                                onPressed: widget.committing
                                    ? null
                                    : widget.onCancel,
                                child: const Text('Cancel'),
                              ),
                              if (!_isDaily)
                                TextButton(
                                  onPressed: widget.committing
                                      ? null
                                      : _openLinks,
                                  child: Text(
                                    'Link${_links.isEmpty ? '' : ' (${_links.length})'}',
                                  ),
                                ),
                              const Spacer(),
                              FilledButton(
                                onPressed:
                                    widget.committing ? null : _commit,
                                child: widget.committing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Save'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Large node editor in the confirm sheet — not overlaid on the photo.
class _NodeEditTile extends StatelessWidget {
  const _NodeEditTile({
    required this.index,
    required this.controller,
    required this.focused,
    required this.enabled,
    required this.onChanged,
    required this.onFocus,
    required this.onRemove,
  });

  final int index;
  final TextEditingController controller;
  final bool focused;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onFocus;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: focused ? MemoryHues.accentSoft : MemoryHues.paper,
          border: Border.all(
            color: focused ? MemoryHues.accent : MemoryHues.rule,
            width: focused ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${index + 1}',
                  style: textTheme.labelLarge?.copyWith(
                    color: MemoryHues.inkMuted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 3,
                  style: textTheme.titleMedium?.copyWith(color: MemoryHues.ink),
                  onTap: onFocus,
                  onChanged: onChanged,
                  decoration: const InputDecoration(
                    hintText: 'Node words',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove node',
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.close, size: 20),
                color: MemoryHues.inkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tap markers on the ghost photo — open the matching sheet field.
class _MindmapMarkerLayer extends StatelessWidget {
  const _MindmapMarkerLayer({
    required this.regions,
    required this.parentSize,
    required this.focusedIndex,
    required this.enabled,
    required this.onTap,
  });

  final List<OcrRegion> regions;
  final Size parentSize;
  final int? focusedIndex;
  final bool enabled;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var i = 0; i < regions.length; i++)
          _MindmapMarker(
            key: ValueKey(regions[i].id),
            region: regions[i],
            index: i,
            parentSize: parentSize,
            focused: focusedIndex == i,
            enabled: enabled,
            onTap: () => onTap(i),
          ),
      ],
    );
  }
}

class _MindmapMarker extends StatelessWidget {
  const _MindmapMarker({
    super.key,
    required this.region,
    required this.index,
    required this.parentSize,
    required this.focused,
    required this.enabled,
    required this.onTap,
  });

  final OcrRegion region;
  final int index;
  final Size parentSize;
  final bool focused;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bbox = region.bbox;
    final left =
        (bbox != null && bbox.length >= 4 ? bbox[0] : 0.12) * parentSize.width;
    final top = (bbox != null && bbox.length >= 4
            ? bbox[1]
            : 0.18 + index * 0.14) *
        parentSize.height;
    final label = region.text.trim().isEmpty ? 'Node ${index + 1}' : region.text;
    final short =
        label.length <= 28 ? label : '${label.substring(0, 26)}…';

    return Positioned(
      left: left.clamp(0, parentSize.width - 72),
      top: top.clamp(0, parentSize.height - 40),
      child: Material(
        color: focused
            ? MemoryHues.accent
            : MemoryHues.paperElevated.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        elevation: focused ? 2 : 0,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              short,
              style: textTheme.labelLarge?.copyWith(
                color: focused ? MemoryHues.paperElevated : MemoryHues.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
