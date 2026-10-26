import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/symbols/active_pack_store.dart';
import 'package:hue_memory/symbols/default_packs.dart';
import 'package:hue_memory/symbols/pack_editor.dart';
import 'package:hue_memory/symbols/pack_yaml.dart';
import 'package:hue_memory/symbols/symbol_models.dart';
import 'package:hue_memory/symbols/symbol_router.dart';
import 'package:hue_memory/vault/fake_vault_fs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const yaml = PackYaml();

  test('slugifyLabel kebab-cases labels', () {
    expect(PackEditor.slugifyLabel('Organising Misc'), 'organising-misc');
    expect(PackEditor.slugifyLabel('  Waiting  '), 'waiting');
  });

  test('mergeExtras appends without replacing defaults', () {
    final base = DefaultPacks.zettelkastenInk;
    final extra = PackEditor.extraFromLibrary(
      drawId: InkDrawIds.plus,
      label: 'project',
      folder: 'Organising/Projects',
    );
    final merged = PackEditor.mergeExtras(base, [extra]);
    expect(merged.id, 'zettelkasten-ink');
    expect(merged.symbols.length, base.symbols.length + 1);
    expect(merged.byId('inbox')?.folder, 'inbox');
    expect(merged.byId('project')?.folder, 'Organising/Projects');
    expect(PackEditor.extrasOf(merged, base).map((s) => s.id), ['project']);
  });

  test('removeSymbol allows defaults and extras; inbox stays', () {
    final base = DefaultPacks.zettelkastenInk;
    final merged = PackEditor.mergeExtras(base, [
      PackEditor.extraFromLibrary(
        drawId: InkDrawIds.asterisk,
        label: 'priority',
        folder: 'Organising/Misc',
      ),
    ]);
    final withoutFleeting =
        PackEditor.removeSymbol(merged, 'fleeting', base: base);
    expect(withoutFleeting.byId('fleeting'), isNull);
    expect(withoutFleeting.byId('priority'), isNotNull);
    expect(PackEditor.removedBaseIds(withoutFleeting, base), ['fleeting']);
    final trimmed =
        PackEditor.removeSymbol(withoutFleeting, 'priority', base: base);
    expect(trimmed.byId('priority'), isNull);
    expect(trimmed.byId('inbox'), isNotNull);
    expect(
      () => PackEditor.removeSymbol(trimmed, 'inbox', base: base),
      throwsA(isA<StateError>()),
    );
  });

  test('router routes extras with nested folder paths', () {
    final base = DefaultPacks.zettelkastenInk;
    final extra = PackEditor.extraFromLibrary(
      drawId: InkDrawIds.squareOpen,
      label: 'event',
      folder: 'Organising/Misc',
    );
    final pack = PackEditor.mergeExtras(base, [extra]);
    final router = SymbolRouter(pack: pack);
    final routed = router.route('□');
    expect(routed.symbol.id, 'event');
    expect(router.noteRelativeDir(routed), 'Organising/Misc');
    // Defaults still route.
    expect(router.route('◇').symbol.id, 'permanent');
  });

  test('extras YAML round-trip', () {
    final extras = [
      PackEditor.extraFromLibrary(
        drawId: InkDrawIds.plus,
        label: 'project',
        folder: 'Organising/Projects',
      ),
      PackEditor.extraFromLibrary(
        drawId: InkDrawIds.halfCircle,
        label: 'waiting',
        folder: 'Organising/Waiting',
      ),
    ];
    final encoded = yaml.encodeExtras(extras);
    final parsed = yaml.parseExtras(encoded);
    expect(parsed.map((s) => s.id), ['project', 'waiting']);
    expect(parsed[0].folder, 'Organising/Projects');
    expect(parsed[1].draw, InkDrawIds.halfCircle);
  });

  test('savePackEdits persists extras and never writes vault packs/', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ActivePackStore(prefs: prefs);
    final vault = FakeVaultFs();

    final base = DefaultPacks.zettelkastenInk;
    final withTwo = PackEditor.mergeExtras(base, [
      PackEditor.extraFromLibrary(
        drawId: InkDrawIds.plus,
        label: 'project',
        folder: 'Organising/Projects',
      ),
      PackEditor.extraFromLibrary(
        drawId: InkDrawIds.chevron,
        label: 'someday',
        folder: 'Organising/Misc',
      ),
    ]);
    await store.savePackEdits(withTwo, vault: vault);

    expect(prefs.getString(ActivePackStore.keyActivePackId), 'zettelkasten-ink');
    expect(
      prefs.getString(ActivePackStore.extrasKeyFor('zettelkasten-ink')),
      isNotNull,
    );
    final active = await store.activePack();
    expect(active.symbols.map((s) => s.id), containsAll(['inbox', 'project', 'someday']));
    expect(await vault.exists('symbol-journal/packs/active.yaml'), isFalse);
    expect(vault.filePaths, isEmpty);

    // Switch away and back — extras survive (folder edit YAML is cleared).
    await store.setActivePack(DefaultPacks.blankCustom, vault: vault);
    expect(await store.readActivePackId(), 'blank-custom');
    await store.setActivePack(base, vault: vault);
    final restored = await store.activePack();
    expect(restored.id, 'zettelkasten-ink');
    expect(restored.byId('project')?.folder, 'Organising/Projects');
    expect(restored.byId('someday')?.folder, 'Organising/Misc');
    expect(restored.symbols.length, base.symbols.length + 2);
  });

  test('two extras on Zettelkasten route like built-ins', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ActivePackStore(prefs: prefs);

    var pack = DefaultPacks.zettelkastenInk;
    pack = PackEditor.addSymbol(
      pack,
      PackEditor.extraFromLibrary(
        drawId: InkDrawIds.plus,
        label: 'project',
        folder: 'Organising/Projects',
      ),
    );
    pack = PackEditor.addSymbol(
      pack,
      PackEditor.extraFromLibrary(
        drawId: InkDrawIds.hook,
        label: 'question',
        folder: 'Organising/Misc',
      ),
    );
    await store.savePackEdits(pack);

    final active = await store.activePack();
    final router = SymbolRouter(pack: active);
    expect(router.route('+').symbol.id, 'project');
    expect(router.noteRelativeDir(router.route('+')), 'Organising/Projects');
    expect(router.route('ʔ').symbol.id, 'question');
    expect(router.noteRelativeDir(router.route('ʔ')), 'Organising/Misc');
    expect(router.route('∼').folder, 'fleeting');
  });

  test('removing a default persists across reload and pack switch', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ActivePackStore(prefs: prefs);
    final vault = FakeVaultFs();

    final base = DefaultPacks.zettelkastenInk;
    final trimmed = PackEditor.removeSymbol(base, 'journal');
    await store.savePackEdits(trimmed, vault: vault);

    expect(
      prefs.getStringList(ActivePackStore.removedKeyFor('zettelkasten-ink')),
      ['journal'],
    );
    expect(await vault.exists('symbol-journal/packs/active.yaml'), isFalse);

    // Fresh store instance to prove prefs round-trip (no in-memory cache).
    final reloaded = ActivePackStore(prefs: prefs);
    final active = await reloaded.activePack();
    expect(active.byId('journal'), isNull);
    expect(active.byId('inbox'), isNotNull);
    expect(SymbolRouter(pack: active).route('J').symbol.id, 'inbox');

    await reloaded.setActivePack(DefaultPacks.blankCustom, vault: vault);
    await reloaded.setActivePack(base, vault: vault);
    final afterSwitch = await reloaded.activePack();
    expect(afterSwitch.byId('journal'), isNull);
    expect(afterSwitch.symbols.length, base.symbols.length - 1);
  });

  test('capture type persists and drives router canvas path', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ActivePackStore(prefs: prefs);
    final vault = FakeVaultFs();

    final base = DefaultPacks.zettelkastenInk;
    final journalVisual = PackEditor.cycleCaptureType(base.byId('journal')!);
    expect(journalVisual.captureType, SymbolCaptureType.visual);
    expect(journalVisual.output, SymbolOutput.canvas);
    final edited = PackEditor.updateSymbol(base, journalVisual);
    await store.savePackEdits(edited, vault: vault);

    final active = await ActivePackStore(prefs: prefs).activePack();
    expect(active.byId('journal')?.captureType, SymbolCaptureType.visual);
    final router = SymbolRouter(pack: active);
    expect(router.isVisualSymbol('journal'), isTrue);
    expect(router.routeById('journal').isCanvas, isTrue);
    expect(await vault.exists('symbol-journal/packs/active.yaml'), isFalse);
  });

  test('restoreRemovedDefaults brings journal back', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ActivePackStore(prefs: prefs);

    final base = DefaultPacks.zettelkastenInk;
    await store.savePackEdits(PackEditor.removeSymbol(base, 'fleeting'));
    expect((await store.activePack()).byId('fleeting'), isNull);

    final restored = await store.restoreRemovedDefaults('zettelkasten-ink');
    expect(restored.byId('fleeting'), isNotNull);
    expect(restored.byId('fleeting')?.folder, 'fleeting');
  });

  test('re-adding removed default from library restores original id', () {
    final base = DefaultPacks.zettelkastenInk;
    final trimmed = PackEditor.removeSymbol(base, 'journal');
    final restored = PackEditor.extraFromLibrary(
      drawId: InkDrawIds.bar,
      label: 'journal',
      folder: 'journal',
      base: base,
    );
    final pack = PackEditor.addSymbol(trimmed, restored);
    expect(pack.byId('journal'), isNotNull);
    expect(PackEditor.removedBaseIds(pack, base), isEmpty);
  });
}
