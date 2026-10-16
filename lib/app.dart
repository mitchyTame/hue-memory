import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'camera/camera_capture.dart';
import 'camera/file_pick_capture.dart';
import 'camera/live_camera_capture.dart';
import 'camera/sample_capture.dart';
import 'capture/last_commit_summary.dart';
import 'capture/page_id.dart';
import 'capture/pending_capture.dart';
import 'ocr/configurable_ocr_client.dart';
import 'ocr/mistral_ocr_client.dart';
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
import 'ui/folder_map_shell.dart';
import 'links/thread_tick.dart';
import 'printables/hue_code.dart';
import 'printables/paper_kit_pdf.dart';
import 'promote/promote_service.dart';
import 'queue/capture_queue.dart';
import 'queue/file_capture_queue.dart';
import 'queue/inbox_only_commit.dart';
import 'ui/library_editor_shell.dart';
import 'ui/ocr_settings_shell.dart';
import 'ui/paper_kit_shell.dart';
import 'ui/promote_shell.dart';
import 'ui/queue_shell.dart';
import 'ui/settings_hub_shell.dart';
import 'ui/symbols_settings_shell.dart';
import 'ui/vault_settings_shell.dart';
import 'vault/commit_pipeline.dart';
import 'vault/daily_note_path.dart';
import 'vault/local_vault_fs.dart';
import 'vault/saf_documents.dart';
import 'vault/saf_vault_fs.dart';
import 'vault/vault_bind.dart';
import 'vault/vault_fs.dart';
import 'writers/link_writer.dart';

enum _SettingsPane { hub, vault, ocr, symbols, folders, paperKit, library }

/// Root app — symbol packs, live camera, durable Obsidian vault folder.
class HueMemoryApp extends StatefulWidget {
  const HueMemoryApp({
    super.key,
    VaultFs? vault,
    CameraCapture? camera,
    OcrClient? ocr,
    PageId? pageIds,
    VaultSettingsStore? settings,
    OcrSettingsStore? ocrSettings,
    ActivePackStore? packStore,
    SymbolPack? initialPack,
    CaptureQueue? captureQueue,
    SafDocuments? safDocuments,
  })  : _vault = vault,
        _camera = camera,
        _ocr = ocr,
        _pageIds = pageIds,
        _settings = settings,
        _ocrSettings = ocrSettings,
        _packStore = packStore,
        _initialPack = initialPack,
        _captureQueue = captureQueue,
        _safDocuments = safDocuments;

  final VaultFs? _vault;
  final CameraCapture? _camera;
  final OcrClient? _ocr;
  final PageId? _pageIds;
  final VaultSettingsStore? _settings;
  final OcrSettingsStore? _ocrSettings;
  final ActivePackStore? _packStore;
  final SymbolPack? _initialPack;
  final CaptureQueue? _captureQueue;
  final SafDocuments? _safDocuments;

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
  late final ActivePackStore _packStore =
      widget._packStore ?? ActivePackStore();
  late final CaptureQueue _captureQueue =
      widget._captureQueue ?? FileCaptureQueue();
  late final SafDocuments _safDocuments =
      widget._safDocuments ?? PluginSafDocuments();

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
      final bound = await resolvePersistedVaultRoot(
        saved: saved,
        documents: _safDocuments,
        fallbackDirectory: defaultVaultDirectory,
      );
      // Only rewrite prefs when the bound root changed (e.g. normalize a
      // document URI → bare tree URI). Never clobber a content:// pick with
      // the app-default path after a flaky grant check.
      final keepSavedSaf = isSafTreeUri(saved) &&
          !isSafTreeUri(bound.persist) &&
          saved != null &&
          saved.isNotEmpty;
      if (!keepSavedSaf && bound.persist != saved) {
        await _vaultSettings.writeVaultRoot(bound.persist);
      }
      try {
        await _packStore.mirrorToVault(bound.vault, _activePack);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _vault = bound.vault;
        _vaultLabel = bound.label;
        _ready = true;
      });
    } catch (_) {
      try {
        final root = await defaultVaultDirectory();
        final bound = bindVaultRoot(
          rootRef: root.path,
          documents: _safDocuments,
        );
        await _vaultSettings.writeVaultRoot(bound.persist);
        if (!mounted) return;
        setState(() {
          _vault = bound.vault;
          _vaultLabel = bound.label;
          _ready = true;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _vaultLabel = 'Vault error — use Settings → Vault to choose a folder';
          _ready = true;
        });
      }
    }
  }

  Future<void> _refreshOcrLabel() async {
    final cfg = await _ocrSettings.read();
    if (!mounted) return;
    setState(() {
      _ocrModeLabel = cfg.shouldUseLive ? 'OCR: Mistral (live)' : 'OCR: mock';
    });
  }

  /// [rootRef] is a filesystem path or a durable `content://` tree URI.
  Future<void> _setVaultRoot(String rootRef) async {
    final bound = bindVaultRoot(
      rootRef: rootRef,
      documents: _safDocuments,
    );
    await verifyVaultWritable(bound.vault);
    await _vaultSettings.writeVaultRoot(bound.persist);
    try {
      await _packStore.mirrorToVault(bound.vault, _activePack);
    } on FileSystemException catch (e) {
      throw VaultBindException(vaultPickFailedMessage(e), cause: e);
    } catch (e) {
      // Mirror is best-effort after a successful write check.
      if (e is VaultBindException) rethrow;
    }
    setState(() {
      _vault = bound.vault;
      _vaultLabel = bound.label;
    });
  }

  Future<void> _selectPack(SymbolPack pack) async {
    final vault = _vault;
    await _packStore.setActivePack(pack, vault: vault);
    setState(() => _activePack = pack);
  }

  Future<void> _saveCustomPack(SymbolPack pack) async {
    final vault = _vault;
    await _packStore.saveCustomPack(pack, vault: vault, activate: true);
    final packs = await _packStore.availablePacks();
    final active = await _packStore.activePack();
    setState(() {
      _availablePacks = packs;
      _activePack = active;
    });
  }

  Future<void> _savePackEdits(SymbolPack pack) async {
    final vault = _vault;
    await _packStore.savePackEdits(pack, vault: vault);
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
              activePack: _activePack,
              availablePacks: _availablePacks,
              captureQueue: _captureQueue,
              safDocuments: _safDocuments,
              onVaultRootChanged: _setVaultRoot,
              onUseDefaultVault: () async {
                final dir = await defaultVaultDirectory();
                await _setVaultRoot(dir.path);
              },
              onOcrSettingsChanged: _refreshOcrLabel,
              onSelectPack: _selectPack,
              onSaveCustomPack: _saveCustomPack,
              onSavePackEdits: _savePackEdits,
            ),
    );
  }
}

DailyNoteSettings dailyNoteSettingsForPack(SymbolPack pack) {
  final daily = pack.byId('daily-tasks');
  return DailyNoteSettings(folder: daily?.folder ?? 'Daily Notes');
}

LastCommitSummary lastCommitSummaryFromResult({
  required CommitResult result,
  required SymbolPack pack,
  required String symbolId,
}) {
  final primary = result.primaryPath;
  final fileName = p.basename(primary);
  final dir = p.dirname(primary);
  final sym = pack.byId(symbolId) ?? pack.byId(result.symbolId);
  final folder = dir == '.' || dir.isEmpty
      ? (sym?.folder ?? 'Daily Notes')
      : dir;
  return LastCommitSummary(
    fileName: fileName,
    folder: folder,
    at: DateTime.now(),
    symbolId: symbolId,
    glyph: sym?.primaryGlyph ?? '?',
  );
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
    required this.activePack,
    required this.availablePacks,
    required this.captureQueue,
    required this.safDocuments,
    required this.onVaultRootChanged,
    required this.onUseDefaultVault,
    required this.onOcrSettingsChanged,
    required this.onSelectPack,
    required this.onSaveCustomPack,
    required this.onSavePackEdits,
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
  final SymbolPack activePack;
  final List<SymbolPack> availablePacks;
  final CaptureQueue captureQueue;
  final SafDocuments safDocuments;
  final Future<void> Function(String rootRef) onVaultRootChanged;
  final Future<void> Function() onUseDefaultVault;
  final Future<void> Function() onOcrSettingsChanged;
  final Future<void> Function(SymbolPack pack) onSelectPack;
  final Future<void> Function(SymbolPack pack) onSaveCustomPack;
  final Future<void> Function(SymbolPack pack) onSavePackEdits;

  @override
  State<_HomeNavigator> createState() => _HomeNavigatorState();
}

class _HomeNavigatorState extends State<_HomeNavigator> {
  late CommitPipeline _pipeline = _buildPipeline(widget.vault, widget.activePack);

  CommitPipeline _buildPipeline(VaultFs vault, SymbolPack pack) {
    return CommitPipeline(
      vault: vault,
      router: SymbolRouter(pack: pack),
      dailyNoteSettings: dailyNoteSettingsForPack(pack),
    );
  }

  PendingCapture? _pending;
  bool _busy = false;
  bool _committing = false;
  _SettingsPane? _settingsPane;
  bool _settingsBusy = false;
  bool _showPromote = false;
  bool _promoteBusy = false;
  bool _showQueue = false;
  bool _queueBusy = false;
  int _queueCount = 0;
  List<QueueJob> _queueJobs = const [];
  List<PromoteCandidate> _promoteCandidates = const [];
  LastCommitSummary? _lastCommit;
  String? _captureStatus;
  bool _mockOcrHintShown = false;
  String? _lastProbePath;
  String? _lastPrintablePath;
  OcrSettings _ocrDraft = const OcrSettings();
  final PaperKitPdf _paperKit = const PaperKitPdf();
  late PromoteService _promote =
      PromoteService.forPack(widget.activePack);
  final List<LinkPick> _recentPages = [
    const LinkPick(
      targetPath: 'permanent/seed-attention',
      displayTitle: 'Attention is a muscle (seed)',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _refreshQueueCount();
  }

  @override
  void didUpdateWidget(covariant _HomeNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vault != widget.vault ||
        oldWidget.activePack != widget.activePack) {
      _pipeline = _buildPipeline(widget.vault, widget.activePack);
      _promote = PromoteService.forPack(widget.activePack);
    }
  }

  Future<void> _refreshQueueCount() async {
    final n = await widget.captureQueue.pendingCount();
    if (!mounted) return;
    setState(() => _queueCount = n);
  }

  Future<void> _openSettings() async {
    final ocr = await widget.ocrSettings.read();
    setState(() {
      _ocrDraft = ocr;
      _settingsPane = _SettingsPane.hub;
    });
  }

  String _ocrFailureMessage(Object error) {
    if (error is MistralOcrException) return error.readable;
    return '$error';
  }

  Future<void> _beginCapture(CameraCapture source) async {
    if (_busy) return;
    final ocrCfg = await widget.ocrSettings.read();
    if (!mounted) return;
    setState(() {
      _busy = true;
      _captureStatus = ocrCfg.shouldUseLive
          ? 'Reading with Mistral…'
          : 'Reading page…';
    });
    if (widget.ocr is ConfigurableOcrClient && !ocrCfg.shouldUseLive) {
      final reason =
          await (widget.ocr as ConfigurableOcrClient).liveBlockedReason();
      if (reason != null && !_mockOcrHintShown && mounted) {
        _mockOcrHintShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reason),
            backgroundColor: MemoryHues.recall,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
    try {
      final shot = await source.capturePage();
      try {
        final meaning = await widget.ocr.extractMeaning(
          shot.imageBytes,
          extensionHint: shot.imageExtension,
        );
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
          _captureStatus = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OCR ready'),
            backgroundColor: MemoryHues.accent,
            duration: Duration(seconds: 2),
          ),
        );
      } catch (ocrError) {
        final reason = _ocrFailureMessage(ocrError);
        final job = await widget.captureQueue.enqueue(
          imageBytes: shot.imageBytes,
          capturedAt: shot.capturedAt,
          imageExtension: shot.imageExtension,
        );
        await widget.captureQueue.markFailed(job.id, reason);
        await _refreshQueueCount();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _captureStatus = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$reason — photo queued'),
            backgroundColor: MemoryHues.recall,
            action: SnackBarAction(
              label: 'Queue',
              textColor: MemoryHues.ink,
              onPressed: _openQueue,
            ),
          ),
        );
      }
    } on CaptureCancelled {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _captureStatus = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _captureStatus = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Capture failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  Future<void> _openQueue() async {
    setState(() => _queueBusy = true);
    try {
      final jobs = await widget.captureQueue.list();
      if (!mounted) return;
      setState(() {
        _queueJobs = jobs;
        _queueCount = jobs.length;
        _showQueue = true;
        _queueBusy = false;
        _settingsPane = null;
        _showPromote = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _queueBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Queue open failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  Future<void> _retryQueuedOcr(QueueJob job) async {
    setState(() => _queueBusy = true);
    try {
      final bytes = await widget.captureQueue.readImage(job.id);
      final meaning = await widget.ocr.extractMeaning(
        bytes,
        extensionHint: job.imageExtension,
      );
      final pageId = widget.pageIds.generate(at: job.capturedAt.toLocal());
      final routed =
          SymbolRouter(pack: widget.activePack).route(meaning.detectedGlyph);
      final pending = PendingCapture(
        pageId: pageId,
        imageBytes: bytes,
        capturedAt: job.capturedAt,
        meaning: meaning,
        imageExtension: job.imageExtension,
        symbolId: routed.symbol.id,
      );
      await widget.captureQueue.markDone(job.id);
      final jobs = await widget.captureQueue.list();
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _showQueue = false;
        _queueJobs = jobs;
        _queueCount = jobs.length;
        _queueBusy = false;
      });
    } catch (e) {
      await widget.captureQueue.markFailed(job.id, '$e');
      final jobs = await widget.captureQueue.list();
      if (!mounted) return;
      setState(() {
        _queueJobs = jobs;
        _queueCount = jobs.length;
        _queueBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Retry OCR failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  Future<void> _inboxOnlyQueued(QueueJob job) async {
    setState(() => _queueBusy = true);
    try {
      final bytes = await widget.captureQueue.readImage(job.id);
      final pageId = widget.pageIds.generate(at: job.capturedAt.toLocal());
      final capture = inboxOnlyCapture(
        pageId: pageId,
        imageBytes: bytes,
        capturedAt: job.capturedAt,
        imageExtension: job.imageExtension,
      );
      final result = await commitInboxOnly(
        pipeline: _pipeline,
        capture: capture,
      );
      await widget.captureQueue.markDone(job.id);
      final jobs = await widget.captureQueue.list();
      if (!mounted) return;
      final summary = lastCommitSummaryFromResult(
        result: result,
        pack: widget.activePack,
        symbolId: result.symbolId,
      );
      setState(() {
        _queueJobs = jobs;
        _queueCount = jobs.length;
        _queueBusy = false;
        _lastCommit = summary;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved ${summary.fileName} in ${summary.folderLabel}',
          ),
          backgroundColor: MemoryHues.accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _queueBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Inbox-only failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  Future<void> _discardQueued(QueueJob job) async {
    setState(() => _queueBusy = true);
    try {
      await widget.captureQueue.remove(job.id);
      final jobs = await widget.captureQueue.list();
      if (!mounted) return;
      setState(() {
        _queueJobs = jobs;
        _queueCount = jobs.length;
        _queueBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _queueBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Discard failed: $e'),
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

      if (result.notePath != null) {
        _recentPages.insert(
          0,
          LinkPick(
            targetPath: result.notePath!,
            displayTitle: title,
          ),
        );
      }

      final summary = lastCommitSummaryFromResult(
        result: result,
        pack: widget.activePack,
        symbolId: symbolId,
      );

      if (!mounted) return;
      setState(() {
        _pending = null;
        _committing = false;
        _lastCommit = summary;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved ${summary.fileName} in ${summary.folderLabel}',
          ),
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
        // Durable tree grant — writable while Obsidian keeps the vault open.
        // Do not use FilePicker.getDirectoryPath (raw /storage/… → errno 13).
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Folder pick cancelled.'),
          ),
        );
        return;
      }
      await widget.onVaultRootChanged(rootRef);
      if (!mounted) return;
      setState(() {
        _settingsBusy = false;
        _lastProbePath = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vault folder ready. Obsidian can stay open.'),
          backgroundColor: MemoryHues.accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _settingsBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(vaultPickFailedMessage(e)),
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
      final path = result.permanentPath;
      final sym = widget.activePack.byId('permanent');
      setState(() {
        _promoteCandidates = list;
        _promoteBusy = false;
        _lastCommit = LastCommitSummary(
          fileName: p.basename(path),
          folder: p.dirname(path),
          at: DateTime.now(),
          symbolId: 'permanent',
          glyph: sym?.primaryGlyph ?? '◇',
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved ${p.basename(path)} in ${p.dirname(path)}',
          ),
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

    if (_showQueue) {
      return QueueShell(
        jobs: _queueJobs,
        busy: _queueBusy,
        onBack: () => setState(() => _showQueue = false),
        onRetryOcr: _retryQueuedOcr,
        onInboxOnly: _inboxOnlyQueued,
        onDiscard: _discardQueued,
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
            onBack: () => setState(() => _settingsPane = _SettingsPane.hub),
            onChooseFolder: _chooseVaultFolder,
            onWriteTestNote: _writeProbe,
            onUseDefault: () async {
              final messenger = ScaffoldMessenger.of(context);
              setState(() => _settingsBusy = true);
              try {
                await widget.onUseDefaultVault();
                if (!mounted) return;
                setState(() {
                  _settingsBusy = false;
                  _lastProbePath = null;
                });
              } catch (e) {
                if (!mounted) return;
                setState(() => _settingsBusy = false);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(vaultPickFailedMessage(e)),
                    backgroundColor: MemoryHues.danger,
                  ),
                );
              }
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
            onVerifyKey: widget.ocr is ConfigurableOcrClient
                ? (widget.ocr as ConfigurableOcrClient).verifyLiveKey
                : (key) => MistralOcrClient(apiKey: key).verifyConnection(),
          );
        case _SettingsPane.symbols:
          return SymbolsSettingsShell(
            packs: widget.availablePacks,
            activePackId: widget.activePack.id,
            busy: _settingsBusy,
            onBack: () => setState(() => _settingsPane = _SettingsPane.hub),
            onOpenLibrary: () =>
                setState(() => _settingsPane = _SettingsPane.library),
            onOpenFolders: () =>
                setState(() => _settingsPane = _SettingsPane.folders),
            onSelect: (pack) async {
              setState(() => _settingsBusy = true);
              await widget.onSelectPack(pack);
              if (!mounted) return;
              setState(() => _settingsBusy = false);
            },
          );
        case _SettingsPane.folders:
          return FolderMapShell(
            pack: widget.activePack,
            busy: _settingsBusy,
            onBack: () => setState(() => _settingsPane = _SettingsPane.symbols),
            onSave: (pack) async {
              setState(() => _settingsBusy = true);
              await widget.onSavePackEdits(pack);
              if (!mounted) return;
              setState(() {
                _settingsBusy = false;
                _settingsPane = _SettingsPane.symbols;
              });
              _pipeline = _buildPipeline(widget.vault, pack);
            },
          );
        case _SettingsPane.library:
          SymbolPack custom = DefaultPacks.blankCustom;
          for (final p in widget.availablePacks) {
            if (p.id == 'blank-custom') {
              custom = p;
              break;
            }
          }
          return LibraryEditorShell(
            pack: custom,
            busy: _settingsBusy,
            onBack: () => setState(() => _settingsPane = _SettingsPane.symbols),
            onSave: (pack) async {
              final messenger = ScaffoldMessenger.of(context);
              setState(() => _settingsBusy = true);
              await widget.onSaveCustomPack(pack);
              if (!mounted) return;
              setState(() {
                _settingsBusy = false;
                _settingsPane = _SettingsPane.symbols;
              });
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Custom pack saved'),
                  backgroundColor: MemoryHues.accent,
                ),
              );
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
      busy: _busy || _promoteBusy || _queueBusy,
      vaultLabel:
          '${widget.vaultLabel} · ${widget.ocrModeLabel} · ${widget.activePack.displayName}',
      shutterHint: widget.shutterHint,
      lastCommit: _lastCommit,
      statusMessage: _captureStatus,
      queueCount: _queueCount,
      onShutter: () => _beginCapture(widget.shutterCamera),
      onPickImage: () => _beginCapture(widget.filePickCamera),
      onOpenSettings: _openSettings,
      onOpenPromote: _openPromote,
      onOpenQueue: _openQueue,
    );
  }
}
