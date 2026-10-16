import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'camera/camera_capture.dart';
import 'camera/file_pick_capture.dart';
import 'camera/live_camera_capture.dart';
import 'camera/sample_capture.dart';
import 'capture/page_id.dart';
import 'capture/pending_capture.dart';
import 'ocr/configurable_ocr_client.dart';
import 'ocr/ocr_client.dart';
import 'ocr/ocr_settings.dart';
import 'settings/vault_settings_store.dart';
import 'symbols/active_pack_store.dart';
import 'symbols/default_packs.dart';
import 'symbols/symbol_models.dart';
import 'symbols/symbol_router.dart';
import 'theme/app_theme.dart';
import 'theme/memory_hues.dart';
import 'ui/capture_shell.dart';
import 'ui/confirm_shell.dart';
import 'links/thread_tick.dart';
import 'printables/hue_code.dart';
import 'printables/paper_kit_pdf.dart';
import 'promote/promote_service.dart';
import 'ui/ocr_settings_shell.dart';
import 'ui/paper_kit_shell.dart';
import 'ui/promote_shell.dart';
import 'ui/settings_hub_shell.dart';
import 'ui/symbols_settings_shell.dart';
import 'ui/vault_settings_shell.dart';
import 'vault/commit_pipeline.dart';
import 'vault/local_vault_fs.dart';
import 'vault/saf_documents.dart';
import 'vault/saf_vault_fs.dart';
import 'vault/vault_fs.dart';
import 'writers/link_writer.dart';

enum _SettingsPane { hub, vault, ocr, symbols, paperKit }

/// Root app. Slice 7: YAML symbol packs + live camera + SAF / Local vault.
class HueMemoryApp extends StatefulWidget {
  const HueMemoryApp({
    super.key,
    VaultFs? vault,
    CameraCapture? camera,
    OcrClient? ocr,
    PageId? pageIds,
    VaultSettingsStore? settings,
    OcrSettingsStore? ocrSettings,
    SafDocuments? safDocuments,
    ActivePackStore? packStore,
    SymbolPack? initialPack,
  })  : _vault = vault,
        _camera = camera,
        _ocr = ocr,
        _pageIds = pageIds,
        _settings = settings,
        _ocrSettings = ocrSettings,
        _safDocuments = safDocuments,
        _packStore = packStore,
        _initialPack = initialPack;

  final VaultFs? _vault;
  final CameraCapture? _camera;
  final OcrClient? _ocr;
  final PageId? _pageIds;
  final VaultSettingsStore? _settings;
  final OcrSettingsStore? _ocrSettings;
  final SafDocuments? _safDocuments;
  final ActivePackStore? _packStore;
  final SymbolPack? _initialPack;

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
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  late final CameraCapture _shutterCamera = widget._camera ??
      (Platform.isAndroid
          ? LiveCameraCapture(navigatorKey: _navKey)
          : SampleAssetCapture());
  late final FilePickCapture _filePickCamera = const FilePickCapture();
  late final OcrClient _ocr = widget._ocr ??
      ConfigurableOcrClient(settings: _ocrSettings);
  late final PageId _pageIds = widget._pageIds ?? PageId();
  late final SafDocuments _safDocuments =
      widget._safDocuments ?? PluginSafDocuments();
  late final ActivePackStore _packStore =
      widget._packStore ?? ActivePackStore();

  VaultFs? _vault;
  String _vaultLabel = 'Loading vault…';
  String _ocrModeLabel = 'OCR: mock';
  SymbolPack _activePack = DefaultPacks.zettelkastenInk;
  List<SymbolPack> _availablePacks = const [DefaultPacks.zettelkastenInk];
  bool _ready = false;

  String get _shutterHint => Platform.isAndroid && widget._camera == null
      ? 'Shutter = live camera\nGallery = pick a photo'
      : 'Shutter = sample page\nGallery = pick a photo';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  String _labelFor(VaultFs vault) {
    if (vault is LocalVaultFs) return vault.rootPath;
    if (vault is SafVaultFs) return safVaultLabel(vault.treeUri);
    return 'Injected vault';
  }

  Future<void> _bootstrap() async {
    await _refreshOcrLabel();
    try {
      _availablePacks = await _packStore.availablePacks();
      _activePack = widget._initialPack ?? await _packStore.activePack();
    } catch (_) {
      _activePack = DefaultPacks.zettelkastenInk;
      _availablePacks = const [DefaultPacks.zettelkastenInk];
    }

    if (widget._vault != null) {
      try {
        await _packStore.mirrorToVault(widget._vault!, _activePack);
      } catch (_) {}
      setState(() {
        _vault = widget._vault;
        _vaultLabel = _labelFor(widget._vault!);
        _ready = true;
      });
      return;
    }

    try {
      final saved = await _vaultSettings.readVaultRoot();
      VaultFs vault;
      String label;
      String persist;

      if (isSafTreeUri(saved)) {
        final grants = await _safDocuments.persistedPermissions();
        final ok = grants.any((g) => g.uri == saved && g.write);
        if (ok) {
          vault = SafVaultFs(treeUri: saved!, documents: _safDocuments);
          label = safVaultLabel(saved);
          persist = saved;
        } else {
          final root = await defaultVaultDirectory();
          vault = LocalVaultFs(root);
          label = root.path;
          persist = root.path;
        }
      } else if (saved != null &&
          saved.isNotEmpty &&
          Directory(saved).existsSync()) {
        final root = Directory(saved);
        vault = LocalVaultFs(root);
        label = root.path;
        persist = root.path;
      } else {
        final root = await defaultVaultDirectory();
        vault = LocalVaultFs(root);
        label = root.path;
        persist = root.path;
      }

      await _vaultSettings.writeVaultRoot(persist);
      await _packStore.mirrorToVault(vault, _activePack);
      if (!mounted) return;
      setState(() {
        _vault = vault;
        _vaultLabel = label;
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

  /// [rootRef] is a filesystem path or a SAF `content://` tree URI.
  Future<void> _setVaultRoot(String rootRef) async {
    if (isSafTreeUri(rootRef)) {
      final vault = SafVaultFs(treeUri: rootRef, documents: _safDocuments);
      await _vaultSettings.writeVaultRoot(rootRef);
      await _packStore.mirrorToVault(vault, _activePack);
      setState(() {
        _vault = vault;
        _vaultLabel = safVaultLabel(rootRef);
      });
      return;
    }
    final vault = LocalVaultFs(Directory(rootRef));
    await _vaultSettings.writeVaultRoot(rootRef);
    await _packStore.mirrorToVault(vault, _activePack);
    setState(() {
      _vault = vault;
      _vaultLabel = vault.rootPath;
    });
  }

  Future<void> _selectPack(SymbolPack pack) async {
    final vault = _vault;
    await _packStore.setActivePack(pack, vault: vault);
    setState(() => _activePack = pack);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'hue-memory',
      navigatorKey: _navKey,
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
              shutterHint: _shutterHint,
              shutterCamera: _shutterCamera,
              filePickCamera: _filePickCamera,
              ocr: _ocr,
              ocrSettings: _ocrSettings,
              pageIds: _pageIds,
              safDocuments: _safDocuments,
              activePack: _activePack,
              availablePacks: _availablePacks,
              onVaultRootChanged: _setVaultRoot,
              onUseDefaultVault: () async {
                final dir = await defaultVaultDirectory();
                await _setVaultRoot(dir.path);
              },
              onOcrSettingsChanged: _refreshOcrLabel,
              onSelectPack: _selectPack,
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
    required this.shutterHint,
    required this.shutterCamera,
    required this.filePickCamera,
    required this.ocr,
    required this.ocrSettings,
    required this.pageIds,
    required this.safDocuments,
    required this.activePack,
    required this.availablePacks,
    required this.onVaultRootChanged,
    required this.onUseDefaultVault,
    required this.onOcrSettingsChanged,
    required this.onSelectPack,
  });

  final VaultFs vault;
  final String vaultLabel;
  final String ocrModeLabel;
  final String shutterHint;
  final CameraCapture shutterCamera;
  final CameraCapture filePickCamera;
  final OcrClient ocr;
  final OcrSettingsStore ocrSettings;
  final PageId pageIds;
  final SafDocuments safDocuments;
  final SymbolPack activePack;
  final List<SymbolPack> availablePacks;
  final Future<void> Function(String rootRef) onVaultRootChanged;
  final Future<void> Function() onUseDefaultVault;
  final Future<void> Function() onOcrSettingsChanged;
  final Future<void> Function(SymbolPack pack) onSelectPack;

  @override
  State<_HomeNavigator> createState() => _HomeNavigatorState();
}

class _HomeNavigatorState extends State<_HomeNavigator> {
  late CommitPipeline _pipeline = CommitPipeline(
    vault: widget.vault,
    router: SymbolRouter(pack: widget.activePack),
  );

  PendingCapture? _pending;
  bool _busy = false;
  bool _committing = false;
  _SettingsPane? _settingsPane;
  bool _settingsBusy = false;
  bool _showPromote = false;
  bool _promoteBusy = false;
  List<PromoteCandidate> _promoteCandidates = const [];
  String? _lastCommitPath;
  String? _lastProbePath;
  String? _lastPrintablePath;
  OcrSettings _ocrDraft = const OcrSettings();
  final PaperKitPdf _paperKit = const PaperKitPdf();
  final PromoteService _promote = PromoteService();
  final List<LinkPick> _recentPages = [
    const LinkPick(
      targetPath: 'permanent/seed-attention',
      displayTitle: 'Attention is a muscle (seed)',
    ),
  ];

  @override
  void didUpdateWidget(covariant _HomeNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vault != widget.vault ||
        oldWidget.activePack.id != widget.activePack.id) {
      _pipeline = CommitPipeline(
        vault: widget.vault,
        router: SymbolRouter(pack: widget.activePack),
      );
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
      final routed = SymbolRouter(pack: widget.activePack)
          .route(meaning.detectedGlyph);
      final seededLinks = meaning.threadTick
          ? ThreadTick.mergePrevious(
              previous: _recentPages.isEmpty ? null : _recentPages.first,
            )
          : const <LinkPick>[];
      final pending = PendingCapture(
        pageId: pageId,
        imageBytes: shot.imageBytes,
        capturedAt: shot.capturedAt,
        meaning: meaning,
        imageExtension: shot.imageExtension,
        symbolId: routed.symbol.id,
        links: seededLinks,
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
    bool inkGhost = true,
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
          inkGhost: inkGhost,
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

      final absolute = switch (widget.vault) {
        final LocalVaultFs local => p.join(local.rootPath, primary),
        final SafVaultFs saf => '${saf.treeUri} → $primary',
        _ => primary,
      };

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
      final String? rootRef;
      if (Platform.isAndroid) {
        final picked = await widget.safDocuments.pickDirectory(
          writePermission: true,
          persistablePermission: true,
        );
        rootRef = picked?.uri;
      } else {
        rootRef = await FilePicker.getDirectoryPath(
          dialogTitle: 'Choose Obsidian vault folder',
        );
      }
      if (rootRef == null) {
        if (!mounted) return;
        setState(() => _settingsBusy = false);
        return;
      }
      await widget.onVaultRootChanged(rootRef);
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

  Future<void> _openPromote() async {
    setState(() => _promoteBusy = true);
    try {
      final list = await _promote.listFleeting(widget.vault);
      if (!mounted) return;
      setState(() {
        _promoteCandidates = list;
        _showPromote = true;
        _promoteBusy = false;
        _settingsPane = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _promoteBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Promote list failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  Future<void> _runPromote({
    required PromoteCandidate source,
    required String title,
    required String ownWords,
    required bool keepOcrShallow,
  }) async {
    setState(() => _promoteBusy = true);
    try {
      final result = await _promote.promote(
        vault: widget.vault,
        source: source,
        title: title,
        ownWords: ownWords,
        keepOcrShallow: keepOcrShallow,
      );
      _recentPages.insert(
        0,
        LinkPick(
          targetPath: result.permanentPath,
          displayTitle: title,
        ),
      );
      final list = await _promote.listFleeting(widget.vault);
      if (!mounted) return;
      setState(() {
        _promoteCandidates = list;
        _promoteBusy = false;
        _lastCommitPath = result.permanentPath;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Promoted → ${result.permanentPath}'),
          backgroundColor: MemoryHues.recall,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _promoteBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  Future<void> _writeLegendPdf() async {
    setState(() => _settingsBusy = true);
    try {
      final bytes = await _paperKit.buildLegend(pack: widget.activePack);
      final stamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('-', '')
          .substring(0, 15);
      final path =
          'symbol-journal/printables/$stamp-legend-${widget.activePack.id}.pdf';
      await widget.vault.writeBytes(path, bytes);
      if (!mounted) return;
      setState(() {
        _settingsBusy = false;
        _lastPrintablePath = path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wrote $path'),
          backgroundColor: MemoryHues.accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _settingsBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Legend PDF failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  Future<void> _writeHueDotPdf() async {
    setState(() => _settingsBusy = true);
    try {
      final codes = HueCode().batch(12);
      final bytes = await _paperKit.buildHueDotSheet(codes: codes);
      final stamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('-', '')
          .substring(0, 15);
      final path = 'symbol-journal/printables/$stamp-hue-dots.pdf';
      await widget.vault.writeBytes(path, bytes);
      if (!mounted) return;
      setState(() {
        _settingsBusy = false;
        _lastPrintablePath = path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wrote $path'),
          backgroundColor: MemoryHues.accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _settingsBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hue-dot PDF failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showPromote) {
      return PromoteShell(
        candidates: _promoteCandidates,
        busy: _promoteBusy,
        onBack: () => setState(() => _showPromote = false),
        onPromote: _runPromote,
      );
    }

    final pane = _settingsPane;
    if (pane != null) {
      switch (pane) {
        case _SettingsPane.hub:
          return SettingsHubShell(
            vaultLabel: widget.vaultLabel,
            ocrModeLabel: widget.ocrModeLabel,
            packLabel: widget.activePack.displayName,
            onBack: () => setState(() => _settingsPane = null),
            onOpenVault: () =>
                setState(() => _settingsPane = _SettingsPane.vault),
            onOpenOcr: () async {
              final ocr = await widget.ocrSettings.read();
              setState(() {
                _ocrDraft = ocr;
                _settingsPane = _SettingsPane.ocr;
              });
            },
            onOpenSymbols: () =>
                setState(() => _settingsPane = _SettingsPane.symbols),
            onOpenPaperKit: () =>
                setState(() => _settingsPane = _SettingsPane.paperKit),
            onOpenPromote: () {
              setState(() => _settingsPane = null);
              _openPromote();
            },
          );
        case _SettingsPane.vault:
          return VaultSettingsShell(
            vaultRootLabel: widget.vaultLabel,
            busy: _settingsBusy,
            lastProbePath: _lastProbePath,
            androidSafHint: Platform.isAndroid,
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
        case _SettingsPane.symbols:
          return SymbolsSettingsShell(
            packs: widget.availablePacks,
            activePackId: widget.activePack.id,
            busy: _settingsBusy,
            onBack: () => setState(() => _settingsPane = _SettingsPane.hub),
            onSelect: (pack) async {
              setState(() => _settingsBusy = true);
              await widget.onSelectPack(pack);
              if (!mounted) return;
              setState(() => _settingsBusy = false);
            },
          );
        case _SettingsPane.paperKit:
          return PaperKitShell(
            packLabel: widget.activePack.displayName,
            busy: _settingsBusy,
            lastWritePath: _lastPrintablePath,
            onBack: () => setState(() => _settingsPane = _SettingsPane.hub),
            onWriteLegend: _writeLegendPdf,
            onWriteHueDots: _writeHueDotPdf,
          );
      }
    }

    final pending = _pending;
    if (pending != null) {
      return ConfirmShell(
        capture: pending,
        pack: widget.activePack,
        linkCandidates: List.unmodifiable(_recentPages),
        committing: _committing,
        onCancel: _committing ? null : () => setState(() => _pending = null),
        onCommit: _commit,
      );
    }
    return CaptureShell(
      busy: _busy || _promoteBusy,
      vaultLabel:
          '${widget.vaultLabel} · ${widget.ocrModeLabel} · ${widget.activePack.displayName}',
      shutterHint: widget.shutterHint,
      lastCommitPath: _lastCommitPath,
      onShutter: () => _beginCapture(widget.shutterCamera),
      onPickImage: () => _beginCapture(widget.filePickCamera),
      onOpenSettings: _openSettings,
      onOpenPromote: _openPromote,
    );
  }
}
