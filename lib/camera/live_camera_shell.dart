import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../symbols/default_packs.dart';
import '../symbols/symbol_models.dart';
import '../theme/hue_atmosphere.dart';
import '../theme/memory_hues.dart';
import 'camera_capture.dart';
import 'camera_session.dart';
import 'symbol_box.dart';

/// Live viewfinder — letterboxed preview; chrome overlays, never squeezes aspect.
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

  bool get _canShoot =>
      _session != null &&
      _session!.isInitialized &&
      !_snapping &&
      _error == null;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final session = _session;
    final error = _error;
    final symbols = widget.pack.symbols;
    final media = MediaQuery.of(context);
    final landscape = media.size.width > media.size.height;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: MemoryHues.fieldDeep,
        systemNavigationBarColor: MemoryHues.fieldDeep,
      ),
      child: Scaffold(
        backgroundColor: MemoryHues.fieldDeep,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final maxH = constraints.maxHeight;
            final ar = session?.previewAspectRatio ?? 3 / 4;

            // Natural letterbox inside the shared atmosphere field.
            var previewW = maxW;
            var previewH = previewW / ar;
            if (previewH > maxH) {
              previewH = maxH;
              previewW = previewH * ar;
            }

            final shutterSize = landscape
                ? (maxH < 360 ? 56.0 : 64.0)
                : (maxH < 640 ? 64.0 : 72.0);
            // Soft scrims for control readability — same ink family, not ribbons.
            final railH = landscape
                ? (maxH * 0.12).clamp(28.0, 48.0)
                : (maxH * 0.1).clamp(40.0, 72.0);

            return Stack(
              fit: StackFit.expand,
              children: [
                const HueAtmosphere(),
                Center(
                  child: SizedBox(
                    width: previewW,
                    height: previewH,
                    child: Stack(
                      fit: StackFit.expand,
                      clipBehavior: Clip.hardEdge,
                      children: [
                        if (error != null)
                          ColoredBox(
                            color: MemoryHues.field,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Camera unavailable\n$error',
                                  textAlign: TextAlign.center,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: MemoryHues.paperElevated,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else if (session == null || !session.isInitialized)
                          const ColoredBox(
                            color: MemoryHues.field,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: MemoryHues.accentSoft,
                                strokeWidth: 2.5,
                              ),
                            ),
                          )
                        else
                          session.buildPreview(),
                        if (error == null)
                          _MovableSymbolBox(
                            box: _box,
                            parentSize: Size(previewW, previewH),
                            enabled: !_snapping,
                            compact: landscape,
                            onChanged: (next) =>
                                setState(() => _box = next.clamped()),
                          ),
                      ],
                    ),
                  ),
                ),

                // Soft top wash (ink → clear) — same family as home.
                IgnorePointer(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      height: railH + media.padding.top,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            MemoryHues.fieldDeep,
                            MemoryHues.fieldDeep.withValues(alpha: 0.55),
                            MemoryHues.fieldDeep.withValues(alpha: 0),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                // Soft bottom wash — ink/teal, never mustard→copper.
                IgnorePointer(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: railH + media.padding.bottom,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            MemoryHues.fieldTeal,
                            MemoryHues.field.withValues(alpha: 0.65),
                            MemoryHues.field.withValues(alpha: 0),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                SafeArea(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            4,
                            landscape ? 0 : 2,
                            4,
                            0,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: 'Cancel',
                                onPressed: _snapping ? null : _cancel,
                                style: IconButton.styleFrom(
                                  foregroundColor: MemoryHues.paperElevated,
                                  backgroundColor: MemoryHues.fieldLift
                                      .withValues(alpha: 0.72),
                                ),
                                icon: const Icon(Icons.close),
                              ),
                              Expanded(
                                child: Text(
                                  landscape
                                      ? 'Frame page · drag glyph box'
                                      : 'Frame the page · drag box over ink glyph',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelMedium?.copyWith(
                                    color: MemoryHues.paperElevated
                                        .withValues(alpha: 0.9),
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 48),
                            ],
                          ),
                        ),
                      ),
                      if (symbols.isNotEmpty)
                        Positioned(
                          left: 12,
                          right: landscape ? shutterSize + 28 : 12,
                          top: 48,
                          height: 40,
                          child: _SymbolChipStrip(
                            symbols: symbols,
                            selectedId: _symbolId,
                            enabled: !_snapping,
                            onSelected: (id) => setState(() {
                              _symbolId = id;
                            }),
                          ),
                        ),
                      Align(
                        alignment: landscape
                            ? Alignment.centerRight
                            : Alignment.bottomCenter,
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: landscape ? 12 : 0,
                            bottom: landscape ? 0 : 8,
                          ),
                          child: _ShutterButton(
                            size: shutterSize,
                            busy: _snapping,
                            enabled: _canShoot,
                            onTap: _shutter,
                          ),
                        ),
                      ),
                    ],
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

/// Compact glyph chips — selected = accent fill, not Material ChoiceChip bulk.
class _SymbolChipStrip extends StatelessWidget {
  const _SymbolChipStrip({
    required this.symbols,
    required this.selectedId,
    required this.enabled,
    required this.onSelected,
  });

  final List<PackSymbol> symbols;
  final String selectedId;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: symbols.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final s = symbols[index];
          final selected = s.id == selectedId;
          return Tooltip(
            message: s.id,
            child: Material(
              color: selected
                  ? MemoryHues.accent.withValues(alpha: 0.92)
                  : MemoryHues.fieldLift.withValues(alpha: 0.82),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: selected
                      ? MemoryHues.accentSoft.withValues(alpha: 0.7)
                      : MemoryHues.paperElevated.withValues(alpha: 0.22),
                ),
              ),
              child: InkWell(
                onTap: !enabled
                    ? null
                    : () => onSelected(selected ? '' : s.id),
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: Text(
                      s.primaryGlyph,
                      style: TextStyle(
                        fontSize: 18,
                        height: 1,
                        color: selected
                            ? MemoryHues.paperElevated
                            : MemoryHues.paperElevated.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.size,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final double size;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Shutter',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: busy
                ? MemoryHues.accent.withValues(alpha: 0.55)
                : enabled
                    ? MemoryHues.accent
                    : MemoryHues.inkMuted,
            shape: BoxShape.circle,
            border: Border.all(
              color: MemoryHues.paperElevated,
              width: 3,
            ),
          ),
          child: busy
              ? Padding(
                  padding: EdgeInsets.all(size * 0.28),
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MemoryHues.paperElevated,
                  ),
                )
              : Center(
                  child: Container(
                    width: size * 0.42,
                    height: size * 0.42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: MemoryHues.paperElevated.withValues(
                        alpha: enabled ? 0.95 : 0.4,
                      ),
                    ),
                  ),
                ),
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
    this.compact = false,
  });

  final SymbolBoxRect box;
  final Size parentSize;
  final bool enabled;
  final bool compact;
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
    final handle = compact ? 24.0 : 28.0;

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
                  color: MemoryHues.recall.withValues(alpha: 0.75),
                  width: 1.5,
                ),
                color: MemoryHues.recall.withValues(alpha: 0.1),
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(5, 3, 5, 2),
                  child: Text(
                    'glyph',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: MemoryHues.paperElevated
                              .withValues(alpha: 0.9),
                          fontSize: compact ? 10 : 11,
                          height: 1.1,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: left + width - handle + 4,
          top: top + height - handle + 4,
          width: handle,
          height: handle,
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
                border: Border.all(color: MemoryHues.paperElevated, width: 1.5),
              ),
              child: Icon(
                Icons.open_in_full,
                size: compact ? 14 : 16,
                color: MemoryHues.paperElevated,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
