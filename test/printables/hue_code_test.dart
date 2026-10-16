import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/printables/hue_code.dart';

void main() {
  test('next returns 2-char friendly codes', () {
    final codes = HueCode(random: Random(42));
    final a = codes.next();
    expect(a.length, 2);
    expect(HueCode.isValid(a), isTrue);
    expect(a.contains(RegExp(r'[01olOL]')), isFalse);
  });

  test('batch mints unique codes', () {
    final codes = HueCode(random: Random(7)).batch(12);
    expect(codes, hasLength(12));
    expect(codes.toSet(), hasLength(12));
    for (final c in codes) {
      expect(HueCode.isValid(c), isTrue);
    }
  });

  test('isValid rejects confusing glyphs', () {
    expect(HueCode.isValid('ka'), isTrue);
    expect(HueCode.isValid('0a'), isFalse);
    expect(HueCode.isValid('ol'), isFalse);
    expect(HueCode.isValid('abc'), isFalse);
  });
}
