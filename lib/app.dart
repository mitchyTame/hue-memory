import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'camera/camera_capture.dart';
import 'camera/file_pick_capture.dart';
import 'camera/sample_capture.dart';
import 'capture/page_id.dart';
import 'capture/pending_capture.dart';
import 'ocr/configurable_ocr_client.dart';
import 'ocr/ocr_client.dart';
import 'ocr/ocr_settings.dart';
import 'settings/vault_settings_store.dart';
import 'theme/app_theme.dart';
import 'theme/memory_hues.dart';
import 'ui/capture_shell.dart';
import 'ui/confirm_shell.dart';
import 'ui/ocr_settings_shell.dart';
import 'ui/settings_hub_shell.dart';
import 'ui/vault_settings_shell.dart';
import 'vault/commit_pipeline.dart';
import 'vault/local_vault_fs.dart';
import 'vault/vault_fs.dart';
import 'writers/link_writer.dart';

enum _SettingsPane { hub, vault, ocr }

/// Root app. Slice 4: configurable Mistral OCR (mock default until consent).
class HueMemoryApp extends StatefulWidget {
  const HueMemoryApp({
    super.key,
    VaultFs? vault,
    CameraCapture? camera,
    OcrClient? ocr,
    PageId? pageIds,
    VaultSettingsStore? settings,
    OcrSettingsStore? ocrSettings,
  })  : _vault = vault,
        _camera = camera,
        _ocr = ocr,
        _pageIds = pageIds,
        _settings = settings,
        _ocrSettings = ocrSettings;

  final VaultFs? _vault;
  final CameraCapture? _camera;
  final OcrClient? _ocr;
  final PageId? _pageIds;
  final VaultSettingsStore? _settings;
  final OcrSettingsStore? _ocrSettings;

  @override
  State<HueMemoryApp> createState() => _HueMemoryAppState();
}

class _HueMemoryAppState extends State<HueMemoryApp> {
  late final VaultSettingsStore _vaultSettings =
      widget._settings ?? PrefsVaultSettingsStore();
  late final OcrSettingsStore _ocrSettings = widget._ocrSettings ??
      PrefsOcrSettingsStore(
        envApiKey: Platform.environment['MISTRAL_API_KEY'] ?? '',
      );
  late final CameraCapture _sampleCamera =
      widget._camera ?? SampleAssetCapture();
  late final FilePickCapture _filePickCamera = FilePickCapture();
  late final OcrClient _ocr = widget._ocr ??
      ConfigurableOcrClient(settings: _ocrSettings);
  late final PageId _pageIds = widget._pageIds ?? PageId();

  VaultFs? _vault;
  String _vaultLabel = 'Loading vault…';
  String _ocrModeLabel = 'OCR: mock';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _refreshOcrLabel();

    if (widget._vault != null) {
      setState(() {
        _vault = widget._vault;
        _vaultLabel = widget._vault is LocalVaultFs
            ? (widget._vault! as LocalVaultFs).rootPath
            : 'Injected vault';
        _ready = true;
      });
      return;
    }

    try {
      final saved = await _vaultSettings.readVaultRoot();
      Directory root;
      if (saved != null && saved.isNotEmpty && Directory(saved).existsSync()) {
        root = Directory(saved);
      } else {
        root = await defaultVaultDirectory();
        await _vaultSettings.writeVaultRoot(root.path);
      }
      final vault = LocalVaultFs(root);
      if (!mounted) return;
      setState(() {
        _vault = vault;
        _vaultLabel = vault.rootPath;
        _ready = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _vaultLabel = 'Vault error: $e';
        _ready = true;
      });
    }
  }

  Future<void> _refreshOcrLabel() async {
    final cfg = await _ocrSettings.read();
    if (!mounted) return;
    setState(() {
      _ocrModeLabel = cfg.shouldUseLive ? 'OCR: Mistral (live)' : 'OCR: mock';
    });
  }

  Future<void> _setVaultRoot(Directory root) async {
    final vault = LocalVaultFs(root);
    await _vaultSettings.writeVaultRoot(root.path);
    setState(() {
      _vault = vault;
      _vaultLabel = vault.rootPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'hue-memory',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: !_ready || _vault == null
          ? const Scaffold(
              backgroundColor: MemoryHues.paper,
              body: Center(child: CircularProgressIndicator()),
            )
          : _HomeNavigator(
              vault: _vault!,
              vaultLabel: _vaultLabel,
              ocrModeLabel: _ocrModeLabel,
              sampleCamera: _sampleCamera,
              filePickCamera: _filePickCamera,
              ocr: _ocr,
              ocrSettings: _ocrSettings,
              pageIds: _pageIds,
              onVaultRootChanged: _setVaultRoot,
              onUseDefaultVault: () async {
                final dir = await defaultVaultDirectory();
                await _setVaultRoot(dir);
              },
              onOcrSettingsChanged: _refreshOcrLabel,
            ),
    );
  }
}

/// App-documents `hue-memory-vault` — durable default for Linux demos.
Future<Directory> defaultVaultDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'hue-memory-vault'));
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
}

class _HomeNavigator extends StatefulWidget {
  const _HomeNavigator({
    required this.vault,
    required this.vaultLabel,
    required this.ocrModeLabel,
    required this.sampleCamera,
    required this.filePickCamera,
    required this.ocr,
    required this.ocrSettings,
    required this.pageIds,
    required this.onVaultRootChanged,
    required this.onUseDefaultVault,
    required this.onOcrSettingsChanged,
  });

  final VaultFs vault;
  final String vaultLabel;
  final String ocrModeLabel;
  final CameraCapture sampleCamera;
  final CameraCapture filePickCamera;
  final OcrClient ocr;
  final OcrSettingsStore ocrSettings;
  final PageId pageIds;
  final Future<void> Function(Directory root) onVaultRootChanged;
  final Future<void> Function() onUseDefaultVault;
  final Future<void> Function() onOcrSettingsChanged;

  @override
  State<_HomeNavigator> createState() => _HomeNavigatorState();
}

class _HomeNavigatorState extends State<_HomeNavigator> {
  late CommitPipeline _pipeline = CommitPipeline(vault: widget.vault);

  PendingCapture? _pending;
  bool _busy = false;
  bool _committing = false;
  _SettingsPane? _settingsPane;
  bool _settingsBusy = false;
  String? _lastCommitPath;
  String? _lastProbePath;
  OcrSettings _ocrDraft = const OcrSettings();
  final List<LinkPick> _recentPages = [
    const LinkPick(
      targetPath: 'permanent/seed-attention',
      displayTitle: 'Attention is a muscle (seed)',
    ),
  ];

  @override
  void didUpdateWidget(covariant _HomeNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vault != widget.vault) {
      _pipeline = CommitPipeline(vault: widget.vault);
    }
  }

  Future<void> _openSettings() async {
    final ocr = await widget.ocrSettings.read();
    setState(() {
      _ocrDraft = ocr;
      _settingsPane = _SettingsPane.hub;
    });
  }

  Future<void> _beginCapture(CameraCapture source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final shot = await source.capturePage();
      final meaning = await widget.ocr.extractMeaning(shot.imageBytes);
      final pageId = widget.pageIds.generate(at: shot.capturedAt.toLocal());
      final pending = PendingCapture(
        pageId: pageId,
        imageBytes: shot.imageBytes,
        capturedAt: shot.capturedAt,
        meaning: meaning,
        imageExtension: shot.imageExtension,
      );
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _busy = false;
      });
    } on CaptureCancelled {
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Capture / OCR failed: $e'),
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

      final absolute = widget.vault is LocalVaultFs
          ? p.join((widget.vault as LocalVaultFs).rootPath, primary)
          : primary;

      if (!mounted) return;
      setState(() {
        _pending = null;
        _committing = false;
        _lastCommitPath = absolute;
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

  Future<void> _chooseVaultFolder() async {
    setState(() => _settingsBusy = true);
    try {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose Obsidian vault folder',
      );
      if (path == null) {
        if (!mounted) return;
        setState(() => _settingsBusy = false);
        return;
      }
      await widget.onVaultRootChanged(Directory(path));
      if (!mounted) return;
      setState(() {
        _settingsBusy = false;
        _lastProbePath = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _settingsBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Folder pick failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  Future<void> _writeProbe() async {
    setState(() => _settingsBusy = true);
    try {
      final path = await writeVaultProbe(widget.vault);
      if (!mounted) return;
      setState(() {
        _settingsBusy = false;
        _lastProbePath = path;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _settingsBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Probe failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pane = _settingsPane;
    if (pane != null) {
      switch (pane) {
        case _SettingsPane.hub:
          return SettingsHubShell(
            vaultLabel: widget.vaultLabel,
            ocrModeLabel: widget.ocrModeLabel,
            onBack: () => setState(() => _settingsPane = null),
            onOpenVault: () => setState(() => _settingsPane = _SettingsPane.vault),
            onOpenOcr: () async {
              final ocr = await widget.ocrSettings.read();
              setState(() {
                _ocrDraft = ocr;
                _settingsPane = _SettingsPane.ocr;
              });
            },
          );
        case _SettingsPane.vault:
          return VaultSettingsShell(
            vaultRootLabel: widget.vaultLabel,
            busy: _settingsBusy,
            lastProbePath: _lastProbePath,
            onBack: () => setState(() => _settingsPane = _SettingsPane.hub),
            onChooseFolder: _chooseVaultFolder,
            onWriteTestNote: _writeProbe,
            onUseDefault: () async {
              setState(() => _settingsBusy = true);
              await widget.onUseDefaultVault();
              if (!mounted) return;
              setState(() {
                _settingsBusy = false;
                _lastProbePath = null;
              });
            },
          );
        case _SettingsPane.ocr:
          return OcrSettingsShell(
            initial: _ocrDraft,
            onBack: () => setState(() => _settingsPane = _SettingsPane.hub),
            onSave: (settings) async {
              await widget.ocrSettings.write(settings);
              await widget.onOcrSettingsChanged();
              setState(() => _ocrDraft = settings);
            },
          );
      }
    }

    final pending = _pending;
    if (pending != null) {
      return ConfirmShell(
        capture: pending,
        linkCandidates: List.unmodifiable(_recentPages),
        committing: _committing,
        onCancel: _committing ? null : () => setState(() => _pending = null),
        onCommit: _commit,
      );
    }
    return CaptureShell(
      busy: _busy,
      vaultLabel: '${widget.vaultLabel} · ${widget.ocrModeLabel}',
      lastCommitPath: _lastCommitPath,
      onShutter: () => _beginCapture(widget.sampleCamera),
      onPickImage: () => _beginCapture(widget.filePickCamera),
      onOpenSettings: _openSettings,
    );
  }
}
