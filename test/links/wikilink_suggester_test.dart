import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/links/wikilink_suggester.dart';
import 'package:hue_memory/vault/fake_vault_fs.dart';
import 'package:hue_memory/writers/link_writer.dart';

void main() {
  const suggester = WikilinkSuggester();

  test('indexes vault notes and suggests by shared tokens', () async {
    final vault = FakeVaultFs();
    vault.ensureDirSync('permanent');
    vault.ensureDirSync('fleeting');
    await vault.writeText(
      'permanent/working-memory-capacity.md',
      '''
---
type: permanent
---

# Working Memory Capacity

Chunking helps hold more items in mind.
''',
    );
    await vault.writeText(
      'fleeting/unrelated-note.md',
      '''
# Grocery list

Milk and eggs.
''',
    );

    final index = await suggester.indexVault(
      vault,
      folders: const ['permanent', 'fleeting'],
    );
    expect(index, hasLength(2));

    final picks = suggester.suggest(
      haystack: 'Today I practiced Chunking on paper.',
      index: index,
    );
    expect(picks, isNotEmpty);
    expect(
      picks.any((p) => p.targetPath.contains('working-memory-capacity')),
      isTrue,
    );
    expect(
      picks.any((p) => p.targetPath.contains('unrelated')),
      isFalse,
    );
  });

  test('insertIntoBody weaves or appends Related wikilinks', () {
    final woven = suggester.insertIntoBody(
      'Practice chunking slowly.',
      const [
        LinkPick(
          targetPath: 'permanent/working-memory-capacity',
          displayTitle: 'Working Memory Capacity',
        ),
      ],
    );
    // "chunking" is not a title token (≥5 from title), so Related footer.
    expect(woven, contains('[[Working Memory Capacity]]'));

    final withTitleWord = suggester.insertIntoBody(
      'Memory training today.',
      const [
        LinkPick(
          targetPath: 'permanent/working-memory-capacity',
          displayTitle: 'Working Memory Capacity',
        ),
      ],
    );
    expect(withTitleWord, contains('Memory [[Working Memory Capacity]]'));
  });

  test('suggest preserves existing picks', () {
    const existing = LinkPick(
      targetPath: 'fleeting/prior',
      displayTitle: 'Prior',
    );
    final picks = suggester.suggest(
      haystack: 'nothing matching',
      index: const [
        VaultNoteRef(path: 'permanent/other', title: 'Other'),
      ],
      existing: const [existing],
    );
    expect(picks, [existing]);
  });
}
