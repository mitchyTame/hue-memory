import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/symbols/active_pack_store.dart';
import 'package:hue_memory/symbols/default_packs.dart';
import 'package:hue_memory/symbols/ink_library.dart';
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

  test('removeSymbol refuses default symbols when base is set', () {
    final base = DefaultPacks.zettelkastenInk;
    final merged = PackEditor.mergeExtras(base, [
      PackEditor.extraFromLibrary(
        drawId: InkDrawIds.asterisk,
        label: 'priority',
        folder: 'Organising/Misc',
      ),
    ]);
    expect(
      () => PackEditor.removeSymbol(merged, 'fleeting', base: base),
      throwsA(isA<StateError>()),
    );
    final trimmed = PackEditor.removeSymbol(merged, 'priority', base: base);
    expect(trimmed.byId('priority'), isNull);
    expect(trimmed.symbols.length, base.symbols.length);
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
}
