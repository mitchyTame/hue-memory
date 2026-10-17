import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/symbols/default_packs.dart';
import 'package:hue_memory/symbols/ink_library.dart';
import 'package:hue_memory/symbols/pack_editor.dart';

void main() {
  test('ink library includes journal bar (J)', () {
    expect(InkLibrary.glyphs, hasLength(19));
    expect(InkDrawIds.all, hasLength(19));
    expect(InkDrawIds.all.toSet(), hasLength(19));
    expect(InkDrawIds.all, contains(InkDrawIds.bar));
    expect(InkLibrary.byId(InkDrawIds.bar)?.unicode, 'J');
    expect(
      InkLibrary.suggestedSymbol(InkDrawIds.bar).folder,
      'journal',
    );
  });

  test('pack editor adds and refuses duplicate draw / inbox remove', () {
    var pack = DefaultPacks.blankCustom;
    pack = PackEditor.addSymbol(
      pack,
      InkLibrary.suggestedSymbol(InkDrawIds.wave),
    );
    expect(pack.symbols, hasLength(2));
    expect(
      () => PackEditor.addSymbol(
        pack,
        InkLibrary.suggestedSymbol(InkDrawIds.wave),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => PackEditor.removeSymbol(pack, 'inbox'),
      throwsA(isA<StateError>()),
    );
    pack = PackEditor.removeSymbol(pack, 'fleeting');
    expect(pack.symbols, hasLength(1));
  });

  test('size guide soft-warns above 9', () {
    expect(PackSizeGuide.sizeMessage(6), isNull);
    expect(PackSizeGuide.sizeMessage(10), contains('crowded'));
    expect(PackSizeGuide.sizeMessage(13), contains('Hard'));
  });
}
