import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/symbols/default_packs.dart';
import 'package:hue_memory/symbols/symbol_models.dart';
import 'package:hue_memory/symbols/symbol_router.dart';

void main() {
  late SymbolRouter router;

  setUp(() {
    router = SymbolRouter(pack: DefaultPacks.zettelkastenInk);
  });

  test('routes ZK ink glyphs to folders and outputs', () {
    final cases = <String, (String, SymbolOutput, String?)>{
      '○': ('inbox', SymbolOutput.markdown, 'inbox'),
      '∼': ('fleeting', SymbolOutput.markdown, 'fleeting'),
      '≡': ('literature', SymbolOutput.markdown, 'literature'),
      '◇': ('permanent', SymbolOutput.markdown, 'permanent'),
      '△': ('visual', SymbolOutput.canvas, 'mindmaps'),
      'J': ('journal', SymbolOutput.markdown, 'journal'),
      '·': ('daily-tasks', SymbolOutput.dailyNoteAppend, 'Organising/Daily'),
    };

    for (final entry in cases.entries) {
      final result = router.route(entry.key);
      expect(result.symbol.id, entry.value.$1, reason: 'glyph ${entry.key}');
      expect(result.output, entry.value.$2, reason: 'glyph ${entry.key}');
      expect(result.folder, entry.value.$3, reason: 'glyph ${entry.key}');
    }
  });

  test('letter aliases map to the same symbols', () {
    expect(router.route('F').symbol.id, 'fleeting');
    expect(router.route('P').symbol.id, 'permanent');
    expect(router.route('V').output, SymbolOutput.canvas);
  });

  test('unknown glyph falls back to inbox', () {
    final result = router.route('‽');
    expect(result.symbol.id, 'inbox');
    expect(result.folder, 'inbox');
  });

  test('routeById selects daily-tasks section', () {
    final result = router.routeById('daily-tasks');
    expect(result.isDailyTasks, isTrue);
    expect(result.section, '## Tasks');
  });

  test('noteRelativeDir returns folder for markdown routes', () {
    final result = router.route('◇');
    expect(router.noteRelativeDir(result), 'permanent');
  });

  test('noteRelativeDir throws for daily tasks', () {
    final result = router.route('·');
    expect(() => router.noteRelativeDir(result), throwsArgumentError);
  });

  test('permanent has own_words review gate', () {
    expect(router.route('◇').symbol.reviewGate, 'own_words');
  });
}
