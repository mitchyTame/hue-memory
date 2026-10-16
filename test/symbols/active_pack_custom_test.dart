import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/symbols/active_pack_store.dart';
import 'package:hue_memory/symbols/default_packs.dart';
import 'package:hue_memory/symbols/ink_library.dart';
import 'package:hue_memory/symbols/pack_editor.dart';
import 'package:hue_memory/vault/fake_vault_fs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saveCustomPack persists YAML and activates', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ActivePackStore(prefs: prefs);
    final vault = FakeVaultFs();

    var pack = DefaultPacks.blankCustom;
    pack = PackEditor.addSymbol(
      pack,
      InkLibrary.suggestedSymbol(InkDrawIds.diamond),
    );
    await store.saveCustomPack(pack, vault: vault);

    expect(prefs.getString(ActivePackStore.keyCustomPackYaml), isNotNull);
    expect(await store.readActivePackId(), 'blank-custom');
    final active = await store.activePack();
    expect(active.symbols.map((s) => s.id), containsAll(['inbox', 'permanent']));
    // Pack YAML is prefs-only — never land packs/ YAML in the Obsidian vault.
    expect(await vault.exists('symbol-journal/packs/custom.yaml'), isFalse);
    expect(vault.filePaths, isEmpty);

    final available = await store.availablePacks();
    expect(available.any((p) => p.id == 'blank-custom'), isTrue);
  });
}
