import 'package:flutter/material.dart';

import '../promote/own_words_gate.dart';
import '../promote/promote_service.dart';
import '../theme/memory_hues.dart';

/// Weekly ∼ → ◇ promote ritual — recall amber, own-words gate.
class PromoteShell extends StatefulWidget {
  const PromoteShell({
    super.key,
    required this.candidates,
    this.busy = false,
    this.onBack,
    this.onPromote,
  });

  final List<PromoteCandidate> candidates;
  final bool busy;
  final VoidCallback? onBack;
  final Future<void> Function({
    required PromoteCandidate source,
    required String title,
    required String ownWords,
    required bool keepOcrShallow,
  })? onPromote;

  @override
  State<PromoteShell> createState() => _PromoteShellState();
}

class _PromoteShellState extends State<PromoteShell> {
  PromoteCandidate? _selected;
  late final TextEditingController _title;
  late final TextEditingController _ownWords;
  bool _keepOcr = false;
  String? _gateError;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _ownWords = TextEditingController();
    if (widget.candidates.isNotEmpty) {
      _select(widget.candidates.first);
    }
  }

  @override
  void didUpdateWidget(covariant PromoteShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.candidates != oldWidget.candidates) {
      if (widget.candidates.isEmpty) {
        setState(() => _selected = null);
      } else if (_selected == null ||
          !widget.candidates.any((c) => c.path == _selected!.path)) {
        _select(widget.candidates.first);
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _ownWords.dispose();
    super.dispose();
  }

  void _select(PromoteCandidate c) {
    setState(() {
      _selected = c;
      _title.text = c.title;
      _ownWords.text = '';
      _keepOcr = false;
      _gateError = null;
    });
  }

  Future<void> _submit() async {
    final source = _selected;
    final callback = widget.onPromote;
    if (source == null || callback == null || widget.busy) return;

    final err = OwnWordsGate.validate(
      ownWords: _ownWords.text,
      sourceBody: source.body,
      keepOcrShallow: _keepOcr,
    );
    if (err != null) {
      setState(() => _gateError = err);
      return;
    }
    setState(() => _gateError = null);
    await callback(
      source: source,
      title: _title.text.trim().isEmpty ? source.title : _title.text.trim(),
      ownWords: _ownWords.text,
      keepOcrShallow: _keepOcr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final selected = _selected;

    return Scaffold(
      backgroundColor: MemoryHues.paper,
      appBar: AppBar(
        title: const Text('Promote ritual'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.busy ? null : widget.onBack,
        ),
        backgroundColor: MemoryHues.recallSoft,
        foregroundColor: MemoryHues.ink,
      ),
      body: widget.candidates.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No fleeting notes waiting.\n'
                  'Capture ∼ waves first, then return weekly.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    color: MemoryHues.inkMuted,
                  ),
                ),
              ),
            )
          : Column(
              children: [
                SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    itemCount: widget.candidates.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final c = widget.candidates[i];
                      final on = selected?.path == c.path;
                      return ChoiceChip(
                        label: Text(c.title, overflow: TextOverflow.ellipsis),
                        selected: on,
                        onSelected: widget.busy
                            ? null
                            : (_) => _select(c),
                        selectedColor: MemoryHues.recallSoft,
                        side: BorderSide(
                          color: on ? MemoryHues.recall : MemoryHues.rule,
                        ),
                      );
                    },
                  ),
                ),
                if (selected != null)
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        Text(
                          '∼  →  ◇',
                          style: textTheme.titleLarge?.copyWith(
                            color: MemoryHues.recall,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Rewrite in your own words. The paper photo stays linked.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: MemoryHues.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text('From fleeting', style: textTheme.labelMedium),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: MemoryHues.rule),
                            borderRadius: BorderRadius.circular(8),
                            color: MemoryHues.paperElevated,
                          ),
                          child: Text(
                            selected.body.isEmpty
                                ? '(empty body)'
                                : selected.body,
                            style: textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _title,
                          enabled: !widget.busy,
                          decoration: const InputDecoration(
                            labelText: 'Permanent title',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _ownWords,
                          enabled: !widget.busy && !_keepOcr,
                          minLines: 4,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: 'Own words',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          onChanged: (_) {
                            if (_gateError != null) {
                              setState(() => _gateError = null);
                            }
                          },
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Keep OCR (shallow)',
                            style: textTheme.bodyMedium,
                          ),
                          subtitle: Text(
                            'Skip rewrite — tags permanent as shallow',
                            style: textTheme.bodySmall?.copyWith(
                              color: MemoryHues.inkMuted,
                            ),
                          ),
                          value: _keepOcr,
                          activeColor: MemoryHues.recall,
                          onChanged: widget.busy
                              ? null
                              : (v) => setState(() {
                                    _keepOcr = v ?? false;
                                    _gateError = null;
                                  }),
                        ),
                        if (_gateError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _gateError!,
                              style: textTheme.bodySmall?.copyWith(
                                color: MemoryHues.danger,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: widget.busy ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: MemoryHues.recall,
                            foregroundColor: MemoryHues.ink,
                          ),
                          child: widget.busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Promote to permanent'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
