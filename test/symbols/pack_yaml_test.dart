import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/symbols/default_packs.dart';
import 'package:hue_memory/symbols/pack_catalog.dart';
import 'package:hue_memory/symbols/pack_yaml.dart';
import 'package:hue_memory/symbols/symbol_models.dart';
import 'package:hue_memory/vault/fake_vault_fs.dart';
import 'package:hue_memory/symbols/active_pack_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const yaml = PackYaml();

  test('parses zettelkasten YAML fixture', () {
    const source = '''
id: zettelkasten-ink
library_ref: ink-v1
label: Zettelkasten ink
symbols:
  - id: inbox
    draw: circle-open
    glyphs: ["○", "I"]
    folder: inbox
    output: markdown
  - id: fleeting
    draw: wave
    glyphs: ["∼", "F"]
    folder: fleeting
    output: markdown
  - id: daily-tasks
    draw: dot
    glyphs: ["·"]
    output: daily-note-append
    section: "## Tasks"
''';
    final pack = yaml.parse(source);
    expect(pack.id, 'zettelkasten-ink');
    expect(pack.displayName, 'Zettelkasten ink');
    expect(pack.byId('fleeting')?.folder, 'fleeting');
    expect(pack.byId('daily-tasks')?.output, SymbolOutput.dailyNoteAppend);
  });

  test('encode round-trips Dart fallback pack', () {
    final encoded = yaml.encode(DefaultPacks.zettelkastenInk);
    final parsed = yaml.parse(encoded);
    expect(parsed.id, DefaultPacks.zettelkastenInk.id);
    expect(parsed.symbols.length, DefaultPacks.zettelkastenInk.symbols.length);
    expect(parsed.byId('permanent')?.reviewGate, 'own_words');
    expect(parsed.byId('visual')?.output, SymbolOutput.canvas);
  });

  test('rejects pack without inbox', () {
    expect(
      () => yaml.parse('''
id: bad
symbols:
  - id: only
    draw: wave
    glyphs: ["∼"]
    output: markdown
'''),
      throwsA(isA<FormatException>()),
    );
  });

  test('loads bundled packs from assets', () async {
    final catalog = PackCatalog();
    final packs = await catalog.loadBundled();
    expect(packs.map((p) => p.id), containsAll(['zettelkasten-ink', 'gtd-ink']));
    final gtd = packs.firstWhere((p) => p.id == 'gtd-ink');
    expect(gtd.byId('inbox')?.folder, 'gtd/inbox');
  });

  test('mirrors active pack YAML into vault', () async {
    final vault = FakeVaultFs();
    final store = ActivePackStore();
    await store.mirrorToVault(vault, DefaultPacks.zettelkastenInk);
    final text = await vault.readText(ActivePackStore.vaultMirrorPath);
    expect(text, contains('id: zettelkasten-ink'));
    expect(text, contains('daily-note-append'));
  });
}
