import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/promote/own_words_gate.dart';

void main() {
  test('rejects empty rewrite', () {
    expect(
      OwnWordsGate.validate(ownWords: '  ', sourceBody: 'Attention is a muscle'),
      isNotNull,
    );
  });

  test('rejects verbatim copy of source', () {
    const body = 'Attention is a muscle';
    expect(
      OwnWordsGate.validate(ownWords: body, sourceBody: body),
      contains('own words'),
    );
  });

  test('accepts a real rewrite', () {
    expect(
      OwnWordsGate.validate(
        ownWords: 'Focus grows when you train it on paper first.',
        sourceBody: 'Attention is a muscle',
      ),
      isNull,
    );
  });

  test('keepOcrShallow bypasses rewrite', () {
    expect(
      OwnWordsGate.validate(
        ownWords: '',
        sourceBody: 'Attention is a muscle',
        keepOcrShallow: true,
      ),
      isNull,
    );
  });
}
