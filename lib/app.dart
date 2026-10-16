import 'package:flutter/material.dart';

import 'camera/camera_capture.dart';
import 'camera/sample_capture.dart';
import 'capture/page_id.dart';
import 'capture/pending_capture.dart';
import 'ocr/mock_ocr_client.dart';
import 'ocr/ocr_client.dart';
import 'theme/app_theme.dart';
import 'theme/memory_hues.dart';
import 'ui/capture_shell.dart';
import 'ui/confirm_shell.dart';
import 'vault/commit_pipeline.dart';
import 'vault/fake_vault_fs.dart';
import 'vault/vault_fs.dart';
import 'writers/link_writer.dart';

/// Root app. Slice 2 uses [FakeVaultFs] + sample capture (no SAF / camera yet).
class HueMemoryApp extends StatelessWidget {
  const HueMemoryApp({
    super.key,
    VaultFs? vault,
    CameraCapture? camera,
    OcrClient? ocr,
    PageId? pageIds,
  })  : _vault = vault,
        _camera = camera,
        _ocr = ocr,
        _pageIds = pageIds;

  final VaultFs? _vault;
  final CameraCapture? _camera;
  final OcrClient? _ocr;
  final PageId? _pageIds;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'hue-memory',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: _HomeNavigator(
        vault: _vault ?? FakeVaultFs(),
        camera: _camera ?? SampleAssetCapture(),
        ocr: _ocr ?? MockOcrClient(),
        pageIds: _pageIds ?? PageId(),
      ),
    );
  }
}

class _HomeNavigator extends StatefulWidget {
  const _HomeNavigator({
    required this.vault,
    required this.camera,
    required this.ocr,
    required this.pageIds,
  });

  final VaultFs vault;
  final CameraCapture camera;
  final OcrClient ocr;
  final PageId pageIds;

  @override
  State<_HomeNavigator> createState() => _HomeNavigatorState();
}

class _HomeNavigatorState extends State<_HomeNavigator> {
  late final CommitPipeline _pipeline =
      CommitPipeline(vault: widget.vault);

  PendingCapture? _pending;
  bool _busy = false;
  bool _committing = false;
  String? _lastCommitPath;
  final List<LinkPick> _recentPages = [
    const LinkPick(
      targetPath: 'permanent/seed-attention',
      displayTitle: 'Attention is a muscle (seed)',
    ),
  ];

  Future<void> _shutter() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final shot = await widget.camera.capturePage();
      final meaning = await widget.ocr.extractMeaning(shot.imageBytes);
      final pageId = widget.pageIds.generate(at: shot.capturedAt.toLocal());
      final pending = PendingCapture(
        pageId: pageId,
        imageBytes: shot.imageBytes,
        capturedAt: shot.capturedAt,
        meaning: meaning,
        imageExtension: 'png',
      );
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Capture failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  Future<void> _commit({
    required String symbolId,
    required String title,
    required String noteBody,
    required List<LinkPick> links,
  }) async {
    final pending = _pending;
    if (pending == null || _committing) return;
    setState(() => _committing = true);
    try {
      final result = await _pipeline.commit(
        CommitInput(
          capture: pending,
          symbolId: symbolId,
          title: title,
          noteBody: noteBody,
          links: links,
          taskLines: symbolId == 'daily-tasks'
              ? noteBody
                  .split('\n')
                  .map((l) => l.trim())
                  .where((l) => l.isNotEmpty)
                  .toList()
              : null,
        ),
      );

      final primary = result.primaryPath;
      if (result.notePath != null) {
        _recentPages.insert(
          0,
          LinkPick(
            targetPath: result.notePath!,
            displayTitle: title,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _pending = null;
        _committing = false;
        _lastCommitPath = primary;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wrote $primary'),
          backgroundColor: MemoryHues.accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _committing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Commit failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    if (pending != null) {
      return ConfirmShell(
        capture: pending,
        linkCandidates: List.unmodifiable(_recentPages),
        committing: _committing,
        onCancel: _committing
            ? null
            : () => setState(() => _pending = null),
        onCommit: _commit,
      );
    }
    return CaptureShell(
      busy: _busy,
      lastCommitPath: _lastCommitPath,
      onShutter: _shutter,
    );
  }
}
