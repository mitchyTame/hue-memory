import 'package:material_ui/material_ui.dart';

import '../capture/pending_capture.dart';
import '../ocr/ocr_client.dart';
import '../symbols/default_packs.dart';
import '../symbols/symbol_models.dart';
import '../symbols/symbol_router.dart';
import '../theme/hue_atmosphere.dart';
import '../todoist/daily_todoist_parser.dart';
import '../todoist/daily_todoist_plan.dart';
import '../todoist/due_phrase.dart';
import '../theme/memory_hues.dart';
import '../vault/daily_note_path.dart';
import '../writers/link_writer.dart';
import 'capture_region_overlay.dart';

typedef ConfirmCommitCallback = Future<void> Function({
  required String symbolId,
  required String title,
  required String noteBody,
  required List<LinkPick> links,
  bool inkGhost,
  List<OcrRegion>? regions,
});

/// Sends a reviewed · daily checklist (title is the ISO day).
typedef ConfirmTodoistSendCallback =
    Future<void> Function({
      required String title,
      required String noteBody,
      required List<OcrRegion> regions,
      required DailyTodoistPlan plan,
    });

/// Matches a freshly planned checklist against earlier captures' Todoist
/// tasks (the ledger), so a re-captured page shows "update" instead of "new".
typedef ConfirmTodoistLinker =
    Future<DailyTodoistPlan> Function(DailyTodoistPlan plan, String pageId);

/// Confirm-on-photo — photo hero, symbol chips, edits, Commit.
///
/// - **△ / visual:** clean photo (no text overlays); labels edited in the
///   sheet list only. Add / remove nodes there.
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
    this.todoistPlanner,
    this.onSendTodoist,
    this.todoistLinker,
  });

  final PendingCapture capture;
  final SymbolPack pack;
  final List<LinkPick> linkCandidates;
  final ConfirmCommitCallback? onCommit;
  final VoidCallback? onCancel;
  final bool committing;

  /// When both are set, · daily pages get a review checklist before anything
  /// is sent to Todoist; otherwise Save commits directly as before.
  final DailyTodoistPlanner? todoistPlanner;
  final ConfirmTodoistSendCallback? onSendTodoist;

  /// Optional: recognise a re-captured page before the checklist is shown.
  final ConfirmTodoistLinker? todoistLinker;

  @override
  State<ConfirmShell> createState() => _ConfirmShellState();
}

class _ConfirmShellState extends State<ConfirmShell> {
  late String _selectedId;
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final SymbolRouter _router;
  bool _inkGhost = true;
  late List<OcrRegion> _regions;
  late List<TextEditingController> _nodeControllers;
  int? _focusedNode;

  DailyTodoistPlan? _plan;
  bool _linking = false;
  final List<TextEditingController> _taskControllers = [];
  final List<TextEditingController> _doneControllers = [];

  bool get _reviewEnabled =>
      widget.todoistPlanner != null && widget.onSendTodoist != null;
  bool get _reviewing => _isDaily && _reviewEnabled && _plan != null;

  @override
  void initState() {
    super.initState();
    _router = SymbolRouter(pack: widget.pack);
    final routed = widget.capture.symbolId.isNotEmpty
        ? _router.routeById(widget.capture.symbolId)
        : _router.route(widget.capture.meaning.detectedGlyph);
    _selectedId = routed.symbol.id;
    _titleController = TextEditingController(
      text: _initialTitle(routed.isDailyTasks),
    );
    _bodyController = TextEditingController(text: widget.capture.noteBody);
    _regions = List<OcrRegion>.from(widget.capture.meaning.regions);
    _nodeControllers = [
      for (final r in _regions) TextEditingController(text: r.text),
    ];
  }

  String _captureDayIso() =>
      DailyNoteDate.formatIso(widget.capture.capturedAt.toLocal());

  /// Daily: title is the calendar day. Prefer hub node date, then capture day.
  String _initialTitle(bool daily) {
    final existing = widget.capture.title.trim();
    if (daily) {
      if (DailyNoteDate.tryParse(existing) != null) return existing;
      for (final r in widget.capture.meaning.regions) {
        final hub = DailyNoteDate.tryParse(r.text);
        if (hub != null) return DailyNoteDate.formatIso(hub);
      }
      return _captureDayIso();
    }
    return existing;
  }

  void _selectSymbol(String id) {
    final wasDaily = _isDaily;
    setState(() {
      _selectedId = id;
      _discardPlan();
      if (_isDaily && !wasDaily) {
        if (DailyNoteDate.tryParse(_titleController.text) == null) {
          _titleController.text = _captureDayIso();
        }
      }
    });
  }

  Future<void> _pickDailyDate() async {
    if (widget.committing || !_isDaily) return;
    final parsed = DailyNoteDate.tryParse(_titleController.text);
    final initial = parsed ?? widget.capture.capturedAt.toLocal();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _titleController.text = DailyNoteDate.formatIso(picked);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    for (final c in _nodeControllers) {
      c.dispose();
    }
    _discardPlan();
    super.dispose();
  }

  bool get _isDaily => _router.routeById(_selectedId).isDailyTasks;
  bool get _isCanvas => _router.routeById(_selectedId).isCanvas;

  /// · daily mindmaps and △ canvases both edit hub/spoke node labels.
  bool get _editMindmapNodes => _isCanvas || _isDaily;

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

  bool get _titleOk {
    final title = _titleController.text.trim();
    if (_isDaily) return DailyNoteDate.tryParse(title) != null;
    return title.isNotEmpty;
  }

  void _discardPlan() {
    for (final c in _taskControllers) {
      c.dispose();
    }
    for (final c in _doneControllers) {
      c.dispose();
    }
    _taskControllers.clear();
    _doneControllers.clear();
    _plan = null;
  }

  /// Validated commit title, or null (after telling the user why).
  String? _validatedTitle() {
    // Typed field only — never append OCR body, region ids, or draft hint.
    final title = _titleController.text.trim();
    if (_isDaily) {
      final day = DailyNoteDate.tryParse(title);
      if (day == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Set the daily date (YYYY-MM-DD or 19 Oct \'26)'),
            backgroundColor: MemoryHues.danger,
          ),
        );
        return null;
      }
      return DailyNoteDate.formatIso(day);
    }
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Type a title / filename before saving'),
          backgroundColor: MemoryHues.danger,
        ),
      );
      return null;
    }
    return title;
  }

  /// Pull latest text from controllers for mindmap nodes (△ and ·).
  void _syncRegionsFromControllers() {
    if (!_editMindmapNodes) return;
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

  /// · daily: mirror nodes into section markdown for fallback sync.
  String _noteBodyForCommit() {
    return _isDaily && _editMindmapNodes
        ? _regions
              .map((r) => r.text.trim())
              .where((t) => t.isNotEmpty)
              .join('\n')
        : _bodyController.text;
  }

  /// Daily step 1 → 2: parse the fixed nodes into an editable checklist.
  Future<void> _review() async {
    if (widget.committing || !_reviewEnabled) return;
    if (_validatedTitle() == null) return;
    _syncRegionsFromControllers();
    var plan = widget.todoistPlanner!.planFromMeaning(
      meaning: widget.capture.meaning,
      regions: List<OcrRegion>.from(_regions),
      markdown: _noteBodyForCommit(),
    );
    final linker = widget.todoistLinker;
    if (linker != null) {
      if (_linking) return;
      setState(() => _linking = true);
      try {
        plan = await linker(plan, widget.capture.pageId);
      } catch (_) {
        // Linking is a convenience; without it every item is simply "new".
      }
      if (!mounted) return;
      _linking = false;
    }
    setState(() {
      _discardPlan();
      _plan = plan;
      for (final t in plan.creates) {
        _taskControllers.add(TextEditingController(text: t.content));
      }
      for (final d in plan.done) {
        _doneControllers.add(TextEditingController(text: d.content));
      }
    });
  }

  void _backToNodes() {
    if (widget.committing) return;
    setState(_discardPlan);
  }

  /// Edit a task's due as words ("tomorrow 9am", "every Monday"); read
  /// against the page date. Empty removes it.
  Future<void> _editDue(int index) async {
    final plan = _plan;
    if (plan == null || widget.committing) return;
    final create = plan.creates[index].create;
    final result = await showDialog<String>(
      context: context,
      builder: (context) =>
          _DueDialog(initial: create.dueString ?? create.duePhrase ?? ''),
    );
    if (result == null || !mounted) return;
    final pageDate = _plan?.pageDate ?? DateTime.now();
    final due = DuePhrase.parsePhrase(result, pageDate: pageDate);
    _updatePlan((p) => p.setTaskDue(index, due));
  }

  void _updatePlan(DailyTodoistPlan Function(DailyTodoistPlan) edit) {
    final plan = _plan;
    if (plan == null) return;
    setState(() => _plan = edit(plan));
  }

  Future<void> _sendReviewed() async {
    final plan = _plan;
    final callback = widget.onSendTodoist;
    if (plan == null || callback == null || widget.committing) return;
    final commitTitle = _validatedTitle();
    if (commitTitle == null) return;
    await callback(
      title: commitTitle,
      noteBody: _noteBodyForCommit(),
      regions: List<OcrRegion>.from(_regions),
      plan: plan,
    );
  }

  Future<void> _commit() async {
    if (_isDaily && _reviewEnabled) {
      if (_reviewing) {
        await _sendReviewed();
      } else {
        await _review();
      }
      return;
    }
    final callback = widget.onCommit;
    if (callback == null || widget.committing) return;
    final commitTitle = _validatedTitle();
    if (commitTitle == null) return;
    _syncRegionsFromControllers();
    await callback(
      symbolId: _selectedId,
      title: commitTitle,
      noteBody: _noteBodyForCommit(),
      links: const [],
      inkGhost: _isCanvas ? _inkGhost : true,
      regions: _editMindmapNodes ? List<OcrRegion>.from(_regions) : null,
    );
  }

  String get _primaryLabel {
    if (_isDaily && _reviewEnabled) {
      final plan = _plan;
      if (plan == null) return _linking ? 'Checking Todoist…' : 'Review';
      final n = plan.includedCount;
      return n == 0 ? 'Send' : 'Send $n to Todoist';
    }
    return 'Save';
  }

  List<Widget> _reviewChildren(TextTheme textTheme) {
    final plan = _plan!;
    final enabled = !widget.committing;
    final labelOnly = plan.labelOnlySections;
    return [
      Text('Review Todoist tasks', style: textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        'Nothing has been sent yet. Untick to skip, tap text to edit, '
        'pick a priority. Skipping a task also skips its subtasks.',
        style: textTheme.bodySmall?.copyWith(color: MemoryHues.inkMuted),
      ),
      if (plan.hasLinks) ...[
        const SizedBox(height: 8),
        Container(
          key: const ValueKey('plan-linked-banner'),
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: MemoryHues.accentSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${plan.linkedByPageId ? 'This page was already sent' : plan.hasLinkedPage ? 'Looks like a re-capture of an earlier page' : 'Some items are already in Todoist'}: '
            '${plan.updateCount} update · ${plan.newCount} new'
            '${plan.completeCount > 0 ? ' · ${plan.completeCount} to complete' : ''}. '
            'Updates change the existing Todoist task instead of adding a '
            'copy; tap a badge to switch.',
            style: textTheme.bodySmall,
          ),
        ),
      ] else if (plan.rememberedCount != null && plan.creates.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'No earlier copies found (checked ${plan.rememberedCount} '
            'remembered task${plan.rememberedCount == 1 ? '' : 's'}'
            '${plan.liveChecked ? ' and your open Todoist tasks' : ''}) — '
            'everything below is new.',
            key: const ValueKey('plan-link-checked'),
            style: textTheme.labelSmall?.copyWith(color: MemoryHues.inkMuted),
          ),
        ),
      const SizedBox(height: 12),
      if (!plan.hasItems)
        Text(
          'No tasks found on this page. Go back and check the date hub, '
          'branches and leaves.',
          style: textTheme.bodyMedium,
        ),
      for (var i = 0; i < plan.creates.length; i++)
        _PlanTaskTile(
          key: ValueKey(plan.creates[i].key),
          task: plan.creates[i],
          depth: plan.depthOf(i),
          controller: _taskControllers[i],
          enabled: enabled,
          onIncluded: (v) => _updatePlan((p) => p.setTaskIncluded(i, v)),
          onText: (t) => _updatePlan((p) => p.setTaskContent(i, t)),
          onPriority: (v) => _updatePlan((p) => p.setTaskPriority(i, v)),
          showLink: plan.hasLinks,
          onUpdate: (v) => _updatePlan((p) => p.setTaskUpdate(i, v)),
          onClearDue: () => _updatePlan((p) => p.clearTaskDue(i)),
          onEditDue: () => _editDue(i),
        ),
      if (plan.done.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Mark done in Todoist', style: textTheme.labelLarge),
        const SizedBox(height: 6),
        for (var i = 0; i < plan.done.length; i++)
          _PlanDoneTile(
            key: ValueKey(plan.done[i].key),
            item: plan.done[i],
            controller: _doneControllers[i],
            enabled: enabled,
            onIncluded: (v) => _updatePlan((p) => p.setDoneIncluded(i, v)),
            onText: (t) => _updatePlan((p) => p.setDoneContent(i, t)),
            liveChecked: plan.liveChecked,
          ),
      ],
      if (labelOnly.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Also creates label${labelOnly.length == 1 ? '' : 's'}: '
            '${labelOnly.join(', ')}',
            style: textTheme.labelMedium?.copyWith(color: MemoryHues.inkMuted),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final symbols = widget.pack.symbols;
    final route = _router.routeById(_selectedId);

    return HueFieldScaffold(
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
                        // Mindmap labels stay in the sheet list only.
                        // OCR region feedback is a transparent UI overlay —
                        // never burned into the vault photo.
                        return Opacity(
                          opacity: _isCanvas && _inkGhost ? 0.42 : 1,
                          // · daily keeps full photo opacity (Todoist, not canvas).
                          child: CaptureRegionOverlay(
                            imageBytes: widget.capture.imageBytes,
                            feedback: widget.capture.regionFeedback,
                            child: Image.memory(
                              widget.capture.imageBytes,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              width: photoConstraints.maxWidth,
                              height: photoConstraints.maxHeight,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Flexible(
                  flex: sheetFlex,
                  child: Material(
                    color: MemoryHues.paperElevated,
                    surfaceTintColor: Colors.transparent,
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
                            children: _reviewing
                                ? _reviewChildren(textTheme)
                                : [
                              Text(
                                _editMindmapNodes
                                    ? (_isDaily
                                        ? 'Fix daily mindmap'
                                        : 'Fix mindmap words')
                                    : 'Confirm',
                                style: textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isDaily
                                    ? 'Date hub → section branches → tasks. '
                                        'Links from a task become Todoist subtasks; '
                                        'extra links to the same node reuse that task.'
                                    : _isCanvas
                                        ? 'Vision is a draft — edit labels in the list '
                                            '(not on the photo). Title becomes the filename.'
                                        : 'Title becomes the filename. OCR text is saved as written.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: MemoryHues.inkMuted,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _titleController,
                                enabled: !widget.committing,
                                style: textTheme.titleMedium,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: _isDaily
                                      ? 'Daily date (YYYY-MM-DD)'
                                      : 'Title / filename (required)',
                                  hintText: _isDaily
                                      ? _captureDayIso()
                                      : (widget.capture.draftTitleSuggestion
                                              .isEmpty
                                          ? null
                                          : 'Draft: ${widget.capture.draftTitleSuggestion}'),
                                  border: const OutlineInputBorder(),
                                  errorText: _titleOk || widget.committing
                                      ? null
                                      : (_isDaily
                                          ? 'Valid date required'
                                          : 'Required before save'),
                                  suffixIcon: _isDaily && !widget.committing
                                      ? IconButton(
                                          tooltip: 'Pick date',
                                          icon: const Icon(Icons.calendar_today),
                                          onPressed: _pickDailyDate,
                                        )
                                      : null,
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
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    final s = symbols[index];
                                    final selected = s.id == _selectedId;
                                    return ChoiceChip(
                                      label: Text('${s.primaryGlyph} ${s.id}'),
                                      selected: selected,
                                      onSelected: widget.committing
                                          ? null
                                          : (_) => _selectSymbol(s.id),
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
                                        ? 'Syncs to Todoist Inbox (not Obsidian Daily)'
                                        : route.isCanvas
                                            ? 'Saves to ${route.folder}/ as .canvas'
                                            : 'Saves to ${route.folder}/',
                                    style: textTheme.labelMedium?.copyWith(
                                      color: MemoryHues.inkMuted,
                                    ),
                                  ),
                                ),
                              if (_editMindmapNodes) ...[
                                if (_isCanvas)
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
                                if (_isDaily)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      'Hub = date · branches = labels · leaves = tasks',
                                      style: textTheme.labelMedium?.copyWith(
                                        color: MemoryHues.inkMuted,
                                      ),
                                    ),
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
                              if (!_editMindmapNodes)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: TextField(
                                    controller: _bodyController,
                                    enabled: !widget.committing,
                                    minLines: 6,
                                    maxLines: null,
                                    style: textTheme.bodyLarge,
                                    decoration: const InputDecoration(
                                      labelText: 'Note (full OCR text)',
                                      border: OutlineInputBorder(),
                                      alignLabelWithHint: true,
                                    ),
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
                              if (_reviewing)
                                TextButton(
                                  onPressed:
                                      widget.committing ? null : _backToNodes,
                                  child: const Text('Edit nodes'),
                                ),
                              const Spacer(),
                              FilledButton(
                                onPressed: widget.committing ||
                                        _linking ||
                                        !_titleOk ||
                                        (_reviewing && !_plan!.hasWork)
                                    ? null
                                    : _commit,
                                child: widget.committing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(_primaryLabel),
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

/// Todoist UI names: P1 = urgent (API 4) … P4 = none.
const List<({String label, int? api})> _priorityChoices = [
  (label: 'P1', api: 4),
  (label: 'P2', api: 3),
  (label: 'P3', api: 2),
  (label: 'P4', api: null),
];

class _PlanTaskTile extends StatelessWidget {
  const _PlanTaskTile({
    super.key,
    required this.task,
    required this.depth,
    required this.controller,
    required this.enabled,
    required this.onIncluded,
    required this.onText,
    required this.onPriority,
    this.showLink = false,
    this.onUpdate,
    this.onClearDue,
    this.onEditDue,
  });

  final PlannedTask task;
  final int depth;
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<bool> onIncluded;
  final ValueChanged<String> onText;
  final ValueChanged<int?> onPriority;
  final bool showLink;
  final ValueChanged<bool>? onUpdate;
  final VoidCallback? onClearDue;
  final VoidCallback? onEditDue;

  static String? dueLabel(DailyTodoistCreate c) {
    final label = c.dueLabel;
    if (label == null) return null;
    return c.dueString != null ? label : 'due $label';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final included = task.included;
    final isSub = task.create.parentNodeId != null;
    return Padding(
      padding: EdgeInsets.only(bottom: 8, left: 20.0 * depth.clamp(0, 3)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: included ? MemoryHues.paper : MemoryHues.paperElevated,
          border: Border.all(color: MemoryHues.rule),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    key: const ValueKey('plan-include'),
                    value: included,
                    onChanged: enabled ? (v) => onIncluded(v ?? false) : null,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        key: const ValueKey('plan-text'),
                        controller: controller,
                        enabled: enabled && included,
                        minLines: 1,
                        maxLines: 3,
                        onChanged: onText,
                        style: textTheme.titleMedium?.copyWith(
                          color: included
                              ? MemoryHues.ink
                              : MemoryHues.inkMuted,
                          decoration: included
                              ? null
                              : TextDecoration.lineThrough,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'Task',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (showLink)
                      ActionChip(
                        key: const ValueKey('plan-link'),
                        label: Text(task.isUpdate ? 'update' : 'new'),
                        visualDensity: VisualDensity.compact,
                        onPressed: enabled &&
                                included &&
                                task.match != null &&
                                !task.match!.isGone
                            ? () => onUpdate?.call(!task.isUpdate)
                            : null,
                        backgroundColor: task.isUpdate
                            ? MemoryHues.accentSoft
                            : MemoryHues.paper,
                        side: BorderSide(
                          color: task.isUpdate
                              ? MemoryHues.accent
                              : MemoryHues.rule,
                        ),
                      ),
                    if (task.create.hasDue)
                      InputChip(
                        key: const ValueKey('plan-due'),
                        label: Text(dueLabel(task.create)!),
                        visualDensity: VisualDensity.compact,
                        onPressed: enabled && included ? onEditDue : null,
                        onDeleted: enabled && included ? onClearDue : null,
                        deleteButtonTooltipMessage: 'No due date',
                      )
                    else if (included)
                      ActionChip(
                        key: const ValueKey('plan-add-due'),
                        label: const Text('+ due'),
                        visualDensity: VisualDensity.compact,
                        onPressed: enabled ? onEditDue : null,
                      ),
                    if (isSub)
                      Text(
                        'subtask',
                        style: textTheme.labelSmall?.copyWith(
                          color: MemoryHues.inkMuted,
                        ),
                      )
                    else if (task.create.label.isNotEmpty)
                      Text(
                        '#${task.create.label}',
                        style: textTheme.labelSmall?.copyWith(
                          color: MemoryHues.inkMuted,
                        ),
                      ),
                    for (final c in _priorityChoices)
                      ChoiceChip(
                        key: ValueKey('plan-priority-${c.label}'),
                        label: Text(c.label),
                        visualDensity: VisualDensity.compact,
                        selected: task.priority == c.api,
                        onSelected: enabled && included
                            ? (_) => onPriority(c.api)
                            : null,
                        selectedColor: MemoryHues.accentSoft,
                        side: BorderSide(
                          color: task.priority == c.api
                              ? MemoryHues.accent
                              : MemoryHues.rule,
                        ),
                      ),
                  ],
                ),
              ),
              if (_remoteNote(task) case final note?)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: Text(
                    note,
                    key: const ValueKey('plan-remote'),
                    style: textTheme.labelSmall?.copyWith(
                      color: MemoryHues.inkMuted,
                    ),
                  ),
                ),
              if (task.isUpdate &&
                  task.match!.content.trim() != task.content.trim())
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: Text(
                    'was: ${task.match!.content}',
                    key: const ValueKey('plan-was'),
                    style: textTheme.labelSmall?.copyWith(
                      color: MemoryHues.inkMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// What Todoist already holds for a matched item.
  static String? _remoteNote(PlannedTask task) {
    final m = task.match;
    if (m == null) return null;
    if (m.isCompleted) {
      return task.included && task.useMatch
          ? 'Already completed in Todoist — sending reopens it'
          : 'Already completed in Todoist (tick to reopen it)';
    }
    if (m.isGone) {
      return task.included
          ? 'No longer in Todoist — sending creates it again'
          : 'No longer in Todoist (tick to create it again)';
    }
    return null;
  }
}

class _PlanDoneTile extends StatelessWidget {
  const _PlanDoneTile({
    super.key,
    required this.item,
    required this.controller,
    required this.enabled,
    required this.onIncluded,
    required this.onText,
    this.liveChecked = false,
  });

  final PlannedDone item;
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<bool> onIncluded;
  final ValueChanged<String> onText;
  final bool liveChecked;

  String? get _status {
    final m = item.match;
    if (m != null && m.isCompleted) return 'Already completed in Todoist';
    if (m != null && m.isGone) return 'No longer in Todoist';
    if (!item.included) return null;
    if (m != null) return 'Will complete: ${m.content}';
    return liveChecked
        ? 'No open Todoist task matches — will be listed as not found'
        : 'Will complete the matching Todoist task';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: item.included ? MemoryHues.paper : MemoryHues.paperElevated,
          border: Border.all(color: MemoryHues.rule),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: const ValueKey('plan-include'),
              value: item.included,
              onChanged: enabled && !item.alreadySettled
                  ? (v) => onIncluded(v ?? false)
                  : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const ValueKey('plan-text'),
                      controller: controller,
                      enabled: enabled && item.included,
                      minLines: 1,
                      maxLines: 3,
                      onChanged: onText,
                      style: textTheme.titleMedium?.copyWith(
                        color: item.included
                            ? MemoryHues.ink
                            : MemoryHues.inkMuted,
                        decoration: item.included
                            ? null
                            : TextDecoration.lineThrough,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: 'Done item',
                      ),
                    ),
                    if (_status case final status?)
                      Text(
                        status,
                        key: const ValueKey('plan-done-status'),
                        style: textTheme.labelSmall?.copyWith(
                          color: MemoryHues.inkMuted,
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

class _DueDialog extends StatefulWidget {
  const _DueDialog({required this.initial});

  final String initial;

  @override
  State<_DueDialog> createState() => _DueDialogState();
}

class _DueDialogState extends State<_DueDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Due date'),
      content: TextField(
        key: const ValueKey('plan-due-field'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'e.g. tomorrow 9am, Fri, 3 Dec, every Monday',
          helperText: 'Leave empty for no due date',
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('plan-due-save'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
