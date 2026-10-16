import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/promote/promote_service.dart';
import 'package:hue_memory/symbols/default_packs.dart';
import 'package:hue_memory/symbols/pack_editor.dart';
import 'package:hue_memory/vault/fake_vault_fs.dart';

void main() {
  late FakeVaultFs vault;
  late PromoteService service;

  setUp(() {
    vault = FakeVaultFs();
    service = PromoteService();
  });

  test('lists fleeting notes and skips already promoted', () async {
    await vault.writeText(
      'fleeting/20261016-p7k2-attention.md',
      '''
---
type: fleeting
symbol: fleeting
glyph: ∼
page_id: 20261016-p7k2
captured_at: 2026-10-16T12:00:00.000Z
source_image: captures/raw/20261016-p7k2.png
status: confirmed
links: []
---

![[captures/raw/20261016-p7k2.png]]

## Note

Attention is a muscle
''',
    );
    await vault.writeText(
      'fleeting/20261015-aaaa-done.md',
      '''
---
type: fleeting
page_id: 20261015-aaaa
status: promoted
---

## Note

Already done
''',
    );

    final list = await service.listFleeting(vault);
    expect(list, hasLength(1));
    expect(list.first.pageId, '20261016-p7k2');
    expect(list.first.body, contains('Attention is a muscle'));
  });

  test('promote writes permanent and stamps fleeting', () async {
    const path = 'fleeting/20261016-p7k2-attention.md';
    await vault.writeText(
      path,
      '''
---
type: fleeting
symbol: fleeting
glyph: ∼
page_id: 20261016-p7k2
captured_at: 2026-10-16T12:00:00.000Z
source_image: captures/raw/20261016-p7k2.png
status: confirmed
links: []
---

## Note

Attention is a muscle
''',
    );

    final candidates = await service.listFleeting(vault);
    final result = await service.promote(
      vault: vault,
      source: candidates.first,
      title: 'Attention as practice',
      ownWords: 'Focus grows when trained on paper before screens.',
    );

    expect(result.permanentPath, startsWith('permanent/'));
    final permanent = await vault.readText(result.permanentPath);
    expect(permanent, contains('type: permanent'));
    expect(permanent, contains('status: promoted'));
    expect(permanent, contains('Focus grows when trained'));
    expect(permanent, contains('[[fleeting/20261016-p7k2-attention]]'));

    final fleeting = await vault.readText(path);
    expect(fleeting, contains('status: promoted'));
    expect(fleeting, contains('promoted_to:'));

    final again = await service.listFleeting(vault);
    expect(again, isEmpty);
  });

  test('promote refuses verbatim own-words', () async {
    await vault.writeText(
      'fleeting/20261016-p7k2-attention.md',
      '''
---
type: fleeting
page_id: 20261016-p7k2
status: confirmed
---

## Note

Attention is a muscle
''',
    );
    final c = (await service.listFleeting(vault)).first;
    expect(
      () => service.promote(
        vault: vault,
        source: c,
        title: 'Same',
        ownWords: 'Attention is a muscle',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('forPack uses custom fleeting/permanent folders', () async {
    var pack = DefaultPacks.zettelkastenInk;
    pack = PackEditor.updateSymbol(
      pack,
      pack.byId('fleeting')!.copyWith(folder: 'inbox-waves'),
    );
    pack = PackEditor.updateSymbol(
      pack,
      pack.byId('permanent')!.copyWith(folder: 'evergreen'),
    );
    final custom = PromoteService.forPack(pack);
    expect(custom.fleetingFolder, 'inbox-waves');
    expect(custom.permanentFolder, 'evergreen');

    await vault.writeText(
      'inbox-waves/20261016-p7k2-attention.md',
      '''
---
type: fleeting
page_id: 20261016-p7k2
status: confirmed
---

## Note

Custom folder fleeting
''',
    );

    final list = await custom.listFleeting(vault);
    expect(list, hasLength(1));
    final result = await custom.promote(
      vault: vault,
      source: list.first,
      title: 'Evergreen note',
      ownWords: 'Rewritten in my own words for the evergreen shelf.',
    );
    expect(result.permanentPath, startsWith('evergreen/'));
    expect(await vault.exists(result.permanentPath), isTrue);
  });
}
