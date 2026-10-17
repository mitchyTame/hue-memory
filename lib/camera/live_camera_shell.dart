import 'package:flutter/material.dart';

import '../symbols/default_packs.dart';
import '../symbols/symbol_models.dart';
import '../theme/memory_hues.dart';
import 'camera_capture.dart';
import 'camera_session.dart';
import 'symbol_box.dart';

/// Full-bleed live viewfinder — movable symbol box + chips + teal shutter.
class LiveCameraShell extends StatefulWidget {
  const LiveCameraShell({
    super.key,
    this.sessionFactory,
    this.pack = DefaultPacks.zettelkastenInk,
    this.initialSymbolId = '',
    this.initialSymbolBox = SymbolBoxRect.defaultMeta,
  });

  /// Defaults to [PluginCameraSession]. Inject [FakeCameraSession] in tests.
  final CameraSessionFactory? sessionFactory;
  final SymbolPack pack;
  final String initialSymbolId;
  final SymbolBoxRect initialSymbolBox;

  @override
  State<LiveCameraShell> createState() => _LiveCameraShellState();
}

class _LiveCameraShellState extends State<LiveCameraShell> {
  CameraSession? _session;
  Object? _error;
  bool _snapping = false;
  late String _symbolId;
  late SymbolBoxRect _box;

  @override
  void initState() {
    super.initState();
    _symbolId = widget.initialSymbolId;
    _box = widget.initialSymbolBox.clamped();
    _open();
  }

  Future<void> _open() async {
    final factory =
        widget.sessionFactory ?? () async => PluginCameraSession();
    try {
      final session = await factory();
      await session.initialize();
      if (!mounted) {
        await session.dispose();
        return;
      }
      setState(() => _session = session);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  Future<void> _shutter() async {
    final session = _session;
    if (session == null || !session.isInitialized || _snapping) return;
    setState(() => _snapping = true);
    try {
      final shot = await session.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop<CaptureResult>(
        CaptureResult(
          imageBytes: shot.imageBytes,
          capturedAt: shot.capturedAt,
          imageExtension: shot.imageExtension,
          symbolId: _symbolId,
          symbolBox: _box.clamped(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _snapping = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Capture failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  void _cancel() {
    Navigator.of(context).pop<CaptureResult>();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final session = _session;
    final error = _error;
    final symbols = widget.pack.symbols;

    return Scaffold(
      backgroundColor: MemoryHues.ink,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final short = constraints.maxHeight < 420;
            final shutterSize = short ? 56.0 : 72.0;
            final bottomPad = short ? 8.0 : 16.0;
            final topPad = short ? 2.0 : 4.0;

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: topPad),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Cancel',
                        onPressed: _snapping ? null : _cancel,
                        icon: const Icon(
                          Icons.close,
                          color: MemoryHues.paperElevated,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Frame the page · drag box over ink glyph',
                          textAlign: TextAlign.center,
                          style: textTheme.labelLarge?.copyWith(
                            color: MemoryHues.paperElevated,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                if (symbols.isNotEmpty)
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: symbols.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final s = symbols[index];
                        final selected = s.id == _symbolId;
                        return ChoiceChip(
                          label: Text(
                            s.primaryGlyph,
                            style: TextStyle(
                              color: selected
                                  ? MemoryHues.ink
                                  : MemoryHues.paperElevated,
                            ),
                          ),
                          selected: selected,
                          onSelected: _snapping
                              ? null
                              : (_) => setState(() {
                                    _symbolId = selected ? '' : s.id;
                                  }),
                          selectedColor: MemoryHues.accentSoft,
                          backgroundColor: MemoryHues.ink.withValues(alpha: 0.4),
                          side: BorderSide(
                            color: selected
                                ? MemoryHues.accent
                                : MemoryHues.paperElevated.withValues(
                                    alpha: 0.4,
                                  ),
                          ),
                          visualDensity: VisualDensity.compact,
                        );
                      },
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, previewConstraints) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          if (error != null)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Camera unavailable:\n$error',
                                  textAlign: TextAlign.center,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: MemoryHues.paperElevated,
                                  ),
                                ),
                              ),
                            )
                          else if (session == null || !session.isInitialized)
                            const Center(
                              child: CircularProgressIndicator(
                                color: MemoryHues.accent,
                              ),
                            )
                          else
                            Positioned.fill(child: session.buildPreview()),
                          if (error == null)
                            _MovableSymbolBox(
                              box: _box,
                              parentSize: Size(
                                previewConstraints.maxWidth,
                                previewConstraints.maxHeight,
                              ),
                              enabled: !_snapping,
                              onChanged: (next) =>
                                  setState(() => _box = next.clamped()),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, short ? 8 : 12, 24, bottomPad),
                  child: Semantics(
                    button: true,
                    label: 'Shutter',
                    child: GestureDetector(
                      onTap: (session == null ||
                              !session.isInitialized ||
                              _snapping ||
                              error != null)
                          ? null
                          : _shutter,
                      child: Container(
                        width: shutterSize,
                        height: shutterSize,
                        decoration: BoxDecoration(
                          color: _snapping
                              ? MemoryHues.accent.withValues(alpha: 0.5)
                              : MemoryHues.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: MemoryHues.paperElevated,
                            width: 3,
                          ),
                        ),
                        child: _snapping
                            ? Padding(
                                padding: EdgeInsets.all(shutterSize * 0.28),
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: MemoryHues.paperElevated,
                                ),
                              )
                            : null,
                      ),
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

/// Drag body to move; drag bottom-right handle to resize.
class _MovableSymbolBox extends StatelessWidget {
  const _MovableSymbolBox({
    required this.box,
    required this.parentSize,
    required this.enabled,
    required this.onChanged,
  });

  final SymbolBoxRect box;
  final Size parentSize;
  final bool enabled;
  final ValueChanged<SymbolBoxRect> onChanged;

  @override
  Widget build(BuildContext context) {
    if (parentSize.width <= 0 || parentSize.height <= 0) {
      return const SizedBox.shrink();
    }
    final left = box.left * parentSize.width;
    final top = box.top * parentSize.height;
    final width = box.width * parentSize.width;
    final height = box.height * parentSize.height;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: GestureDetector(
            onPanUpdate: enabled
                ? (d) {
                    onChanged(
                      box.copyWith(
                        left: box.left + d.delta.dx / parentSize.width,
                        top: box.top + d.delta.dy / parentSize.height,
                      ),
                    );
                  }
                : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: MemoryHues.recall.withValues(alpha: 0.9),
                  width: 2,
                ),
                color: MemoryHues.recall.withValues(alpha: 0.12),
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    'glyph',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: MemoryHues.paperElevated.withValues(alpha: 0.85),
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: left + width - 22,
          top: top + height - 22,
          width: 28,
          height: 28,
          child: GestureDetector(
            onPanUpdate: enabled
                ? (d) {
                    onChanged(
                      box.copyWith(
                        width: box.width + d.delta.dx / parentSize.width,
                        height: box.height + d.delta.dy / parentSize.height,
                      ),
                    );
                  }
                : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: MemoryHues.accent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: MemoryHues.paperElevated),
              ),
              child: const Icon(
                Icons.open_in_full,
                size: 16,
                color: MemoryHues.paperElevated,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
