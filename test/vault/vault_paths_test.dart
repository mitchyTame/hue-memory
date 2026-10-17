import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/vault/vault_paths.dart';

void main() {
  test('normalizeVaultFolder trims and strips junk prefixes', () {
    expect(normalizeVaultFolder('  fleeting/ '), 'fleeting');
    expect(normalizeVaultFolder('/permanent/'), 'permanent');
    expect(normalizeVaultFolder('hue-memory/fleeting'), 'fleeting');
    expect(normalizeVaultFolder('symbol-journal/journal'), 'journal');
    expect(normalizeVaultFolder('pack/inbox'), 'inbox');
    expect(normalizeVaultFolder('packs/gtd/inbox'), 'gtd/inbox');
    expect(normalizeVaultFolder('gtd/inbox'), 'gtd/inbox');
    expect(normalizeVaultFolder(''), isNull);
    expect(normalizeVaultFolder('   '), isNull);
  });

  test('normalizeVaultFolder rejects parent escapes', () {
    expect(
      () => normalizeVaultFolder('../outside'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('joinVaultRelative builds clean paths', () {
    expect(
      joinVaultRelative('fleeting', '20261016-a.md'),
      'fleeting/20261016-a.md',
    );
    expect(
      joinVaultRelative('hue-memory/mindmaps', 'x.canvas'),
      'mindmaps/x.canvas',
    );
    expect(joinVaultRelative(null, 'root.md'), 'root.md');
  });

  test('assertVaultWriteAllowed blocks json', () {
    expect(
      () => assertVaultWriteAllowed('captures/raw/x.json'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => assertVaultWriteAllowed('mindmaps/a.json.canvas'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => assertVaultWriteAllowed('mindmaps/a.canvas.json'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => assertVaultWriteAllowed('mindmaps/a.canvas'),
      returnsNormally,
    );
    expect(
      () => assertVaultWriteAllowed('fleeting/a.md'),
      returnsNormally,
    );
  });

  test('assertVaultWriteAllowed blocks symbol-journal and pack YAML', () {
    expect(
      () => assertVaultWriteAllowed('symbol-journal/packs/active.yaml'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => assertVaultWriteAllowed('symbol-journal/printables/x.pdf'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => assertVaultWriteAllowed('packs/active.yaml'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => assertVaultWriteAllowed('journal/note.md'),
      returnsNormally,
    );
    expect(
      () => assertVaultWriteAllowed('captures/raw/p.png'),
      returnsNormally,
    );
  });
}
